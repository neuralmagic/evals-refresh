#!/usr/bin/env python3
"""Queue tooling for the redhatai-queue-refresh and redhatai-queue-eval skills.

The queue is the private HF collection "<org>/Eval Queue". This script implements
everything both skills need:

  eval_queue.py count <model_id> [--debug]   Count the evaluations on one model card.
  eval_queue.py scan [--author RedHatAI] [--out scan.json] [--full]
                                            Re-derive the queue: every quantized chat model
                                            in the org whose card carries <= MAX_EVALS
                                            evaluations. Incremental by default: the last
                                            refresh date is read from the collection's
                                            description ("Last refresh: YYYY-MM-DD") and only
                                            models created since then (createdAt) or changed
                                            since then (lastModified) are examined; existing
                                            members whose repos did not change are kept
                                            without re-fetching. --full examines everything
                                            (first run, after changing the counting rules,
                                            or when drift is suspected).
  eval_queue.py collection list              Print the collection's items (needs HF_TOKEN).
  eval_queue.py collection sync <scan.json> [--apply]
                                            Add queued models to / remove stale models from
                                            the collection, then stamp the scan's date into
                                            the collection description as the new "Last
                                            refresh" marker. Incremental scans only remove
                                            the members they re-checked and found stale;
                                            full scans make the collection exactly the scan
                                            queue. Dry run unless --apply (needs HF_TOKEN).
  eval_queue.py collection add <model_id> [--note ...]
  eval_queue.py collection remove <model_id>

The date is stamped only by an applied sync, so a scan that is never applied does not
advance the watermark. The incremental comparison uses a one-day lookback (the date is
local, HF timestamps are UTC); over-inclusion is harmless, a missed model is not.

Counting rules (the "evaluations attached to a card" number):

  * Distinct benchmark labels in *scored* table rows — markdown or HTML — that live under an
    evaluation-flavored heading. The heading STACK matters: a table counts when the joined
    chain of its section plus every ancestor section matches eval|result|performance|accuracy|
    benchmark|score and does not match reproduc|throughput|latency|memory|footprint|hardware|
    deployment|speed. Subheadings do NOT end a section: the gemma-4-style cards put their
    accuracy tables under "#### Without thinking" inside "### Accuracy" inside "## Evaluation",
    and a counter that ends a section at the first deeper heading scores those cards 0
    (this exact bug once queued RedHatAI/gemma-4-31B-it-NVFP4, whose card carries 12).
  * A scored row is a table row with at least one numeric cell (a number after stripping
    % and +/- decorations). Its benchmark label is every non-numeric cell before the first
    numeric one, joined — "SWE-Bench Lite", not just "Lite" — falling back to the first
    non-numeric cell in the row when the row starts with numeric columns (index/version).
    Aggregate rows ("Average", "Recovery") are skipped. Variant labels count separately
    (IFEval prompt-level vs inst-level are two).
  * Transposed tables (the scored rows are model references — repo ids or names carrying a
    quant/dtype marker, like the Qwen3-VL "Accuracy Comparison" cards) count their BENCHMARKS
    instead: the non-numeric header cells, minus generic words (Model/Accuracy/Recovery/...),
    falling back to the deepest section title. Counting the model names would inflate the
    number; the row for this repo is the model's own score either way.
  * Plus every dataset named in the card's model-index YAML metadata (the HF API returns it
    pre-parsed as `model-index`).
  * Fenced code blocks and the YAML frontmatter are stripped before parsing: "#" comment
    lines inside shell/python blocks otherwise wreck the heading stack.
  * A card that cannot be fetched is an ERROR (count unknown), never a count of 0. A missing
    README (404) legitimately counts 0.

Validate a changed counter against known cards before trusting it:
  RedHatAI/Qwen3.8-27B-MXFP4 = 12       RedHatAI/Meta-Llama-3.1-8B-Instruct-FP8-dynamic = 16
  RedHatAI/gemma-4-31B-it-NVFP4 = 12    RedHatAI/Meta-Llama-3-8B-Instruct-FP8-KV = 1
  RedHatAI/gpt-oss-20b = 0

Environment: HF_TOKEN with write access to the org (collection commands, and the scan's
incremental mode — the collection is private, so even reading it needs the token; without
one the scan falls back to a full pass). HF_SCAN_CACHE=1 enables a dev-only HTTP cache under
/tmp (never use it for a real refresh — cached cards go stale).
"""

import concurrent.futures
import hashlib
import html as html_mod
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timedelta

