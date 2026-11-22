# shanjiaz/GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k — Terminal-Bench 2.1 acceptance

| | |
|---|---|
| Workload | `inspect_harbor/terminal_bench_2_1`, 89 agent trajectories, one epoch |
| Category / exec tier | agentic-and-coding (swe-agent) / `agent`, Docker and Inspect ReAct tools |
| vLLM recipe | https://recipes.vllm.ai/zai-org/GLM-5.3 |
| Target | `zai-org/GLM-5.3` at `ba32f8c19c8738e2c57c71798c601d477a7bf844` |
| Draft | `shanjiaz/GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k` at `69e879bb4164969d6194f456cced7eeab54a38c3` (step 8090) |
| Task package | `terminal-bench/terminal-bench-2-1` at `sha256:7d7bdc1cbedad549fc1140404bd4dc45e5fd0ea7c4186773687d177ad3a0699a` |

This directory measures draft acceptance on the observed agent trajectories. Pooled acceptance length is
**3.0782036738** across **4,363 valid model calls**. Task outcomes are outside this report's acceptance-only scope.

## Files

- `serve.sh` holds target, draft, precision, context, parser and speculative-metrics settings.
- `run_eval.sh` holds the workload pin, sampling, limits, concurrency and complete API logging.
- `local_orchestrator.sh` starts and stops the owned server; it is the only file you should modify for your environment.
- `server_requirements.txt` and `client_requirements.txt` record the environments used.
- `analyze_spec_decode.py` is the existing sibling's offline acceptance analyzer, copied unchanged.
- `monitor_spec_decode.py` is the existing sibling's acceptance-collapse monitor and audit, copied unchanged.
- `results.json` and `acceptance_by_position.csv` contain sanitized acceptance results and provenance.
- `.gitignore` keeps the setup's local model cache and environments out of version control.
- `README.md` records the protocol and reproduction steps.

## Run

### Setup

Use Linux with the NVIDIA driver, Python 3.12, `uv`, Docker and its Compose plugin. Create both environments
from the complete freezes and export the paths used by the orchestrator.

```bash
uv venv --python 3.12 .venv-server
uv pip install --python .venv-server/bin/python -r server_requirements.txt --torch-backend=auto
uv venv --python 3.12 .venv-client
uv pip install --python .venv-client/bin/python --no-deps -r client_requirements.txt
export SERVER_VENV="$PWD/.venv-server"
export CLIENT_VENV="$PWD/.venv-client"
export HF_HOME="$PWD/.cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
```

The draft requires authorized Hugging Face access. Authenticate locally, export `HF_TOKEN` in the shell,
and allow roughly 756 GB for the target's 141 shards, plus draft weights and task images. Stage the pinned
snapshots before serving offline. Keep credentials and raw trajectories private.

```bash
"$SERVER_VENV/bin/hf" download zai-org/GLM-5.3 --revision ba32f8c19c8738e2c57c71798c601d477a7bf844
"$SERVER_VENV/bin/hf" download shanjiaz/GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k --revision 69e879bb4164969d6194f456cced7eeab54a38c3
export MODEL_PATH="$HF_HUB_CACHE/models--zai-org--GLM-5.3/snapshots/ba32f8c19c8738e2c57c71798c601d477a7bf844"
export SPECULATOR="$HF_HUB_CACHE/models--shanjiaz--GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k/snapshots/69e879bb4164969d6194f456cced7eeab54a38c3"
```

### Run the eval

Reserve all eight GPUs, smoke-test two trajectories, then run the workload. Separate output directories keep
the smoke calls out of the main acceptance analysis.

```bash
canhazgpu run --gpus 8 --note "GLM-5.3 DFlash2 smoke" -- bash -c 'LOG_DIR=logs/smoke EPOCHS=1 MAX_CONNECTIONS=2 MAX_SANDBOXES=2 ./local_orchestrator.sh --limit 2'
canhazgpu run --gpus 8 --note "GLM-5.3 DFlash2 acceptance" -- bash -c 'LOG_DIR=logs/full ./local_orchestrator.sh'
"$CLIENT_VENV/bin/inspect" view --log-dir ./logs/full
"$CLIENT_VENV/bin/python" analyze_spec_decode.py logs/full -o spec_decode_report
"$CLIENT_VENV/bin/python" monitor_spec_decode.py audit spec_decode_report/calls.csv -o spec_decode_report
```

## Results

Recorded on 2026-11-22 with `temperature=1, top_p=0.95, reasoning_effort=max, max_tokens=65536,
epochs=1, time_limit=7200, client_timeout=7200, max_connections=20, max_sandboxes=20,
override_cpus=0, extra_body={"return_token_ids":true}`. Inspect `0.3.283` and inspect-harbor `1.0.0` were used.

The server used vLLM `0.34.0` (`62d4bc3c7e33b1b6c906e233e6af2d3506c482ca`), TP8/DP1, native FP8 target
weights, BF16 compute, FP8 target/draft KV, context 262,144, 128 sequences, memory utilization 0.85,
prefix caching enabled and `FULL_AND_PIECEWISE` graphs. Eight draft tokens were proposed with adaptive
verification disabled. The recorded served alias is `zai-org/GLM-5.3`.

| acceptance metric | value |
|---|---|
| Trajectories represented / valid model calls | 89 / 4,363 |
| Pooled acceptance length, `1 + accepted / steps` | **3.0782036738** |
| Pooled draft acceptance rate, `accepted / proposed` | 25.9775459230% |
| Verification steps / accepted drafts / proposed drafts | 2,747,697 / 5,710,274 / 21,981,576 |
| Mean / median per-call acceptance length | 3.7902078739 / 3.4682875264 |
| Missing metrics / corrupt metrics / histogram mismatches | 0 / 0 / 0 |
| Calls flagged for acceptance collapse | 0 |

Positions are numbered 1–8. Overall rates use all verification rounds as the denominator;
conditional rates are conditioned on acceptance of the preceding position (position 1 is unconditional).

| draft position | overall acceptance | conditional acceptance |
|---|---|---|
| 1 | 68.90% | 68.90% |
| 2 | 46.17% | 67.00% |
| 3 | 31.11% | 67.39% |
| 4 | 21.40% | 68.78% |
| 5 | 15.12% | 70.65% |
| 6 | 10.96% | 72.50% |
| 7 | 8.10% | 73.89% |
| 8 | 6.06% | 74.81% |

One trajectory ended with a compaction error; its valid earlier model calls remain included. Whole-request
counters reconcile. The unchanged analyzer's thinking/response estimates have unverified token alignment,
so phase acceptance figures are excluded.

Two trajectories acquired and used their own hidden task files. Excluding those entire tasks gives a
post-hoc 87-trajectory, 4,280-call diagnostic of MAL **3.0774688553** and draft acceptance **25.9683606917%**.
That diagnostic changes the cohort; unresolved contextual audit cases remain documented in `results.json`.
The historical MAL 2.938 uses preview revision `3325df9c`; the exact pre-finetune parent `8a96994d` has no
matched evaluation here, so these figures do not establish a finetuning improvement.

## Patches for upstream

No local task or framework patch was applied. `serve.sh` explicitly selects the legacy
`GlmMoeDsaForCausalLM` implementation through `--model-class-overrides`, matching the recorded run.
