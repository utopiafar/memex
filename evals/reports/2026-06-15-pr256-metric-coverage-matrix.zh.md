# PR256 指标覆盖矩阵

生成时间：2026-06-16T03:28:22.343627Z

指标源：`docs/memex-evaluation-framework.md`。本文件只抽取 PR #256 指标详情表格第一列的 metric 名称，不把统计方式或数据源字段算作 metric。

## 覆盖状态汇总

| 状态 | 数量 | 含义 |
| --- | ---: | --- |
| `direct_metrics_json` | 66 | 当前 replay/closeout 的 `metrics.json` 已同名直出。 |
| `direct_judge` | 8 | 当前 judge artifact 已同名直出。 |
| `expanded_direct_metrics_json` | 1 | PR 文档合并写法已拆成多个 top-k 指标直出。 |
| `proxy_or_trace` | 55 | 当前数据集和日志覆盖同类风险，但不是同名聚合指标。 |
| `not_in_memory_primary_switch_gate` | 21 | 属于 PR256 Agent 大框架，但不作为 Memory Primary 新旧链路切换门禁。 |
| `needs_new_gold_or_instrumentation` | 0 | 需要新增 gold、trace 或聚合器才能稳定评估。 |

## 审计结论

- 当前证据足以支撑 Memory Primary 实验开关：核心写入、召回、卡片、Super Agent、工具轨迹、稳定性、延迟、token 与 LLM judge 指标已有大样本新旧对比。
- 严格按 PR #256 的每个原子 metric 名称看，当前已没有 `needs_new_gold_or_instrumentation` 项；仍有一批指标以 proxy/trace、focused judge 或非本次门禁方式覆盖。
- 因此，本矩阵用于区分“上线门禁已覆盖的风险”和“后续平台化评估仍需补齐的原子指标”。

## Artifact

| 类型 | 路径 |
| --- | --- |
| PR #256 指标源 | `docs/memex-evaluation-framework.md` |
| Legacy baseline metrics | `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_with_pr256_instrumentation_20260615` |
| Memory Primary v12 metrics | `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_with_pr256_instrumentation_20260615` |
| Legacy judge | `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614/judge/judge_metrics.json` |
| Memory Primary judge | `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615/judge/judge_metrics.json` |
| Quick Query closeout | `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_with_latency_20260615` |
| Trace metric smoke | `evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615` |

## 指标逐项矩阵

| Metric | 状态 | 证据/处理方式 |
| --- | --- | --- |
| `abstention_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `action_extraction_precision` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `action_extraction_recall` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `agent_chain_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_empty_response_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_finalization_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_llm_turns_per_task` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_response_cache_hit_rate` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `agent_response_cache_miss_reason_mix` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `agent_route_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_route_miss_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_route_overtrigger_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_tool_rounds_per_task` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `agent_turn_budget_violation_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `answer_must_include` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_cache_fts_freshness` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `card_completed_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_entity_recall` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_field_precision` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `card_field_recall` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_hallucinated_field_absence` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_materialization_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_schema_valid_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_source_fact_grounding_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_template_any_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_template_primary_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_time_parse_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `card_title_relevance_score` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `character_routing_accuracy` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `chat_recall_source_coverage` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `chat_session_persistence_rate` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `citation_precision` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `citation_recall` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `comment_boundary_safety` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `comment_not_fact_leakage_absence` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `comment_relevance_score` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `completed_with_failure_reason_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `completion_tokens_by_agent` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `compound_segment_coverage` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `compound_segment_overmerge_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `context_peek_count_per_task` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `context_peek_redundancy_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `coreference_resolution_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `correction_operation_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `cost_per_input` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `cost_per_successful_input` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `cross_day_continuity_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `dataset_oracle_consistency` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `due_time_exact_match` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `duplicate_insight_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `end_to_end_task_success_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `failed_task_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `final_state_match_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `first_write_after_read_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `follow_up_query_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `freshness_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `grounded_answer_rate` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `input_full_idle_latency_ms` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `input_required_chain_latency_ms` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `input_timeout_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `input_to_valid_card_success_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `insight_actionability_score` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `insight_generation_success_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `insight_grounding_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `insight_novelty_score` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `insight_parse_valid_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `insight_refresh_idempotence` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `insight_source_coverage` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `long_context_case_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `long_context_conversation_recall_at_10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `long_context_fact_recall_at_10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `long_context_staleness_error_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `long_term_preference_write_recall` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `loop_detection_absence` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `max_turns_absence` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_conflict_handling` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `memory_duplicate_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_must_not_write_precision` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_must_write_recall` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_recall_at_10` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_source_grounding` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `memory_temporal_validity` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `memory_write_precision` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `multi_turn_context_retention` | `not_in_memory_primary_switch_gate` | 该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。 |
| `noise_resilience_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `personalization_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_append_coherence` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `pkm_clarification_completion_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_completion_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_content_preservation` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_loop_detection_absence` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_merge_split_quality` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_no_overwrite_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_noop_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_path_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_read_before_write_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_redundant_tool_call_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `pkm_source_grounding` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `project_self_test_traceability` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `prompt_cache_token_hit_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `prompt_cache_token_hit_rate_by_agent` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `prompt_tokens_by_agent` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `read_tool_error_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `record_question_preservation_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `reflection_action_false_positive_absence` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `relationship_case_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `relationship_entity_resolution_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `relationship_precision_at_10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `relationship_reasoning_error_rate` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `relationship_recall_at_10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `relationship_temporal_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `repeated_tool_call_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `retrieval_filter_accuracy` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `retrieval_hit_at_1/3/5/10` | `expanded_direct_metrics_json` | PR 文档用合并写法；当前 artifact 以 `retrieval_hit_at_1`, `retrieval_hit_at_3`, `retrieval_hit_at_5`, `retrieval_hit_at_10` 分列直出。 |
| `retrieval_mrr` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `retrieval_ndcg_at_10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `retrieval_precision_at_1/3/5/10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `retrieval_recall_at_5/10` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `retry_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `scenario_family_coverage` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `schedule_aggregation_settlement_rate` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_refresh_action_accuracy` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_refresh_duplicate_rate` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_refresh_missed_absence` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_refresh_unnecessary_absence` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_time_parse_accuracy` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `schedule_update_cancel_accuracy` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `sensitive_domain_boundary_compliance` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `super_agent_read_only_compliance` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `system_action_creation_accuracy` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `system_action_user_choice_respect` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `task_completion_status` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `task_queue_pressure_p95` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `temporary_state_personalization_absence` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `thought_tokens_by_agent` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tokens_by_agent` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tokens_per_input` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tokens_per_successful_input` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_args_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_call_failure_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_call_latency_p95_by_tool` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_call_minimality` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_call_retry_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_calls_per_input` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `tool_selection_accuracy` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
| `trajectory_efficiency_score` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `trajectory_rule_compliance` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `uncertainty_calibration` | `proxy_or_trace` | 本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。 |
| `unconfirmed_action_creation_absence` | `not_in_memory_primary_switch_gate` | Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。 |
| `unsupported_claim_absence` | `direct_judge` | 在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。 |
| `write_tool_error_rate` | `direct_metrics_json` | 在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。 |
