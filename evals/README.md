# Memex Agent Evals

This directory contains lightweight evaluation entrypoints for the Memory
Primary pipeline. The first runner is intentionally small and current-code
compatible: it replays JSONL operations through real `MemexRouter.submitInput`,
waits for `LocalTaskExecutor` to settle, and emits observations plus a Markdown
comparison report.

See `METRICS.md` for the candidate gate, failure attribution, and evidence-level
definitions.

## Current Iteration Target

This iteration keeps the legacy `legacy_pkm` baseline frozen and iterates only
the Memory Primary path. The target scale run is 12 personas, 600 record
operations per persona, and at least 50 interleaved Super Agent asks per
persona. All metrics from the original online gate and the newly confirmed
journey, vector-contribution, pairwise-judge, provider-pool, and artifact-audit
metrics must be recorded in `metrics.json`, judge artifacts, case logs, or the
iteration report.

Legacy is frozen, but not exempt from scoring. If `legacy_pkm` fails because of
its own chain behavior, such as task exceptions, loop/max-turn failures, failure
to settle, or inability to exit normally, the failure is counted as a legacy
chain failure. Only clearly external provider infrastructure problems, such as
429/out-of-quota/connection failures, are classified separately as provider
health noise and excluded from effect-quality conclusions after rerouting.

The execution order is:

1. Generate and audit the small fixture.
2. Run the real-provider small gate.
3. Render badcases, fix only Memory Primary issues, and record each iteration in
   `evals/ITERATION_LOG.md`.
4. Generate/audit the 12-user scale fixture and shard plan.
5. Run scale shards, monitor with `watch-status`, merge, judge, render
   badcases, run strict audit, and publish the Chinese report.

## Retrieval Practice Baseline

The Memory Primary recall path follows a simple hybrid-search baseline instead
of case-specific ranking rules:

- Lexical retrieval: FTS/BM25-like ranking over memory text and metadata.
- Dense retrieval: OpenRouter `qwen/qwen3-embedding-8b` embeddings for semantic
  similarity.
- Fusion: reciprocal rank fusion (RRF) over the two ranked lists. Entity,
  evidence, recency, and importance are kept as traceable reasons/tie-break
  context rather than bespoke case fixes.

This mirrors current public production patterns: Azure AI Search describes
hybrid full-text plus vector queries merged with RRF, Elastic positions hybrid
search as lexical plus semantic retrieval in one ranked list, and OpenSearch
ships rank-fusion processors for hybrid search. The original SIGIR RRF paper is
also useful here because RRF combines ranked lists without requiring fragile
normalization between BM25 scores and vector similarities.

References:

- https://learn.microsoft.com/en-us/azure/search/hybrid-search-overview
- https://www.elastic.co/what-is/hybrid-search
- https://docs.opensearch.org/latest/vector-search/ai-search/hybrid-search/index/
- https://cormack.uwaterloo.ca/cormacksigir09-rrf.pdf
- https://openrouter.ai/docs/api/reference/embeddings
- https://huggingface.co/Qwen/Qwen3-Embedding-8B

## Dataset Generation

Generate the default scale mock dataset:

```bash
dart run evals/bin/generate_memory_primary_mock_dataset.dart
```

Defaults:

- Output: `evals/datasets/memory_primary_mock_scale`
- Cases: 8
- Records: 192
- Memory recall probes: 16

Useful env vars:

- `MEMEX_EVAL_GENERATED_CASES`: number of persona cases.
- `MEMEX_EVAL_GENERATED_RECORDS_PER_CASE`: records per persona.
- `MEMEX_EVAL_SUPER_AGENT_ASKS_PER_CASE`: active read-only Super Agent asks
  per case. Defaults to `0`; set to `1` or `2` for targeted ask/recall
  journeys with real LLM credentials.
- `MEMEX_EVAL_GENERATED_DATASET_DIR`: output directory.

Generate a shorter tuning dataset for real LLM prompt iteration:

```bash
MEMEX_EVAL_GENERATED_CASES=4 \
MEMEX_EVAL_GENERATED_RECORDS_PER_CASE=8 \
MEMEX_EVAL_GENERATED_DATASET_DIR=evals/datasets/memory_primary_mock_short \
dart run evals/bin/generate_memory_primary_mock_dataset.dart
```

