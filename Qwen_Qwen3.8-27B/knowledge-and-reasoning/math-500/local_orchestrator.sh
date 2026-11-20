#!/usr/bin/env bash
# Local glue, specific to one server: venvs, GPUs, serve in background, eval, tear down.
# Treat this as a template and adapt paths/GPUs to your own environment.
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
PORT="${PORT:-8000}"
mkdir -p logs

source ~/.venvs/vllm/bin/activate
./serve.sh > logs/serve.log 2>&1 &
SERVE_PID=$!
until curl -sf "http://localhost:${PORT}/health" >/dev/null; do sleep 10; done

source ~/.venvs/inspect/bin/activate
./run_eval.sh "$@"

kill $SERVE_PID
