#!/usr/bin/env bash
# Standard English MMLU with Inspect's 0-shot protocol; model recommendations: temperature=1.0, top_p=0.95, reasoning_effort=high.
set -euo pipefail
MODEL="${MODEL:-mistralai/Mistral-Large-4-1T-A52B}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"
export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"
inspect eval inspect_evals/mmlu_0_shot --model "vllm/${MODEL}" --epochs "$EPOCHS" --epochs-reducer mean --temperature 1.0 --top-p 0.95 --reasoning-effort high --max-tokens "${MAX_TOKENS:-16384}" --max-connections "${MAX_CONNECTIONS:-8}" -M client_timeout=7200 --log-dir "$LOG_DIR" "$@"
