# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_smoke`。

## 结论

- 基本可用，但存在需要跟踪的失败项。
- 本次覆盖 1 个 case、2 个 eval task，断言通过率 90.9%。
- 失败断言数：1；Token 总量：0；LLM 调用次数：1；工具调用次数：0。
- 主要失败项：
  - `full_chain_submit_001_card` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 processing。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 1 |
| 用户输入 | 1 |
| Eval task | 2 |
| 断言 | 11 |
| LLM 调用 | 1 |
| Tool 调用 | 0 |
| 实际 token | 0 |

- 数据语言：zh-CN
- Token 估算：本次没有可靠 token 记录，通常表示 fixture 或 no-LLM replay；真实模型实验需要用同规模 replay 重新估算。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |

### 关键指标口径

| 指标 | 含义 |
| --- | --- |
| `card_field_constraint_accuracy` | 指定 card 字段是否包含应保留的细节。 |
| `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 |
| `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| `latency_budget` | 最大延迟是否未超过预算。 |
| `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| `tool_call_budget` | 工具调用次数是否未超过预算。 |
| `total_token_budget` | 总 token 是否未超过预算。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 5 | 6 | 83.3% | 1.000 |
| 成本 / Trace | 5 | 5 | 100.0% | 1.000 |

### 关键指标结果

| 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| `card_field_constraint_accuracy` | 1 | 1 | 100.0% | 1.000 |
| `card_schema_valid` | 1 | 1 | 100.0% | - |
| `card_status_accuracy` | 0 | 1 | 0.0% | - |
| `card_type_accuracy` | 1 | 1 | 100.0% | - |
| `cost_answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| `hallucinated_field_absence` | 1 | 1 | 100.0% | - |
| `latency_budget` | 1 | 1 | 100.0% | - |
| `task_completion_status` | 1 | 1 | 100.0% | - |
| `title_constraint_accuracy` | 1 | 1 | 100.0% | 1.000 |
| `tool_call_budget` | 1 | 1 | 100.0% | - |
| `total_token_budget` | 1 | 1 | 100.0% | 1.000 |

### 成本与 Trace

- LLM 调用次数：1
- 工具调用次数：0
- Token 总量：0
- 单次 LLM 平均 token：0.000
- 平均延迟：48.538 ms
- P95 延迟：0.000 ms

## 失败样本

- `full_chain_submit_001_card` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 processing。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-11-full-chain-smoke`
- 数据集：`evals/datasets/full_chain_smoke`
- 观察适配器：`replay_file`
- 场景样本数：1
- 评估任务数：2
- 断言通过：10/11 （90.9%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_submit_001` | `full_chain_submit_001_card` | 未通过 | 1 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_submit_001` | `full_chain_submit_001_cost` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：1
- Eval task 数：2
- Case family 分布：card_extraction=1
- Task type 分布：card_extraction=1，cost_trace=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_full_chain_001` | 产品经理 | 杭州 | zh-CN | 1 | 1 | 2 | 今天先把 Memex eval 的全链路 smoke 跑通，重点看输入、卡片、后台任务和 trace 有没有串起来。 |
