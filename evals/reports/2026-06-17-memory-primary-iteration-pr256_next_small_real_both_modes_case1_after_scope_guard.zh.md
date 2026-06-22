# Memory Primary 新一轮评估报告

生成时间：2026-06-17T06:24:30.619775Z

## 摘要

| 项 | 值 |
| --- | --- |
| Run dir | `evals/runs/pr256_next_small_real_both_modes_case1_after_scope_guard_20260617` |
| Dataset | `-` |
| Modes | `legacy_pkm, memory_primary` |
| LLM enabled | `true` |
| Gate | `pass` |
| Artifact audit | `pass` |
| Judge tasks | `126` |
| Pairwise judge tasks | `6` |
| Failures | `47` |

说明：老链路保持 frozen baseline；新链路可迭代。召回策略采用 FTS + dense embedding 候选和 RRF 融合，向量贡献通过覆盖型指标记录，不依赖 case-by-case 启发式打分。

## 样本与旅程

| Mode | Cases | Records | Agent asks | Recall probes | Projection | Operation coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `legacy_pkm` | 1 | 48 | 6 | 3 | 1 | 1 |
| `memory_primary` | 1 | 48 | 6 | 3 | 1 | 1 |

## 核心指标

| 指标 | legacy_pkm | memory_primary | Delta |
| --- | ---: | ---: | ---: |
| Card completed | 1 | 1 | 0 |
| Card insight | 0.896 | 1 | 0.104 |
| Memory must-write hit | 0 | 1 | 1 |
| Memory must-not precision | 1 | 1 | 0 |
| Memory duplicate | 0 | 0 | 0 |
| Related fact hit | 0.783 | 1 | 0.217 |
| Memory recall hit | 0 | 1 | 1 |
| Agent answer hit | 0.941 | 1 | 0.059 |
| Agent boundary precision | 1 | 1 | 0 |
| Agent read-only | 1 | 1 | 0 |
| Agent route accuracy | 0.979 | 1 | 0.021 |
| Task settlement | 1 | 1 | 0 |
| Failed task count | 0 | 0 | - |
| Not-settled task count | 0 | 0 | - |
| P95 record latency ms | 79640 | 63789 | -15851 |
| Tokens/input | 9504.604 | 3081.417 | - |

## Agent 间歇问答

| 指标 | legacy_pkm | memory_primary |
| --- | ---: | ---: |
| Dataset ask count | 6 | 6 |
| Interleaved ask count | 6 | 6 |
| Interleaving rate | 1 | 1 |
| Asks / 100 records | 12.500 | 12.500 |
| Records / ask | 8 | 8 |
| Query family coverage | 0.600 | 0.600 |
| Min asks / case | 6 | 6 |
| P95 record gap | 9 | 9 |
| Agent ask count | 6 | 6 |
| Answer success | 1 | 1 |
| Answer hit | 0.941 | 1 |
| Boundary precision | 1 | 1 |
| Read-only compliance | 1 | 1 |
| Tool selection | 1 | 1 |
| Tool args | 1 | 1 |
| Tool minimality | 1 | 1 |
| Provider attempts | 6 | 6 |
| Provider retries | 0 | 0 |
| Provider retry rate | 0 | 0 |
| Pairwise mode wins | 1 | 4 |
| Pairwise match levels | strict:6 |  |

## Agent Query Family 明细

| Query family | legacy_pkm | memory_primary |
| --- | --- | --- |
| `location_routine` | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `partner_owner_disambiguation` | asks=1<br>hit=0.500<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `project_owner_current` | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `relationship_responsibility_split` | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `report_preference` | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.667<br>vec_only=0 |
| `role_mood_transition` | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |

## 召回与向量收益

| 指标 | Memory Primary |
| --- | ---: |
| Hit@1 | 0 |
| Hit@3 | 1 |
| Hit@5 | 1 |
| Hit@10 | 1 |
| Positive probes | 15 |
| FTS positive coverage | 0.933 |
| Vector positive coverage | 0.933 |
| Vector-only positive hit | 0 |
| FTS-only positive hit | 0 |
| Hybrid positive coverage | 0.933 |
| Vector lift@10 | 0 |
| Vector-supported query | 1 |
| Vector-only query | 0 |
| Positive source breakdown | both:14, fts_only:0, missed:1, vector_only:0 |

## LLM-as-Judge

| 项 | 值 |
| --- | --- |
| Model | `mimo-v2.5-pro` |
| Task count | `126` |
| Provider count | `23` |
| Disabled providers | `0` |
| Concurrency | `8` |

| Metric | Total | Pass rate | Avg score | Winner/match detail |
| --- | ---: | ---: | ---: | --- |
| `unsupported_claim_absence` | 12 | 1 | 1 | - |
| `card_title_relevance_score` | 96 | 0.802 | 0.845 | - |
| `grounded_answer_rate` | 12 | 0.917 | 0.925 | - |
| `pairwise_answer_quality` | 6 | 1 | 0.917 | wins=legacy_pkm:1, memory_primary:4, tie:1; match=strict:6 |

## Gate

