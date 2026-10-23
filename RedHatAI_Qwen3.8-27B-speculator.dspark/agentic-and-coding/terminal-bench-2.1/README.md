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

**These are smoke-test numbers.** The run covered 16 of the 89 tasks, the first 16 in dataset order (the
dataset is not shuffled), with 1 epoch. That prefix is not a random sample, and 8 of the 16 are tasks the base
Qwen3.8-27B run failed in all three of its epochs. Rerun all 89 tasks before quoting this score or these
acceptance numbers.

With model generation config:

`temperature=1.0, top_p=0.95, top_k=20, reasoning_effort=xhigh, max_tokens=65536 (per turn), max_connections=9, max_sandboxes=9, time_limit=7200s, client_timeout=7200, override_cpus=0, epochs=1, TP=4 DP=1`

the following scores and token stats are obtained:

| metric | value |
|---|---|
| accuracy over all 16 samples (sample errors count as failures) | 0.688 (11 of 16) |
| stderr | 0.1159 |
| accuracy over the 15 graded samples (sample errors excluded) | 0.733 (11 of 15) |
| time-limit hits (7200 s) | 1 (`caffe-cifar-10`, failed) |
| turns truncated at max_tokens | 1 sample |
| sample errors | 1 (`schemelike-metacircular-eval`, `RuntimeError: Compaction insufficient`, see Patches) |
| agent turns per sample: median / mean / max | 42 / 79 / 298 |
| tasks passing | kv-store-grpc, log-summary-date-ranges, model-extraction-relu-logits, openssl-selfsigned-cert, path-tracing, pypi-server, regex-chess, regex-log, torch-pipeline-parallelism, torch-tensor-parallelism, write-compressor |
| tasks failing | caffe-cifar-10 (time limit), dna-assembly, mteb-leaderboard, qemu-alpine-ssh |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 7,300,363 | 128,303 | 97,703 |
| median | 3,287,555 | 80,984 | 59,916 |
| max | 37,092,102 | 464,263 | 399,566 |

Input tokens are cumulative over agent turns, because the history is resent every turn. They include
cache reads.

Serving did not degrade the model on this prefix. Of the 8 tasks the base run failed in all three epochs,
this run passed 4 (`path-tracing`, `regex-chess`, `torch-pipeline-parallelism`, `write-compressor`). The one
failure on a task the base run did pass is `caffe-cifar-10`, which hit the 7200 s limit, so it reflects the
single-replica time budget rather than a serving fault.

### Draft acceptance

`analyze_spec_decode.py` over the same log: 1,267 model calls and 618,406 verify steps, all of them carrying
`metrics.speculative_decoding` (1267 of 1267), with 0 histogram/step-count mismatches.

| headline metric | value |
|---|---|
| micro MAL (1 + accepted/steps) | 3.319 |
| mean first-token acceptance rate | 0.701 |
| macro MAL (unweighted mean of per-call values) | 3.553 |
| median per-call MAL | 3.347 |
| mean conditional acceptance rate | 0.731 |

Per-call MAL: median 3.347, p05 2.581, p95 5.197. Micro MAL weights every verify step equally, so long
responses dominate it; macro MAL weights every request equally. They differ here because call length
correlates with acceptance (Spearman -0.234).

| position | overall acceptance | conditional acceptance |
|---|---|---|
| 0 | 0.701 | 0.701 |
| 1 | 0.493 | 0.703 |
| 2 | 0.352 | 0.713 |
| 3 | 0.255 | 0.726 |
| 4 | 0.188 | 0.738 |
| 5 | 0.142 | 0.752 |
| 6 | 0.107 | 0.758 |
| 7 | 0.082 | 0.760 |

The conditional column is the per-position hazard rate, and it rises with position, so acceptance is better
than geometric. The overall column is the model-card convention: its sum plus 1 equals micro MAL.

| region | verify steps | share of steps | MAL | position-0 acceptance |
|---|---|---|---|---|
| thinking | 512,824 | 82.9% | 3.051 | 0.673 |
| response | 105,582 | 17.1% | 4.624 | 0.836 |

Draft acceptance is far higher in the response text than in the thinking text. The response region here is
mostly tool-call JSON, which is more predictable than reasoning prose. 1,091 of 618,406 steps straddled the
boundary and were attributed by the midpoint of their accepted tokens.

MAL by context length rises with context: 3.036 below 4k tokens, 3.173 at 32-64k, 3.377 at 64-128k and 3.568
above 128k. MAL shows no trend in turn number (micro 2.87 to 3.69 across bins, apart from the 16-call turn-5
bin at 4.62). Within a response, MAL rises from 3.09 in the first decile to 3.89 in the last. Removing calls
or samples above the p95 output length moves micro MAL from 3.319 to 3.302 and 3.294, so long outliers do not
drive the result. Passing samples average MAL 3.423 against 3.230 for failing samples.

## Patches for upstream

None are needed for the dataset. Two tooling issues are known, both present in the sibling task dirs and
relevant only if this POC is extended.

1. **Inspect's vLLM context-window discovery loses a race with compaction.** The `vllm` provider learns the
   served `max_model_len` from `/v1/models` during the first `generate()`, but the ReAct agent's compaction
   resolves its threshold (0.9 x window) on the first `compact_fn`, which runs before that call. Every sample
   therefore uses Inspect's 128,000 default, and a threshold of 115,200, instead of the served 262,144 and
   235,929. `CompactionEdit` only clears old tool results and thinking blocks, so a long trajectory eventually
   cannot be reduced, and the sample dies with `RuntimeError: Compaction insufficient`. Inspect records that as
   a sample error. One sample here, `schemelike-metacircular-eval`, failed this way. No CLI or env override
   exists. Pinning the window needs `set_model_info()` in Python, or an upstream fix that re-resolves the
   threshold after registration. `inspect_harbor` hardcodes `CompactionEdit()` and could expose the threshold
   as a task arg.
2. **`--per-request-spec-decode-metrics` is experimental** in vLLM 0.32.0. The response shape may change, and
   only single-sequence (`n == 1`) requests are populated.
