#!/usr/bin/env bash
# Serve Mistral Large 4 with the official vLLM image and recipe.
set -euo pipefail

MODEL_PATH="${MODEL_PATH:?local_orchestrator.sh must set MODEL_PATH}"
MODEL_MOUNT="${MODEL_MOUNT:?local_orchestrator.sh must set MODEL_MOUNT}"
MODEL_ID="${MODEL_ID:-mistral-large-4}"
PORT="${PORT:-8000}"
CONTAINER_NAME="${CONTAINER_NAME:-mistral-large-4-eval}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai@sha256:83a52c97e78b284d031e98135f17a448789358be31aa246237d6ad0130ef7657}"

docker_args=(
  --rm
  --name "$CONTAINER_NAME"
  --gpus all
  --network host
  --ipc=host
  --mount "type=bind,src=$MODEL_MOUNT,dst=$MODEL_MOUNT,readonly"
  -e HF_HUB_OFFLINE=1
  -e VLLM_ENGINE_READY_TIMEOUT_S=6000
  -e VLLM_DISABLED_KERNELS=HummingMxFp4LinearKernel
  "$VLLM_IMAGE"
  "$MODEL_PATH"
  --served-model-name "$MODEL_ID"
  --tokenizer-mode mistral
  --config-format mistral
  --load-format mistral
  --max-model-len 262144
  --max-num-batched-tokens 8192
  --max-num-seqs 128
  --gpu-memory-utilization 0.85
  --tensor-parallel-size 8
  --enable-auto-tool-choice
  --tool-call-parser mistral
  --reasoning-parser mistral
  --default-chat-template-kwargs '{"reasoning_effort":"high"}'
  --limit-mm-per-prompt '{"image":0,"audio":0}'
  --host 0.0.0.0
  --port "$PORT"
)

exec docker run "${docker_args[@]}"
