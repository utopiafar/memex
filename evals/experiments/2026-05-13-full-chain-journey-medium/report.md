# Memex Agent Eval 实验报告

## 结论

- 断言全绿，但只能作为 journey fixture smoke；数据集同质化明显，暂不适合作为强 benchmark。
- 本次覆盖 6 个 case、60 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：3928980；LLM 调用次数：1854；工具调用次数：1248。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.700。
- 审计摘要：数据集在语言一致性、基础结构和oracle逻辑上表现良好，但存在致命缺陷：6个案例高度同质化，几乎是同一模板的简单替换。这导致数据集多样性严重不足，无法有效评估Agent在不同真实场景下的泛化能力，作为benchmark的价值大打折扣。必须首先解决模板化问题，增加案例的独特性和真实性，然后才能考虑扩大规模。
- 观察数据耗时：2小时00分00秒；Benchmark 评分耗时：29秒。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/full_chain_journey_medium`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 6 |
| Case | 6 |
| 用户输入 | 600 |
| Eval task | 60 |
| 断言 | 306 |
| LLM 调用 | 1854 |
| Tool 调用 | 1248 |
| 实际 token | 3928980 |
| 观察数据耗时 | 2小时00分00秒 |
| Benchmark 评分耗时 | 29秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 3928980 tokens；同规模复跑可先按 3143184-4714776 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| Super Agent 问答 | 检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 回答是否利用用户偏好、习惯或上下文做个性化表达。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 平均每条用户输入消耗的 token 是否在预算内。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 任务失败比例是否低于预算。 |
| 成本 / Trace | 稳定性 | `retry_rate` | 任务 retry 比例是否低于预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 168 | 168 | 100.0% | 1.000 |
| 成本 / Trace | 48 | 48 | 100.0% | 0.905 |
| 记忆写入 | 54 | 54 | 100.0% | 1.000 |
| Super Agent 问答 | 36 | 36 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 42 | 42 | 100.0% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 42 | 42 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 42 | 42 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 42 | 42 | 100.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 6 | 6 | 100.0% | 1.000 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 6 | 6 | 100.0% | - |
| 成本 / Trace | Token 成本 | `cost_per_input` | 6 | 6 | 100.0% | 0.921 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 6 | 6 | 100.0% | 0.604 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 6 | 6 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 6 | 6 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 6 | 6 | 100.0% | - |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 6 | 6 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 6 | 6 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 6 | 6 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 6 | 6 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 6 | 6 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 24 | 24 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 18 | 18 | 100.0% | - |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 6 | 6 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 6 | 6 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 6 | 6 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：1854
- 工具调用次数：1248
- Token 总量：3928980
- 单次 LLM 平均 token：2119.191
- 平均延迟：1688.000 ms
- P95 延迟：3871.000 ms
- 观察数据耗时：2小时00分00秒
- Case 观察耗时累计：2小时00分00秒
- Benchmark 评分耗时：29秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-full-chain-journey-medium`
- 数据集：`evals/datasets/full_chain_journey_medium`
- 观察适配器：`fixture`
- 本地完整日志：`evals/runs/2026-05-13-full-chain-journey-medium/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-full-chain-journey-medium/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-full-chain-journey-medium/outputs.jsonl`
- 场景样本数：6
- 评估任务数：60
- 观察数据耗时：2小时00分00秒
- Benchmark 评分耗时：29秒
- 断言通过：306/306 （100.0%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_card_project_meeting` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_family_visit` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_weekly_report` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_cost_review` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_failure_review` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_final_review` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_project_meeting` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_family_visit` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_weekly_report` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_cost_review` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_failure_review` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_final_review` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_project_meeting` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_family_visit` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_weekly_report` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_cost_review` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_failure_review` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_final_review` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_project_meeting` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_family_visit` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_weekly_report` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_cost_review` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_failure_review` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_final_review` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_project_meeting` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_family_visit` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_weekly_report` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_cost_review` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_failure_review` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_final_review` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_project_meeting` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_family_visit` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_weekly_report` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_cost_review` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_failure_review` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_final_review` | 通过 | 0 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_cost` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_cost` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_cost` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_cost` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_cost` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_cost` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_memory` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_memory` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_memory` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_memory` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_memory` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_memory` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_super_agent` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_super_agent` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_super_agent` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_super_agent` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_super_agent` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_super_agent` | 通过 | 0 |