Use short-scale for fast prompt/schema iteration, then rerun the 24-record scale
dataset for rollout evidence.

## Full-Chain Smoke

Run without external LLMs:

```bash
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 \
  flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

Run with real eval LLM and embedding credentials:

```bash
MEMEX_EVAL_ENABLE_LLM=1 \
MEMEX_EVAL_LLM_TYPE=mimo \
MEMEX_EVAL_LLM_MODEL=mimo-v2.5 \
MEMEX_EVAL_LLM_BASE_URL=<anthropic-compatible-base-url> \
MEMEX_EVAL_LLM_API_KEY=<redacted> \
MEMEX_EVAL_EMBEDDING_MODEL=qwen/qwen3-embedding-8b \
MEMEX_EVAL_EMBEDDING_BASE_URL=https://openrouter.ai/api/v1 \
MEMEX_EVAL_EMBEDDING_API_KEY=<redacted> \
env -u ws_proxy -u wss_proxy \
  NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 \
  flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

The same real-run paths can be launched through the safer orchestration wrapper,
which reads already-exported environment variables, never accepts API keys as
arguments, unsets local WebSocket proxies, and writes only redacted artifacts:

```bash
dart run evals/bin/run_memory_primary_iteration.dart doctor
dart run evals/bin/run_memory_primary_iteration.dart preflight
dart run evals/bin/run_memory_primary_iteration.dart small
dart run evals/bin/run_memory_primary_iteration.dart judge <run-dir>
dart run evals/bin/run_memory_primary_iteration.dart badcases <run-dir>
dart run evals/bin/run_memory_primary_iteration.dart audit <run-dir>
dart run evals/bin/run_memory_primary_iteration.dart report <run-dir>
dart run evals/bin/run_memory_primary_iteration.dart status <run-dir>
dart run evals/bin/run_memory_primary_iteration.dart watch-status <scale_shard_manifest.json>
```

Before a real replay, run a model/provider preflight only. This writes
`llm_preflight.json` and a short `report.md`, then exits before case execution:

```bash
MEMEX_EVAL_ENABLE_LLM=1 \
MEMEX_EVAL_LLM_PREFLIGHT_ONLY=1 \
MEMEX_EVAL_LLM_TYPE=mimo \
MEMEX_EVAL_LLM_MODEL=mimo-v2.5 \
MEMEX_EVAL_LLM_BASE_URL=<anthropic-compatible-base-url> \
MEMEX_EVAL_LLM_API_KEY=<redacted> \
flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

Do not scale a run until preflight passes for every configured subscription.
If a provider rejects synthetic preflight calls but works in the real agent
path, set `MEMEX_EVAL_SKIP_LLM_PREFLIGHT=1` and document the reason in
`evals/ITERATION_LOG.md`.

For provider pools, pass comma-separated `MEMEX_EVAL_LLM_BASE_URLS` and
`MEMEX_EVAL_LLM_API_KEYS` for the MiMo agent chain. Use OpenRouter only through
`MEMEX_EVAL_EMBEDDING_*` for Qwen3 Embedding 8B. If local Flutter tests fail
with `Invalid WebSocket upgrade request`, unset `ws_proxy` / `wss_proxy` and set
`NO_PROXY=localhost,127.0.0.1,::1`.

During full-chain replay, each case/user still starts from one assigned provider
slot for journey comparability. Interleaved Super Agent asks may retry across the
configured pool on retryable provider errors; clearly out-of-quota providers are
disabled for the remainder of the run. Attempts are written as redacted
`provider_attempts` in observations and summarized by
`super_agent_provider_*` metrics.

Scale shards also enable an eval-only non-settlement guard by default:
`MEMEX_EVAL_ABORT_CASE_AFTER_CONSECUTIVE_UNSETTLED_RECORDS=3`. If a frozen
legacy chain, or any other mode, repeatedly fails to settle record operations,
the harness records `task_not_settled` plus
`case_aborted_after_consecutive_unsettled`, counts skipped operations in
`eval_aborted_operation_count`, and moves on to preserve reproducible artifacts.
This guard does not change agent behavior and does not turn chain failures into
provider noise.

Generate the PR256 small gate fixture with interleaved Agent asks and varied
roles, locations, mood transitions, and conflict topics:

```bash
MEMEX_EVAL_PERSONA_COUNT=3 \
MEMEX_EVAL_RECORDS_PER_PERSONA=48 \
MEMEX_EVAL_AGENT_QUERIES_PER_PERSONA=6 \
dart run evals/bin/generate_pr256_full_metric_dataset.dart
```

Generate the scale target for this iteration:

```bash
dart run evals/bin/run_memory_primary_iteration.dart generate-scale
dart run evals/bin/run_memory_primary_iteration.dart plan-scale
```

Audit the generated dataset shape before spending provider budget:

```bash
dart run evals/bin/run_memory_primary_iteration.dart audit-dataset \
  evals/datasets/pr256_full_metric_small/cases.jsonl

