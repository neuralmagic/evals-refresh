# RedHatAI/Qwen3.8-27B-speculator.dspark — Terminal-Bench 2.1

| | |
|---|---|
| Task | `inspect_harbor/terminal_bench_2_1` (89 tasks, Harbor hub package `terminal-bench/terminal-bench-2-1` pinned to digest `sha256:7d7bdc1c…`) |
| Category | agentic-and-coding (subclass: swe-agent) |
| Exec tier | `agent` (one prebuilt Docker container per task, bash and python tools, hidden verifier) |
| vLLM recipe | https://recipes.vllm.ai/Qwen/Qwen3.8-27B |
| Target model | https://huggingface.co/Qwen/Qwen3.8-27B |
| Draft (speculator) | https://huggingface.co/RedHatAI/Qwen3.8-27B-speculator.dspark (DSpark, ~4 GB, `num_speculative_tokens=8`) |
| Task source | https://hub.harborframework.com/datasets/terminal-bench/terminal-bench-2-1 |

This directory measures draft-model acceptance for DSpark on real agent trajectories. It is not a leaderboard
entry. `serve.sh` runs the target with the DSpark draft model and with `--per-request-spec-decode-metrics
detailed`. `run_eval.sh` passes Inspect's `--log-model-api`, so the log keeps the raw response of every model
call. `analyze_spec_decode.py` reads those responses offline.

The task, agent and generation settings match `Qwen_Qwen3.8-27B/agentic-and-coding/terminal-bench-2.1`:

- Inspect's ReAct agent (`bash`, `python`, `update_plan`, `submit`; 300 s tool timeout; automatic context
  compaction), not the Terminus 2 agent used by the leaderboard and the Qwen model card.
- One uniform `--time-limit 7200` instead of Harbor's per-task agent timeouts.
- Containers run without Harbor's CPU cap (`override_cpus=0`) and with `inspect_harbor`'s 6 GB memory floor.
- Per-turn `max_tokens` 65536, with sampling from the base model's `generation_config.json` (temp 1.0, top_p
  0.95, top_k 20) and reasoning effort xhigh.

Three settings differ from that run, so the score is not comparable with it:

- Epochs: 1 (`pass@1`) instead of 3, the repo default and enough for an acceptance study.
- Serving: one TP=4 replica on 4 H100s instead of TP=2 x DP=4 on 8. The KV pool holds 2,119,249 tokens, and
  concurrency is capped at 9 so that `concurrency x max_model_len` stays within 1.2x the pool (9 x 262,144 =
  1.11x). The base run had 267 samples in flight. On one replica the 7200 s wall-clock limit leaves less time
  per sample, so read the score as a check that serving works, not as a ranking.
- Speculative decoding: the DSpark draft proposes tokens and the target verifies them. This changes what
  generation costs, not the task, the scaffold or the sampling. This directory reports the acceptance numbers,
  with the score next to them.

## Files

- `serve.sh` runs the target with vLLM and the DSpark draft model. The vLLM serve arguments live here: recipe
  parallelism, context length, parsers, `--speculative-config` and `--per-request-spec-decode-metrics`.
- `run_eval.sh` runs the Inspect task against that server. The Inspect parameters live here: task and package
  digest, epochs, sampling, per-turn max tokens, concurrency, sandbox count, time limit and `--log-model-api`.
- `analyze_spec_decode.py` collates the raw responses out of the `.eval` logs into a per-call CSV and computes
  the acceptance analysis (MAL, per-position rates, thinking against response, slices, outliers). It is the one
  file beyond the standard set, and the deliverable of this directory.
- `server_requirements.txt` and `client_requirements.txt` are `pip freeze` of the vLLM and Inspect venvs that
  produced the results below. The client venv is the `inspect-harbor` one (see Run).
- `local_orchestrator.sh` runs everything on one host. It checks the GPU reservation, activates the venvs,
  points Docker at the rootless daemon, starts `serve.sh` in the background, runs `run_eval.sh` and tears down.
  Modify this file only, to match the environment you run in.

## Run

### Setup (once per host)

Create a server and a client environment as below. The commands use the paths that `local_orchestrator.sh`
activates; if you keep the environments elsewhere, change the paths in both places.
`server_requirements.txt` and `client_requirements.txt` are the exact `pip freeze` of the environments that
produced the results below (Python 3.12, host details in their headers). Installing from them reproduces those
environments; the commented alternative gives an equivalent fresh install.

