# Memory Primary Eval Metrics

This eval layer is designed to answer whether the Memory Primary pipeline is
better than the legacy per-input PKM path under comparable replay data. It keeps
the earlier harness discipline: small gate first, real timestamps, full-chain
`submitInput`, persistent task settling, local artifacts, and rule-based checks
before any optional LLM judging.

## Evidence Levels

| Level | Meaning |
| --- | --- |
| `llm_preflight` | Validates every configured provider/model subscription before case execution; blocks scale runs when the model is unsupported or credentials are invalid. |
| `harness_smoke` | No external LLM. Validates replay plumbing, task settling, report generation, and fallback paths only. |
| `audited_synthetic_fixture` | Generated mock data with expected memory/card/recall checks. Useful for regression and scale shape, but still synthetic. |
| `real_llm_small_gate` | Same full chain with real LLM and embedding credentials on a small case limit. Validates live agent behavior before scaling. |
| `real_llm_scale` | Larger replay run with real LLM/embedding, failure attribution, and candidate gate. Required before product rollout. |

## Core Metrics

| Metric | Why it matters |
| --- | --- |
| `completed_card_rate` | Input still materializes usable timeline cards. |
| `cards_with_insight_rate` | Memory Primary chain should enrich cards through `card_insight_agent`. |
| `memory_expected_hit_rate` | Long-term facts that should be remembered are present in active Memory Primary atoms. |
| `memory_must_not_write_precision` | Temporary/noisy facts are not over-written into long-term memory. |
| `memory_recall_hit_rate` | Direct Memory Primary recall can retrieve expected active memories after writes and corrections. |
| `memory_recall_must_not_precision` | Recall should not surface forbidden stale/noisy facts. |
| `super_agent_answer_success_rate` / `super_agent_answer_hit_rate` / `super_agent_boundary_precision` | Targeted ask journeys verify that Super Agent can read the right memory without asserting stale or forbidden facts. |
| `related_fact_hit_rate` | Card insight cites expected earlier records where the dataset defines cross-record continuity. |
| `card_expected_hit_rate` | Card titles/insights preserve expected key information. |
| `scenario_family_coverage` / `agent_chain_coverage` / `journey_stage_coverage` | PR #256 coverage metrics showing whether the selected dataset actually exercises the intended scenarios, chains, and journeys. |
| `task_settlement_rate` | Background work converges inside the configured timeout. |
| `failed_task_count` / `task_not_settled_count` | Hard operational stability signals. |
| `avg_record_elapsed_ms` / `p90_record_elapsed_ms` / `p95_record_elapsed_ms` / `p99_record_elapsed_ms` / `max_record_elapsed_ms` | Latency and cost proxy; Memory Primary quality gains must not hide unacceptable tail latency. |
| `slowest_records` | Top slow record operations per mode, including case, operation, task settlement, task status counts, atom count, and card title for latency attribution. |

## PR #256 Metric Alignment

The source framework is `docs/memex-evaluation-framework.md` from
`memex-lab/memex#256` (merged on 2026-06-10 and synced into this worktree for
local auditability). The PR is intentionally a broad Agent-eval framework, so
the rollout evidence separates metric names into direct run metrics, LLM judge
metrics, proxy/trace metrics, and explicit out-of-scope product capabilities.

Current large-run evidence:

- Legacy baseline:
  `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_with_pr256_instrumentation_20260615`
- Memory Primary v12:
  `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_with_pr256_instrumentation_20260615`
- Focused Quick Query closeout:
  `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_with_latency_20260615`
  (deterministic replay with `tool_call_latency_p95_by_tool`) and
  `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_after_relationship_type_fix_20260615`
  (LLM judge closeout)
- Trace metric smoke:
  `evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615`
  (LLM turn metadata and agent activity transcript closeout)
- Per-metric coverage audit:
  `evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md`

The replay runner separates metrics into:

| Tier | Meaning | Current status |
| --- | --- | --- |
| `collected` | Emitted directly in `metrics.json` from replay artifacts. | Used for small gate and scale reports. |
| `case_log` | Available in `case_logs/<mode>/<case_id>.json` for debugging or manual/LLM judging. | Used for failure triage and iteration notes. |
| `proxy_or_trace` | The PR metric is represented by a stricter deterministic proxy or preserved in case logs for audit. | Used when the exact PR metric needs richer labels than the rollout dataset carries. |
| `not_in_rollout_scope` | Product capability or Agent surface not required for the Memory Primary vs legacy switch. | Excluded from gate and called out explicitly. |

### Collected Metrics