dart run evals/bin/run_memory_primary_iteration.dart audit-dataset \
  evals/datasets/pr256_full_metric_large_p12_r600_q50/cases.jsonl
```

The dataset audit verifies case/record/ask counts, strict interleaving of
Super Agent asks between record operations, query-family coverage, and persona
diversity across roles, locations, travel cities, moods, and conflict topics.

Create a scale shard manifest before launching the 12-persona run:

```bash
dart run evals/bin/run_memory_primary_iteration.dart plan-scale \
  evals/datasets/pr256_full_metric_large_p12_r600_q50/cases.jsonl
```

The plan writes `scale_shard_manifest.json`, `scale_shard_commands.sh`, and
`scale_shard_plan.md` under `MEMEX_EVAL_SCALE_PLAN_DIR` or
`evals/runs/pr256_next_scale_p12_r600_q50/plan` by default. It includes one
command per persona shard, plus status, watch-status, merge, judge, badcase,
strict-audit, and report commands. The generated files intentionally contain no
provider secrets.

Track a long scale run at a fixed interval:

```bash
MEMEX_EVAL_STATUS_INTERVAL_SECONDS=300 \
dart run evals/bin/run_memory_primary_iteration.dart watch-status \
  evals/runs/pr256_next_scale_p12_r600_q50/plan/scale_shard_manifest.json
```

`watch-status` treats missing/incomplete shards as progress warnings, writes the
latest `scale_shard_audit.json/md`, and then prints the status table for every
planned shard. Final pass/fail still comes from strict `audit-shards`, merged
`audit`, judge, and report commands.

To spread cases across multiple equivalent subscriptions, provide comma-separated
lists. The runner assigns one model config per case/user by index, which keeps a
single user from mixing providers during a replay. For sharded runs that use
`MEMEX_EVAL_CASE_OFFSET`/`MEMEX_EVAL_CASE_LIMIT`, the global case offset is part
of provider slot selection so single-case shard processes still spread across
the prioritized provider order. Set `MEMEX_EVAL_LLM_PROVIDER_PRIORITIES` to
prefer healthier routes when assigning case slots; providers with the same
priority keep their listed order:

```bash
MEMEX_EVAL_LLM_MODEL=mimo-v2.5 \
MEMEX_EVAL_LLM_BASE_URLS=<base-url-a>,<base-url-b>,<base-url-c>,<base-url-d> \
MEMEX_EVAL_LLM_API_KEYS=<redacted-a>,<redacted-b>,<redacted-c>,<redacted-d> \
MEMEX_EVAL_LLM_PROVIDER_PRIORITIES=2,1,1,0 \
flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

For LLM-as-judge post-processing, `evals/bin/run_pr256_judge.dart` can use all
configured providers concurrently because judge tasks do not share a replay user
workspace. Retryable 408/429/5xx/network errors put only that provider into a
short cooldown, defaulting to 5000ms, then it re-enters the pool. Use
`MEMEX_EVAL_JUDGE_PROVIDER_PRIORITIES` to prefer lower-latency or healthier
routes while still keeping every configured provider eligible. Providers that
are out of quota should be omitted from these comma-separated lists until they
are revalidated; short-window 429s can stay in the pool and will cool down
automatically:

