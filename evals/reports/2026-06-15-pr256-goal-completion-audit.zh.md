# PR256 Memory Primary 目标完成度审计

生成时间：2026-06-15

## 审计结论

本轮目标已经具备进入实验 feature 开关的证据闭环：同一套 8 persona / 每 persona 400 条输入 / 共 3200 条 record 的大样本下，新链路 `memory_primary` 通过 deterministic gate，老链路 `legacy_pkm` 失败；新链路后续发现的 Quick Query grounding 和 relationship badcase 已用同一批大样本 case log 复建 Memory 后完成 32 个 ask / 64 个 judge task closeout。

需要保留的边界是：并非 `memex-lab/memex#256` 文档里的每个原子指标都在 `metrics.json` 中一一同名产出。当前已经在 `evals/METRICS.md` 中把指标分成 `collected`、`case_log`、`proxy_or_trace`、`not_in_rollout_scope`，并在 `evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md` 中生成了 151 个 PR 指标的逐项覆盖矩阵。这足够支撑 Memory Primary 实验开关上线判断，但若后续要做“指标名完全一一对应”的平台化评估，还需要继续把部分 trace/proxy 指标固化成独立聚合项。

## 目标逐项状态

| 目标要求 | 状态 | 证据 |
| --- | --- | --- |
| 使用 PR #256 完整 Agent 指标 | 已覆盖上线门禁口径 | `docs/memex-evaluation-framework.md` 已同步到本 worktree；`evals/METRICS.md` 已按 direct/judge/proxy/out-of-scope 对齐。 |
| 针对性设计合成数据和评估方法 | 已完成 | `evals/datasets/pr256_full_metric_large_p8_r400/cases.jsonl`，8 persona，每 persona 400 record，覆盖 correction、relationship、long-context、noise、sensitive boundary、parsed OCR、preference、ask 等。 |
| 先小数据集迭代新链路 | 已完成 | `evals/ITERATION_LOG.md` 记录 small gate、supplemental judge、Quick Query badcase 和修复过程。 |
| 大数据集新旧链路对比 | 已完成 | legacy baseline 与 Memory Primary v12 都在同一数据集完成 3200 record 评估。 |
| 老链路保持线上不变 | 基线冻结 | 老链路 artifact 固定为 `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614`；后续修复只进入 Memory Primary / Quick Query / eval infra。 |
| 发现 badcase 后迭代新链路 | 已完成 | CardInsight fallback、provider scheduling、Quick Query grounding、relationship memory merge、fallback slotting 均有 case 触发和验证记录。 |
| 完整日志可回溯 | 已完成 | 每轮保留 `metrics.json`、`report.md`、`failures.jsonl`、`observations.jsonl`、`judge_results.jsonl`、case logs 和迭代日志。 |
| provider 并发与 quota 处理 | 已完成 | judge runner 支持所有配置 provider、priority、短 cooldown、min interval、retry；out-of-quota provider 从池中移除，短 429 provider 自动冷却后回池。 |

## 核心证据

| Artifact | 用途 | 关键结论 |
| --- | --- | --- |
| `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614` | 老链路大样本 baseline | `task_settlement_rate=0.808`，`failed_task_count=98`，`task_not_settled_count=615`，gate fail。 |
| `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615` | 新链路大样本 merged run | `task_settlement_rate=1.0`，`failed_task_count=0`，`memory_expected_hit_rate=1.0`，`super_agent_answer_hit_rate=1.0`，gate pass。 |
| `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615/judge/judge_metrics.json` | 原始 PR256 judge | `card_title_relevance_score=3198/3200`，`grounded_answer_rate=31/32`，`unsupported_claim_absence=26/32`；暴露 Quick Query grounding badcase。 |
| `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615/supplemental_judge/judge_metrics.json` | 补充 judge | insight/comment/PKM projection 指标基本通过；1 个 PKM raw bad 审计为 judge artifact。 |
| `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_with_latency_20260615` | Quick Query latency closeout | 复用同一批 8 persona case log 重放 32 ask，`failure_count=0`，并同名直出 `tool_call_latency_p95_by_tool.search_memory_primary.count=32`、`p95=0ms`。 |
| `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_after_relationship_type_fix_20260615` | Quick Query closeout judge source | 32 ask 全部 deterministic 通过，`retrieval_hit_at_10=1.0`，`failure_count=0`。 |
| `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_after_relationship_type_fix_20260615/judge/judge_metrics.json` | Quick Query closeout judge | `unsupported_claim_absence=32/32`，`grounded_answer_rate=32/32`，`error_count=0`。 |
| `evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615` | Trace metric smoke | 3 record LLM smoke 通过，`agent_empty_response_rate=0.0` 且 LLM turn 分母为 3；case log 同步导出 `agent_activity_trace`，并同名直出 `context_peek_redundancy_rate` 与 `first_write_after_read_rate`。 |
| `evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md` | PR256 指标逐项覆盖矩阵 | 151 个 metric 行：66 个 `metrics.json` 同名直出，8 个 judge 同名直出，1 个 top-k 展开直出，55 个 proxy/trace，21 个非本次门禁，0 个需新增 instrumentation。 |
| `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_with_pr256_instrumentation_20260615` | 新链路补充 instrumentation merge | 离线重聚合同一批 8 persona shard，gate 仍为 pass，并补出 `agent_finalization_rate`、`agent_llm_turns_per_task`、`agent_turn_budget_violation_rate`、`input_full_idle_latency_ms`、`task_queue_pressure_p95`、`tool_calls_per_input`。 |
| `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_with_pr256_instrumentation_20260615` | 老链路补充 instrumentation merge | 离线重聚合同一批 legacy shard，gate 仍为 fail；只补指标字段，不重跑或修改老链路。 |

