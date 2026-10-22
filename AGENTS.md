# evals-refresh: guide for agents

This repo holds copy-pasteable, reproducible evaluations of open-weight models served with
**vLLM** and evaluated with **Inspect** (`inspect-ai`, plus `inspect_evals` and `inspect_harbor`
task packages). Read this file before running or adding anything. Everything below is a rule
unless it says "hint".

## 0. Local environment notes

`local_env_notes.md`, next to this file, holds environment requirements and pitfalls that apply to any host
(serving, caches, Docker setup, image pulls, venvs). Read it before running anything; it is imported below so
that Claude Code loads it with this file. It is committed and used on other servers, so keep it general. Facts
about one machine (paths, user names, installed versions, other tenants) go in `local_env_notes.local.md`,
which git ignores; read it too if it exists.

@local_env_notes.md

## 1. Ground truth, in priority order

1. **Serving flags come from the model's official vLLM recipe** at `https://recipes.vllm.ai/<Org>/<model>`
   (path is case-sensitive; the source is `github.com/vllm-project/recipes`). Record the URL in the
   task README. Do not invent flags; do not copy flags from another model.
2. **Sampling params come from the model's `generation_config.json`** on the HF hub (temperature,
   top_p, top_k). Never run greedy: every model here is a reasoning model whose vendor warns
   against `temperature=0`.
3. **Thinking is on, at the highest effort the model supports**, set on both sides for safety:
   server-side via `--default-chat-template-kwargs` in `serve.sh`, and per request in
   `run_eval.sh` (`--reasoning-effort xhigh` for Qwen; `extra_body.chat_template_kwargs` via
   `assets/generate_config.json` for Gemma, which has no effort levels). Adapt as needed for
   each model family.
4. **Task definitions come from `inspect_evals` or `inspect_harbor` unchanged.** No task wrappers
   in this repo. If a task is broken, fix it upstream (PR from a fork under github.com/eldarkurtic) and
   consume the fix from the fork branch (pip install from git, or a Harbor registry pin to the fork
   commit); document it under the README's "Patches for upstream" section. No local patch scripts.
5. **The model card's protocol decides comparability.** Before adding a task, read what the card
   reports (subset, single-shot vs agentic, judge, epochs) and say in the README whether our number
   is comparable. `eval_coverage_matrix.md` at the repo root maps benchmarks to packages,
   categories, and execution tiers (`none` / `sandbox` / `agent`).

## 2. Layout

```
<org>_<model>/<category>/<task>/
  serve.sh                 vLLM server: model, TP/DP, context, parsers, thinking default. Nothing else apart from vLLM server specific arguments.
  run_eval.sh              inspect eval: task, epochs, sampling, reasoning, limits, concurrency. Nothing else apart from vLLM server specific arguments.
  local_orchestrator.sh    the ONLY env-specific file: venvs, GPUs, secrets, start server, wait, eval, teardown.
  README.md                task table, Files, Run, Results (config + scores + token stats), Patches.
  server_requirements.txt  `pip freeze` of the vLLM venv that produced the results, host info in the header.
  client_requirements.txt  `pip freeze` of the Inspect venv that produced the results.
  assets/                  only what the scripts reference: chat templates, generate_config.json, registry pins.
  logs/                    gitignored. Keep only the final run's .eval, serve.log, full.log.
```

- `<org>_<model>` is the HF id with `/` replaced by `_` (`Qwen_Qwen3.8-27B`, `google_gemma-4-31B-it`).
- `<category>` is the `Evaluates` column of `eval_coverage_matrix.md`: `knowledge-and-reasoning`,
  `agentic-and-coding`, `general-tool-usage`, `long-context`, `multimodal`.
- Every task directory is standalone. No shared includes, nothing to source. Duplication across
  models is deliberate; drift between copies is expected and is the point (each copy documents
  what ran).
- `serve.sh` and `run_eval.sh` are plain, readable bash with env-var overrides
  (`MODEL`, `PORT`, `TP`, `DP`, `EPOCHS`, `LOG_DIR`, `MAX_TOKENS`, `MAX_CONNECTIONS`, ...). No
  defensive scaffolding, no logging frameworks, no argument parsers.


## 3. Rules of engagement

- **Never `git commit` or `git push`.** Leave changes in the working tree and say what changed.
  Committing is the repo owner's job.
- **Pull before you start, and read what came in.** Several hosts push to this repo. Fixes and conventions found on
  one host (e.g. the leak fixes of section 11) reach you only through a pull, so before copying a task dir, check
  the newest copies of that task under every model. If a pull brings a task dir that you also have locally, the two
  are probably different runs: compare them, ask the user which one is final, and move the other out of the repo
  with its logs (a README must match the logs next to it).
