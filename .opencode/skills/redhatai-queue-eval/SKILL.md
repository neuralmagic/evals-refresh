---
name: RedHatAI eval queue run
description: Use when asked to evaluate the next model (or a model) from the RedHatAI eval queue, given a number of GPUs to use. Picks a random quantized model from the private RedHatAI "Eval Queue" HF collection that fits the given GPUs, evaluates it on GPQA-Diamond, MMLU-Pro, SWE-bench-verified and Terminal-Bench 2.1 — plus the unquantized base model on the same benchmarks when it fits in VRAM, otherwise with baselines taken from the base model's model card — updates the model's HF card, and removes it from the collection. Maintaining the queue itself is the redhatai-queue-refresh skill's job.
---

# RedHatAI eval queue run

One invocation takes one model from the queue and evaluates it end to end. The queue is the
**private HF collection `RedHatAI` → "Eval Queue"** — quantized models whose HF cards carry
≤3 evaluations — maintained by the `redhatai-queue-refresh` skill (its
`.opencode/skills/redhatai-queue-refresh/SKILL.md` documents the queue rules and the
card-eval counting; refresh it first if asked, or if the collection looks stale).

Queue reads and removals go through `eval_queue.py` in that skill's directory — run it from
the repo root. Both skills need `HF_TOKEN` with RedHatAI access (the collection is private).

This skill commits nothing. AGENTS.md §3 applies in full: new task directories stay in the
working tree for the repo owner to commit. Every other rule in AGENTS.md applies too — read
it first (especially §1, §3, §5–§11), plus `local_env_notes.md` and
`local_env_notes.local.md`.

## 0. Pre-flight

1. `git pull --ff-only origin main` — several hosts push to this repo.
2. **GPUs: the request states how many GPUs to use (N).** If it doesn't, ask the user before
   doing anything else — the pick, the fit arithmetic and the reservation all depend on N.
3. Check prerequisites and note gaps: `chg` on PATH (GPU reservations), `nvidia-smi`, Docker
   for the two agentic benchmarks (disk on the data-root, local_env_notes), and `HF_TOKEN`
   in the environment — needed to read the private collection and to push the card update.
   It stays local — never in the repo, never in logs.
4. Verify N GPUs are actually free: with `chg`, `chg status` — only `AVAILABLE` rows are
   free (an `UNRESERVED` row with memory in use is not). Without `chg`, `nvidia-smi
   --query-gpu=index,memory.total,memory.used` plus the host's allocation convention. Fewer
   than N free ⇒ stop and report to the user.

## 1. Pick a model that fits the N GPUs

1. Read the queue (from the repo root):

   ```bash
   python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py collection list
   ```

   Each item's note carries `base=…; <quant>; ckpt=<GB>; <n> card evals (<date>)`.
2. A queue entry fits if there is a tensor-parallel degree `k ∈ {1, 2, 4, 8}`, `k ≤ N`, with
   `checkpoint_GB × 1.15 / k + 8 ≤ per-GPU VRAM in GB` (weights ≈ checkpoint size; the 15%
   + 8 GiB cover activations, CUDA graphs and a minimal KV pool). Single node only. For
   entries with `ckpt=?` (no safetensors info), fetch the size first. The agentic
   benchmarks need KV headroom beyond this — read the "GPU KV cache size" line in serve.log
   and size `--max-connections` to it (AGENTS.md §9).
3. Pick uniformly at random among the fitting entries — `shuf -n1` over their model ids —
   and record the pick, the free-GPU snapshot and the fit arithmetic for the final report.
   The pick is capped at N GPUs even if more are free — that is the budget the user gave.
4. Re-verify the pick before setting up: read its card (confirm the evaluation count and the
   base model; `base=?` notes mean no card and no `base_model` metadata — resolve the base
   by hand from the checkpoint name and the HF search), confirm `config.quantization_config`,
   confirm the architecture is in the installed vLLM's model registry (AGENTS.md §7), and
   confirm the checkpoint downloads (gated or missing ⇒ stop and report). If the pick's card
   now carries more than 3 evaluations (it gained them since the last refresh), remove it
   from the collection (`eval_queue.py collection remove <id>`) and re-pick.
