#!/usr/bin/env bash
# Host-specific glue: checkpoints, HF cache, Docker, Inspect venv, server and evaluation.
set -euo pipefail

export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export HF_HOME="${HF_HOME:-/data/Roderick-Wu/huggingface}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$HF_HUB_CACHE}"
MODEL_PATH="${MODEL_PATH:-/data/Roderick-Wu/huggingface/hub/models--mistralai--Mistral-Large-4-1T-A52B/snapshots/af26e7869af601441d5cdf75a1272469ddc3d059}"
MODEL_MOUNT="${MODEL_MOUNT:-/data/Roderick-Wu/huggingface/hub}"
MODEL_ID="${MODEL_ID:-mistral-large-4}"
CONTAINER_NAME="${CONTAINER_NAME:-mistral-large-4-base-mmlu-pro}"
PORT="${PORT:-8000}"
INSPECT_ENV="${INSPECT_ENV:-/home/Roderick-Wu/.venvs/mistral-large-4-inspect}"
export HF_HOME HF_HUB_CACHE TRANSFORMERS_CACHE MODEL_PATH MODEL_MOUNT MODEL_ID CONTAINER_NAME PORT

mkdir -p logs
./serve.sh > logs/serve.log 2>&1 &
SERVE_PID=$!

cleanup() {
  docker stop --time 60 "$CONTAINER_NAME" >/dev/null 2>&1 || true
  wait "$SERVE_PID" 2>/dev/null || true
}
trap cleanup EXIT

until curl -sf "http://localhost:${PORT}/health" >/dev/null; do
  if ! kill -0 "$SERVE_PID" 2>/dev/null; then
    wait "$SERVE_PID"
    exit 1
  fi
  sleep 10
done

source "$INSPECT_ENV/bin/activate"
./run_eval.sh "$@" 2>&1 | tee logs/full.log
