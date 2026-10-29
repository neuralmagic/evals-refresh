#!/usr/bin/env bash
# Serve Qwen/Qwen3.8-27B with vLLM.
# Flags follow the official vLLM recipe: https://recipes.vllm.ai/Qwen/Qwen3.8-27B
set -euo pipefail

MODEL="${MODEL:-Qwen/Qwen3.8-27B}"
PORT="${PORT:-8000}"
TP="${TP:-2}"   # 27B bf16 fits comfortably on 2x H100
DP="${DP:-4}"   # 4 replicas behind one endpoint -> all 8 GPUs

exec vllm serve "$MODEL" \
  --tensor-parallel-size "$TP" \
  --data-parallel-size "$DP" \
  --max-model-len 262144 \
  --reasoning-parser qwen3 \
  --default-chat-template-kwargs '{"enable_thinking": true, "reasoning_effort": "xhigh"}' \
  --enable-auto-tool-choice --tool-call-parser qwen3_xml \
  --served-model-name "$MODEL" \
  --host 0.0.0.0 --port "$PORT"
