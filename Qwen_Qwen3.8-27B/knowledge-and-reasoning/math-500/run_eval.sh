#!/usr/bin/env bash
# MATH-500 on Qwen/Qwen3.8-27B against an already-running vLLM server.
set -euo pipefail

MODEL="${MODEL:-Qwen/Qwen3.8-27B}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

# Inspect ignores --limit when --sample-id is present; require an explicit ID
# subset for smoke tests rather than silently running all 500 questions.
if [[ " $* " == *" --limit "* || " $* " == *" --limit="* ]]; then
  echo 'Use --sample-id to select a smoke-test subset; --limit is ignored with --sample-id.' >&2
  exit 1
fi

# The stock MATH task also calls an LLM judge. Generate first, then score only
# with its SymPy scorer, without changing the upstream task.
mkdir -p "$LOG_DIR"
RUN_LOG_DIR="$(mktemp -d "$LOG_DIR/math-500-XXXXXXXX")"
MATH_SCORER="$(python -c 'import importlib.util; print(importlib.util.find_spec("inspect_evals.math.math").origin)')@expression_exact_match_sympy"

inspect eval inspect_evals/math \
  --model "vllm/${MODEL}" \
  --sample-id "$(paste -sd, assets/math500_sample_ids.txt)" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 --top-k 20 \
  --reasoning-effort xhigh \
  --max-tokens "${MAX_TOKENS:-131072}" \
  --max-connections "${MAX_CONNECTIONS:-128}" \
  -M client_timeout=7200 \
  --no-score --log-dir "$RUN_LOG_DIR" \
  "$@"

inspect score "$RUN_LOG_DIR"/*.eval --scorer "$MATH_SCORER" --overwrite
mv "$RUN_LOG_DIR"/*.eval "$LOG_DIR"/
rmdir "$RUN_LOG_DIR"
