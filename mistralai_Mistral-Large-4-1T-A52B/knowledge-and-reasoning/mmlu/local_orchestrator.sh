#!/usr/bin/env bash
# Host-specific glue for the official vLLM image, HF cache, Inspect venv and Docker daemon.
set -euo pipefail
MODEL="${MODEL:-mistralai/Mistral-Large-4-1T-A52B}"
PORT="${PORT:-8000}"
TP="${TP:-8}"
PP="${PP:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-65536}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.85}"
CPU_OFFLOAD_GB="${CPU_OFFLOAD_GB:-0}"
ENABLE_DSPARK="${ENABLE_DSPARK:-0}"
HF_HOME="${HF_HOME:-/data/Roderick-Wu/huggingface}"
HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
VLLM_CACHE_ROOT="${VLLM_CACHE_ROOT:-$HF_HOME/vllm-cache}"
MODEL_PATH="${MODEL_PATH:-/root/.cache/huggingface/hub/models--mistralai--Mistral-Large-4-1T-A52B/snapshots/af26e7869af601441d5cdf75a1272469ddc3d059}"
IMAGE="${VLLM_IMAGE:-vllm/vllm-openai@sha256:83a52c97e78b284d031e98135f17a448789358be31aa246237d6ad0130ef7657}"
DOCKER_BIN="${DOCKER_BIN:-/usr/bin/docker}"
TASK="mmlu"
CONTAINER_NAME="mistral-l4-${TASK}-${BASHPID}"
DOCKER_NETWORK_MODE="${DOCKER_NETWORK_MODE:-bridge}"
NETWORK_ARGS=()
if [[ "$DOCKER_NETWORK_MODE" == "host" ]]; then
  NETWORK_ARGS=(--network host)
  VLLM_HOST="${VLLM_HOST:-127.0.0.1}"
elif [[ "$DOCKER_NETWORK_MODE" == "bridge" ]]; then
  NETWORK_ARGS=(-p "127.0.0.1:${PORT}:${PORT}")
  VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
else
  echo "Unsupported DOCKER_NETWORK_MODE: $DOCKER_NETWORK_MODE" >&2
  exit 2
fi
export VLLM_HOST
INSPECT_VENV="${INSPECT_VENV:-$HOME/.venvs/mistral-l4-handoff}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3,4,5,6,7}"
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"
export HF_HOME HF_HUB_CACHE TRANSFORMERS_CACHE
export MODEL MODEL_PATH PORT TP PP MAX_MODEL_LEN MAX_NUM_SEQS MAX_NUM_BATCHED_TOKENS GPU_MEMORY_UTILIZATION CPU_OFFLOAD_GB ENABLE_DSPARK
mkdir -p logs "$VLLM_CACHE_ROOT"
GPU_DEVICE_REQUEST="\"device=${CUDA_VISIBLE_DEVICES}\""
container_id="$("$DOCKER_BIN" run -d --init --runtime=nvidia --gpus "$GPU_DEVICE_REQUEST" --ipc=host --name "$CONTAINER_NAME" "${NETWORK_ARGS[@]}" -v "$VLLM_CACHE_ROOT:/root/.cache" -v "$HF_HUB_CACHE:/root/.cache/huggingface/hub:ro" -v "$PWD:/task:ro" -w /task -e HF_HOME=/root/.cache/huggingface -e HF_HUB_CACHE=/root/.cache/huggingface/hub -e HF_HUB_OFFLINE=1 -e CUDA_VISIBLE_DEVICES -e NCCL_DEBUG -e NCCL_DEBUG_SUBSYS -e VLLM_LOGGING_LEVEL -e VLLM_WORKER_MULTIPROC_METHOD -e NCCL_CUMEM_ENABLE -e NCCL_NVLS_ENABLE -e NCCL_P2P_DISABLE -e DISABLE_CUSTOM_ALL_REDUCE -e VLLM_DISTRIBUTED_USE_SPLIT_GROUP -e VLLM_DISABLE_PYNCCL -e VLLM_ENABLE_V1_MULTIPROCESSING -e VLLM_HOST -e MODEL -e MODEL_PATH -e PORT -e TP -e PP -e VLLM_PP_LAYER_PARTITION -e MAX_MODEL_LEN -e MAX_NUM_SEQS -e MAX_NUM_BATCHED_TOKENS -e GPU_MEMORY_UTILIZATION -e CPU_OFFLOAD_GB -e ENABLE_DSPARK -e VLLM_ENGINE_READY_TIMEOUT_S="${VLLM_ENGINE_READY_TIMEOUT_S:-7200}" --entrypoint bash "$IMAGE" ./serve.sh)"
"$DOCKER_BIN" logs --follow "$container_id" > logs/serve.log 2>&1 &
LOGS_PID=$!
TPS_LOG="${TPS_LOG:-/tmp/mistral_base_throughput.tsv}"
TPS_TASK="${TPS_TASK:-$TASK}"
TPS_PID=""
cleanup() {
  if [[ -n "$TPS_PID" ]]; then kill "$TPS_PID" 2>/dev/null || true; fi
  kill "$LOGS_PID" 2>/dev/null || true
  "$DOCKER_BIN" stop --time 120 "$container_id" >/dev/null 2>&1 || true
  "$DOCKER_BIN" rm "$container_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT
mkdir -p "$(dirname "$TPS_LOG")"
if [[ ! -e "$TPS_LOG" ]]; then
  printf 'timestamp_utc\ttask\taggregate_generation_tps\trunning_requests\ttps_per_running_request\tmax_aggregate_tps\n' > "$TPS_LOG"
fi
(
  max_seen="$(awk -F '\t' 'NR > 1 && $3 + 0 > m { m = $3 + 0 } END { printf "%.1f", m + 0 }' "$TPS_LOG")"
  last_stats=""
  while kill -0 "$LOGS_PID" 2>/dev/null; do
    stats="$(grep -oE 'Avg generation throughput: [0-9]+([.][0-9]+)? tokens/s, Running: [0-9]+ reqs' logs/serve.log | tail -n 1 || true)"
    if [[ -n "$stats" && "$stats" != "$last_stats" ]]; then
      tps="${stats#Avg generation throughput: }"; tps="${tps%% tokens/s,*}"
      running="${stats##*, Running: }"; running="${running%% reqs}"
      max_seen="$(awk -v a="$tps" -v b="$max_seen" 'BEGIN { printf "%.1f", (a > b ? a : b) }')"
      per_request="$(awk -v a="$tps" -v n="$running" 'BEGIN { printf "%.2f", (n > 0 ? a / n : 0) }')"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$TPS_TASK" "$tps" "$running" "$per_request" "$max_seen" >> "$TPS_LOG"
      last_stats="$stats"
    fi
    sleep 5
  done
) &
TPS_PID=$!
until curl -sf "http://localhost:${PORT}/health" >/dev/null; do
  status="$("$DOCKER_BIN" inspect --format '{{.State.Status}}' "$container_id" 2>/dev/null || echo missing)"
  if [[ "$status" != running ]]; then
    echo "vLLM container exited (status: $status); see logs/serve.log" >&2
    cat logs/serve.log >&2
    exit 1
  fi
  sleep 10
done
source "$INSPECT_VENV/bin/activate"
./run_eval.sh "$@"
