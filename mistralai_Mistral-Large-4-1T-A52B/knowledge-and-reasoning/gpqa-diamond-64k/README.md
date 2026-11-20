# mistralai/Mistral-Large-4-1T-A52B — GPQA Diamond (198 questions, 4 choices)

| | |
|---|---|
| Task | inspect_evals/gpqa_diamond (GPQA Diamond (198 questions, 4 choices)) |
| Category | knowledge-and-reasoning |
| Exec tier | none — no Docker sandbox or tools |
| Model card | https://huggingface.co/mistralai/Mistral-Large-4-1T-A52B |
| vLLM recipe | https://recipes.vllm.ai/mistralai/Mistral-Large-4-1T-A52B |

The task default uses its chain-of-thought multiple-choice prompt and fixed answer-choice shuffle. The final run used one epoch (pass@1), a 262,144-token server context, a 131,072-token output cap, and 16 sequences/connections. The Mistral Large 4 model card reports no GPQA Diamond score or protocol; this setup supports a direct comparison of the two checkpoints. The official Mistral checkpoint is FP8 block-scaled, not BF16. Checkpoint revision: af26e7869af601441d5cdf75a1272469ddc3d059; stored size: FP8 block-scaled; 1,060,618,650,948 bytes (987.8 GiB). The earlier base GPQA result used a different context and output cap, so it remains a separate historical result; the earlier base MMLU-Pro result is a different task.

## Files

- serve.sh — vLLM server flags from the official Mistral Large 4 recipe, including tensor parallelism, context, Mistral reasoning/tool parsers and text-only input limits. DSpark is disabled to match the paired quantized run.
- run_eval.sh — Inspect task, one-epoch sampling and limits.
- local_orchestrator.sh — starts the official vLLM image, waits for health, runs the Inspect client environment, and tears down the server. This is the only host-specific file.
- server_requirements.txt / client_requirements.txt — pinned vLLM image and frozen Inspect/SWE-bench client packages.


## Run

### Setup

Run the base checkpoint on an NVIDIA host with eight B300 GPUs, the NVIDIA Container Toolkit, and Docker. The serving image is pinned by digest in `local_orchestrator.sh`. Create an Inspect environment from `client_requirements.txt` and set `INSPECT_VENV` in `local_orchestrator.sh` to its path:

~~~bash
docker pull vllm/vllm-openai@sha256:83a52c97e78b284d031e98135f17a448789358be31aa246237d6ad0130ef7657
uv venv --python 3.12 --seed ~/.venvs/mistral-l4-handoff
source ~/.venvs/mistral-l4-handoff/bin/activate
uv pip install -r client_requirements.txt
~~~

Download the exact checkpoint revision into the Hugging Face cache mounted by local_orchestrator.sh:

~~~bash
export HF_HOME=/path/to/hf-cache
hf download mistralai/Mistral-Large-4-1T-A52B --revision af26e7869af601441d5cdf75a1272469ddc3d059
~~~

Use the same HF_HOME value when running `local_orchestrator.sh`; edit its default if needed. The defaults are CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7, TP=8, GPU_MEMORY_UTILIZATION=0.85, a 262,144-token context, and 16 server sequences. CPU offload and DSpark are disabled.

For GPQA, accept the dataset terms for Idavidrein/gpqa with the account used by HF_TOKEN, then export HF_TOKEN before running.



### Run the eval

Smoke-test first:

~~~bash
EPOCHS=1 MAX_TOKENS=8192 ./local_orchestrator.sh --limit 2
~~~

Then run the complete benchmark:

~~~bash
./local_orchestrator.sh
inspect view --log-dir ./logs
~~~

## Results

Model generation config:

temperature=1.0, top_p=0.95, reasoning_effort=high, max_tokens=131072, max_connections=16, client_timeout=7200, TP=8, max_model_len=262144, max_num_seqs=16, max_num_batched_tokens=8192, gpu_memory_utilization=0.85, cpu_offload_gb=0, DSpark=off, epochs=1

| metric | value |
|---|---|
| accuracy (pass@1) | 0.919 (182 of 198) |
| stderr | 0.019 |
| samples | 198 |
| truncated (`stop_reason=max_tokens`) | 0 |
| unparsed answers | 0 |
| sample errors | 0 |

| tokens / sample | input | output | reasoning |
|---|---:|---:|---:|
| mean | 268.4 | 18,994.9 | 18,754.3 |
| median | 234.5 | 10,244.5 | 9,964 |
| max | 2,859 | 117,189 | 116,940 |

Output-token totals include the reasoning tokens shown separately.

## Patches for upstream

None.
