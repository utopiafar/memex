# Memex Agent Eval 实验报告

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为。
- 本次覆盖 8 个 case、32 个 eval task，断言通过率 52.6%。
- 失败断言数：138；Token 总量：217130；LLM 调用次数：158；工具调用次数：612。
- Replay 实测耗时：30分38秒；Benchmark 评分耗时：0秒。
- 主要失败项：
  - `journey_real_replay_v1_01_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_01_mem_reminder.
  - `journey_real_replay_v1_01_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_01_mem_project_owner.
  - `journey_real_replay_v1_01_super_agent` / `answer_must_include`：Answer missing: 下午不喝.

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_journey_real_replay_v1`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 8 |
| Case | 8 |
| 用户输入 | 64 |
| Eval task | 32 |
| 断言 | 291 |
| LLM 调用 | 158 |
| Tool 调用 | 612 |
| 实际 token | 217130 |
| Replay 实测耗时 | 30分38秒 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 217130 tokens；同规模复跑可先按 173704-260556 tokens 预留。

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
| Card 抽取 | 延迟 | `input_to_card_latency` | 从用户输入到 card 产物的延迟是否在预算内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
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
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 19 | 40 | 47.5% | 0.125 |
| 成本 / Trace | 84 | 168 | 50.0% | 0.468 |
| 记忆写入 | 25 | 45 | 55.6% | 0.310 |
| Super Agent 问答 | 25 | 38 | 65.8% | 0.125 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 1 | 8 | 12.5% | - |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 1 | 8 | 12.5% | 0.125 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 8 | 8 | 100.0% | - |
| Card 抽取 | 延迟 | `input_to_card_latency` | 8 | 8 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 1 | 8 | 12.5% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 1 | 6 | 16.7% | 0.167 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 8 | 8 | 100.0% | - |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 1 | 8 | 12.5% | 0.250 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 8 | 8 | 100.0% | 0.642 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 8 | 8 | 100.0% | 0.932 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 8 | 12.5% | - |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 1 | 8 | 12.5% | 0.125 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | 1 | 8 | 12.5% | 0.514 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 1 | 8 | 12.5% | 0.125 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 8 | 8 | 100.0% | - |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 1 | 8 | 12.5% | 0.234 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 1 | 8 | 12.5% | 0.125 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 1 | 8 | 12.5% | 0.234 |
| 成本 / Trace | 用户旅程覆盖 | `scenario_family_coverage` | 1 | 8 | 12.5% | 0.271 |
| 成本 / Trace | 用户画像区分 | `persona_specificity_coverage` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `retry_rate` | 8 | 8 | 100.0% | 0.961 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 8 | 8 | 100.0% | 1.000 |
| 成本 / Trace | 跨日连续性 | `cross_day_continuity_coverage` | 1 | 8 | 12.5% | 0.125 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 1 | 8 | 12.5% | 0.300 |
| 成本 / Trace | 追问闭环 | `follow_up_query_coverage` | 1 | 8 | 12.5% | 0.125 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 8 | 8 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 0 | 8 | 0.0% | 0.094 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 1 | 21 | 4.8% | 0.048 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 16 | 16 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 8 | 8 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 8 | 8 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：158
- 工具调用次数：612
- Token 总量：217130
- 单次 LLM 平均 token：1374.241
- 平均延迟：4518.039 ms
- P95 延迟：40000.000 ms
- Replay 实测耗时：30分38秒
- Case 观察耗时累计：30分38秒
- Benchmark 评分耗时：0秒

## 失败样本

- `journey_real_replay_v1_01_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_01_mem_reminder.
- `journey_real_replay_v1_01_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_01_mem_project_owner.
- `journey_real_replay_v1_01_super_agent` / `answer_must_include`：Answer missing: 下午不喝.
- `journey_real_replay_v1_02_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=5, failed_tasks=0, active_details=fts_index_update:pending | card_agent_task:processing | pkm_agent_task:pending | comment_agent_task:pending.
- `journey_real_replay_v1_02_cost` / `record_operation_coverage`：record_operations=1, min=8.
- `journey_real_replay_v1_02_cost` / `journey_time_span_coverage`：journey_span_days=0.00, min=2.0.
- `journey_real_replay_v1_02_cost` / `app_operation_sequence_completeness`：Missing operation types: ask_super_agent, fetch_timeline, post_comment, refresh_knowledge_insights, refresh_schedule_aggregation, wait_memory.
- `journey_real_replay_v1_02_cost` / `input_channel_diversity`：Missing input channels: clipboard, ocr_clip, photo_note, text.
- `journey_real_replay_v1_02_cost` / `feature_trigger_coverage`：Missing feature triggers: timeline_browse, comment, memory, knowledge_insight, super_agent.
- `journey_real_replay_v1_02_cost` / `journey_stage_coverage`：Missing journey stages: comment_correction, knowledge_insight, memory_write, pkm_organize, schedule_refresh, super_agent_qa, timeline_review.
- `journey_real_replay_v1_02_cost` / `scenario_family_coverage`：Missing scenario families: correction, family_care, finance, noise, social_relationship.
- `journey_real_replay_v1_02_cost` / `cross_day_continuity_coverage`：cross_day_links=0, min=1.
- `journey_real_replay_v1_02_cost` / `correction_operation_coverage`：correction_operations=0, min=1.
- `journey_real_replay_v1_02_cost` / `noise_resilience_coverage`：noise_inputs=0, min=1.
- `journey_real_replay_v1_02_cost` / `follow_up_query_coverage`：follow_up_queries=0, min=1.
- `journey_real_replay_v1_02_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_02_mem_reminder.
- `journey_real_replay_v1_02_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_02_mem_project_owner.
- `journey_real_replay_v1_02_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v1_02_mem_latest_preference.
- `journey_real_replay_v1_02_card_project` / `card_schema_valid`：Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。
- `journey_real_replay_v1_02_card_project` / `card_status_accuracy`：Card 状态不符合预期。期望状态 completed，实际状态 null。

## 问题排查与建议

### 排查过程

- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。
- 对全链路失败，优先查看 cost task 中的 `settled`、`active_tasks`、`failed_tasks`，再关联同一 case 的 card 断言。
- 对 card 失败，检查对应 `input_id` 是否能通过提交返回的 fact id 找到 card，以及 card 是否停留在 processing/null。

### 结论

- 全链路主要问题是后台任务未在预算时间内全部收敛，后续 card 断言出现 null/缺字段更像链路未完成的下游现象。
- Card 相关失败集中在未生成、未完成或无法按输入来源取回，优先怀疑 task 生命周期、card agent 落盘和 fact_id/card_id 关联。

### 修改建议

- 给 LocalTaskExecutor / task handler 增加按 case 可检索的任务状态摘要，明确 pending、processing、retrying 的阻塞点和最后一次错误。
- 在 replay harness 里保留每个 active task 的 type、status、attempt、updated_at，便于区分真实超时和观察窗口太短。
- 检查 submitInput 返回的 fact_id 到 TimelineCard 的关联路径，确认 card agent 完成后会把 status 从 processing 推进到 completed。
- 为 card agent 增加最小字段契约测试：title、status、source/fact 关联、关键主题词进入 title 或结构化字段。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-17-full-chain-real-replay-v1`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v1`
- 观察适配器：`replay_file`
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为
- 本地完整日志：`evals/runs/2026-05-17-full-chain-real-replay-v1/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-17-full-chain-real-replay-v1/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-17-full-chain-real-replay-v1/outputs.jsonl`
- 场景样本数：8
- 评估任务数：32
- Replay 实测耗时：30分38秒
- Benchmark 评分耗时：0秒
- 断言通过：153/291 （52.6%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v1_01` | `journey_real_replay_v1_01_card_project` | 通过 | 0 |
| `journey_real_replay_v1_02` | `journey_real_replay_v1_02_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_03` | `journey_real_replay_v1_03_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_04` | `journey_real_replay_v1_04_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_05` | `journey_real_replay_v1_05_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_06` | `journey_real_replay_v1_06_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_07` | `journey_real_replay_v1_07_card_project` | 未通过 | 3 |
| `journey_real_replay_v1_08` | `journey_real_replay_v1_08_card_project` | 未通过 | 3 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v1_01` | `journey_real_replay_v1_01_cost` | 通过 | 0 |
| `journey_real_replay_v1_02` | `journey_real_replay_v1_02_cost` | 未通过 | 12 |
| `journey_real_replay_v1_03` | `journey_real_replay_v1_03_cost` | 未通过 | 12 |
| `journey_real_replay_v1_04` | `journey_real_replay_v1_04_cost` | 未通过 | 12 |
| `journey_real_replay_v1_05` | `journey_real_replay_v1_05_cost` | 未通过 | 12 |
| `journey_real_replay_v1_06` | `journey_real_replay_v1_06_cost` | 未通过 | 12 |
| `journey_real_replay_v1_07` | `journey_real_replay_v1_07_cost` | 未通过 | 12 |
| `journey_real_replay_v1_08` | `journey_real_replay_v1_08_cost` | 未通过 | 12 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v1_01` | `journey_real_replay_v1_01_memory` | 未通过 | 2 |
| `journey_real_replay_v1_02` | `journey_real_replay_v1_02_memory` | 未通过 | 3 |
| `journey_real_replay_v1_03` | `journey_real_replay_v1_03_memory` | 未通过 | 2 |
| `journey_real_replay_v1_04` | `journey_real_replay_v1_04_memory` | 未通过 | 3 |
| `journey_real_replay_v1_05` | `journey_real_replay_v1_05_memory` | 未通过 | 2 |
| `journey_real_replay_v1_06` | `journey_real_replay_v1_06_memory` | 未通过 | 2 |
| `journey_real_replay_v1_07` | `journey_real_replay_v1_07_memory` | 未通过 | 3 |
| `journey_real_replay_v1_08` | `journey_real_replay_v1_08_memory` | 未通过 | 3 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v1_01` | `journey_real_replay_v1_01_super_agent` | 未通过 | 1 |
| `journey_real_replay_v1_02` | `journey_real_replay_v1_02_super_agent` | 未通过 | 2 |
| `journey_real_replay_v1_03` | `journey_real_replay_v1_03_super_agent` | 未通过 | 2 |
| `journey_real_replay_v1_04` | `journey_real_replay_v1_04_super_agent` | 未通过 | 1 |
| `journey_real_replay_v1_05` | `journey_real_replay_v1_05_super_agent` | 未通过 | 2 |
| `journey_real_replay_v1_06` | `journey_real_replay_v1_06_super_agent` | 未通过 | 2 |
| `journey_real_replay_v1_07` | `journey_real_replay_v1_07_super_agent` | 未通过 | 2 |
| `journey_real_replay_v1_08` | `journey_real_replay_v1_08_super_agent` | 未通过 | 1 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：8
- 输入条数：64
- Eval task 数：32
- Case family 分布：full_chain_journey_real_replay_v1=8
- Task type 分布：card_extraction=8，cost_trace=8，memory_write=8，super_agent_qa=8

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `scale_u_001` | 增长产品经理 | 上海 | zh-CN | 1 | 8 | 4 | 以后 导出灰度 这种重要安排提前一天提醒我，最好把 失败率截图 一起列出来。<br>先记一下旧规则：下午也可以喝咖啡。，等我后面确认再改。 |
| `scale_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 8 | 4 | 以后 北美站增长 这种重要安排提前一天提醒我，最好把 ROAS 分层表 一起列出来。<br>先记一下旧规则：ROAS 低于 1.8 才提醒。，等我后面确认再改。 |
| `scale_u_003` | 数据分析师 | 杭州 | zh-CN | 1 | 8 | 4 | 以后 Memex 评测看板 这种重要安排提前一天提醒我，最好把 hit@3 和 MRR 截图 一起列出来。<br>先记一下旧规则：指标解释可以只写中文名。，等我后面确认再改。 |
| `scale_u_004` | 律师 | 广州 | zh-CN | 1 | 8 | 4 | 以后 合同条款库 这种重要安排提前一天提醒我，最好把 条款来源编号 一起列出来。<br>先记一下旧规则：合同问题可以直接给结论。，等我后面确认再改。 |
| `scale_u_005` | 财务主管 | 成都 | zh-CN | 1 | 8 | 4 | 以后 预算月结 这种重要安排提前一天提醒我，最好把 付款审批表 一起列出来。<br>先记一下旧规则：付款超过五万再提醒。，等我后面确认再改。 |
| `scale_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 8 | 4 | 以后 小红书活动 这种重要安排提前一天提醒我，最好把 素材来源链接 一起列出来。<br>先记一下旧规则：素材复盘只看点赞数。，等我后面确认再改。 |
| `scale_u_007` | 家庭照护者 | 南京 | zh-CN | 1 | 8 | 4 | 以后 妈妈康复计划 这种重要安排提前一天提醒我，最好把 血压记录表 一起列出来。<br>先记一下旧规则：晚间用药按 8 点提醒。，等我后面确认再改。 |
| `scale_u_008` | 研究生 | 北京 | zh-CN | 1 | 8 | 4 | 以后 论文开题 这种重要安排提前一天提醒我，最好把 文献矩阵 一起列出来。<br>先记一下旧规则：文献综述每周日提醒。，等我后面确认再改。 |
