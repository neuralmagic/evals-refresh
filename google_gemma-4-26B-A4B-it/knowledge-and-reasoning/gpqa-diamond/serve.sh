#!/usr/bin/env bash
# Serve google/gemma-4-26B-A4B-it with vLLM.
# Flags follow the official vLLM recipe: https://recipes.vllm.ai/Google/gemma-4-26B-A4B-it
set -euo pipefail

MODEL="${MODEL:-google/gemma-4-26B-A4B-it}"
MODEL_PATH="${MODEL_PATH:-$MODEL}"
PORT="${PORT:-8204}"
TP="${TP:-1}"
DP="${DP:-1}"

exec vllm serve "$MODEL_PATH" \
  --tensor-parallel-size "$TP" \
  --data-parallel-size "$DP" \
  --max-model-len 262144 \
  --reasoning-parser gemma4 \
  --default-chat-template-kwargs '{"enable_thinking": true}' \
  --enable-auto-tool-choice --tool-call-parser gemma4 \
  --limit-mm-per-prompt '{"image": 0, "audio": 0}' \
  --chat-template "$(dirname "$0")/assets/tool_chat_template_gemma4.jinja" \
  --served-model-name "$MODEL" \
  --host 0.0.0.0 --port "$PORT"
