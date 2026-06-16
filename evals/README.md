# Memex Agent Evals

This directory contains lightweight evaluation entrypoints for the Memory
Primary pipeline. The first runner is intentionally small and current-code
compatible: it replays JSONL operations through real `MemexRouter.submitInput`,
waits for `LocalTaskExecutor` to settle, and emits observations plus a Markdown
comparison report.

See `METRICS.md` for the candidate gate, failure attribution, and evidence-level
definitions.

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
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 \
  flutter test --no-pub evals/replay/memory_primary_full_chain_replay_test.dart
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

- Use `MEMEX_EVAL_TASK_TIMEOUT_SECONDS=180` and
  `MEMEX_EVAL_SUITE_TIMEOUT_SECONDS=7200` for 24-record shards.
- Keep real-model execution to at most two concurrent shards unless the model
  provider has been separately load-tested.
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
dart run evals/bin/merge_memory_primary_eval_runs.dart \
  evals/runs/memory_primary_scale_shard_0 \
  evals/runs/memory_primary_scale_shard_1
```

Or with env vars:

```bash
MEMEX_EVAL_MERGE_RUN_DIRS=evals/runs/memory_primary_scale_shard_0,evals/runs/memory_primary_scale_shard_1 \
MEMEX_EVAL_MERGE_OUTPUT_DIR=evals/runs/memory_primary_scale_merged \
dart run evals/bin/merge_memory_primary_eval_runs.dart
```

The merge script concatenates `observations.jsonl` / `failures.jsonl`, recomputes
aggregate rates, deltas, and `gate.json`, then writes a merged `report.md`.

## Suggested Progression

1. Run no-LLM smoke on `memory_primary_smoke` to validate harness plumbing.
2. Run real LLM + embedding with `MEMEX_EVAL_CASE_LIMIT=1`.
3. Generate `memory_primary_mock_scale` and run no-LLM for report shape.
4. Run real LLM + embedding on scale data in shards by setting
   `MEMEX_EVAL_CASE_OFFSET`, `MEMEX_EVAL_CASE_LIMIT`, and distinct
   `MEMEX_EVAL_RUN_DIR` values.
5. Only treat a run as rollout evidence when it uses real LLM + embedding,
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
