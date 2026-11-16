#!/usr/bin/env bash
# Local glue: one model per GPU slot, env-var overridable for the queue driver.
set -uo pipefail
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-4}"
export PORT="${PORT:-8204}"
MODEL="${MODEL:-google/gemma-4-31B-it}"
export MODEL_PATH="${MODEL_PATH:-/data/dsikka/gemma4-bf16/gemma-4-31B-it}"
export HF_HUB_OFFLINE=1
mkdir -p logs

if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
  echo "something is already serving on port ${PORT}; stop it first" >&2
  exit 1
fi

source ~/.venvs/vllm/bin/activate
./serve.sh > logs/serve.log 2>&1 &
SERVE_PID=$!

until curl -sf "http://localhost:${PORT}/v1/models" | grep -qF "\"${MODEL}\""; do
  kill -0 $SERVE_PID 2>/dev/null || { echo "vLLM server exited before becoming healthy, see logs/serve.log" >&2; exit 1; }
  sleep 10
done

source ~/.venvs/inspect/bin/activate
EVAL_RC=0
./run_eval.sh "$@" || EVAL_RC=$?

kill $SERVE_PID 2>/dev/null
for _ in $(seq 1 30); do kill -0 $SERVE_PID 2>/dev/null || break; sleep 2; done
kill -9 $SERVE_PID 2>/dev/null
for _ in $(seq 1 30); do curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1 || break; sleep 2; done
for _ in $(seq 1 15); do
  used=$(nvidia-smi --id="$CUDA_VISIBLE_DEVICES" --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1)
  if [ -n "$used" ] && [ "$used" -lt 1000 ]; then break; fi
  for pid in $(nvidia-smi --id="$CUDA_VISIBLE_DEVICES" --query-compute-apps=pid --format=csv,noheader 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
  sleep 4
done
exit $EVAL_RC
