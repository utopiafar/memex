# Memex Agent Eval 实验报告

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力。
- 本次覆盖 112 个 case、112 个 eval task，断言通过率 86.1%。
- 失败断言数：80；Token 总量：251440；LLM 调用次数：112；工具调用次数：16。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.550。
- 审计摘要：数据集的主要缺陷在于高度的模板化和重复性。虽然语言为中文且任务设计（oracle一致性）基本合理，但不同persona和案例的输入、上下文缺乏实质性的领域差异和自然变化，像是由同一套模板批量生成。这严重损害了数据的自然度、persona的可信度以及作为评估基准的多样性，因此整体评分较低，不适合作为有效的smoke/benchmark数据，需要在内容多样性上进行大幅重构。
- 主要失败项：
  - `hard_memory_transient_03_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期不太想说话。
  - `hard_memory_transient_03_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
  - `hard_memory_transient_07_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期想安静。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/hard_case_challenge`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 16 |
| Case | 112 |
| 用户输入 | 1568 |
| Eval task | 112 |
| 断言 | 576 |
| LLM 调用 | 112 |
| Tool 调用 | 16 |
| 实际 token | 251440 |
| Benchmark 评分耗时 | 38秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 251440 tokens；同规模复跑可先按 201152-301728 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| PKM 整理 | 检查 PKM 条目是否放到正确路径、保留关键信息并引用来源。 |
| 检索问答 | 检查查询时是否召回正确来源，并基于证据回答。 |
| 日程刷新 | 检查日程相关输入是否正确 skip / dirty / refresh，并控制不必要刷新。 |
| Super Agent 问答 | 检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 |
| Card 抽取 | 字段抽取 | `location_accuracy` | 地点字段是否包含期望地点。 |
| Card 抽取 | 字段抽取 | `participant_recall` | 期望人物是否都被抽取出来。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 时间解析是否落在允许误差内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | PKM 条目是否保留关键事实、结论和下一步。 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | PKM 条目是否没有写入明确禁止的临时信息。 |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | PKM 条目是否保留期望来源 id。 |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | PKM 条目数量是否符合合并/拆分预期。 |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | PKM 条目路径是否包含期望目录或项目名。 |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 回答是否利用用户偏好、习惯或上下文做个性化表达。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 日程刷新决策是否等于期望的 skip / dirty / refresh。 |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 必须刷新时是否没有漏掉刷新。 |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 无需刷新时是否没有触发重刷新。 |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 是否没有对同一日程变化触发重复刷新。 |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 证据不足时是否正确表达不确定，证据充分时是否不乱拒答。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | Top 1 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | Top 3 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | Top 5 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 第一个正确来源排名的倒数，越高越好。 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | Top 5 中覆盖了多少期望来源。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 答案引用的来源是否覆盖期望来源。 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 答案是否同时满足来源引用和无无证据断言。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 100 | 112 | 89.3% | 0.750 |
| 记忆写入 | 80 | 96 | 83.3% | 0.906 |
| PKM 整理 | 64 | 80 | 80.0% | 0.750 |
| 检索问答 | 120 | 128 | 93.8% | 1.000 |
| 日程刷新 | 68 | 80 | 85.0% | 1.000 |
| Super Agent 问答 | 64 | 80 | 80.0% | 0.875 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 16 | 16 | 100.0% | - |
| Card 抽取 | 字段抽取 | `location_accuracy` | 16 | 16 | 100.0% | - |
| Card 抽取 | 字段抽取 | `participant_recall` | 12 | 16 | 75.0% | 0.750 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 12 | 16 | 75.0% | 0.750 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 16 | 16 | 100.0% | - |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 12 | 16 | 75.0% | 0.750 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 16 | 16 | 100.0% | - |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | 12 | 16 | 75.0% | 0.750 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | 12 | 16 | 75.0% | - |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | 12 | 16 | 75.0% | - |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | 16 | 16 | 100.0% | - |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | 12 | 16 | 75.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 12 | 16 | 75.0% | 0.750 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 12 | 16 | 75.0% | - |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 12 | 16 | 75.0% | - |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 16 | 16 | 100.0% | - |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 12 | 16 | 75.0% | - |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 12 | 16 | 75.0% | 1.000 |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 0 | 4 | 0.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 12 | 12 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 24 | 32 | 75.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 28 | 28 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 12 | 12 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 12 | 12 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 28 | 32 | 87.5% | 0.875 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 12 | 16 | 75.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 12 | 16 | 75.0% | 0.875 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 12 | 16 | 75.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 16 | 16 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 8 | 8 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 12 | 16 | 75.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 8 | 8 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：112
- 工具调用次数：16
- Token 总量：251440
- 单次 LLM 平均 token：2245.000
- 平均延迟：1046.667 ms
- P95 延迟：1200.000 ms
- Benchmark 评分耗时：38秒

