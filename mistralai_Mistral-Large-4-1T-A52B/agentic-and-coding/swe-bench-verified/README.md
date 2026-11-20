# Mistral Large 4 — SWE-bench Verified

| | |
|---|---|
| Task | `inspect_evals/swe_bench` (500 instances, `princeton-nlp/SWE-bench_Verified`, test split, revision `c104f840cc67f8b6eec6f759ebc8b2693d585d4a`) |
| Task version | inspect-evals 0.20.0, SWE-bench Verified 5-C |
| Sandbox | Official SWE-bench x86_64 Docker Hub images, no network access |
| vLLM recipe | [Mistral Large 4](https://recipes.vllm.ai/mistralai/Mistral-Large-4-1T-A52B) |
| Model card | [mistralai/Mistral-Large-4-1T-A52B](https://huggingface.co/mistralai/Mistral-Large-4-1T-A52B) |

The Inspect task uses its default ReAct agent with `python`, `bash_session`, `text_editor`, and `submit`; tool timeout is 210 seconds. One epoch (pass@1) is run with up to 8 concurrent samples and 8 sandboxes. We explicitly use the official SWE-bench image template, which avoids the reference-fix git-history exposure in the old default images.

**Protocol note.** The Mistral Large 4 card reports an Artificial Analysis Coding Agent Index result, not SWE-bench Verified. This exact test-split, tool-using pass@1 result is a separate measurement and is not directly comparable to the card's index.

## Files

- `serve.sh`: vLLM settings, TP8, 262,144 context, 8 sequences, Mistral parsers and text-only input limits; speculative decoding and CPU offload are disabled for a matched base/quantized comparison.
- `run_eval.sh`: task revision, sampling, response and task limits, concurrency, and timeout.
- `local_orchestrator.sh`: host-local model cache, Docker daemon, GPU allocation, and Inspect environment.
- `client_requirements.txt`: frozen Inspect/SWE-bench client environment.

## Run

### Setup

Create the client environment from `client_requirements.txt` and set `INSPECT_VENV` in `local_orchestrator.sh` to its path. The model server uses rootful Docker. The SWE-bench sandboxes use the host's rootless Docker daemon; set `DOCKER_HOST` to its socket and ensure `DOCKER_CONFIG` and the rootless Docker CLI point to the same user installation. Before the full run, load the official test images into that daemon; its 65,536-ID subordinate mapping cannot extract some matplotlib image layers until their out-of-range owners are mapped to root. Set `VLLM_CACHE_ROOT` to a writable persistent directory so later server launches reuse JIT caches.

### Run the eval

```bash
./local_orchestrator.sh --limit 2
./local_orchestrator.sh
inspect view --log-dir ./logs
```

## Configuration

Temperature 1.0, top-p 0.95, top-k unset, reasoning effort high; max 16,384 tokens per model response, 200 agent messages, 14,400 seconds per sample, 7,200-second client timeout, one epoch, and fail-on-error threshold 0.1. The server uses TP8/PP1, max model length 262,144, max sequences 8, max batched tokens 8,192, GPU memory utilization 0.85, no CPU offload, and no speculative decoding.

## Results

Base model, one epoch: **385/500 resolved (77.0% pass@1)**. The full run scored 497 cases; the three sandbox startup failures were rerun separately with the same model and sampling settings. Two passed and one did not, giving scores for all 500 unique instances.

## Patches for upstream

Use the official SWE-bench images to avoid reference fixes in the old default Epoch AI image history, as tracked in [inspect_evals#2632](https://github.com/UKGovernmentBEIS/inspect_evals/issues/2632). No local task patch is used.