```bash
# server: vLLM 0.32.0, the first release with --per-request-spec-decode-metrics
python3.12 -m venv ~/.venvs/vllm && source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt          # or: pip install vllm==0.32.0
# client: Inspect
python3.12 -m venv ~/.venvs/inspect-harbor && source ~/.venvs/inspect-harbor/bin/activate
pip install -r client_requirements.txt          # or:
# pip install "inspect-harbor==1.0.0" "inspect-ai==0.3.283" httpx2 "openai==3.14.0"
```

`inspect-harbor` pulls in `litellm`, which pins `openai<3`, while Inspect's OpenAI-compatible providers need
`openai>=3`. Installing `openai==3.14.0` last overrides the pin. pip prints a conflict warning, which is
harmless here because Inspect's agent path never imports `litellm`. `httpx2` is imported by `inspect-ai` but
not declared.

Both models are fetched from the Hugging Face Hub on first use into the usual cache (`HF_HOME` if set). The
target is ~54 GB in 18 safetensors files; the speculator is ~4 GB. Both are public and un-gated. Export
`HF_TOKEN` in your shell before running (never in the repo) to avoid anonymous rate limits. huggingface_hub 2.x
keeps large files in a content-addressed store under `<HF_HOME>/hub/blobs/` and leaves each model's
`blobs/<sha>` entries as symlinks into it, so `du -sh` on a model directory under-reports by orders of
magnitude. Check the files with `ls -laL <snapshot>/*.safetensors` instead.

Docker (with the compose plugin) must be reachable by your user. `local_orchestrator.sh` exports `DOCKER_HOST`
for a rootless daemon (`unix:///run/user/<uid>/docker.sock`, image store under `~/.local/share/docker`). With a
rootful daemon, drop that export. Rootless Docker needs a runc runtime with `NoNewKeyring` in `daemon.json` and
cannot apply CPU limits, hence `-T override_cpus=0` in `run_eval.sh`.

### Run the eval

`local_orchestrator.sh` refuses to start without a `canhazgpu` reservation, because this class of host is
shared and no run may touch the GPUs unreserved:

```bash
canhazgpu run --gpus 4 --note "TB-2.1 DSpark" -- ./local_orchestrator.sh
inspect view --log-dir ./logs
```

Smoke-test first with 2 tasks and 2 concurrent samples:
`canhazgpu run --gpus 4 -- bash -c 'EPOCHS=1 MAX_CONNECTIONS=2 MAX_SANDBOXES=2 ./local_orchestrator.sh --limit 2'`

Docker needs roughly 70 GB free in its image store: one prebuilt image per task, 21 GB compressed. On the first
run Harbor downloads the 89 task definitions into `~/.cache/harbor/tasks/packages/terminal-bench/`.

### Analyse the run

```bash
# from the client venv, because collate needs inspect_ai; analyze alone uses the standard library
python analyze_spec_decode.py logs -o spec_decode_report
# or in two steps, to reuse the CSV across analyses
python analyze_spec_decode.py collate logs -o calls.csv
python analyze_spec_decode.py analyze calls.csv -o spec_decode_report
```

## Speculative decoding instrumentation

The acceptance metrics come from vLLM 0.32.0's experimental per-request reporting, captured by Inspect.

1. `serve.sh` passes `--speculative-config '{"method":"dspark","model":…,"num_speculative_tokens":8}'` to
   enable the draft model, with 8 tokens per verify step as the recipe's "DSpark (opt-in)" section specifies.
   It also passes `--per-request-spec-decode-metrics detailed`, which adds a `metrics.speculative_decoding`
   object to every chat-completion response. The object holds the mean acceptance length, a histogram of
   how many verify steps accepted exactly j draft tokens, the step and token counts, and the ordered per-step
   arrays that only the `detailed` level emits. Only single-sequence requests (`n == 1`)
   are populated, and Inspect always sends `n == 1`.
2. `run_eval.sh` passes `--log-model-api`, which makes Inspect keep the raw request and response of every model
   call under `ModelEvent.call`. Without the flag Inspect keeps only the first few calls per model plus errors.
   The OpenAI-compatible provider stores the response through `completion.model_dump()`, so the non-standard
   `metrics` field survives.
