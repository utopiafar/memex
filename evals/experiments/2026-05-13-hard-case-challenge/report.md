# Memex Agent Eval 实验报告

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 本次覆盖 112 个 case、112 个 eval task，断言通过率 86.1%。
- 失败断言数：80；Token 总量：251440；LLM 调用次数：112；工具调用次数：16。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.600。
- 审计摘要：数据集在语言和基础persona设置上合格，但存在根本性设计缺陷：1) 样本覆盖不全，无法评估整体；2) 评估任务存在严重的oracle泄漏，将复杂推理任务降级为简单指令遵循；3) 案例内容高度模板化和重复，缺乏自然对话的多样性和复杂性。因此，当前数据集不适合作为有效的Agent能力评估基准，需要重新设计任务逻辑并大幅扩充和多样化案例内容。
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
| Benchmark 评分耗时 | 35秒 |

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
- Benchmark 评分耗时：35秒

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

- 运行 ID：`2026-05-13-hard-case-challenge`
- 数据集：`evals/datasets/hard_case_challenge`
- 观察适配器：`fixture`
- 本地完整日志：`evals/runs/2026-05-13-hard-case-challenge/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-hard-case-challenge/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-hard-case-challenge/outputs.jsonl`
- 场景样本数：112
- 评估任务数：112
- Benchmark 评分耗时：35秒
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

- 总体分：0.600
- 语言一致性：0.700
- Persona 可信度：0.800
- 输入自然度：0.500
- Oracle 一致性：0.300
- 审计结论：数据集在语言和基础persona设置上合格，但存在根本性设计缺陷：1) 样本覆盖不全，无法评估整体；2) 评估任务存在严重的oracle泄漏，将复杂推理任务降级为简单指令遵循；3) 案例内容高度模板化和重复，缺乏自然对话的多样性和复杂性。因此，当前数据集不适合作为有效的Agent能力评估基准，需要重新设计任务逻辑并大幅扩充和多样化案例内容。
- 覆盖备注：样本仅覆盖了 `memory_transient` 和 `memory_conflict` 两个家族，其余5个家族（如 `card_ambiguous_time`, `pkm_organization` 等）无样本，无法评估。；提供的24个样本案例在结构和内容上高度同质化，可能无法代表整个数据集的多样性。

### 审计问题

- `ALL_SAMPLE_CASES` / high：样本覆盖严重不均衡，无法评估数据集整体质量。；建议：需要从所有7个案例家族中抽取代表性样本进行审查。
- `hard_memory_transient_01` / high：Oracle泄漏：`eval_tasks.expected` 中的 `must_write` 和 `must_not_write` 要求直接、明确地源自 `input_stream` 的第一条消息（用户指令），使得任务变成了简单的指令遵循，而非基于隐藏真相的推理。；建议：评估任务应基于 `ground_truth_world` 中隐含的、需要从对话历史中推断出的状态或规则，而非直接复述用户明确给出的指令。
- `hard_memory_transient_01` / medium：输入内容高度模板化和重复。所有 `memory_transient` 案例的第一条输入都遵循“表达临时情绪/状态 + 强调重要会议提前一天提醒”的固定模式，且后续上下文（context）也高度相似，只是替换了关键词（如“预算复盘”、“饮食限制”）。；建议：增加用户表达的多样性和自然度，避免使用“不要把这个写成长期偏好”这类直接揭示任务目标的元指令。上下文应更贴近真实、连贯的对话流。
- `hard_memory_conflict_01` / high：Oracle泄漏：`eval_tasks.expected` 中的 `conflicts` 要求直接对应 `input_stream` 第一条消息中用户明确陈述的新旧偏好对比，任务本质是信息提取而非冲突消解推理。；建议：冲突场景应设计得更隐蔽，例如新偏好在对话中逐渐浮现，或旧偏好存在于更早的、未直接引用的记忆中，需要Agent进行关联和判断。
- `hard_memory_conflict_01` / medium：所有 `memory_conflict` 案例都围绕“咖啡偏好”这一单一主题，且输入表述虽有变化但语义相同，缺乏多样性。；建议：引入更多类型的偏好或事实冲突场景（如日程安排、工作习惯、饮食限制等）。
- `ALL_CASES` / medium：`context` 流中的许多消息包含“不要影响 memory_transient 的判断”、“先不用写成长记忆”等元指令，这在真实用户交互中极不自然，像是给评估系统的提示而非用户对话。；建议：移除所有元指令，让上下文成为纯粹的用户与Agent或其他人的自然对话、笔记或状态更新。
- `ALL_CASES` / low：时间跨度设置（2026年5月）略显刻意，且每天都有密集输入，不太符合一般用户的实际使用频率。；建议：时间设置可以更随机，输入频率可以更符合真实场景（如某些天无输入）。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `hard_memory_transient_01` | 0.400 | 典型的模板化案例，存在严重的oracle泄漏问题。评估任务直接复述用户指令，无法测试Agent的推理能力。 |
| `hard_memory_transient_02` | 0.400 | 与case 01结构完全相同，仅替换了职业、城市和少数词汇，问题性质一致。 |
| `hard_memory_conflict_01` | 0.300 | 冲突解决任务设计失败，答案直接来自用户输入。咖啡主题重复。 |
| `hard_memory_conflict_02` | 0.300 | 与conflict case 01本质相同，仅输入表述稍有变化，核心问题未变。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：16
- 输入条数：1568
- Eval task 数：112
- Case family 分布：hard_case_card_ambiguous_time=16，hard_case_memory_conflict=16，hard_case_memory_transient=16，hard_case_pkm_organization=16，hard_case_retrieval_grounding=16，hard_case_schedule_router=16，hard_case_super_agent_boundary=16
- Task type 分布：card_extraction=16，memory_write=32，pkm_organization=16，retrieval_qa=16，schedule_refresh=16，super_agent_qa=16

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `hard_u_01` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。<br>今天在上海处理预算复盘，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_02` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。<br>今天在深圳处理饮食限制，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_03` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。<br>今天在北京处理临时情绪，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_04` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。<br>今天在杭州处理客户反馈，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_05` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。<br>今天在上海处理项目周报，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_06` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。<br>今天在深圳处理日程改期，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_07` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。<br>今天在北京处理证据引用，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_08` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。<br>今天在杭州处理PKM 归档，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_09` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。<br>今天在上海处理工具调用，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_10` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。<br>今天在深圳处理时间解析，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_11` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。<br>今天在北京处理冲突记忆，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_12` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。<br>今天在杭州处理只读问答，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_13` | 数据分析师 | 上海 | zh-CN | 7 | 98 | 7 | 今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。<br>今天在上海处理来源追溯，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_14` | 跨境电商运营 | 深圳 | zh-CN | 7 | 98 | 7 | 刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。<br>今天在深圳处理会议提醒，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_15` | 老师 | 北京 | zh-CN | 7 | 98 | 7 | 今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。<br>今天在北京处理预算复盘，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
| `hard_u_16` | 产品经理 | 杭州 | zh-CN | 7 | 98 | 7 | 下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。<br>今天在杭州处理饮食限制，有点碎，但这只是背景，不要影响 memory_transient 的判断。 |
