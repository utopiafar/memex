# Real Replay v3 未收敛 case 复盘

## 范围

- 实验：`2026-05-18-full-chain-real-replay-v3-latest-main-skipfix`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v3`
- 代码基线：合入 `upstream/main` `4268259` 后的分支提交 `f324450`
- 观测来源：
  - `evals/runs/2026-05-18-full-chain-real-replay-v3-latest-main-skipfix-merged/observations.jsonl`
  - `evals/runs/2026-05-18-full-chain-real-replay-v3-latest-main-skipfix-full.flutter.log`
  - `evals/runs/2026-05-18-full-chain-real-replay-v3-latest-main-skipfix-tail.flutter.log`
  - 各 case 临时 workspace 的 `_System/state_dir/*.json`

本轮 16 个 case 中，case 级 `task_completion_status` 未收敛的共有 4 个。其中 3 个是 `pkm_agent_task` retry 到 5 后 failed，1 个是 `schedule_aggregator_task` 在显式刷新窗口内仍处于 processing。

## 汇总

| Case | 未收敛操作 | 直接阻塞任务 | 最终状态 | 原因分类 |
| --- | --- | --- | --- | --- |
| `journey_real_replay_v3_01_a` | `record_012` | `pkm_agent_task` | failed, retry_count=5 | 主项目逻辑：PKM 对缺失领域文件的重复搜索没有终止路径 |
| `journey_real_replay_v3_03_b` | `record_166` | `pkm_agent_task` | failed, retry_count=5 | 主项目逻辑：PKM 重复创建同一个 clarification request |
| `journey_real_replay_v3_04_a` | `schedule_refresh_001` | `schedule_aggregator_task` | processing, retry_count=1 | 主项目逻辑：Schedule Aggregator 对空时间窗/历史 dirty card 没有 no-op completion path |
| `journey_real_replay_v3_08_b` | `record_166` | `pkm_agent_task` | failed, retry_count=5 | 主项目逻辑：PKM 在 clarification 后继续重复检索/读取同一资料 |

## Case 1: `journey_real_replay_v3_01_a`

### 触发输入

- Operation：`journey_real_replay_v3_01_record_012`
- 时间：`2026-01-08T21:12:00+08:00`
- 渠道：`email_snippet`
- 阶段/场景：`capture` / `correction`
- 原始输入：`周末要处理 爸妈体检报告复印件，提醒我不要和 导出灰度 的深度工作冲突。`

### 原始日志证据

Flutter log 显示前 11 条 record 均已完成，第 12 条从 5 分钟开始进入 `pkm_agent_task` retry，`comment_agent_task` 一直 pending，最终 retry 到 5 后 case 熔断：

```text
full.flutter.log:52  pkm_agent_task:retrying#retry1 ... Maximum turns reached ... | comment_agent_task:pending
full.flutter.log:58  pkm_agent_task:retrying#retry2 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:60  pkm_agent_task:retrying#retry3 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:62  pkm_agent_task:retrying#retry4 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:64  pkm_agent_task:retrying#retry5 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:65  record_012 did not settle; stopping remaining operations for this case.
```

`observations.jsonl` 的失败任务详情：

```text
pkm_agent_task: failed, retry_count=5
AgentExceptionCode.loopDetection:
Agent repeatedly executes identical Glob searches ('**/*体检*' and '**/*医疗*') multiple times,
each returning 'No files found', without progressing to alternative actions.
```

PKM state 中的工具轨迹进一步确认循环形态：

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

### 机理判断

这个输入同时包含两个意图：一个是个人事务提醒，另一个是避免与已有项目深度工作冲突。PKM 先正确读取了已有的 `导出灰度安排提醒.md`，但在处理“爸妈体检报告复印件”时发现没有健康/医疗相关文件，于是不断尝试 `体检` / `医疗` 搜索。搜索连续返回空结果后，agent 没有切换到创建新文件、创建提醒、发起澄清或降级完成，而是反复调用相同 Glob，触发 loopDetection。

这不是测试框架误判：raw state 里确实存在重复工具调用，且下游 `comment_agent_task` 因 PKM 未完成一直 pending。

## Case 2: `journey_real_replay_v3_03_b`

### 触发输入

- Operation：`journey_real_replay_v3_03_record_166`
- 时间：`2026-03-01T08:26:00+08:00`
- 渠道：`email_snippet`
- 阶段/场景：`conflict_resolution` / `schedule`
- 原始输入：`下次 上午深度分析 前提醒我检查 hit@3 和 MRR 截图，如果和 Memex 评测看板 冲突就提前一天提示。`

### 原始日志证据

Flutter log 显示 `record_166` 在 1 分 31 秒进入 retry，随后快速 retry 到 5：

```text
full.flutter.log:359 pkm_agent_task:retrying#retry1 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:361 pkm_agent_task:retrying#retry2 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:362 pkm_agent_task:retrying#retry3 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:363 pkm_agent_task:retrying#retry4 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:364 pkm_agent_task:retrying#retry5 ... Loop detected ... | comment_agent_task:pending
full.flutter.log:365 record_166 did not settle; stopping remaining operations for this case.
```

PKM state 中的工具轨迹：

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

### 机理判断

agent 判断“上午深度分析”缺少具体时间，因此选择创建澄清请求。这个判断本身合理，但成功创建澄清请求后，PKM workflow 没有把“已创建 clarification request”视为可完成状态；dedupe 命中也没有告诉 agent “无需重复创建”。于是 agent 反复调用同一个 `create_clarification_request`，直到 loopDetection。

这里的核心不是 LLM 网络慢，也不是等待窗口不足，而是主项目 completion evidence/工具契约没有覆盖“需要用户补充信息”的完成分支。

## Case 3: `journey_real_replay_v3_04_a`

### 触发输入和操作

前置触发 record：

- Operation：`journey_real_replay_v3_04_record_012`
- 时间：`2026-01-08T21:12:00+08:00`
- 原始输入：`周末要处理 父亲复诊材料，提醒我不要和 合同条款库 的深度工作冲突。`

未收敛操作：

- Operation：`journey_real_replay_v3_04_a_schedule_refresh_001`
- 类型：`refresh_schedule_aggregation`

### 原始日志证据

前 12 条 record、timeline fetch 和 comment 都完成，显式 schedule aggregation 刷新未在 3 分钟窗口内收敛：

```text
full.flutter.log:428 schedule_refresh_001 type=refresh_schedule_aggregation start
full.flutter.log:429 schedule_aggregator_task:pending
full.flutter.log:430 schedule_aggregator_task:processing
full.flutter.log:433 schedule_aggregator_task:retrying#retry1 ... Maximum turns reached ...
full.flutter.log:434 schedule_aggregator_task:processing#retry1 ... Maximum turns reached ...
full.flutter.log:435 schedule_refresh_001 did not settle; stopping remaining operations for this case.
```

Schedule Aggregator state 中的工具轨迹：

```text
get_schedule_cards {"from_date":"2026-05-15","to_date":"2026-05-25"}
-> No temporal cards found in the specified date range.
LS /Cards
Read /Cards/2026/01/05_ts_1.yaml
Read /Cards/2026/01/06_ts_1.yaml
Read /Cards/2026/01/06_ts_2.yaml
Read /Cards/2026/01/08_ts_1.yaml
Read /Cards/2026/01/08_ts_3.yaml
```

assistant thought 里已经识别到关键矛盾：

```text
The refresh_state mentions card IDs like "2026/01/05.md#ts_1"... These are from January 2026,
not within the May 2026 date range. ... get_schedule_cards returned no temporal cards.
```

### 机理判断

Schedule Aggregator 默认按当前真实时间 `2026-05-18` 取 `2026-05-15` 到 `2026-05-25` 的时间窗；但 replay case 的 dirty card 都是 `2026-01` 的历史 card。工具返回空时间窗后，agent 又回读 dirty state 里的历史 cards。它已经能观察到“dirty card 在 January，不在 May aggregation window”，但没有一个合法的完成动作来表示“当前窗口无可聚合 temporal cards，已消费本次 dirty state / 本次刷新 no-op”。最后触发 Maximum turns，retry 后仍处于 processing。

这也是主项目逻辑问题：测试框架只是按照显式 `refresh_schedule_aggregation` 操作等待 3 分钟，状态中确实有一个 active `schedule_aggregator_task` 未终止。

## Case 4: `journey_real_replay_v3_08_b`

### 触发输入

- Operation：`journey_real_replay_v3_08_record_166`
- 时间：`2026-03-01T08:26:00+08:00`
- 渠道：`email_snippet`
- 阶段/场景：`conflict_resolution` / `schedule`
- 原始输入：`下次 上午读论文 前提醒我检查 文献矩阵，如果和 论文开题 冲突就提前一天提示。`

### 原始日志证据

Flutter log 显示 `record_166` 在 2 分 31 秒进入 retry，5 分 03 秒 retry 到上限：

```text
tail.flutter.log:233 pkm_agent_task:retrying#retry1 ... Loop detected ... | comment_agent_task:pending
tail.flutter.log:234 pkm_agent_task:retrying#retry2 ... Loop detected ... | comment_agent_task:pending
tail.flutter.log:235 pkm_agent_task:retrying#retry3 ... Loop detected ... | comment_agent_task:pending
tail.flutter.log:237 pkm_agent_task:retrying#retry4 ... Loop detected ... | comment_agent_task:pending
tail.flutter.log:238 pkm_agent_task:retrying#retry5 ... Loop detected ... | comment_agent_task:pending
tail.flutter.log:239 record_166 did not settle; stopping remaining operations for this case.
```

PKM state 中的工具轨迹：

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

### 机理判断

这个 case 和 `03_b` 同类，但多了一个“先创建两个 clarification request，再继续检索和重复读同一文件”的阶段。agent 已经知道缺少“上午读论文”和“论文开题”的具体时间，并成功创建了澄清请求；之后又继续尝试从已有 `文献综述安排.md` 里找时间信息。该文件只包含“每周五下午提醒，具体时间待确认”，不能满足“上午读论文”的精确冲突判断。agent 没有把“已发起澄清，当前信息不足”作为完成路径，而是重复 Read 同一文件，触发 loopDetection。

## 归因

### 主项目逻辑问题

1. PKM agent 缺少“搜索无结果 / 澄清已创建 / 信息不足”的 completion path。
   - GitHub issue: https://github.com/memex-lab/memex/issues/146
   - 表现为重复 empty search、重复创建同 dedupe_key clarification、重复读取同一文件。
   - 影响 3 个 case，且都会阻塞 `comment_agent_task`，导致剩余用户旅程操作无法继续。

2. Schedule Aggregator 缺少“目标时间窗无 temporal cards / dirty card 不在当前窗口”的 no-op completion path。
   - GitHub issue: https://github.com/memex-lab/memex/issues/147
   - 表现为 `get_schedule_cards` 空结果后继续回读历史 dirty cards，但没有保存空聚合或标记刷新完成。
   - 影响 1 个 case，导致后续 insight/memory/QA 操作没有执行。

### 测试方法/测试框架问题

这 4 个 case 的未收敛不是测试框架导致的误报。框架层面本轮主要问题是全量长跑超过 Flutter test 240 分钟总超时；该问题已经通过 `MEMEX_EVAL_CASE_OFFSET` 和 `MEMEX_EVAL_TEST_TIMEOUT_MINUTES` 修复，并记录在 `evals/HARNESS_ENGINEERING.md`。

## 建议的主项目修复

### PKM

- 将“成功创建 clarification request”纳入 PKM task completion evidence：当事实需要用户补充信息，且工具返回已有/新建 clarification id 时，允许 PKM 更新 card insight 后完成任务。
- `create_clarification_request` 对同一 `dedupe_key` 命中时返回更明确的状态，例如 `created=false, existing_id=...`，并在 prompt/handler 中要求立即停止重复创建。
- 对 `Glob` / `Grep` 的空结果增加 negative cache：同一 pattern 连续空结果后，禁止继续重复搜索，必须改为创建新 P.A.R.A. note、创建 clarification 或 no-op complete。
- 给 PKM handler 增加每个 fact 的同参工具调用上限，超过后自动降级为“部分处理完成 + 待用户补充”，避免 LocalTaskExecutor 反复重试同一死路。
- 把 schedule/reminder 的冲突判断从 PKM 里拆出或明确边界：PKM 可以记录用户偏好与项目资料，但具体日程冲突应交给 schedule 相关 agent；信息不足时由 clarification path 收口。

### Schedule Aggregator

- Aggregator 的目标窗口应从 dirty state / card timestamp / replay clock 中明确传入，避免总是按真实 wall clock 聚合。
- 当 `get_schedule_cards` 在目标窗口为空时，保存一个空 aggregation 或 no-op result，并标记本轮 dirty state 已消费。
- 对 dirty card 在目标窗口外的情况，生成诊断 summary 并完成，而不是继续读历史 card。
- `Maximum turns reached` 后不要让 task 长时间保持 active processing；handler 应把它转成 failed 或 degraded completion，方便 UI 和测试明确收敛。

## 已创建 GitHub issue

- PKM loopDetection：https://github.com/memex-lab/memex/issues/146
- Schedule Aggregator no-op completion：https://github.com/memex-lab/memex/issues/147
