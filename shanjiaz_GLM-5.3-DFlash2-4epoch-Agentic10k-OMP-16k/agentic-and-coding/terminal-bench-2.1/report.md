# Speculative-decoding analysis — agentic fine-tune

Acceptance-only tables from the completed Terminal-Bench 2.1 run of `shanjiaz/GLM-5.3-DFlash2-4epoch-Agentic10k-OMP-16k` (step 8090), recorded on 2026-11-22. See [README.md](README.md) for measured settings and [results.json](results.json) for exact counters and provenance.

The separate smoke run is excluded. Every valid main-run model response is included regardless of its task outcome. Raw trajectories remain private. Thinking/response attribution is unverified and omitted.

Positions use the native analyzer's zero-based labels 0–7; the README and whole-run CSV label the same drafts 1–8.

## Coverage

- Logs: 1, samples: 89, tasks: 89
- Model calls: 4363, with spec metrics: 4363, without: 0
- Histogram/step-count consistency: 0 mismatch(es) over 4363 calls

## Headline

| metric | value |
|---|---|
| micro MAL (1 + accepted/steps) | 3.078 |
| pooled first-token acceptance rate | 0.689 |
| macro MAL (unweighted mean of per-call values) | 3.790 |
| median per-call MAL | 3.468 |
| mean conditional acceptance rate | 0.705 |

Micro MAL weights every verify step equally, so long responses dominate it. Macro MAL is the unweighted mean of the per-call values, so every request carries the same weight. The two differ when call length correlates with acceptance.

## Distribution of per-call MAL

| n | mean | median | p05 | p25 | p75 | p95 |
|---|---|---|---|---|---|---|
| 4363 | 3.790 | 3.468 | 2.546 | 2.973 | 4.288 | 6.200 |

## Per-position acceptance (overall)

`overall` = P(the draft token at this position is accepted) = P(verify step accepted more than j drafts); `conditional` = P(position j accepted | position j-1 accepted) = overall[j] / overall[j-1], with position 0 conditioned on nothing. The conditional column gives the per-position conditional acceptance probability; overall[j] is the running product of the conditionals. Exact whole-run counters, histogram and position rates are in [results.json](results.json) and [acceptance_by_position.csv](acceptance_by_position.csv).

| position | overall acceptance | conditional acceptance |
|---|---|---|
| 0 | 0.689 | 0.689 |
| 1 | 0.462 | 0.670 |
| 2 | 0.311 | 0.674 |
| 3 | 0.214 | 0.688 |
| 4 | 0.151 | 0.706 |
| 5 | 0.110 | 0.725 |
| 6 | 0.081 | 0.739 |
| 7 | 0.061 | 0.748 |
| **Σ overall + 1 = MAL** | 3.078 | |

## MAL by turn number

| turns | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| 1 | 89 | 172267 | 2.812 | 3.885 |
| 2 | 89 | 135589 | 2.849 | 3.860 |
| 3 | 89 | 76548 | 2.916 | 3.660 |
| 4 | 89 | 81283 | 2.967 | 3.750 |
| 5 | 88 | 95355 | 3.006 | 3.805 |
| 6-10 | 423 | 264211 | 3.085 | 3.869 |
| 11-20 | 680 | 492754 | 3.094 | 3.735 |
| 21-40 | 882 | 535970 | 3.123 | 3.787 |
| 41+ | 1934 | 893720 | 3.158 | 3.793 |

## MAL by context length (prompt tokens)

| tokens | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| <4k | 252 | 316797 | 2.851 | 3.885 |
| 4-16k | 418 | 263223 | 2.984 | 3.840 |
| 16-32k | 474 | 221720 | 3.003 | 3.848 |
| 32-64k | 793 | 440457 | 3.081 | 3.799 |
| 64-128k | 1111 | 720118 | 3.120 | 3.739 |
| 128k+ | 1315 | 785382 | 3.182 | 3.773 |

## MAL by output length

| tokens | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| <1k | 2723 | 271608 | 3.548 | 4.092 |
| 1-4k | 1177 | 743734 | 3.158 | 3.360 |
| 4-16k | 382 | 910089 | 3.061 | 3.149 |
| 16-64k | 75 | 678288 | 2.900 | 2.928 |
| 64k+ | 6 | 143978 | 2.731 | 2.751 |

## MAL by epoch

| epoch | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| 1 | 4363 | 2747697 | 3.078 | 3.790 |

## MAL by stop reason

| stop_reason | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| max_tokens | 6 | 143978 | 2.731 | 2.751 |
| stop | 5 | 1221 | 3.220 | 3.240 |
| tool_calls | 4352 | 2602498 | 3.097 | 3.792 |

## Outlier removal

Thresholds: call output tokens p95 = 7511, sample total output tokens p95 = 364684.

