#!/usr/bin/env bash
# Terminal-Bench 2.1 via the Harbor hub, run against the DSpark speculative-decoding server
# (serve.sh) with full model-API logging so every raw response, and therefore every
# `metrics.speculative_decoding` payload, lands in the .eval log.
#
# What this measures: the 89 tasks of Terminal-Bench 2.1 (Harbor hub package terminal-bench/terminal-bench-2-1,
# pinned to the digest below), solved agentically. Each task runs in its own prebuilt Docker container; the model
# gets bash/python tools through Inspect's ReAct agent and a hidden verifier decides pass/fail.
# The leaderboard and the Qwen model card use the Terminus 2 agent; this scaffold is different, so the numbers
# are not directly comparable (see README).
#
# --log-model-api keeps the raw request/response of *every* model API call in the log (default keeps only the
# first few calls per model plus errors). analyze_spec_decode.py reads those payloads.
# --max-tokens is per turn; 65536 leaves room for several turns inside the 262k context.
# --time-limit caps wall time per sample. Harbor's per-task agent timeouts range from 600 s to 12000 s (most 900 s);
# Inspect only supports one uniform limit, so 7200 s is used for every task.
# -T override_cpus=0 drops the per-container CPU cap (Harbor: 1 CPU for 83 of 89 tasks). Rootless Docker without
# CPU-controller delegation rejects `cpus`; 0 means no limit. Memory caps are kept (inspect_harbor floors them at 6 GB).
# --max-sandboxes equals --max-connections: Inspect holds one container per in-flight sample. Concurrency is
# sized to the KV pool, not to the task count. A TP=4 replica on 4x H100 holds 2,119,249 KV tokens; with the
# server's max_model_len of 262,144 the rule is concurrency * max_context <= 1.2 x pool, i.e.
# 1.2 * 2,119,249 / 262,144 = 9.7, so 9. (Raising it does not error: vLLM queues and evicts prefix-cached
# histories, re-prefilling a whole agent history on every turn.) Recheck "GPU KV cache size" in serve.log
# when changing TP, and keep MAX_SANDBOXES equal to MAX_CONNECTIONS.
# -M client_timeout raises Inspect's HTTP timeout (default 600s) for long reasoning turns.
# --fail-on-error 0.1 aborts only if >10% of samples hit infrastructure errors.
#
# Sampling params come from the base model's generation_config.json (temp 1.0, top_p 0.95, top_k 20).
# --reasoning-effort is forwarded by Inspect as the OpenAI `reasoning_effort` field; vLLM turns it
# into chat_template_kwargs {"enable_thinking": true, "reasoning_effort": "xhigh"} (see the recipe).
set -euo pipefail

MODEL="${MODEL:-RedHatAI/Qwen3.8-27B-speculator.dspark}"
PORT="${PORT:-8000}"
EPOCHS="${EPOCHS:-1}"
LOG_DIR="${LOG_DIR:-./logs}"

export VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:${PORT}/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-local}"

inspect eval inspect_harbor/terminal_bench_2_1 \
  -T ref=sha256:7d7bdc1cbedad549fc1140404bd4dc45e5fd0ea7c4186773687d177ad3a0699a \
  -T override_cpus=0 \
  --model "vllm/${MODEL}" \
  --epochs "$EPOCHS" --epochs-reducer mean \
  --temperature 1.0 --top-p 0.95 --top-k 20 \
  --reasoning-effort xhigh \
  --max-tokens "${MAX_TOKENS:-65536}" \
  --max-connections "${MAX_CONNECTIONS:-9}" \
  --max-sandboxes "${MAX_SANDBOXES:-9}" \
  --time-limit "${TIME_LIMIT:-7200}" \
  --fail-on-error 0.1 \
  --log-model-api \
  -M client_timeout=7200 \
  --log-dir "$LOG_DIR" \
  "$@"
