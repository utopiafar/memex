# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/module_smoke`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 10 个 case、10 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：2500；LLM 调用次数：1；工具调用次数：1。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 3 |
| Case | 10 |
| 用户输入 | 6 |
| Eval task | 10 |
| 断言 | 63 |
| LLM 调用 | 1 |
| Tool 调用 | 1 |
| 实际 token | 2500 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 2500 tokens；同规模复跑可先按 2000-3000 tokens 预留。

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
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | PKM 条目路径是否包含期望目录或项目名。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 日程刷新决策是否等于期望的 skip / dirty / refresh。 |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 必须刷新时是否没有漏掉刷新。 |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 无需刷新时是否没有触发重刷新。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | Top 1 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | Top 3 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | Top 5 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 第一个正确来源排名的倒数，越高越好。 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | Top 5 中覆盖了多少期望来源。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 答案引用的来源是否覆盖期望来源。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 路由分类是否等于期望标签。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 7 | 7 | 100.0% | 1.000 |
| 成本 / Trace | 5 | 5 | 100.0% | 0.896 |
| 记忆写入 | 10 | 10 | 100.0% | 1.000 |
| PKM 整理 | 4 | 4 | 100.0% | 1.000 |
| 检索问答 | 9 | 9 | 100.0% | 1.000 |
| 日程刷新 | 11 | 11 | 100.0% | - |
| Super Agent 问答 | 13 | 13 | 100.0% | 1.000 |
| 路由 / 工具调用 | 4 | 4 | 100.0% | - |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 1 | 1 | 100.0% | - |
| Card 抽取 | 字段抽取 | `location_accuracy` | 1 | 1 | 100.0% | - |
| Card 抽取 | 字段抽取 | `participant_recall` | 1 | 1 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 1 | 1 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 1 | 1 | 100.0% | - |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 1 | 1 | 100.0% | 1.000 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 1 | 1 | 100.0% | - |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | 1 | 1 | 100.0% | 1.000 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | 1 | 1 | 100.0% | - |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | 1 | 1 | 100.0% | - |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | 1 | 1 | 100.0% | - |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 1 | 1 | 100.0% | - |
| 成本 / Trace | Token 成本 | `total_token_budget` | 1 | 1 | 100.0% | 0.792 |
| 成本 / Trace | 任务收敛 | `task_completion_status` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 1 | 1 | 100.0% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 1 | 1 | 100.0% | 1.000 |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 2 | 2 | 100.0% | - |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 2 | 2 | 100.0% | - |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 2 | 2 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 2 | 2 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 2 | 2 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 1 | 1 | 100.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 1 | 1 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 2 | 2 | 100.0% | - |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 3 | 3 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 3 | 3 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 3 | 3 | 100.0% | - |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 3 | 3 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：1
- 工具调用次数：1
- Token 总量：2500
- 单次 LLM 平均 token：2500.000
- 平均延迟：5366.667 ms
- P95 延迟：8000.000 ms
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-module-smoke`
- 数据集：`evals/datasets/module_smoke`
- 观察适配器：`fixture`
- 场景样本数：10
- 评估任务数：10
- Benchmark 评分耗时：0秒
- 断言通过：63/63 （100.0%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_card_event_001` | `task_card_event_001` | 通过 | 0 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_cost_trace_001` | `task_cost_trace_001` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_memory_write_001` | `task_memory_write_001` | 通过 | 0 |
| `module_memory_conflict_001` | `task_memory_conflict_001` | 通过 | 0 |

#### PKM 整理

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_pkm_organization_001` | `task_pkm_organization_001` | 通过 | 0 |

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_retrieval_qa_001` | `task_retrieval_qa_001` | 通过 | 0 |

#### 日程刷新

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_schedule_refresh_001` | `task_schedule_refresh_001` | 通过 | 0 |
| `module_schedule_skip_001` | `task_schedule_skip_001` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_super_agent_qa_001` | `task_super_agent_qa_001` | 通过 | 0 |

#### 路由 / 工具调用

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_router_tool_001` | `task_router_tool_001` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：3
- 输入条数：6
- Eval task 数：10
- Case family 分布：card_extraction=1，cost_trace=1，memory_conflict=1，memory_write=1，pkm_organization=1，retrieval_qa=1，schedule_refresh=2，super_agent_qa=1，tool_calling=1
- Task type 分布：card_extraction=1，cost_trace=1，memory_write=2，pkm_organization=1，retrieval_qa=1，schedule_refresh=2，super_agent_qa=1，tool_calling=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 5 | 1 | 5 | 下周三晚上七点提醒我去望京和 Jason 讨论投流预算。 |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 3 | 4 | 3 | 以后重要会议尽量提前一天提醒我，别临近了才说。<br>我今天上午想安静一会儿，这只是今天。 |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 2 | 1 | 2 | Memex eval 周报重点写风险、owner 和回滚预案。 |