## 失败样本

- `hard_memory_transient_03_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期不太想说话。
- `hard_memory_transient_03_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_transient_07_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期想安静。
- `hard_memory_transient_07_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_transient_11_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期不太想说话。
- `hard_memory_transient_11_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_transient_15_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期想安静。
- `hard_memory_transient_15_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_conflict_03_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_03_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_memory_conflict_07_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_07_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_memory_conflict_11_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_11_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_memory_conflict_15_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_15_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_card_ambiguous_time_03_task` / `time_parse_accuracy`：Expected time=2026-05-22T19:00:00+08:00, observed=2026-05-16T19:00:00+08:00, diff=8640.00m.
- `hard_card_ambiguous_time_03_task` / `participant_recall`：Participant recall 0/1.
- `hard_card_ambiguous_time_03_task` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.
- `hard_card_ambiguous_time_07_task` / `time_parse_accuracy`：Expected time=2026-05-26T19:00:00+08:00, observed=2026-05-20T19:00:00+08:00, diff=8640.00m.

## 问题排查与建议

### 排查过程

- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。
- 对 card 失败，检查对应 `input_id` 是否能通过提交返回的 fact id 找到 card，以及 card 是否停留在 processing/null。
- 对 memory 失败，检查写入 memory 的 source_ids 和内容是否来自临时输入或显式“不要当成长期习惯”的输入。

### 结论

- 标题关键词缺失说明即使 card 生成成功，也需要继续验证输入关键信息是否进入标题或结构化字段。
- Memory 写入边界仍需加强：临时状态或显式反例会被误写成长记忆。

### 修改建议

