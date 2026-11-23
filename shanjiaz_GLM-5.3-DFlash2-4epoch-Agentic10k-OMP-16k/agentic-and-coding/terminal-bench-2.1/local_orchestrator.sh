#!/usr/bin/env bash
# Environment glue for the measured 8x B300, TP8/DP1 run; adapt only this file.
# Create both venvs and download the pinned snapshots as shown in README.md.
# Reserve eight GPUs first; canhazgpu releases them after this script exits.
# Docker must already work (inherit DOCKER_HOST/DOCKER_CONFIG for rootless Docker).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

: "${CUDA_VISIBLE_DEVICES:?Reserve eight GPUs before running this script}"
export TP="${TP:-8}" DP="${DP:-1}" PORT="${PORT:-19221}"
IFS=',' read -ra GPUS <<< "$CUDA_VISIBLE_DEVICES"
if (( ${#GPUS[@]} < TP * DP )); then
  echo "TP=$TP x DP=$DP needs $((TP * DP)) reserved GPUs." >&2
  exit 1
fi
SERVER_VENV="${SERVER_VENV:-$HOME/.venvs/glm53-tb21-server}"
CLIENT_VENV="${CLIENT_VENV:-$HOME/.venvs/glm53-tb21-client}"
export HF_HOME="${HF_HOME:-/data/$USER/huggingface}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export MODEL="${MODEL:-zai-org/GLM-5.3}"
export MODEL_PATH="${MODEL_PATH:-$HF_HUB_CACHE/models--zai-org--GLM-5.3/snapshots/ba32f8c19c8738e2c57c71798c601d477a7bf844}"
export SPECULATOR="${SPECULATOR:-$HF_HUB_CACHE/models--shanjiaz--GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k/snapshots/69e879bb4164969d6194f456cced7eeab54a38c3}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}" OMP_NUM_THREADS="${OMP_NUM_THREADS:-8}"
export LOG_DIR="${LOG_DIR:-./logs/full}"
ANALYSIS_DIR="${ANALYSIS_DIR:-$LOG_DIR/spec_decode_report}"
test -r "$MODEL_PATH/config.json"
test -r "$SPECULATOR/config.json"
if [[ -e "$LOG_DIR/serve.log" ]]; then
  echo "Use a fresh LOG_DIR to keep previous logs and acceptance pools separate." >&2
  exit 1
fi
mkdir -p "$LOG_DIR"

# Do not attach a benchmark to a server or GPU process owned by another run.
if curl -sf --max-time 3 "http://127.0.0.1:${PORT}/health" >/dev/null; then
  echo "Port $PORT already has a healthy server; choose another port." >&2
  exit 1
fi
if [[ -n "$(nvidia-smi --id="$CUDA_VISIBLE_DEVICES" --query-compute-apps=pid --format=csv,noheader)" ]]; then
  echo "Reserved GPUs still have compute processes; wait for their owner to finish." >&2
  exit 1
fi

SERVE_PID="" CANARY_PID="" EVAL_PID=""
cleanup() {
  # Stop only process groups created here, then wait for our GPUs to drain.
  trap - EXIT INT TERM
  touch "$LOG_DIR/canary.stop"
  for pid in "$EVAL_PID" "$CANARY_PID" "$SERVE_PID"; do
    [[ -z "$pid" ]] || kill -TERM -- "-$pid" 2>/dev/null || true
  done
  sleep 3
  for pid in "$EVAL_PID" "$CANARY_PID" "$SERVE_PID"; do
    [[ -z "$pid" ]] || kill -KILL -- "-$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  while [[ -n "$SERVE_PID" ]] && nvidia-smi --id="$CUDA_VISIBLE_DEVICES" \
    --query-gpu=memory.used --format=csv,noheader,nounits | awk '$1 > 512 { busy=1 } END { exit !busy }'; do
    echo "Waiting for reserved GPU memory to drain before release." >&2
    sleep 2
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PATH="$SERVER_VENV/bin:$PATH" HF_HUB_OFFLINE=1 setsid ./serve.sh > "$LOG_DIR/serve.log" 2>&1 &
SERVE_PID=$!
deadline=$((SECONDS + 5400))
until curl -sf --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null; do
  if ! kill -0 "$SERVE_PID" 2>/dev/null || (( SECONDS >= deadline )); then
    echo "Server failed its 90-minute startup budget; see $LOG_DIR/serve.log." >&2
    exit 1
  fi
  sleep 10
done

rm -f "$LOG_DIR/canary.stop"
setsid "$CLIENT_VENV/bin/python" monitor_spec_decode.py canary \
  --base-url "http://127.0.0.1:${PORT}/v1" --model "$MODEL" \
  --interval 120 --max-tokens 1024 \
  --log "$LOG_DIR/canary.jsonl" --flag "$LOG_DIR/collapse_detected.jsonl" \
  --stop-file "$LOG_DIR/canary.stop" > "$LOG_DIR/canary.log" 2>&1 &
CANARY_PID=$!
PATH="$CLIENT_VENV/bin:$PATH" setsid ./run_eval.sh "$@" > "$LOG_DIR/eval.log" 2>&1 &
EVAL_PID=$!
STATUS=0
wait "$EVAL_PID" || STATUS=$?
EVAL_PID=""
touch "$LOG_DIR/canary.stop"

# Acceptance is computed from Inspect calls; canary requests stay separate.
if "$CLIENT_VENV/bin/python" analyze_spec_decode.py "$LOG_DIR" -o "$ANALYSIS_DIR"; then
  "$CLIENT_VENV/bin/python" monitor_spec_decode.py audit "$ANALYSIS_DIR/calls.csv" -o "$ANALYSIS_DIR" || STATUS=1
else
  STATUS=1
fi
exit "$STATUS"
