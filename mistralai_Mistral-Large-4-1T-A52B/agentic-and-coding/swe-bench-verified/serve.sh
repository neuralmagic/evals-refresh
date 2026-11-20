#!/usr/bin/env bash
# Mistral Large 4 serving flags follow the official vLLM recipe.
set -euo pipefail
MODEL="${MODEL:-mistralai/Mistral-Large-4-1T-A52B}"
MODEL_PATH="${MODEL_PATH:-$MODEL}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
TP="${TP:-8}"
PP="${PP:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.85}"
CPU_OFFLOAD_GB="${CPU_OFFLOAD_GB:-0}"
DISABLE_CUSTOM_ALL_REDUCE="${DISABLE_CUSTOM_ALL_REDUCE:-0}"
ALL_REDUCE_ARGS=()
if [[ "$DISABLE_CUSTOM_ALL_REDUCE" == "1" ]]; then
  ALL_REDUCE_ARGS=(--disable-custom-all-reduce)
fi
DSPARK_ARGS=()
if [[ "${ENABLE_DSPARK:-0}" == "1" ]]; then
  DSPARK_ARGS=(--speculative-config '{"method":"dspark","num_speculative_tokens":3}')
fi
OFFLOAD_ARGS=()
if [[ "$CPU_OFFLOAD_GB" != "0" ]]; then
  OFFLOAD_ARGS=(--cpu-offload-gb "$CPU_OFFLOAD_GB")
fi
exec vllm serve "$MODEL_PATH" --tokenizer-mode mistral --config-format mistral --load-format mistral --tensor-parallel-size "$TP" --pipeline-parallel-size "$PP" --max-model-len "$MAX_MODEL_LEN" --max-num-seqs "$MAX_NUM_SEQS" --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS" --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" "${ALL_REDUCE_ARGS[@]}" "${OFFLOAD_ARGS[@]}" --enable-prefix-caching --reasoning-parser mistral --default-chat-template-kwargs '{"reasoning_effort":"high"}' --enable-auto-tool-choice --tool-call-parser mistral --limit-mm-per-prompt '{"image":0,"audio":0}' "${DSPARK_ARGS[@]}" --served-model-name "$MODEL" --host "$VLLM_HOST" --port "$PORT"
