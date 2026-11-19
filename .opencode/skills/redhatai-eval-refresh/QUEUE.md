# RedHatAI models needing evaluations

Cached queue for the `redhatai-eval-refresh` skill (`.opencode/skills/redhatai-eval-refresh/SKILL.md`):
every quantized model in the `RedHatAI` org — excluding speculators, base models, and anything this
repo cannot serve — whose Hugging Face model card carries **3 or fewer evaluations** (distinct
benchmarks with the model's own reported scores). The skill regenerates this file before every
pick; it is committed to main so every host shares one queue. A model leaves the queue once its
card carries more than 3 evaluations.

- Last refreshed: 2026-11-18 (initial population, run by hand with the procedure in SKILL.md §1)
- Scope: **all** quantized models, as specified — including 2024-era GPTQ/marlin checkpoints and
  card-less compressed-tensors variants. The random pick is uniform over queue ∩ fits-on-GPUs.
- Model ids are HF repo ids (`https://huggingface.co/<id>`). Base-model ids ending in `?` were
  inferred from the checkpoint name (the repo has no model card to read) — resolve before use.
  `params (B)` / `ckpt (GB)` come from the HF API `safetensors` block at refresh time.

Refresh funnel: 810 org models → 491 quantized chat-model candidates (−45 speculators/dspark
drafts, −101 pruned/sparse/DeepSparse-era research checkpoints, −57 gguf/onnx, −20
non-generative pipelines, −3 safety classifiers, −93 without quantization signal) → 130 with ≤3
card evaluations → −16 failing verification (no `quantization_config`, or no chat template
found) → −9 quantizations of Qwen2.5 *base* models (Qwen2.5 base checkpoints ship a chat
template, so the template check alone does not exclude them) → **105 queued**.

## Queue

| # | model | base model | quant | arch | params (B) | ckpt (GB) | card evals | notes |
|---|---|---|---|---|---|---|---|---|
| 1 | RedHatAI/gemma-4-31B-it-NVFP4 | google/gemma-4-31B-it | NVFP4 | Gemma4ForConditionalGeneration | 32.7 | 30.4 | 0 | |
| 2 | RedHatAI/gemma-4-26B-A4B-it-FP8-dynamic | google/gemma-4-26B-A4B-it | FP8-dynamic | Gemma4ForConditionalGeneration | 26.5 | 24.7 | 0 | |
| 3 | RedHatAI/Muse-Glimmer-30B-NVFP4 | meta-models/Muse-Glimmer-30B | NVFP4 | MuseGlimmerForConditionalGeneration | 29.8 | 17.5 | 0 | |
| 4 | RedHatAI/yi-34b-chat-marlin | 01-ai/yi-34b-chat? | GPTQ int4 (marlin) | LlamaForCausalLM | 5.1 | 4.8 | 0 | no model card; base inferred |
| 5 | RedHatAI/zephyr-beta-7b-marlin | ? | GPTQ int4 (marlin) | MistralForCausalLM | 1.1 | 1.1 | 0 | no model card; base unresolved |
| 6 | RedHatAI/zephyr-7b-beta-marlin | HuggingFaceH4/zephyr-7b-beta | GPTQ int4 (marlin) | MistralForCausalLM | 1.2 | 1.1 | 0 | |
| 7 | RedHatAI/phi-2-super-marlin | ? | GPTQ int4 (marlin) | PhiForCausalLM | 0.6 | 0.6 | 0 | base unresolved |
| 8 | RedHatAI/TinyLlama-1.1B-Chat-v1.0-marlin | TinyLlama/TinyLlama-1.1B-Chat-v1.0 | GPTQ int4 (marlin) | LlamaForCausalLM | 0.3 | 0.2 | 0 | |
| 9 | RedHatAI/OpenHermes-2.5-Mistral-7B-marlin | teknium/OpenHermes-2.5-Mistral-7B | GPTQ int4 (marlin) | MistralForCausalLM | 1.2 | 1.1 | 0 | |
| 10 | RedHatAI/Nous-Hermes-2-Yi-34B-marlin | NousResearch/Nous-Hermes-2-Yi-34B | GPTQ int4 (marlin) | LlamaForCausalLM | 5.4 | 5.0 | 0 | |
| 11 | RedHatAI/Meta-Llama-3-8B-Instruct-FP8-KV | meta-llama/Meta-Llama-3-8B-Instruct | FP8 (AutoFP8, FP8 KV) | LlamaForCausalLM | 8.0 | 7.5 | 1 (GSM8K 5-shot) | |
| 12 | RedHatAI/Meta-Llama-3-70B-Instruct-FP8-KV | meta-llama/Meta-Llama-3-70B-Instruct? | FP8 (AutoFP8, FP8 KV) | LlamaForCausalLM | 70.6 | 65.7 | 1 | base inferred |
| 13 | RedHatAI/Mistral-7B-Instruct-v0.3-quantized.w8a8 | mistralai/Mistral-7B-Instruct-v0.3? | W8A8 | MistralForCausalLM | 7.3 | 6.8 | 0 | base inferred |
| 14 | RedHatAI/Mistral-Large-Instruct-2407-FP8 | mistralai/Mistral-Large-Instruct-2407? | FP8 | MistralForCausalLM | 122.6 | 114.2 | 0 | no model card; base inferred |
| 15 | RedHatAI/Llama-3.2-90B-Vision-Instruct-FP8-dynamic | meta-llama/Llama-3.2-90B-Vision-Instruct | FP8-dynamic | MllamaForConditionalGeneration | 88.6 | 82.5 | 0 | multimodal |
| 16 | RedHatAI/Qwen2.5-1.5B-Instruct-quantized.w8a8 | Qwen/Qwen2.5-1.5B-Instruct? | W8A8 | Qwen2ForCausalLM | 1.8 | 1.7 | 0 | no model card; base inferred |
| 17 | RedHatAI/Qwen2.5-3B-Instruct-quantized.w8a8 | Qwen/Qwen2.5-3B-Instruct? | W8A8 | Qwen2ForCausalLM | 3.4 | 3.2 | 0 | no model card; base inferred |
| 18 | RedHatAI/Qwen2.5-32B-Instruct-quantized.w8a8 | Qwen/Qwen2.5-32B-Instruct? | W8A8 | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 19 | RedHatAI/Qwen2.5-72B-Instruct-quantized.w8a8 | Qwen/Qwen2.5-72B-Instruct? | W8A8 | Qwen2ForCausalLM | 72.7 | 67.7 | 0 | no model card; base inferred |
| 20 | RedHatAI/Qwen2.5-0.5B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-0.5B-Instruct? | W8A16 | Qwen2ForCausalLM | 0.6 | 0.6 | 0 | no model card; base inferred |
| 21 | RedHatAI/Qwen2.5-7B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-7B-Instruct? | W8A16 | Qwen2ForCausalLM | 7.6 | 7.1 | 0 | no model card; base inferred |
| 22 | RedHatAI/Qwen2.5-32B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-32B-Instruct? | W8A16 | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 23 | RedHatAI/Qwen2.5-3B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-3B-Instruct? | W8A16 | Qwen2ForCausalLM | 3.4 | 3.2 | 0 | no model card; base inferred |
| 24 | RedHatAI/Qwen2.5-1.5B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-1.5B-Instruct? | W8A16 | Qwen2ForCausalLM | 1.8 | 1.7 | 0 | no model card; base inferred |
| 25 | RedHatAI/Qwen2.5-72B-Instruct-quantized.w8a16 | Qwen/Qwen2.5-72B-Instruct? | W8A16 | Qwen2ForCausalLM | 72.7 | 67.7 | 0 | no model card; base inferred |
| 26 | RedHatAI/Qwen2.5-72B-Instruct-quantized.w4a16 | Qwen/Qwen2.5-72B-Instruct? | W4A16 | Qwen2ForCausalLM | 72.7 | 67.7 | 0 | no model card; base inferred |
| 27 | RedHatAI/Qwen2.5-32B-Instruct-quantized.w4a16 | Qwen/Qwen2.5-32B-Instruct? | W4A16 | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 28 | RedHatAI/Qwen2.5-0.5B-Instruct-FP8-dynamic | Qwen/Qwen2.5-0.5B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 0.6 | 0.6 | 0 | no model card; base inferred |
| 29 | RedHatAI/Qwen2.5-1.5B-Instruct-FP8-dynamic | Qwen/Qwen2.5-1.5B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 1.8 | 1.7 | 0 | no model card; base inferred |
| 30 | RedHatAI/Qwen2.5-3B-Instruct-FP8-dynamic | Qwen/Qwen2.5-3B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 3.4 | 3.2 | 0 | no model card; base inferred |
| 31 | RedHatAI/Qwen2.5-32B-Instruct-FP8-dynamic | Qwen/Qwen2.5-32B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 32 | RedHatAI/Qwen2.5-Math-72B-Instruct-FP8-dynamic | Qwen/Qwen2.5-Math-72B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 72.7 | 67.7 | 0 | no model card; base inferred |
| 33 | RedHatAI/Qwen2.5-Coder-32B-Instruct-FP8-dynamic | Qwen/Qwen2.5-Coder-32B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 34 | RedHatAI/Qwen2.5-Coder-14B-Instruct-FP8-dynamic | Qwen/Qwen2.5-Coder-14B-Instruct | FP8-dynamic | Qwen2ForCausalLM | 14.8 | 13.8 | 0 | |
| 35 | RedHatAI/Qwen2.5-Coder-7B-Instruct-FP8-dynamic | Qwen/Qwen2.5-Coder-7B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 7.6 | 7.1 | 0 | no model card; base inferred |
| 36 | RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic | Qwen/Qwen2.5-72B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 72.7 | 67.7 | 0 | no model card; base inferred |
| 37 | RedHatAI/Qwen2.5-14B-Instruct-FP8-dynamic | Qwen/Qwen2.5-14B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 14.8 | 13.8 | 0 | no model card; base inferred |
| 38 | RedHatAI/Qwen2.5-Math-7B-Instruct-FP8-dynamic | Qwen/Qwen2.5-Math-7B-Instruct? | FP8-dynamic | Qwen2ForCausalLM | 7.6 | 7.1 | 0 | no model card; base inferred |
| 39 | RedHatAI/Phi-3-vision-128k-instruct-W4A16-G128 | microsoft/Phi-3-vision-128k-instruct | W4A16 | Phi3VForCausalLM | 4.3 | 4.0 | 0 | multimodal |
| 40 | RedHatAI/DeepSeek-R1-Llama-70B-quantized.w8a8 | deepseek-ai/DeepSeek-R1-Llama-70B? | W8A8 | LlamaForCausalLM | 70.6 | 65.7 | 0 | no model card; base inferred |
| 41 | RedHatAI/Phi-4-mini-instruct-quantized.w8a8 | microsoft/Phi-4-mini-instruct? | W8A8 | Phi3ForCausalLM | 4.5 | 4.1 | 0 | no model card; base inferred |
| 42 | RedHatAI/QwQ-32B-quantized.w8a8 | Qwen/QwQ-32B? | W8A8 | Qwen2ForCausalLM | 32.8 | 30.5 | 0 | no model card; base inferred |
| 43 | RedHatAI/Llama-4-Maverick-17B-128E-Instruct-FP8 | meta-llama/Llama-4-Maverick-17B-128E-Instruct | FP8 | Llama4ForConditionalGeneration | 401.7 | 374.1 | 0 | multimodal MoE |
| 44 | RedHatAI/gemma-3-1b-it-FP8-dynamic | google/gemma-3-1b-it? | FP8-dynamic | Gemma3ForCausalLM | 1.3 | 1.2 | 0 | no model card; base inferred |
| 45 | RedHatAI/Qwen3-0.6B-FP8-BLOCK | Qwen/Qwen3-0.6B? | FP8-block | Qwen3ForCausalLM | 0.6 | 0.6 | 0 | no model card; base inferred |
| 46 | RedHatAI/watt-tool-8B-FP8-dynamic | ? | FP8-dynamic | LlamaForCausalLM | 8.0 | 7.5 | 0 | no model card; base unresolved |
| 47 | RedHatAI/ToolACE-2-Llama-3.1-8B-FP8-dynamic | ? | FP8-dynamic | LlamaForCausalLM | 8.0 | 7.5 | 0 | no model card; base unresolved |
| 48 | RedHatAI/Kimi-K2-Instruct-quantized.w4a16 | moonshotai/Kimi-K2-Instruct | W4A16 | DeepseekV3ForCausalLM | 1034.3 | 963.3 | 0 | |
| 49 | RedHatAI/SmolLM3-3B-FP8-dynamic | HuggingFaceTB/SmolLM3-3B | FP8-dynamic | SmolLM3ForCausalLM | 3.1 | 2.9 | 3 (AIME24, MATH-500, GPQA-Diamond) | |
| 50 | RedHatAI/SmolLM3-3B-quantized.w4a16 | HuggingFaceTB/SmolLM3-3B | W4A16 | SmolLM3ForCausalLM | 3.4 | 3.2 | 3 (AIME24, MATH-500, GPQA-Diamond) | |
| 51 | RedHatAI/Qwen3-Coder-480B-A35B-Instruct-FP8 | Qwen/Qwen3-Coder-480B-A35B-Instruct | FP8 | Qwen3MoeForCausalLM | 480.2 | 447.2 | 0 | |
| 52 | RedHatAI/gpt-oss-120b | openai/gpt-oss-120b | MXFP4 | GptOssForCausalLM | 120.4 | 112.1 | 0 | requant of an already-MXFP4 checkpoint |
| 53 | RedHatAI/gpt-oss-20b | openai/gpt-oss-20b | MXFP4 | GptOssForCausalLM | 21.5 | 20.0 | 0 | requant of an already-MXFP4 checkpoint |
| 54 | RedHatAI/Kimi-K2-Thinking-FP8-Block | moonshotai/Kimi-K2-Thinking? | FP8-block | DeepseekV3ForCausalLM | 1026.5 | 956.0 | 0 | no model card; base inferred |
| 55 | RedHatAI/Qwen3-VL-32B-Instruct-FP8-dynamic | Qwen/Qwen3-VL-32B-Instruct | FP8-dynamic | Qwen3VLForConditionalGeneration | 33.4 | 31.1 | 0 | multimodal |
| 56 | RedHatAI/Qwen3-VL-32B-Instruct-FP8-block | Qwen/Qwen3-VL-32B-Instruct | FP8-block | Qwen3VLForConditionalGeneration | 33.4 | 31.1 | 0 | multimodal |
| 57 | RedHatAI/Qwen3-VL-32B-Instruct-NVFP4 | Qwen/Qwen3-VL-32B-Instruct | NVFP4 | Qwen3VLForConditionalGeneration | 19.7 | 18.4 | 0 | multimodal |
| 58 | RedHatAI/Qwen3-Next-80B-A3B-Instruct-NVFP4 | Qwen/Qwen3-Next-80B-A3B-Instruct | NVFP4 | Qwen3NextForCausalLM | — | — | 0 | size unknown — refetch at pick time |
| 59 | RedHatAI/GLM-4.6-FP8 | zai-org/GLM-4.6? | FP8 | Glm4MoeForCausalLM | 358.5 | 333.8 | 0 | base inferred |
| 60 | RedHatAI/Qwen3-Next-80B-A3B-Thinking-FP8-block | Qwen/Qwen3-Next-80B-A3B-Thinking | FP8-block | Qwen3NextForCausalLM | 79.7 | 74.2 | 3 (AIME 2025, MATH-500, GPQA Diamond) | |
| 61 | RedHatAI/Qwen3-Next-80B-A3B-Thinking-NVFP4 | Qwen/Qwen3-Next-80B-A3B-Thinking | NVFP4 | Qwen3NextForCausalLM | — | — | 0 | size unknown — refetch at pick time |
| 62 | RedHatAI/DeepSeek-R1-NVFP4-FP8-BLOCK | deepseek-ai/DeepSeek-R1 | NVFP4-FP8 | DeepseekV3ForCausalLM | 396.8 | 369.5 | 0 | |
| 63 | RedHatAI/Qwen3-Coder-Next-NVFP4 | Qwen/Qwen3-Coder-Next | NVFP4 | Qwen3NextForCausalLM | — | — | 1 | size unknown — refetch at pick time |
| 64 | RedHatAI/MiniMax-M2.5 | MiniMaxAI/MiniMax-M2.5? | FP8 | MiniMaxM2ForCausalLM | 228.7 | 213.0 | 0 | base inferred |
| 65 | RedHatAI/Qwen3-Coder-Next-FP8-dynamic | Qwen/Qwen3-Coder-Next | FP8-dynamic | Qwen3NextForCausalLM | 79.8 | 74.3 | 1 | |
| 66 | RedHatAI/Ministral-3-3B-Instruct-2512 | mistralai/Ministral-3-3B-Instruct-2512? | FP8 | Mistral3ForConditionalGeneration | 3.9 | 3.6 | 0 | card tag names the Base checkpoint — verify base |
| 67 | RedHatAI/DeepSeek-V3.2-NVFP4-FP8-BLOCK | deepseek-ai/DeepSeek-V3.2 | NVFP4-FP8 | DeepseekV32ForCausalLM | 384.2 | 357.8 | 0 | |
| 68 | RedHatAI/Mistral-Small-4-119B-2603 | mistralai/Mistral-Small-4-119B-2603 | FP8 | Mistral3ForConditionalGeneration | 119.4 | 111.2 | 0 | |
| 69 | RedHatAI/Trinity-Large-Thinking-NVFP4 | arcee-ai/Trinity-Large-Thinking | NVFP4 | AfmoeForCausalLM | 226.4 | 210.9 | 0 | |
| 70 | RedHatAI/gemma-4-31B-it-FP8-block | google/gemma-4-31B-it | FP8-block | Gemma4ForConditionalGeneration | 31.3 | 29.1 | 0 | |
| 71 | RedHatAI/gemma-4-26B-A4B-it-NVFP4 | google/gemma-4-26B-A4B-it | NVFP4 | Gemma4ForConditionalGeneration | 25.8 | 24.0 | 0 | |
| 72 | RedHatAI/gemma-4-31B-it-FP8-dynamic | google/gemma-4-31B-it | FP8-dynamic | Gemma4ForConditionalGeneration | 31.3 | 29.1 | 0 | |
| 73 | RedHatAI/gpt-oss-20b-essential | openai/gpt-oss-20b | MXFP4 | GptOssForCausalLM | 21.5 | 20.0 | 0 | |
| 74 | RedHatAI/gpt-oss-120b-essential | openai/gpt-oss-120b | MXFP4 | GptOssForCausalLM | 116.8 | 108.8 | 0 | |
| 75 | RedHatAI/Qwen3.6-27B-FP8 | Qwen/Qwen3.6-27B | FP8 | Qwen3_5ForConditionalGeneration | 27.8 | 25.9 | 0 | |
| 76 | RedHatAI/command-a-plus-05-2026-w4a4 | CohereLabs/command-a-plus-05-2026-bf16 | W4A4 | Cohere2VisionForConditionalGeneration | 125.8 | 117.2 | 0 | multimodal |
| 77 | RedHatAI/Mellum2-12B-A2.5B-Thinking-FP8-Dynamic | JetBrains/Mellum2-12B-A2.5B-Thinking | FP8-dynamic | MellumForCausalLM | 12.2 | 11.3 | 0 | code model |
| 78 | RedHatAI/Mellum2-12B-A2.5B-Thinking-NVFP4 | JetBrains/Mellum2-12B-A2.5B-Thinking | NVFP4 | MellumForCausalLM | 7.0 | 6.6 | 0 | code model |
| 79 | RedHatAI/NVIDIA-Nemotron-3-Ultra-550B-A55B-FP8-block | nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-BF16 | FP8-block | NemotronHForCausalLM | 560.5 | 522.0 | 0 | |
| 80 | RedHatAI/NVIDIA-Nemotron-3-Ultra-550B-A55B-quantized.w4a16 | nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-BF16 | W4A16 | NemotronHForCausalLM | 560.5 | 522.0 | 0 | |
| 81 | RedHatAI/Mistral-Medium-3.5-128B | mistralai/Mistral-Medium-3.5-128B | FP8 | Mistral3ForConditionalGeneration | 127.7 | 118.9 | 0 | |
| 82 | RedHatAI/GLM-5.2-NVFP4-FP8 | zai-org/GLM-5.2 | NVFP4-FP8 | GlmMoeDsaForCausalLM | 753.3 | 395.6 | 1 (GPQA Diamond) | |
| 83 | RedHatAI/GLM-5.2-NVFP4 | zai-org/GLM-5.2 | NVFP4 | GlmMoeDsaForCausalLM | 426.0 | 396.7 | 0 | |
| 84 | RedHatAI/Hy3-NVFP4-FP8 | tencent/Hy3 | NVFP4-FP8 | HYV3ForCausalLM | 298.8 | 278.3 | 0 | |
| 85 | RedHatAI/Inkling-FP8-dynamic | thinkingmachines/Inkling | FP8-dynamic | InklingForConditionalGeneration | 952.6 | 887.2 | 0 | |
| 86 | RedHatAI/Inkling-FP8-block | thinkingmachines/Inkling | FP8-block | InklingForConditionalGeneration | 952.4 | 887.0 | 0 | |
| 87 | RedHatAI/Inkling-NVFP4-FP8-BLOCK | thinkingmachines/Inkling | NVFP4-FP8 | InklingForConditionalGeneration | 952.4 | 887.0 | 1 (GPQA Diamond) | |
| 88 | RedHatAI/Ornith-1.0-35B-FP8-BLOCK | deepreinforce-ai/Ornith-1.0-35B | FP8-block | Qwen3_5MoeForConditionalGeneration | 35.1 | 32.7 | 0 | |
| 89 | RedHatAI/Ornith-1.0-35B-NVFP4 | deepreinforce-ai/Ornith-1.0-35B | NVFP4 | Qwen3_5MoeForConditionalGeneration | 35.1 | 19.4 | 0 | |
| 90 | RedHatAI/Inkling-Small-FP8-dynamic | thinkingmachines/Inkling-Small | FP8-dynamic | InklingForConditionalGeneration | 266.0 | 247.8 | 0 | |
| 91 | RedHatAI/Muse-Glimmer-30B-FP8-block | meta-models/Muse-Glimmer-30B | FP8-block | MuseGlimmerForConditionalGeneration | 29.8 | 27.7 | 0 | |
| 92 | RedHatAI/Muse-Glimmer-30B-INT4 | meta-models/Muse-Glimmer-30B | INT4 | MuseGlimmerForConditionalGeneration | 29.8 | 7.4 | 0 | |
| 93 | RedHatAI/Qwen3.8-2.4T-A95B-NVFP4 | Qwen/Qwen3.8-2.4T-A95B | NVFP4 | Qwen3_5MoeForCausalLM | 2419.8 | 1285.7 | 2 (GPQA Diamond, DeepSWE 1.1) | |
| 94 | RedHatAI/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-FP8 | nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16 | FP8 | NemotronHForCausalLM | 31.6 | 29.4 | 0 | |
| 95 | RedHatAI/Qwen3.8-2.4T-A95B-NVFP4-FP8 | Qwen/Qwen3.8-2.4T-A95B | NVFP4-FP8 | Qwen3_5MoeForCausalLM | 2419.8 | 1285.7 | 1 (GPQA Diamond) | |
| 96 | RedHatAI/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 | nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16? | NVFP4 (modelopt) | NemotronHForCausalLM | 32.9 | 30.7 | 0 | base inferred |
| 97 | RedHatAI/Qwen3.8-2.4T-A95B-NVFP4-REAP-25 | Qwen/Qwen3.8-2.4T-A95B | NVFP4 (REAP 25%) | Qwen3_5MoeForCausalLM | 1853.4 | 1726.1 | 2 (GPQA Diamond, DeepSWE 1.1) | |
| 98 | RedHatAI/Qwen3.8-2.4T-A95B-NVFP4-REAP-50 | Qwen/Qwen3.8-2.4T-A95B | NVFP4 (REAP 50%) | Qwen3_5MoeForCausalLM | 1260.6 | 1174.0 | 2 (GPQA Diamond, DeepSWE 1.1) | |
| 99 | RedHatAI/GLM-5.3-Flash | zai-org/GLM-5.3-Flash? | FP8 | Glm5NextForConditionalGeneration | 321.3 | 299.3 | 0 | base inferred |
| 100 | RedHatAI/GLM-5.3-MXFP4xFP8 | zai-org/GLM-5.3 | MXFP4xFP8 | GlmMoeDsaForCausalLM | 390.6 | 363.8 | 2 (DeepSWE 1.1, Terminal-Bench 2.1) | |
| 101 | RedHatAI/DeepSeek-V4-Flash-0731-NVFP4 | deepseek-ai/DeepSeek-V4-Flash-0731 | NVFP4 | DeepseekV4ForCausalLM | 145.8 | 135.8 | 0 | |
| 102 | RedHatAI/Kimi-K3-INT4 | moonshotai/Kimi-K3 | INT4 | KimiK3ForConditionalGeneration | 2779.9 | 2589.0 | 2 (MATH-500, GPQA Diamond) | |
| 103 | RedHatAI/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-FP8 | nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-BF16 | FP8 | NemotronH_Omni_Reasoning_V3 | 124.5 | 115.9 | 0 | multimodal |
| 104 | RedHatAI/Qwen3.8-27B-FP8 | Qwen/Qwen3.8-27B | FP8 | Qwen3_5ForConditionalGeneration | 27.8 | 25.9 | 0 | |
| 105 | RedHatAI/Ripple-65B-Preview-NVFP4 | ricursiveAI/Ripple-65B-Preview | NVFP4 | RicursiveForCausalLM | 64.8 | 39.8 | 1 (Terminal-Bench 2.1, 89 tasks) | |

## Excluded at the last verification step

These passed the tag filters and the ≤3-evaluation count but were dropped at verification. The
"no chat template" exclusions can be tokenizer quirks (a template in a nonstandard file, or a
Llama-2-era template that only lived in code) — re-check them on refresh before trusting the
exclusion.

| model | reason |
|---|---|
| RedHatAI/llama-2-7b-chat-marlin | no chat template found (Llama-2 templates lived in code — re-check) |
| RedHatAI/Meta-Llama-3.1-70B-quantized.w8a16 | no chat template (base-model quantization) |
| RedHatAI/Meta-Llama-3.1-70B-quantized.w8a8 | no chat template (base-model quantization) |
| RedHatAI/Llama-3.2-1B-quantized.w8a8 | no chat template (base-model quantization) |
| RedHatAI/Llama-3.2-3B-quantized.w8a8 | no chat template (base-model quantization) |
| RedHatAI/Llama-3.2-1B-FP8 | no chat template (base-model quantization) |
| RedHatAI/phi-4 | no `quantization_config` (not a quantized checkpoint) |
| RedHatAI/Mistral-Small-4-119B-2603-NVFP4 | no `quantization_config` (not a quantized checkpoint) |
| RedHatAI/DeepSeek-V4-Pro | no chat template found |
| RedHatAI/DeepSeek-V4-Flash | no chat template found |
| RedHatAI/DeepSeek-V4-Pro-NVFP4-FP8 | no chat template found |
| RedHatAI/Kimi-K3-FP8-BLOCK | no chat template found |
| RedHatAI/Kimi-K3-NVFP4 | no chat template found |
| RedHatAI/DeepSeek-V4-Pro-0813 | no chat template found |
| RedHatAI/DeepSeek-V4.1-Flash | no chat template found |
| RedHatAI/DeepSeek-V4-Flash-0731 | no chat template found |
| RedHatAI/Qwen2.5-32B-quantized.w8a8 | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-72B-quantized.w4a16 | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-32B-quantized.w4a16 | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-32B-FP8-dynamic | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-Math-72B-FP8-dynamic | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-Coder-32B-FP8-dynamic | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-Coder-14B-FP8-dynamic | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-Math-7B-FP8-dynamic | quantization of a Qwen2.5 base model |
| RedHatAI/Qwen2.5-Coder-7B-FP8-dynamic | quantization of a Qwen2.5 base model |

## Completed by this skill

| date | model | GPQA-Diamond | MMLU-Pro | SWE-bench Verified | Terminal-Bench 2.1 | baseline | card section |
|---|---|---|---|---|---|---|---|
| — | | | | | | | |
