# Memex Agent Eval 实验报告

## 人工复核摘要

- 代码基线：已合入最新 `upstream/main` `4268259`，包含 PKM skip/no-op prompt 收窄修复；实验在合并提交 `485d7b4` 之后运行。
- 运行方式：真实 LLM replay，模型配置通过环境变量传入，报告与仓库文件中不保存 API key；本地执行时按 Flutter 代理规避要求 unset `ws_proxy` / `wss_proxy`，并设置 localhost `NO_PROXY`。
- 数据规模：`full_chain_journey_real_replay_v3` 为 8 persona、16 case、192 条真实提交记录、304 个用户旅程操作、96 个 eval task，规模大于上一轮 v2 的 8 case、128 record、184 operation、48 task。
- 长跑闭环：首分片完成 case 1-12 后被 Flutter test 默认 240 分钟超时截断；随后增加 `MEMEX_EVAL_CASE_OFFSET` 和 `MEMEX_EVAL_TEST_TIMEOUT_MINUTES` 后从 case offset 12 续跑 case 13-16。两段 observations 合并后覆盖全部 16 case、96 task。
- 时间口径：自动报告中的 `Replay 实测耗时` 来自首分片；本次正式解读使用合并后的 case 观察耗时 `5小时15分02秒`。其中首分片 3小时55分56秒，tail 分片 1小时19分07秒。
- 结论：原先“明确不要长期化/噪声/临时状态”的 no-op path 在本轮没有复现为失败，`memory_must_not_write_precision` 为 32/32。剩余不稳定主要是新的 PKM 复杂内容 loop、Knowledge Insight max-turn 后可恢复重试、Schedule Aggregator 一次 max-turn 后未在窗口内收敛，以及标题/记忆召回/问答完整性质量不足。
- 未收敛 case 详细复盘见 `non_converged_cases.md`。已提交上游问题：PKM loopDetection https://github.com/memex-lab/memex/issues/146；Schedule Aggregator no-op completion https://github.com/memex-lab/memex/issues/147。

### 主要失败形态

| 类型 | 影响 | 证据 | 判断 |
| --- | --- | --- | --- |
| PKM loopDetection 硬失败 | 3 个 case 未完整推进后续操作 | `journey_real_replay_v3_01_a`、`03_b`、`08_b` 均为 `pkm_agent_task` retry 到 5 后 failed | 项目问题。Agent 对“搜索不到已有文件/同工具重复调用/复杂纠错内容”的终止与替代路径不足，需要在 PKM agent 层修。 |
| Schedule Aggregator 未收敛 | 1 个 case 停在 active processing | `journey_real_replay_v3_04_a` 的 `schedule_aggregator_task` 在 `Maximum turns reached` 后仍 processing | 项目问题。聚合 agent 需要 max-turn 后的降级保存或 no-op completion path。 |
| Knowledge Insight max-turn 可恢复 | 多个 case 出现 loop/max-turn 指标失败，但最终任务完成 | `01_b`、`02_a`、`02_b`、`07_a`、`07_b` 等 case 的 max-turn 断言失败，但 `tasks_settled=true` | 项目问题偏稳定性。重试能兜住结果，但 token/耗时偏高，应减少无效工具循环。 |
| Flutter test 总时长超时 | 首次全量跑被 240 分钟测试预算截断 | 首分片到 case 13 时触发 `TimeoutException after 4:00:00` | 测试框架问题，已在本分支通过 offset 续跑和测试超时参数修复。 |
| 自动报告耗时口径不适配分片 | 自动字段只显示首分片 wall time | 下文自动报告 `Replay 实测耗时` 为 3小时55分56秒，而合并 case 观察耗时为 5小时15分02秒 | 测试框架问题，后续报告生成器应显式支持 shard metadata。 |

## 结论