3. `analyze_spec_decode.py` reads those responses. `collate` walks `sample.events` rather than
   `sample.messages`, because compaction drops early turns from the messages. It numbers the `model` events to
   get a 1-based turn number, and writes one row per call holding the task, epoch, turn, stop reason, token
   usage (input, cache-read, output, reasoning) and every acceptance field. `analyze` then reports:
   - MAL, defined as `1 + accepted_draft_tokens / num_spec_steps`, where the leading 1 is the always-accepted
     bonus token. It reports a pooled value over all steps (micro), where every verify step weighs the
     same, and the unweighted mean of the per-call values (macro), where every request weighs the same,
     and the per-call distribution.
   - Draft acceptance rate, defined as `accepted_draft_tokens / num_draft_tokens`.
   - Per-position acceptance, as two rates. The overall rate is the probability that the draft token at
     position j is accepted, which is the tail of the histogram, `Σ_{i>j} hist[i] / steps`. It is also the
     model-card convention, and the overall rates plus 1 reproduce MAL. The conditional rate is the
     probability that position j is accepted given that position j-1 was, `overall[j] / overall[j-1]`, which
     is the per-position hazard rate. Either follows from the other, because the overall rate is the running
     product of the conditionals. Both rates are sliced by turn number, context length, output length,
     pass/fail and stop reason. The "exactly j" marginal probabilities stay in `report.json` and
     `acceptance_by_position.csv`.
   - Thinking against response, in token space and without a tokenizer. A completion is one contiguous token
     sequence, and each verify step emits its accepted drafts plus one bonus token, so step spans follow from
     `per_step_accepted` (the `Σ(accepted+1)` sum equals `completion_tokens`). The reasoning block is a prefix
     of the completion, and its token length is `usage.completion_tokens_details.reasoning_tokens`, which
     equals the token count of the reasoning text. MAL and both per-position rates are therefore reported per
     region. A step is attributed to the region that holds the midpoint of its
     accepted tokens, and the report states how many steps straddled the boundary, which is well under 1%.
   - MAL by turn number, by context-length and output-length bins, and by task.
   - Outlier checks, computed two ways: drop the calls above the p95 output-token count, and drop whole
     samples whose total output exceeds its p95.
   - Within-response drift, as the MAL of each decile of position within a response, and MAL for passing
     against failing samples.

   No timing or throughput metric is reported. Tokens per second and wall time depend on the host, the
   concurrency and the serving topology, so they describe only the run that produced them.

Outputs are `report.md`, `report.json` and one CSV per slice family. vLLM labels the per-request field
experimental, so its shape may change between releases.

## Results

All 89 tasks, 1 epoch each, produced by two runs with identical settings: 16 tasks first, then the remaining
73 (`logs/` holds both `.eval` files, and the analysis pools them). Every task is counted once.

With model generation config:

`temperature=1.0, top_p=0.95, top_k=20, reasoning_effort=xhigh, max_tokens=65536 (per turn), max_connections=9, max_sandboxes=9, time_limit=7200s, client_timeout=7200, override_cpus=0, epochs=1, TP=4 DP=1`

the following scores and token stats are obtained:

| metric | value |
|---|---|
| accuracy over all 89 samples (pass@1, sample errors count as failures) | 0.742 (66 of 89) |
| stderr | 0.0464 |
| accuracy over the 87 graded samples (sample errors excluded) | 0.759 (66 of 87) |
| time-limit hits (7200 s) | 3 (`caffe-cifar-10`, `extract-moves-from-video`, `gpt2-codegolf`, all failed) |
| samples with a turn truncated at max_tokens | 5 |
| sample errors | 2, both `RuntimeError: Compaction insufficient` (`schemelike-metacircular-eval`, `largest-eigenval`; see Patches) |
| agent turns per sample: median / mean / max | 32 / 73 / 551 |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 7,326,555 | 119,103 | 90,342 |
| median | 1,695,537 | 47,498 | 35,493 |
| max | 92,915,144 | 766,670 | 565,343 |

Input tokens are cumulative over agent turns, because the history is resent every turn, and they include
cache reads.

**The 0.742 is not comparable with the base run's 0.493 avg@3.** The task, scaffold and sampling match, but that
run served 267 samples at once on 8 H100s and this one serves 9 at a time on 4, so each sample here gets far
more generation throughput inside the same 7200 s limit. The gap is mostly that: of the 31 tasks the base run
failed in all three of its epochs, this run passed 16 (`build-pov-ray`, `chess-best-move`, `cobol-modernization`,
`compile-compcert`, `fix-ocaml-gc`, `mailman`, `make-mips-interpreter`, `path-tracing`, `path-tracing-reverse`,
`query-optimize`, `regex-chess`, `torch-pipeline-parallelism`, `tune-mjcf`, `video-processing`,
`winning-avg-corewars`, `write-compressor`). In the other direction, 15 of this run's 23 non-passes are on that
same always-failing list, so 8 are failures on tasks the base run solved at least once. Speculative decoding
changes what generation costs, not what the model can do, so neither number should be read as evidence about
DSpark's effect on capability.

