# Memex Agent 评估报告

## 结论

- 基本可用，但存在需要跟踪的失败项。
- 本次覆盖 14 个 case、15 个 eval task，断言通过率 97.4%。
- 失败断言数：2；Token 总量：32555；LLM 调用次数：16；工具调用次数：16。
- 主要失败项：
  - `memory_pref_001_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_quiet_today: 用户今天上午想安静一会儿。
  - `memory_pref_001_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.

## 运行信息

- 运行 ID：`local_fixture_v1_refresh`
- 数据集：`evals/datasets/v1`
- 观察适配器：`fixture`
- 场景样本数：14
- 评估任务数：15
- 断言通过：75/77 （97.4%）

## 分场景结果

| 场景 | 评估目标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 | 18 | 18 | 100.0% | 1.000 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 | 7 | 7 | 100.0% | 0.557 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 | 11 | 13 | 84.6% | 0.938 |
| 检索问答 | 检查查询时是否召回正确来源，并基于证据回答。 | 25 | 25 | 100.0% | 1.000 |
| 路由 / 工具调用 | 检查路由标签、工具选择、工具参数和禁止工具调用。 | 14 | 14 | 100.0% | - |

## 关键指标与解释

| 指标 | 含义 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | ---: | ---: | ---: | ---: |
| `answer_must_include` | 答案是否包含所有必须提到的信息。 | 3 | 3 | 100.0% | 1.000 |
| `answer_source_citation` | 答案引用的来源是否覆盖期望来源。 | 2 | 2 | 100.0% | 1.000 |
| `card_field_constraint_accuracy` | 指定 card 字段是否包含应保留的细节。 | 1 | 1 | 100.0% | 1.000 |
| `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 | 3 | 3 | 100.0% | - |
| `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 | 3 | 3 | 100.0% | - |
| `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 | 1 | 1 | 100.0% | 1.000 |
| `hallucinated_field_absence` | 是否没有编造禁止字段。 | 3 | 3 | 100.0% | - |
| `latency_budget` | 最大延迟是否未超过预算。 | 2 | 2 | 100.0% | - |
| `location_accuracy` | 地点字段是否包含期望地点。 | 1 | 1 | 100.0% | - |
| `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 | 1 | 1 | 100.0% | - |
| `memory_duplicate_rate` | 重复或近似重复记忆的比例。 | 3 | 3 | 100.0% | 1.000 |
| `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 | 1 | 2 | 50.0% | - |
| `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 | 2 | 2 | 100.0% | 1.000 |
| `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 | 2 | 2 | 100.0% | - |
| `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 | 2 | 3 | 66.7% | 0.833 |
| `participant_recall` | 期望人物是否都被抽取出来。 | 2 | 2 | 100.0% | 1.000 |
| `prohibited_tool_absence` | 是否没有调用被禁止的工具。 | 4 | 4 | 100.0% | - |
| `retrieval_hit_at_1` | Top 1 结果中是否命中任一正确来源。 | 3 | 3 | 100.0% | 1.000 |
| `retrieval_hit_at_3` | Top 3 结果中是否命中任一正确来源。 | 3 | 3 | 100.0% | 1.000 |
| `retrieval_hit_at_5` | Top 5 结果中是否命中任一正确来源。 | 3 | 3 | 100.0% | 1.000 |
| `retrieval_mrr` | 第一个正确来源排名的倒数，越高越好。 | 3 | 3 | 100.0% | 1.000 |
| `retrieval_recall_at_5` | Top 5 中覆盖了多少期望来源。 | 3 | 3 | 100.0% | 1.000 |
| `router_label_accuracy` | 路由分类是否等于期望标签。 | 4 | 4 | 100.0% | - |
| `time_parse_accuracy` | 时间解析是否落在允许误差内。 | 2 | 2 | 100.0% | 1.000 |
| `title_constraint_accuracy` | 标题是否包含关键主题词。 | 3 | 3 | 100.0% | 1.000 |
| `tool_args_accuracy` | 工具参数是否包含期望字段和值。 | 3 | 3 | 100.0% | - |
| `tool_call_budget` | 工具调用次数是否未超过预算。 | 2 | 2 | 100.0% | - |
| `tool_selection_accuracy` | 是否调用了期望工具。 | 3 | 3 | 100.0% | - |
| `total_token_budget` | 总 token 是否未超过预算。 | 2 | 2 | 100.0% | 0.335 |
| `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 | 2 | 2 | 100.0% | - |
| `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 | 3 | 3 | 100.0% | - |

## 成本与 Trace

