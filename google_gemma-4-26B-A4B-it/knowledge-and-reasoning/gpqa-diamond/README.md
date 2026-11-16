# google/gemma-4-26B-A4B-it — GPQA-Diamond

| | |
|---|---|
| Task | `inspect_evals/gpqa_diamond` (198 questions, 4 choices) |
| Category | knowledge-and-reasoning (subclass: science-reasoning) |
| Exec tier | `none` — no Docker, no sandbox, no tools |
| vLLM recipe | https://recipes.vllm.ai/Google/gemma-4-26B-A4B-it |

`cot=True` (the package default): every question is asked with the package's chain-of-thought multiple-choice
prompt (`ANSWER: $LETTER`), answer choices shuffled with the package's fixed seed (`shuffle_choices=42`). The
dataset is the simple-evals `gpqa_diamond.csv`, verified by SHA256 inside `inspect_evals` (no HF revision).
The package default is 4 epochs; this run uses 3 epochs with a mean reducer (avg@3).

## Files

- `serve.sh` — deploys the model with a vLLM server. vLLM-serve arguments live here
  (parallelism, context length, reasoning/tool parsers), taken from the official recipe.
- `run_eval.sh` — runs the Inspect task against that server. Inspect-side params live here
  (task, epochs, sampling params, reasoning effort, max tokens, concurrency).
- `assets/generate_config.json` — Inspect generate config that cannot be given as a CLI flag; here it
  carries the per-request `chat_template_kwargs` that enable thinking.
- `assets/tool_chat_template_gemma4.jinja` — vLLM's Gemma 4 chat template (from the recipe), used by `serve.sh`.
- `server_requirements.txt` / `client_requirements.txt` — `pip freeze` of the vLLM and Inspect
  venvs that produced the results below, with the host (GPUs, driver, CUDA, Python) in the header.
- `local_orchestrator.sh` — runs everything in your local dev environment: activates the
  venvs, sets GPUs, starts `serve.sh` in the background, runs `run_eval.sh`, tears down.
  **This is the only file you should modify** to match the environment you run in.

## Run

### Setup (once per host)

Create a server and a client environment as below. The commands use the paths that `local_orchestrator.sh` activates;
if you keep the environments elsewhere, change the paths there. `server_requirements.txt` and
`client_requirements.txt` pin the packages for the two environments (Python 3.12). The client environment also
needs the local `neuralmagic/inspect_evals` checkout installed first, as the commands show.

```bash
# server: vLLM 0.29.0 (CUDA 13 wheels; add the matching https://download.pytorch.org/whl/<cuXXX> index if pip cannot resolve torch)
python3.12 -m venv ~/.venvs/vllm && source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt          # or: pip install vllm==0.29.0
# client: one Inspect env shared by the google/gemma-4-26B-A4B-it dirs
python3.12 -m venv ~/.venvs/inspect && source ~/.venvs/inspect/bin/activate
pip install -e /path/to/inspect_evals
pip install -r client_requirements.txt
```

The fork branch is not pushed yet, so use the existing local checkout. If that checkout is lost,
this client environment cannot be recreated from this repo alone until the branch is pushed.

The client env uses the neuralmagic inspect_evals fork, so the task code is the fork's current
version rather than the 0.20.0 that produced the Gemma-4-31B-it numbers. The task protocol is
unchanged, but account for the version difference when comparing across models.

Model weights and datasets are fetched from the Hugging Face Hub on first use into the usual cache (`HF_HOME`
if set). Export `HF_TOKEN` in your shell before running (never in the repo): the dataset `Idavidrein/gpqa` is gated,
accept its terms at https://huggingface.co/datasets/Idavidrein/gpqa with the account the token belongs to.
Without a token, anonymous Hub downloads are rate-limited.

### Run the eval

```bash
./local_orchestrator.sh
inspect view --log-dir ./logs
```

Always smoke-test first: `EPOCHS=1 ./local_orchestrator.sh --limit 5`

## Results

Not run yet. The model card reports 82.3% for GPQA Diamond.

## Patches for upstream

None.
