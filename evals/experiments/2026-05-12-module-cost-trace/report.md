# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/cost_trace`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 1 个 case、1 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：2500；LLM 调用次数：1；工具调用次数：1。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 1 |
| 用户输入 | 0 |
| Eval task | 1 |
| 断言 | 5 |
| LLM 调用 | 1 |
| Tool 调用 | 1 |
| 实际 token | 2500 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 2500 tokens；同规模复跑可先按 2000-3000 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | 5 | 5 | 100.0% | 0.896 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 成本 / Trace | Token 成本 | `total_token_budget` | 1 | 1 | 100.0% | 0.792 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 1 | 1 | 100.0% | 1.000 |

### 成本与 Trace

- LLM 调用次数：1
- 工具调用次数：1
- Token 总量：2500
- 单次 LLM 平均 token：2500.000
- 平均延迟：5366.667 ms
- P95 延迟：8000.000 ms
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-module-cost-trace`
- 数据集：`evals/datasets/modules/cost_trace`
- 观察适配器：`fixture`
- 场景样本数：1
- 评估任务数：1
- Benchmark 评分耗时：0秒
- 断言通过：5/5 （100.0%）

### 场景任务明细

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_cost_trace_001` | `task_cost_trace_001` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：0
- Eval task 数：1
- Case family 分布：cost_trace=1
- Task type 分布：cost_trace=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 0 | 1 |  |