| variant | calls | steps | micro MAL | macro MAL |
|---|---|---|---|---|
| all calls | 4363 | 2747697 | 3.078 | 3.790 |
| drop calls with output_tokens > p95 | 4144 | 1446210 | 3.204 | 3.829 |
| drop whole samples with total output_tokens > p95 | 3304 | 1976313 | 3.095 | 3.809 |

## MAL by decile of recorded speculative verification steps

Each request's recorded speculative verification steps are divided into ten equal-index bins, then counters are pooled within each bin. These are step-index bins, not output-token offsets or thinking/response phases (MAL = 1 + accepted drafts / verify steps).

| decile | verify steps | MAL |
|---|---|---|
| 0 | 276748 | 3.033 |
| 1 | 274540 | 2.911 |
| 2 | 275014 | 2.899 |
| 3 | 274497 | 2.911 |
| 4 | 274151 | 2.938 |
| 5 | 275441 | 2.998 |
| 6 | 274966 | 3.012 |
| 7 | 274545 | 3.050 |
| 8 | 275009 | 3.269 |
| 9 | 272786 | 3.766 |

## Per-task MAL (20 lowest)

| task | calls | micro MAL | macro MAL |
|---|---|---|---|
| terminal-bench/install-windows-3.11 | 138 | 2.645 | 3.132 |
| terminal-bench/qemu-startup | 28 | 2.659 | 3.383 |
| terminal-bench/tune-mjcf | 25 | 2.703 | 3.338 |
| terminal-bench/sqlite-with-gcov | 27 | 2.717 | 3.112 |
| terminal-bench/configure-git-webserver | 17 | 2.730 | 3.485 |
| terminal-bench/cancel-async-tasks | 11 | 2.749 | 3.396 |
| terminal-bench/winning-avg-corewars | 111 | 2.764 | 3.344 |
| terminal-bench/qemu-alpine-ssh | 28 | 2.769 | 3.720 |
| terminal-bench/headless-terminal | 42 | 2.800 | 3.345 |
| terminal-bench/filter-js-from-html | 131 | 2.814 | 3.858 |
| terminal-bench/large-scale-text-editing | 21 | 2.819 | 3.321 |
| terminal-bench/mailman | 119 | 2.830 | 3.935 |
| terminal-bench/regex-chess | 58 | 2.844 | 4.316 |
| terminal-bench/schemelike-metacircular-eval | 109 | 2.849 | 3.448 |
| terminal-bench/build-pov-ray | 67 | 2.862 | 3.748 |
| terminal-bench/compile-compcert | 85 | 2.883 | 3.614 |
| terminal-bench/reshard-c4-data | 45 | 2.892 | 3.866 |
| terminal-bench/train-fasttext | 90 | 2.905 | 3.554 |
| terminal-bench/query-optimize | 34 | 2.911 | 3.208 |
| terminal-bench/custom-memory-heap-crash | 22 | 2.915 | 3.688 |

Full 89-task table: [mal_by_task.csv](mal_by_task.csv). Whole-run position rates: [acceptance_by_position.csv](acceptance_by_position.csv).

## Historical preview comparison

Both runs used the same 89-task Terminal-Bench 2.1 workload. The published preview used revision `3325df9c`; our exact pre-finetune parent is `8a96994d` and has no matched run here. Hardware/runtime and generated trajectories also differed. The observed increase therefore does not isolate the effect of fine-tuning or establish speedup. Preview position rates are rounded published values, so deltas are approximate.

| metric | Published preview | Agentic fine-tune | Relative change |
|---|---:|---:|---:|
| Pooled acceptance length | 2.938 | 3.07820 | +4.77% |

| native draft position | Preview overall | Fine-tuned overall | Change (percentage points) | Relative change |
|---|---:|---:|---:|---:|
| 0 | 65.90% | 68.90% | +3.00 | +4.6% |
| 1 | 43.20% | 46.17% | +2.97 | +6.9% |
| 2 | 28.70% | 31.11% | +2.41 | +8.4% |
| 3 | 19.50% | 21.40% | +1.90 | +9.7% |
| 4 | 13.80% | 15.12% | +1.32 | +9.6% |
| 5 | 9.90% | 10.96% | +1.06 | +10.7% |
| 6 | 7.30% | 8.10% | +0.80 | +10.9% |
| 7 | 5.50% | 6.06% | +0.56 | +10.2% |

Preview source: [published reference README](https://github.com/neuralmagic/evals-refresh/blob/ce503c3fc45da55dd3ac32a9f5257acff8128f32/RedHatAI_GLM-5.3-speculator.dflash2-preview/agentic-and-coding/terminal-bench-2.1/README.md).

The source analyzer JSON has SHA256 `e6d8da42f3b3a812f3ece19f0f847e6486661727456d956e16950a7cede9a77c`. This public copy omits task-score groupings and unverified phase estimates, corrects the step-decile description, and adds the historical comparison.