- 检查 submitInput 返回的 fact_id 到 TimelineCard 的关联路径，确认 card agent 完成后会把 status 从 processing 推进到 completed。
- 为 card agent 增加最小字段契约测试：title、status、source/fact 关联、关键主题词进入 title 或结构化字段。
- 在 memory write prompt / schema 中显式区分长期偏好、一次性状态和用户明确否定长期化的输入。
- 给 memory 写入增加 temporal_scope / confidence / source span 字段，低置信或短期事实默认不进入长期记忆。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-hard-case-challenge-diversity-audit`
- 数据集：`evals/datasets/hard_case_challenge`
- 观察适配器：`fixture`
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力
- 本地完整日志：`evals/runs/2026-05-13-hard-case-challenge-diversity-audit/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-hard-case-challenge-diversity-audit/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-hard-case-challenge-diversity-audit/outputs.jsonl`
- 场景样本数：112
- 评估任务数：112
- Benchmark 评分耗时：38秒
- 断言通过：496/576 （86.1%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_card_ambiguous_time_01` | `hard_card_ambiguous_time_01_task` | 通过 | 0 |
| `hard_card_ambiguous_time_02` | `hard_card_ambiguous_time_02_task` | 通过 | 0 |
| `hard_card_ambiguous_time_03` | `hard_card_ambiguous_time_03_task` | 未通过 | 3 |
| `hard_card_ambiguous_time_04` | `hard_card_ambiguous_time_04_task` | 通过 | 0 |
| `hard_card_ambiguous_time_05` | `hard_card_ambiguous_time_05_task` | 通过 | 0 |
| `hard_card_ambiguous_time_06` | `hard_card_ambiguous_time_06_task` | 通过 | 0 |
| `hard_card_ambiguous_time_07` | `hard_card_ambiguous_time_07_task` | 未通过 | 3 |
| `hard_card_ambiguous_time_08` | `hard_card_ambiguous_time_08_task` | 通过 | 0 |
| `hard_card_ambiguous_time_09` | `hard_card_ambiguous_time_09_task` | 通过 | 0 |
| `hard_card_ambiguous_time_10` | `hard_card_ambiguous_time_10_task` | 通过 | 0 |
| `hard_card_ambiguous_time_11` | `hard_card_ambiguous_time_11_task` | 未通过 | 3 |
| `hard_card_ambiguous_time_12` | `hard_card_ambiguous_time_12_task` | 通过 | 0 |
| `hard_card_ambiguous_time_13` | `hard_card_ambiguous_time_13_task` | 通过 | 0 |
| `hard_card_ambiguous_time_14` | `hard_card_ambiguous_time_14_task` | 通过 | 0 |
| `hard_card_ambiguous_time_15` | `hard_card_ambiguous_time_15_task` | 未通过 | 3 |
| `hard_card_ambiguous_time_16` | `hard_card_ambiguous_time_16_task` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_memory_transient_01` | `hard_memory_transient_01_task` | 通过 | 0 |
| `hard_memory_transient_02` | `hard_memory_transient_02_task` | 通过 | 0 |
| `hard_memory_transient_03` | `hard_memory_transient_03_task` | 未通过 | 2 |
| `hard_memory_transient_04` | `hard_memory_transient_04_task` | 通过 | 0 |
| `hard_memory_transient_05` | `hard_memory_transient_05_task` | 通过 | 0 |
| `hard_memory_transient_06` | `hard_memory_transient_06_task` | 通过 | 0 |
| `hard_memory_transient_07` | `hard_memory_transient_07_task` | 未通过 | 2 |
| `hard_memory_transient_08` | `hard_memory_transient_08_task` | 通过 | 0 |
| `hard_memory_transient_09` | `hard_memory_transient_09_task` | 通过 | 0 |
| `hard_memory_transient_10` | `hard_memory_transient_10_task` | 通过 | 0 |
| `hard_memory_transient_11` | `hard_memory_transient_11_task` | 未通过 | 2 |
| `hard_memory_transient_12` | `hard_memory_transient_12_task` | 通过 | 0 |
| `hard_memory_transient_13` | `hard_memory_transient_13_task` | 通过 | 0 |
| `hard_memory_transient_14` | `hard_memory_transient_14_task` | 通过 | 0 |
| `hard_memory_transient_15` | `hard_memory_transient_15_task` | 未通过 | 2 |
| `hard_memory_transient_16` | `hard_memory_transient_16_task` | 通过 | 0 |
| `hard_memory_conflict_01` | `hard_memory_conflict_01_task` | 通过 | 0 |
| `hard_memory_conflict_02` | `hard_memory_conflict_02_task` | 通过 | 0 |
| `hard_memory_conflict_03` | `hard_memory_conflict_03_task` | 未通过 | 2 |
| `hard_memory_conflict_04` | `hard_memory_conflict_04_task` | 通过 | 0 |
| `hard_memory_conflict_05` | `hard_memory_conflict_05_task` | 通过 | 0 |
| `hard_memory_conflict_06` | `hard_memory_conflict_06_task` | 通过 | 0 |
| `hard_memory_conflict_07` | `hard_memory_conflict_07_task` | 未通过 | 2 |
| `hard_memory_conflict_08` | `hard_memory_conflict_08_task` | 通过 | 0 |
| `hard_memory_conflict_09` | `hard_memory_conflict_09_task` | 通过 | 0 |
| `hard_memory_conflict_10` | `hard_memory_conflict_10_task` | 通过 | 0 |
| `hard_memory_conflict_11` | `hard_memory_conflict_11_task` | 未通过 | 2 |
| `hard_memory_conflict_12` | `hard_memory_conflict_12_task` | 通过 | 0 |
| `hard_memory_conflict_13` | `hard_memory_conflict_13_task` | 通过 | 0 |
| `hard_memory_conflict_14` | `hard_memory_conflict_14_task` | 通过 | 0 |
| `hard_memory_conflict_15` | `hard_memory_conflict_15_task` | 未通过 | 2 |
| `hard_memory_conflict_16` | `hard_memory_conflict_16_task` | 通过 | 0 |

#### PKM 整理

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_pkm_organization_01` | `hard_pkm_organization_01_task` | 通过 | 0 |
| `hard_pkm_organization_02` | `hard_pkm_organization_02_task` | 通过 | 0 |
| `hard_pkm_organization_03` | `hard_pkm_organization_03_task` | 未通过 | 4 |
| `hard_pkm_organization_04` | `hard_pkm_organization_04_task` | 通过 | 0 |
| `hard_pkm_organization_05` | `hard_pkm_organization_05_task` | 通过 | 0 |
| `hard_pkm_organization_06` | `hard_pkm_organization_06_task` | 通过 | 0 |
| `hard_pkm_organization_07` | `hard_pkm_organization_07_task` | 未通过 | 4 |
| `hard_pkm_organization_08` | `hard_pkm_organization_08_task` | 通过 | 0 |
| `hard_pkm_organization_09` | `hard_pkm_organization_09_task` | 通过 | 0 |
| `hard_pkm_organization_10` | `hard_pkm_organization_10_task` | 通过 | 0 |
| `hard_pkm_organization_11` | `hard_pkm_organization_11_task` | 未通过 | 4 |
| `hard_pkm_organization_12` | `hard_pkm_organization_12_task` | 通过 | 0 |
| `hard_pkm_organization_13` | `hard_pkm_organization_13_task` | 通过 | 0 |
| `hard_pkm_organization_14` | `hard_pkm_organization_14_task` | 通过 | 0 |
| `hard_pkm_organization_15` | `hard_pkm_organization_15_task` | 未通过 | 4 |
| `hard_pkm_organization_16` | `hard_pkm_organization_16_task` | 通过 | 0 |

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_retrieval_grounding_01` | `hard_retrieval_grounding_01_task` | 通过 | 0 |
| `hard_retrieval_grounding_02` | `hard_retrieval_grounding_02_task` | 通过 | 0 |
| `hard_retrieval_grounding_03` | `hard_retrieval_grounding_03_task` | 未通过 | 2 |
| `hard_retrieval_grounding_04` | `hard_retrieval_grounding_04_task` | 通过 | 0 |
| `hard_retrieval_grounding_05` | `hard_retrieval_grounding_05_task` | 通过 | 0 |
| `hard_retrieval_grounding_06` | `hard_retrieval_grounding_06_task` | 通过 | 0 |
| `hard_retrieval_grounding_07` | `hard_retrieval_grounding_07_task` | 未通过 | 2 |
| `hard_retrieval_grounding_08` | `hard_retrieval_grounding_08_task` | 通过 | 0 |
| `hard_retrieval_grounding_09` | `hard_retrieval_grounding_09_task` | 通过 | 0 |
| `hard_retrieval_grounding_10` | `hard_retrieval_grounding_10_task` | 通过 | 0 |
| `hard_retrieval_grounding_11` | `hard_retrieval_grounding_11_task` | 未通过 | 2 |
| `hard_retrieval_grounding_12` | `hard_retrieval_grounding_12_task` | 通过 | 0 |
| `hard_retrieval_grounding_13` | `hard_retrieval_grounding_13_task` | 通过 | 0 |
| `hard_retrieval_grounding_14` | `hard_retrieval_grounding_14_task` | 通过 | 0 |
| `hard_retrieval_grounding_15` | `hard_retrieval_grounding_15_task` | 未通过 | 2 |
| `hard_retrieval_grounding_16` | `hard_retrieval_grounding_16_task` | 通过 | 0 |

#### 日程刷新

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_schedule_router_01` | `hard_schedule_router_01_task` | 通过 | 0 |
| `hard_schedule_router_02` | `hard_schedule_router_02_task` | 通过 | 0 |
| `hard_schedule_router_03` | `hard_schedule_router_03_task` | 未通过 | 3 |
| `hard_schedule_router_04` | `hard_schedule_router_04_task` | 通过 | 0 |
| `hard_schedule_router_05` | `hard_schedule_router_05_task` | 通过 | 0 |
| `hard_schedule_router_06` | `hard_schedule_router_06_task` | 通过 | 0 |
| `hard_schedule_router_07` | `hard_schedule_router_07_task` | 未通过 | 3 |
| `hard_schedule_router_08` | `hard_schedule_router_08_task` | 通过 | 0 |
| `hard_schedule_router_09` | `hard_schedule_router_09_task` | 通过 | 0 |
| `hard_schedule_router_10` | `hard_schedule_router_10_task` | 通过 | 0 |
| `hard_schedule_router_11` | `hard_schedule_router_11_task` | 未通过 | 3 |
| `hard_schedule_router_12` | `hard_schedule_router_12_task` | 通过 | 0 |
| `hard_schedule_router_13` | `hard_schedule_router_13_task` | 通过 | 0 |
| `hard_schedule_router_14` | `hard_schedule_router_14_task` | 通过 | 0 |
| `hard_schedule_router_15` | `hard_schedule_router_15_task` | 未通过 | 3 |
| `hard_schedule_router_16` | `hard_schedule_router_16_task` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `hard_super_agent_boundary_01` | `hard_super_agent_boundary_01_task` | 通过 | 0 |
| `hard_super_agent_boundary_02` | `hard_super_agent_boundary_02_task` | 通过 | 0 |
| `hard_super_agent_boundary_03` | `hard_super_agent_boundary_03_task` | 未通过 | 4 |
| `hard_super_agent_boundary_04` | `hard_super_agent_boundary_04_task` | 通过 | 0 |
| `hard_super_agent_boundary_05` | `hard_super_agent_boundary_05_task` | 通过 | 0 |
| `hard_super_agent_boundary_06` | `hard_super_agent_boundary_06_task` | 通过 | 0 |
| `hard_super_agent_boundary_07` | `hard_super_agent_boundary_07_task` | 未通过 | 4 |
| `hard_super_agent_boundary_08` | `hard_super_agent_boundary_08_task` | 通过 | 0 |
| `hard_super_agent_boundary_09` | `hard_super_agent_boundary_09_task` | 通过 | 0 |
| `hard_super_agent_boundary_10` | `hard_super_agent_boundary_10_task` | 通过 | 0 |
| `hard_super_agent_boundary_11` | `hard_super_agent_boundary_11_task` | 未通过 | 4 |
| `hard_super_agent_boundary_12` | `hard_super_agent_boundary_12_task` | 通过 | 0 |
| `hard_super_agent_boundary_13` | `hard_super_agent_boundary_13_task` | 通过 | 0 |
| `hard_super_agent_boundary_14` | `hard_super_agent_boundary_14_task` | 通过 | 0 |
| `hard_super_agent_boundary_15` | `hard_super_agent_boundary_15_task` | 未通过 | 4 |
| `hard_super_agent_boundary_16` | `hard_super_agent_boundary_16_task` | 通过 | 0 |