- **`git add` a new task dir's files as soon as you create them (stage only, never commit), and re-check/re-stage
  after every wait on a long-running eval.** On at least one host, this repo's working tree has been observed to
  lose new task-dir files entirely, including ones already `git add`-staged: not just `git clean -fd` (which
  would spare staged files) but at least once also reverting the index itself (`git status` showed staged `A`
  entries become `AD`, i.e. added-in-index but deleted-from-worktree, then disappear from the index too), and it
  has hit a directory *mid-run* (a `vllm serve` process survives with its cwd shown as `(deleted)` in `ps`/`/proc`,
  confirming the directory itself was unlinked while open, not just emptied) as well as an unrelated, already
  finished task dir's files at the same time. Staging is a cheap, harmless precaution (it does not commit or
  push) but is not a reliable fix by itself; the only durable record is what you report inline in chat (full
  results, not just a log filename) as you go, in case files need to be recreated afterward. If this happens
  mid-eval, check for orphaned GPU-holding processes from the lost directory (`ps aux`, `chg status`) and kill
  them before relaunching, recreate the directory from what you already wrote, re-stage, and keep going; do not
  spend an open-ended amount of time root-causing the sync mechanism itself unless the user asks.
- **Reflect after every eval and every meaningful piece of work, and write the general lessons into the notes.**
  This is mandatory; section 12 gives the procedure.
- **Keep every agent instruction in this file.** `CLAUDE.md` only imports it (`@AGENTS.md`), so Claude Code and
  other agent harnesses read the same rules. Do not add content to `CLAUDE.md`, including what `/init` proposes;
  put conventions here, environment notes that apply to any host in `local_env_notes.md`, and facts about one
  machine in `local_env_notes.local.md`.
- **Never refer to a local venv as if it exists.** Venvs are local to one user and server, and other users won't
  have yours. In this file, `local_env_notes.md` and READMEs, describe an environment by its packages (the dir's
  requirements files or pins) and give the commands to create it. Real paths live only in `local_orchestrator.sh`
  and `local_env_notes.local.md`. A README's Setup commands may create the environments at the paths the
  orchestrator activates, as long as the README says to change both together.
- **Never put secrets in the repo.** `HF_TOKEN`, API keys and other secrets should be local on
  the user's machine. 
- **Ask before deciding anything that changes what is measured**: protocol, subset, judge model,
  time limits, epochs. Do not silently narrow or widen a task. Infrastructure choices (TP/DP,
  concurrency, disk) are yours to make and to document.
- **Always smoke-test first** (`EPOCHS=1 ./local_orchestrator.sh --limit 5`, or `--limit 2` for
  agentic tasks), read the samples, and only then launch the full run. Verify in the log that
  reasoning was parsed into a separate `reasoning` content part, that `stop_reason` is `stop`
  (not `max_tokens`), and that the config you intended is what `eval.model_generate_config` recorded.
- **Audit every run of a task with tools for cheating before you report it** (exec tier `sandbox` or `agent`).
  Some models fetch a task's solution from the internet or from git history instead of solving it. Before the run,
  close every leak the task allows; after the run, scan the trajectories. Section 11 lists the fixes and the audit.
- **One epoch is the default** (`--epochs 1`, pass@1) for every benchmark, new task and new model. Run more
  epochs (`EPOCHS=N`, `--epochs-reducer mean`, avg@N) only when the user asks for them, and say so in the README.
  When you copy a task dir whose `run_eval.sh` defaults to more epochs, set its `EPOCHS` default back to 1. The
  defaults in existing dirs record what produced their results (section 10).
- **Results go in the README as data, not narrative.** Fill the Results template (below). Do not
  describe failed attempts, ablations, or how you got there in the README. README only contains
  final results, everything else should be discussed with the user in chat.
- **Headline scores over all samples.** Sample errors and unscored samples count as failures (0; in avg@N, 0 for
  that epoch), so every model is scored with the same denominator, e.g. "0.336 (38 of 113)". List the errors
  separately and compute stderr the same way. Never headline a scored-only rate: errored samples differ between
  models, and they are often the longest, unfinished trajectories. Some older READMEs headline errors-excluded
  numbers; recompute their all-samples figure before comparing with them.
- **One task directory, one server.** Do not add multi-model orchestration, judges on split GPUs,
  or background daemons. If a task needs a judge, run judging as a separate phase
  (`inspect eval --no-score`, then `inspect score --model-role grader=...`) and document it.

## 4. Python environments (adapt in `local_orchestrator.sh`)

Three environments, deliberately separate. They are local to each user and server, so create your own, name and place
them as you like, and point `local_orchestrator.sh` at them; it is the only file that knows their paths.

**Use `uv` by default** to create and install into every environment (server, `inspect_evals` client,
`inspect_harbor` client). If no particular Python version is required:

```bash
uv venv .venv
source .venv/bin/activate
uv pip install --python .venv <package-spec-or--r-requirements-file>
```

If a Python version is required (e.g. a vLLM recipe or a task pins one), name the venv after it so
multiple versions can coexist:

```bash
uv venv --python 3.11 .venv-py311
source .venv-py311/bin/activate
uv pip install --python .venv-py311 <package-spec-or--r-requirements-file>
```

If `uv` is not available on the host, fall back to the standard library, same venv names:

```bash
python3 -m venv .venv                  # or: python3.11 -m venv .venv-py311
source .venv/bin/activate              # or: source .venv-py311/bin/activate
pip install <package-spec-or--r-requirements-file>
```

| environment | used by | create with |
|---|---|---|
| vLLM server | `serve.sh` | `uv pip install vllm` |
| Inspect client for `inspect_evals` tasks | `run_eval.sh` | `uv pip install inspect-evals openai` |
| Inspect client for `inspect_harbor` tasks | `run_eval.sh` | `uv pip install inspect-harbor httpx2 "openai==3.14.0"` |

