---
name: RedHatAI eval refresh
description: Use when asked to refresh RedHatAI quantized-model evaluations, run the next model in the eval queue, or update the models-needing-evals list. Maintains the private RedHatAI "Eval Queue" Hugging Face collection of quantized models (not speculators, not base models) whose HF model cards carry at most 3 evaluations, picks a random one that fits the available GPUs (using chg if available), evaluates it on GPQA-Diamond, MMLU-Pro, SWE-bench-verified and Terminal-Bench 2.1 — plus the unquantized base model on the same benchmarks when it fits in VRAM, otherwise with baselines taken from the base model's model card — then updates the HF model card and removes the model from the collection.
---

# RedHatAI eval refresh

One invocation takes one model from the queue and evaluates it end to end. The queue is the
**private HF collection `RedHatAI` → "Eval Queue"** — every quantized model in the org
(excluding speculators, base models, and anything this repo cannot serve) whose HF model card
carries **3 or fewer evaluations**. A model leaves the collection once its card carries more.

All queue operations go through `eval_queue.py`, next to this file
(`.opencode/skills/redhatai-eval-refresh/eval_queue.py`): it counts a card's evaluations,
re-derives the queue for the whole org, and syncs/reads the collection. Read its docstring
before changing anything — the counting rules live there, with the known-good validation
counts.

This skill commits nothing. AGENTS.md §3 applies in full: new task directories stay in the
working tree for the repo owner to commit; the queue's shared state lives in the HF
collection, not in this repo. Every other rule in AGENTS.md applies too — read it first
(especially §1, §3, §5–§11), plus `local_env_notes.md` and `local_env_notes.local.md`.

## 0. Pre-flight

1. `git pull --ff-only origin main` — several hosts push to this repo; pull before you start.
2. Check prerequisites and note gaps: `chg` on PATH (GPU reservations), `nvidia-smi`, Docker
   for the two agentic benchmarks (disk on the data-root, local_env_notes), and `HF_TOKEN`
   with RedHatAI access in the environment — needed from step 1 on, because the collection is
   private (even reading it requires the token). It stays local — never in the repo, never in
   logs.

## 1. Refresh the queue

1. Run the scan (a few minutes; ~1000 anonymous HF API requests at low concurrency, with
   429-aware backoff):

   ```bash
   python3 eval_queue.py scan --out /tmp/scan.json
   ```

   Do **not** set `HF_SCAN_CACHE` for a real refresh — its cache serves stale cards. A fetch
   failure is reported under `ERRORS` with the count unknown; those models are never queued
   on a guess — fix the fetch (usually re-run) or re-count them by hand.
2. Audit the scan before syncing: spot-check the boundary with
   `python3 eval_queue.py count <id> --debug` (lists every counted row with its section) —
   especially anything at 3–4 evaluations and anything that just entered or left the queue —
   and re-validate the counter against the known cards when it changed:
   `Qwen3.8-27B-MXFP4` = 12, `Meta-Llama-3.1-8B-Instruct-FP8-dynamic` = 16,
   `gemma-4-31B-it-NVFP4` = 12, `Meta-Llama-3-8B-Instruct-FP8-KV` = 1, `gpt-oss-20b` = 0.
3. Sync the collection (dry run first, then `--apply`; adds queue entries with a note
   carrying base model, quant, checkpoint size and eval count, removes entries that no
   longer qualify):

   ```bash
   python3 eval_queue.py collection sync /tmp/scan.json          # plan only
   python3 eval_queue.py collection sync /tmp/scan.json --apply
   ```

What the scan does (all implemented in `eval_queue.py`; audit, don't re-implement):

- Lists the org (`GET /api/models?author=RedHatAI`, Link-header pagination). Do not pass
  `expand[]` to this endpoint: the response items then come back without the default fields
  (`tags`), which silently breaks every filter below.
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

## 2. Pick a model that fits the available GPUs

1. Read the queue: `python3 eval_queue.py collection list` (needs `HF_TOKEN`). Each item's
   note carries `base=…; <quant>; ckpt=<GB>; <n> card evals (<date>)`.
2. Free GPUs: with `chg` on PATH, `chg status` — only `AVAILABLE` rows are free (an
   `UNRESERVED` row with memory in use is not). Without `chg`, `nvidia-smi
   --query-gpu=index,memory.total,memory.used` plus the host's allocation convention.
   Per-GPU capacity comes from `memory.total`.
3. A queue entry fits if there is a tensor-parallel degree `k ∈ {1, 2, 4, 8}`, `k ≤` the number
   of free GPUs, with `checkpoint_GB × 1.15 / k + 8 ≤ per-GPU VRAM in GB` (weights ≈ checkpoint
   size; the 15% + 8 GiB cover activations, CUDA graphs and a minimal KV pool). Single node
   only. For entries with `ckpt=?` (no safetensors info), fetch the size first. The agentic
   benchmarks need KV headroom beyond this — read the "GPU KV cache size" line in serve.log
   and size `--max-connections` to it (AGENTS.md §9).
4. Pick uniformly at random among the fitting entries — `shuf -n1` over their model ids — and
   record the pick, the free-GPU snapshot and the fit arithmetic for the final report.
5. Re-verify the pick before setting up: read its card (confirm the evaluation count and the
   base model; `base=?` notes mean no card and no `base_model` metadata — resolve the base by
   hand from the checkpoint name and the HF search), confirm `config.quantization_config`,
   confirm the architecture is in the installed vLLM's model registry (AGENTS.md §7), and
   confirm the checkpoint downloads (gated or missing ⇒ stop and report).
6. Nothing fits, or the queue is empty ⇒ stop and report the queue and GPU situation to the
   user.

## 3. Evaluate the model on the four benchmarks

| benchmark | task dir | category | package | exec tier |
|---|---|---|---|---|
| GPQA Diamond | `gpqa-diamond` | knowledge-and-reasoning | inspect_evals `gpqa_diamond` | none |
| MMLU-Pro | `mmlu-pro` | knowledge-and-reasoning | inspect_evals `mmlu_pro` | none |
| SWE-bench Verified | `swe-bench-verified` | agentic-and-coding | inspect_evals `swe_bench` | agent |
| Terminal-Bench 2.1 | `terminal-bench-2.1` | agentic-and-coding | inspect_harbor `terminal_bench_2_1` | agent |

1. Create `RedHatAI_<model>/` (HF id with `/` → `_`) with the four task dirs, copied per
   AGENTS.md §7 from the closest existing dir of that task — same model family if one exists,
   otherwise `RedHatAI_Qwen3.8-Flash-Next-NVFP4`, which carries all four. For
   `swe-bench-verified` always copy from a Qwen3.8-Flash-Next dir: only those carry the §11
   leak fixes. Build each client env from the copied dir's `client_requirements.txt` (§4).
2. If any of the four benchmarks already have a task dir for this model in the repo, do not
   rerun them — reuse their README results in step 5.
3. `serve.sh` from the model's vLLM recipe at `https://recipes.vllm.ai/<Org>/<model>` (record
   the URL in each README). If no recipe exists for the exact checkpoint, start from the base
   model's recipe — vLLM reads `quantization_config` from the checkpoint, so the recipe flags
   carry over — and say so in the README. Sampling params from the checkpoint's
   `generation_config.json`; thinking on at the model's highest effort, set on both sides
   (§1). Text-only tasks on multimodal checkpoints: zero `--limit-mm-per-prompt` (§7). Keep
   `--max-tokens` strictly below `--max-model-len`.
