# Memory Primary 新一轮评估报告

生成时间：2026-06-22T00:43:36.233883Z

## 摘要

| 项 | 值 |
| --- | --- |
| Run dir | `evals/runs/pr256_next_scale_p12_r600_q50_both_modes_after_pool_prune5_c1_20260620_merged` |
| Dataset | `evals/datasets/pr256_full_metric_large_p12_r600_q50/cases.jsonl` |
| Modes | `legacy_pkm, memory_primary` |
| LLM enabled | `true` |
| Gate | `pass` |
| Artifact audit | `pass` |
| Judge tasks | `17400` |
| Pairwise judge tasks | `600` |
| Failures | `8352` |

说明：老链路保持 frozen baseline；新链路可迭代。召回策略采用 FTS + dense embedding 候选和 RRF 融合，向量贡献通过覆盖型指标记录，不依赖 case-by-case 启发式打分。

## 样本与旅程

| Mode | Cases | Records | Agent asks | Recall probes | Projection | Operation coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `legacy_pkm` | 12 | 7200 | 600 | 36 | 12 | 1 |
| `memory_primary` | 12 | 7200 | 600 | 36 | 12 | 1 |

## 核心指标

| 指标 | legacy_pkm | memory_primary | Delta |
| --- | ---: | ---: | ---: |
| Card completed | 1 | 1 | 0 |
| Card insight | 0.871 | 1 | 0.129 |
| Memory must-write hit | 0 | 1 | 1 |
| Memory must-not precision | 1 | 1 | 0 |
| Memory duplicate | 0 | 0.013 | 0.013 |
| Related fact hit | 0.116 | 0.825 | 0.709 |
| Memory recall hit | 0 | 0.986 | 0.986 |
| Agent answer hit | 0.818 | 0.992 | 0.174 |
| Agent boundary precision | 0.953 | 1 | 0.047 |
| Agent read-only | 0.990 | 1 | 0.010 |
| Agent route accuracy | 1 | 1 | 0 |
| Task settlement | 0.998 | 1 | 0.002 |
| Failed task count | 0 | 0 | - |
| Provider infra task errors | 0 | 0 | - |
| Provider-contaminated op rate | 0 | 0 | 0 |
| Not-settled task count | 11 | 0 | - |
| P95 record latency ms | 91045 | 60441 | -30604 |
| Tokens/input | 19464.672 | 3276.333 | - |

## Agent 间歇问答

| 指标 | legacy_pkm | memory_primary |
| --- | ---: | ---: |
| Dataset ask count | 600 | 600 |
| Interleaved ask count | 600 | 600 |
| Interleaving rate | 1 | 1 |
| Asks / 100 records | 8.333 | 8.333 |
| Records / ask | 12 | 12 |
| Query family coverage | 1 | 1 |
| Min asks / case | 50 | 50 |
| P95 record gap | 13 | 13 |
| Agent ask count | 600 | 600 |
| Answer success | 1 | 1 |
| Answer hit | 0.818 | 0.992 |
| Boundary precision | 0.953 | 1 |
| Read-only compliance | 0.990 | 1 |
| Tool selection | 1 | 1 |
| Tool args | 1 | 0.917 |
| Tool minimality | 0.988 | 1 |
| Provider attempts | 600 | 600 |
| Provider retries | 0 | 0 |
| Provider retry rate | 0 | 0 |
| Pairwise mode wins | 68 | 531 |
| Pairwise match levels | loose:72, partial:4, strict:524 |  |

## Agent Query Family 明细

| Query family | legacy_pkm | memory_primary |
| --- | --- | --- |
| `failure_recovery_alignment` | asks=60<br>hit=0.992<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.770<br>vec_only=0 |
| `location_routine` | asks=60<br>hit=0.989<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `ocr_conflict_grounding` | asks=60<br>hit=0.704<br>boundary=0.467<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.749<br>vec_only=0 |
| `owner_only_scope` | asks=60<br>hit=0.583<br>boundary=0.983<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.323<br>vec_only=0 |
| `partner_owner_disambiguation` | asks=60<br>hit=0.983<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=0.983<br>boundary=1<br>r10=0.817<br>vec=0.324<br>vec_only=0 |
| `project_owner_current` | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.353<br>vec_only=0 |
| `relationship_responsibility_split` | asks=60<br>hit=0.992<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=0.975<br>boundary=1<br>r10=0.950<br>vec=0.634<br>vec_only=0 |
| `report_preference` | asks=60<br>hit=0.917<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.887<br>vec_only=0 |
| `role_mood_transition` | asks=60<br>hit=0.822<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=1<br>boundary=1<br>r10=1<br>vec=0.819<br>vec_only=0 |
| `sensitive_boundary` | asks=60<br>hit=0.075<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=60<br>hit=0.933<br>boundary=1<br>r10=1<br>vec=0.817<br>vec_only=0 |