```bash
MEMEX_EVAL_JUDGE_BASE_URLS=<base-a>,<base-b>,<base-c>,<base-d>,<base-e> \
MEMEX_EVAL_JUDGE_API_KEYS=<redacted-a>,<redacted-b>,<redacted-c>,<redacted-d>,<redacted-e> \
MEMEX_EVAL_JUDGE_PROVIDER_PRIORITIES=1,1,1,1,2 \
MEMEX_EVAL_JUDGE_PROVIDER_COOLDOWN_MS=5000 \
MEMEX_EVAL_JUDGE_CONCURRENCY=32 \
dart run evals/bin/run_pr256_judge.dart
```

Useful env vars:

- `MEMEX_EVAL_DATASET`: JSONL dataset path. Defaults to
  `evals/datasets/memory_primary_smoke/cases.jsonl`.
- `MEMEX_EVAL_RUN_DIR`: output directory. Defaults to
  `evals/runs/memory_primary_full_chain_<timestamp>`.
- `MEMEX_EVAL_PIPELINE_MODES`: comma-separated modes. Defaults to
  `legacy_pkm,memory_primary`.
- `MEMEX_EVAL_MODES`: alias for `MEMEX_EVAL_PIPELINE_MODES`, useful for short
  targeted reruns.
- `MEMEX_EVAL_CASE_OFFSET`: skip this many cases before applying limit.
- `MEMEX_EVAL_CASE_LIMIT`: limit cases for a small gate.
- `MEMEX_EVAL_CHANGED_CASES`: comma-separated case ids to run. This filters the
  loaded dataset before offset/limit, so targeted regression runs can replay
  only affected cases.
- `MEMEX_EVAL_ASK_TIMEOUT_SECONDS`: timeout for each `super_agent_ask`
  operation. Defaults to `180`.
- `MEMEX_EVAL_LLM_PREFLIGHT_ONLY=1`: validate LLM provider/model connectivity
  and exit before case execution.
- `MEMEX_EVAL_SKIP_LLM_PREFLIGHT=1`: skip the preflight when a provider is known
  to reject synthetic checks.
- `MEMEX_EVAL_LLM_PREFLIGHT_WARN_ONLY=1`: keep running even when preflight
  fails; the failure remains recorded in artifacts.
- `MEMEX_EVAL_TASK_TIMEOUT_SECONDS`: task settle timeout per operation.
- `MEMEX_EVAL_SUITE_TIMEOUT_SECONDS`: Flutter test suite timeout. Use a
  longer value such as `3600` for 24-record real LLM shards.
- `MEMEX_EVAL_ENFORCE_GATE=1`: fail the test when `gate.json` does not pass.
- `MEMEX_EVAL_MAX_P95_RECORD_MS`: override the candidate latency threshold.

Recommended real-LLM scale settings:

- Use `MEMEX_EVAL_TASK_TIMEOUT_SECONDS=300` or higher for record-chain shards
  when providers are cooling down from short-window 429s, and set
  `MEMEX_EVAL_SUITE_TIMEOUT_SECONDS` according to shard size.
- Keep record-chain execution to at most one or two concurrent shards unless the
  model provider pool has been separately load-tested. Judge tasks may use
  higher concurrency because they have independent provider fallback and do not
  share a persona workspace.
- Treat nonzero `provider_infra_task_error_count` or
  `provider_infra_affected_operation_rate` as provider-contaminated evidence:
  lower shard concurrency, adjust `MEMEX_EVAL_LLM_PROVIDER_PRIORITIES`, remove
  out-of-quota providers, and rerun affected shards before making effect-quality
  claims.
- If Flutter local test startup reports WebSocket/proxy errors, keep localhost
  out of proxy routing and clear websocket proxy env vars:

