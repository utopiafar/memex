# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/full_chain_journey_medium`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 3 个 case、18 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：617940；LLM 调用次数：303；工具调用次数：228。
- Replay 实测耗时：21分00秒；Benchmark 评分耗时：28秒。

## 执行补充

- 本报告是 `fixture` adapter 的中等规模 Journey 基线，用于验证数据集、grader、指标聚合和报告结构；其中 token / latency 来自 fixture 观察值，不代表真实模型实耗。
- 同步试跑过真实 `serial_full_chain_replay_test.dart`：数据集为 3 个 persona、每人 40 条 record，`maxConcurrency=1`，逐条输入后等待任务收敛。试跑在第 1 个 persona 的第 7-8 条输入附近暴露出后台任务长时间 `processing/retrying`，第 7 条等待超过 5 分钟仍未完全 idle；继续完整 120 条会主要变成等待超时，因此中止并把它记录为执行发现。
- 结论：数据集已经可以作为中等规模 Journey benchmark 的结构基线；真实链路层面下一步要先定位 task 不收敛 / retrying 的原因，再跑完整 120 条 replay。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 3 |
| Case | 3 |
| 用户输入 | 120 |
| Eval task | 18 |
| 断言 | 105 |
| LLM 调用 | 303 |
| Tool 调用 | 228 |
| 实际 token | 617940 |
| Replay 总耗时 | 21分00秒 |
| Benchmark 评分耗时 | 28秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 617940 tokens；同规模复跑可先按 494352-741528 tokens 预留。

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
| Card 抽取 | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | 24 | 24 | 100.0% | 0.964 |
| 记忆写入 | 27 | 27 | 100.0% | 1.000 |
| Super Agent 问答 | 18 | 18 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 9 | 9 | 100.0% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 9 | 9 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 9 | 9 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 9 | 9 | 100.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 3 | 3 | 100.0% | 1.000 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 3 | 3 | 100.0% | - |
| 成本 / Trace | Token 成本 | `cost_per_input` | 3 | 3 | 100.0% | 0.940 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 3 | 3 | 100.0% | 0.880 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 3 | 3 | 100.0% | - |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 3 | 3 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 3 | 3 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 3 | 3 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 3 | 3 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 3 | 3 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 12 | 12 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 9 | 9 | 100.0% | - |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 3 | 3 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 3 | 3 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 3 | 3 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：303
- 工具调用次数：228
- Token 总量：617940
- 单次 LLM 平均 token：2039.406
- 平均延迟：1354.370 ms
- P95 延迟：2394.000 ms
- Replay 总耗时：21分00秒
- Case 耗时累计：21分00秒
- Benchmark 评分耗时：28秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-full-chain-journey-medium-fixture`
- 数据集：`evals/datasets/full_chain_journey_medium`
- 观察适配器：`fixture`
- 场景样本数：3
- 评估任务数：18
- Replay 运行耗时：21分00秒
- Benchmark 评分耗时：28秒
- 断言通过：105/105 （100.0%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_card_project_meeting` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_family_visit` | 通过 | 0 |
| `journey_medium_001` | `journey_medium_001_card_weekly_report` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_project_meeting` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_family_visit` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_card_weekly_report` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_project_meeting` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_family_visit` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_card_weekly_report` | 通过 | 0 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_cost` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_cost` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_cost` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_memory` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_memory` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_memory` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_medium_001` | `journey_medium_001_super_agent` | 通过 | 0 |
| `journey_medium_002` | `journey_medium_002_super_agent` | 通过 | 0 |
| `journey_medium_003` | `journey_medium_003_super_agent` | 通过 | 0 |

## 数据质量审计

- 总体分：0.850
- 语言一致性：0.900
- Persona 可信度：0.850
- 输入自然度：0.900
- Oracle 一致性：0.900
- 审计结论：数据集整体质量良好，语言稳定为中文且自然，人物设定（职业、城市）可信，ground_truth、input_stream和eval_tasks之间具有高度的内部一致性，未发现明显的oracle泄漏。主要缺陷在于三个案例的输入流存在严重的模板化重复，降低了数据的多样性和自然度。作为小规模smoke test数据集（overall_score >= 0.8）可以接受，但在扩大规模前必须解决模板化问题以增加场景多样性。
- 覆盖备注：数据集包含3个案例，覆盖了card_extraction、memory_write、super_agent_qa和cost_trace四种任务类型。；每个案例包含40条输入记录和6个评估任务，结构完整。；案例覆盖了不同职业（产品经理、跨境电商运营、数据分析师）和城市（杭州、深圳、上海），具有一定的多样性。

### 审计问题

- `journey_medium_001, journey_medium_002, journey_medium_003` / medium：三个案例的输入流（input_stream）在结构、时间线、大部分句子内容上高度模板化和重复，仅替换了项目名称、协作人姓名、城市和少数习惯细节。；建议：在扩大数据集规模时，应设计更多样化的用户场景、对话流和任务序列，避免简单的‘查找替换’式生成，以提高数据的自然度和评估的鲁棒性。
- `journey_medium_001, journey_medium_002, journey_medium_003` / low：部分习惯（如‘周三下午需求评审’、‘周三晚上健身’、‘上午深度分析’）在ground_truth_world的‘habits’中列出，但在提供的40条input_stream样本中并未被明确提及或强化，其来源不够清晰。；建议：确保ground_truth_world中声明的用户习惯（habits）在input_stream中有对应的、自然的提及或体现，以增强内部一致性。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `journey_medium_001` | 0.850 | 语言自然，符合产品经理场景。ground_truth事实（会议提醒、咖啡偏好、项目负责人Alex）与input_stream和eval_tasks预期一致。主要问题是输入流与其他案例高度相似，模板化明显。 |
| `journey_medium_002` | 0.850 | 语言自然，跨境电商运营场景可信。内部一致性好，ground_truth事实（会议提醒、咖啡偏好、项目负责人Jason）可从输入中推出。问题同样是输入流结构高度模板化。 |
| `journey_medium_003` | 0.850 | 语言自然，数据分析师场景（如dashboard review）贴合。ground_truth事实（会议提醒、咖啡偏好、项目负责人Grace）与输入和任务预期一致。模板化重复问题是主要扣分项。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：3
- 输入条数：120
- Eval task 数：18
- Case family 分布：full_chain_journey_medium=3
- Task type 分布：card_extraction=9，cost_trace=3，memory_write=3，super_agent_qa=3

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `journey_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 40 | 6 | 以后像导出项目评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 40 | 6 | 以后像北美站增长评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
| `journey_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 40 | 6 | 以后像Memex eval评审这种重要会议，尽量提前一天提醒我，别临近了才说。<br>先记一下，我最近不喝咖啡，早上也不要，免得影响状态。 |
