# Memex Agent Eval 实验报告

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 6 个 case、54 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：3113280；LLM 调用次数：1488；工具调用次数：1002。
- 观察数据耗时：1小时36分00秒；Benchmark 评分耗时：32秒。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/full_chain_journey_medium`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 6 |
| Case | 6 |
| 用户输入 | 480 |
| Eval task | 54 |
| 断言 | 282 |
| LLM 调用 | 1488 |
| Tool 调用 | 1002 |
| 实际 token | 3113280 |
| 观察数据耗时 | 1小时36分00秒 |
| Benchmark 评分耗时 | 32秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 3113280 tokens；同规模复跑可先按 2490624-3735936 tokens 预留。

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
| Card 抽取 | 144 | 144 | 100.0% | 1.000 |
| 成本 / Trace | 48 | 48 | 100.0% | 0.922 |
| 记忆写入 | 54 | 54 | 100.0% | 1.000 |
| Super Agent 问答 | 36 | 36 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 36 | 36 | 100.0% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 36 | 36 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 36 | 36 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 36 | 36 | 100.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 6 | 6 | 100.0% | 1.000 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 6 | 6 | 100.0% | - |
| 成本 / Trace | Token 成本 | `cost_per_input` | 6 | 6 | 100.0% | 0.922 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 6 | 6 | 100.0% | 0.688 |
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

- LLM 调用次数：1488
- 工具调用次数：1002
- Token 总量：3113280
- 单次 LLM 平均 token：2092.258
- 平均延迟：1565.202 ms
- P95 延迟：3374.000 ms
- 观察数据耗时：1小时36分00秒
- Case 观察耗时累计：1小时36分00秒
- Benchmark 评分耗时：32秒

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
- 评估任务数：54
- 观察数据耗时：1小时36分00秒
- Benchmark 评分耗时：32秒
- 断言通过：282/282 （100.0%）

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
| `journey_medium_002` | `journey_medium_002_card_project_meeting` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_family_visit` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_weekly_report` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_cost_review` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_failure_review` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_project_meeting` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_family_visit` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_weekly_report` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_cost_review` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_failure_review` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_project_meeting` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_family_visit` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_weekly_report` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_cost_review` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_failure_review` | 通过 | 0 |
| `journey_medium_004` | `journey_medium_004_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_project_meeting` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_family_visit` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_weekly_report` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_cost_review` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_failure_review` | 通过 | 0 |
| `journey_medium_005` | `journey_medium_005_card_roadmap_sync` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_project_meeting` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_family_visit` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_weekly_report` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_cost_review` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_failure_review` | 通过 | 0 |
| `journey_medium_006` | `journey_medium_006_card_roadmap_sync` | 通过 | 0 |

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

- 总体分：0.750
- 语言一致性：1.000
- Persona 可信度：0.900
- 输入自然度：0.600
- Oracle 一致性：1.000
- 审计结论：数据集在语言一致性、基础persona可信度和oracle内部一致性方面表现优秀。主要缺陷在于数据生成的‘模板化’和‘重复性’过高：六个案例的输入流句式、任务结构高度同构，仅通过替换项目名、城市、人名等变量生成，这使得数据集缺乏评估模型泛化能力和处理真实世界多样性的深度，更像是一个‘填空题’集合而非自然的用户交互日志。因此，它适合作为初步的功能验证（smoke test），但作为有区分度的benchmark，其自然性和多样性不足。
- 覆盖备注：数据覆盖了用户偏好记忆（会议提醒、咖啡习惯）、项目信息（负责人）、临时指令与长期记忆的区分、复盘模板要求等多种类型。；评估任务类型全面，包括信息抽取、记忆写入、问答和成本追踪。

### 审计问题

- `journey_medium_001` / medium：输入流存在高度模板化和重复模式，不同persona的输入仅在项目名称、城市、同事姓名等占位符上不同，句式结构高度雷同。；建议：增加输入句式的多样性，减少‘今天有点烦’、‘晚上散步想到一个点’等固定句式的机械重复，让不同职业用户的表达习惯有更明显的区分。
- `journey_medium_002` / medium：eval_tasks 结构完全同构，6个案例的任务类型、数量、甚至部分任务描述（如 must_not_fields）完全一致，仅内容占位符不同，降低了评估的多样性。；建议：为不同persona设计略有差异的评估任务组合或侧重点，例如为数据分析师增加数据口径相关的抽取任务，为律师增加合同条款相关的记忆任务。
- `journey_medium_003` / low：部分‘习惯’（如‘周三下午需求评审’）在输入流中未得到充分体现或演化，更像是静态设定。；建议：让用户的习惯在输入流中有更动态的体现，例如因故调整习惯时间，或习惯与其他事件产生冲突时的处理指令。
- `journey_medium_004` / low：‘ground_truth_world’中的‘events’仅包含两个示例，与长达80条的‘input_stream’相比，关联性展示不足，可能影响对‘事实’提取任务的评估理解。；建议：在ground_truth_world中更明确地标注哪些input_stream记录对应‘事实’或‘事件’，或增加events的数量以更好地锚定关键信息。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `journey_medium_001` | 0.750 | 语言地道，persona合理，oracle一致性完美。主要扣分项在于输入流的句式存在明显的模板复制痕迹，自然度不足。 |
| `journey_medium_002` | 0.750 | 与001案例结构高度相似，仅在项目、城市、人名上做了替换。虽然单看合理，但作为一组数据，重复性过高，影响了整体的‘自然’评分。 |
| `journey_medium_003` | 0.750 | 数据分析师的persona（如‘指标解释要保留英文metric id’）在输入中体现不足。整体仍受限于模板化输入和同构任务的问题。 |
| `journey_medium_004` | 0.750 | 律师persona的‘下午审合同’习惯在输入中有呼应。核心问题仍是与其他案例共享的模板化和任务同构问题。 |
| `journey_medium_005` | 0.750 | 财务主管的‘月底结账’、‘早上核对付款’习惯在输入中得到体现。但整体数据生成模式与其他案例无异。 |
| `journey_medium_006` | 0.750 | 内容运营的‘晚上看评论’、‘周五整理选题’习惯有体现。作为系列中的最后一个，模板化问题同样显著。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：6
- 输入条数：480
- Eval task 数：54
- Case family 分布：full_chain_journey_medium=6
- Task type 分布：card_extraction=36，cost_trace=6，memory_write=6，super_agent_qa=6

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `journey_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 80 | 9 | 以后像导出项目评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 80 | 9 | 以后像北美站增长评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 80 | 9 | 以后像Memex eval评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_004` | 律师 | 广州 | zh-CN | 1 | 80 | 9 | 以后像法务合同库评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_005` | 财务主管 | 成都 | zh-CN | 1 | 80 | 9 | 以后像预算月结评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 80 | 9 | 以后像小红书活动评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
