---
name: RedHatAI eval queue refresh
description: Use when asked to refresh or update the RedHatAI eval queue, the models-needing-evals list, or the Eval Queue collection. Re-scans the RedHatAI org for quantized models (not speculators, not base models) whose HF model cards carry at most 3 evaluations and syncs the private "Eval Queue" HF collection — incrementally, using the last-refresh date recorded in the collection's description (newly created models plus repos modified since then), or fully with --full. Does not run any evaluations; the redhatai-queue-eval skill does that.
---

# RedHatAI eval queue refresh

The queue is the **private HF collection `RedHatAI` → "Eval Queue"**: every quantized model in
the org (excluding speculators, base models, and anything this repo cannot serve) whose HF
model card carries **3 or fewer evaluations**. A model leaves once its card carries more.
This skill refreshes that collection; evaluating queue members is the `redhatai-queue-eval`
skill's job.

All queue operations go through `eval_queue.py`, next to this file
(`.opencode/skills/redhatai-queue-refresh/eval_queue.py`) — run it from the repo root. Read
its docstring before changing anything: the card-eval counting rules live there, with
known-good validation counts.

This skill commits nothing (AGENTS.md §3 applies in full) and runs no evaluations. Read
AGENTS.md first (especially §1 and §3), plus `local_env_notes.md` and `local_env_notes.local.md`.

## 0. Pre-flight

1. `git pull --ff-only origin main` — several hosts push to this repo.
2. `HF_TOKEN` with RedHatAI access must be in the environment (or
   `~/.cache/huggingface/token`) — the collection is private, so even reading it requires
   the token, and the incremental scan reads the last-refresh date from its description.
   The token stays local — never in the repo, never in logs.

## 1. Run the scan

```bash
python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py scan --out /tmp/scan.json
```

The scan is **incremental by default**: it reads the last refresh date from the
collection's description (the "Last refresh: YYYY-MM-DD" marker, stamped by the previous
applied sync) and examines only

- models **created** since that date (HF `createdAt`), and
- models whose repos **changed** since that date (HF `lastModified`, fetched in a second org
  listing — `expand[]` returns it but drops the default fields like `tags`, so it cannot
  replace the plain listing). This is what keeps models with ≤3 evals in the queue no matter
  when they were created: a repo that changed is re-examined, a card that gained evals drops
  its model from the queue, and a card rewritten to fewer reported evals brings its model
  back in. Creation date alone is not enough — cards gain eval sections after publication.

Collection members whose repos did not change are kept without re-fetching (they cannot have
gained evals); changed members are re-counted and listed under "stale members" if they now
carry more than 3. A member deleted from the Hub without any change lingers until a full
scan. The date comparison keeps a one-day lookback (the marker is a local date, HF
timestamps are UTC); over-inclusion is harmless, a missed model is not.

Run a **full scan** (`--full`) when: the collection is new, the counting rules in
`eval_queue.py` changed (an improved counter must re-examine every card, not just changed
repos), or drift is suspected. A full scan makes the sync replace the collection contents
exactly; an incremental sync only adds the new qualifiers and removes the stale members it
re-checked.

Operational notes: ~1000 anonymous HF API requests for a full scan (a few minutes, 429-aware
backoff), only the changed slice for an incremental one. Do **not** set `HF_SCAN_CACHE` for a
real refresh — its cache serves stale cards and stale collection state. A fetch failure is
reported under `ERRORS` with the count unknown; those models are never queued on a guess —
fix the fetch (usually re-run) or re-count them by hand.

## 2. Audit the scan before syncing

Spot-check the boundary with
`python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py count <id> --debug`
(it lists every counted row with its section) — especially anything at 3–4 evaluations and
anything that just entered or left the queue. Re-validate the counter against the known
cards whenever its rules changed: `Qwen3.8-27B-MXFP4` = 12,
`Meta-Llama-3.1-8B-Instruct-FP8-dynamic` = 16, `gemma-4-31B-it-NVFP4` = 12,
`Meta-Llama-3-8B-Instruct-FP8-KV` = 1, `gpt-oss-20b` = 0.

## 3. Sync the collection

```bash
python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py collection sync /tmp/scan.json          # plan only
python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py collection sync /tmp/scan.json --apply
```

Adds queued models (each item's note carries `base=…; <quant>; ckpt=<GB>; <n> card evals
(<date>)`), removes stale ones, then stamps the scan's date into the description as the new
"Last refresh" marker. The date advances only on an applied sync, so a scan that is never
applied does not move the watermark.

## 4. Report

Report the queue's new state (`collection list`): item count, what entered and left, fetch
errors if any, and whether the run was incremental or full.

## What the scan does (all implemented in `eval_queue.py`; audit, don't re-implement)

- Lists the org (`GET /api/models?author=RedHatAI`, Link-header pagination). Do not pass
  `expand[]` to the plain listing: the response items then come back without the default
  fields (`tags`), which silently breaks every filter below.
- Keeps a model iff **all** hold:
  - **Quantized**: it has a `base_model:quantized:<base>` tag or a quantization-format tag
    (fp8, fp4, int4, int8, 8-bit, 4-bit, w4a16, w8a8, w8a16, w4a4, gptq, awq, marlin, mxfp4,
    nvfp4, quantized, llm-compressor, compressed-tensors). The tag is only a signal — the
    per-model check that matters is `config.quantization_config`, which the org's BF16
    mirrors (tagged `compressed-tensors` without being quantized) fail.
  - **Not a speculator**: the id doesn't match `speculator|dspark` (case-insensitive) and
    `library_name` isn't `speculators`.
  - **Not a base model**: it has a chat template — `config.chat_template_jinja`, a
    `chat_template` in `config.tokenizer_config`, or a `chat_template*` file in the repo.
    Careful: Qwen2.5 *base* checkpoints ship a chat template anyway, so a repo/base id
    matching `Qwen2.5(-family)?-<size>B` without `Instruct` is a base model and is excluded
    by name; from Qwen3 on, the suffix-less ids are chat models.
  - **Servable by this repo**: `pipeline_tag` is text-generation or image-text-to-text (or
    missing); not gguf/onnx; not a DeepSparse-era pruned/sparse research checkpoint; not a
    safety classifier.
- Counts the evaluations attached to its card (README body tables + `model-index` metadata)
  — the full rules and their failure modes are in `eval_queue.py`'s docstring. The two that
  bit us: a table under `####`-subheadings of an eval section still counts (section scoping
  must use the heading *stack*, not the nearest heading — this bug once queued
  `gemma-4-31B-it-NVFP4` with 12 evals on its card counted as 0), and transposed tables
  (rows are models) count their header/section benchmarks, not the model names.
- Queue = models with **3 or fewer** evaluations that pass verification
  (`quantization_config` present, chat template, not gated, not a Qwen2.5-base quant).
  Verification exclusions and the >3 models are recorded in scan.json — read both, don't
  just trust the queue list.
