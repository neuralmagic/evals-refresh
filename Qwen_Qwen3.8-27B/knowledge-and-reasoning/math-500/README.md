# Qwen/Qwen3.8-27B — MATH-500

| | |
|---|---|
| Task | `inspect_evals/math` (500 MATH-500 test problems, zero-shot) |
| Category | knowledge-and-reasoning (subclass: math-reasoning) |
| Exec tier | `none` — no Docker, no sandbox, no tools |
| vLLM recipe | https://recipes.vllm.ai/Qwen/Qwen3.8-27B |

The 500 selected questions and reference solutions match `HuggingFaceH4/MATH-500` at revision
`6e4ed1a2a79af7d8630a6b768ec859cb5af4d3be`. Inspect loads the full MATH test set at revision
`0530c78699ea5e8eb5530600900e1f328b48acad`; `--sample-id` selects the matching questions. The model card
does not report MATH-500. The Inspect prompt and SymPy scorer differ from LightEval's prompt and math
extractor, so scores are not directly comparable. The scorer can miss equivalent answers it cannot parse
or subtract, including some tuple expressions.

## Files

- `serve.sh` — serves the model using the vLLM recipe.
- `run_eval.sh` — selects the 500 samples, generates answers, then applies Inspect's SymPy scorer.
- `assets/math500_sample_ids.txt` — the 500 stable sample IDs for the pinned Inspect MATH dataset.
- `server_requirements.txt` / `client_requirements.txt` — provisional server and client package pins.
- `local_orchestrator.sh` — local environment, GPU selection and server lifecycle; the only file you should modify.

## Run

### Setup

Create separate environments for vLLM and Inspect. The paths below match `local_orchestrator.sh`; if you
change the paths, change them there too. The server pins are copied from the Qwen 27B AIME task, and the
client pins include the MATH scorer dependencies. Neither environment has yet produced MATH-500 results.

```bash
python3.12 -m venv ~/.venvs/vllm
source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt
python3.12 -m venv ~/.venvs/inspect
source ~/.venvs/inspect/bin/activate
pip install -r client_requirements.txt
```

Install CUDA-flavored PyTorch wheels from the matching PyTorch index if needed. The model and dataset are
downloaded from Hugging Face; export `HF_TOKEN` locally if needed. Docker is not required.

### Run the eval

```bash
EPOCHS=1 ./local_orchestrator.sh --sample-id "$(head -n 5 assets/math500_sample_ids.txt | paste -sd,)"
./local_orchestrator.sh
inspect view --log-dir ./logs
```

Read the smoke-test samples before the full run. Inspect treats `--sample-id` and `--limit` as alternatives,
so `--limit` does not work for this task; select smoke-test IDs as above. `run_eval.sh` first generates without
scoring, then applies the upstream SymPy scorer in a separate scoring step; it does not invoke the upstream
model judge.

## Results

Not yet run. The default configuration is one epoch, `temperature=1.0`, `top_p=0.95`, `top_k=20`,
`reasoning_effort=xhigh`, `max_tokens=131072`, `max_connections=128`, and `client_timeout=7200`.

## Patches for upstream

None.
