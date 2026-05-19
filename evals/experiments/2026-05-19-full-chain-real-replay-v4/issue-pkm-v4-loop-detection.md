# PKM agent 在 v4 高密度真实 replay 中反复读取同一上下文并触发 loopDetection

Upstream issue: https://github.com/memex-lab/memex/issues/163

## 背景

在 v4 全链路真实 LLM replay 中，系统设计侧前几轮已修复的问题有明显改善，但 PKM agent 仍出现新的成规模不闭环形态：不是单个相对时间提醒，而是在多 persona、多项目、多场景的高密度输入中，PKM agent 会反复读取/检索同一上下文，最终触发 `loopDetection`，导致当前 case 后续用户旅程被熔断。

本 issue 关联但不同于 #154。#154 聚焦“相对时间提醒 + 项目冲突检查”的单一输入；本轮 v4 复现面更广，覆盖协作复盘、项目联系人、纠错、社区协作、合规边界、隐私安全、供应商/家庭事务冲突等场景。

实验信息：

- 数据集：`evals/datasets/full_chain_journey_real_replay_v4`
- 规模：12 persona、36 case、432 条 record、684 个计划操作、216 个 eval task
- 真实 LLM：`mimo-v2-pro`
- 评分：1563/2013，断言通过率 77.6%
- 任务健康：active/retrying 为 0，failed task 为 12
- 唯一 hard failed task type：`pkm_agent_task`，12/12 个硬未收敛 case 都集中在 PKM
- 相关指标：`task_completion_status` 24/36，`operation_settlement_rate` 24/36，`loop_detection_absence` 16/36，`max_turns_absence` 28/36

## 代表复现场景

### 职业协作复盘

Case：`journey_real_replay_v4_10_c`

```text
复盘一下最近 订阅计费重构 里的协作方式，重点看 Nora 的反馈和我自己的表达边界。
```

结果：

- 第 10 条 record 早停，后续 timeline/comment/schedule/insight/Super Agent 操作都没有执行。
- `pkm_agent_task` retry 到 5 次后 failed。
- trace 中该 fact 的 PKM 工具序列为 24 次连续 `Read`。

### 社区协作和公开材料边界

Case：`journey_real_replay_v4_03_c`

```text
Memex 评测看板 的社区协作要确认 hit@3 和 MRR 截图，志愿者反馈和公开材料要分开记录。
```

结果：

- 第 11 条 record 早停。
- `pkm_agent_task` retry 到 5 次后 failed。
- trace 中该 fact 的 PKM 工具序列为 24 次连续 `BatchRead`。

### 隐私/医疗边界

Case：`journey_real_replay_v4_07_c`

```text
涉及 医疗记录只能提醒和整理，不能替代医生判断。，回答时必须标明证据来源，不要把敏感信息写进公开总结。
```

结果：

- 第 8 条 record 早停。
- 首轮表现为 `Maximum turns reached`，之后进入 LLM diagnosis loop。
- trace 显示该 fact 的 PKM 工具调用累计 366 次：`Read` 192 次，`Grep` 174 次。

### 家庭事务与项目深度工作冲突

Case：`journey_real_replay_v4_12_a`

```text
周末要处理 孩子托管时间，提醒我不要和 社区阅读计划 的深度工作冲突。
```

结果：

- 第 12 条 record 早停。
- `pkm_agent_task` retry 到 5 次后 failed。
- 错误中 LLM diagnosis 明确指出：Agent 反复读取 `提醒规则.md` 和 `社区阅读计划.md`，重复同一分析，没有推进到更新文件或创建提醒。
- trace 显示该 fact 的 PKM 工具序列为 360 次 `Read`。

## 触发条件归纳

这批输入通常同时满足几类条件：

1. 输入不是纯粹新增事实，而是“复盘/边界/纠错/提醒/来源约束”的混合意图。
2. 需要读既有项目上下文，但读到的上下文不足以直接唯一决定下一步写入。
3. 正确行为可能是 no-op、只写一条轻量规则、创建澄清/提醒，或把职责交给 card/schedule/comment 链路。
4. PKM agent 已经能找到相关上下文，却没有稳定 terminal action，于是持续 Read/Grep/BatchRead 同一材料。
5. 当前终止主要依赖 generic loopDetection，而不是 PKM 自己基于“无新增信息/无稳定长期知识”的业务完成路径。

## 期望行为

这些输入不应该让 PKM task failed。合理完成路径包括：

- 对只读边界/来源约束：写入一条明确、去重的 PKM rule，或判断已有规则覆盖后 no-op completed。
- 对提醒/调度类语义：card/schedule 负责提醒；PKM 如果没有稳定长期知识，走 `skip_pkm_organization(reason: reminder_or_schedule_intent)`。
- 对纠错/覆盖旧规则：只更新相关 preference/rule，不能在项目文件之间反复搜索。
- 对信息不足但需要追问：创建一次 clarification request，然后把当前 task 标记 completed，而不是继续读同一文件。
- 对敏感/公开边界：可写成一条项目公开总结边界；如果已有同类规则，no-op completed。

## 建议解法

1. 给 PKM agent 增加“候选动作决策”阶段：每条输入先分类为 `write_rule` / `update_project` / `noop` / `clarify` / `delegate_to_schedule`，并要求后续只能落到其中一个 terminal action。
2. 扩展 `skip_pkm_organization` 的业务理由枚举：覆盖 `already_covered`、`not_long_term`、`handled_by_schedule`、`insufficient_source`、`privacy_boundary_no_public_write` 等。
3. 在 handler 层接受 `skip_pkm_organization` / `create_clarification_request` / `write_boundary_rule` 等作为明确 completed 证据，避免 agent “知道该停但停不下来”。
4. 加工具调用本地保护：同一 fact 内连续读取同一路径或同一查询结果内容哈希不变时，下一步必须选择 terminal action，不能继续 Read/Grep/BatchRead。
5. 对 `Read/Grep/BatchRead` 增加 per-fact budget，超过阈值时返回结构化错误，指导 agent 输出 no-op/clarification，而不是让 generic loopDetection 结束任务。
6. 增加回归用例：直接复用本 issue 的代表样例，断言 `pkm_agent_task` completed、failed task 为 0，并校验同一 fact 下同类工具不会连续调用超过阈值。

## 为什么不是测试框架问题

- 本轮 root invariant 全部通过：`root_invariant_absence` 36/36。
- Card 产物健康是 100%：`card_materialization_rate` 36/36，`card_completed_rate` 36/36。
- 失败任务类型只有 `pkm_agent_task`，没有 card/schedule/comment/fts 的 hard fail。
- Replay 三个 shard 都完整退出 0，并合并 216 条 observation 评分。
- Flutter 代理规避已生效，没有 `flutter_tester` WebSocket 问题。
- 每个 operation 等待预算为 15 分钟，失败任务通常在 3-9 分钟内已经进入 failed，不是单纯等待窗口太短。