## 数据质量审计

- 总体分：0.550
- 语言一致性：0.900
- Persona 可信度：0.400
- 输入自然度：0.500
- Oracle 一致性：0.850
- 审计结论：数据集的主要缺陷在于高度的模板化和重复性。虽然语言为中文且任务设计（oracle一致性）基本合理，但不同persona和案例的输入、上下文缺乏实质性的领域差异和自然变化，像是由同一套模板批量生成。这严重损害了数据的自然度、persona的可信度以及作为评估基准的多样性，因此整体评分较低，不适合作为有效的smoke/benchmark数据，需要在内容多样性上进行大幅重构。
- 覆盖备注：数据集覆盖了7个评估任务家族，每个家族有16个案例，结构完整。；抽样策略确保了每个家族都有案例被审查。；主要问题在于输入内容和上下文的高度模板化和重复性，这严重影响了数据的自然度和评估效度。

### 审计问题

- `ALL` / high：输入和上下文内容高度模板化、重复。不同persona（职业、城市）的输入几乎只是替换关键词（如‘预算复盘’、‘饮食限制’、‘临时情绪’），句式结构和表达逻辑完全相同。；建议：为不同职业和背景的persona设计真正体现其领域思维和语言习惯的输入内容。例如，数据分析师的碎碎念应更偏向数据、指标；老师的碎碎念可能涉及学生、教案。避免使用完全相同的句式模板。
- `ALL` / medium：上下文流（context）在不同案例间几乎完全相同，只是顺序和极少数词汇有变化。这导致输入流缺乏多样性，像是批量生成的背景噪音，而非有机的对话历史。；建议：根据每个案例的具体任务和persona，设计独特且相关的上下文。上下文应自然地引出或与核心输入（input）形成有意义的互动，而不是通用的‘注意事项’列表。
- `hard_memory_transient_01` / medium：输入‘作为数据分析师，我临时问一下饮食限制 的写法...’与数据分析师的职业身份关联牵强，更像是为了填充‘职业特色’而硬凑的句子。；建议：移除或替换为与数据分析师日常工作更相关的碎碎念，例如关于数据清洗、指标口径的临时想法。
- `hard_super_agent_boundary_01` / low：ground_truth_world中的记忆内容（‘不要海鲜、少糖’）在input_stream中并未明确出现，仅存在于ground_truth中。这可能导致评估时出现‘oracle泄漏’的嫌疑，即评估标准依赖了输入中未提供的隐藏信息。；建议：确保ground_truth中的关键信息（如记忆内容）必须在input_stream的某处有明确来源或依据，以保证评估的公平性和可追溯性。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `hard_memory_transient_01` | 0.600 | 核心任务（区分临时状态与长期偏好）设计合理，但输入和上下文高度模板化，persona的职业特色未体现。 |
| `hard_memory_conflict_01` | 0.650 | 记忆冲突场景清晰，评估标准明确。但上下文流与其他案例雷同，降低了测试的多样性。 |
| `hard_card_ambiguous_time_01` | 0.700 | 时间纠正任务明确，ground_truth与输入一致。问题同样在于上下文的通用性过强。 |
| `hard_retrieval_grounding_01` | 0.700 | 检索任务要求基于记录回答，设计良好。但persona和输入流的模板化问题依然存在。 |
| `hard_super_agent_boundary_01` | 0.500 | 只读边界测试有意义，但ground_truth中的记忆内容在输入中无依据，存在潜在的数据一致性问题。 |
| `hard_schedule_router_01` | 0.600 | 测试日程路由的‘跳过’逻辑合理。输入‘今天有点累...’是自然的，但后续上下文再次落入通用模板。 |
| `hard_pkm_organization_01` | 0.650 | PKM组织任务清晰，评估标准具体。输入内容本身是合理的指令，但缺乏与persona背景的深度结合。 |
| `hard_memory_transient_02` | 0.550 | 与01号案例任务相同，仅persona和少数词汇变化，属于重复性测试，价值有限。 |
| `hard_memory_conflict_02` | 0.600 | 同01号案例，仅咖啡规则细节不同。模板化问题严重。 |
| `hard_card_ambiguous_time_02` | 0.650 | 任务与01号案例同构，仅人物和地点变化。 |
| `hard_retrieval_grounding_02` | 0.650 | 任务与01号案例同构。 |
| `hard_super_agent_boundary_02` | 0.500 | 任务与01号案例同构，且同样存在ground_truth信息在输入中无来源的问题。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：16
- 输入条数：1568
- Eval task 数：112
- Case family 分布：hard_case_card_ambiguous_time=16，hard_case_memory_conflict=16，hard_case_memory_transient=16，hard_case_pkm_organization=16，hard_case_retrieval_grounding=16，hard_case_schedule_router=16，hard_case_super_agent_boundary=16
- Task type 分布：card_extraction=16，memory_write=32，pkm_organization=16，retrieval_qa=16，schedule_refresh=16，super_agent_qa=16

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `hard_u_01` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。<br>刚在上海路上想起预算复盘，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_02` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。<br>刚在深圳路上想起饮食限制，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_03` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。<br>刚在北京路上想起临时情绪，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_04` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。<br>刚在杭州路上想起客户反馈，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_05` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。<br>刚在上海路上想起项目周报，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_06` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。<br>刚在深圳路上想起日程改期，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_07` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。<br>刚在北京路上想起证据引用，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_08` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。<br>刚在杭州路上想起PKM 归档，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_09` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。<br>刚在上海路上想起工具调用，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_10` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。<br>刚在深圳路上想起时间解析，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_11` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。<br>刚在北京路上想起冲突记忆，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_12` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。<br>刚在杭州路上想起只读问答，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_13` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。<br>刚在上海路上想起来源追溯，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_14` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。<br>刚在深圳路上想起会议提醒，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
| `hard_u_15` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。<br>刚在北京路上想起预算复盘，先碎碎念一句：今天这个状态大概只是被会打断了，不代表长期习惯。 |
| `hard_u_16` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。<br>刚在杭州路上想起饮食限制，先碎碎念一句：我只是当下有点烦，长期偏好还是要看反复出现的记录。 |