- 未达到稳定基线标准，需要优先分析失败项。
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为。
- 本次覆盖 16 个 case、96 个 eval task，断言通过率 82.8%。
- 失败断言数：154；Token 总量：1723080；LLM 调用次数：1664；工具调用次数：9966。
- Replay 首分片耗时：3小时55分56秒；合并 case 观察耗时：5小时15分02秒；Benchmark 评分耗时：0秒。
- 主要失败项：
  - `journey_real_replay_v3_01_a_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=0, failed_tasks=1, failed_details=pkm_agent_task:failed:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, LLM Diagnosis detecte....
  - `journey_real_replay_v3_01_a_cost` / `failed_task_count_budget`：后台任务收敛或 Agent 循环控制不达标。failed_task_count=1, max=0.
  - `journey_real_replay_v3_01_a_cost` / `loop_detection_absence`：后台任务收敛或 Agent 循环控制不达标。loop_detection_tasks=1, max=0.

## 实验问题与背景

- 本次要回答的问题：真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`replay_file` adapter，数据集 `evals/datasets/full_chain_journey_real_replay_v3`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 8 |
| Case | 16 |
| 用户输入 | 192 |
| Eval task | 96 |
| 断言 | 894 |
| LLM 调用 | 1664 |
| Tool 调用 | 9966 |
| 实际 token | 1723080 |
| Replay 首分片耗时 | 3小时55分56秒 |
| 合并 case 观察耗时 | 5小时15分02秒 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 1723080 tokens；同规模复跑可先按 1378464-2067696 tokens 预留。

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
| Card 抽取 | 133 | 152 | 87.5% | 0.396 |
| 成本 / Trace | 459 | 528 | 86.9% | 0.902 |
| 记忆写入 | 51 | 90 | 56.7% | 0.336 |
| Super Agent 问答 | 97 | 124 | 78.2% | 0.502 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_completed_rate` | 16 | 16 | 100.0% | 1.000 |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 30 | 32 | 93.8% | - |
| Card 抽取 | 产物生成 | `card_materialization_rate` | 16 | 16 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 9 | 24 | 37.5% | 0.396 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 32 | 32 | 100.0% | - |
| Card 抽取 | 延迟 | `input_to_card_latency` | 32 | 32 | 100.0% | - |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 30 | 32 | 93.8% | - |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 7 | 12 | 58.3% | 0.583 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 32 | 32 | 100.0% | - |
| 成本 / Trace | Agent 循环控制 | `loop_detection_absence` | 7 | 16 | 43.8% | - |
| 成本 / Trace | Agent 循环控制 | `max_turns_absence` | 10 | 16 | 62.5% | - |
| 成本 / Trace | Agent 覆盖 | `llm_agent_coverage` | 16 | 16 | 100.0% | 1.000 |
| 成本 / Trace | App 行为仿真 | `app_operation_sequence_completeness` | 12 | 16 | 75.0% | 0.813 |
| 成本 / Trace | Token 成本 | `cost_per_input` | 16 | 16 | 100.0% | 0.810 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 16 | 16 | 100.0% | 0.821 |
| 成本 / Trace | Trace 完整性 | `trace_completeness` | 16 | 16 | 100.0% | - |
| 成本 / Trace | 任务收敛 | `active_task_count_budget` | 15 | 16 | 93.8% | - |
| 成本 / Trace | 任务收敛 | `failed_task_count_budget` | 13 | 16 | 81.3% | - |
| 成本 / Trace | 任务收敛 | `operation_settlement_rate` | 12 | 16 | 75.0% | 0.981 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 12 | 16 | 75.0% | - |
| 成本 / Trace | 修正 / 冲突更新 | `correction_operation_coverage` | 16 | 16 | 100.0% | 0.500 |
| 成本 / Trace | 功能触发覆盖 | `feature_trigger_coverage` | 10 | 16 | 62.5% | 0.875 |
| 成本 / Trace | 噪声鲁棒性 | `noise_resilience_coverage` | 14 | 16 | 87.5% | 0.875 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 16 | 16 | 100.0% | - |
| 成本 / Trace | 工具覆盖 | `tool_diversity` | 16 | 16 | 100.0% | 1.000 |
| 成本 / Trace | 延迟 | `latency_budget` | 16 | 16 | 100.0% | - |
| 成本 / Trace | 测试框架不变量 | `root_invariant_absence` | 16 | 16 | 100.0% | - |
| 成本 / Trace | 用户旅程覆盖 | `journey_stage_coverage` | 14 | 16 | 87.5% | 0.938 |
| 成本 / Trace | 用户旅程覆盖 | `journey_time_span_coverage` | 14 | 16 | 87.5% | 0.946 |
| 成本 / Trace | 用户旅程覆盖 | `operation_success_rate` | 12 | 16 | 75.0% | 0.981 |
| 成本 / Trace | 用户旅程覆盖 | `record_operation_coverage` | 14 | 16 | 87.5% | 0.938 |
| 成本 / Trace | 用户旅程覆盖 | `scenario_family_coverage` | 14 | 16 | 87.5% | 0.958 |
| 成本 / Trace | 用户画像区分 | `persona_specificity_coverage` | 16 | 16 | 100.0% | 1.000 |
| 成本 / Trace | 稳定性 | `failed_task_rate` | 16 | 16 | 100.0% | 0.997 |
| 成本 / Trace | 稳定性 | `retry_rate` | 16 | 16 | 100.0% | 1.000 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 16 | 16 | 100.0% | 1.000 |
| 成本 / Trace | 跨日连续性 | `cross_day_continuity_coverage` | 14 | 16 | 87.5% | 0.925 |
| 成本 / Trace | 输入多样性 | `input_channel_diversity` | 14 | 16 | 87.5% | 0.982 |
| 成本 / Trace | 追问闭环 | `follow_up_query_coverage` | 12 | 16 | 75.0% | 0.750 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 16 | 16 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 10 | 32 | 31.3% | 0.471 |
| 记忆写入 | 产物生成 | `memory_artifact_presence` | 6 | 16 | 37.5% | 0.563 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 4 | 42 | 9.5% | 0.095 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 32 | 32 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 15 | 16 | 93.8% | 0.969 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 32 | 32 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：1664
- 工具调用次数：9966
- Token 总量：1723080
- 单次 LLM 平均 token：1035.505
- 平均延迟：10731.380 ms
- P95 延迟：69000.000 ms
- Replay 首分片耗时：3小时55分56秒
- Case 观察耗时累计：5小时15分02秒
- Benchmark 评分耗时：0秒

