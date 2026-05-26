# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_medium`。

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 本次覆盖 6 个 case、18 个 eval task，断言通过率 50.0%。
- 失败断言数：39；Token 总量：297539；LLM 调用次数：213；工具调用次数：666。
- 主要失败项：
  - `full_chain_medium_002_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
  - `full_chain_medium_002_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
  - `full_chain_medium_002_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 6 |
| Case | 6 |
| 用户输入 | 12 |
| Eval task | 18 |
| 断言 | 78 |
| LLM 调用 | 213 |
| Tool 调用 | 666 |
| 实际 token | 297539 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 297539 tokens；同规模复跑可先按 238031-357047 tokens 预留。

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
| Card 抽取 | 18 | 48 | 37.5% | 0.167 |
| 成本 / Trace | 21 | 30 | 70.0% | 0.599 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 2 | 12 | 16.7% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 2 | 12 | 16.7% | 0.167 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 12 | 12 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 2 | 12 | 16.7% | - |
| 成本 / Trace | Token 成本 | `total_token_budget` | 4 | 6 | 66.7% | 0.198 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 6 | 16.7% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 5 | 6 | 83.3% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 5 | 6 | 83.3% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 6 | 6 | 100.0% | 1.000 |

### 成本与 Trace

- LLM 调用次数：213
- 工具调用次数：666
- Token 总量：297539
- 单次 LLM 平均 token：1396.897
- 平均延迟：860.327 ms
- P95 延迟：0.000 ms

## 失败样本

- `full_chain_medium_002_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_002_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_002_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.
- `full_chain_medium_002_card_b` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_002_card_b` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_002_card_b` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：数据看板.
- `full_chain_medium_002_cost` / `total_token_budget`：Token 成本超过预算或余量不足。total_tokens=65923, max=60000.
- `full_chain_medium_002_cost` / `tool_call_budget`：工具调用次数超过预算。tool_calls=53, max=50.
- `full_chain_medium_002_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=6, failed_tasks=0, active_details=card_agent_task:retrying:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, Tool call loop detect... | pkm_agent_task:processing:AgentException(code: AgentExceptionCode.loopDetection, message: Maximum turns reached (20). Possible... | comment_agent_task:pending | card_agent_task:processing.
- `full_chain_medium_003_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_003_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_003_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：合同风险.
- `full_chain_medium_003_card_b` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_003_card_b` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_003_card_b` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：灰度.
- `full_chain_medium_003_cost` / `total_token_budget`：Token 成本超过预算或余量不足。total_tokens=63076, max=60000.
- `full_chain_medium_003_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=6, failed_tasks=0, active_details=card_agent_task:retrying:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, Tool call loop detect... | pkm_agent_task:pending | comment_agent_task:pending | card_agent_task:processing.
- `full_chain_medium_004_card_a` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `full_chain_medium_004_card_a` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。
- `full_chain_medium_004_card_a` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：付款清单.

## 问题排查与建议

### 排查过程

- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。
- 对全链路失败，优先查看 cost task 中的 `settled`、`active_tasks`、`failed_tasks`，再关联同一 case 的 card 断言。
- 对 card 失败，检查对应 `input_id` 是否能通过提交返回的 fact id 找到 card，以及 card 是否停留在 processing/null。

### 结论

- 全链路主要问题是后台任务未在预算时间内全部收敛，后续 card 断言出现 null/缺字段更像链路未完成的下游现象。
- active task 中出现 loopDetection，说明至少部分 agent task 卡在重复工具调用保护上，而不是普通网络超时。
- Card 相关失败集中在未生成、未完成或无法按输入来源取回，优先怀疑 task 生命周期、card agent 落盘和 fact_id/card_id 关联。
- 标题关键词缺失说明即使 card 生成成功，也需要继续验证输入关键信息是否进入标题或结构化字段。
- 成本类失败需要和 trace 一起看，判断是必要工具链过长还是重复调用。

### 修改建议

- 给 LocalTaskExecutor / task handler 增加按 case 可检索的任务状态摘要，明确 pending、processing、retrying 的阻塞点和最后一次错误。
- 在 replay harness 里保留每个 active task 的 type、status、attempt、updated_at，便于区分真实超时和观察窗口太短。
- 针对 loopDetection case，优先检查 card_agent / pkm_agent 的工具调用终止条件，避免同一工具连续调用 5 次后进入 retrying。
- 检查 submitInput 返回的 fact_id 到 TimelineCard 的关联路径，确认 card agent 完成后会把 status 从 processing 推进到 completed。
- 为 card agent 增加最小字段契约测试：title、status、source/fact 关联、关键主题词进入 title 或结构化字段。
- 对高成本 case 按 trace 聚合 agent/tool 调用，优先消除重复检索和重复 PKM 整理。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-full-chain-medium-llm-expanded`
- 数据集：`evals/datasets/full_chain_medium`
- 观察适配器：`replay_file`
- 场景样本数：6
- 评估任务数：18
- 断言通过：39/78 （50.0%）

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
| `full_chain_medium_004` | `full_chain_medium_004_card_a` | 未通过 | 3 |
| `full_chain_medium_004` | `full_chain_medium_004_card_b` | 未通过 | 3 |
| `full_chain_medium_005` | `full_chain_medium_005_card_a` | 未通过 | 3 |
| `full_chain_medium_005` | `full_chain_medium_005_card_b` | 未通过 | 3 |
| `full_chain_medium_006` | `full_chain_medium_006_card_a` | 未通过 | 3 |
| `full_chain_medium_006` | `full_chain_medium_006_card_b` | 未通过 | 3 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `full_chain_medium_001` | `full_chain_medium_001_cost` | 通过 | 0 |
| `full_chain_medium_002` | `full_chain_medium_002_cost` | 未通过 | 3 |
| `full_chain_medium_003` | `full_chain_medium_003_cost` | 未通过 | 2 |
| `full_chain_medium_004` | `full_chain_medium_004_cost` | 未通过 | 2 |
| `full_chain_medium_005` | `full_chain_medium_005_cost` | 未通过 | 1 |
| `full_chain_medium_006` | `full_chain_medium_006_cost` | 未通过 | 1 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：6
- 输入条数：12
- Eval task 数：18
- Case family 分布：full_chain_replay=6
- Task type 分布：card_extraction=12，cost_trace=6

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_fc_medium_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 2 | 3 | 明天上午十点提醒我和 Ada 过一下投流预算。<br>周五下午三点和老王在腾讯会议复盘客户续约，记一下。 |
| `eval_fc_medium_002` | 产品经理 | 杭州 | zh-CN | 1 | 2 | 3 | 下周三晚上七点提醒我去望京和 Annie 吃饭。<br>今天下班前提醒我把数据看板周报发给 Leo。 |
| `eval_fc_medium_003` | 律师 | 广州 | zh-CN | 1 | 2 | 3 | 5月16日下午两点和 Mina 线上确认合同风险。<br>明早九点提醒我检查版本灰度监控和回滚预案。 |
| `eval_fc_medium_004` | 财务主管 | 成都 | zh-CN | 1 | 2 | 3 | 周四中午前提醒我确认供应商付款清单。<br>明天下午四点和 Jason 讨论预算调整，地点飞书会议。 |
| `eval_fc_medium_005` | 内容运营 | 苏州 | zh-CN | 1 | 2 | 3 | 这周五提醒我整理小红书活动复盘素材。<br>5月18日上午十点和 Grace 看一下选题排期。 |
| `eval_fc_medium_006` | 数据分析师 | 武汉 | zh-CN | 1 | 2 | 3 | 明天早上提醒我检查实验埋点有没有漏字段。<br>周三下午两点和小陈复盘转化漏斗异常。 |
