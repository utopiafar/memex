# Memex Agent Eval 实验报告

## 人工复盘补充

- 本轮 v4 真实 LLM 全链路实验已经完整跑完：三个 shard 均退出 0，合并后完成 36 case / 216 eval task 评分。
- 关键结论：仍未达到稳定基线，主阻塞是 `pkm_agent_task` 的 loopDetection。12 个 hard failed case 全部集中在 PKM，已提 upstream issue：[memex-lab/memex#163](https://github.com/memex-lab/memex/issues/163)。
- 这次不是 Flutter 代理、root 隔离或等待窗口问题：`root_invariant_absence` 36/36，card materialization/completion 均 36/36，failed task type 只有 `pkm_agent_task`。
- 长跑时的 agent/evals 相关代码基线是合入 `upstream/main` `545e50e393a76e1d0a0a393ea6fb0d267393c01d` 后的 `5fc5f433503aa8c3d289b271d95bb284087871bc`。长跑结束后当前分支已继续合入 `upstream/main` `e63d4dbdc5c5c28b971e0b31c91c4c02eb446e29`，该增量只涉及 Android launcher shortcut 资源和 Gradle shortcut 配置，不触及 agent/evals 链路。
- 未收敛明细和原始日志证据见 `non_converged_cases.md`。

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为。
- 本次覆盖 36 个 case、216 个 eval task，断言通过率 77.6%。
- 失败断言数：450；Token 总量：3245437；LLM 调用次数：3260；工具调用次数：19650。
- Replay 实测耗时：3小时54分02秒；Benchmark 评分耗时：0秒。
- 主要失败项：
  - `journey_real_replay_v4_01_a_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v4_01_a_mem_reminder.
  - `journey_real_replay_v4_01_a_card_project` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：Mina.
  - `journey_real_replay_v4_01_a_card_boundary` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：导出灰度.

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_journey_real_replay_v4`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 12 |
| Case | 36 |
| 用户输入 | 432 |
| Eval task | 216 |
| 断言 | 2013 |
| LLM 调用 | 3260 |
| Tool 调用 | 19650 |
| 实际 token | 3245437 |
| Replay 实测耗时 | 3小时54分02秒 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 3245437 tokens；同规模复跑可先按 2596350-3894524 tokens 预留。

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
| Card 抽取 | Card 状态 | `card_completed_rate` | 真实提交记录中有多少对应 card 已进入 completed 状态。 |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| Card 抽取 | 产物生成 | `card_materialization_rate` | 真实提交记录中有多少能取回对应 card 产物。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 延迟 | `input_to_card_latency` | 从用户输入到 card 产物的延迟是否在预算内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 回答是否利用用户偏好、习惯或上下文做个性化表达。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 成本 / Trace | Agent 循环控制 | `loop_detection_absence` | 后台任务是否没有触发 loopDetection 保护。 |
| 成本 / Trace | Agent 循环控制 | `max_turns_absence` | 后台任务是否没有触发 Maximum turns reached。 |
| 成本 / Trace | Agent 覆盖 | `llm_agent_coverage` | 真实链路中调用 LLM 的 agent 种类是否达到预期，避免只跑到单点链路。 |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 是否执行了预期 App 行为类型，例如记录、回看、评论、刷新和问答。 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 平均每条用户输入消耗的 token 是否在预算内。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | Trace 是否包含期望的关键事件或工具调用节点。 |
| 成本 / Trace | 任务收敛 | `active_task_count_budget` | 观察结束时仍 active 的后台任务数量是否在预算内。 |
| 成本 / Trace | 任务收敛 | `failed_task_count_budget` | 观察结束时 failed 的后台任务数量是否在预算内。 |
| 成本 / Trace | 任务收敛 | `operation_settlement_rate` | 需要等待后台任务的操作中，有多少在预算窗口内完成收敛。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 是否包含足够的用户修正、偏好更新或冲突覆盖样本。 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | trace 和操作记录是否覆盖本轮预期功能触发点。 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 是否包含足够的临时情绪、一次性尝试、OCR 噪声等不应长期化输入。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 工具覆盖 | `tool_diversity` | 真实链路中被调用的工具种类是否达到预期，反映跨功能路径覆盖。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 测试框架不变量 | `root_invariant_absence` | Replay harness 每条 record 是否写入并观测在当前 case 的 data root。 |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 用户旅程是否覆盖捕获、组织、回看、追问、修正和洞察等阶段。 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 模拟用户操作是否跨越足够多天，避免只测单日短上下文。 |
| 成本 / Trace | 用户旅程覆盖 | `operation_success_rate` | 真实用户旅程操作是否大多无错误且等待型操作能继续推进。 |
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
| 记忆写入 | 产物生成 | `memory_artifact_presence` | 真实旅程是否沉淀出最低数量的 memory 产物。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 269 | 348 | 77.3% | 0.358 |
| 成本 / Trace | 975 | 1188 | 82.1% | 0.860 |
| 记忆写入 | 114 | 195 | 58.5% | 0.341 |
| Super Agent 问答 | 205 | 282 | 72.7% | 0.405 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_completed_rate` | 36 | 36 | 100.0% | 1.000 |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 59 | 72 | 81.9% | - |
| Card 抽取 | 产物生成 | `card_materialization_rate` | 36 | 36 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 7 | 60 | 11.7% | 0.358 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 72 | 72 | 100.0% | - |
| Card 抽取 | 延迟 | `input_to_card_latency` | 72 | 72 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 59 | 72 | 81.9% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 12 | 30 | 40.0% | 0.400 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 72 | 72 | 100.0% | - |
| 成本 / Trace | Agent 循环控制 | `loop_detection_absence` | 16 | 36 | 44.4% | - |
| 成本 / Trace | Agent 循环控制 | `max_turns_absence` | 28 | 36 | 77.8% | - |
| 成本 / Trace | Agent 覆盖 | `llm_agent_coverage` | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 24 | 36 | 66.7% | 0.714 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 36 | 36 | 100.0% | 0.832 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 36 | 36 | 100.0% | 0.850 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 36 | 36 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `active_task_count_budget` | 36 | 36 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `failed_task_count_budget` | 24 | 36 | 66.7% | - |
| 成本 / Trace | 任务收敛 | `operation_settlement_rate` | 24 | 36 | 66.7% | 0.949 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 24 | 36 | 66.7% | - |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 36 | 36 | 100.0% | 0.333 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | 20 | 36 | 55.6% | 0.812 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 31 | 36 | 86.1% | 0.875 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 36 | 36 | 100.0% | - |
| 成本 / Trace | 工具覆盖 | `tool_diversity` | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | 延迟 | `latency_budget` | 36 | 36 | 100.0% | - |
| 成本 / Trace | 测试框架不变量 | `root_invariant_absence` | 36 | 36 | 100.0% | - |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 25 | 36 | 69.4% | 0.873 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 27 | 36 | 75.0% | 0.888 |
| 成本 / Trace | 用户旅程覆盖 | `operation_success_rate` | 24 | 36 | 66.7% | 0.949 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 25 | 36 | 69.4% | 0.873 |
| 成本 / Trace | 用户旅程覆盖 | `scenario_family_coverage` | 26 | 36 | 72.2% | 0.889 |
| 成本 / Trace | 用户画像区分 | `persona_specificity_coverage` | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 34 | 36 | 94.4% | 0.992 |
| 成本 / Trace | 稳定性 | `retry_rate` | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 36 | 36 | 100.0% | 1.000 |
| 成本 / Trace | 跨日连续性 | `cross_day_continuity_coverage` | 25 | 36 | 69.4% | 0.835 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 25 | 36 | 69.4% | 0.873 |
| 成本 / Trace | 追问闭环 | `follow_up_query_coverage` | 24 | 36 | 66.7% | 0.667 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 33 | 36 | 91.7% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 16 | 72 | 22.2% | 0.407 |
| 记忆写入 | 产物生成 | `memory_artifact_presence` | 9 | 36 | 25.0% | 0.444 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 6 | 87 | 6.9% | 0.069 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 72 | 72 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 36 | 36 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 72 | 72 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：3260
- 工具调用次数：19650
- Token 总量：3245437
- 单次 LLM 平均 token：995.533
- 平均延迟：10508.672 ms
- P95 延迟：67000.000 ms
- Replay 实测耗时：3小时54分02秒
- Case 观察耗时累计：10小时31分35秒
- Benchmark 评分耗时：0秒

### 观测指标分层

| 类别 | 指标 | 数值 |
| --- | --- | ---: |
| 旅程执行 | 操作成功率 | 97.8% |
| 旅程执行 | 需等待操作收敛率 | 97.3% |
| 旅程执行 | 记录操作数 | 377 |
| 后台任务 | active / failed / retrying | 0 / 12 / 0 |
| 后台任务 | loopDetection / maxTurns | 21 / 8 |
| 测试框架 | root invariant failures / checks | 0 / 377 |
| 产物健康 | Card materialized / completed | 100.0% / 100.0% |
| 产物健康 | Memory entries / sourced | 47 / 0 |
| 成本行为 | 缓存 token / thought token | 18194752 / 0 |

#### 任务类型分布

| Item | Count |
| --- | ---: |
| `fts_index_update` | 1459 |
| `card_agent_task` | 377 |
| `comment_agent_task` | 377 |
| `handle_analyze_assets` | 377 |
| `pkm_agent_task` | 377 |
| `schedule_refresh_router_task` | 377 |
| `schedule_aggregator_task` | 25 |
| `knowledge_insight_task` | 24 |
| `process_ai_reply` | 24 |

#### 失败任务类型

| Item | Count |
| --- | ---: |
| `pkm_agent_task` | 12 |

#### LLM 调用 by agent

| Item | Count |
| --- | ---: |
| `pkm_agent` | 1417 |
| `schedule_refresh_router_agent` | 770 |
| `knowledge_insight_agent` | 529 |
| `card_agent` | 381 |
| `schedule_aggregator_agent` | 130 |
| `comment_agent` | 33 |

#### Token by agent

| Item | Count |
| --- | ---: |
| `pkm_agent` | 2097084 |
| `card_agent` | 591324 |
| `knowledge_insight_agent` | 234694 |
| `schedule_refresh_router_agent` | 130120 |
| `comment_agent` | 105043 |
| `schedule_aggregator_agent` | 87172 |

#### Tool 调用 by name

| Item | Count |
| --- | ---: |
| `Read` | 723 |
| `Grep` | 357 |
| `save_timeline_card` | 347 |
| `update_timeline_card_insight` | 257 |
| `save_knowledge_insight_cards` | 207 |
| `skip_schedule_refresh` | 188 |
| `mark_schedule_dirty` | 183 |
| `Edit` | 169 |
| `Write` | 153 |
| `LS` | 139 |
| `write_todos` | 106 |
| `BatchRead` | 73 |

#### 操作耗时分布

| Operation | Count | Avg | Max |
| --- | ---: | ---: | ---: |
| `ask_super_agent` | 48 | 29秒 | 1分54秒 |
| `fetch_timeline` | 24 | 0秒 | 0秒 |
| `post_comment` | 24 | 19秒 | 34秒 |
| `record` | 377 | 1分12秒 | 9分01秒 |
| `refresh_knowledge_insights` | 24 | 3分35秒 | 11分46秒 |
| `refresh_schedule_aggregation` | 24 | 1分01秒 | 1分59秒 |
| `wait_memory` | 24 | 1分30秒 | 2分00秒 |

## 失败样本

- `journey_real_replay_v4_01_a_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v4_01_a_mem_reminder.
- `journey_real_replay_v4_01_a_card_project` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：Mina.
- `journey_real_replay_v4_01_a_card_boundary` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：导出灰度.
- `journey_real_replay_v4_01_a_super_agent` / `answer_must_include`：Answer missing: 上午, 下午不喝.
- `journey_real_replay_v4_01_b_cost` / `loop_detection_absence`：后台任务收敛或 Agent 循环控制不达标。loop_detection_tasks=1, max=0.
- `journey_real_replay_v4_01_b_cost` / `max_turns_absence`：后台任务收敛或 Agent 循环控制不达标。max_turns_tasks=1, max=0.
- `journey_real_replay_v4_01_b_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v4_01_b_mem_reminder.
- `journey_real_replay_v4_01_b_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v4_01_b_mem_project_owner.
- `journey_real_replay_v4_01_b_card_project` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：Mina.
- `journey_real_replay_v4_01_b_super_agent` / `answer_must_include`：Answer missing: 上午, 下午不喝.
- `journey_real_replay_v4_01_b_super_agent_followup` / `answer_must_include`：Answer missing: 不要.
- `journey_real_replay_v4_01_c_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=0, failed_tasks=1, failed_details=pkm_agent_task:failed:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, Tool call loop detect....
- `journey_real_replay_v4_01_c_cost` / `failed_task_count_budget`：后台任务收敛或 Agent 循环控制不达标。failed_task_count=1, max=0.
- `journey_real_replay_v4_01_c_cost` / `loop_detection_absence`：后台任务收敛或 Agent 循环控制不达标。loop_detection_tasks=1, max=0.
- `journey_real_replay_v4_01_c_cost` / `record_operation_coverage`：record_operations=10, min=12.
- `journey_real_replay_v4_01_c_cost` / `operation_success_rate`：真实用户旅程操作成功率不足。operation_success_rate=0.900, min=0.95.
- `journey_real_replay_v4_01_c_cost` / `operation_settlement_rate`：后台任务收敛或 Agent 循环控制不达标。operation_settlement_rate=0.900, min=0.95.
- `journey_real_replay_v4_01_c_cost` / `journey_time_span_coverage`：journey_span_days=2.96, min=3.0.
- `journey_real_replay_v4_01_c_cost` / `app_operation_sequence_completeness`：Missing operation types: ask_super_agent, fetch_timeline, post_comment, refresh_knowledge_insights, refresh_schedule_aggregation, wait_memory.
- `journey_real_replay_v4_01_c_cost` / `input_channel_diversity`：Missing input channels: browser_clip, meeting_note.

## 问题排查与建议

### 排查过程

- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。
- 对全链路失败，优先查看 cost task 中的 `settled`、`active_tasks`、`failed_tasks`，再关联同一 case 的 card 断言。
- 对 card 失败，检查对应 `input_id` 是否能通过提交返回的 fact id 找到 card，以及 card 是否停留在 processing/null。

### 结论

- 全链路主要问题是后台任务未在预算时间内全部收敛，后续 card 断言出现 null/缺字段更像链路未完成的下游现象。
- active task 中出现 loopDetection，说明至少部分 agent task 卡在重复工具调用保护上，而不是普通网络超时。
- 标题关键词缺失说明即使 card 生成成功，也需要继续验证输入关键信息是否进入标题或结构化字段。

### 修改建议

- 给 LocalTaskExecutor / task handler 增加按 case 可检索的任务状态摘要，明确 pending、processing、retrying 的阻塞点和最后一次错误。
- 在 replay harness 里保留每个 active task 的 type、status、attempt、updated_at，便于区分真实超时和观察窗口太短。
- 针对 loopDetection case，优先检查 card_agent / pkm_agent 的工具调用终止条件，避免同一工具连续调用 5 次后进入 retrying。
- 检查 submitInput 返回的 fact_id 到 TimelineCard 的关联路径，确认 card agent 完成后会把 status 从 processing 推进到 completed。
- 为 card agent 增加最小字段契约测试：title、status、source/fact 关联、关键主题词进入 title 或结构化字段。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-19-full-chain-real-replay-v4-merged`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v4`
- 观察适配器：`replay_file`
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为
- 本地完整日志：`evals/runs/2026-05-19-full-chain-real-replay-v4-merged/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-19-full-chain-real-replay-v4-merged/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-19-full-chain-real-replay-v4-merged/outputs.jsonl`
- 场景样本数：36
- 评估任务数：216
- Replay 实测耗时：3小时54分02秒
- Benchmark 评分耗时：0秒
- 断言通过：1563/2013 （77.6%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_card_project` | 通过 | 0 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_card_boundary` | 未通过 | 2 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_card_project` | 通过 | 0 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_card_boundary` | 未通过 | 2 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_card_project` | 未通过 | 3 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_card_project` | 通过 | 0 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_card_project` | 通过 | 0 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_card_project` | 未通过 | 3 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_card_boundary` | 未通过 | 2 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_card_boundary` | 未通过 | 3 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_card_project` | 通过 | 0 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_card_boundary` | 通过 | 0 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_card_boundary` | 未通过 | 2 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_card_project` | 未通过 | 1 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_card_boundary` | 未通过 | 1 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_cost` | 通过 | 0 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_cost` | 未通过 | 2 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_cost` | 未通过 | 14 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_cost` | 未通过 | 15 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_cost` | 未通过 | 17 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_cost` | 未通过 | 2 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_cost` | 未通过 | 2 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_cost` | 未通过 | 16 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_cost` | 未通过 | 13 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_cost` | 未通过 | 2 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_cost` | 未通过 | 1 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_cost` | 未通过 | 16 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_cost` | 未通过 | 1 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_cost` | 未通过 | 1 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_cost` | 未通过 | 4 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_cost` | 通过 | 0 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_cost` | 未通过 | 1 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_cost` | 通过 | 0 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_cost` | 未通过 | 3 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_cost` | 未通过 | 1 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_cost` | 未通过 | 15 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_cost` | 未通过 | 1 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_cost` | 通过 | 0 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_cost` | 未通过 | 1 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_cost` | 未通过 | 2 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_cost` | 未通过 | 4 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_cost` | 未通过 | 1 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_cost` | 未通过 | 14 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_cost` | 未通过 | 17 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_cost` | 未通过 | 15 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_cost` | 未通过 | 2 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_cost` | 未通过 | 1 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_cost` | 未通过 | 1 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_cost` | 未通过 | 9 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_cost` | 未通过 | 16 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_cost` | 未通过 | 3 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_memory` | 未通过 | 1 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_memory` | 未通过 | 3 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_memory` | 未通过 | 3 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_memory` | 未通过 | 3 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_memory` | 未通过 | 3 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_memory` | 未通过 | 1 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_memory` | 未通过 | 3 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_memory` | 未通过 | 3 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_memory` | 未通过 | 3 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_memory` | 未通过 | 3 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_memory` | 未通过 | 3 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_memory` | 未通过 | 3 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_memory` | 未通过 | 3 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_memory` | 未通过 | 3 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_memory` | 未通过 | 1 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_memory` | 未通过 | 2 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_memory` | 未通过 | 2 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_memory` | 未通过 | 2 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_memory` | 未通过 | 2 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_01_a` | `journey_real_replay_v4_01_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_01_b` | `journey_real_replay_v4_01_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_01_c` | `journey_real_replay_v4_01_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_02_a` | `journey_real_replay_v4_02_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_02_b` | `journey_real_replay_v4_02_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_02_c` | `journey_real_replay_v4_02_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_03_a` | `journey_real_replay_v4_03_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_03_b` | `journey_real_replay_v4_03_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_03_c` | `journey_real_replay_v4_03_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_04_a` | `journey_real_replay_v4_04_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_04_b` | `journey_real_replay_v4_04_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_04_c` | `journey_real_replay_v4_04_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_05_a` | `journey_real_replay_v4_05_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_05_b` | `journey_real_replay_v4_05_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_05_c` | `journey_real_replay_v4_05_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_06_a` | `journey_real_replay_v4_06_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_06_b` | `journey_real_replay_v4_06_b_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_06_c` | `journey_real_replay_v4_06_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_07_a` | `journey_real_replay_v4_07_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_07_b` | `journey_real_replay_v4_07_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_07_c` | `journey_real_replay_v4_07_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_08_a` | `journey_real_replay_v4_08_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_08_b` | `journey_real_replay_v4_08_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_08_c` | `journey_real_replay_v4_08_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_09_a` | `journey_real_replay_v4_09_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_09_b` | `journey_real_replay_v4_09_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_super_agent` | 未通过 | 1 |
| `journey_real_replay_v4_09_c` | `journey_real_replay_v4_09_c_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_10_a` | `journey_real_replay_v4_10_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_10_b` | `journey_real_replay_v4_10_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_10_c` | `journey_real_replay_v4_10_c_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_11_a` | `journey_real_replay_v4_11_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_11_b` | `journey_real_replay_v4_11_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_11_c` | `journey_real_replay_v4_11_c_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_12_a` | `journey_real_replay_v4_12_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v4_12_b` | `journey_real_replay_v4_12_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_super_agent` | 通过 | 0 |
| `journey_real_replay_v4_12_c` | `journey_real_replay_v4_12_c_super_agent_followup` | 未通过 | 1 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：432
- Eval task 数：216
- Case family 分布：full_chain_journey_real_replay_v4=36
- Task type 分布：card_extraction=72，cost_trace=36，memory_write=36，super_agent_qa=72

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `scale_u_001` | 增长产品经理 | 上海 | zh-CN | 3 | 36 | 18 | 以后 导出灰度 这种重要安排提前一天提醒我，最好把 失败率截图 一起列出来。<br>先记一下旧规则：下午也可以喝咖啡。，等我后面确认再改。 |
| `scale_u_002` | 跨境电商运营 | 深圳 | zh-CN | 3 | 36 | 18 | 以后 北美站增长 这种重要安排提前一天提醒我，最好把 ROAS 分层表 一起列出来。<br>先记一下旧规则：ROAS 低于 1.8 才提醒。，等我后面确认再改。 |
| `scale_u_003` | 数据分析师 | 杭州 | zh-CN | 3 | 36 | 18 | 以后 Memex 评测看板 这种重要安排提前一天提醒我，最好把 hit@3 和 MRR 截图 一起列出来。<br>先记一下旧规则：指标解释可以只写中文名。，等我后面确认再改。 |
| `scale_u_004` | 律师 | 广州 | zh-CN | 3 | 36 | 18 | 以后 合同条款库 这种重要安排提前一天提醒我，最好把 条款来源编号 一起列出来。<br>先记一下旧规则：合同问题可以直接给结论。，等我后面确认再改。 |
| `scale_u_005` | 财务主管 | 成都 | zh-CN | 3 | 36 | 18 | 以后 预算月结 这种重要安排提前一天提醒我，最好把 付款审批表 一起列出来。<br>先记一下旧规则：付款超过五万再提醒。，等我后面确认再改。 |
| `scale_u_006` | 内容运营 | 苏州 | zh-CN | 3 | 36 | 18 | 以后 小红书活动 这种重要安排提前一天提醒我，最好把 素材来源链接 一起列出来。<br>先记一下旧规则：素材复盘只看点赞数。，等我后面确认再改。 |
| `scale_u_007` | 家庭照护者 | 南京 | zh-CN | 3 | 36 | 18 | 以后 妈妈康复计划 这种重要安排提前一天提醒我，最好把 血压记录表 一起列出来。<br>先记一下旧规则：晚间用药按 8 点提醒。，等我后面确认再改。 |
| `scale_u_008` | 研究生 | 北京 | zh-CN | 3 | 36 | 18 | 以后 论文开题 这种重要安排提前一天提醒我，最好把 文献矩阵 一起列出来。<br>先记一下旧规则：文献综述每周日提醒。，等我后面确认再改。 |
| `scale_u_009` | 产品设计师 | 厦门 | zh-CN | 3 | 36 | 18 | 以后 智能相册改版 这种重要安排提前一天提醒我，最好把 用户访谈摘录 一起列出来。<br>先记一下旧规则：评审只看视觉稿。，等我后面确认再改。 |
| `scale_u_010` | 独立开发者 | 武汉 | zh-CN | 3 | 36 | 18 | 以后 订阅计费重构 这种重要安排提前一天提醒我，最好把 Stripe webhook 日志 一起列出来。<br>先记一下旧规则：失败回调超过 20 次再提醒。，等我后面确认再改。 |
| `scale_u_011` | 咖啡店主理人 | 青岛 | zh-CN | 3 | 36 | 18 | 以后 春季新品菜单 这种重要安排提前一天提醒我，最好把 试饮反馈表 一起列出来。<br>先记一下旧规则：新品复盘只看销量。，等我后面确认再改。 |
| `scale_u_012` | 公益项目协调人 | 西安 | zh-CN | 3 | 36 | 18 | 以后 社区阅读计划 这种重要安排提前一天提醒我，最好把 报名名单 一起列出来。<br>先记一下旧规则：活动前一天晚上提醒。，等我后面确认再改。 |
