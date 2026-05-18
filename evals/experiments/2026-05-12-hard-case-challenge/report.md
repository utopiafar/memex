# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/hard_case_challenge`。

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 本次覆盖 56 个 case、56 个 eval task，断言通过率 86.1%。
- 失败断言数：40；Token 总量：123480；LLM 调用次数：56；工具调用次数：8。
- 主要失败项：
  - `hard_memory_transient_03_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期不太想说话。
  - `hard_memory_transient_03_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
  - `hard_memory_transient_07_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期想安静。

## 执行补充

- 这是 Hard Case Challenge Set，不追求全绿；`fixture_observed` 中保留了 14 个种子失败，用来验证失败样本、分场景指标和 error analysis 是否能稳定暴露问题。
- 数据质量审计结果：语言一致性 1.0，oracle 一致性 0.9，输入自然度 0.8；主要剩余问题是同类挑战仍偏模板化，后续扩展应加入更多类型的偏好冲突、更多相对时间表达和更复杂的多条件检索。
- 当前失败集中在临时状态误写、冲突记忆未更新、相对时间/实体抽取、Super Agent 只读边界、日程误刷新和 PKM 路径错误，符合 hard set 预期。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 8 |
| Case | 56 |
| 用户输入 | 56 |
| Eval task | 56 |
| 断言 | 288 |
| LLM 调用 | 56 |
| Tool 调用 | 8 |
| 实际 token | 123480 |
| Benchmark 评分耗时 | 25秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 123480 tokens；同规模复跑可先按 98784-148176 tokens 预留。

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
| Card 抽取 | 50 | 56 | 89.3% | 0.750 |
| 记忆写入 | 40 | 48 | 83.3% | 0.906 |
| PKM 整理 | 32 | 40 | 80.0% | 0.750 |
| 检索问答 | 60 | 64 | 93.8% | 1.000 |
| 日程刷新 | 34 | 40 | 85.0% | 1.000 |
| Super Agent 问答 | 32 | 40 | 80.0% | 0.875 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 8 | 8 | 100.0% | - |
| Card 抽取 | 字段抽取 | `location_accuracy` | 8 | 8 | 100.0% | - |
| Card 抽取 | 字段抽取 | `participant_recall` | 6 | 8 | 75.0% | 0.750 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 6 | 8 | 75.0% | 0.750 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 8 | 8 | 100.0% | - |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 6 | 8 | 75.0% | 0.750 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 8 | 8 | 100.0% | - |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | 6 | 8 | 75.0% | 0.750 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | 6 | 8 | 75.0% | - |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | 6 | 8 | 75.0% | - |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | 8 | 8 | 100.0% | - |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | 6 | 8 | 75.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 6 | 8 | 75.0% | 0.750 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 6 | 8 | 75.0% | - |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 6 | 8 | 75.0% | - |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 8 | 8 | 100.0% | - |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 6 | 8 | 75.0% | - |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 6 | 8 | 75.0% | 1.000 |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 0 | 2 | 0.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 6 | 6 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 12 | 16 | 75.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 14 | 14 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 6 | 6 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 6 | 6 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 14 | 16 | 87.5% | 0.875 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 6 | 8 | 75.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 6 | 8 | 75.0% | 0.875 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 6 | 8 | 75.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 8 | 8 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 4 | 4 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 6 | 8 | 75.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 4 | 4 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：56
- 工具调用次数：8
- Token 总量：123480
- 单次 LLM 平均 token：2205.000
- 平均延迟：1046.667 ms
- P95 延迟：1200.000 ms
- Benchmark 评分耗时：25秒

## 失败样本

- `hard_memory_transient_03_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期不太想说话。
- `hard_memory_transient_03_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_transient_07_task` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory temporary_mood: 用户长期想安静。
- `hard_memory_transient_07_task` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `hard_memory_conflict_03_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_03_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_memory_conflict_07_task` / `memory_must_write_recall`：Missing required memory coffee_latest.
- `hard_memory_conflict_07_task` / `memory_conflict_handling`：Conflict latestActive=false oldInactive=false.
- `hard_card_ambiguous_time_03_task` / `time_parse_accuracy`：Expected time=2026-05-23T19:00:00+08:00, observed=2026-05-16T19:00:00+08:00, diff=10080.00m.
- `hard_card_ambiguous_time_03_task` / `participant_recall`：Participant recall 0/1.
- `hard_card_ambiguous_time_03_task` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.
- `hard_card_ambiguous_time_07_task` / `time_parse_accuracy`：Expected time=2026-05-27T19:00:00+08:00, observed=2026-05-20T19:00:00+08:00, diff=10080.00m.
- `hard_card_ambiguous_time_07_task` / `participant_recall`：Participant recall 0/1.
- `hard_card_ambiguous_time_07_task` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：吃饭.
- `hard_retrieval_grounding_03_task` / `unsupported_claim_absence`：Prohibited claims present: 5月14日.
- `hard_retrieval_grounding_03_task` / `abstention_accuracy`：Expected should_abstain=true, observed_abstained=false.
- `hard_retrieval_grounding_07_task` / `unsupported_claim_absence`：Prohibited claims present: 5月14日.
- `hard_retrieval_grounding_07_task` / `abstention_accuracy`：Expected should_abstain=true, observed_abstained=false.
- `hard_super_agent_boundary_03_task` / `unsupported_claim_absence`：Prohibited claims present: 已经帮你更新.
- `hard_super_agent_boundary_03_task` / `prohibited_tool_absence`：Prohibited tools called: update_memory.

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

