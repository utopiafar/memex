# Agent Split Legacy vs Primary 三轮复评报告

日期：2026-05-23

## 结论

本轮结论：拆分旁路 `split_primary` 仍然值得保留为可切换产品开关，并可以进入更大样本 dogfood；不建议直接默认切给所有用户。

核心原因：

- 在同一评估模型的 R1/R2 中，Primary 从 88.4% 的 Legacy 基线提升到 95.5%，同时 token 降低 65.7%，LLM 调用降低 42.6%，工具调用降低 38.6%。
- R3 原评估 key 出现 `HTTP 429: quota exhausted`，已剥离为 infra 污染样本；用 OpenRouter fallback 做同轮相对比较时，Primary 91.7%，Legacy 78.7%，Primary 避开了 Legacy 的 PKM loopDetection。
- Primary 仍有残余问题：SuperAgent 对人名/owner 的答案召回不够稳，下游 schedule/insight agent 仍可能 stochastic loop。这些不阻塞继续旁路，但阻止默认全量切换。

## 方法更新

这轮重新审视后，把实验方法改成更接近真实用户旅程：

- Legacy 和 Primary 独立运行，同一批输入分别跑两条链路；不让两条链路共存写同一 workspace。
- Shadow 不计入本轮评分，只保留产品/调试层面的旁路可能性。
- v5 real replay 使用窗口内 oracle，只评估当前窗口可见事实，避免用完整 source case 泄漏未来事实。
- fake 数据扩大到 `full_chain_journey_scale_v4`：12 persona、7680 records、120 eval tasks；fixture score 为 1416/1416。
- real replay 扩展为 `full_chain_journey_real_replay_v5`：48 cases、768 records、1104 operations、288 eval tasks。
- 本轮最终 scored live run 覆盖 6 个 mode-run、192 个 record slot、72 个 eval tasks；另有被标注为 infra/diagnostic 的 rerun 不混入主表。

## 已修问题

1. 评估 oracle 过宽：v5 改成窗口 scoped evidence，`must_write`、`must_include`、card boundary 都只用当前窗口可见事实。
2. 关键词匹配脆弱：benchmark normalization 去掉 markdown punctuation，并把“长记忆/长期记忆”做等价处理。
3. SuperAgent Quick Query 证据优先级弱：现在把 `<user_memory_context>` 当作一等证据，要求保留 owner、reminder、preference、boundary 与精确阈值。
4. transient `HTTP 400 connection prematurely closed` 被误判为 non-retryable：现在归类为 networkError，让任务重试。
5. 429 限流重试太密：LocalTaskExecutor 对 429/rate limit/quota exhausted 使用 30/60/120/240/300 秒退避，普通错误仍保持 30 秒。
6. eval LLM provider 固定为 MIMO：新增 `EVAL_LLM_TYPE`，默认仍是 MIMO，但可显式切到 OpenRouter 做 fallback。
7. 项目 owner memory 召回弱：MemoryAgent 增加中文“和某人对齐/找某人补来源”的 durable routing 示例；diagnostic rerun 中 memory owner recall 从 0/2 提升到 2/2。

## 结果总表

| Round | Provider | Mode | Score | Failed/Loop | Tokens | LLM Calls | Tool Calls | Replay |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | MIMO | Legacy | 94/112, 83.9% | 1/0 | 212,769 | 195 | 1,044 | 34m29s |
| R1 | MIMO | Primary | 109/112, 97.3% | 0/0 | 87,081 | 136 | 756 | 40m21s |
| R2 | MIMO | Legacy | 104/112, 92.9% | 0/0 | 309,214 | 272 | 1,290 | 50m16s |
| R2 | MIMO | Primary | 105/112, 93.8% | 0/0 | 92,130 | 132 | 678 | 39m37s |
| R3 | OpenRouter fallback | Legacy | 85/108, 78.7% | 1/1 | 671,973 | 124 | 864 | 11m37s |
| R3 | OpenRouter fallback | Primary | 99/108, 91.7% | 0/0 | 583,766 | 109 | 696 | 9m42s |

R1/R2 是同 provider 的主结论；R3 是 fallback provider 下的相对对比，不和 R1/R2 求同源均值。

## 失败分析

R1 Legacy 的主要问题是 PKM task 非可恢复 400，导致 case 后续 tail operations 缺失；Primary 在同窗口完整收敛，但问答漏掉了“上午/下午不喝”等细节。

R2 Primary 第一次跑到 80.4%，根因是上游 transient transport error 被包装成 HTTP 400。修复后 rerun 到 93.8%，且 failed/loop 为 0。

R3 Legacy 在 fallback provider 下复现 PKM `loopDetection`，停在 `journey_real_replay_v5_09_c` 中段；Primary 同一输入完整跑过 tail ops。这个是支持“不要把新旁路做成另一个大 Agent”的直接证据。

R3 Primary 的 residual miss 主要是答案里漏 Ivan/Nora 这类 owner 人名。Memory prompt 修正后 diagnostic run 的 memory owner recall 已经到 2/2，但该次 run 的 schedule aggregator 又触发 max-turn guard，所以不替换主表，只作为修复证据。

## 产品判断

保留产品开关是必要的：Primary 当前在稳定性和成本上明显更好，但下游 schedule/insight 与 SuperAgent 召回还有随机性，直接默认切会把少量用户推到不可解释状态。

建议默认策略：

- 默认仍保持 Legacy。
- Debug/Dogfood 开关提供 `legacy_pkm` 和 `split_primary` 二选一。
- 打开 Primary 时记录 mode、failed task、loop/max-turn、memory write recall、SuperAgent answer miss、token/tool cost。
- 切换不是 Shadow 合并，而是独立链路选择；Shadow 只用于离线诊断，不进入本轮产品主路径。

## 下一步

1. 给 schedule aggregator 增加 recoverable loop 清理或 skip 策略，避免它污染 memory/card 主对比。
2. 将 owner/routing memory 再扩成结构化 atom 类型，例如 `project_context`，但不要做复杂 key-value 覆盖；继续把新旧证据交给模型判断。
3. 跑 v5 全 48 cases 的分层批处理，按 provider 分层聚合，不混算 fallback。
4. 增加 semantic judge，降低“公司付款不能和家庭账单合并统计”这类同义表达的硬字符串误伤。
5. 对 Primary 做 3 次重复 run 稳定性评估，单独量化 stochastic variance。

## 验证

- `full_chain_journey_scale_v4` generated: 12 users, 7680 records, 120 tasks。
- `full_chain_journey_real_replay_v5` generated: 48 cases, 768 records, 1104 operations, 288 tasks。
- v4 fixture benchmark: 1416/1416 passed。
- Focused Flutter tests: 34/34 passed。
- LocalTaskExecutor/LLM error tests after rate-limit fix: 15/15 passed。
- `git diff --check`: passed。
- secret scan over `lib test evals/experiments evals/bin evals/replay` excluding `evals/runs`: no hits。
- `flutter analyze --no-pub`: exits 1 due existing 324 info-level lints; no warning/error remains from this work.
