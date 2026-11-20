# nvidia/Qwen3.8-27B-NVFP4 — MRCR

| | |
|---|---|
| Task | `inspect_evals/mrcr` (openai/mrcr @ `f4c69fae7cf81f7ca26b9fee34b392a50f6b8a1d`, 2/4/8-needle combined; filtered to served `max_model_len=262144`) |
| Category | long-context (subclass: long-context) |
| Exec tier | `none` — no Docker, no sandbox, no tools |
| vLLM recipe | https://recipes.vllm.ai/Qwen/Qwen3.8-27B (NVFP4 NVIDIA variant); model card https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4 |

The Qwen3.8-27B card reports Context Arena / GDM-MRCRv2 averages over runs that include contexts up to 1M (YaRN). This dir serves the native 262,144 window (recipe NVFP4 path, no YaRN), so samples longer than that are dropped by the task's `max_model_len` filter and the number is not comparable to the card's full 1M figure. Sampling matches `generation_config.json` (temperature 1.0, top_p 0.95, top_k 20) with thinking at `xhigh`. Topology: TP=1 × DP=4 (user request). Checkpoint uses mixed NVFP4/FP8 (`quantization=modelopt_mixed`); vLLM selected FlashInferCuteDslNvFp4LinearKernel for NVFP4 GEMM.

## Files

- `serve.sh` — deploys the model with a vLLM server. vLLM-serve arguments live here
  (parallelism, context length, reasoning/tool parsers), taken from the official recipe.
- `run_eval.sh` — runs the Inspect task against that server. Inspect-side params live here
  (task, epochs, sampling params, reasoning effort, concurrency, `max_model_len`).
- `server_requirements.txt` / `client_requirements.txt` — `pip freeze` of the vLLM and Inspect
  venvs that produced the results below, with the host (GPUs, driver, CUDA, Python) in the header.
- `local_orchestrator.sh` — runs everything in your local dev environment: activates the
  venvs, sets GPUs, starts `serve.sh` in the background, runs `run_eval.sh`, tears down.
  **This is the only file you should modify** to match the environment you run in.

## Run

### Setup (once per host)

Create a server and a client environment as below. The commands use the paths that `local_orchestrator.sh` activates;
if you keep the environments elsewhere, change the paths there. `server_requirements.txt` and
`client_requirements.txt` are the exact `pip freeze` of the environments that produced the results below:

```bash
# server: vLLM 0.34.0 (CUDA 13 wheels; add the matching https://download.pytorch.org/whl/<cuXXX> index if pip cannot resolve torch)
python3.12 -m venv ~/.venvs/vllm && source ~/.venvs/vllm/bin/activate
pip install -r server_requirements.txt          # or: pip install vllm==0.34.0 "transformers>=5.8.0"
# client: Inspect + neuralmagic/inspect_evals (MRCR lives on this fork, not on PyPI)
python3.12 -m venv ~/.venvs/inspect && source ~/.venvs/inspect/bin/activate
pip install -r client_requirements.txt          # or:
# pip install "git+https://github.com/neuralmagic/inspect_evals.git@e64c20fd6c49b4848461090630699d398ead7ba0" openai "transformers>=5.8.0"
```

Pre-download the weights into the HF hub cache and export `HF_HUB_OFFLINE=1` for the server only so DP
workers do not hit Hub rate limits. Export `HF_TOKEN` in your shell if needed (never in the repo).

### Run the eval

```bash
EPOCHS=1 ./local_orchestrator.sh --limit 5   # smoke test; inspect the samples first
./local_orchestrator.sh
inspect view --log-dir ./logs
```

## Results

With model generation config:

`temperature=1.0, top_p=0.95, top_k=20, reasoning_effort=xhigh, max_model_len=262144, gen_kwargs={temperature:1.0, top_p:0.95, top_k:20}, max_connections=32, client_timeout=7200, epochs=1`

the following scores and token stats are obtained:

| metric | value |
|---|---|
| mrcr_2needle (pass@1) | 0.976 (589 of 589) |
| mrcr_2needle stderr | 0.00521 |
| mrcr_2needle auc | 97.32 |
| mrcr_4needle (pass@1) | 0.934 (591 of 591) |
| mrcr_4needle stderr | 0.00951 |
| mrcr_4needle auc | 92.35 |
| mrcr_8needle (pass@1) | 0.799 (593 of 593) |
| mrcr_8needle stderr | 0.0156 |
| mrcr_8needle auc | 74.63 |
| samples | 1773 (589 / 591 / 593 after filtering 211 / 209 / 207 of 800 per needle count that exceeded `max_model_len=262144`) |
| truncated (stop_reason=max_tokens) | 5 |
| sample errors | 0 |

| tokens / sample | input | output | reasoning |
|---|---|---|---|
| mean | 64,080 | 1,199 | 815 |
| median | 32,951 | 883 | 536 |
| max | 261,618 | 21,022 | 20,765 |

Reasoning is parsed into a separate content part for every sample (1773/1773).

MRCR writes a plain-text metrics summary beside the `.eval` log. Full `.txt` contents:

```
mrcr_2needle 0.976438006337401
mrcr_2needle_auc 97.3225951588402
mrcr_2needle_overall 0.976438006337401
mrcr_2needle_mean 0.976438006337401
mrcr_2needle_stderr 0.005210007984211018
mrcr_2needle_count_gt_0_le_8k 100.0
mrcr_2needle_gt_0_le_8k 0.9922354107107858
mrcr_2needle_stderr_gt_0_le_8k 0.006102044135048192
mrcr_2needle_count_gt_32k_le_64k 97.0
mrcr_2needle_gt_32k_le_64k 0.9721179826998593
mrcr_2needle_stderr_gt_32k_le_64k 0.013582034769765924
mrcr_2needle_count_gt_8k_le_16k 94.0
mrcr_2needle_gt_8k_le_16k 0.9818436507893875
mrcr_2needle_stderr_gt_8k_le_16k 0.012257717100949443
mrcr_2needle_count_gt_16k_le_32k 101.0
mrcr_2needle_gt_16k_le_32k 0.9713300718683456
mrcr_2needle_stderr_gt_16k_le_32k 0.013866245773665568
mrcr_2needle_count_gt_64k_le_128k 100.0
mrcr_2needle_gt_64k_le_128k 0.9819675047173579
mrcr_2needle_stderr_gt_64k_le_128k 0.011817563521903425
mrcr_2needle_count_gt_128k_le_256k 97.0
mrcr_2needle_gt_128k_le_256k 0.9588516436610629
mrcr_2needle_stderr_gt_128k_le_256k 0.016745614370563492
mrcr_4needle 0.9343692791770007
mrcr_4needle_auc 92.35418360843802
mrcr_4needle_overall 0.9343692791770007
mrcr_4needle_mean 0.9343692791770007
mrcr_4needle_stderr 0.009510908196879279
mrcr_4needle_count_gt_128k_le_256k 104.0
mrcr_4needle_gt_128k_le_256k 0.8334504413843147
mrcr_4needle_stderr_gt_128k_le_256k 0.033946896634616856
mrcr_4needle_count_gt_8k_le_16k 95.0
mrcr_4needle_gt_8k_le_16k 0.9636798575490243
mrcr_4needle_stderr_gt_8k_le_16k 0.01807226680178634
mrcr_4needle_count_gt_16k_le_32k 94.0
mrcr_4needle_gt_16k_le_32k 0.9637117863511189
mrcr_4needle_stderr_gt_16k_le_32k 0.017243962639277362
mrcr_4needle_count_gt_32k_le_64k 101.0
mrcr_4needle_gt_32k_le_64k 0.91803978791909
mrcr_4needle_stderr_gt_32k_le_64k 0.025825646363130235
mrcr_4needle_count_gt_64k_le_128k 95.0
mrcr_4needle_gt_64k_le_128k 0.9695096540003907
mrcr_4needle_stderr_gt_64k_le_128k 0.016511337803973
mrcr_4needle_count_gt_0_le_8k 102.0
mrcr_4needle_gt_0_le_8k 0.9663673332903047
mrcr_4needle_stderr_gt_0_le_8k 0.017177556210336172
mrcr_8needle 0.7992995623728488
mrcr_8needle_auc 74.63231004206915
mrcr_8needle_overall 0.7992995623728488
mrcr_8needle_mean 0.7992995623728488
mrcr_8needle_stderr 0.01557486887639485
mrcr_8needle_count_gt_32k_le_64k 97.0
mrcr_8needle_gt_32k_le_64k 0.7607017529250117
mrcr_8needle_stderr_gt_32k_le_64k 0.04102696600687505
mrcr_8needle_count_gt_16k_le_32k 98.0
mrcr_8needle_gt_16k_le_32k 0.873625615702106
mrcr_8needle_stderr_gt_16k_le_32k 0.03210456092780189
mrcr_8needle_count_gt_128k_le_256k 101.0
mrcr_8needle_gt_128k_le_256k 0.5556869667826776
mrcr_8needle_stderr_gt_128k_le_256k 0.04573052013726461
mrcr_8needle_count_gt_64k_le_128k 101.0
mrcr_8needle_gt_64k_le_128k 0.8070064877270575
mrcr_8needle_stderr_gt_64k_le_128k 0.03690557120498893
mrcr_8needle_count_gt_8k_le_16k 94.0
mrcr_8needle_gt_8k_le_16k 0.9179586401712218
mrcr_8needle_stderr_gt_8k_le_16k 0.027426399098193353
mrcr_8needle_count_gt_0_le_8k 102.0
mrcr_8needle_gt_0_le_8k 0.8888344022842035
mrcr_8needle_stderr_gt_0_le_8k 0.03021427899591075
```

Serving was `TP=1 DP=4` on four B200s (~4.52M KV tokens per replica at 262144; `--max-connections 32`). Wall time about 27 min of eval after server start + exact-tokenizer filtering.

## Patches for upstream

Client pinned to `neuralmagic/inspect_evals@e64c20fd` (`update_mrcr`): per-needle metric blocks and the `.txt` metrics summary beside the `.eval` log. Once that lands on `main`, point the pin at the upstream commit instead.
