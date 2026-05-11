# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_medium`。

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 本次覆盖 3 个 case、9 个 eval task，断言通过率 64.1%。
- 失败断言数：14；Token 总量：111516；LLM 调用次数：75；工具调用次数：246。
- 主要失败项：
  - `full_chain_medium_002_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
  - `full_chain_medium_002_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
  - `full_chain_medium_002_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 3 |
| Case | 3 |
| 用户输入 | 6 |
| Eval task | 9 |
| 断言 | 39 |
| LLM 调用 | 75 |
| Tool 调用 | 246 |
| 实际 token | 111516 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 111516 tokens；同规模复跑可先按 89213-133819 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 12 | 24 | 50.0% | 0.333 |
| 成本 / Trace | 13 | 15 | 86.7% | 0.690 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 2 | 6 | 33.3% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 2 | 6 | 33.3% | 0.333 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 6 | 6 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 2 | 6 | 33.3% | - |
| 成本 / Trace | Token 成本 | `total_token_budget` | 3 | 3 | 100.0% | 0.380 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 3 | 33.3% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 3 | 3 | 100.0% | 1.000 |

### 成本与 Trace

- LLM 调用次数：75
- 工具调用次数：246
- Token 总量：111516
- 单次 LLM 平均 token：1486.880
- 平均延迟：1088.803 ms
- P95 延迟：0.000 ms

## 失败样本

- `full_chain_medium_002_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_002_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_002_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.
- `full_chain_medium_002_card_b` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_002_card_b` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_002_card_b` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：数据看板.
- `full_chain_medium_002_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=5, failed_tasks=0.
- `full_chain_medium_003_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_003_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_003_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：合同风险.
- `full_chain_medium_003_card_b` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_003_card_b` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_003_card_b` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：灰度.
- `full_chain_medium_003_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=6, failed_tasks=0.

## 实验详情

### 运行信息

- 运行 ID：`2026-05-11-full-chain-medium-llm`
- 数据集：`evals/datasets/full_chain_medium`
- 观察适配器：`replay_file`
- 场景样本数：3
- 评估任务数：9
- 断言通过：25/39 （64.1%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_medium_001` | `full_chain_medium_001_card_a` | 通过 | 0 |
| `full_chain_medium_001` | `full_chain_medium_001_card_b` | 通过 | 0 |
| `full_chain_medium_002` | `full_chain_medium_002_card_a` | 未通过 | 3 |
| `full_chain_medium_002` | `full_chain_medium_002_card_b` | 未通过 | 3 |
| `full_chain_medium_003` | `full_chain_medium_003_card_a` | 未通过 | 3 |
| `full_chain_medium_003` | `full_chain_medium_003_card_b` | 未通过 | 3 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_medium_001` | `full_chain_medium_001_cost` | 通过 | 0 |
| `full_chain_medium_002` | `full_chain_medium_002_cost` | 未通过 | 1 |
| `full_chain_medium_003` | `full_chain_medium_003_cost` | 未通过 | 1 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：3
- 输入条数：6
- Eval task 数：9
- Case family 分布：full_chain_replay=3
- Task type 分布：card_extraction=6，cost_trace=3

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_fc_medium_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 2 | 3 | 明天上午十点提醒我和 Ada 过一下投流预算。<br>周五下午三点和老王在腾讯会议复盘客户续约，记一下。 |
| `eval_fc_medium_002` | 产品经理 | 杭州 | zh-CN | 1 | 2 | 3 | 下周三晚上七点提醒我去望京和 Annie 吃饭。<br>今天下班前提醒我把数据看板周报发给 Leo。 |
| `eval_fc_medium_003` | 律师 | 广州 | zh-CN | 1 | 2 | 3 | 5月16日下午两点和 Mina 线上确认合同风险。<br>明早九点提醒我检查版本灰度监控和回滚预案。 |
