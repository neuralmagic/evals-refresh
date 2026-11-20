#!/usr/bin/env bash
# SWE-bench Verified (500 instances), official x86_64 SWE-bench sandbox images.
# Mistral Large 4 sampling: temperature=1.0, top_p=0.95, top_k unset; highest reasoning effort is high.
set -euo pipefail
MODEL="${MODEL:-mistralai/Mistral-Large-4-1T-A52B}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

inspect eval inspect_evals/swe_bench \
  -T dataset=princeton-nlp/SWE-bench_Verified \
  -T split=test \
  -T revision=c104f840cc67f8b6eec6f759ebc8b2693d585d4a \
  -T arch=x86_64 \
  -T allow_internet=False \
  -T image_name_template='swebench/sweb.eval.{arch}.{org}_1776_{repo}-{issue}:latest' \
  --model "vllm/${MODEL}" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 \
  --reasoning-effort high \
  --max-tokens "${MAX_TOKENS:-16384}" \
  --message-limit "${MESSAGE_LIMIT:-200}" \
  --max-connections "${MAX_CONNECTIONS:-8}" \
  --max-sandboxes "${MAX_SANDBOXES:-8}" \
  --time-limit "${TIME_LIMIT:-14400}" \
  --fail-on-error 0.1 \
  -M client_timeout=7200 \
  --log-dir "$LOG_DIR" \
  "$@"
