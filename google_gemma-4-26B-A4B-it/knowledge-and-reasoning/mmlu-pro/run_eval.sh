#!/usr/bin/env bash
# MMLU-Pro on google/gemma-4-26B-A4B-it against an already-running vLLM server.
# Sampling params come from the model's generation_config.json (temp 1.0, top_p 0.95, top_k 64).
# assets/generate_config.json turns thinking on per request (Gemma 4 has no reasoning-effort levels,
# only enable_thinking); it is also the server default in serve.sh.
# -M client_timeout raises Inspect's HTTP timeout (default 600s): long reasoning traces take longer
# than 10 min to generate and would otherwise be cut off and retried from scratch forever.
set -euo pipefail

MODEL="${MODEL:-google/gemma-4-26B-A4B-it}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

inspect eval inspect_evals/mmlu_pro \
  --model "vllm/${MODEL}" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 --top-k 64 \
  --generate-config "$(dirname "$0")/assets/generate_config.json" \
  --max-tokens "${MAX_TOKENS:-131072}" \
  --max-connections "${MAX_CONNECTIONS:-256}" \
  -M client_timeout=7200 \
  --log-dir "$LOG_DIR" \
  "$@"