4. Set every copied dir's `EPOCHS` default to 1 (§3, §10) unless the user asked for more.
5. Smoke test each task before the full run (`EPOCHS=1 ./local_orchestrator.sh --limit 5`;
   `--limit 2` for the two agentic ones) and read the samples: reasoning parsed into a
   separate content part, `stop_reason` = `stop`, and the intended
   `eval.model_generate_config` (§3).
6. Full runs, one task at a time (§3: one task directory, one server). With `chg`, hold the
   reservation for the whole run (`chg run` wrapping the orchestrator) and tear down by exact
   process group, confirming 0 MiB on your GPUs before the next server (§9). For the agentic
   two follow §8: `--max-sandboxes` = `--max-connections`, a `--time-limit` runaway guard,
   `--fail-on-error 0.1`, per-turn `--max-tokens` with room for multi-turn history. Launch
   long runs so they survive a dropped session (local_env_notes) and monitor with
   `inspect ctl task list`.
7. Audit the agentic runs for solution leaks before reporting anything (§11 — read
   `sample.events`, not `sample.messages`). Then fill each README from the §6 template —
   headline scores over all samples — and regenerate `server_requirements.txt` /
   `client_requirements.txt` from the venvs that produced the results.

## 4. Baseline: the unquantized model

1. The unquantized model is the pick's base model — the collection item's `base=` note,
   confirmed against the quantized card's "quantized version of …" line. `base=?` means
   unresolved — resolve it (card, HF search) before proceeding.
2. If the base model fits the same free GPUs (the step-2 fit check on its own checkpoint
   size), evaluate it on the same four benchmarks with the same protocol after the quantized
   model's runs finish — one server at a time. Its task dirs go under `<org>_<base-model>/`
   with the same copying rules. Those local runs are the baseline column.
3. Otherwise take the baseline numbers for whichever of the four benchmarks the base model's
   card reports, and note — on the quantized model's card (step 5) and in the task READMEs'
   protocol notes — that the baseline comes from the base model's model card rather than a
   local run. Check comparability against how the card measured it (§1 rule 5).
4. If the base model is not publicly available, say so in the card note and report it to the
   user in the final summary.

## 5. Update the model card

1. Requires `HF_TOKEN` with write access to RedHatAI. It stays local — never in the repo, never
   in logs.
2. Load the live card (`huggingface_hub` `ModelCard.load`), append a new evaluation section
   following the card's existing convention (`## Evaluation vN`, incrementing N), and push with
   `push_to_hub`. The section contains: a results table (benchmark | this model | unquantized
   baseline | recovery) covering the four benchmarks plus any reused in-repo runs; the
   all-samples headline scores; the `eval.model_generate_config` line, epochs, vLLM version,
   GPU count and type, and date; and the note on where the baseline came from (local run vs the
   base model's card). Preserve every other part of the card — change only the section you add.
3. If anything about the run was abnormal — sample errors, a leak found in the §11 audit,
   protocol deviations — report it to the user and let them decide before pushing to the Hub.
4. No `HF_TOKEN` available ⇒ skip the push, leave the model in the collection, and tell the
   user the card update (and the step-6 removal) are pending.

## 6. Update the queue

1. The evaluated model's card now carries more than 3 evaluations — remove it from the
   collection:

   ```bash
   python3 eval_queue.py collection remove <model_id>
   ```

   (A refresh, §1, would also drop it — removing it here keeps the queue exact for the next
   host without a full rescan.)
2. Reflect per AGENTS.md §12 (general lessons into AGENTS.md / `local_env_notes.md`; nothing
   host-specific outside `local_env_notes.local.md`).
3. Leave the new task directories in the working tree and list them for the user — committing
   is the repo owner's job (AGENTS.md §3).
4. Report to the user: what ran, the four scores next to the baseline's, token/limit stats
   worth noting, leaks found in the audit (if any), the card diff pushed, and the queue's new
   state (`collection list`).
