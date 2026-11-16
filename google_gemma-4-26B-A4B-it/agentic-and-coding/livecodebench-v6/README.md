# google/gemma-4-26B-A4B-it — LiveCodeBench v6

| | |
|---|---|
| Task | `inspect_evals/livecodebench` (1,055 problems, full `release_v6`) |
| Category | agentic-and-coding (subclass: code-gen) |
| Exec tier | `sandbox` — one Docker container per sample for test execution |
| vLLM recipe | https://recipes.vllm.ai/Google/gemma-4-26B-A4B-it |

This is the single-shot protocol behind the model card's LiveCodeBench v6 number, not the 100-task
agentic Harbor sample in this repo's other `livecodebench` dirs. One generation per problem, and a
problem scores 1 only when every public and private test passes. The model card reports 77.1%.

The prompt and comparison rules follow the official LiveCodeBench generic OpenAIChat variant. One
execution difference remains: this implementation runs each test in a fresh process, while the
official harness reuses one process and module across a problem's inputs. A solution that relies on
state across calls can therefore score differently.

## Files

- `serve.sh` — deploys the model with a vLLM server. vLLM-serve arguments live here
  (parallelism, context length, reasoning/tool parsers), taken from the official recipe.
- `run_eval.sh` — runs the Inspect task against that server. Inspect-side params live here
  (task, epochs, sampling params, per-request max tokens, concurrency, sandbox count, time limit).
- `assets/generate_config.json` — per-request `chat_template_kwargs` that enable thinking.
- `assets/tool_chat_template_gemma4.jinja` — vLLM's Gemma 4 tool-calling chat template.
- `client_requirements.txt` / `server_requirements.txt` — pins for the two environments. The client
  environment also needs the local `neuralmagic/inspect_evals` checkout installed first.
- `local_orchestrator.sh` — runs everything in your local dev environment: activates the
  venvs, sets GPUs, starts `serve.sh` in the background, runs `run_eval.sh`, tears down.
  **This is the only file you should modify** to match the environment you run in.

## Run

### Setup (once per host)

The LiveCodeBench task is not in a released `inspect_evals`; install the local checkout of the
`livecodebench-v6` branch of the neuralmagic fork.

```bash
# server: vLLM >= 0.25.0 for Gemma 4 26B-A4B
python3.12 -m venv ~/.venvs/vllm && source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt          # or: pip install vllm
# client: Inspect with the LiveCodeBench v6 task from the local fork checkout
python3.12 -m venv ~/.venvs/inspect && source ~/.venvs/inspect/bin/activate
pip install -e /path/to/inspect_evals
pip install -r client_requirements.txt
```

The fork branch is not pushed yet, so use the existing local checkout. If that checkout is lost,
this client environment cannot be recreated from this repo alone until the branch is pushed.

When the branch is pushed, replace the editable install with a commit pin in
`client_requirements.txt`. `local_orchestrator.sh` refuses to start if `inspect-evals` is not
installed from `neuralmagic/inspect_evals` or if the `inspect_evals/livecodebench` task is missing.

Model weights and the dataset are fetched from the Hugging Face Hub on first use into the usual
cache (`HF_HOME` if set). Export `HF_TOKEN` in your shell before running (never in the repo).
The dataset is public but large (about 4.5 GB).

### Run the eval

```bash
./local_orchestrator.sh
inspect view --log-dir ./logs
```

Always smoke-test first: `EPOCHS=1 ./local_orchestrator.sh --limit 2`

## Results

Not run yet.

## Patches for upstream

The full `release_v6` task is implemented on branch `livecodebench-v6` of
https://github.com/neuralmagic/inspect_evals. Upstream `inspect_evals` no longer accepts new
implementations under `src/`, so this dir pins the fork branch until the task moves to a registered
external package.
