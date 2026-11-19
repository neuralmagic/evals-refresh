---
name: RedHatAI eval refresh
description: Use when asked to refresh RedHatAI quantized-model evaluations, run the next model in the eval queue, or update the models-needing-evals list. Refreshes the cached list of RedHatAI quantized models (not speculators, not base models) whose HF model cards carry at most 3 evaluations, picks a random one that fits the available GPUs (using chg if available), evaluates it on GPQA-Diamond, MMLU-Pro, SWE-bench-verified and Terminal-Bench 2.1 — plus the unquantized base model on the same benchmarks when it fits in VRAM, otherwise with baselines taken from the base model's model card — then updates the HF model card and commits the refreshed queue and the new task dirs to main.
---

# RedHatAI eval refresh

One invocation takes one model from the queue and evaluates it end to end. The queue is
`QUEUE.md` in this skill's directory (repo path `.opencode/skills/redhatai-eval-refresh/QUEUE.md`),
committed to main so every host shares it.

This skill is the one sanctioned exception to AGENTS.md §3's "never `git commit` or `git push`":
step 6 commits the refreshed queue and the new task directories directly to main and pushes.
Every other rule in AGENTS.md applies in full — read it first (especially §1, §3, §5–§11), plus
`local_env_notes.md` and `local_env_notes.local.md`.

## 0. Pre-flight

1. `git pull --ff-only origin main` — the queue is shared state; pull before every use, and
   again before the final commit.
2. Check prerequisites and note gaps: `chg` on PATH (GPU reservations), `nvidia-smi`, Docker
   for the two agentic benchmarks (disk on the data-root, local_env_notes), and `HF_TOKEN` in
   the environment — needed only for step 5, never committed anywhere.

## 1. Refresh the queue

Regenerate `QUEUE.md` with the procedure that produced it (the counting is heuristic; the
whole file is rewritten on every refresh, keeping only the "Completed" section):

1. List the org: `GET https://huggingface.co/api/models?author=RedHatAI&limit=1000`, following
   the `Link: <...>; rel="next"` header. Anonymous access is fine — ~1000 small requests at
   concurrency ≤ 8 stayed under the rate limit when this was built; pace down on 429s.
2. Keep a model iff **all** hold:
   - **Quantized**: it has a `base_model:quantized:<base>` tag or a quantization-format tag
     (fp8, fp4, int4, mxfp4, nvfp4, w4a16, w8a8, w8a16, gptq, awq, marlin, compressed-tensors,
     llm-compressor). Verify on the shortlist (step 5): `config.quantization_config` must
     exist — the org also hosts BF16 mirrors that carry `vllm`/`compressed-tensors` tags
     without being quantized.
   - **Not a speculator**: the id doesn't match `speculator|dspark` (case-insensitive) and the
     card doesn't describe a speculative-decoding draft model.
   - **Not a base model**: it has a chat template — a `chat_template.jinja` in the repo, or a
     non-null `chat_template` in `tokenizer_config.json`. The `conversational` tag is only a
     hint (it is missing on many instruct checkpoints). Careful: some base checkpoints ship a
     chat template anyway — the whole Qwen2.5 base series does — so judge by the base model id
     when the suffix is the only signal (`Qwen/Qwen2.5-32B` is base, `Qwen/Qwen2.5-32B-Instruct`
     is not; from Qwen3 on, the suffix-less ids are chat models).
   - **Servable by this repo**: `pipeline_tag` is text-generation or image-text-to-text; not
     gguf/onnx (vLLM cannot serve them); not a DeepSparse-era pruned/sparse research checkpoint;
     not a safety classifier (Llama-Guard and similar).