```bash
NO_PROXY=localhost,127.0.0.1,::1 \
no_proxy=localhost,127.0.0.1,::1 \
env -u ws_proxy -u wss_proxy -u WS_PROXY -u WSS_PROXY \
  flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

By default `CardInsightAgent` uses a deterministic fast insight draft for the
first Memory Primary gate path. Set `MEMEX_CARD_INSIGHT_ENABLE_LLM=1` only when
explicitly evaluating deeper LLM-generated card insight quality; that path is
slower and should be measured separately from the Memory Primary memory gate.

Outputs:

- `observations.jsonl`: per mode/case/operation observations.
- `failures.jsonl`: per-case failure attribution.
- `metrics.json`: aggregate metrics per mode.
- `gate.json`: candidate rollout gate result.
- `report.md`: side-by-side comparison plus tail-latency attribution for the
  slowest record operations.
- `llm_preflight.json`: redacted per-subscription provider/model connectivity
  result, including HTTP status and error summary when applicable.
- `case_debug_index.md`: per-mode/per-case index for debugging, including
  failure counts, unsettled operations, slowest operation, and the case log path.
- `case_logs/<mode>/<case_id>.json`: detailed case log with original case data,
  operation observations, new task timeline, final cards, active Memory atoms,
  PKM file snapshot snippets, LLM token/cache statistics, and failures.

The runner redacts API keys from artifacts. Do not commit `evals/runs/`.

## Case Debugging and Iteration Notes

When a run exposes a problem, start from `case_debug_index.md`, open the
corresponding `case_logs/<mode>/<case_id>.json`, and inspect these sections
together:

- `operation_observations`: per input/recall/projection observations and new
  tasks created by that operation.
- `final_tasks`: task status, retry counts, payloads, results, and errors.
- `final_cards`: card status, title, templates, insight, comments, and raw YAML
  content as parsed by the app.
- `final_memory_atoms`: active Memory Primary atoms after the case journey.
- `pkm_snapshot`: PKM files and snippets for legacy/PARA inspection.
- `llm_usage`: token/cache statistics from `_System/llm_calls`.

For each meaningful iteration, add a short entry to
`evals/ITERATION_LOG.md` with the affected case id, failed metric, root cause,
fix, verification run, and residual risk. You can also stamp the run artifacts
with metadata:

```bash
MEMEX_EVAL_ITERATION_ID=memory-primary-small-gate-001 \
MEMEX_EVAL_ITERATION_NOTE="tighten owner correction recall" \
MEMEX_EVAL_BASELINE_RUN=evals/runs/<previous_run> \
MEMEX_EVAL_CHANGED_CASES=memory_primary_scale_003,memory_primary_scale_006 \
flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```

## Merge Shards

Merge several completed run directories:

```bash
dart run evals/bin/run_memory_primary_iteration.dart merge \
  evals/runs/memory_primary_scale_shard_0 \
  evals/runs/memory_primary_scale_shard_1
```

Or with env vars:

```bash
MEMEX_EVAL_MERGE_RUN_DIRS=evals/runs/memory_primary_scale_shard_0,evals/runs/memory_primary_scale_shard_1 \
MEMEX_EVAL_MERGE_OUTPUT_DIR=evals/runs/memory_primary_scale_merged \
dart run evals/bin/run_memory_primary_iteration.dart merge
```

The merge script concatenates `observations.jsonl`, `failures.jsonl`, and
`judge_tasks.jsonl`, copies `case_logs/`, recomputes aggregate rates, deltas,
and `gate.json`, then writes a merged `report.md` and `case_debug_index.md`.

## Artifact Audit

Audit a small, shard, or merged run before treating it as evidence:

```bash
dart run evals/bin/run_memory_primary_iteration.dart audit evals/runs/<run-dir>
```

For final real-provider evidence, tighten the audit with:

```bash
MEMEX_EVAL_AUDIT_EXPECT_MODES=legacy_pkm,memory_primary \
MEMEX_EVAL_AUDIT_EXPECT_LLM=1 \
MEMEX_EVAL_AUDIT_EXPECT_JUDGE=1 \
MEMEX_EVAL_AUDIT_EXPECT_PAIRWISE=1 \
MEMEX_EVAL_AUDIT_EXPECT_BADCASES=1 \
MEMEX_EVAL_AUDIT_EXPECT_GATE_PASS=1 \
dart run evals/bin/run_memory_primary_iteration.dart audit evals/runs/<merged-run-dir>
```

The audit writes `artifact_audit.json` and `artifact_audit.md`, checks required
artifacts, mode metrics, case log coverage, judge task counts, optional judge
outputs, optional gate status, and common provider-key leak patterns.

## Badcase Ledger

After replay or merge, render a badcase ledger before audit/report:

```bash
dart run evals/bin/run_memory_primary_iteration.dart badcases evals/runs/<run-dir>
```

This writes `badcases.md` and `badcases.jsonl`. Each grouped badcase includes
case id, persona, operation id, input, expected result, actual result, failed
metric categories, root-cause classification, suggested fix point, verification
artifact/command, legacy impact, and whether a scale retest is needed. The
classification is an initial machine summary; precise root causes and final
fixes still belong in `evals/ITERATION_LOG.md`.

## Iteration Report

After replay, judge, merge, and audit, render a Chinese closeout report from
the run artifacts:

```bash
dart run evals/bin/run_memory_primary_iteration.dart report evals/runs/<run-dir>
```

By default the report is written to `evals/reports/` with the run directory name
in the file name. Set `MEMEX_EVAL_REPORT_OUTPUT` or pass a second argument when
a fixed output path is needed:

```bash
dart run evals/bin/run_memory_primary_iteration.dart report \
  evals/runs/<merged-run-dir> \
  evals/reports/<date>-memory-primary-scale-p12-r600-q50.zh.md