These installs are the starting point for a new task. To reproduce a dir's results, create the environments from its
`server_requirements.txt` and `client_requirements.txt` instead (same `uv venv` / `uv pip install` pattern, substituting
`-r server_requirements.txt` / `-r client_requirements.txt` for the package spec), as its README Setup shows.

`inspect-harbor` depends on `litellm`, which pins `openai<3`, while Inspect's OpenAI-compatible
providers need `openai>=3`; installing `openai==3.14.0` last overrides the pin and the resulting
pip warning is harmless (Inspect's agent path never imports litellm). `httpx2` is imported by
recent `inspect-ai` but not declared.

## 5. How to run an existing task

```bash
cd <org>_<model>/<category>/<task>
EPOCHS=1 ./local_orchestrator.sh --limit 5     # smoke test; inspect the samples first
./local_orchestrator.sh                        # full run (EPOCHS=N for more epochs, if the user asks)
inspect view --log-dir ./logs                  # browse samples (port 7575)
```

Monitor a running eval from another shell with `inspect ctl task list` (from the same venv).
During Docker image builds it reports no running eval; watch the eval's stdout instead.

Read results programmatically (this is how README numbers are produced):

```python
from inspect_ai.log import read_eval_log
log = read_eval_log("logs/<file>.eval")
log.eval.model_generate_config      # the config line for the README
log.results.scores                  # accuracy, stderr
log.stats.model_usage               # run totals: input / output / reasoning tokens
for s in log.samples:
    s.output.usage                  # per-sample tokens (reasoning counted separately)
    s.output.stop_reason            # "stop" or "max_tokens"
    s.scores, s.error, s.limit      # verdict, infra error, time/message limit hit
```

If a run is interrupted, `inspect eval-retry logs/<file>.eval` reruns only unfinished samples and
keeps completed ones. It reuses the log's task and args; env vars still apply.

To add epochs to a finished run (when the user asks for avg@N), keep the existing log as epoch 1, run
`EPOCHS=<N-1>` into its own log dir with the same concurrency (in agentic tasks the number of samples in flight
changes the time-limit hits), and combine with a per-task mean over all N epochs. Every log numbers its epochs
from 1: map them to overall epochs before you report per-epoch numbers or point to a sample.

## 6. README template (fill exactly this, nothing more)

```
# <org>/<model> — <Task name>

| | |
|---|---|
| Task | `<package>/<task>` (<size, subset>) |
| Category | <category> (subclass: <from the matrix>) |
| Exec tier | `none` / `sandbox` / `agent` — <what infra it needs> |
| vLLM recipe | <url> |

<one-paragraph protocol note if the number is not comparable to the model card>

## Files            (one line per file, what lives in it; local_orchestrator.sh is "the only file you should modify")
## Run              (### Setup: how to create both venvs from the *_requirements.txt files or the pinned
                     packages, HF_TOKEN / gated datasets, Docker expectations; ### Run the eval: the three
                     commands above. A newcomer must be able to reproduce the results from the README alone.)
## Results
With model generation config:
`<eval.model_generate_config, plus epochs, limits, client_timeout>`
the following scores and token stats are obtained:
| metric | value |                       accuracy (pass@1, or avg@N if asked for), stderr, per-epoch, samples,
                                          truncated / time-limit hits, unparsed / no-solution, sample errors
| tokens / sample | input | output | reasoning |   mean / median / max
<one line on how to read the token numbers if non-obvious; list of always-failing tasks for agentic evals>
## Patches for upstream   (every upstream defect this task needed fixed: the PR/issue link, and how this dir
                            consumes the fix from the fork - a pip install from the fork branch or a Harbor registry
                            pin to the fork commit in assets/ - never a local patch script; "None." otherwise)
```

No log filenames in the README (logs are gitignored). No environment details in the README
(they live in the two requirements files). Regenerate the requirements files after the final
run with `pip freeze` from each venv, with a header comment giving date, GPUs, driver, CUDA,
Python.

## 7. Adding a new model

1. Create `<org>_<model>/<category>/<task>/` by copying the closest existing task dir. For a task listed in
   section 11, copy the dir named there, which carries the leak fixes.
2. `serve.sh`: rewrite from the model's vLLM recipe. Keep only what the recipe says plus
   `--tensor-parallel-size`, `--data-parallel-size`, `--served-model-name`, `--host/--port`. Before
   `local_orchestrator.sh` launches it, check how many GPUs are actually free and confirm every parallelism degree
   the command sets (tensor × data × pipeline × expert) does not exceed that count, and launch through `chg` if it
   is installed (`local_env_notes.md`, "Serving", has the exact commands). Confirm the reasoning parser and tool
   parser names exist in the installed vLLM
   (`vllm/reasoning/__init__.py`, `vllm/tool_parsers/__init__.py`) and that the architecture in
   the model's `config.json` is in `vllm/model_executor/models/registry.py`. If the recipe uses a
   custom chat template, copy it into `assets/` byte-identical and point `--chat-template` at it.
   For text-only tasks on multimodal models pass `--limit-mm-per-prompt '{"image": 0, "audio": 0}'`.
3. `run_eval.sh`: sampling from `generation_config.json`; thinking on per request; keep
   `-M client_timeout=7200` (Inspect's default HTTP timeout is 600 s and silently retries long
   generations from scratch); `--max-tokens` strictly below `--max-model-len`.
4. Check how the model's card reports the benchmark and note comparability in the README.
5. Smoke test, read samples, full run, fill Results, regenerate requirements files.

## 8. Adding a new task

1. Find it in `eval_coverage_matrix.md`. `inspect_evals` tasks run in the `inspect_evals` client environment;
   `inspect_harbor` tasks (`Where` = `inspect_harbor`) need the `inspect_harbor` one (section 4) and Docker.
   `PARTIAL` / `MISSING` rows are not the benchmark the cards report; say so if asked.
2. Read the task's README in the package and its task signature (`inspect list tasks`, or import
   it). Identify: dataset and pinned revision, gating (HF token / terms), subset flags,
   sandbox, judge model, default metrics, and whether the protocol matches the model cards.