| Rule | Actual | Required | Status |
| --- | ---: | ---: | --- |
| `completed_card_rate >= 0.98` | 1 | 0.980 | pass |
| `cards_with_insight_rate >= 0.95` | 1 | 0.950 | pass |
| `memory_expected_hit_rate >= 0.7` | 1 | 0.700 | pass |
| `memory_must_not_write_precision >= 0.95` | 1 | 0.950 | pass |
| `card_expected_hit_rate >= 0.8` | 1 | 0.800 | pass |
| `related_fact_hit_rate >= 0.6` | 1 | 0.600 | pass |
| `memory_recall_hit_rate >= 0.7` | 1 | 0.700 | pass |
| `memory_recall_must_not_precision >= 0.95` | 1 | 0.950 | pass |
| `super_agent_answer_success_rate >= 0.95` | 1 | 0.950 | pass |
| `super_agent_answer_hit_rate >= 0.95` | 1 | 0.950 | pass |
| `super_agent_boundary_precision >= 0.95` | 1 | 0.950 | pass |
| `task_settlement_rate >= 0.98` | 1 | 0.980 | pass |
| `failed_task_count <= 0` | 0 | 0 | pass |
| `task_not_settled_count <= 0` | 0 | 0 | pass |
| `p95_record_elapsed_ms <= 180000` | 63789 | 180000 | pass |
| `memory_expected_hit_rate_delta >= 0.15` | 1 | 0.150 | pass |
| `related_fact_hit_rate_delta >= 0.0` | 0.217 | 0 | pass |
| `memory_recall_hit_rate_delta >= 0.15` | 1 | 0.150 | pass |
| `agent_route_accuracy >= 0.95` | 1 | 0.950 | pass |
| `agent_route_miss_rate <= 0.05` | 0 | 0.050 | pass |
| `agent_route_overtrigger_rate <= 0.05` | 0 | 0.050 | pass |
| `card_template_primary_accuracy >= 0.8` | 1 | 0.800 | pass |
| `card_template_any_accuracy >= 0.9` | 1 | 0.900 | pass |
| `card_field_recall >= 0.95` | 1 | 0.950 | pass |
| `card_entity_recall >= 0.95` | 1 | 0.950 | pass |
| `card_time_parse_accuracy >= 0.95` | 1 | 0.950 | pass |
| `card_hallucinated_field_absence >= 0.95` | 1 | 0.950 | pass |
| `retrieval_hit_at_10 >= 0.7` | 1 | 0.700 | pass |
| `answer_must_include >= 0.95` | 1 | 0.950 | pass |
| `super_agent_read_only_compliance >= 0.95` | 1 | 0.950 | pass |
| `tool_selection_accuracy >= 0.95` | 1 | 0.950 | pass |
| `tool_args_accuracy >= 0.9` | 1 | 0.900 | pass |
| `tool_call_minimality >= 0.95` | 1 | 0.950 | pass |
| `tool_call_failure_rate <= 0.05` | 0 | 0.050 | pass |
| `repeated_tool_call_rate <= 0.1` | 0 | 0.100 | pass |
| `read_tool_error_rate <= 0.05` | 0 | 0.050 | pass |
| `write_tool_error_rate <= 0.05` | 0 | 0.050 | pass |
| `loop_detection_absence >= 1.0` | 1 | 1 | pass |
| `max_turns_absence >= 1.0` | 1 | 1 | pass |
| `scenario_family_coverage >= 1.0` | 1 | 1 | pass |
| `agent_chain_coverage >= 1.0` | 1 | 1 | pass |
| `journey_stage_coverage >= 1.0` | 1 | 1 | pass |
| `operation_type_coverage >= 1.0` | 1 | 1 | pass |
| `cross_day_continuity_coverage >= 1.0` | 1 | 1 | pass |
| `correction_operation_coverage >= 1.0` | 1 | 1 | pass |
| `noise_resilience_coverage >= 1.0` | 1 | 1 | pass |
| `follow_up_query_coverage >= 1.0` | 1 | 1 | pass |
| `relationship_case_coverage >= 1.0` | 1 | 1 | pass |
| `long_context_case_coverage >= 1.0` | 1 | 1 | pass |
| `dataset_oracle_consistency >= 1.0` | 1 | 1 | pass |

## Artifact Audit

| 项 | 值 |
| --- | --- |
| Status | `pass` |
| Findings | `0` |
| Errors | `0` |
| Warnings | `0` |

## Badcase 概览

| Category | legacy_pkm | memory_primary | Total |
| --- | ---: | ---: | ---: |
| `agent_route_missing` | 1 | 0 | 1 |
| `card_entity_missing` | 1 | 0 | 1 |
| `card_field_missing` | 19 | 0 | 19 |
| `memory_expected_missing` | 14 | 0 | 14 |
| `memory_recall_missing` | 6 | 0 | 6 |
| `related_fact_missing` | 5 | 0 | 5 |
| `super_agent_answer_missing` | 1 | 0 | 1 |

## Artifact 索引

- `metrics.json`: present
- `gate.json`: present
- `report.md`: present
- `failures.jsonl`: present
- `observations.jsonl`: present
- `judge_tasks.jsonl`: present
- `judge/judge_metrics.json`: present
- `judge/judge_results.jsonl`: present
- `badcases.md`: present
- `badcases.jsonl`: present
- `artifact_audit.json`: present
- `artifact_audit.md`: present
- `case_debug_index.md`: present

## 当前判断

- Gate 与 artifact audit 均通过，可以把本 run 作为本轮上线证据候选。