HF = "https://huggingface.co"
ORG = "RedHatAI"
COLLECTION_TITLE = "Eval Queue"
# The Hub caps collection descriptions at 150 chars; collection_description() must stay below.
COLLECTION_DESCRIPTION_BASE = (
    "Internal use only: RedHatAI quantized models with <=3 card evals; queue for the evals-refresh skills."
)
LAST_REFRESH_RE = re.compile(r"Last refresh:\s*(\d{4}-\d{2}-\d{2})")
MAX_EVALS = 3
WORKERS = 8
CACHE_DIR = os.path.join("/tmp/opencode", "hf_scan_cache")


def collection_description(date_str):
    return "%s Last refresh: %s." % (COLLECTION_DESCRIPTION_BASE, date_str)

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def _cache_path(url):
    return os.path.join(CACHE_DIR, hashlib.sha1(url.encode()).hexdigest() + ".json")


def http(url, token=None, data=None, method=None):
    """GET/POST/DELETE; returns (status, body_text, headers). Raises after final failure."""
    cacheable = (data is None and "/api/collections" not in url
                 and (not url.split("/api/models")[-1].startswith("?") if "/api/models" in url else True))
    use_cache = cacheable and os.environ.get("HF_SCAN_CACHE") == "1"
    if use_cache and method in (None, "GET") and os.path.exists(_cache_path(url)):
        with open(_cache_path(url)) as f:
            c = json.load(f)
        return c["status"], c["body"], {}

    headers = {"User-Agent": "evals-refresh-queue-script"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data is not None else None
    if body is not None:
        headers["Content-Type"] = "application/json"

    last = None
    for attempt in range(8):
        req = urllib.request.Request(url, data=body, headers=headers, method=method or ("POST" if body is not None else "GET"))
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                text = r.read().decode("utf-8", "replace")
                if use_cache:
                    os.makedirs(CACHE_DIR, exist_ok=True)
                    with open(_cache_path(url), "w") as f:
                        json.dump({"status": r.status, "body": text}, f)
                return r.status, text, dict(r.headers)
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace") if e.fp else ""
            if e.code in (400, 401, 403, 404, 409, 422):
                return e.code, text, dict(e.headers or {})
            last = "HTTP %d for %s" % (e.code, url)
            retry_after = (e.headers or {}).get("Retry-After") if hasattr(e, "headers") else None
            if str(retry_after or "").isdigit():
                wait = min(300, int(retry_after))
            elif e.code == 429:
                wait = min(300, 30 * 2 ** attempt)
            else:
                wait = min(60, 2 ** attempt)
        except Exception as e:  # network hiccups
            last = "%s for %s" % (e, url)
            wait = min(60, 2 ** attempt)
        time.sleep(wait)
    raise RuntimeError("fetch failed after retries: " + str(last))


def token():
    tok = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if not tok:
        try:
            with open(os.path.expanduser("~/.cache/huggingface/token")) as f:
                tok = f.read().strip()
        except OSError:
            pass
    return tok or None


def api_get(path, tok=None):
    status, text, _ = http(HF + path, token=tok)
    if status != 200:
        raise RuntimeError("GET %s -> %d: %s" % (path, status, text[:200]))
    return json.loads(text)


# ---------------------------------------------------------------------------
# Card-evaluation counting
# ---------------------------------------------------------------------------

EVAL_RE = re.compile(r"eval|result|performance|accuracy|benchmark|score", re.I)
SKIP_RE = re.compile(
    r"reproduc|throughput|latency|memory|footprint|hardware|deployment|speed|requirement", re.I
)
HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(.*)$", re.M)
TABLE_RE = re.compile(r"<table\b.*?</table>", re.S | re.I)
TR_RE = re.compile(r"<tr\b.*?</tr>", re.S | re.I)
CELL_RE = re.compile(r"<t[dh]\b[^>]*>(.*?)</t[dh]>", re.S | re.I)
NUM_RE = re.compile(r"[-+]?\d*\.?\d+([eE][-+]?\d+)?")
HEADER_WORDS = {
    "benchmark", "metric", "task", "model", "category", "value", "score", "name",
    "dataset", "version", "filter", "stderr", "acc", "shots", "method", "average",
    "rank", "metric name", "load precision",
}
# A row label that looks like a model reference rather than a benchmark: repo ids
# ("Qwen/Qwen3-VL-32B-Instruct") or names carrying a quant/dtype marker.
MODELISH = re.compile(r"/|\b(fp8|fp4|nvfp4|mxfp4|w4a16|w8a8|w8a16|w4a4|int4|int8|bf16|fp16|awq|gptq|marlin)\b", re.I)
AGGREGATE = re.compile(r"\baverage\b|\brecovery\b", re.I)
GENERIC_HEADER = {
    "model", "accuracy", "recovery", "score", "value", "metric", "benchmark", "name",
    "method", "task", "category", "average", "rank", "scheme", "precision", "notes",
}


def strip_frontmatter(text):
    return re.sub(r"\A---[ \t]*\r?\n.*?\r?\n---[ \t]*(\r?\n|$)", "", text, count=1, flags=re.S)


def strip_code_fences(text):
    out, in_fence, fence = [], False, ""
    for line in text.split("\n"):
        s = line.lstrip()
        if not in_fence and (s.startswith("```") or s.startswith("~~~")):
            in_fence, fence = True, s[:3]
            continue
        if in_fence and s.startswith(fence):
            in_fence = False
            continue
        if not in_fence:
            out.append(line)
    return "\n".join(out)


def clean_cell(cell):
    cell = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", cell)  # markdown links -> text
    cell = re.sub(r"<br\s*/?>", " ", cell, flags=re.I)
    cell = re.sub(r"<[^>]+>", "", cell)
    cell = html_mod.unescape(cell)
    cell = cell.replace("**", "").replace("__", "").replace("`", "")
    return re.sub(r"\s+", " ", cell).strip()


def is_number(cell):
    c = cell.strip().strip("%").strip()
    c = c.lstrip("±~≈").strip().rstrip("±").strip()
    c = c.replace(",", "")
    return bool(c) and bool(NUM_RE.fullmatch(c))


def heading_stack(headings, pos):
    stack = []
    for start, level, title in headings:
        if start >= pos:
            break
        while stack and stack[-1][0] >= level:
            stack.pop()
        stack.append((level, title))
    return [t for _, t in stack]


def iter_tables(body):
    """Yields (offset, rows); rows are lists of cleaned cell strings."""
    for m in TABLE_RE.finditer(body):
        rows = []
        for tr in TR_RE.finditer(m.group(0)):
            cells = [clean_cell(c) for c in CELL_RE.findall(tr.group(0))]
            if cells:
                rows.append(cells)
        if rows:
            yield m.start(), rows

    lines, off, cur = body.split("\n"), 0, None
    for line in lines:
        s = line.strip()
        if s.startswith("|"):
            if cur is None:
                cur = [off, []]
            cells = [clean_cell(c) for c in s.strip("|").split("|")]
            if not all(c == "" or re.fullmatch(r":?-+:?", c) for c in cells):
                cur[1].append(cells)
        else:
            if cur and cur[1]:
                yield cur[0], cur[1]
            cur = None
        off += len(line) + 1
    if cur and cur[1]:
        yield cur[0], cur[1]


def model_index_names(model_index):
    names = set()
    for entry in model_index or []:
        for r in entry.get("results") or []:
            ds = r.get("dataset") or {}
            tk = r.get("task") or {}
            n = ds.get("name") or ds.get("type") or tk.get("name") or tk.get("type")
            if n:
                names.add(re.sub(r"\s+", " ", str(n)).strip().lower())
    return names


def count_card(readme, model_index=None, debug=False):
    """Returns (count, names, debug_rows)."""
    names, rows = set(), []
    body = strip_code_fences(strip_frontmatter(readme or ""))
    headings = [(m.start(), len(m.group(1)), m.group(2).strip()) for m in HEADING_RE.finditer(body)]
    for offset, table_rows in iter_tables(body):
        stack = heading_stack(headings, offset)
        ctx = " > ".join(stack)
        if not stack or not EVAL_RE.search(ctx) or SKIP_RE.search(ctx):
            continue
        row_labels = []
        for cells in table_rows:
            num_idx = next((i for i, c in enumerate(cells) if is_number(c)), None)
            if num_idx is None:
                continue
            labels = [c for c in cells[:num_idx] if c]
            if not labels:  # row starts with numeric columns (index/version)
                labels = [c for c in cells if c and not is_number(c)][:1]
                if not labels:
                    continue
            name = re.sub(r"\s+", " ", " ".join(labels)).strip()
            if len(name) < 2 or name.lower() in HEADER_WORDS or AGGREGATE.search(name):
                continue
            row_labels.append(name)
        if not row_labels:
            continue
        # Transposed table: the scored rows are models, not benchmarks. Then the model's
        # own scores are the row for this repo, and the benchmarks are the header cells
        # (falling back to the deepest section title when the header is generic).
        if len([n for n in row_labels if MODELISH.search(n)]) * 2 >= len(row_labels):
            header = [c for c in table_rows[0] if c and not is_number(c)]
            bench = [c for c in header if re.sub(r"[^a-z0-9]", "", c.lower()) not in GENERIC_HEADER]
            if not bench:
                bench = [stack[-1]]
            for b in bench:
                key = re.sub(r"\s+", " ", b).strip().lower()
                if len(key) >= 2 and key not in HEADER_WORDS:
                    names.add(key)
                    if debug:
                        rows.append((ctx, "%s [transposed]" % b))
        else:
            for name in row_labels:
                names.add(name.lower())
                if debug:
                    rows.append((ctx, name))
    names |= model_index_names(model_index)
    return len(names), sorted(names), rows


# ---------------------------------------------------------------------------
# Org scan
# ---------------------------------------------------------------------------

SPECULATOR_ID = re.compile(r"speculator|dspark", re.I)
SAFETY_ID = re.compile(r"llama-guard|guard|shieldgemma|safety|moderation", re.I)
QWEN25_BASE_ID = re.compile(r"^Qwen2\.5(-\w+)?-[\d.]+B($|[-.])", re.I)
QUANT_TAGS = {
    "fp8", "fp4", "int4", "int8", "8-bit", "4-bit", "w4a16", "w8a8", "w8a16", "w4a4",
    "gptq", "awq", "marlin", "mxfp4", "nvfp4", "quantized", "llm-compressor", "llmcompressor",
    "compressed-tensors",
}
RESEARCH_TAGS = {"deepsparse", "sparse", "sparsity", "pruning", "pruned", "obert"}
GOOD_PIPELINES = {"text-generation", "image-text-to-text"}


def list_models(author):
    url = HF + "/api/models?author=%s&limit=1000" % urllib.parse.quote(author)
    out = []
    while url:
        status, text, headers = http(url)
        if status != 200:
            raise RuntimeError("model list -> %d" % status)
        out.extend(json.loads(text))
        link = headers.get("Link") or headers.get("link") or ""
        m = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = m.group(1) if m else None
    return out


def list_models_last_modified(author):
    """{repo_id: lastModified} for the org. A separate call because expand[] drops the
    default fields (tags) the candidate filter needs — the §1 pitfall, used on purpose."""
    url = HF + "/api/models?author=%s&limit=1000&expand[]=lastModified" % urllib.parse.quote(author)
    out = {}
    while url:
        status, text, headers = http(url)
        if status != 200:
            raise RuntimeError("model list (lastModified) -> %d" % status)
        for m in json.loads(text):
            out[m.get("id")] = m.get("lastModified") or ""
        link = headers.get("Link") or headers.get("link") or ""
        m = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = m.group(1) if m else None
    return out


def is_candidate(m):
    """List-stage filter; returns (keep, reason)."""
    mid = m.get("id", "")
    tags = set(m.get("tags") or [])
    if SPECULATOR_ID.search(mid):
        return False, "speculator/dspark id"
    if m.get("library_name") == "speculators":
        return False, "speculators library"
    if m.get("library_name") == "deepsparse" or tags & RESEARCH_TAGS:
        return False, "pruned/sparse/DeepSparse-era research checkpoint"
    if "onnx" in tags or "gguf" in tags or m.get("library_name") in ("onnx", "gguf"):
        return False, "onnx/gguf"
    pipe = m.get("pipeline_tag")
    if pipe and pipe not in GOOD_PIPELINES:
        return False, "pipeline_tag %s" % pipe
    if SAFETY_ID.search(mid):
        return False, "safety classifier"
    if not (tags & QUANT_TAGS or any(t.startswith("base_model:quantized:") for t in tags)):
        return False, "no quantization signal"
    return True, ""


def resolve_base(model_id, info):
    card = info.get("cardData") or {}
    if isinstance(card.get("base_model"), str) and card["base_model"]:
        return card["base_model"], False
    for t in info.get("tags") or []:
        if t.startswith("base_model:quantized:"):
            return t.split(":", 2)[2], False
    return None, True


def has_chat_template(model_id, info):
    cfg = info.get("config") or {}
    if cfg.get("chat_template_jinja"):
        return True
    if (cfg.get("tokenizer_config") or {}).get("chat_template"):
        return True
    if any("chat_template" in (s.get("rfilename") or "") for s in info.get("siblings") or []):
        return True
    # last resort: the raw tokenizer_config.json
    try:
        status, text, _ = http(HF + "/%s/raw/main/tokenizer_config.json" % model_id)
    except Exception:
        return None  # unknown
    if status != 200:
        return False
    return re.search(r'"chat_template"\s*:', text) is not None


def qwen25_base(repo_id):
    name = repo_id.split("/")[-1]
    return bool(QWEN25_BASE_ID.match(name)) and "Instruct" not in name


def fetch_candidate(model_id):
    try:
        status, text, _ = http(HF + "/api/models/%s?blobs=true" % urllib.parse.quote(model_id, safe="/"))
        if status != 200:
            return {"id": model_id, "error": "model info -> HTTP %d" % status}
        info = json.loads(text)
        rstatus, rtext, _ = http(HF + "/%s/raw/main/README.md" % model_id)
        if rstatus in (401, 403):
            return {"id": model_id, "error": "README gated (HTTP %d)" % rstatus, "info": info}
        if rstatus not in (200, 404):
            return {"id": model_id, "error": "README -> HTTP %d" % rstatus, "info": info}
        return {"id": model_id, "info": info, "readme": rtext if rstatus == 200 else ""}
    except Exception as e:
        return {"id": model_id, "error": str(e)[:200]}


def quant_label(qcfg):
    """A short human label for the quantization scheme (NVFP4, FP8-dynamic, gptq-int4, ...)."""
    if not qcfg:
        return "quantized"
    method = qcfg.get("quant_method")
    if method and method != "compressed-tensors":
        return "%s%s" % (method, ("-int%s" % qcfg["bits"]) if qcfg.get("bits") else "")
    fmts = []
    if qcfg.get("format"):
        fmts.append(qcfg["format"])
    for g in (qcfg.get("config_groups") or {}).values():
        if isinstance(g, dict) and g.get("format"):
            fmts.append(g["format"])
    out = []
    for f in fmts:
        if f not in out:
            out.append(f)
    return "/".join(out) or method or "quantized"


def evaluate_candidate(result):
    """Adds eval count + verification to a fetch_candidate result."""
    if "error" in result and "info" not in result:
        return result
    model_id, info, readme = result["id"], result.get("info") or {}, result.get("readme") or ""
    if "error" in result:
        result["queued"], result["reason"] = False, result.pop("error")
        return result

    count, names, _ = count_card(readme, info.get("model-index"))
    result["evals"], result["eval_names"] = count, names

    cfg = info.get("config") or {}
    qcfg = cfg.get("quantization_config")
    base, base_unresolved = resolve_base(model_id, info)
    st = info.get("safetensors") or {}
    params = st.get("parameters") or {}
    result.update({
        "base": base,
        "base_unresolved": base_unresolved,
        "quant": quant_label(qcfg),
        "arch": (cfg.get("architectures") or [cfg.get("model_type") or "?"])[0],
        "params_b": round(sum(params.values()) / 1e9, 1) if params else None,
        "ckpt_gb": round(st["total"] / 1e9, 1) if st.get("total") else None,
        "gated": bool(info.get("gated")),
    })

    reason = None
    if not qcfg:
        reason = "no quantization_config (not a quantized checkpoint)"
    elif info.get("gated"):
        reason = "gated repo"
    else:
        chat = has_chat_template(model_id, info)
        if chat is None:
            result["evals"] = None
            result["queued"], result["reason"] = False, "chat template check failed (network) — re-run"
            return result
        if not chat:
            reason = "no chat template (base model?)"
        elif qwen25_base(model_id) or (base and qwen25_base(base)):
            reason = "quantization of a Qwen2.5 base model (Qwen2.5 bases ship chat templates)"
    if reason:
        result["queued"], result["reason"] = False, reason
    else:
        result["queued"] = count <= MAX_EVALS
        result["reason"] = None if result["queued"] else "%d card evals > %d" % (count, MAX_EVALS)
    return result


def cmd_scan(args):
    author = args.get("author") or ORG
    out_path = args.get("out") or "scan.json"
    date_str = time.strftime("%Y-%m-%d")

    # Incremental watermark: the last applied refresh, from the collection's description.
    since, coll_slug = None, None
    tok = token()
    if tok and not args.get("full"):
        try:
            coll_slug, desc = find_collection(tok)
            m = LAST_REFRESH_RE.search(desc or "")
            if m:
                since = m.group(1)
        except Exception as e:
            print("warning: could not read the collection (%s) — running a full scan" % e)
    mode = "incremental" if since else "full"
    if mode == "full":
        print("full scan%s" % (" (--full)" if args.get("full") else " (no last-refresh date in the collection description)"))
    else:
        print("incremental scan since %s (from the collection description)" % since)

    models = list_models(author)
    member_ids, items = set(), []
    if mode == "incremental":
        # One extra day of lookback: the watermark date is local, HF timestamps are UTC.
        lookback = (datetime.strptime(since, "%Y-%m-%d") - timedelta(days=1)).date().isoformat()
        lm = list_models_last_modified(author)
        if coll_slug:
            _, items = collection_items(coll_slug, tok)
            member_ids = {item_repo_id(it) for it in items}

        def dirty(m):
            created = (m.get("createdAt") or "")[:10]
            if not created or created >= lookback:
                return True
            modified = lm.get(m.get("id"))
            return modified is None or not modified or modified[:10] >= lookback

        pool = [m for m in models if dirty(m)]
        # Members whose repos did not change cannot have gained evals: keep, don't re-fetch.
        # (A deleted-but-unchanged member lingers until a --full; deletions are rare.)
        dirty_members = sorted(
            mid for mid in member_ids
            if lm.get(mid) is None or not lm.get(mid) or lm.get(mid)[:10] >= lookback
        )
        print("org models: %d; changed/created since %s: %d (of which %d are collection members)"
              % (len(models), lookback, len(pool), len(dirty_members)))
    else:
        pool = models

    funnel, candidates = Counter(), []
    for m in pool:
        if mode == "incremental" and m.get("id") in member_ids:
            continue  # dirty members are re-checked directly, not through the funnel
        keep, reason = is_candidate(m)
        if keep:
            candidates.append(m)
        else:
            funnel[reason] += 1
    if mode == "full":
        print("org models: %d -> candidates: %d" % (len(models), len(candidates)))
    else:
        print("candidates among changed non-members: %d" % len(candidates))
    for reason, n in funnel.most_common():
        print("  -%3d  %s" % (n, reason))

    results, stale_members, errors = [], [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for r in ex.map(lambda m: evaluate_candidate(fetch_candidate(m["id"])), candidates):
            results.append(r)
        if mode == "incremental":
            for mid, r in zip(dirty_members, ex.map(fetch_candidate, dirty_members)):
                if "error" in r and "info" not in r:
                    if "HTTP 404" in str(r.get("error")):
                        stale_members.append({"id": mid, "reason": "repo deleted"})
                    else:
                        errors.append({"id": mid, "reason": str(r.get("error"))[:200]})
                    continue
                count, _, _ = count_card(r.get("readme") or "", (r.get("info") or {}).get("model-index"))
                if count > MAX_EVALS:
                    stale_members.append({"id": mid, "reason": "%d card evals > %d since last refresh" % (count, MAX_EVALS)})

    queue = [r for r in results if r.get("queued")]
    not_queued = [{"id": r["id"], "evals": r.get("evals"), "reason": r.get("reason")}
                  for r in results if not r.get("queued") and r.get("evals") is not None and r["evals"] > MAX_EVALS]
    excluded = [{"id": r["id"], "reason": r.get("reason")} for r in results
                if not r.get("queued") and r.get("evals") is not None and r["evals"] <= MAX_EVALS]
    errors += [{"id": r["id"], "reason": r.get("reason") or r.get("error")} for r in results if r.get("evals") is None]

    scan = {
        "date": date_str,
        "author": author,
        "max_evals": MAX_EVALS,
        "mode": mode,
        "since": since,
        "funnel": {"org_models": len(models), "examined": len(pool),
                   "candidates": len(candidates), **dict(funnel)},
        "queue": queue,
        "stale_members": stale_members,
        "excluded_at_verification": excluded,
        "not_queued_more_than_max_evals": not_queued,
        "errors": errors,
    }
    with open(out_path, "w") as f:
        json.dump(scan, f, indent=1, sort_keys=True)

    if mode == "incremental":
        print("\nincremental: %d examined, %d new qualifiers (queue additions), %d stale members (removals)"
              % (len(pool), len(queue), len(stale_members)))
    print("\nqueue (<= %d card evals, verified): %d models" % (MAX_EVALS, len(queue)))
    for r in sorted(queue, key=lambda r: r["id"]):
        print("  %-70s evals=%-3d base=%s" % (r["id"], r["evals"], r.get("base") or "?"))
    if stale_members:
        print("\nstale members (to remove):")
        for r in stale_members:
            print("  %-70s %s" % (r["id"], r["reason"]))
    if excluded:
        print("\nexcluded at verification (%d):" % len(excluded))
        for r in excluded:
            print("  %-70s %s" % (r["id"], r["reason"]))
    if errors:
        print("\nERRORS (fetch failures — counts unknown, NOT queued; re-run): %d" % len(errors))
        for r in errors:
            print("  %-70s %s" % (r["id"], r["reason"]))
    if mode == "full":
        print("\nnot queued (%d card evals > %d): %d models" % (MAX_EVALS, MAX_EVALS, len(not_queued)))
        for r in sorted(not_queued, key=lambda r: r["evals"]):
            print("  %-70s evals=%s" % (r["id"], r["evals"]))
    print("\nwrote %s" % out_path)


def cmd_count(args):
    model_id = args["model_id"]
    result = fetch_candidate(model_id)
    if "error" in result and "info" not in result:
        sys.exit("error: %s" % result["error"])
    info, readme = result.get("info") or {}, result.get("readme") or ""
    count, names, rows = count_card(readme, info.get("model-index"), debug=args.get("debug"))
    if args.get("debug"):
        for ctx, name in rows:
            print("  [%s] %s" % (ctx, name))
        print()
    print("%s: %d evaluations" % (model_id, count))
    for n in names:
        print("  -", n)


# ---------------------------------------------------------------------------
# HF collection (the queue)
# ---------------------------------------------------------------------------


def collection_url(slug):
    if "/" not in slug:
        slug = ORG + "/" + slug
    return HF + "/api/collections/" + slug


def _norm_collection_slug(c):
    slug = c.get("slug") or c.get("id")
    if "/" not in str(slug):
        slug = "%s/%s-%s" % (ORG, slug, c.get("id")) if c.get("id") else ORG + "/" + str(slug)
    return slug


def find_collection(tok):
    """Read-only lookup: returns (slug, description) or (None, None). Never creates."""
    url = HF + "/api/collections?owner=" + urllib.parse.quote(ORG) + "&limit=100"
    while url:
        data = api_get(url[len(HF):], tok)
        items = data if isinstance(data, list) else (data.get("collections") or data.get("items") or [])
        for c in items:
            if c.get("title") == COLLECTION_TITLE:
                slug = _norm_collection_slug(c)
                desc = c.get("description") or ""
                if not desc:  # listing may omit the description; the collection GET has it
                    desc = api_get("/api/collections/" + slug, tok).get("description") or ""
                return slug, desc
        nxt = data.get("next") if isinstance(data, dict) else None
        url = (HF + nxt) if nxt else None
    return None, None


def find_or_create_collection(tok):
    """Returns the collection's slug (e.g. 'RedHatAI/eval-queue-abcdef12')."""
    slug, _ = find_collection(tok)
    if slug:
        return slug
    status, text, _ = http(HF + "/api/collections", token=tok,
                           data={"title": COLLECTION_TITLE, "namespace": ORG,
                                 "description": COLLECTION_DESCRIPTION_BASE, "private": True})
    if status not in (200, 201):
        sys.exit("create collection -> HTTP %d: %s" % (status, text[:300]))
    c = json.loads(text)
    slug = c.get("slug") or c.get("id")
    if "/" not in str(slug):
        slug = ORG + "/" + str(slug)
    print("created collection %s (private)" % slug)
    return slug


def collection_items(slug, tok):
    data = api_get("/api/collections/" + slug, tok)
    return data, data.get("items") or []


def get_collection_items(tok):
    slug = find_or_create_collection(tok)
    data, items = collection_items(slug, tok)
    return slug, data, items


def item_note(item):
    note = item.get("note")
    if isinstance(note, dict):
        return note.get("text") or note.get("html") or ""
    return note or ""


def item_repo_id(item):
    inner = item.get("item") or item
    return inner.get("id") or inner.get("repo_id")


def cmd_collection(args):
    tok = token()
    if not tok:
        sys.exit("HF_TOKEN (or ~/.cache/huggingface/token) with org access is required for collection commands.")
    action = args["action"]

    if action == "list":
        slug, data, items = get_collection_items(tok)
        print("collection: %s (%s) — %d items" % (slug, "private" if data.get("private") else data.get("visibility", "?"), len(items)))
        print("description: %s" % (data.get("description") or "(none)"))
        for it in sorted(items, key=lambda i: str(item_repo_id(i))):
            print("  %-70s %s" % (item_repo_id(it), item_note(it)[:90]))

    elif action == "sync":
        with open(args["scan_json"]) as f:
            scan = json.load(f)
        desired = {r["id"]: r for r in scan["queue"]}
        slug, data, items = get_collection_items(tok)
        current = {item_repo_id(it): it for it in items}
        to_add = sorted(set(desired) - set(current))
        if scan.get("mode") == "incremental":
            # Only the members the scan re-checked and found stale are removed; members
            # whose repos did not change were never re-fetched and stay.
            to_remove = sorted({s["id"] for s in scan.get("stale_members", [])} & set(current))
        else:
            to_remove = sorted(set(current) - set(desired))
        new_desc = collection_description(scan["date"])
        assert len(new_desc) <= 150, "description exceeds the Hub's 150-char limit"
        print("collection %s: %d items; scan (%s, since %s): %d qualifiers"
              % (slug, len(current), scan.get("mode"), scan.get("since"), len(desired)))
        for rid in to_add:
            r = desired[rid]
            note = "base=%s; %s; ckpt=%s GB; %d card evals (%s)" % (
                r.get("base") or "?", r.get("quant"), r.get("ckpt_gb") or "?", r["evals"], scan["date"])
            print("  + %-70s %s" % (rid, note))
            if args.get("apply"):
                status, text, _ = http(collection_url(slug) + "/items", token=tok,
                                       data={"item": {"type": "model", "id": rid}, "note": note[:500]})
                if status not in (200, 201):
                    sys.exit("add %s -> HTTP %d: %s" % (rid, status, text[:300]))
        for rid in to_remove:
            it = current[rid]
            print("  - %s" % rid)
            if args.get("apply"):
                iid = it.get("_id") or it.get("id")
                status, text, _ = http(collection_url(slug) + "/items/" + str(iid), token=tok, method="DELETE")
                if status not in (200, 204):
                    sys.exit("remove %s -> HTTP %d: %s" % (rid, status, text[:300]))
        print("  description -> %s" % new_desc)
        if args.get("apply"):
            status, text, _ = http(collection_url(slug), token=tok, data={"description": new_desc}, method="PATCH")
            if status not in (200, 201):
                sys.exit("update description -> HTTP %d: %s" % (status, text[:300]))
        else:
            print("\ndry run — pass --apply to change the collection")

    elif action == "add":
        slug, _, _ = get_collection_items(tok)
        status, text, _ = http(collection_url(slug) + "/items", token=tok,
                               data={"item": {"type": "model", "id": args["model_id"]},
                                     "note": (args.get("note") or "")[:500]})
        print("add -> HTTP %d %s" % (status, text[:200]))

    elif action == "remove":
        slug, _, items = get_collection_items(tok)
        match = [it for it in items if item_repo_id(it) == args["model_id"]]
        if not match:
            sys.exit("%s not in collection" % args["model_id"])
        iid = match[0].get("_id") or match[0].get("id")
        status, text, _ = http(collection_url(slug) + "/items/" + str(iid), token=tok, method="DELETE")
        print("remove -> HTTP %d %s" % (status, text[:200]))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd, rest = argv[1], argv[2:]
    if cmd == "count":
        if not rest:
            sys.exit("usage: eval_queue.py count <model_id> [--debug]")
        cmd_count({"model_id": rest[0], "debug": "--debug" in rest[1:]})
    elif cmd == "scan":
        args = {"author": ORG, "out": "scan.json", "full": False}
        i = 0
        while i < len(rest):
            if rest[i] == "--author":
                args["author"] = rest[i + 1]; i += 2
            elif rest[i] == "--out":
                args["out"] = rest[i + 1]; i += 2
            elif rest[i] == "--full":
                args["full"] = True; i += 1
            else:
                sys.exit("unknown arg: " + rest[i]); i += 1
        cmd_scan(args)
    elif cmd == "collection":
        if len(rest) < 1:
            sys.exit("usage: eval_queue.py collection <list|sync|add|remove> ...")
        action, cargs = rest[0], rest[1:]
        if action == "sync":
            if not cargs:
                sys.exit("usage: eval_queue.py collection sync <scan.json> [--apply]")
            args = {"action": "sync", "scan_json": cargs[0], "apply": "--apply" in cargs[1:]}
        elif action in ("add", "remove"):
            if not cargs:
                sys.exit("usage: eval_queue.py collection %s <model_id> [--note ...]" % action)
            note = cargs[2] if action == "add" and len(cargs) > 2 and cargs[1] == "--note" else None
            args = {"action": action, "model_id": cargs[0], "note": note}
        elif action == "list":
            args = {"action": "list"}
        else:
            sys.exit("unknown collection action: " + action)
        cmd_collection(args)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