3. Decide with the user anything from rule 3 (subset, judge, epochs, limits). Also discuss with 
   user the potential need to extend models context length (e.g. with YaRN) if needed for the task
   and if the model supports it.
4. Category directory = the matrix's `Evaluates` column. Task directory name = the benchmark's
   common name in lowercase with hyphens (`gpqa-diamond`, `livecodebench`).
5. Sandboxed / agentic tasks: check disk (per-task images), set `--max-sandboxes` equal to
   `--max-connections` (Inspect holds a container per in-flight sample), set `--time-limit` as a
   runaway guard and report hits, and use `--fail-on-error 0.1` so one infra error cannot abort
   a multi-hour run while a systematic one still does. Per-turn `--max-tokens` must leave room
   for multi-turn history inside the context window (65536 was used with a 262k window). Find out how
   the task could leak its solution (network policy in each `task.toml`, git history in the images, public
   copies of the task files), close what you can, and add the task to section 11.
6. Judged tasks: no external APIs are assumed. Plan a local judge as a separate scoring phase and
   keep it identical across models.

## 9. Gotchas already paid for

- **`inspect ctl` "http_retries" climbing with no errors** = client-side timeouts re-running
  long generations forever. Fix: `-M client_timeout=<seconds>` (or `INSPECT_HTTP_REQUEST_TIMEOUT`).
  `--timeout` is a different, outer budget and does not fix it.
- **`extra_body` (e.g. `chat_template_kwargs`) has no CLI flag.** `-M` args go to the provider
  constructor, not the request. Use `--generate-config assets/generate_config.json`; it merges
  with the individual sampling flags.
- **`--max-tokens >= --max-model-len`** makes vLLM reject every request while Inspect reports
  success with accuracy 0.000 in seconds.
- **Harbor tasks build one image per task, serially, before any sample starts**, and Inspect's
  control server is invisible during that phase. A Dockerfile that copies per-task files before
  `apt-get` defeats layer sharing (LiveCodeBench: ~750 MB and ~1 min per image ×100). Pre-build in
  parallel if needed; check disk first.
- **A Harbor verifier that exits without writing `reward.txt`** turns a failed task into a sample
  *error*, excluded from accuracy, and aborts the eval under default fail-on-error. Fixed upstream
  for LiveCodeBench; pin via `assets/harbor_registry.json` + `inspect_harbor/harbor -T registry_path=...`.
- **Models sometimes emit pseudo tool calls as plain text** (Gemma: `<div class="tool_call">`);
  the ReAct loop then re-prompts until the time limit. Count these in the README as "no solution".
- **GitHub's API is rate-limited without a login**; use `git ls-remote` / shallow clones instead,
  or log in with `gh auth login`.
- **vLLM prints an `EngineDeadError` traceback at shutdown** when the orchestrator kills it.
  It is noise if it appears at the moment the eval finished.
- **Inspect's multiple-choice parser** requires `ANSWER: <LETTER>` on the last line; a model that
  writes `ANSWER: $A` can never be parsed. Check the unparsed count.
