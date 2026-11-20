# mistralai/Mistral-Large-4-1T-A52B — MMLU, original English split (57 subjects; full dataset)

| | |
|---|---|
| Task | inspect_evals/mmlu_0_shot (MMLU, original English split (57 subjects; full dataset)) |
| Category | knowledge-and-reasoning |
| Exec tier | none — no Docker sandbox or tools |
| Model card | https://huggingface.co/mistralai/Mistral-Large-4-1T-A52B |
| vLLM recipe | https://recipes.vllm.ai/mistralai/Mistral-Large-4-1T-A52B |

0-shot Simple Evals style, no explicit chain-of-thought prompt, as recommended by Inspect for instruction-tuned models. The full task contains 13,937 questions and uses one epoch (pass@1), a 16,384-token output cap, 65,536-token server context, and 8 sequences/connections. The Mistral Large 4 model card reports no standard MMLU score or protocol; this setup supports a direct comparison of the two checkpoints. The official Mistral checkpoint is FP8 block-scaled, not BF16. Checkpoint revision: af26e7869af601441d5cdf75a1272469ddc3d059; stored size: FP8 block-scaled; 1,060,618,650,948 bytes (987.8 GiB). The earlier base MMLU-Pro result is a different task and cannot be reused for this comparison.

## Files

- serve.sh — vLLM server flags from the official Mistral Large 4 recipe, including tensor parallelism, context, Mistral reasoning/tool parsers and text-only input limits. DSpark is disabled to match the paired quantized run.
- run_eval.sh — Inspect task, one-epoch sampling and limits.
- local_orchestrator.sh — starts the official vLLM image, waits for health, runs the Inspect client environment, and tears down the server. This is the only host-specific file.
- server_requirements.txt / client_requirements.txt — pinned vLLM image and frozen Inspect/SWE-bench client packages.


## Run

### Setup

Use the same pinned vLLM image as the quantized run on an NVIDIA host with eight B300 GPUs, the NVIDIA Container Toolkit, and Docker. Create an Inspect environment from `client_requirements.txt` and set `INSPECT_VENV` in `local_orchestrator.sh` to its path:

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

Use the same HF_HOME value when running `local_orchestrator.sh`; edit its default if needed. The defaults are CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7, TP=8, GPU_MEMORY_UTILIZATION=0.85, a 65,536-token context, and 8 server sequences. The orchestrator pins the H200 run's vLLM image digest and serves this base snapshot with CPU offload and DSpark disabled.





### Run the eval

Smoke-test first:

~~~bash
./local_orchestrator.sh --limit 5
~~~

Then run the complete benchmark:

~~~bash
./local_orchestrator.sh
inspect view --log-dir ./logs
~~~

## Results

No GPU-backed run has been recorded yet. Fill the score, stderr, sample count, errors, truncation and token-stat fields after the smoke test and full run.

Model generation config:

temperature=1.0, top_p=0.95, reasoning_effort=high, max_tokens=16384, max_connections=8, client_timeout=7200, TP=8, max_model_len=65536, max_num_seqs=8, max_num_batched_tokens=8192, gpu_memory_utilization=0.85, cpu_offload_gb=0, DSpark=off, epochs=1

| metric | value |
|---|---|
| accuracy (pass@1) | 0.905 (12,614 of 13,937) |
| stderr | 0.0025 |
| samples | 13,937 |
| truncated (`stop_reason=max_tokens`) | 365 |
| unparsed answers | 365 |
| sample errors | 0 |

| tokens / sample | input | output | reasoning |
|---|---:|---:|---:|
| mean | 161.2 | 1,932.2 | 1,925.4 |
| median | 127 | 397 | 390 |
| max | 1,036 | 16,384 | 16,383 |

Output-token totals include the reasoning tokens shown separately.

## Patches for upstream

None.