3. Count the evaluations attached to its card — `GET https://huggingface.co/<id>/raw/main/README.md`
   (no README ⇒ 0). The count is the number of **distinct benchmarks for which the card reports
   this model's own score**, across all `Evaluation`/`Results`/`Performance`/`Accuracy` sections
   and any `model-index` metadata. Baseline columns copied from other models do not count. The
   tables are HTML (`<table>/<tr>/<td>`) or markdown; in a table row that contains numbers, the
   benchmark name is the last non-numeric cell before the first numeric one. Spot-check several
   counts by eye, especially anything near the 3-evaluation boundary.
4. Queue = the models with **3 or fewer** evaluations.
5. For each queued model, `GET https://huggingface.co/api/models/<id>?blobs=true` and record
   `quantization_config.quant_method`, `architectures`, `safetensors.parameters` (sum),
   `safetensors.total` (bytes) and `gated`. Drop any that fail verification — no
   `quantization_config`, gated, or no chat template — and list them under "Excluded" with the
   reason (re-check rather than trust: a chat template in a nonstandard file flips a model back
   in, and Qwen2.5-family base targets must be excluded by name, per step 2).
6. Rewrite `QUEUE.md`: header with the refresh date, the filter funnel, the queue table, the
   excluded table. Base-model ids inferred from the checkpoint name (entries with no card to
   read) are marked with a trailing `?` and must be resolved by hand in step 4 of this skill.

## 2. Pick a model that fits the available GPUs

1. Free GPUs: with `chg` on PATH, `chg status` — only `AVAILABLE` rows are free (an `UNRESERVED`
   row with memory in use is not). Without `chg`, `nvidia-smi
   --query-gpu=index,memory.total,memory.used` plus the host's allocation convention.
   Per-GPU capacity comes from `memory.total`.
2. A queue entry fits if there is a tensor-parallel degree `k ∈ {1, 2, 4, 8}`, `k ≤` the number
   of free GPUs, with `checkpoint_GB × 1.15 / k + 8 ≤ per-GPU VRAM in GB` (weights ≈ checkpoint
   size; the 15% + 8 GiB cover activations, CUDA graphs and a minimal KV pool). Single node
   only. For entries with unknown size, fetch `safetensors.total` first. The agentic benchmarks
   need KV headroom beyond this — read the "GPU KV cache size" line in serve.log and size
   `--max-connections` to it (AGENTS.md §9).
3. Pick uniformly at random among the fitting entries — `shuf -n1` over their model ids — and
   record the pick, the free-GPU snapshot and the fit arithmetic for the final report.
4. Re-verify the pick before setting up: read its card (confirm the evaluation count and the
   base model; resolve any `?`), confirm `config.quantization_config`, confirm the architecture
   is in the installed vLLM's model registry (AGENTS.md §7), and confirm the checkpoint
   downloads (gated or missing ⇒ stop and report).
5. Nothing fits, or the queue is empty ⇒ stop and report the queue and GPU situation to the
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

1. The unquantized model is the queue's base-model column, confirmed against the quantized
   card's "quantized version of …" line. Entries marked `?` were inferred from the checkpoint
   name — resolve them (card, HF search) before proceeding.
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
4. No `HF_TOKEN` available ⇒ skip the push, mark the queue entry "evaluated <date>, card update
   pending" instead of removing it, and tell the user.

## 6. Update the queue and commit to main

1. Refresh `QUEUE.md`: the evaluated model now carries more than 3 evaluations — move it to
   "Completed by this skill" with the date, the four scores, where the baseline came from, and
   the card section it landed in.
2. Reflect per AGENTS.md §12 (general lessons into AGENTS.md / `local_env_notes.md`; nothing
   host-specific outside `local_env_notes.local.md`).
3. Commit to main and push: `QUEUE.md`, the new task dirs (logs stay gitignored), and any note
   updates from the reflection. If main moved, `git pull --rebase` first. Suggested message:
   `redhatai-eval-refresh: <model> (gpqa-diamond, mmlu-pro, swe-bench-verified, terminal-bench-2.1)`.
4. Report to the user: what ran, the four scores next to the baseline's, token/limit stats
   worth noting, leaks found in the audit (if any), the card diff pushed, and the queue's new
   state.