### 观测指标分层

| 类别 | 指标 | 数值 |
| --- | --- | ---: |
| 旅程执行 | 操作成功率 | 98.5% |
| 旅程执行 | 需等待操作收敛率 | 98.2% |
| 旅程执行 | 记录操作数 | 180 |
| 后台任务 | active / failed / retrying | 1 / 3 / 0 |
| 后台任务 | loopDetection / maxTurns | 9 / 6 |
| 测试框架 | root invariant failures / checks | 0 / 180 |
| 产物健康 | Card materialized / completed | 100.0% / 100.0% |
| 产物健康 | Memory entries / sourced | 28 / 0 |
| 成本行为 | 缓存 token / thought token | 7308864 / 0 |

#### 任务类型分布

| Item | Count |
| --- | ---: |
| `fts_index_update` | 694 |
| `card_agent_task` | 180 |
| `comment_agent_task` | 180 |
| `handle_analyze_assets` | 180 |
| `pkm_agent_task` | 180 |
| `schedule_refresh_router_task` | 180 |
| `schedule_aggregator_task` | 15 |
| `process_ai_reply` | 13 |
| `knowledge_insight_task` | 12 |

#### Active 任务类型

| Item | Count |
| --- | ---: |
| `schedule_aggregator_task` | 1 |

#### 失败任务类型

| Item | Count |
| --- | ---: |
| `pkm_agent_task` | 3 |

#### LLM 调用 by agent

| Item | Count |
| --- | ---: |
| `pkm_agent` | 651 |
| `schedule_refresh_router_agent` | 366 |
| `knowledge_insight_agent` | 257 |
| `schedule_aggregator_agent` | 190 |
| `card_agent` | 181 |
| `comment_agent` | 19 |

#### Token by agent

| Item | Count |
| --- | ---: |
| `pkm_agent` | 1078574 |
| `card_agent` | 345058 |
| `knowledge_insight_agent` | 110893 |
| `schedule_refresh_router_agent` | 65276 |
| `schedule_aggregator_agent` | 62893 |
| `comment_agent` | 60386 |

#### Tool 调用 by name

| Item | Count |
| --- | ---: |
| `Read` | 361 |
| `save_timeline_card` | 149 |
| `Grep` | 136 |
| `LS` | 112 |
| `update_timeline_card_insight` | 112 |
| `save_knowledge_insight_cards` | 107 |
| `skip_schedule_refresh` | 93 |
| `Write` | 73 |
| `Glob` | 70 |
| `mark_schedule_dirty` | 64 |
| `Edit` | 60 |
| `BatchRead` | 48 |

#### 操作耗时分布

| Operation | Count | Avg | Max |
| --- | ---: | ---: | ---: |
| `ask_super_agent` | 24 | 35秒 | 2分26秒 |
| `fetch_timeline` | 13 | 0秒 | 0秒 |
| `post_comment` | 13 | 15秒 | 23秒 |
| `record` | 180 | 1分12秒 | 11分34秒 |
| `refresh_knowledge_insights` | 12 | 3分39秒 | 8分46秒 |
| `refresh_schedule_aggregation` | 13 | 1分39秒 | 3分00秒 |
| `wait_memory` | 12 | 1分10秒 | 2分00秒 |

