# Memory Primary 新一轮评估报告

生成时间：2026-06-17T14:13:23.594287Z

## 摘要

| 项 | 值 |
| --- | --- |
| Run dir | `evals/runs/pr256_shape_provider_infra_metrics_20260617` |
| Dataset | `-` |
| Modes | `legacy_pkm, memory_primary` |
| LLM enabled | `false` |
| Gate | `fail` |
| Artifact audit | `missing` |
| Judge tasks | `126` |
| Pairwise judge tasks | `6` |
| Failures | `135` |

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
| Card insight | 0 | 1 | 1 |
| Memory must-write hit | 0 | 0 | 0 |
| Memory must-not precision | 1 | 1 | 0 |
| Memory duplicate | 0 | 0 | 0 |
| Related fact hit | 0 | 1 | 1 |
| Memory recall hit | 0 | 0 | 0 |
| Agent answer hit | 0 | 0 | 0 |
| Agent boundary precision | 1 | 1 | 0 |
| Agent read-only | 1 | 1 | 0 |
| Agent route accuracy | 1 | 1 | 0 |
| Task settlement | 1 | 1 | 0 |
| Failed task count | 0 | 0 | - |
| Provider infra task errors | 0 | 0 | - |
| Provider-contaminated op rate | 0 | 0 | - |
| Not-settled task count | 0 | 0 | - |
| P95 record latency ms | 1559 | 1563 | 4 |
| Tokens/input | 0 | 0 | - |

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
| Answer success | 0 | 0 |
| Answer hit | 0 | 0 |
| Boundary precision | 1 | 1 |
| Read-only compliance | 1 | 1 |
| Tool selection | 1 | 0 |
| Tool args | 1 | 0 |
| Tool minimality | 1 | 1 |
| Provider attempts | 0 | 0 |
| Provider retries | 0 | 0 |
| Provider retry rate | 0 | 0 |

## Agent Query Family 明细

| Query family | legacy_pkm | memory_primary |
| --- | --- | --- |
| `location_routine` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |
| `partner_owner_disambiguation` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |
| `project_owner_current` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |
| `relationship_responsibility_split` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |
| `report_preference` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |
| `role_mood_transition` | asks=1<br>hit=0<br>boundary=1<br>r10=1<br>vec=0<br>vec_only=0 | asks=1<br>hit=0<br>boundary=1<br>r10=0<br>vec=0<br>vec_only=0 |

## 召回与向量收益

| 指标 | Memory Primary |
| --- | ---: |
| Hit@1 | 0 |
| Hit@3 | 0 |
| Hit@5 | 0 |
| Hit@10 | 0 |
| Positive probes | 15 |
| FTS positive coverage | 0 |
| Vector positive coverage | 0 |
| Vector-only positive hit | 0 |
| FTS-only positive hit | 0 |
| Hybrid positive coverage | 0 |
| Vector lift@10 | 0 |
| Vector-supported query | 0 |
| Vector-only query | 0 |
| Positive source breakdown | both:0, fts_only:0, missed:15, vector_only:0 |

## LLM-as-Judge

本 run 尚未发现 `judge/judge_metrics.json`，真实 small/scale 收口时需要补跑 judge。

## Gate

| Rule | Actual | Required | Status |
| --- | ---: | ---: | --- |
| `completed_card_rate >= 0.98` | 1 | 0.980 | pass |
| `cards_with_insight_rate >= 0.95` | 1 | 0.950 | pass |
| `memory_expected_hit_rate >= 0.7` | 0 | 0.700 | fail |
| `memory_must_not_write_precision >= 0.95` | 1 | 0.950 | pass |
| `card_expected_hit_rate >= 0.8` | 1 | 0.800 | pass |
| `related_fact_hit_rate >= 0.6` | 1 | 0.600 | pass |
| `memory_recall_hit_rate >= 0.7` | 0 | 0.700 | fail |
| `memory_recall_must_not_precision >= 0.95` | 1 | 0.950 | pass |
| `super_agent_answer_success_rate >= 0.95` | 0 | 0.950 | fail |
| `super_agent_answer_hit_rate >= 0.95` | 0 | 0.950 | fail |
| `super_agent_boundary_precision >= 0.95` | 1 | 0.950 | pass |
| `task_settlement_rate >= 0.98` | 1 | 0.980 | pass |
| `failed_task_count <= 0` | 0 | 0 | pass |
| `task_not_settled_count <= 0` | 0 | 0 | pass |
| `p95_record_elapsed_ms <= 20000` | 1563 | 20000 | pass |
| `memory_expected_hit_rate_delta >= 0.15` | 0 | 0.150 | fail |
| `related_fact_hit_rate_delta >= 0.0` | 1 | 0 | pass |
| `memory_recall_hit_rate_delta >= 0.15` | 0 | 0.150 | fail |

Failed rules: `memory_expected_hit_rate >= 0.7`, `memory_recall_hit_rate >= 0.7`, `super_agent_answer_success_rate >= 0.95`, `super_agent_answer_hit_rate >= 0.95`, `memory_expected_hit_rate_delta >= 0.15`, `memory_recall_hit_rate_delta >= 0.15`

## Artifact Audit

未找到 `artifact_audit.json`。真实证据收口需要补跑 audit。

## Badcase 概览

| Category | legacy_pkm | memory_primary | Total |
| --- | ---: | ---: | ---: |
| `memory_expected_missing` | 14 | 14 | 28 |
| `memory_recall_missing` | 6 | 6 | 12 |
| `related_fact_missing` | 23 | 0 | 23 |
| `retrieval_hit_missing` | 0 | 6 | 6 |
| `super_agent_answer_missing` | 17 | 17 | 34 |
| `super_agent_ask_error` | 6 | 6 | 12 |
| `tool_args_mismatch` | 0 | 14 | 14 |
| `tool_selection_missing` | 0 | 6 | 6 |

## Artifact 索引

- `metrics.json`: present
- `gate.json`: present
- `report.md`: present
- `failures.jsonl`: present
- `observations.jsonl`: present
- `judge_tasks.jsonl`: present
- `judge/judge_metrics.json`: missing
- `judge/judge_results.jsonl`: missing
- `badcases.md`: missing
- `badcases.jsonl`: missing
- `artifact_audit.json`: missing
- `artifact_audit.md`: missing
- `case_debug_index.md`: present

## 当前判断

- 本 run 还不能作为最终上线证据，需要先处理 gate/audit 中的失败项。
- 向量召回暂未覆盖正样本，需要检查 embedding provider、query 构造或 chunk 表达。
