# mistralai/Mistral-Large-4-1T-A52B — MMLU-Pro

| | |
|---|---|
| Task | `inspect_evals/mmlu_pro` (12,032 questions, 10 choices, 14 subjects, 0-shot) |
| Category | knowledge-and-reasoning (subclass: knowledge-recall) |
| Exec tier | `none` — no Docker, no sandbox, no tools |
| vLLM recipe | https://recipes.vllm.ai/mistralai/Mistral-Large-4-1T-A52B |

The model card reports composite Artificial Analysis and coding-agent metrics rather than a directly comparable MMLU-Pro score. Treat this result as a standalone evaluation.

`fewshot=0` (the package default): each question uses the package’s chain-of-thought multiple-choice prompt (`ANSWER: $LETTER`). Dataset revision `527feea0af`.

## Files

- `serve.sh` — serves this checkpoint with the official Mistral Large 4 vLLM recipe and image.
- `run_eval.sh` — runs the unmodified Inspect task with the selected sampling and reasoning settings.
- `local_orchestrator.sh` — host-specific checkpoint paths, GPU selection, HF cache, startup, evaluation, and teardown. **This is the only file to modify for another host.**
- `server_requirements.txt` / `client_requirements.txt` — serving image and Inspect client package snapshots.

## Run

### Setup

The serving command uses the official `vllm/vllm-openai:mistral-large-4` image pinned by digest in `serve.sh`. Docker with access to all eight NVIDIA GPUs is required. The model checkpoint is expected at the path set in `local_orchestrator.sh`.

Create the Inspect client environment from `client_requirements.txt`, then set `HF_HOME` and `HF_TOKEN` in the shell as needed. The MMLU-Pro dataset is downloaded from Hugging Face on first use; export `HF_TOKEN` if required by your Hub access.

### Run the eval

```bash
EPOCHS=1 ./local_orchestrator.sh --limit 5
./local_orchestrator.sh
inspect view --log-dir ./logs
```

## Results

With model generation config:

`temperature=1.0, top_p=0.95, reasoning_effort=high, max_tokens=131072, max_connections=128, client_timeout=7200, epochs=1`

| metric | value |
|---|---|
| accuracy (pass@1) | 0.871 (10,480 of 12,032) |
| stderr | 0.003 |
| samples | 12,032 |
| truncated (`stop_reason=max_tokens`) | 1 |
| unparsed answers | 4 |
| sample errors | 0 |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 254.4 | 6,022.0 | 5,879.2 |
| median | 221 | 1,146 | 983 |
| max | 1,292 | 131,072 | 131,071 |

Output-token totals include the reasoning tokens shown separately.

## Patches for upstream

None.
