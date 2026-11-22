#!/usr/bin/env bash
# Native FP8 GLM-5.3 plus the final step-8090 DFlash2 drafter, on vLLM 0.34.0.
# Target recipe: https://recipes.vllm.ai/zai-org/GLM-5.3
# local_orchestrator.sh supplies the two pinned local snapshots.
# Keep the measured API alias zai-org/GLM-5.3, distinct from the draft artifact.
# The generic class override exposes the draft's six auxiliary target layers.
set -euo pipefail

MODEL="${MODEL:-zai-org/GLM-5.3}"
: "${MODEL_PATH:?Set MODEL_PATH to the pinned GLM-5.3 snapshot}"
: "${SPECULATOR:?Set SPECULATOR to the pinned step-8090 snapshot}"
PORT="${PORT:-19221}"
TP="${TP:-8}"
DP="${DP:-1}"

exec vllm serve "$MODEL_PATH" \
  --served-model-name "$MODEL" \
  --host 127.0.0.1 --port "$PORT" \
  --tensor-parallel-size "$TP" --data-parallel-size "$DP" \
  --dtype bfloat16 --kv-cache-dtype fp8 \
  --max-model-len "${MAX_MODEL_LEN:-262144}" \
  --max-num-seqs "${MAX_NUM_SEQS:-128}" \
  --gpu-memory-utilization 0.85 \
  --enable-prefix-caching \
  --compilation-config '{"cudagraph_mode":"FULL_AND_PIECEWISE"}' \
  --tokenizer-mode glm5_next \
  --enable-auto-tool-choice --tool-call-parser glm47 \
  --reasoning-parser glm47 \
  --default-chat-template-kwargs '{"reasoning_effort":"max"}' \
  --speculative-config "{\"method\":\"dflash\",\"model\":\"${SPECULATOR}\",\"num_speculative_tokens\":8,\"kv_cache_dtype\":\"fp8\",\"enable_adaptive_verification\":false}" \
  --per-request-spec-decode-metrics detailed \
  --enable-force-include-usage \
  --model-class-overrides '{"GlmMoeDsaForCausalLM":"vllm.model_executor.models.deepseek_v2:GlmMoeDsaForCausalLM"}'
