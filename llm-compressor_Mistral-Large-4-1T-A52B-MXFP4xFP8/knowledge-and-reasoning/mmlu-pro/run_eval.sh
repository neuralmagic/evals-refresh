#!/usr/bin/env bash
# Full GPQA-Diamond evaluation on Mistral Large 4.
# Sampling comes from the checkpoint generation_config.json; reasoning effort is high.
set -euo pipefail

MODEL="${MODEL:-mistral-large-4}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

eval_args=(
  inspect_evals/mmlu_pro
  --model "vllm/${MODEL}"
  --epochs "$EPOCHS"
  --epochs-reducer mean
  --temperature 1.0
  --top-p 0.95
  --reasoning-effort high
  --max-tokens "${MAX_TOKENS:-131072}"
  --max-connections "${MAX_CONNECTIONS:-128}"
  -M client_timeout=7200
  --log-dir "$LOG_DIR"
)
exec inspect eval "${eval_args[@]}" "$@"