```

The report consumes existing artifacts only. It summarizes sample coverage,
gate status, Agent interleaved-query metrics, pairwise judge results, vector
retrieval contribution, provider retry diagnostics, badcase categories, and the
artifact audit status without re-running the chain.

## Progress Status

During long small/scale runs or after merging shards, summarize progress and
evidence health without opening every artifact:

```bash
dart run evals/bin/run_memory_primary_iteration.dart status evals/runs/<run-dir>
```

The status command reads `progress.json`, `metrics.json`, `gate.json`,
`artifact_audit.json`, and optional judge metrics. It prints the latest
operation, mode-level records/asks/query-interleaving/memory/recall/Agent/gate
signals, and judge provider status when available.

## Suggested Progression

1. Run no-LLM smoke on `memory_primary_smoke` to validate harness plumbing.
2. Generate and audit the PR256 small gate fixture with interleaved Agent asks.
3. Run real LLM + OpenRouter embedding with `MEMEX_EVAL_CASE_LIMIT=1`, and use
   `status` for progress checks while it runs.
4. Iterate only the Memory Primary path and record each badcase in
   `evals/ITERATION_LOG.md`; use `badcases` to generate the structured ledger
   from run artifacts before hand-editing root-cause notes.
5. Generate and audit the 12 persona / 600 records / 50 asks scale dataset,
   run `plan-scale`, then run real LLM + embedding in shards from the generated
   manifest commands.
6. Only treat a run as rollout evidence when it uses real LLM + embedding,
   passes the candidate gate, and shows positive Memory Primary deltas against
   `legacy_pkm`.

Current reference evidence:

- `evals/reports/2026-06-10-memory-primary-fresh-current.md` summarizes the
  8-case / 192-record real LLM + embedding run from 2026-06-10.
- The local artifact report is
  `evals/runs/memory_primary_merged_fresh_current_fastinsight_shards_0_7_20260610/report.md`.
  This path is intentionally ignored by git; regenerate it when validating a
  new model, prompt, schema, or retrieval change.

Example 8-case scale shards:

```bash
MEMEX_EVAL_DATASET=evals/datasets/memory_primary_mock_scale/cases.jsonl \
MEMEX_EVAL_CASE_OFFSET=0 MEMEX_EVAL_CASE_LIMIT=2 \
MEMEX_EVAL_RUN_DIR=evals/runs/memory_primary_scale_shard_0 \
flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart

MEMEX_EVAL_DATASET=evals/datasets/memory_primary_mock_scale/cases.jsonl \
MEMEX_EVAL_CASE_OFFSET=2 MEMEX_EVAL_CASE_LIMIT=2 \
MEMEX_EVAL_RUN_DIR=evals/runs/memory_primary_scale_shard_1 \
flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
```
