#!/usr/bin/env bash
# The pinned 89-task Terminal-Bench 2.1 ReAct scaffold, one epoch at C20.
# Raw API logging preserves detailed acceptance counters and generated token IDs.
# The 7200-second limits apply to each task and each client request.
set -euo pipefail

MODEL="${MODEL:-zai-org/GLM-5.3}"
PORT="${PORT:-19221}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs/full}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-20}"
export VLLM_BASE_URL="${VLLM_BASE_URL:-http://127.0.0.1:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

exec inspect eval inspect_harbor/terminal_bench_2_1 \
  -T ref=sha256:7d7bdc1cbedad549fc1140404bd4dc45e5fd0ea7c4186773687d177ad3a0699a \
  -T override_cpus=0 \
  --model "vllm/${MODEL}" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 --reasoning-effort max \
  --max-tokens "${MAX_TOKENS:-65536}" \
  --max-connections "$MAX_CONNECTIONS" \
  --max-sandboxes "${MAX_SANDBOXES:-$MAX_CONNECTIONS}" \
  --time-limit "${TIME_LIMIT:-7200}" \
  --fail-on-error 0.1 \
  --log-model-api \
  -M client_timeout=7200 \
  --extra-body '{"return_token_ids":true}' \
  --log-dir "$LOG_DIR" \
  "$@"
