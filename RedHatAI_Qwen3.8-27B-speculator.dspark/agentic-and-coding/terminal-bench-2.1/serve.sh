#!/usr/bin/env bash
# Serve Qwen/Qwen3.8-27B with vLLM, speculative decoding against the DSpark draft model
# RedHatAI/Qwen3.8-27B-speculator.dspark, and per-request spec-decode acceptance metrics in every response.
#
# Target flags follow the official vLLM recipe: https://recipes.vllm.ai/Qwen/Qwen3.8-27B
# The recipe's "DSpark (opt-in)" section names this exact speculator and num_speculative_tokens 8.
# --per-request-spec-decode-metrics is experimental in vLLM 0.32.0: it puts
# `metrics.speculative_decoding` in every chat-completion response (single-sequence requests only).
set -euo pipefail

MODEL="${MODEL:-Qwen/Qwen3.8-27B}"
SPECULATOR="${SPECULATOR:-RedHatAI/Qwen3.8-27B-speculator.dspark}"
NUM_SPEC_TOKENS="${NUM_SPEC_TOKENS:-8}"
PORT="${PORT:-8000}"
TP="${TP:-4}"   # 27B bf16 + DSpark draft on 4x H100; the draft shards with the target
DP="${DP:-1}"   # one replica = one prefix cache for the agent's multi-turn histories

exec vllm serve "$MODEL" \
  --tensor-parallel-size "$TP" \
  --data-parallel-size "$DP" \
  --max-model-len 262144 \
  --reasoning-parser qwen3 \
  --default-chat-template-kwargs '{"enable_thinking": true, "reasoning_effort": "xhigh"}' \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --speculative-config "{\"method\":\"dspark\",\"model\":\"${SPECULATOR}\",\"num_speculative_tokens\":${NUM_SPEC_TOKENS}}" \
  --per-request-spec-decode-metrics detailed \
  --served-model-name "$SPECULATOR" \
  --host 0.0.0.0 --port "$PORT"