## 召回与向量收益

| 指标 | Memory Primary |
| --- | ---: |
| Hit@1 | 0 |
| Hit@3 | 0.947 |
| Hit@5 | 0.965 |
| Hit@10 | 0.977 |
| Positive probes | 16560 |
| FTS positive coverage | 0.640 |
| Vector positive coverage | 0.638 |
| Vector-only positive hit | 0 |
| FTS-only positive hit | 0.001 |
| Hybrid positive coverage | 0.641 |
| Vector lift@10 | 0.001 |
| Vector-supported query | 0.997 |
| Vector-only query | 0 |
| Positive source breakdown | both:10573, fts_only:24, missed:5963, vector_only:0 |

## LLM-as-Judge

| 项 | 值 |
| --- | --- |
| Model | `mimo-v2.5-pro` |
| Task count | `17400` |
| Provider count | `21` |
| Disabled providers | `0` |
| Concurrency | `21` |

| Metric | Total | Pass rate | Avg score | Winner/match detail |
| --- | ---: | ---: | ---: | --- |
| `unsupported_claim_absence` | 1200 | 0.882 | 0.891 | - |
| `card_title_relevance_score` | 14400 | 0.828 | 0.858 | - |
| `grounded_answer_rate` | 1200 | 0.866 | 0.877 | - |
| `pairwise_answer_quality` | 600 | 1 | 0.902 | wins=legacy_pkm:68, memory_primary:531, tie:1; match=loose:72, partial:4, strict:524 |

## Gate

| Rule | Actual | Required | Status |
| --- | ---: | ---: | --- |
| `completed_card_rate >= 0.98` | 1 | 0.980 | pass |
| `cards_with_insight_rate >= 0.95` | 1 | 0.950 | pass |
| `memory_expected_hit_rate >= 0.7` | 1 | 0.700 | pass |
| `memory_must_not_write_precision >= 0.95` | 1 | 0.950 | pass |
| `card_expected_hit_rate >= 0.8` | 1 | 0.800 | pass |
| `related_fact_hit_rate >= 0.6` | 0.825 | 0.600 | pass |
| `memory_recall_hit_rate >= 0.7` | 0.986 | 0.700 | pass |
| `memory_recall_must_not_precision >= 0.95` | 1 | 0.950 | pass |
| `super_agent_answer_success_rate >= 0.95` | 1 | 0.950 | pass |
| `super_agent_answer_hit_rate >= 0.95` | 0.992 | 0.950 | pass |
| `super_agent_boundary_precision >= 0.95` | 1 | 0.950 | pass |
| `task_settlement_rate >= 0.98` | 1 | 0.980 | pass |
| `failed_task_count <= 0` | 0 | 0 | pass |
| `task_not_settled_count <= 0` | 0 | 0 | pass |
| `p95_record_elapsed_ms <= 180000` | 60441 | 180000 | pass |
| `memory_expected_hit_rate_delta >= 0.15` | 1 | 0.150 | pass |
| `related_fact_hit_rate_delta >= 0.0` | 0.709 | 0 | pass |
| `memory_recall_hit_rate_delta >= 0.15` | 0.986 | 0.150 | pass |

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
| `card_entity_missing` | 158 | 0 | 158 |
| `card_field_missing` | 3629 | 0 | 3629 |
| `card_hallucinated_field_present` | 26 | 0 | 26 |
| `card_incomplete` | 1 | 0 | 1 |
| `card_time_parse_mismatch` | 7 | 1 | 8 |
| `memory_expected_missing` | 168 | 0 | 168 |
| `memory_recall_missing` | 72 | 1 | 73 |
| `related_fact_missing` | 3171 | 628 | 3799 |
| `retrieval_hit_missing` | 0 | 14 | 14 |
| `super_agent_answer_missing` | 295 | 13 | 308 |
| `super_agent_forbidden_present` | 34 | 0 | 34 |
| `super_agent_read_only_violation` | 6 | 0 | 6 |
| `task_not_settled` | 11 | 0 | 11 |
| `tool_args_mismatch` | 0 | 110 | 110 |
| `tool_call_minimality_violation` | 7 | 0 | 7 |

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