- **vLLM's YaRN `--hf-overrides` needs the top-level `max_position_embeddings` bumped too**, not
  just `rope_scaling`. `derived_max_model_len` (`vllm/config/model.py`) rejects `--max-model-len`
  above the config's `max_position_embeddings` *before* applying any scaling, and its comment
  says so explicitly for `rope_type="yarn"` ("YaRN variants leave max_position_embeddings already
  scaled") — unlike other rope types, it does not auto-multiply by `factor` for you. The actual
  rotary-embedding math only reads `rope_scaling.original_max_position_embeddings`/`factor`, so
  this bump is purely to satisfy the validator: set both, e.g. for Qwen3-8B's card-validated
  config, `--hf-overrides '{"max_position_embeddings": 131072, "rope_scaling": {"rope_type":
  "yarn", "factor": 4.0, "original_max_position_embeddings": 32768}}' --max-model-len 131072`.
  There is no standalone `--rope-scaling` CLI flag in vLLM 0.31.0 despite some model cards' `vllm
  serve` examples implying one; `--hf-overrides` is the equivalent (forwards a dict into the HF
  config, same as hand-editing `config.json`).
- **`inspect score <log>` can't load a task-embedded custom scorer**: it is only registered as an
  import side effect of its task module (e.g. `inspect_evals.niah.niah`), which `inspect eval`
  triggers by loading the task spec but a bare `inspect score` CLI process never does ("couldn't
  be loaded... provide a path to the file"). This also blocks passing non-string scorer args
  (e.g. a scorer-building callable) back through `-S`. Workaround: a short script using
  `inspect_ai`'s own public API — `from inspect_ai import score; from inspect_ai.log import
  read_eval_log, write_eval_log`; import the scorer factory directly from the task's module,
  reconstruct it exactly as the task does, call `score(log, [scorer], model_roles={"grader":
  get_model(...)}, action="overwrite")`, then `write_eval_log`. This is not a "local patch
  script" under rule 4 (it doesn't change the task's dataset, scorer logic or rubric) — it
  replaces a CLI entry point with the same package's public function. Useful for any two-phase
  `--no-score` / score workflow (e.g. self-grading) on a task with a custom scorer.
- **A self-grading judge can score an empty/truncated completion as near-perfect** instead of
  penalizing it. Seen on niah: 3 samples hit `stop_reason=max_tokens` with zero completion text
  (all budget spent on reasoning), and the self-grading judge (`model_graded_qa`) scored them
  5, 10 and 10 on a rubric whose floor is "no answer". Don't infer judged-task quality from the
  truncation count alone — audit the judge's score on every truncated *and* every empty-completion
  sample specifically (`not (s.output.completion or "").strip()`), and correct/floor scores the
  judge mishandled before reporting a headline number (`AGENTS.md` rule 3: unscored/failed
  samples count as failures). Report both the raw and corrected numbers, and the sample ids, so
  the discrepancy is auditable. The rubric's own floor can itself be a nonzero value on a
  non-0/1 scale (niah's `custom_model_graded_qa_with_history_scorer` floors at "1", i.e.
  "completely unrelated to the reference", not 0) — a judge that correctly assigns that floor to
  an empty/truncated completion is not mis-grading, but the corrected headline number should still
  floor it further to true 0, since a no-answer sample must contribute zero credit under rule 3.
- **`model_graded_qa`'s parsed grade (`Score.value`) is a numeric string** ("10", "1", "7" for a
  `grade_pattern=r"(\d+)"` rubric), not an `int`/`float`, except for a grader-parse failure
  (`Score.unscored()`, value `NaN` as a `float`). A sample-auditing script that checks
  `isinstance(value, (int, float))` silently misclassifies every real score as unscored (giving a
  headline accuracy of 0.0 that looks like a real result, not an error) — cast through `float()`
  in a `try`/`except (TypeError, ValueError)` instead, and catch the `NaN` case after casting.
  Sanity-check any such script's headline number against a handful of samples' raw
  completions/targets before trusting it.
- **A task's own "accuracy" metric can be an unnormalized mean of a non-0/1 rubric.** niah's
  `subset_accuracy_combinations()` metric sums the rubric's raw values (1/3/5/7/10) and divides by
  sample count — "overall_accuracy" is actually a mean score out of 10, not a 0-1 fraction. Divide
  by the rubric's max before reporting it next to other tasks' pass@1 numbers, and say so.
- **Inspect's `vllm` provider only reads `VLLM_BASE_URL`/`VLLM_API_KEY` env vars inside the process
  that calls `generate()` for the first time.** A two-phase script (e.g. a separate
  `score_niah.py` run after `run_eval.sh` by the orchestrator) is a different process; the env
  vars `run_eval.sh` exported for its own `inspect eval` subprocess do not reach it, so
  `get_model("vllm/...")` falls through to starting a *new local* vLLM server and fails with
  "vLLM Server requires optional dependencies" if the real `vllm` package isn't installed in that
  venv (by design, the Inspect client venv doesn't have it — AGENTS.md section 4). Pass
  `base_url=`/`api_key=` to `get_model()` explicitly instead of relying on inherited env.
- **An older vLLM version can silently drop reasoning-token accounting from the usage response**
  while still producing and parsing reasoning content correctly. On vLLM 0.24.0 (vs. 0.31.0 on the
  same host), every sample's `output.usage.reasoning_tokens` came back `None` even though every
  sample still had a separate `ContentReasoning` message part with real reasoning text — the
  content pipeline and the usage-accounting field are evidently populated by different code paths
  that didn't both exist yet in 0.24.0. Don't read a missing/`None` reasoning-token count as "no
  thinking happened"; check the content parts (as the smoke-test checklist already requires)
  before concluding reasoning is off, and note the reporting gap in the README's token table
  instead of reporting a false 0.
- **Check the actual port you intend to serve on, not just the free-GPU count, on a shared host.**
  `serve.sh`'s default port can already be bound by a a different, unrelated job (another user's
  interactive `vllm serve`, or your own leftover from an earlier session) even when `nvidia-smi`
  shows enough GPUs free. vLLM then fails to bind ("Address already in use") inside the
  orchestrator's background job, but a health check against the *wrong*, already-running server on
  that port can still pass, and `inspect eval` then gets a confusing 404 ("model does not exist")
  instead of a connection error. Check with `ss -ltnp | grep <port>` (or `lsof -i :<port>`) before
  a run, and change the port if it's taken, rather than just re-trying.
- **An `export`ed `PORT` (or similar) from debugging one task dir silently overrides a later,
  unrelated task dir's `${PORT:-default}` fallback in the same shell session.** `serve.sh` /
  `run_eval.sh` / `local_orchestrator.sh` read `PORT` with a default (`PORT="${PORT:-8002}"`), so
  it only falls back to the dir's documented port when the variable is unset — not when it is set
  to something else. An earlier `export PORT=8001` left over from testing a different dir (e.g. a
  one-off `python score_niah.py` invocation) made a brand-new dir's smoke test launch on port 8001
  instead of its intended 8002, invisibly, with no error (both the server and the eval client
  inherited the same stale value, so the run was internally consistent and "worked"). It only
  surfaced by noticing the startup log's `non-default args` line didn't match the port the script
  was supposed to use. `unset PORT` (or any such override) before launching a different task dir
  in a long-lived shell, and check the startup log's actual bound port against what the dir's
  README/scripts say, not just that *a* server became healthy.
- **A hybrid linear-attention / gated-delta-network (SSM-style) model needs far less KV cache per
  token than a dense transformer at the same context length**, because most layers keep a
  constant-size recurrent state instead of a per-token cache entry (check `config.json`'s
  `layer_types`: a model with `full_attention` only every Nth layer, the rest `linear_attention`,
  only pays full KV-cache cost for the full-attention layers). Qwen3.5-9B at `--max-model-len
  262144` reported 1.68M KV-cache tokens on a single H100 (vLLM's own "Maximum concurrency for
  262,144 tokens per request: 6.42x" log line) — roughly 13x more concurrent full-length requests
  per GPU than a same-size dense model would fit at a comparable context length. Don't assume a
  `--max-connections` value tuned for a dense model's KV budget is a ceiling for a hybrid one;
  check the server log's "GPU KV cache size" / "Maximum concurrency" lines after the smoke test
  and size connections from the real number, not from a different model's precedent.
- **Some model families have no thinking mode at all, not even an "off" switch.** Rule 3's
  "thinking is on, at the highest effort" default assumes a model that supports both modes.
  Qwen3-Coder-Next's card states it plainly: "This model supports only non-thinking mode and does
  not generate `<think>` blocks in its output. Meanwhile, specifying `enable_thinking=False` is no
  longer required." For such a model, there is no `--reasoning-parser` to set on the server, no
  `enable_thinking`/`chat_template_kwargs` to pass anywhere (generation or grading), and no
  separate reasoning content part to check for in the smoke-test audit (confirm its absence
  instead, on every sample, as evidence the model genuinely has no thinking mode rather than
  evidence something is misconfigured). Check the model card before assuming every model needs a
  reasoning parser and a thinking-enabled chat template kwarg.

## 10. Conventions established in the task directories

Sections 1-9 set the defaults. The existing task dirs depart from some of them on purpose, and each README
says why. When you touch a task, follow the same task under the other model instead of the defaults, and do not
revert these departures:

- **No build, lint or unit tests.** The only test is the smoke run from inside a task dir
  (`EPOCHS=1 ./local_orchestrator.sh --limit 5`; use `--limit 2` for agentic tasks). It needs the GPUs, and Docker
  for sandboxed tasks.
- **Epoch defaults of existing dirs vary** (`EPOCHS` in `run_eval.sh`). They record what produced each README's
  results and predate the one-epoch default of section 3; new runs use 1 epoch unless the user asks for more:
  - 3: gpqa-diamond, livecodebench, terminal-bench-2.1, bfcl.
  - 8: aime-2026 (only 30 problems).
  - 1: mmlu-pro (12k samples), swe-bench-verified, swe-bench-pro, deepswe-1.1, gdpval-aa, tau2-bench, tau3-bench.
  - 1 for every task of the four Qwen3.8-Flash-Next dirs (RedHatAI, Inferact and nvidia NVFP4, Qwen BF16), at the
    user's request.
- **Sampling flags.** Inspect's `vllm` provider drops `--top-k` from the request. The value that applies is the
  server default vLLM takes from the checkpoint's `generation_config.json` (logged at vLLM startup).
- **Qwen3.8-Flash-Next dirs** (8x B200 host):
  - Serving: vLLM nightly, TP=1 × DP=4 set in `serve.sh`; the agentic dirs override it to TP=4 × DP=1 in
    `local_orchestrator.sh`. The RedHatAI dirs use GPUs 0-3 on port 8000, the Inferact dirs GPUs 4-7 on port 8001,
    the nvidia dirs GPUs 0-3 on port 8002, and the Qwen BF16 dirs GPUs 4-7 on port 8003.
  - Qwen BF16: `serve.sh` sets TP=4 × DP=1 (the recipe needs at least 423 GB of VRAM per replica). That replica has
    room for 9.5M KV-cache tokens against 20.4M for an NVFP4 TP=4 replica, and with about 100 agent sessions it
    re-prefilled every history each turn. So its swe-bench-pro and deepswe-1.1 dirs run one TP=8 replica on all 8
    GPUs (17.1M tokens), and terminal-bench-2.1 runs 45 concurrent samples instead of 89. The superseded runs are
    kept in `logs/superseded_kv_thrash/`.
  - Model loading: vLLM keeps the 51B n-gram table in pinned host memory. Start the two servers one after the
    other, and keep `VLLM_ENGINE_READY_TIMEOUT_S` raised.
  - RedHatAI's server venv carries a vLLM fix from the `eldarkurtic/vllm` fork (see its README).
- **Serving topology for multi-turn tasks.** swe-bench-*, deepswe-1.1, bfcl, gdpval-aa, tau2-bench and tau3-bench
  export `TP=8 DP=1` in `local_orchestrator.sh` instead of TP=2 × DP=4. vLLM's prefix cache is per replica, and
  DP routes each turn to a random replica, so agent histories would be prefilled again on every turn. `serve.sh`
  keeps the recipe defaults; the override lives only in the orchestrator.
- **User simulator (tau2/tau3-bench).** Qwen/Qwen3.8-27B plays the customer for every model. The Qwen dirs reuse
  the eval server. The Gemma dirs start a second server from `assets/serve_user_model.sh` on GPUs 4-7 and run
  the model under test at TP=4 on GPUs 0-3. This is the one accepted exception to "one task directory, one
  server".
- **Docker for agent tasks.** `local_orchestrator.sh` exports `DOCKER_HOST` pointing at the rootless socket
  (`/run/user/$UID/docker.sock`); the image store location is host-specific (see `local_env_notes.md`). Harbor tasks pass
  `-T override_cpus=0`, because rootless Docker rejects CPU caps. In tau3-bench, containers reach the host's
  vLLM through `CONTAINER_HOST_IP`, not localhost.
- **Per-model assets.** Every Gemma dir carries two assets:
  - `assets/tool_chat_template_gemma4.jinja`, the recipe's template, used by `serve.sh`.
  - `assets/generate_config.json`, which turns thinking on per request.

  Qwen dirs need neither, because `--reasoning-effort xhigh` does the job. The Gemma recipe URL is
  `https://recipes.vllm.ai/Google/gemma-4-31B-it`: capital `G`, although the HF org is `google`.
- **Each dir pins its own client packages.**
  - inspect_harbor: 0.7.5, 0.7.6, 1.0.0, or a git commit (tau3-bench; the Flash-Next swe-bench-pro and
    deepswe-1.1 dirs).
  - bfcl and the older swe-bench-verified dirs install inspect_evals from `eldarkurtic/inspect_evals` fork branches.

  Before a run, create the client environment from the dir's `client_requirements.txt` and README Setup, or check
  that an environment you already have matches it.
- **Harbor fork pins.** livecodebench, swe-bench-pro and deepswe-1.1 load their tasks through
  `assets/harbor_registry.json`, which has one entry per task, each pinned to a commit of
  `github.com/eldarkurtic/harbor-datasets`. `run_eval.sh` points `inspect_harbor/harbor -T registry_path=...` at
  that file.
- **SWE-style tasks can leak the solution to the agent.** Only the Qwen3.8-Flash-Next dirs carry the fixes;
  the other dirs of deepswe-1.1, swe-bench-pro and swe-bench-verified ran without them. See section 11.
- **Every task exists once per model.** Do not mirror an edit into the other model's copy unless asked.
- **Coverage matrix.** When you add a task, set ✅ in the `Repo` column of `eval_coverage_matrix.md` in both
  places: the Benchmarks table and the per-subclass detail table.

## 11. Solution leaks: fixes to use and the audit after every run

An agent with tools can take a task's solution instead of solving it: fetch it from the internet, or read it from
the project's future git history inside the image. Models differ in how hard they try, so close every leak a task
allows before the run, and audit the trajectories after it.

**Fixes.** Copy deepswe-1.1, swe-bench-pro and swe-bench-verified from the Qwen3.8-Flash-Next dirs
(`Qwen_Qwen3.8-Flash-Next`, `RedHatAI_Qwen3.8-Flash-Next-NVFP4`, `Inferact_Qwen3.8-Flash-Next-NVFP4`,
`nvidia_Qwen3.8-Flash-Next-NVFP4`). The `Qwen_Qwen3.8-27B`, `google_gemma-4-31B-it`, `RedHatAI_Qwen3.8-27B-MXFP4`
and `amd_Qwen3.8-27B-Quark-AWQ-MXFP4` copies of these tasks ran before the fixes; don't reuse their client setup.

- **deepswe-1.1.** Every `task.toml` sets `network_mode = "no-network"` for `[agent]` and `[verifier]`, but stock
  inspect_harbor (1.0.0 and earlier) applies only `[environment].network_mode`, so agents silently get internet.
  - Fix: install inspect_harbor from the fork `eldarkurtic/inspect_harbor@cb61925` (branch
    `fix/enforce-agent-network-mode`), which applies the network mode per phase. Create the client environment
    from a Flash-Next deepswe-1.1 dir's `client_requirements.txt`, which pins that commit; `local_env_notes.md`
    gives the install caveats.
  - Upstream: meridianlabs-ai/inspect_harbor#200. Once a release carries it, switch back to the release.
  - Use the v1.1 task images. The v1.0 images keep future `origin/*` refs.
- **swe-bench-pro.** The published tasks give the agent internet, and their images keep the project's future git
  history, including the gold commit. Agents downloaded newer upstream releases, and one run was withdrawn.
  - Fix: the inspect_harbor fork above, plus `assets/harbor_registry.json` pinned to
    `eldarkurtic/harbor-datasets@d81053e87b`. That pin carries harbor-framework/harbor-datasets#263: the agent is
    offline, the history is removed, and the gold tests ship with the verifier.
  - The older pin `2494eda6ae` has only the verifier fixes (#258), not the leak fixes.
- **swe-bench-verified.** inspect_evals' default Epoch AI images keep every release tag of the project, so the
  reference fix is readable offline (`git show <later tag>:<file>`).
  - Fix: use the official images, `-T image_name_template=swebench/sweb.eval.{arch}.{org}_1776_{repo}-{issue}:latest`
    (UKGovernmentBEIS/inspect_evals#2632). The agent has no internet by the task's default.
- **terminal-bench-2.1.** Every task sets `allow_internet = true`, and several verifiers `apt-get install` at test
  time, so the network can't be closed.
  - The task files, including `solution/solve.sh` and `tests/`, are public: `harbor-framework/terminal-bench-2-1`
    on GitHub, and mirrors on the HF Hub (find them with `huggingface.co/api/datasets?search=terminal-bench`).
  - Only the audit catches it when an agent downloads its own task's files.
- **livecodebench.** The tasks set no network policy, so the agent has internet (the fork changes nothing). Audit
  for lookups of the problem's published solutions.
- **Any new task with tools.** Check each `task.toml` network policy against what the runner enforces (after a run,
  Harbor's task files are cached under `~/.cache/harbor/tasks/packages/` and `~/.cache/inspect_harbor/tasks/git/`;
  tasks loaded from a registry pin can be read from the pinned commit with a shallow fetch). Check the
  images for refs and tags newer than the base commit (`git log --all`, `git tag`, unreachable objects). Search for
  public copies of the task files. Then add the task to this list.
- Validate a dataset or verifier change with `--solver inspect_harbor/oracle` on every image family. Image
  families differ even within one repo; for example, the Alpine images' BusyBox `tar` lacks GNU options.

**Audit after every run, before you fill Results.** Scan every tool call of every sample in the final `.eval`
logs. Read `sample.events`, not `sample.messages`: context compaction drops early turns from the messages.

```python
import json, re
from inspect_ai.log import read_eval_log
NET = re.compile(r"pip3? (download|index)|git (fetch|clone|pull|ls-remote|remote add)|git log [^|;&\n]*--all"
                 r"|github\.com|githubusercontent|gitlab\.com|huggingface\.co|pypi\.org|registry\.npmjs|npm (view|pack)"
                 r"|proxy\.golang|go (get|install|mod download)|crates\.io|curl |wget |urlopen|requests\.get", re.I)
log = read_eval_log("logs/<file>.eval", resolve_attachments=True)
for s in log.samples:
    for ev in s.events:
        if ev.event == "tool" and NET.search(cmd := json.dumps(ev.arguments)):
            print(s.id, s.epoch, {k: v.value for k, v in (s.scores or {}).items()}, cmd[:300], str(ev.result)[:300])
```

- Networked tasks give hundreds of hits; review them by hand.
- A leak is any case where the agent obtained:
  - its own task's files (`solution/`, `tests/`);
  - the project's upstream work past the task's base commit: GitHub issues, PRs, commits or files, or a clone or
    fetch of the upstream repo;
  - a newer release of the project itself (`pip download`, `npm view`/`npm pack`, `go get ...@latest`);
  - the reference fix from git history in the image.
- Not leaks: installing tools (linters, formatters, test runners), dependency downloads, `git clone /app` (a local
  copy), URLs the agent writes into code or docs, and Go import paths.
- In a task whose agent should be offline, any successful outbound request means the fix is not active. Stop, and
  check the client environment against the dir's `client_requirements.txt`.
- For each leak, check whether the sample passed and whether it used what it fetched. Report every leak to the
  user in chat: sample id, epoch, what was fetched, the score, and the score with leaked samples counted as
  failures. The user decides whether and how the README reports it.

## 12. Reflection procedure (mandatory)

Run it when you finish an eval of a model (final run done, README filled) or any other meaningful piece of work: a
new task, an infrastructure problem solved, an upstream fix, a move to a new host or tool version. Do it before you
report back to the user. These notes are the knowledge base every later agent starts from, on any server, so each
lesson you skip will be paid for again.

1. **Collect.** List what went wrong or cost time, what surprised you, what you had to find out by experiment, and
   what you would do differently. Include what the user corrected or decided along the way.
2. **Keep what generalizes:** anything that would help another agent with another model on another server. Drop
   one-off noise.
3. **Write it where the next agent reads it:**
   - rules, eval protocol, scoring, Inspect / vLLM / Harbor behaviour, leaks and audits: this file (section 9 for
     gotchas, 10 for conventions, 11 for leaks, or a new section);
   - serving, caches, Docker, images, client environments: `local_env_notes.md`;
   - one task's upstream defects: that task's README, under Patches;
   - facts about this machine only: `local_env_notes.local.md`, which is not shared.
4. **Write it general.** Leave out paths, user names, venv locations, hostnames and other tenants. Name the tool,
   version and symptom, and give cause and fix with numbers where you have them, so others recognize the problem.
5. **Build on what is there.** Update or correct an existing note rather than adding a near-duplicate, and delete
   notes that turned out wrong. Keep READMEs to results (section 3): the lessons go in the notes, not the README.
6. **Report.** Tell the user in chat which notes you added or changed; committing them is their job.

The internet-access and cheating findings of section 11 show why. They were first recorded only in a few task READMEs,
so later runs of the same tasks on another host copied an older dir and ran without the fixes.
