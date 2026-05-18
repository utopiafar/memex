# PKM agent 在真实 replay 中对信息不足/搜索无结果场景反复工具调用，导致 loopDetection 未收敛

GitHub issue: https://github.com/memex-lab/memex/issues/146

## 背景

在 `2026-05-18-full-chain-real-replay-v3-latest-main-skipfix` 真实 LLM 全链路实验中，v3 数据集共 16 case、192 record、304 operations、96 eval task。合入最新 `main` 后，原先“明确不要长期化/噪声/临时状态”的 no-op path 没有复现失败，但仍有 3 个 case 因 `pkm_agent_task` loopDetection retry 到上限而未收敛：

- `journey_real_replay_v3_01_a`
- `journey_real_replay_v3_03_b`
- `journey_real_replay_v3_08_b`

这些失败都发生在 record 阶段。PKM 未完成后，`comment_agent_task` 一直 pending，case 后续的 timeline/comment/schedule/insight/memory/QA 用户旅程无法继续。

## 触发场景 1：缺失领域文件后重复 empty search

Case：`journey_real_replay_v3_01_a`

触发输入：

```text
周末要处理 爸妈体检报告复印件，提醒我不要和 导出灰度 的深度工作冲突。
```

原始日志表现：

```text
record_012 waiting ... pkm_agent_task:retrying#retry1 ... Maximum turns reached ... | comment_agent_task:pending
record_012 waiting ... pkm_agent_task:retrying#retry2 ... Loop detected ... | comment_agent_task:pending
record_012 waiting ... pkm_agent_task:retrying#retry5 ... Loop detected ... | comment_agent_task:pending
record_012 did not settle; stopping remaining operations for this case.
```

失败任务详情：

```text
pkm_agent_task failed, retry_count=5
AgentExceptionCode.loopDetection:
Agent repeatedly executes identical Glob searches ('**/*体检*' and '**/*医疗*') multiple times,
each returning 'No files found', without progressing to alternative actions.
```

PKM state 里的工具轨迹：

```text
Read /Projects/导出灰度安排提醒.md
Read /Areas/个人规则/咖啡饮用规则.md
Glob **/*健康*
Glob **/*体检* -> No files found
Glob **/*医疗* -> No files found
Glob **/*体检* -> No files found
Glob **/*医疗* -> No files found
... 同一组 empty search 反复出现
```

## 触发场景 2：重复创建相同 clarification request

Case：`journey_real_replay_v3_03_b`

触发输入：

```text
下次 上午深度分析 前提醒我检查 hit@3 和 MRR 截图，如果和 Memex 评测看板 冲突就提前一天提示。
```

工具轨迹：

```text
Read /Areas/指标解释规范.md
Read /Projects/Analytics/Memex评测看板进展.md
activate_skills ["ask_clarification"]
create_clarification_request dedupe_key="上午深度分析:时间"
create_clarification_request dedupe_key="上午深度分析:时间"
create_clarification_request dedupe_key="上午深度分析:时间"
create_clarification_request dedupe_key="上午深度分析:时间"
```

每次工具结果都返回同一个 clarification request id：

```text
Clarification request created: 90ad0db4-a1bf-42a2-8863-3a92c3036998
```

最终 `pkm_agent_task` retry 到 5，`comment_agent_task` 保持 pending，case 被停止。

## 触发场景 3：已创建 clarification 后继续重复读取同一文件

Case：`journey_real_replay_v3_08_b`

触发输入：

```text
下次 上午读论文 前提醒我检查 文献矩阵，如果和 论文开题 冲突就提前一天提示。
```

工具轨迹：

```text
Grep "读论文|文献矩阵" -> No matches found
Read /Projects/论文开题准备.md
activate_skills ["ask_clarification"]
create_clarification_request dedupe_key="reading_paper_schedule"
create_clarification_request dedupe_key="thesis_proposal_schedule"
Grep "矩阵|文献矩阵" -> No matches found
Grep "读论文|文献" -> /Areas/学习管理/文献综述安排.md
Read /Areas/学习管理/文献综述安排.md
Grep "读论文|上午读" -> No matches found
Read /Areas/学习管理/文献综述安排.md
Read /Areas/学习管理/文献综述安排.md
Read /Areas/学习管理/文献综述安排.md
Read /Areas/学习管理/文献综述安排.md
```

## 触发条件归纳

- 输入包含提醒/冲突判断，但缺少精确时间，例如“周末”“下次”“上午深度分析”“上午读论文”。
- workspace 中存在部分相关项目资料，但不足以完成冲突判断。
- PKM agent 可以识别需要澄清，或可以发现搜索无结果，但没有把这些状态视为可完成分支。
- LocalTaskExecutor retry 后，agent 会重复走同一死路，最终达到 retry 上限。

## 触发机理

目前 PKM workflow 的完成证据更偏向“写入 P.A.R.A. + 更新 card insight”或显式 skip。对于“信息不足，需要用户补充”的真实场景，成功创建 clarification request 并不是一个被接受的 completion path。于是 agent 会继续寻找更多证据或重复发起相同 clarification。

另外，工具层/handler 层缺少同参工具调用的硬性终止策略。相同 `Glob` / `Grep` 连续返回空结果、相同 `create_clarification_request` dedupe_key 连续命中、相同 `Read` 文件多次读取，都没有把 agent 从当前循环中拉出来。

## 建议解法

1. 将“成功创建或命中 clarification request”纳入 PKM completion evidence。
   - 当缺少时间/对象/范围等关键信息时，PKM 可以更新 card insight 为“已发起澄清，等待用户补充”，然后完成 task。
   - 不应要求这类输入必须产生 P.A.R.A. mutation。

2. `create_clarification_request` 返回更明确的 dedupe 状态。
   - 建议返回 `created=true/false`、`request_id`、`dedupe_key`。
   - 当 `created=false` 或已存在同 key request 时，prompt/handler 应要求停止重复创建。

3. 增加 per-fact negative cache / same-tool-args guard。
   - 同一 `Glob` / `Grep` pattern 连续空结果后，禁止再次调用相同参数。
   - 同一 `Read` 文件连续读取后，如果没有新状态变化，要求进入总结/澄清/降级完成。

4. 对提醒/冲突判断类输入明确 PKM 与 Schedule Agent 的职责边界。
   - PKM 可记录用户偏好和项目资料。
   - 精确提醒时间、冲突检测应交给 schedule agent；信息不足时由 clarification path 收口。

5. 在 `pkm_agent_task` handler 层增加降级完成。
   - 达到 max-turn 或同参工具阈值时，优先保存“部分处理 + 待澄清”的 card insight，而不是让 LocalTaskExecutor 重试同一循环 5 次。

## 验收建议

- 新增单测：PKM 对成功创建 clarification request 的场景应完成，不调用重复 clarification。
- 新增单测：同一 `Glob` / `Grep` empty result 不应重复超过阈值。
- 新增真实 replay 回归样本：复用上述 3 条输入，期望 `pkm_agent_task` completed，`comment_agent_task` 不再被 pending 阻塞。