## 数据质量审计

- 总体分：0.700
- 语言一致性：0.900
- Persona 可信度：0.800
- 输入自然度：0.600
- Oracle 一致性：0.900
- 审计结论：数据集在语言一致性、基础结构和oracle逻辑上表现良好，但存在致命缺陷：6个案例高度同质化，几乎是同一模板的简单替换。这导致数据集多样性严重不足，无法有效评估Agent在不同真实场景下的泛化能力，作为benchmark的价值大打折扣。必须首先解决模板化问题，增加案例的独特性和真实性，然后才能考虑扩大规模。
- 覆盖备注：数据集覆盖了6种不同职业和城市的persona，任务类型包括卡片提取、记忆写入、超级问答和成本追踪。；每个案例包含100条输入流和10个评估任务，结构完整。；主要问题在于6个案例的结构和内容高度同质化，缺乏多样性。

### 审计问题

- `journey_medium_001` / high：高度模板化和重复性。所有6个案例的输入流结构、事件序列、甚至具体语句（如咖啡偏好更新、情绪管理、家庭事务提醒）都几乎完全相同，仅替换项目名称和协作人姓名。；建议：打破模板，为不同persona设计更符合其职业特性、生活习惯和城市背景的多样化输入流和事件。避免简单替换关键词。
- `journey_medium_001` / medium：输入流中存在大量重复或高度相似的语句（例如，关于‘杭州通勤不稳定’、‘晚上散步想到一个点’、‘临时咨询’等），降低了自然度和挑战性。；建议：精简重复内容，增加更多反映用户长期偏好、复杂决策或独特生活细节的输入，使对话历史更丰富、更具区分度。
- `journey_medium_001` / low：部分中文表达略显生硬或书面化，如‘先记一下’、‘帮我记一下’，在口语中可能更常说‘记一下’或‘提醒我’。；建议：微调部分语句，使其更符合中文日常口语习惯，提升自然度。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `journey_medium_001` | 0.650 | 单个案例结构完整，ground truth与任务一致。但作为样本，其内容与后续案例高度雷同，模板化严重，严重影响了数据集的整体多样性和评估有效性。 |
| `journey_medium_002` | 0.650 | 与案例001结构完全一致，仅项目名称和协作人不同。虽然persona（跨境电商运营）和城市（深圳）设定合理，但内容缺乏独特性。 |
| `journey_medium_003` | 0.650 | 继续重复相同的模板。数据分析师（上海）的persona未在输入流中体现出明显的数据分析工作特性（如对数据口径、指标的深入讨论不足）。 |
| `journey_medium_004` | 0.650 | 律师（广州）的persona同样被套入通用模板，未见法律相关工作（如合同审阅、案例研究）的独特内容。 |
| `journey_medium_005` | 0.650 | 财务主管（成都）的案例依然遵循固定模式。‘月底结账’、‘早上核对付款’等习惯在输入流中体现不足，大部分内容是通用的工作沟通。 |
| `journey_medium_006` | 0.650 | 内容运营（苏州）的案例是模板的最后一次重复。‘小红书活动’、‘晚上看评论’等特性未得到充分发挥。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：6
- 输入条数：600
- Eval task 数：60
- Case family 分布：full_chain_journey_medium=6
- Task type 分布：card_extraction=42，cost_trace=6，memory_write=6，super_agent_qa=6

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `journey_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 100 | 10 | 以后像导出项目评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 100 | 10 | 以后像北美站增长评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 100 | 10 | 以后像Memex eval评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_004` | 律师 | 广州 | zh-CN | 1 | 100 | 10 | 以后像法务合同库评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_005` | 财务主管 | 成都 | zh-CN | 1 | 100 | 10 | 以后像预算月结评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 100 | 10 | 以后像小红书活动评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