5. Nothing fits, or the queue is empty ⇒ stop and report the queue and GPU situation to the
   user.

## 2. Evaluate the model on the four benchmarks

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
   rerun them — reuse their README results in step 4.
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
6. Full runs, one task at a time (§3: one task directory, one server). With `chg`, hold a
   reservation of exactly the N GPUs for the whole run (`chg run` wrapping the orchestrator)
   and tear down by exact process group, confirming 0 MiB on your GPUs before the next
   server (§9). For the agentic two follow §8: `--max-sandboxes` = `--max-connections`, a
   `--time-limit` runaway guard, `--fail-on-error 0.1`, per-turn `--max-tokens` with room
   for multi-turn history. Launch long runs so they survive a dropped session
   (local_env_notes) and monitor with `inspect ctl task list`.
7. Audit the agentic runs for solution leaks before reporting anything (§11 — read
   `sample.events`, not `sample.messages`). Then fill each README from the §6 template —
   headline scores over all samples — and regenerate `server_requirements.txt` /
   `client_requirements.txt` from the venvs that produced the results.

## 3. Baseline: the unquantized model

1. The unquantized model is the pick's base model — the collection item's `base=` note,
   confirmed against the quantized card's "quantized version of …" line. `base=?` means
   unresolved — resolve it (card, HF search) before proceeding.
2. If the base model fits the same N GPUs (the step-1 fit check on its own checkpoint size),
   evaluate it on the same four benchmarks with the same protocol after the quantized
   model's runs finish — one server at a time, within the same reservation. Its task dirs go
   under `<org>_<base-model>/` with the same copying rules. Those local runs are the
   baseline column.
3. Otherwise take the baseline numbers for whichever of the four benchmarks the base model's
   card reports, and note — on the quantized model's card (step 4) and in the task READMEs'
   protocol notes — that the baseline comes from the base model's model card rather than a
   local run. Check comparability against how the card measured it (§1 rule 5).
4. If the base model is not publicly available, say so in the card note and report it to the
   user in the final summary.

## 4. Update the model card

1. Requires `HF_TOKEN` with write access to RedHatAI. It stays local — never in the repo,
   never in logs.
2. Load the live card (`huggingface_hub` `ModelCard.load`), append a new evaluation section
   following the card's existing convention (`## Evaluation vN`, incrementing N), and push
   with `push_to_hub`. The section contains: a results table (benchmark | this model |
   unquantized baseline | recovery) covering the four benchmarks plus any reused in-repo
   runs; the all-samples headline scores; the `eval.model_generate_config` line, epochs,
   vLLM version, GPU count and type, and date; and the note on where the baseline came from
   (local run vs the base model's card). Preserve every other part of the card — change only
   the section you add.
3. If anything about the run was abnormal — sample errors, a leak found in the §11 audit,
   protocol deviations — report it to the user and let them decide before pushing to the Hub.
4. No `HF_TOKEN` available ⇒ skip the push, leave the model in the collection, and tell the
   user the card update (and the step-5 removal) are pending.

## 5. Update the queue

1. The evaluated model's card now carries more than 3 evaluations — remove it from the
   collection:

   ```bash
   python3 .opencode/skills/redhatai-queue-refresh/eval_queue.py collection remove <model_id>
   ```

2. Reflect per AGENTS.md §12 (general lessons into AGENTS.md / `local_env_notes.md`; nothing
   host-specific outside `local_env_notes.local.md`).
3. Leave the new task directories in the working tree and list them for the user —
   committing is the repo owner's job (AGENTS.md §3).
4. Report to the user: what ran, the four scores next to the baseline's, token/limit stats
   worth noting, leaks found in the audit (if any), the card diff pushed, and the queue's new
   state (`collection list`).
