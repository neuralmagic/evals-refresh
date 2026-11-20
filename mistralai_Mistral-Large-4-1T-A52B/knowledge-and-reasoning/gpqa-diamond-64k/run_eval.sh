#!/usr/bin/env bash
# GPQA Diamond. Model recommendations: temperature=1.0, top_p=0.95, reasoning_effort=high; top_k is unset.
set -euo pipefail
MODEL="${MODEL:-mistralai/Mistral-Large-4-1T-A52B}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"
export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"
inspect eval inspect_evals/gpqa_diamond --model "vllm/${MODEL}" --epochs "$EPOCHS" --epochs-reducer mean --temperature 1.0 --top-p 0.95 --reasoning-effort high --max-tokens "${MAX_TOKENS:-131072}" --max-connections "${MAX_CONNECTIONS:-16}" -M client_timeout=7200 --log-dir "$LOG_DIR" "$@"