## 指标覆盖说明

| 指标层 | 当前处理 |
| --- | --- |
| 直出指标 | card/materialization、memory write/recall/source、retrieval hit@k、Super Agent answer/tool/read-only、task settlement、latency、token、coverage 等直接写入 `metrics.json`。 |
| LLM judge 指标 | title relevance、grounded answer、unsupported claim、insight novelty/actionability、comment relevance/boundary、PKM coherence 已生成 judge task 并落盘。 |
| proxy/trace 指标 | relationship、long-context、question preservation、false positive、citation、ranking variants 等通过 generated oracle、case log、tool trace 或 focused judge 覆盖 rollout 风险。 |
| 非本次门禁指标 | 语音识别、产品 UI、schedule exact payload、多轮 chat、真实货币成本等不作为 Memory Primary 切换门禁。 |

## 老链路冻结证据

| 证据 | 说明 |
| --- | --- |
| `lib/domain/models/agent_pipeline_config.dart:21` | 默认配置仍为 `AgentPipelineMode.legacyPkm`；未知存储值也回退到 `legacyPkm`。 |
| `lib/data/repositories/memex_router.dart:337` | legacy 分支仍注册 `comment_agent` 依赖 `pkm_agent`；Memory Primary 的 `memory_primary_task` / `card_insight_task` 在 `runsMemoryPrimary` 分支中独立注册。 |
| `lib/data/services/chat_service.dart:126` | Quick Query 的 Memory Primary fallback/post-processing 只在 `pipelineConfig.runsMemoryPrimary && isQuickQuery` 时启用。 |
| `lib/agent/super_agent/super_agent.dart:62` | `search_memory_primary` 只在 `runsMemoryPrimary` 时挂载；legacy Quick Query 仍使用原 read-only tool set。 |
| `lib/data/services/task_handlers/card_agent_handler.dart:2491` | Card completion fallback/title guard 只在 `payload['pipeline_mode'] == 'memory_primary'` 时触发。 |

## Provider 策略

当前策略是区分两类任务：

1. 全链路 replay：单 persona 固定一个 provider，避免同一用户 journey 混用 provider cache；provider health 用 `MEMEX_EVAL_LLM_PROVIDER_PRIORITIES` 控制 shard 分配。
2. LLM-as-judge：judge task 无共享用户 workspace，因此使用所有可用 provider 并发，支持 `MEMEX_EVAL_JUDGE_PROVIDER_PRIORITIES`、短 cooldown、min request interval、retry failed/resume。最新 provider 可作为更高 priority 路由；明确 out-of-quota 的 provider 会在本次 judge pool 中禁用，短窗口 429 provider 保留并自动冷却后回池。

所有 artifact 中 API key 均只记录为 `<redacted>`。

## 上线判断

建议推进实验 feature 开关：

- 开关形态：`legacy_pkm` / `memory_primary` 二选一。
- 切换方式：切到 Memory Primary 后全量刷新数据，不做双轨兼容。
- PARA：作为可选 projection，可手动或定期触发，不再绑定每次输入。
- 灰度关注：task settlement、Quick Query unsupported claim、relationship recall、token/latency、provider quota。

当前没有阻塞 Memory Primary 实验开关的 #256 指标 blocker。`needs_new_gold_or_instrumentation` 已降为 0；剩余工作主要是把 `proxy_or_trace` 指标逐步产品化为可长期自动看板，而不是再阻塞本轮上线论证。

最后 3 个 instrumentation 指标的 closeout 边界：

| Metric | 缺口 | 当前处理 |
| --- | --- | --- |
| `agent_empty_response_rate` | 已补 LLM turn metadata。 | `LLMCallRecordService` 聚合 `empty_response_turns`；LLM smoke 中 `calls=3`、`empty_response_turns=0`、`agent_empty_response_rate=0.0`。 |
| `context_peek_redundancy_rate` | 已补 activity trace 聚合。 | case log 导出 `agent_activity_trace`；当前保守只把同一 agent 内完全重复 read/query 算冗余，不猜测“未被使用”。 |
| `first_write_after_read_rate` | 已补 file write 顺序聚合。 | 当前只把通用文件 `Write/Edit/Move/Remove` 纳入分母，不把 Memory Primary structured save/update 误判为需先读文件。 |
