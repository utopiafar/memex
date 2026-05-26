# Memex Agent Eval 实验报告

## 结论

- 断言全绿，适合作为 grader smoke；如需证明 Agent 能力，应接真实 replay 或补数据审计。
- 证据等级：fixture/grader smoke，主要验证 grader、报告和指标聚合能否工作。
- 本次覆盖 8 个 case、80 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：1107232；LLM 调用次数：248；工具调用次数：136。
- 观察数据耗时：1小时16分48秒；Benchmark 评分耗时：0秒。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/full_chain_journey_scale_v2`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 8 |
| Case | 8 |
| 用户输入 | 2560 |
| Eval task | 80 |
| 断言 | 824 |
| LLM 调用 | 248 |
| Tool 调用 | 136 |
| 实际 token | 1107232 |
| 观察数据耗时 | 1小时16分48秒 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 1107232 tokens；同规模复跑可先按 885786-1328678 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| PKM 整理 | 检查 PKM 条目是否放到正确路径、保留关键信息并引用来源。 |
| 检索问答 | 检查查询时是否召回正确来源，并基于证据回答。 |
| 日程刷新 | 检查日程相关输入是否正确 skip / dirty / refresh，并控制不必要刷新。 |
| Super Agent 问答 | 检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。 |
| 路由 / 工具调用 | 检查路由标签、工具选择、工具参数和禁止工具调用。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| Card 抽取 | 字段抽取 | `card_field_constraint_accuracy` | 指定 card 字段是否包含应保留的细节。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 延迟 | `input_to_card_latency` | 从用户输入到 card 产物的延迟是否在预算内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | PKM 条目是否保留关键事实、结论和下一步。 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | PKM 条目是否没有写入明确禁止的临时信息。 |
| PKM 整理 | 时效性 | `pkm_update_freshness` | PKM 条目是否反映最新输入或更新。 |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | PKM 条目是否保留期望来源 id。 |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | PKM 条目数量是否符合合并/拆分预期。 |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | PKM 条目路径是否包含期望目录或项目名。 |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 回答是否利用用户偏好、习惯或上下文做个性化表达。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 是否执行了预期 App 行为类型，例如记录、回看、评论、刷新和问答。 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 平均每条用户输入消耗的 token 是否在预算内。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | Trace 是否包含期望的关键事件或工具调用节点。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 是否包含足够的用户修正、偏好更新或冲突覆盖样本。 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | trace 和操作记录是否覆盖本轮预期功能触发点。 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 是否包含足够的临时情绪、一次性尝试、OCR 噪声等不应长期化输入。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 用户旅程是否覆盖捕获、组织、回看、追问、修正和洞察等阶段。 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 模拟用户操作是否跨越足够多天，避免只测单日短上下文。 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 全链路 replay 中真实提交记录的数量是否达到本轮样本要求。 |
| 成本 / Trace | 用户旅程覆盖 | `scenario_family_coverage` | 输入是否覆盖本 persona 预期的工作、生活、健康、家庭、财务等场景族。 |
| 成本 / Trace | 用户画像区分 | `persona_specificity_coverage` | trace 摘要是否保留能区分该用户职业、城市、项目或习惯的特征。 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 任务失败比例是否低于预算。 |
| 成本 / Trace | 稳定性 | `retry_rate` | 任务 retry 比例是否低于预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 成本 / Trace | 跨日连续性 | `cross_day_continuity_coverage` | 跨日输入之间是否形成足够的连续引用、复盘或后续行动链。 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 输入是否覆盖文本、语音转写、OCR/剪贴等不同真实来源形态。 |
| 成本 / Trace | 追问闭环 | `follow_up_query_coverage` | 是否覆盖用户回看后继续追问、澄清或要求综合总结的闭环。 |
| 成本 / Trace | 队列等待 | `queue_idle_time` | 任务队列等待或空转时间是否在预算内。 |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 日程刷新决策是否等于期望的 skip / dirty / refresh。 |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 必须刷新时是否没有漏掉刷新。 |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 无需刷新时是否没有触发重刷新。 |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 是否没有对同一日程变化触发重复刷新。 |
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
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 检索是否应用了期望的人物、时间、类型或项目过滤条件。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_call_minimality` | 工具调用数量是否没有超过完成任务所需的上限。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 路由分类是否等于期望标签。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 96 | 96 | 100.0% | 1.000 |
| 成本 / Trace | 176 | 176 | 100.0% | 0.975 |
| 记忆写入 | 104 | 104 | 100.0% | 1.000 |
| PKM 整理 | 80 | 80 | 100.0% | 1.000 |
| 检索问答 | 168 | 168 | 100.0% | 1.000 |
| 日程刷新 | 56 | 56 | 100.0% | 1.000 |
| Super Agent 问答 | 96 | 96 | 100.0% | 1.000 |
| 路由 / 工具调用 | 48 | 48 | 100.0% | - |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 16 | 16 | 100.0% | - |
| Card 抽取 | 字段抽取 | `card_field_constraint_accuracy` | 16 | 16 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 16 | 16 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 16 | 16 | 100.0% | - |
| Card 抽取 | 延迟 | `input_to_card_latency` | 16 | 16 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 16 | 16 | 100.0% | - |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | 16 | 16 | 100.0% | 1.000 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | 8 | 8 | 100.0% | - |
| PKM 整理 | 时效性 | `pkm_update_freshness` | 16 | 16 | 100.0% | - |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | 16 | 16 | 100.0% | - |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | 8 | 8 | 100.0% | - |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | 16 | 16 | 100.0% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 8 | 8 | 100.0% | 1.000 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 8 | 8 | 100.0% | - |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 8 | 8 | 100.0% | 0.800 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 8 | 8 | 100.0% | 0.775 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 16 | 16 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 用户旅程覆盖 | `scenario_family_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 用户画像区分 | `persona_specificity_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 跨日连续性 | `cross_day_continuity_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 追问闭环 | `follow_up_query_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 队列等待 | `queue_idle_time` | 8 | 8 | 100.0% | - |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 8 | 8 | 100.0% | - |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 8 | 8 | 100.0% | - |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 8 | 8 | 100.0% | - |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 8 | 8 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 16 | 16 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 24 | 24 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 16 | 16 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 16 | 16 | 100.0% | - |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 32 | 32 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 24 | 24 | 100.0% | - |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 8 | 8 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 8 | 8 | 100.0% | 1.000 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 32 | 32 | 100.0% | - |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 16 | 16 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 16 | 16 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_call_minimality` | 16 | 16 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 16 | 16 | 100.0% | - |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 8 | 8 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：248
- 工具调用次数：136
- Token 总量：1107232
- 单次 LLM 平均 token：4464.645
- 平均延迟：979.764 ms
- P95 延迟：1455.000 ms
- 观察数据耗时：1小时16分48秒
- Case 观察耗时累计：1小时16分48秒
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-16-full-chain-journey-scale-v2`
- 数据集：`evals/datasets/full_chain_journey_scale_v2`
- 观察适配器：`fixture`
- 证据等级：fixture/grader smoke，主要验证 grader、报告和指标聚合能否工作
- 本地完整日志：`evals/runs/2026-05-16-full-chain-journey-scale-v2/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-16-full-chain-journey-scale-v2/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-16-full-chain-journey-scale-v2/outputs.jsonl`
- 场景样本数：8
- 评估任务数：80
- 观察数据耗时：1小时16分48秒
- Benchmark 评分耗时：0秒
- 断言通过：824/824 （100.0%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_01` | `journey_scale_v2_01_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_card_cross_domain_review` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_card_project_milestone` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_card_cross_domain_review` | 通过 | 0 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_cost` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_cost` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_cost` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_cost` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_cost` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_cost` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_cost` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_cost` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_memory` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_memory` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_memory` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_memory` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_memory` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_memory` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_memory` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_memory` | 通过 | 0 |

#### PKM 整理

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_pkm` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_pkm` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_pkm` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_pkm` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_pkm` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_pkm` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_pkm` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_pkm` | 通过 | 0 |

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_retrieval` | 通过 | 0 |
| `journey_scale_v2_01` | `journey_scale_v2_01_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_retrieval` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_retrieval` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_retrieval` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_retrieval` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_retrieval` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_retrieval` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_retrieval_followup` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_retrieval` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_retrieval_followup` | 通过 | 0 |

