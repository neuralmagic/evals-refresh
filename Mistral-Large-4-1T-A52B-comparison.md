# Mistral Large 4 base vs. MXFP4×FP8 results

The base model is `mistralai/Mistral-Large-4-1T-A52B` (revision `af26e7869af601441d5cdf75a1272469ddc3d059`); the compressed model is `RedHatAI/Mistral-Large-4-1T-A52B-MXFP4xFP8` (revision `f17a8e90adfbd83a51ecceb28e2017ee600828ae`). The later GPQA, MMLU 0-shot, and SWE-bench comparisons used 8×B300 for base and 8×H200 for compressed. The MMLU-Pro pair comes from earlier full-run logs.

| Benchmark | Base | MXFP4×FP8 | Δ (base − compressed) |
|---|---:|---:|---:|
| GPQA Diamond, 198 questions | 182/198 (91.92%) | 178/198 (89.90%)¹ | **+2.02 pp** |
| MMLU-Pro, 12,032 questions | 10,480/12,032 (87.10%) | 10,490/12,032 (87.18%) | **−0.08 pp** |
| MMLU 0-shot, 13,937 questions | 12,614/13,937 (90.51%) | 12,642/13,937 (90.71%) | **−0.20 pp** |
| SWE-bench Verified, 500 tasks | 385/500 (77.00%)² | 377/500 (75.40%)³ | **+1.60 pp** |

Positive deltas favor the base model. These are single-run, one-epoch results; there is no multi-seed average. Both models used temperature 1.0, top-p 0.95, high reasoning, and one epoch. MMLU 0-shot used 16,384 max output tokens; its server connection limit differed (base 8, compressed 2). SWE-bench used the same pinned test split, task revision, response cap, and time/message limits.

The MMLU-Pro standard errors were 0.31 percentage points for base and 0.30 for compressed. MMLU 0-shot standard errors were 0.25 points for each. The observed gaps on those tasks are smaller than one standard error.

¹ The compressed GPQA score combines a 198-question run at 65,536 max output tokens and a 14-question retry at 131,072. The main run scored 171/198; all 14 retried IDs were originally wrong or capped, and 7/14 passed on retry, giving 178/198. This combined score is computed across the two logs.

² The base SWE-bench score combines 497 scored cases in the full run with a separate retry of its three Docker startup failures. The retry IDs exactly match those three missing scores; two passed and one failed, so all 500 unique tasks now have scores.

³ The compressed SWE-bench score is computed from two disjoint raw logs: an initial 400-task run and a 100-task continuation. Together they cover all 500 instances, with 377 resolved and 123 unresolved.

## Interpretation

The base model scored higher on GPQA Diamond and SWE-bench Verified. The compressed model scored slightly higher on both MMLU evaluations. The small MMLU gaps are descriptive results from one run per model. Throughput is not compared because the models ran on different GPU types.

DeepSWE 1.1 has not been run on either checkpoint, so there is no result for that benchmark.

The base vLLM server is stopped. I verified all eight GPUs had 0 MiB allocated afterward.

## Logs

### Base model

- [GPQA Diamond, 131k cap](mistralai_Mistral-Large-4-1T-A52B/knowledge-and-reasoning/gpqa-diamond-64k/logs/base-gpqa-131k/2026-11-17T21-42-17-00-00_gpqa-diamond_WFY4KgXSkRZcPoWS4gaxu7.eval)
- [MMLU 0-shot](mistralai_Mistral-Large-4-1T-A52B/knowledge-and-reasoning/mmlu/logs/base-mmlu-0-shot/2026-11-18T15-13-11-00-00_mmlu-0-shot_TTEPnSQbwdZR44riJpg4cy.eval)
- [SWE-bench full run](mistralai_Mistral-Large-4-1T-A52B/agentic-and-coding/swe-bench-verified/logs/base-swe-verified-full/2026-11-19T15-25-54-00-00_swe-bench_DvPu9b283uXLr6t7pmahiR.eval)
- [SWE-bench three-case retry](mistralai_Mistral-Large-4-1T-A52B/agentic-and-coding/swe-bench-verified/logs/base-swe-verified-retry/2026-11-20T15-45-22-00-00_swe-bench_EgR7Js8SfNQfmDZ85LCGD9.eval)

### MXFP4×FP8 model

- [GPQA Diamond full run](RedHatAI_Mistral-Large-4-1T-A52B-MXFP4xFP8/knowledge-and-reasoning/gpqa-diamond/logs/2026-11-16T17-27-16-00-00_gpqa-diamond_BuMmVVBwEDU7HH5Gut235z.eval)
- [GPQA Diamond 14-case retry](RedHatAI_Mistral-Large-4-1T-A52B-MXFP4xFP8/knowledge-and-reasoning/gpqa-diamond/logs/2026-11-16T19-56-15-00-00_gpqa-diamond_knJ2SXvccgiFk8q99ddTb7.eval)
- [MMLU 0-shot](RedHatAI_Mistral-Large-4-1T-A52B-MXFP4xFP8/knowledge-and-reasoning/mmlu/logs/2026-11-12T15-16-57-00-00_mmlu-0-shot_LEFUG24BBMBwV4MZd59urA.eval)
- [SWE-bench initial run, 400 tasks](RedHatAI_Mistral-Large-4-1T-A52B-MXFP4xFP8/agentic-and-coding/swe-bench-verified/logs/2026-11-16T21-53-47-00-00_swe-bench_HycHSmJmzL9S6VpHoYTWjC.eval)
- [SWE-bench continuation, 100 tasks](RedHatAI_Mistral-Large-4-1T-A52B-MXFP4xFP8/agentic-and-coding/swe-bench-verified/logs/2026-11-17T15-13-10-00-00_swe-bench_7VnoVm4fDR4NgQiLn9dd3N.eval)

The two MMLU-Pro `.eval` archives are split into 40 MiB chunks to fit GitHub's per-file limit. Run [`restore_mistral_mmlu_pro_logs.sh`](restore_mistral_mmlu_pro_logs.sh) from the repository root to reconstruct the byte-identical archives and verify their SHA-256 hashes.
