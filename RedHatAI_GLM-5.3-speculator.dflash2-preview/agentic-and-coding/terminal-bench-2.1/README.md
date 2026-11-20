# RedHatAI/GLM-5.3-speculator.dflash2-preview — Terminal-Bench 2.1

| | |
|---|---|
| Task | `inspect_harbor/terminal_bench_2_1` (89 tasks, Harbor hub package `terminal-bench/terminal-bench-2-1` pinned to digest `sha256:7d7bdc1c…`) |
| Category | agentic-and-coding (subclass: swe-agent) |
| Exec tier | `agent` — one prebuilt Docker container per task (Docker Hub image named in the task's `task.toml`), bash/python tools, hidden verifier |
| vLLM recipe | https://recipes.vllm.ai/zai-org/GLM-5.3 |
| Target model | https://huggingface.co/zai-org/GLM-5.3 (FP8, 78-layer `GlmMoeDsaForCausalLM`, ~756 GB) — revision `ba32f8c1` (unchanged since 2026-10-14) |
| Draft (speculator) | https://huggingface.co/RedHatAI/GLM-5.3-speculator.dflash2-preview (DFlash2, ~4.1 GB, 5-layer Qwen3-style backbone, `num_speculative_tokens=8`) — **revision `83c1f7eb`** (results below; `3325df9c` kept for comparison) |
| Task source | https://hub.harborframework.com/datasets/terminal-bench/terminal-bench-2-1 |

This directory measures draft-model acceptance for DFlash2 on real agent trajectories. It is not a leaderboard
entry. `serve.sh` runs the target with the DFlash2 draft model and with `--per-request-spec-decode-metrics
detailed`. `run_eval.sh` passes Inspect's `--log-model-api`, so the log keeps the raw response of every model
call. `analyze_spec_decode.py` reads those responses offline.

The task, agent and generation settings match the sibling
`RedHatAI_GLM-5.3-MXFP4xFP8/agentic-and-coding/terminal-bench-2.1` directory (same model family, same task pin):

- Inspect's ReAct agent (`bash`, `python`, `update_plan`, `submit`; 300 s tool timeout; automatic context
  compaction), not the Claude Code 2.1.207 harness used by the GLM-5.3 model card (88.2) or the Terminus 2 agent
  used by the leaderboard.
