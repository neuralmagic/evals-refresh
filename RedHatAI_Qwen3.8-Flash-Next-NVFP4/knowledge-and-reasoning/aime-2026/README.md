# RedHatAI/Qwen3.8-Flash-Next-NVFP4 — AIME 2026

| | |
|---|---|
| Task | `inspect_evals/aime2026` (30 problems (AIME I + II), integer answers) |
| Category | knowledge-and-reasoning (subclass: math-reasoning) |
| Exec tier | `none` — no Docker, no sandbox, no tools |
| vLLM recipe | https://recipes.vllm.ai/Qwen/Qwen3.8-Flash-Next |

Answers are matched numerically after stripping `\boxed{}`; the prompt asks for `ANSWER: $ANSWER` on the last line.
Dataset pinned at revision `79037aebdb`. One epoch instead of the repo's usual avg@8 for this task, by request:
with 30 problems a single epoch has a standard error of several points. Neither the Qwen/Qwen3.8-Flash-Next card
nor the RedHatAI card reports AIME 2026, so there is no reference number. Checkpoint: NVFP4 (W4A4) on the MoE
experts only, compressed-tensors format produced with LLM Compressor; everything else, including the 51B n-gram
embedding table, stays BF16. Revision `863f54a`. This checkpoint's `generation_config.json` omits `top_p`, so the
card's 0.95 is sent with every request.

## Files

- `serve.sh` — deploys the model with a vLLM server. vLLM-serve arguments live here (parallelism, context length,
  KV-cache dtypes, reasoning/tool parsers, text-only mode), taken from the official recipe (Blackwell, features
  tool_calling, reasoning, text_only). TP=1 × DP=4 on four GPUs: vLLM keeps the n-gram table in pinned host memory
  and shards the MoE experts across the DP group.
- `run_eval.sh` — runs the Inspect task against that server. Inspect-side params live here
  (task, epochs, sampling params, reasoning effort, max tokens, concurrency).
- `server_requirements.txt` / `client_requirements.txt` — `pip freeze` of the vLLM and Inspect
  venvs that produced the results below, with the host (GPUs, driver, CUDA, Python) in the header.
- `local_orchestrator.sh` — runs everything in your local dev environment: activates the venvs, sets GPUs
  (0-3, port 8000, so both NVFP4 checkpoints can run side by side on one 8-GPU host) and the local
  checkpoint path, starts `serve.sh` in the background, runs `run_eval.sh`, tears down.
  **This is the only file you should modify** to match the environment you run in.

## Run

### Setup (once per host)

Create a server and a client environment as below. The commands use the paths that `local_orchestrator.sh` activates;
if you keep the environments elsewhere, change the paths there. `server_requirements.txt` and
`client_requirements.txt` are the exact `pip freeze` of the environments that produced the results below (Python 3.12,
host details in their headers).

```bash
# server: the same vLLM nightly (0.30.1rc1.dev418+g50319916a) binaries plus the Qwen4Exp compressed-tensors
# PLE fix of vllm-project/vllm#59431, which merged after that nightly (see Patches for upstream)
uv venv ~/.venvs/vllm-nightly-ple-fix --python 3.12 && source ~/.venvs/vllm-nightly-ple-fix/bin/activate
uv pip install -r server_requirements.txt --index-strategy unsafe-best-match \
  --extra-index-url https://wheels.vllm.ai/50319916a3c72ec1358f9e29c7c282d316d86f78 \
  --extra-index-url https://download.pytorch.org/whl/cu130
git clone https://github.com/vllm-project/vllm.git && cd vllm
git checkout 50319916a3c72ec1358f9e29c7c282d316d86f78   # the nightly commit the binaries come from
git show c32513b99d29b3c6efee38df752a696bc2696c2f | git apply   # vllm-project/vllm#59431; applies cleanly and gives the source tree that produced the results
uv pip install "cmake>=3.26.1" ninja "setuptools>=77.0.3,<81" "setuptools-scm>=8.0" "setuptools-rust>=1.9.0" wheel jinja2
VLLM_USE_PRECOMPILED=1 VLLM_PRECOMPILED_WHEEL_COMMIT=50319916a3c72ec1358f9e29c7c282d316d86f78 \
  uv pip install --no-deps --no-build-isolation -e .
# client: Inspect
uv venv ~/.venvs/inspect --python 3.12 && source ~/.venvs/inspect/bin/activate
uv pip install -r client_requirements.txt          # or: uv pip install "inspect-evals==0.20.0" openai
```

`local_orchestrator.sh` serves the checkpoint from a local copy (`MODEL_PATH`); unset it to let vLLM fetch
`RedHatAI/Qwen3.8-Flash-Next-NVFP4` from the Hugging Face Hub. Loading copies the 51B n-gram table into pinned host
memory (about 100 GB per server), which takes several minutes. Export `HF_TOKEN` in your shell before running
(never in the repo); nothing here is gated, but anonymous Hub downloads are rate-limited.

### Run the eval

```bash
./local_orchestrator.sh
inspect view --log-dir ./logs
```

Always smoke-test first: `EPOCHS=1 ./local_orchestrator.sh --limit 5`

## Results

With model generation config:

`temperature=1.0, top_p=0.95, top_k=20, reasoning_effort=xhigh, max_tokens=131072, max_connections=128, client_timeout=7200, epochs=1`

the following scores and token stats are obtained:

| metric | value |
|---|---|
| accuracy | 1.000 |
| stderr | 0.0000 |
| samples | 30 (1 epoch) |
| problems solved | 30 / 30 |
| truncated (stop_reason=max_tokens) | 0 |
| unparsed answers | 0 |
| sample errors | 0 |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 274 | 20,601 | 19,742 |
| median | 271 | 13,166 | 12,286 |
| max | 512 | 120,372 | 118,637 |

Total run time about 50 min on 4x B200 (TP=1 × DP=4), sharing the server with the other two knowledge-and-reasoning tasks of this model, which ran at the same time.

## Patches for upstream

vLLM (nightly and `main` as of 2026-09-30) cannot load this checkpoint:
`Qwen4ExpPLEEmbeddingMethod.from_quant_config` accepts only unquantized, ModelOpt and FP8 configs, and raises
`NotImplementedError: Qwen4Exp PLE embedding does not support quantization config CompressedTensorsConfig` for any
compressed-tensors checkpoint, even when, as here, no config group targets the n-gram table.
The fix (the table is loaded unquantized unless a compressed-tensors config group targets it) is
[vllm-project/vllm#59431](https://github.com/vllm-project/vllm/pull/59431), merged upstream on 2026-09-30 as commit
`c32513b99d`, after the nightly used here. The results were produced with that same 8-line change applied on top of
nightly `50319916a3`, installed editable on the nightly's precompiled binaries. Setup reproduces that source tree by
applying the upstream commit to the nightly checkout. vLLM 0.32.0 and later releases include the fix (v0.31.0 was cut
before the merge and does not). Newer builds were not verified against this checkpoint here.