- 运行 ID：`2026-05-12-hard-case-challenge`
- 数据集：`evals/datasets/hard_case_challenge`
- 观察适配器：`fixture`
- 场景样本数：56
- 评估任务数：56
- Benchmark 评分耗时：25秒
- 断言通过：248/288 （86.1%）

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
| `hard_memory_conflict_01` | `hard_memory_conflict_01_task` | 通过 | 0 |
| `hard_memory_conflict_02` | `hard_memory_conflict_02_task` | 通过 | 0 |
| `hard_memory_conflict_03` | `hard_memory_conflict_03_task` | 未通过 | 2 |
| `hard_memory_conflict_04` | `hard_memory_conflict_04_task` | 通过 | 0 |
| `hard_memory_conflict_05` | `hard_memory_conflict_05_task` | 通过 | 0 |
| `hard_memory_conflict_06` | `hard_memory_conflict_06_task` | 通过 | 0 |
| `hard_memory_conflict_07` | `hard_memory_conflict_07_task` | 未通过 | 2 |
| `hard_memory_conflict_08` | `hard_memory_conflict_08_task` | 通过 | 0 |

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

## 数据质量审计

- 总体分：0.700
- 语言一致性：1.000
- Persona 可信度：0.800
- 输入自然度：0.800
- Oracle 一致性：0.900
- 审计结论：数据集语言一致，persona和输入基本自然，oracle内部一致性良好。主要问题在于样本内同一家族的案例内容高度重复和模板化，这会限制评估的多样性和全面性，可能导致对Agent能力的评估产生偏差。因此整体评分未达到0.8的基准线，建议在扩大规模前先解决内容多样性问题。
- 覆盖备注：样本覆盖了所有7个案例家族和6种任务类型，但样本内同一家族的案例内容高度重复。

### 审计问题

- `hard_memory_transient_01 至 hard_memory_transient_08` / medium：内容高度模板化与重复；建议：应丰富临时情绪的具体原因和长期规则（如会议提醒）的具体表述，避免仅替换情绪词和日期。
- `hard_memory_conflict_01 至 hard_memory_conflict_08` / medium：咖啡偏好更新场景高度重复；建议：可引入其他类型的偏好冲突（如饮食、锻炼习惯、工作时间段等），并设计更复杂的更新逻辑（如分时段、有条件限制）。
- `hard_card_ambiguous_time_01 至 hard_card_ambiguous_time_08` / medium：事件修正场景单一；建议：可设计更多样的模糊时间指代（如“下周三下午”、“月底”）和不同类型的事件（会议、约会、截止日期），而不仅限于“和XX吃饭”。
- `hard_retrieval_grounding_01 至 hard_retrieval_grounding_04` / low：检索问题模式相似；建议：可设计更复杂的检索问题，如涉及多条件组合（时间+人物+主题）、模糊指代或需要跨多个记忆片段进行推理的问题。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `hard_memory_transient_01` | 0.800 | 输入自然，任务清晰地区分了临时状态和长期规则，oracle一致。但作为模板案例的起点，其重复性拉低了整体多样性评分。 |
| `hard_memory_conflict_01` | 0.800 | 偏好更新场景合理，任务要求明确（写入新偏好并处理冲突）。但后续案例过于相似。 |
| `hard_card_ambiguous_time_01` | 0.800 | 时间修正指令明确，ground truth事件与eval task中的期望提取字段完全对应。但场景缺乏变化。 |
| `hard_retrieval_grounding_03` | 0.900 | 这是一个很好的阴性案例（ground truth为空），测试了模型在证据不足时是否应该拒绝回答，符合“证据不足时说不确定”的偏好设置。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：8
- 输入条数：56
- Eval task 数：56
- Case family 分布：hard_case_card_ambiguous_time=8，hard_case_memory_conflict=8，hard_case_memory_transient=8，hard_case_pkm_organization=8，hard_case_retrieval_grounding=8，hard_case_schedule_router=8，hard_case_super_agent_boundary=8
- Task type 分布：card_extraction=8，memory_write=16，pkm_organization=8，retrieval_qa=8，schedule_refresh=8，super_agent_qa=8

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `hard_u_01` | 数据分析师 | 上海 | zh-CN | 7 | 7 | 7 | 今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。<br>我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。 |
| `hard_u_02` | 跨境电商运营 | 深圳 | zh-CN | 7 | 7 | 7 | 今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。<br>上个月说过早上也不要咖啡，现在改一下：上午一小杯可以，午后不要。 |
| `hard_u_03` | 老师 | 北京 | zh-CN | 7 | 7 | 7 | 我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。<br>咖啡偏好更新下，之前完全不喝是旧信息，现在只允许上午喝。 |
| `hard_u_04` | 产品经理 | 杭州 | zh-CN | 7 | 7 | 7 | 今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。<br>之前那条“不要咖啡”过期了，最近早上可以喝，下午保持不喝。 |
| `hard_u_05` | 数据分析师 | 上海 | zh-CN | 7 | 7 | 7 | 今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。<br>我又开始喝咖啡了，但限定上午，下午喝会影响睡眠。 |
| `hard_u_06` | 跨境电商运营 | 深圳 | zh-CN | 7 | 7 | 7 | 刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。<br>别再按“完全不喝咖啡”理解我了，现在是上午可以、下午不行。 |
| `hard_u_07` | 老师 | 北京 | zh-CN | 7 | 7 | 7 | 今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。<br>咖啡这件事修正一下：早上开会前可以一杯，下午还是避免。 |
| `hard_u_08` | 产品经理 | 杭州 | zh-CN | 7 | 7 | 7 | 下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。<br>以前不喝咖啡是那阵子胃不舒服，现在上午可以喝一杯。 |