- One uniform `--time-limit 7200` instead of Harbor's per-task agent timeouts.
- Containers run without Harbor's CPU cap (`override_cpus=0`) and with `inspect_harbor`'s 6 GB memory floor.
- Per-turn `max_tokens` 65536, sampling from the checkpoint's `generation_config.json` (temp 1.0, top_p 0.95; no
  top_k, unlike Qwen) and reasoning effort `max` (GLM-5.3's highest and default level).
- Epochs: 1 (`pass@1`).

The only difference from that sibling directory is the serving stack: the full-precision FP8 `zai-org/GLM-5.3`
checkpoint (~756 GB) instead of the MXFP4xFP8 quantized one, one TP=8 replica, and DFlash2 speculative decoding
against `RedHatAI/GLM-5.3-speculator.dflash2-preview` instead of MTP. Speculative decoding changes what generation costs,
not the task, the scaffold or the sampling. This directory reports the acceptance numbers, with the score next
to them.

## Files

- `serve.sh` runs the target with vLLM and the DFlash2 draft model. The vLLM serve arguments live here: parallelism,
  context length, KV-cache dtype, parsers, `--speculative-config` and `--per-request-spec-decode-metrics`.
- `run_eval.sh` runs the Inspect task against that server. The Inspect parameters live here: task and package
  digest, epochs, sampling, per-turn max tokens, concurrency, sandbox count, time limit and `--log-model-api`.
- `monitor_spec_decode.py` is the guard for vLLM #63587: `canary` probes a live server for the acceptance
  collapse while the eval runs, `audit` quantifies collapsed calls in the collated CSV (see the bug section).
- `analyze_spec_decode.py` collates the raw responses out of the `.eval` logs into a per-call CSV and computes
  the acceptance analysis (MAL, per-position rates, thinking against response, slices, outliers). It is the
  deliverable of this directory.
- `server_requirements.txt` and `client_requirements.txt` are `pip freeze` of the vLLM and Inspect venvs that
  produced the results below. The client venv is the `inspect-harbor` one (see Run).
- `local_orchestrator.sh` runs everything on one host. It checks the GPU reservation, activates the venvs, sets
  the HF cache, starts `serve.sh` in the background, runs `run_eval.sh` and tears down. Modify this file only,
  to match the environment you run in.

That is 8 committed files: the same shape as the sibling directories (7 files), plus `monitor_spec_decode.py`
for the `#63587` guard. `logs/` (eval log, canary, `calls.csv`, smoke runs) and `spec_decode_report/` are run
artifacts and stay out of git, as the repo's `.gitignore` intends.

## Run

### Setup (once per host)

Create a server and a client environment as below. The commands use the paths that `local_orchestrator.sh`
activates; if you keep the environments elsewhere, change the paths in both places.

```bash
# server: vLLM main @ ace415c06 (nightly wheel 0.34.0rc1.dev253+gace415c06), which contains the
# #64059 DFlash-fix; 0.32.0/0.33.0 do NOT contain it
python3.12 -m venv ~/.venvs/vllm && source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt          # or:
# uv pip install --pre vllm==0.34.0rc1.dev253+gace415c06 --extra-index-url https://wheels.vllm.ai/nightly
# client: Inspect
python3.12 -m venv ~/.venvs/inspect-harbor && source ~/.venvs/inspect-harbor/bin/activate
pip install -r client_requirements.txt          # or:
# pip install "inspect-harbor==1.0.0" "inspect-ai==0.3.283" httpx2 "openai==3.14.0"
```

`inspect-harbor` pulls in `litellm`, which pins `openai<3`, while Inspect's OpenAI-compatible providers need
`openai>=3`. Installing `openai==3.14.0` last overrides the pin. pip prints a conflict warning, which is
harmless here because Inspect's agent path never imports `litellm`. `httpx2` is imported by `inspect-ai` but
not declared.

Both models are fetched from the Hugging Face Hub on first use into the usual cache (`HF_HOME`). The target is
~756 GB in 141 safetensors shards; the speculator is ~2.5 GB. Both are public and un-gated. Export `HF_TOKEN` in
your shell before running (never in the repo) to avoid anonymous rate limits. huggingface_hub 2.x keeps large
files in a content-addressed store under `<HF_HOME>/hub/blobs/` and leaves each model's `blobs/<sha>` entries as
symlinks into it, so `du -sh` on a model directory under-reports. Check the files with
`ls -laL <snapshot>/*.safetensors` instead. On this host the cache is on the large `/data` volume
(`HF_HOME=/data/reed-meyerson/hf`), because `/home` does not have ~1 TB free. `local_orchestrator.sh` serves with
`HF_HUB_OFFLINE=1`.

flashinfer 0.7.0.post1 (installed by vLLM) has no matching `flashinfer-cubin` wheel, so the DSA sparse-MLA
kernels are JIT-compiled on first start: `serve.sh` exports `CUDA_HOME=/usr/local/cuda` so the JIT path is
available. The compiled kernels are cached under `~/.cache/flashinfer`, so later starts are fast.
`VLLM_ENGINE_READY_TIMEOUT_S=3600` in `local_orchestrator.sh` raises vLLM's 600 s engine start-up budget, which
loading a ~756 GB checkpoint does not fit in.

Docker (with the compose plugin, v2.x or later) must be reachable by your user. On this host the daemon is
**rootful and shared** (other tenants' containers are running on it), so `local_orchestrator.sh` leaves
`DOCKER_HOST` unset; the image store lives under `/var/lib/docker`. The compose plugin is installed user-locally
in `~/.docker/cli-plugins/docker-compose`. The eval needs roughly 70 GB free in the Docker image store.

The 89 task images are Docker Hub images named in each task's `task.toml`. Docker Hub limits anonymous pulls per
IP, so pre-pull them ahead of the run: `docker pull mirror.gcr.io/<repo>:<tag> && docker tag mirror.gcr.io/<repo>:<tag>
<repo>:<tag> && docker rmi mirror.gcr.io/<repo>:<tag>` (the `mirror.gcr.io` pull-through cache is not rate limited
and needs no login). Harbor downloads the 89 task definitions into `~/.cache/inspect_harbor/` on first use.

### Run the eval

`local_orchestrator.sh` refuses to start without a `canhazgpu` reservation, because this class of host is
shared and no run may touch the GPUs unreserved:

```bash
canhazgpu run --gpus 8 --note "TB-2.1 GLM-5.3 DFlash2" -- ./local_orchestrator.sh
inspect view --log-dir ./logs
```

To pin a draft revision (see "Model revisions" below) export, before the command above:

```bash
export SPECULATOR=<hf snapshot dir for the revision>
export SERVED_NAME=RedHatAI/GLM-5.3-speculator.dflash2-preview   # the client addresses this name
export LOG_DIR=./logs/rev-<sha>
```

Smoke-test first with 2 tasks and 2 concurrent samples:
`canhazgpu run --gpus 8 --note "TB-2.1 GLM-5.3 DFlash2 smoke" -- bash -c 'EPOCHS=1 MAX_CONNECTIONS=2 MAX_SANDBOXES=2 ./local_orchestrator.sh --limit 2'`

Concurrency is 20 in flight, not all 89 tasks at once. This server's MLA KV pool is 979,392 tokens (`GPU KV cache
size` in `logs/serve.log`: ~90.7 GiB of FP8 weights per B200 leaves ~65 GiB per GPU for KV, and MLA replicates
the latent KV across TP ranks), and Terminal-Bench histories reach ~30-60k tokens, so 20 x 60k = 1.2M is about
1.3x the pool. 32 would be ~2x over and would evict prefix-cached agent histories late in the run, forcing a
re-prefill of the whole history on every turn. Keep `MAX_SANDBOXES` equal to `MAX_CONNECTIONS`.

### Analyse the run

```bash
# from the client venv, because collate needs inspect_ai; analyze alone uses the standard library
RUN=logs/rev-83c1f7eb        # one directory per served revision
python analyze_spec_decode.py collate "$RUN" -o "$RUN/calls.csv"
python analyze_spec_decode.py analyze "$RUN/calls.csv" -o spec_decode_report
# then the #63587 collapse audit over the same per-call CSV
python monitor_spec_decode.py audit "$RUN/calls.csv" -o spec_decode_report
```

Keep runs apart by revision: export `LOG_DIR=./logs/rev-<sha>` before `local_orchestrator.sh` (that is where the
`.eval` lands), then move `logs/serve.log` and `logs/canary.*` into the same directory afterwards. Collating a
directory that holds more than one `.eval` pools the runs, which is not what the numbers above are.

## Speculative decoding instrumentation

The acceptance metrics come from vLLM main's experimental per-request reporting, captured by Inspect.

1. `serve.sh` passes `--speculative-config '{"method":"dflash","model":"RedHatAI/GLM-5.3-speculator.dflash2-preview",
   "num_speculative_tokens":8}'` to enable the draft model. `dflash` is the method name vLLM knows for
   DFlash/DFlash2 drafts (there is no separate `dflash2` method); the speculator's `DFlash2DraftModel`
   architecture selects the dflash2 implementation (`qwen3_dflash2`) automatically, so no extra flag is needed. 8 tokens per verify step matches the speculator
   card's acceptance tables ("eight draft tokens with adaptive verification disabled"); the card's speedup
   example instead uses 7 tokens with `enable_adaptive_verification`, which changes what a "step" means and is
   not what the acceptance numbers below should be read against, so adaptive verification is left at its
   default (off) here. The draft consumes auxiliary hidden states from target layers 18, 30, 42, 54, 66 and 74
   (1-based), which its config carries as `aux_hidden_state_layer_ids`. `serve.sh` also passes `--per-request-spec-decode-metrics
   detailed`, which adds a `metrics.speculative_decoding` object to every chat-completion response. The object
   holds the mean acceptance length, a histogram of how many verify steps accepted exactly j draft tokens, the
   step and token counts, and the ordered per-step arrays that only the `detailed` level emits. Only
   single-sequence requests (`n == 1`) are populated, and Inspect always sends `n == 1`.
2. `run_eval.sh` passes `--log-model-api`, which makes Inspect keep the raw request and response of every model
   call under `ModelEvent.call`. Without the flag Inspect keeps only the first few calls per model plus errors.
   The OpenAI-compatible provider stores the response through `completion.model_dump()`, so the non-standard
   `metrics` field survives.
3. `analyze_spec_decode.py` reads those responses. `collate` walks `sample.events` rather than
   `sample.messages`, because compaction drops early turns from the messages. It numbers the `model` events to
   get a 1-based turn number, and writes one row per call holding the task, epoch, turn, stop reason, token
   usage (input, cache-read, output, reasoning) and every acceptance field. `analyze` then reports:
   - MAL, defined as `1 + accepted_draft_tokens / num_spec_steps`, where the leading 1 is the always-accepted
     bonus token. It reports a pooled value over all steps (micro), where every verify step weighs the same, and
     the unweighted mean of the per-call values (macro), where every request weighs the same, and the per-call
     distribution.
   - Draft acceptance rate, defined as `accepted_draft_tokens / num_draft_tokens`.
   - Per-position acceptance, as two rates. The overall rate is the probability that the draft token at position
     j is accepted, which is the tail of the histogram, `Σ_{i>j} hist[i] / steps`; the overall rates plus 1
     reproduce MAL. The conditional rate is the probability that position j is accepted given that position j-1
     was, `overall[j] / overall[j-1]`, the per-position hazard rate. Both rates are sliced by turn number,
     context length, output length, pass/fail and stop reason. The "exactly j" marginal probabilities stay in
     `report.json` and `acceptance_by_position.csv`.
   - Thinking against response, in token space and without a tokenizer. A completion is one contiguous token
     sequence, and each verify step emits its accepted drafts plus one bonus token, so step spans follow from
     `per_step_accepted` (the `Σ(accepted+1)` sum equals `completion_tokens`). The reasoning block is a prefix
     of the completion, and its token length is `usage.completion_tokens_details.reasoning_tokens`. MAL and both
     per-position rates are therefore reported per region. A step is attributed to the region that holds the
     midpoint of its accepted tokens, and the report states how many steps straddled the boundary.
   - MAL by turn number, by context-length and output-length bins, and by task.
   - Outlier checks, computed two ways: drop the calls above the p95 output-token count, and drop whole samples
     whose total output exceeds its p95.
   - Within-response drift, as the MAL of each decile of position within a response, and MAL for passing against
     failing samples.

   No timing or throughput metric is reported. Tokens per second and wall time depend on the host, the
   concurrency and the serving topology, so they describe only the run that produced them.

Outputs are `report.md`, `report.json` and one CSV per slice family. vLLM labels the per-request field
experimental, so its shape may change between releases.

## The DFlash/DFlash2 acceptance-collapse bug (vLLM #63587) and what this directory does about it

On vLLM 0.32.0/0.33.0, a DFlash or DFlash2 draft served with the default `FULL_AND_PIECEWISE` CUDA graphs can
silently lose all draft acceptance. **This directory does not run 0.32.0**: it serves from vLLM main
(`0.34.0rc1.dev253+gace415c06`, commit `ace415c06`), which contains the upstream fix. The failure is quiet: the output text stays correct and the task score is
unaffected, but

- a call can be dead from its first verify step (MAL ≈ 1.00), or accept for a while and then stop for the rest
  of the call with no recovery (a trailing run of zero-accepted steps in `per_step_accepted`);
- it concentrates in long or `max_tokens`-capped generations;
- it costs roughly 3x wall clock, because the request falls back to one token per forward pass while still
  drafting 8 per step;
- it poisons pooled acceptance: one collapsed call emits ~1 token per step against ~4.4 for a healthy one, so
  collapsed calls can dominate the pooled step count and drag *micro* MAL (pooled over steps) from ~3.5 to
  ~2.4 while *macro* MAL (per-call mean) stays ~4.2. Micro and macro diverging is itself a smell.

The root cause is the in-graph draft decode-metadata update path
(`vllm/v1/worker/gpu/spec_decode/speculator.py`, `supports_decode_metadata_update`). It is fixed upstream by PR
#64059 (merged 2026-11-04, in no release tag as of 2026-11-11). Affected deployments also log
`Speculative decoding (method=dflash) is enabled but no KV cache group could be identified as the draft
model's.`.

The fix (PR #64059, commit `d3a323093`) adds `DraftModelSpeculator._map_kernel_block_tables()` and calls it on
the non-FULL-graph path in `DFlashSpeculator`, so the persistent kernel block tables a FULL graph reads are
refreshed every step; before the fix only the FULL path refreshed them, and the stale tables made every draft
token get rejected. That commit is an ancestor of the vLLM commit this directory serves from, so the default
`FULL_AND_PIECEWISE` CUDA graphs are used unchanged (no `--compilation-config` override).

This directory still takes three precautions:

1. **Escape hatch in `serve.sh`**: `CUDAGRAPH_MODE` is unset by default (vLLM's default graphs). Setting
   `CUDAGRAPH_MODE=PIECEWISE` (or `NONE` for an `--enforce-eager`-style run) reproduces the pre-fix workaround
   if a future build regresses. The mode actually in effect is echoed by `local_orchestrator.sh` from
   `serve.log`.
2. **Live canary** (`monitor_spec_decode.py canary`, started by `local_orchestrator.sh`): one capped-length
   request (`max_tokens=1024`, temperature 1.0, top_p 0.95, reasoning effort max) every 2 minutes for the
   duration of the eval. Each response's `metrics.speculative_decoding` is checked for MAL ≈ 1.00 with ≥ 4
   verify steps, for a trailing zero-run of ≥ 4 steps on calls of ≥ 8 steps, and for MAL falling below 0.6x the
   running healthy median. Probes go to `logs/canary.jsonl`, hits to `logs/collapse_detected.jsonl`, and the
   orchestrator prints a warning at teardown if any hit. The canary deliberately sits outside Inspect: it is a
   *signal*, not the evidence.
3. **Definitive post-hoc audit** (`monitor_spec_decode.py audit` over the collated per-call CSV): counts
   collapsed calls and the share of verify steps they hold, and recomputes micro MAL, macro MAL and the
   per-position acceptance curve with and without them, plus `collapsed_calls.csv` for the offenders. The audit
   is reported next to the headline acceptance numbers, so a reader can tell whether the workaround held.

If the audit finds collapsed calls, the honest reading is the "excluding collapsed" column plus an explicit note
that the run hit #63587 anyway (e.g. a graph-capture or backend regression); the raw pooled numbers understate
acceptance.

## Deviations from the prompt's suggested flags

- `--tokenizer-mode glm5_next`: this exists in vLLM main (0.34.0rc1) but NOT in 0.32.0, whose choices are
  `auto`, `cohere`, `deepseek_v32`, `deepseek_v4`, `hf`, `inkling`, `kimi_k3`, `mistral`. On this checkpoint both
  resolve to the same tokenizer (`CachedTokenizersBackend`, 154,856 tokens, rendering
  `[gMASK]<sop><|system|>Reasoning Effort: Max<|user|>…`), so the choice is not load-bearing; `glm5_next` is
  used because it names the model family explicitly.
- `--disable-flashinfer-autotune` does exist in main, but is left at its default (autotune on): the autotune
  result is cached in `~/.cache/vllm/flashinfer_autotune_cache/`, so it costs one startup, not every startup.
- `--kv-cache-dtype fp8_e4m3` is written as `--kv-cache-dtype fp8`, which vLLM maps to `fp8_e4m3` and which is
  the spelling used by the GLM-5.3 siblings.
- `--reasoning-parser glm47` + `--tool-call-parser glm47` + `--enable-auto-tool-choice` are GLM-5.x's parsers
  (`glm47_moe_reasoning_parser`, `glm47_moe_tool_parser`).

## Patches for upstream

None are needed for the dataset. Two tooling notes, both inherited from the sibling directories:

1. **Context compaction can fail, at either threshold, and the window it uses is racy.** The `vllm` provider
   learns the served `max_model_len` from `/v1/models` during the first `generate()`, but the ReAct agent's
   compaction resolves its threshold (0.9 x window) on the first `compact_fn`, which can run before that call.
   `CompactionEdit` only clears old tool results and thinking blocks, keeping the last 3 tool-use pairs and all
   conversation text, so a trajectory whose own messages exceed the threshold cannot be reduced and the sample
   dies with `RuntimeError: Compaction insufficient`. Inspect records that as a sample error, not a failure.
2. **`--per-request-spec-decode-metrics` is experimental** in vLLM main. The response shape may change, and
   only single-sequence (`n == 1`) requests are populated.

### Model revisions behind these numbers

Hugging Face revisions are mutable in practice, so pin them. The results in this directory were produced with:

| role | repo | revision served |
|---|---|---|
| verifier | `zai-org/GLM-5.3` | `ba32f8c19c8738e2c57c71798c601d477a7bf844` (unchanged since 2026-10-14) |
| draft | `RedHatAI/GLM-5.3-speculator.dflash2-preview` | `83c1f7eb0ee7f12b3b853206a712c8b57362edfa` (2026-11-13) |

That draft revision is the validated 4-epoch checkpoint ("Replace draft weights with validated 4-epoch DFlash2
checkpoint"). Relative to the earlier preview revision `3325df9c8ddad6b11afc9623ca6c3833d70fa4ef`, which an
earlier run of this same directory used (numbers kept below for comparison), the weights were replaced —
identical size, different sha256 (`ab5a2e09…` vs `2d8c6616…`) — the architecture and every serving-relevant config
field are unchanged (`block_size` 9, aux layers `[18,30,42,54,66,74]`, 5 layers, hidden 6144; only
`speculators_version` moved 0.8.0.dev222 → 0.9.0a95), and the card is byte-identical. Its own validation numbers
improve (accept_len 3.566 → 3.662, accept_rate 41.3% → 42.6%), which is what this re-run measures on agent
trajectories.

`serve.sh` needs no change between revisions: download the one you want (`hf download <repo> --revision <sha>`) and
pass the snapshot directory as `SPECULATOR` together with `SERVED_NAME=RedHatAI/GLM-5.3-speculator.dflash2-preview`
(`SERVED_NAME` exists because the client addresses the model by name, not by checkpoint path).

## Results

All 89 tasks, 1 epoch each, in a single run on revision `83c1f7eb` (2026-11-20 17:55:35 → 21:34:05 UTC,
**3 h 38 m** wall clock), produced by

`temperature=1.0, top_p=0.95, reasoning_effort=max, max_tokens=65536 (per turn), max_connections=20,
max_sandboxes=20, time_limit=7200 s, client_timeout=7200, override_cpus=0, epochs=1, TP=8 DP=1,
max_model_len=262144, kv-cache-dtype fp8, DFlash2 draft with 8 speculative tokens, adaptive verification off`

| metric | value |
|---|---|
| accuracy over all 89 samples (pass@1) | **0.865 (77 of 89)** |
| stderr | 0.0364 |
| sample errors | 0 |
| time-limit hits (7200 s) | 6 (3 failed, 3 passed anyway: `regex-chess`, `schemelike-metacircular-eval`, `train-fasttext`) |
| per-turn `max_tokens` truncations | 10 model calls |
| agent turns per sample: median / mean / max | 26 / 41 / 276 |
| wall clock | 3 h 38 m, 20 samples in flight |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 3,253,131 | 84,330 | 69,107 |
| median | 1,250,392 | 58,135 | 47,731 |
| max output | — | 678,191 | — |

Input tokens are cumulative over agent turns (the history is resent every turn) and include cache reads.
Reasoning is ~82% of output tokens, which is why acceptance on the thinking region dominates the pooled numbers.

**Not comparable with the GLM-5.3 model card's 88.2** (Claude Code 2.1.207 harness, 6 h timeout, top_p 1.0) or with
the sibling `RedHatAI_GLM-5.3-MXFP4xFP8` directory's 0.888 (two phases, the second at a 14400 s limit).

### Draft acceptance (DFlash2 on real agent trajectories)

`analyze_spec_decode.py` over the run: **3,690 model calls, 3,688 carrying `metrics.speculative_decoding`** (the
two without are errored calls in time-limit samples), **2,483,916 verify steps**, 0 histogram/step-count
mismatches.

| headline metric | value |
|---|---|
| micro MAL (1 + accepted/steps) | **3.020** |
| mean first-token acceptance rate | 0.666 |
| macro MAL (unweighted mean of per-call values) | 3.250 |
| median per-call MAL | 3.053 |
| mean conditional acceptance rate | 0.709 |

Per-call MAL: median 3.053, p05 2.298, p95 4.941.

| position | overall acceptance | conditional acceptance |
|---|---|---|
| 0 | 0.666 | 0.666 |
| 1 | 0.443 | 0.666 |
| 2 | 0.299 | 0.675 |
| 3 | 0.208 | 0.694 |
| 4 | 0.149 | 0.716 |
| 5 | 0.109 | 0.736 |
| 6 | 0.082 | 0.753 |
| 7 | 0.063 | 0.764 |

| region | verify steps | share of steps | MAL | position-0 acceptance |
|---|---|---|---|---|
| thinking | 2,172,501 | 87.5% | 2.832 | 0.651 |
| response | 311,415 | 12.5% | 4.332 | 0.774 |

Acceptance is much higher in the response region (mostly tool-call JSON). 371 of 2.48 M steps straddled the
boundary and were attributed by the midpoint of their accepted tokens.

Passing samples average slightly higher acceptance than failing ones (micro MAL 3.042 vs 2.943, macro 3.268 vs
3.191), consistent with harder tasks producing less predictable text, but the separation is small. Dropping calls above the p95 output length moves micro MAL from 3.020 to 3.063;
dropping whole samples above their p95 output moves it to 3.040, so long outliers are not driving the result.

### The #63587 acceptance-collapse audit: clean

- **Live canary** (one capped 1024-token probe every 2 minutes for the whole 3 h 38 m run): **91 probes, 91 OK,
  0 collapse flags.** MAL median 3.39, p05 2.64, p95 4.83 (min 2.43, max 5.26) over a median of 303 verify steps;
  longest trailing zero-accepted run in any probe was 4.
- **Post-hoc audit** (`monitor_spec_decode.py audit`, full output in `spec_decode_report/collapse_audit.md`):
  **0 collapsed calls** of 3,688, so "all calls" and "excluding collapsed" are identical above.

The run used vLLM's default `FULL_AND_PIECEWISE` CUDA graphs (the draft captures FULL graphs), i.e. exactly the
configuration that fails on 0.32.0/0.33.0; the build served here contains the #64059 fix.

### Re-run on the validated checkpoint: head-to-head with revision `3325df9c`

The same protocol, same serve flags, same task pin, only the draft weights changed:

| metric | `3325df9c` (preview, 2026-11-11) | `83c1f7eb` (validated 4-epoch, 2026-11-20) |
|---|---|---|
| accuracy (pass@1) | 0.854 (76/89) | **0.865 (77/89)** |
| stderr | 0.0376 | 0.0364 |
| micro MAL | 2.938 | **3.020** (+2.8%) |
| macro MAL | 3.154 | **3.250** (+3.0%) |
| median per-call MAL | 2.971 | **3.053** |
| position-0 acceptance | 0.659 | **0.666** |
| thinking-region MAL | 2.746 | **2.832** |
| response-region MAL | 4.127 | **4.332** |
| verify steps | 2,566,160 | 2,483,916 |
| collapsed calls | 0 of 3,849 | 0 of 3,688 |
| sample errors | 0 | 0 |
| time-limit hits | 7 | 6 |
| wall clock | 3 h 19 m | 3 h 38 m |

The +3% acceptance is the same direction and rough magnitude as the checkpoint's own validation improvement
(accept_len +2.7%), which is the expected size of the effect. The score move (76 → 77) is well inside one standard
error (≈3.6 points), and the per-task churn confirms it is noise rather than a capability change:

- **gained (4):** `dna-insert`, `model-extraction-relu-logits`, `nginx-request-logging`, `path-tracing`
- **lost (3):** `extract-moves-from-video`, `protein-assembly`, `sanitize-git-repo`
- **failed in both (9):** `filter-js-from-html`, `gcode-to-text`, `llm-inference-batching-scheduler`,
  `make-doom-for-mips`, `pytorch-model-cli`, `qemu-alpine-ssh`, `qemu-startup`, `raman-fitting`,
  `video-processing`

Wall clock grew slightly despite the better acceptance because two samples ran close to the 7200 s cap.

### Files produced

- `logs/rev-83c1f7eb/` — this run: `*.eval` (`--log-model-api` raw payloads), `calls.csv`, `serve.log`,
  `canary.jsonl`.
- `logs/rev-3325df9c/` — the earlier preview-weights run, same layout, kept for the comparison above.
- `logs/smoke-vllm032/`, `logs/smoke-nightly/` — the two 2-task smoke runs (vLLM 0.32.0 + PIECEWISE graphs, then
  main + default FULL graphs), both 2/2 passed.
- `spec_decode_report/` — `report.md`, `report.json`, `acceptance_by_position.csv`,
  `mal_by_{turn,context,output,epoch,pass,stop_reason,task}.csv`, plus `collapse_audit.md`, `collapse_audit.json`
  and (when non-empty) `collapsed_calls.csv`.

`logs/` and `spec_decode_report/` are run artifacts and stay out of git, as the repo's `.gitignore` intends; only
the 8 code/doc files are committed.