- LLM 调用次数：16
- 工具调用次数：16
- Token 总量：32555
- 单次 LLM 平均 token：2034.688
- 平均延迟：1504.500 ms
- P95 延迟：3050.000 ms

## 失败样本

- `memory_pref_001_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_quiet_today: 用户今天上午想安静一会儿。
- `memory_pref_001_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.

## 场景任务明细

### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `card_event_001` | `card_event_001_t1` | 通过 | 0 |
| `card_task_002` | `card_task_002_t1` | 通过 | 0 |
| `card_note_003` | `card_note_003_t1` | 通过 | 0 |

### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `card_event_001` | `card_event_001_cost` | 通过 | 0 |
| `cost_trace_002` | `cost_trace_002_t1` | 通过 | 0 |

### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `memory_pref_001` | `memory_pref_001_t1` | 未通过 | 2 |
| `memory_conflict_002` | `memory_conflict_002_t1` | 通过 | 0 |
| `memory_noise_003` | `memory_noise_003_t1` | 通过 | 0 |

### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `retrieval_qa_001` | `retrieval_qa_001_t1` | 通过 | 0 |
| `retrieval_project_002` | `retrieval_project_002_t1` | 通过 | 0 |
| `retrieval_uncertain_003` | `retrieval_uncertain_003_t1` | 通过 | 0 |

### 路由 / 工具调用

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `tool_schedule_001` | `tool_schedule_001_t1` | 通过 | 0 |
| `tool_readonly_001` | `tool_readonly_001_t1` | 通过 | 0 |
| `tool_refresh_002` | `tool_refresh_002_t1` | 通过 | 0 |
| `tool_skip_003` | `tool_skip_003_t1` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：14
- 输入条数：17
- Eval task 数：15
- Case family 分布：card_extraction=3，cost_trace=1，memory_write=3，retrieval_qa=3，tool_calling=4
- Task type 分布：card_extraction=3，cost_trace=2，memory_write=3，retrieval_qa=3，tool_calling=4

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_u_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 1 | 2 | 下周三晚上七点提醒我去望京和老王吃饭 |
| `eval_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 2 | 1 | 以后我都尽量上午安排深度工作，下午开会。<br>我今天上午想安静一会儿。 |
| `eval_u_003` | 跨境电商运营 | 深圳 | zh-CN | 1 | 2 | 1 | 周四下午三点和 Jason 看一下投流预算，记一下。<br>以后订餐提醒我别点海鲜，我最近过敏又犯了。 |
| `eval_u_004` | 工程师 | 上海 | zh-CN | 1 | 1 | 1 | 帮我把明天上午10点半和 Ada 做项目复盘加到日历，地点飞书会议。 |
| `eval_u_005` | 设计师 | 北京 | zh-CN | 1 | 1 | 1 | 我之前说过希望你怎么和我沟通吗？ |
| `eval_u_006` | 财务主管 | 成都 | zh-CN | 1 | 1 | 1 | 周五下班前提醒我把 Q2 预算表发给 Annie，别忘了附上最新现金流预测。 |
| `eval_u_007` | 内容运营 | 上海 | zh-CN | 1 | 1 | 1 | 今天复盘了小红书活动，封面标题带具体数字的笔记点击率明显更高，后面选题要记一下。 |
| `eval_u_008` | 咨询顾问 | 北京 | zh-CN | 1 | 1 | 1 | 我之前说不喝咖啡，但最近又开始喝了，早上可以来一杯。 |
| `eval_u_009` | 游戏策划 | 广州 | zh-CN | 1 | 1 | 1 | 今天突然想喝奶茶，但只是今天，别当成习惯。 |
| `eval_u_010` | 独立开发者 | 杭州 | zh-CN | 1 | 2 | 1 | Memex 评估第一阶段先别追求大量用户，重点是 trace 级 Agent eval 闭环。<br>路由那块先盯 schedule refresh，容易把 skip、dirty、refresh 判错。 |
| `eval_u_011` | 律师 | 深圳 | zh-CN | 1 | 1 | 1 | 以后重要日程提前一天提醒我。 |
| `eval_u_012` | 产品运营 | 厦门 | zh-CN | 1 | 1 | 1 | 把周三的双周复盘改到周四下午4点，参会人还是 Leo 和 Mina。 |
| `eval_u_013` | 数据分析师 | 南京 | zh-CN | 1 | 1 | 1 | 今天这个天气真让人犯困。 |
| `eval_u_014` | 市场经理 | 苏州 | zh-CN | 1 | 1 | 1 | 帮我回顾一下最近三个营销实验的结论，简单归纳就好，别写太长。 |
