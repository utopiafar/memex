# Memory Primary 新一轮评估报告

生成时间：2026-06-17T18:32:20.781324Z

## 摘要

| 项 | 值 |
| --- | --- |
| Run dir | `evals/runs/pr256_next_small_real_merged_p3_mp_after_query_scope_payment_fix_20260618` |
| Dataset | `evals/datasets/pr256_full_metric_small/cases.jsonl` |
| Modes | `memory_primary` |
| LLM enabled | `true` |
| Gate | `pass` |
| Artifact audit | `pass` |
| Judge tasks | `180` |
| Pairwise judge tasks | `0` |
| Failures | `0` |

说明：老链路保持 frozen baseline；新链路可迭代。召回策略采用 FTS + dense embedding 候选和 RRF 融合，向量贡献通过覆盖型指标记录，不依赖 case-by-case 启发式打分。

## 样本与旅程

| Mode | Cases | Records | Agent asks | Recall probes | Projection | Operation coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `memory_primary` | 3 | 144 | 18 | 9 | 3 | 1 |

## 核心指标

| 指标 | memory_primary | Delta |
| --- | ---: | ---: |
| Card completed | 1 | - |
| Card insight | 1 | - |
| Memory must-write hit | 1 | - |
| Memory must-not precision | 1 | - |
| Memory duplicate | 0 | - |
| Related fact hit | 1 | - |
| Memory recall hit | 1 | - |
| Agent answer hit | 1 | - |
| Agent boundary precision | 1 | - |
| Agent read-only | 1 | - |
| Agent route accuracy | 1 | - |
| Task settlement | 1 | - |
| Failed task count | 0 | - |
| Provider infra task errors | 0 | - |
| Provider-contaminated op rate | 0 | - |
| Not-settled task count | 0 | - |
| P95 record latency ms | 61792 | - |
| Tokens/input | 2939.535 | - |

## Agent 间歇问答

| 指标 | memory_primary |
| --- | ---: |
| Dataset ask count | 18 |
| Interleaved ask count | 18 |
| Interleaving rate | 1 |
| Asks / 100 records | 12.500 |
| Records / ask | 8 |
| Query family coverage | 0.600 |
| Min asks / case | 6 |
| P95 record gap | 9 |
| Agent ask count | 18 |
| Answer success | 1 |
| Answer hit | 1 |
| Boundary precision | 1 |
| Read-only compliance | 1 |
| Tool selection | 1 |
| Tool args | 1 |
| Tool minimality | 1 |
| Provider attempts | 18 |
| Provider retries | 0 |
| Provider retry rate | 0 |

## Agent Query Family 明细

| Query family | memory_primary |
| --- | --- |
| `location_routine` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `partner_owner_disambiguation` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `project_owner_current` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `relationship_responsibility_split` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `report_preference` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |
| `role_mood_transition` | asks=3<br>hit=1<br>boundary=1<br>r10=1<br>vec=1<br>vec_only=0 |

## 召回与向量收益

| 指标 | Memory Primary |
| --- | ---: |
| Hit@1 | 0 |
| Hit@3 | 1 |
| Hit@5 | 1 |
| Hit@10 | 1 |
| Positive probes | 45 |
| FTS positive coverage | 1 |
| Vector positive coverage | 1 |
| Vector-only positive hit | 0 |
| FTS-only positive hit | 0 |
| Hybrid positive coverage | 1 |
| Vector lift@10 | 0 |
| Vector-supported query | 1 |
| Vector-only query | 0 |
| Positive source breakdown | both:45, fts_only:0, missed:0, vector_only:0 |

## LLM-as-Judge

| 项 | 值 |
| --- | --- |
| Model | `mimo-v2.5-pro` |
| Task count | `180` |
| Provider count | `23` |
| Disabled providers | `0` |
| Concurrency | `12` |

| Metric | Total | Pass rate | Avg score | Winner/match detail |
| --- | ---: | ---: | ---: | --- |
| `card_title_relevance_score` | 144 | 1 | 1 | - |
| `unsupported_claim_absence` | 18 | 1 | 1 | - |
| `grounded_answer_rate` | 18 | 1 | 1 | - |

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
| `p95_record_elapsed_ms <= 180000` | 61792 | 180000 | pass |

## Artifact Audit

| 项 | 值 |
| --- | --- |
| Status | `pass` |
| Findings | `0` |
| Errors | `0` |
| Warnings | `0` |

## Badcase 概览

当前 `failures.jsonl` 为空。

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