## 失败样本

- `journey_real_replay_v3_01_a_cost` / `task_completion_status`：后台任务没有全部正常结束。settled=false, active_tasks=0, failed_tasks=1, failed_details=pkm_agent_task:failed:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, LLM Diagnosis detecte....
- `journey_real_replay_v3_01_a_cost` / `failed_task_count_budget`：后台任务收敛或 Agent 循环控制不达标。failed_task_count=1, max=0.
- `journey_real_replay_v3_01_a_cost` / `loop_detection_absence`：后台任务收敛或 Agent 循环控制不达标。loop_detection_tasks=1, max=0.
- `journey_real_replay_v3_01_a_cost` / `operation_success_rate`：真实用户旅程操作成功率不足。operation_success_rate=0.917, min=0.95.
- `journey_real_replay_v3_01_a_cost` / `operation_settlement_rate`：后台任务收敛或 Agent 循环控制不达标。operation_settlement_rate=0.917, min=0.95.
- `journey_real_replay_v3_01_a_cost` / `memory_artifact_presence`：旅程没有沉淀出足够的 memory 产物。memory_entries=1, min=2.
- `journey_real_replay_v3_01_a_cost` / `app_operation_sequence_completeness`：Missing operation types: ask_super_agent, fetch_timeline, post_comment, refresh_knowledge_insights, refresh_schedule_aggregation, wait_memory.
- `journey_real_replay_v3_01_a_cost` / `feature_trigger_coverage`：Missing feature triggers: timeline_browse, comment, knowledge_insight, super_agent.
- `journey_real_replay_v3_01_a_cost` / `follow_up_query_coverage`：follow_up_queries=0, min=2.
- `journey_real_replay_v3_01_a_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v3_01_a_mem_reminder.
- `journey_real_replay_v3_01_a_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v3_01_a_mem_project_owner.
- `journey_real_replay_v3_01_a_card_project` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：Mina.
- `journey_real_replay_v3_01_a_card_boundary` / `title_constraint_accuracy`：标题没有覆盖期望关键词。缺少关键词：导出灰度.
- `journey_real_replay_v3_01_a_super_agent` / `answer_must_include`：Answer missing: 导出灰度, Mina, 上午, 下午不喝.
- `journey_real_replay_v3_01_a_super_agent` / `personalization_accuracy`：Answer missing personalized details: 导出灰度.
- `journey_real_replay_v3_01_a_super_agent_followup` / `answer_must_include`：Answer missing: 不要, 长期记忆.
- `journey_real_replay_v3_01_b_cost` / `loop_detection_absence`：后台任务收敛或 Agent 循环控制不达标。loop_detection_tasks=1, max=0.
- `journey_real_replay_v3_01_b_cost` / `max_turns_absence`：后台任务收敛或 Agent 循环控制不达标。max_turns_tasks=1, max=0.
- `journey_real_replay_v3_01_b_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v3_01_b_mem_reminder.
- `journey_real_replay_v3_01_b_memory` / `memory_must_write_recall`：Missing required memory journey_real_replay_v3_01_b_mem_project_owner.

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

- 运行 ID：`2026-05-18_094510`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v3`
- 观察适配器：`replay_file`
- 证据等级：真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为
- 本地完整日志：`evals/runs/2026-05-18_094510/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-18_094510/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-18_094510/outputs.jsonl`
- 场景样本数：16
- 评估任务数：96
- Replay 首分片耗时：3小时55分56秒
- 合并 case 观察耗时：5小时15分02秒
- Benchmark 评分耗时：0秒
- 断言通过：740/894 （82.8%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_card_boundary` | 未通过 | 2 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_card_boundary` | 通过 | 0 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_card_project` | 通过 | 0 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_card_boundary` | 未通过 | 1 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_card_project` | 未通过 | 1 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_card_boundary` | 未通过 | 2 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_cost` | 未通过 | 9 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_cost` | 未通过 | 2 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_cost` | 未通过 | 3 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_cost` | 未通过 | 4 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_cost` | 未通过 | 1 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_cost` | 未通过 | 16 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_cost` | 未通过 | 10 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_cost` | 通过 | 0 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_cost` | 通过 | 0 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_cost` | 未通过 | 2 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_cost` | 通过 | 0 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_cost` | 通过 | 0 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_cost` | 未通过 | 3 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_cost` | 未通过 | 3 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_cost` | 通过 | 0 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_cost` | 未通过 | 16 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_memory` | 未通过 | 2 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_memory` | 未通过 | 3 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_memory` | 未通过 | 3 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_memory` | 未通过 | 3 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_memory` | 未通过 | 2 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_memory` | 未通过 | 2 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_memory` | 未通过 | 3 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_memory` | 未通过 | 2 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_memory` | 未通过 | 2 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_memory` | 未通过 | 2 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_memory` | 未通过 | 1 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_memory` | 未通过 | 2 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_memory` | 未通过 | 3 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_memory` | 未通过 | 3 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_memory` | 未通过 | 3 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_memory` | 未通过 | 3 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v3_01_a` | `journey_real_replay_v3_01_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_01_b` | `journey_real_replay_v3_01_b_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v3_02_a` | `journey_real_replay_v3_02_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_02_b` | `journey_real_replay_v3_02_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v3_03_a` | `journey_real_replay_v3_03_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v3_03_b` | `journey_real_replay_v3_03_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_04_a` | `journey_real_replay_v3_04_a_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_04_b` | `journey_real_replay_v3_04_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_super_agent` | 未通过 | 2 |
| `journey_real_replay_v3_05_a` | `journey_real_replay_v3_05_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_05_b` | `journey_real_replay_v3_05_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_super_agent` | 通过 | 0 |
| `journey_real_replay_v3_06_a` | `journey_real_replay_v3_06_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_06_b` | `journey_real_replay_v3_06_b_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_07_a` | `journey_real_replay_v3_07_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_super_agent` | 未通过 | 2 |
| `journey_real_replay_v3_07_b` | `journey_real_replay_v3_07_b_super_agent_followup` | 未通过 | 1 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_08_a` | `journey_real_replay_v3_08_a_super_agent_followup` | 通过 | 0 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_super_agent` | 未通过 | 1 |
| `journey_real_replay_v3_08_b` | `journey_real_replay_v3_08_b_super_agent_followup` | 未通过 | 1 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：8
- 输入条数：192
- Eval task 数：96
- Case family 分布：full_chain_journey_real_replay_v3=16
- Task type 分布：card_extraction=32，cost_trace=16，memory_write=16，super_agent_qa=32

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `scale_u_001` | 增长产品经理 | 上海 | zh-CN | 2 | 24 | 12 | 以后 导出灰度 这种重要安排提前一天提醒我，最好把 失败率截图 一起列出来。<br>先记一下旧规则：下午也可以喝咖啡。，等我后面确认再改。 |
| `scale_u_002` | 跨境电商运营 | 深圳 | zh-CN | 2 | 24 | 12 | 以后 北美站增长 这种重要安排提前一天提醒我，最好把 ROAS 分层表 一起列出来。<br>先记一下旧规则：ROAS 低于 1.8 才提醒。，等我后面确认再改。 |
| `scale_u_003` | 数据分析师 | 杭州 | zh-CN | 2 | 24 | 12 | 以后 Memex 评测看板 这种重要安排提前一天提醒我，最好把 hit@3 和 MRR 截图 一起列出来。<br>先记一下旧规则：指标解释可以只写中文名。，等我后面确认再改。 |
| `scale_u_004` | 律师 | 广州 | zh-CN | 2 | 24 | 12 | 以后 合同条款库 这种重要安排提前一天提醒我，最好把 条款来源编号 一起列出来。<br>先记一下旧规则：合同问题可以直接给结论。，等我后面确认再改。 |
| `scale_u_005` | 财务主管 | 成都 | zh-CN | 2 | 24 | 12 | 以后 预算月结 这种重要安排提前一天提醒我，最好把 付款审批表 一起列出来。<br>先记一下旧规则：付款超过五万再提醒。，等我后面确认再改。 |
| `scale_u_006` | 内容运营 | 苏州 | zh-CN | 2 | 24 | 12 | 以后 小红书活动 这种重要安排提前一天提醒我，最好把 素材来源链接 一起列出来。<br>先记一下旧规则：素材复盘只看点赞数。，等我后面确认再改。 |
| `scale_u_007` | 家庭照护者 | 南京 | zh-CN | 2 | 24 | 12 | 以后 妈妈康复计划 这种重要安排提前一天提醒我，最好把 血压记录表 一起列出来。<br>先记一下旧规则：晚间用药按 8 点提醒。，等我后面确认再改。 |
| `scale_u_008` | 研究生 | 北京 | zh-CN | 2 | 24 | 12 | 以后 论文开题 这种重要安排提前一天提醒我，最好把 文献矩阵 一起列出来。<br>先记一下旧规则：文献综述每周日提醒。，等我后面确认再改。 |