### Draft acceptance

`analyze_spec_decode.py` over both logs: 6,482 of 6,483 model calls carried `metrics.speculative_decoding` (one
call did not), across 3,134,551 verify steps, with 0 histogram/step-count mismatches.

| headline metric | value |
|---|---|
| micro MAL (1 + accepted/steps) | 3.381 |
| mean first-token acceptance rate | 0.708 |
| macro MAL (unweighted mean of per-call values) | 3.539 |
| median per-call MAL | 3.366 |
| mean conditional acceptance rate | 0.740 |

Per-call MAL: median 3.366, p05 2.528, p95 5.153. Micro MAL weights every verify step equally, so long
responses dominate it; macro MAL weights every request equally. They differ because call length correlates
with acceptance (Spearman -0.119 over all 6,482 calls).

| position | overall acceptance | conditional acceptance |
|---|---|---|
| 0 | 0.708 | 0.708 |
| 1 | 0.501 | 0.708 |
| 2 | 0.360 | 0.718 |
| 3 | 0.262 | 0.728 |
| 4 | 0.196 | 0.747 |
| 5 | 0.149 | 0.763 |
| 6 | 0.115 | 0.772 |
| 7 | 0.089 | 0.773 |

The conditional column is the per-position hazard rate, and it rises with position, so acceptance is better
than geometric: later draft tokens are accepted slightly more often than earlier ones, once their predecessor
was. The overall column is the model-card convention, and its sum plus 1 equals micro MAL.

| region | verify steps | share of steps | MAL | position-0 acceptance |
|---|---|---|---|---|
| thinking | 2,570,857 | 82.0% | 3.130 | 0.680 |
| response | 563,694 | 18.0% | 4.529 | 0.838 |

Acceptance is much higher in the response text than in the thinking text. The response region is mostly
tool-call JSON, which is more predictable than reasoning prose. 5,678 of 3,134,551 steps straddled the boundary
and were attributed by the midpoint of their accepted tokens.

MAL rises with context length: 2.987 below 4k tokens, 3.139 at 4-16k, 3.206 at 16-32k, 3.242 at 32-64k, 3.385
at 64-128k and 3.586 above 128k. MAL shows no trend in turn number (2.91 to 3.47 across bins). Within a
response, MAL rises from 3.21 in the first decile to 3.98 in the last. Removing calls or samples above the p95
output length moves micro MAL from 3.381 to 3.372 and 3.327, so long outliers do not drive the result. Passing
samples average MAL 3.399 against 3.363 for failing samples, so acceptance does not predict task success here.

## Patches for upstream

None are needed for the dataset. Two tooling issues are known, both present in the sibling task dirs and
relevant only if this POC is extended.

1. **Context compaction can fail, at either threshold, and the window it uses is racy.** The `vllm` provider
   learns the served `max_model_len` from `/v1/models` during the first `generate()`, but the ReAct agent's
   compaction resolves its threshold (0.9 x window) on the first `compact_fn`, which can run before that call.
   Both outcomes occur in this dir: `schemelike-metacircular-eval` kept Inspect's 128,000 default and a
   threshold of 115,200, while `largest-eigenval` discovered the served 262,144 and used 235,929. `CompactionEdit`
   only clears old tool results and thinking blocks, keeping the last 3 tool-use pairs and all conversation
   text, so a trajectory whose own messages exceed the threshold cannot be reduced and the sample dies with
   `RuntimeError: Compaction insufficient`. Inspect records that as a sample error, not a failure. Both samples
   above failed this way: 118,867 tokens against 115,200, and 237,577 against 235,929. No CLI or env override
   exists. Pinning the window needs `set_model_info()` in Python, or an upstream fix that re-resolves the
   threshold after registration. `inspect_harbor` hardcodes `CompactionEdit()` and could expose the threshold
   as a task arg.
2. **`--per-request-spec-decode-metrics` is experimental** in vLLM 0.32.0. The response shape may change, and
   only single-sequence (`n == 1`) requests are populated.