#### 日程刷新

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_schedule` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_schedule` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_schedule` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_schedule` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_schedule` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_schedule` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_schedule` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_schedule` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_super_agent` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_super_agent` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_super_agent` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_super_agent` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_super_agent` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_super_agent` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_super_agent` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_super_agent` | 通过 | 0 |

#### 路由 / 工具调用

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_scale_v2_01` | `journey_scale_v2_01_tool_route` | 通过 | 0 |
| `journey_scale_v2_02` | `journey_scale_v2_02_tool_route` | 通过 | 0 |
| `journey_scale_v2_03` | `journey_scale_v2_03_tool_route` | 通过 | 0 |
| `journey_scale_v2_04` | `journey_scale_v2_04_tool_route` | 通过 | 0 |
| `journey_scale_v2_05` | `journey_scale_v2_05_tool_route` | 通过 | 0 |
| `journey_scale_v2_06` | `journey_scale_v2_06_tool_route` | 通过 | 0 |
| `journey_scale_v2_07` | `journey_scale_v2_07_tool_route` | 通过 | 0 |
| `journey_scale_v2_08` | `journey_scale_v2_08_tool_route` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：8
- 输入条数：2560
- Eval task 数：80
- Case family 分布：full_chain_journey_scale_v2=8
- Task type 分布：card_extraction=16，cost_trace=8，memory_write=8，pkm_organization=8，retrieval_qa=16，schedule_refresh=8，super_agent_qa=8，tool_calling=8

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `scale_u_001` | 增长产品经理 | 上海 | zh-CN | 1 | 320 | 10 | 以后 导出灰度 这种重要安排提前一天提醒我，最好把 失败率截图 一起列出来。<br>先记一下旧规则：下午也可以喝咖啡。，等我后面确认再改。 |
| `scale_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 320 | 10 | 以后 北美站增长 这种重要安排提前一天提醒我，最好把 ROAS 分层表 一起列出来。<br>先记一下旧规则：ROAS 低于 1.8 才提醒。，等我后面确认再改。 |
| `scale_u_003` | 数据分析师 | 杭州 | zh-CN | 1 | 320 | 10 | 以后 Memex 评测看板 这种重要安排提前一天提醒我，最好把 hit@3 和 MRR 截图 一起列出来。<br>先记一下旧规则：指标解释可以只写中文名。，等我后面确认再改。 |
| `scale_u_004` | 律师 | 广州 | zh-CN | 1 | 320 | 10 | 以后 合同条款库 这种重要安排提前一天提醒我，最好把 条款来源编号 一起列出来。<br>先记一下旧规则：合同问题可以直接给结论。，等我后面确认再改。 |
| `scale_u_005` | 财务主管 | 成都 | zh-CN | 1 | 320 | 10 | 以后 预算月结 这种重要安排提前一天提醒我，最好把 付款审批表 一起列出来。<br>先记一下旧规则：付款超过五万再提醒。，等我后面确认再改。 |
| `scale_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 320 | 10 | 以后 小红书活动 这种重要安排提前一天提醒我，最好把 素材来源链接 一起列出来。<br>先记一下旧规则：素材复盘只看点赞数。，等我后面确认再改。 |
| `scale_u_007` | 家庭照护者 | 南京 | zh-CN | 1 | 320 | 10 | 以后 妈妈康复计划 这种重要安排提前一天提醒我，最好把 血压记录表 一起列出来。<br>先记一下旧规则：晚间用药按 8 点提醒。，等我后面确认再改。 |
| `scale_u_008` | 研究生 | 北京 | zh-CN | 1 | 320 | 10 | 以后 论文开题 这种重要安排提前一天提醒我，最好把 文献矩阵 一起列出来。<br>先记一下旧规则：文献综述每周日提醒。，等我后面确认再改。 |