| PR #256 area | Metrics currently emitted |
| --- | --- |
| Card Agent | `card_materialization_rate`, `input_to_valid_card_success_rate`, `card_completed_rate`, `completed_with_failure_reason_rate`, `card_schema_valid_rate`, `card_source_fact_grounding_rate`, `card_expected_hit_rate`, `cards_with_insight_rate` |
| Memory | `memory_must_write_recall`, `memory_must_not_write_precision`, `memory_recall_at_10`, `memory_source_grounding`, `memory_duplicate_rate` |
| Retrieval / grounding | `retrieval_hit_at_1`, `retrieval_hit_at_3`, `retrieval_hit_at_5`, `retrieval_hit_at_10`, `related_fact_hit_rate`, `answer_must_include` |
| Super Agent / Chat | `super_agent_ask_count`, `super_agent_answer_success_rate`, `super_agent_answer_hit_rate`, `super_agent_boundary_precision`, `super_agent_tokens_per_ask`, `super_agent_read_only_compliance`, `tool_selection_accuracy`, `tool_args_accuracy`, `tool_call_minimality` |
| Tool trajectory | `tool_call_failure_rate`, `tool_call_retry_rate`, `repeated_tool_call_rate`, `read_tool_error_rate`, `write_tool_error_rate`, `context_peek_count_per_task`, `context_peek_redundancy_rate`, `first_write_after_read_rate`, `agent_tool_rounds_per_task`, `loop_detection_absence`, `max_turns_absence` |
| Stability | `task_settlement_rate`, `task_completion_status`, `failed_task_rate`, `retry_rate`, `input_timeout_rate`, `task_status_totals`, `task_type_status_totals` |
| Agent turn trace | `agent_empty_response_rate`, `agent_empty_response_count`, `agent_llm_turns_per_task`, `agent_llm_turns_per_task_by_agent` |
| Latency | `input_required_chain_latency_ms`, `avg_record_elapsed_ms`, `p90_record_elapsed_ms`, `p95_record_elapsed_ms`, `p99_record_elapsed_ms`, `max_record_elapsed_ms` |
| Cost / cache | `tokens_per_input`, `tokens_per_successful_input`, `llm_usage_total`, `tokens_by_agent`, `prompt_cache_token_hit_rate` |
| Coverage | `scenario_family_coverage`, `agent_chain_coverage`, `journey_stage_coverage`, `operation_type_coverage`, `cross_day_continuity_coverage`, `correction_operation_coverage`, `noise_resilience_coverage`, `follow_up_query_coverage`; raw covered/expected sets are also preserved under `coverage`. |
| Provider readiness | `llm_preflight.json` records redacted per-subscription model/provider connectivity, HTTP status, and provider error summaries before replay. |

### LLM Judge Metrics

| PR #256 area | Metrics | Current evidence |
| --- | --- | --- |
| Card title quality | `card_title_relevance_score` | Original 3200-card judge in the Memory Primary v12 run. |
| QA grounding | `unsupported_claim_absence`, `grounded_answer_rate` | Original 32-ask judge plus focused 64-task closeout after Quick Query fixes. |
| Knowledge Insight | `insight_novelty_score`, `insight_actionability_score` | Supplemental judge over 320 large-run insight samples. |
| Comment | `comment_relevance_score`, `comment_boundary_safety` | Supplemental judge over 80 large-run comment/boundary samples. |
| PKM/PARA projection | `pkm_append_coherence` | Supplemental judge over 8 projection samples; one raw failure is audited as judge artifact in the report. |

### Proxy / Trace Coverage

These PR #256 metric names are not emitted one-for-one in `metrics.json`, but
the current dataset and artifacts evaluate the same rollout risk through
stricter generated oracle checks or case-log trace inspection:

| PR #256 metric family | Current proxy/evidence |
| --- | --- |
| `compound_segment_coverage`, `compound_segment_overmerge_rate` | The generated records are multi-signal journeys with per-operation route, card, memory, related-fact, and ask expectations. Segment-level labels are collapsed into these deterministic expectations rather than emitted as a separate segment metric. |
| `record_question_preservation_rate` | Question-like records are included and checked through card expected text, memory expected text, and Quick Query judge tasks. |
| `reflection_action_false_positive_absence`, `temporary_state_personalization_absence`, `unconfirmed_action_creation_absence` | Covered by `memory_must_not_write_precision`, card `must_not_fields`, no write-tool/read-only checks, and comment boundary judge. |
| `long_term_preference_write_recall`, `memory_write_precision`, `memory_conflict_handling`, `memory_temporal_validity` | Covered by must-write/must-not, recall, source grounding, conflict/correction cases, and final active Memory atoms in case logs. |
| Relationship metrics such as `relationship_recall_at_10`, `relationship_temporal_accuracy`, `relationship_reasoning_error_rate` | Covered by relationship recall probes, related-fact expectations, Quick Query `ask_relationship_payment`, read-only tool traces, and focused judge closeout. |
| Long-context metrics such as `long_context_fact_recall_at_10`, `long_context_staleness_error_rate`, `coreference_resolution_accuracy` | Covered by long-context anchor records, old/new owner conflict asks, expected sources, and forbidden stale-owner assertions. |
| Retrieval ranking metrics beyond hit-rate (`retrieval_mrr`, `retrieval_ndcg_at_10`, precision/recall variants) | Top-k ranked sources are preserved in observations and case logs; the rollout gate uses `retrieval_hit_at_1/3/5/10` plus LLM grounding judge. |
| Citation metrics (`citation_precision`, `citation_recall`) | Current Quick Query answers expose evidence fact ids in `search_memory_primary` tool results and final fallback answers; exact citation precision/recall is preserved as trace evidence rather than a separate aggregate metric. |
| Chat/multi-turn/session metrics | The rollout dataset uses single-turn Quick Query asks with persisted chat sessions. Multi-turn context retention is not a Memory Primary switch gate yet. |
| Schedule/System Action exact payload metrics | Schedule tasks appear in task status totals, but the large dataset does not assert reminder/calendar payload gold. These metrics remain out of the Memory Primary switch gate. |
| Cost metrics in currency (`cost_per_input`, `cost_per_successful_input`) | The current artifacts use token counts and model usage (`tokens_per_input`, `tokens_by_agent`, `llm_usage_total`) because provider pricing is external and not stable enough for a reproducible local gate. |

### Case-Level Debug Artifacts

Each run writes:

- `llm_preflight.json`: provider/model readiness for all subscriptions that the
  selected case slots will use.
- `case_debug_index.md`: one-line index by mode and case.
- `case_logs/<mode>/<case_id>.json`: original case, expected labels,
  operation observations, task payload/result/error timeline, final cards,
  active Memory atoms, PKM snapshots, LLM token/cache stats, and failures.
- `evals/ITERATION_LOG.md`: short human-maintained record for case failures,
  root causes, fixes, verification runs, and residual risks.

## Candidate Gate

The runner emits `gate.json` and includes the same rules in `report.md`.
`MEMEX_EVAL_ENFORCE_GATE=1` makes the Flutter test fail if the candidate gate
does not pass.

Default candidate thresholds:

| Rule | Default |
| --- | ---: |
| `completed_card_rate` | >= 0.98 |
| `cards_with_insight_rate` | >= 0.95 |
| `memory_expected_hit_rate` | >= 0.70 |
| `memory_must_not_write_precision` | >= 0.95 |
| `card_expected_hit_rate` | >= 0.80 |
| `related_fact_hit_rate` | >= 0.60 |
| `memory_recall_hit_rate` | >= 0.70 |
| `memory_recall_must_not_precision` | >= 0.95 |
| `super_agent_answer_success_rate` | >= 0.95 |
| `super_agent_answer_hit_rate` | >= 0.95 |
| `super_agent_boundary_precision` | >= 0.95 |
| `task_settlement_rate` | >= 0.98 |
| `failed_task_count` | <= 0 |
| `task_not_settled_count` | <= 0 |
| `p95_record_elapsed_ms` | <= `MEMEX_EVAL_MAX_P95_RECORD_MS` |
| `memory_expected_hit_rate_delta` vs legacy | >= 0.15 |
| `related_fact_hit_rate_delta` vs legacy | >= 0.00 |
| `memory_recall_hit_rate_delta` vs legacy | >= 0.15 |

## Failure Attribution

Every failed rule-level expectation is also written to `failures.jsonl`.
Important categories include:

- `memory_expected_missing`
- `memory_forbidden_present`
- `memory_recall_missing`
- `memory_recall_forbidden_present`
- `related_fact_missing`
- `card_expected_missing`
- `card_missing`
- `card_incomplete`
- `task_not_settled`

The report aggregates these categories so the next iteration can distinguish
extract/write issues from recall, insight grounding, and operational stability.

Text expectations may be plain strings or an any-of group:

```json
{"label": "peanut allergy", "any_of": ["花生过敏", "allergic to peanuts", "peanut allergy"]}
```

Any-of groups keep rule scoring deterministic while avoiding false negatives
when agents preserve the same fact in Chinese or English.
