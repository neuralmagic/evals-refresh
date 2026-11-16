#!/usr/bin/env bash
# LiveCodeBench release_v6 on google/gemma-4-31B-it.
#
# Full single-shot protocol: 1,055 problems, one generation per problem,
# pass@1 when every public and private test passes. This uses the task from
# neuralmagic/inspect_evals on branch livecodebench-v6, not the 100-task
# Harbor sample in this repo's livecodebench dir.
#
# Sampling comes from the model's generation_config.json (temp 1.0, top_p 0.95,
# top_k 64). assets/generate_config.json enables thinking per request.
# -M client_timeout raises Inspect's HTTP timeout for long reasoning traces.
# --max-sandboxes equals --max-connections because the scorer runs one
# container per in-flight sample.
set -euo pipefail

MODEL="${MODEL:-google/gemma-4-31B-it}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

inspect eval inspect_evals/livecodebench \
  --model "vllm/${MODEL}" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 --top-k 64 \
  --generate-config "$(dirname "$0")/assets/generate_config.json" \
  --max-tokens "${MAX_TOKENS:-65536}" \
  --max-connections "${MAX_CONNECTIONS:-32}" \
  --max-sandboxes "${MAX_SANDBOXES:-32}" \
  --time-limit "${TIME_LIMIT:-1800}" \
  --fail-on-error 0.1 \
  -M client_timeout=7200 \
  --log-dir "$LOG_DIR" \
  "$@"
