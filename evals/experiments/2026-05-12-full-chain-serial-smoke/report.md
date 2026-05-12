# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_serial_smoke`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 1 个 case、3 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：26376；LLM 调用次数：18；工具调用次数：69。
- Replay 实测耗时：6分45秒；Benchmark 评分耗时：0秒。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 1 |
| 用户输入 | 5 |
| Eval task | 3 |
| 断言 | 15 |
| LLM 调用 | 18 |
| Tool 调用 | 69 |
| 实际 token | 26376 |
| Replay 总耗时 | 6分45秒 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 26376 tokens；同规模复跑可先按 21101-31651 tokens 预留。

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
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | 5 | 5 | 100.0% | 0.978 |
| 记忆写入 | 5 | 5 | 100.0% | 1.000 |
| Super Agent 问答 | 5 | 5 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 1 | 1 | 100.0% | - |
| 成本 / Trace | Token 成本 | `total_token_budget` | 1 | 1 | 100.0% | 0.956 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 1 | 1 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 1 | 1 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 1 | 1 | 100.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 1 | 1 | 100.0% | 1.000 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 1 | 1 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 1 | 1 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：18
- 工具调用次数：69
- Token 总量：26376
- 单次 LLM 平均 token：1465.333
- 平均延迟：13739.130 ms
- P95 延迟：98000.000 ms
- Replay 总耗时：6分45秒
- Case 耗时累计：6分45秒
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-full-chain-serial-smoke`
- 数据集：`evals/datasets/full_chain_serial_smoke`
- 观察适配器：`replay_file`
- 场景样本数：1
- 评估任务数：3
- Replay 运行耗时：6分45秒
- Benchmark 评分耗时：0秒
- 断言通过：15/15 （100.0%）

### 场景任务明细

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_serial_001` | `full_chain_serial_001_cost` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_serial_001` | `full_chain_serial_001_memory` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_serial_001` | `full_chain_serial_001_super_agent` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：5
- Eval task 数：3
- Case family 分布：full_chain_serial_replay=1
- Task type 分布：cost_trace=1，memory_write=1，super_agent_qa=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_serial_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 5 | 3 | 以后重要会议尽量提前一天提醒我，别临近了才说。<br>我不喝咖啡，早上也不要。 |
