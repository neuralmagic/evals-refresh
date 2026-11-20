#!/usr/bin/env bash
# Serve nvidia/Qwen3.8-27B-NVFP4 with vLLM.
# Flags follow the official vLLM recipe NVFP4 (NVIDIA) path:
# https://recipes.vllm.ai/Qwen/Qwen3.8-27B (variant nvidia/Qwen3.8-27B-NVFP4)
# Speculative decoding (MTP / DSpark) is an opt-in recipe feature and is left off.
# --language-model-only: MRCR is text-only; the checkpoint is multimodal (vision tower).
set -euo pipefail

MODEL="${MODEL:-nvidia/Qwen3.8-27B-NVFP4}"
MODEL_PATH="${MODEL_PATH:-$MODEL}"   # HF id, or a local copy of the checkpoint
PORT="${PORT:-8000}"
TP="${TP:-1}"   # NVFP4 weights fit one B200
DP="${DP:-4}"   # user request: 4 replicas behind one endpoint

exec vllm serve "$MODEL_PATH" \
  --tensor-parallel-size "$TP" \
  --data-parallel-size "$DP" \
  --max-model-len 262144 \
  --kv-cache-dtype fp8 \
  --reasoning-parser qwen3 \
  --default-chat-template-kwargs '{"enable_thinking": true, "reasoning_effort": "xhigh"}' \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --language-model-only \
  --served-model-name "$MODEL" \
  --host 0.0.0.0 --port "$PORT"
