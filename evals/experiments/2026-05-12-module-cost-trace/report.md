# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/cost_trace`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 3 个 case、3 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：9700；LLM 调用次数：3；工具调用次数：3。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 3 |
| Case | 3 |
| 用户输入 | 111 |
| Eval task | 3 |
| 断言 | 24 |
| LLM 调用 | 3 |
| Tool 调用 | 3 |
| 实际 token | 9700 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 9700 tokens；同规模复跑可先按 7760-11640 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 成本 / Trace | Token 成本 | `cost_per_input` | 平均每条用户输入消耗的 token 是否在预算内。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | Trace 是否包含期望的关键事件或工具调用节点。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 任务失败比例是否低于预算。 |
| 成本 / Trace | 稳定性 | `retry_rate` | 任务 retry 比例是否低于预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 成本 / Trace | 队列等待 | `queue_idle_time` | 任务队列等待或空转时间是否在预算内。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | 24 | 24 | 100.0% | 0.894 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | Token 成本 | `cost_per_input` | 2 | 2 | 100.0% | 0.733 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 3 | 3 | 100.0% | 0.753 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 2 | 2 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 2 | 2 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 2 | 2 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 3 | 3 | 100.0% | 1.000 |
| 成本 / Trace | 队列等待 | `queue_idle_time` | 1 | 1 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：3
- 工具调用次数：3
- Token 总量：9700
- 单次 LLM 平均 token：3233.333
- 平均延迟：5367.778 ms
- P95 延迟：9000.000 ms
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-module-cost-trace`
- 数据集：`evals/datasets/modules/cost_trace`
- 观察适配器：`fixture`
- 场景样本数：3
- 评估任务数：3
- Benchmark 评分耗时：0秒
- 断言通过：24/24 （100.0%）

### 场景任务明细

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_cost_trace_001` | `task_cost_trace_001` | 通过 | 0 |
| `module_cost_trace_queue_002` | `task_cost_trace_queue_002` | 通过 | 0 |
| `module_cost_trace_stability_003` | `task_cost_trace_stability_003` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：3
- 输入条数：111
- Eval task 数：3
- Case family 分布：cost_trace=3
- Task type 分布：cost_trace=3

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 36 | 1 | 早上先看一下昨天广告账户的消耗，今天预算别太激进。<br>午饭别订海鲜，最近过敏又有点反复。 |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 37 | 1 | 早上先过一遍版本风险，今天别被零碎需求打散。<br>以后评审材料希望结论先行，细节放后面。 |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 38 | 1 | 早上先跑昨天的数据质量检查，看有没有埋点延迟。<br>以后异常分析先看样本量，再看比例变化。 |
