# Memex Agent 评估报告

## 结论

- 基本可用，但存在需要跟踪的失败项。
- 本次覆盖 1 个 case、2 个 eval task，断言通过率 90.9%。
- 失败断言数：1；Token 总量：0；LLM 调用次数：1；工具调用次数：0。
- 主要失败项：
  - `full_chain_submit_001_card` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 processing。

## 运行信息

- 运行 ID：`full_chain_replay_smoke`
- 数据集：`evals/datasets/full_chain_smoke`
- 观察适配器：`replay_file`
- 场景样本数：1
- 评估任务数：2
- 断言通过：10/11 （90.9%）

## 分场景结果

| 场景 | 评估目标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 | 5 | 6 | 83.3% | 1.000 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 | 5 | 5 | 100.0% | 1.000 |

## 关键指标与解释

| 指标 | 含义 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | ---: | ---: | ---: | ---: |
| `card_field_constraint_accuracy` | 指定 card 字段是否包含应保留的细节。 | 1 | 1 | 100.0% | 1.000 |
| `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 | 1 | 1 | 100.0% | - |
| `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 | 0 | 1 | 0.0% | - |
| `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 | 1 | 1 | 100.0% | - |
| `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 | 1 | 1 | 100.0% | 1.000 |
| `hallucinated_field_absence` | 是否没有编造禁止字段。 | 1 | 1 | 100.0% | - |
| `latency_budget` | 最大延迟是否未超过预算。 | 1 | 1 | 100.0% | - |
| `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 | 1 | 1 | 100.0% | - |
| `title_constraint_accuracy` | 标题是否包含关键主题词。 | 1 | 1 | 100.0% | 1.000 |
| `tool_call_budget` | 工具调用次数是否未超过预算。 | 1 | 1 | 100.0% | - |
| `total_token_budget` | 总 token 是否未超过预算。 | 1 | 1 | 100.0% | 1.000 |

## 成本与 Trace

- LLM 调用次数：1
- 工具调用次数：0
- Token 总量：0
- 单次 LLM 平均 token：0.000
- 平均延迟：48.538 ms
- P95 延迟：0.000 ms

## 失败样本

- `full_chain_submit_001_card` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 processing。

## 场景任务明细

### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_submit_001` | `full_chain_submit_001_card` | 未通过 | 1 |

### 成本 / Trace

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
