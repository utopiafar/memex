# Memex Agent Eval 实验报告

## 结论

- 真实链路整体通过，适合作为当前 replay 基线。
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为。
- 本次覆盖 1 个 case、3 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：59825；LLM 调用次数：58；工具调用次数：177。
- LLM Judge 断言数：1。
- 数据质量审计通过：overall=0.900。
- 审计摘要：数据质量高，但 dataset_summary 显示仅有一个 case，需扩大规模以验证全面覆盖和多样性
- Replay 实测耗时：7分47秒；Benchmark 评分耗时：52秒。
- 人工复核备注：`full_chain_realistic_smoke` 数据集完整规模是 2 个 persona、13 条 record、24 个 App 操作。本轮按 `MEMEX_EVAL_CASE_LIMIT=1` 先跑通首个 persona 的真实链路；下一轮应跑完整 2 case，再扩到 6-12 persona。
- 运行环境备注：本地 `ws_proxy/wss_proxy/http_proxy/https_proxy` 会破坏 `flutter_tester` WebSocket 握手；真实 replay 使用 `env -u ws_proxy -u wss_proxy -u http_proxy -u https_proxy ... flutter test --no-pub ...` 跑通。模型 key 只通过环境变量注入，未写入报告或数据集。

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_realistic_smoke`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 1 |
| 用户输入 | 6 |
| Eval task | 3 |
| 断言 | 24 |
| LLM 调用 | 58 |
| LLM Judge 断言 | 1 |
| Tool 调用 | 177 |
| 实际 token | 59825 |
| Replay 实测耗时 | 7分47秒 |
| Benchmark 评分耗时 | 52秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 59825 tokens；同规模复跑可先按 47860-71790 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| Super Agent 问答 | 检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 是否执行了预期 App 行为类型，例如记录、回看、评论、刷新和问答。 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 平均每条用户输入消耗的 token 是否在预算内。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | Trace 是否包含期望的关键事件或工具调用节点。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | trace 和操作记录是否覆盖本轮预期功能触发点。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 模拟用户操作是否跨越足够多天，避免只测单日短上下文。 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 全链路 replay 中真实提交记录的数量是否达到本轮样本要求。 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 任务失败比例是否低于预算。 |
| 成本 / Trace | 稳定性 | `retry_rate` | 任务 retry 比例是否低于预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 输入是否覆盖文本、语音转写、OCR/剪贴等不同真实来源形态。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | LLM judge 给出的 groundedness/completeness 综合分。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | 14 | 14 | 100.0% | 0.993 |
| 记忆写入 | 4 | 4 | 100.0% | 1.000 |
| Super Agent 问答 | 6 | 6 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 1 | 1 | 100.0% | - |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 1 | 1 | 100.0% | 0.960 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 1 | 1 | 100.0% | 0.970 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 1 | 1 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 1 | 1 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 1 | 1 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | 1 | 1 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 1 | 1 | 100.0% | - |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 1 | 1 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 1 | 1 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：58
- 工具调用次数：177
- Token 总量：59825
- 单次 LLM 平均 token：1031.466
- 平均延迟：7590.411 ms
- P95 延迟：53000.000 ms
- Replay 实测耗时：7分47秒
- Case 观察耗时累计：7分47秒
- Benchmark 评分耗时：52秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-16-realistic-full-chain-smoke`
- 数据集：`evals/datasets/full_chain_realistic_smoke`
- 观察适配器：`replay_file`
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为
- 本地完整日志：`evals/runs/2026-05-16-realistic-full-chain-smoke/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-16-realistic-full-chain-smoke/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-16-realistic-full-chain-smoke/outputs.jsonl`
- 场景样本数：1
- 评估任务数：3
- Replay 实测耗时：7分47秒
- Benchmark 评分耗时：52秒
- 断言通过：24/24 （100.0%）
- LLM Judge：`anthropic` / `mimo-v2-pro` / max_tokens=4096
- LLM Judge 任务策略：`retrieval_and_super_agent_qa_unless_expected_llm_judge_false`
- LLM Judge 断言数：1

### 场景任务明细

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `realistic_chain_product_release` | `realistic_chain_product_release_cost` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `realistic_chain_product_release` | `realistic_chain_product_release_memory` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `realistic_chain_product_release` | `realistic_chain_product_release_super_agent` | 通过 | 0 |

## 数据质量审计

- 总体分：0.900
- 语言一致性：1.000
- Persona 可信度：1.000
- 输入自然度：1.000
- Oracle 一致性：1.000
- 审计结论：数据质量高，但 dataset_summary 显示仅有一个 case，需扩大规模以验证全面覆盖和多样性
- 覆盖备注：所有 case 语言均为 zh-CN，符合要求；抽样中观察到输入包含 text、voice_transcript、ocr_clip 等多样渠道，内容自然；抽样中观察到 persona 为增长产品经理，职业相关输入可信

### 审计问题

模型审计未发现明显数据质量问题。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `realistic_chain_product_release` | 1.000 | 语言一致，persona 可信，输入自然多样，ground_truth_world 与 eval_tasks 一致 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：6
- Eval task 数：3
- Case family 分布：full_chain_realistic_replay=1
- Task type 分布：cost_trace=1，memory_write=1，super_agent_qa=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_realistic_product_001` | 增长产品经理 | 上海 | zh-CN | 1 | 6 | 3 | 以后重要发布会提前一天提醒我，尤其是灰度和回滚相关的评审，别临近了才说。<br>语音记一下，下周二上午十点和 Mina 看导出灰度风险，记得带最近三天的失败率截图。 |
