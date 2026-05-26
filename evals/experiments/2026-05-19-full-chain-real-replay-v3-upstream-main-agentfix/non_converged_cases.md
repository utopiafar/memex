# 未收敛 Case 复盘

## 结论

本轮只有 1 个硬未收敛 case：`journey_real_replay_v3_03_b` 在 `journey_real_replay_v3_03_record_166` 停止。根因是 PKM agent 面对“相对时间提醒 + 项目冲突检查”的输入时，没有进入 no-op / clarification completion path，而是重复读取同一个项目文件，最终触发 `loopDetection`。这属于主项目逻辑问题，不是本轮测试方法或测试框架问题。已提 upstream issue：[memex-lab/memex#154](https://github.com/memex-lab/memex/issues/154)。

本轮 `summary.json` 最终完成 16 个 case，Flutter test 退出 0；case 级熔断只停止了 `03_b` 的后续操作，没有中断整个实验。`status.json` 在测试结束后仍保留最后一次活跃状态快照，因此最终状态以 `summary.json` 和 `metrics.json` 为准。

## 实验上下文

- Run id：`2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix-full`
- 报告目录：`evals/experiments/2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix`
- 本地原始 run 目录：`evals/runs/2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix-full`
- Flutter 状态日志：`evals/runs/2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix-full.flutter.log`
- 代码基线：`upstream/main` `bb4b9e58d30541585b235aafd416adba226cedb7`，当前分支合并提交 `c6dcd7c`
- 数据规模：16 case、192 条计划输入、304 个计划操作、96 个 eval task
- 实际结果：782/894 断言通过，真实 replay 耗时 4小时19分16秒，总 token 1599928

## 总体任务健康

| 指标 | 本轮 |
| --- | ---: |
| active task | 0 |
| failed task | 1 |
| retrying task | 0 |
| loopDetection task | 3 |
| maxTurns task | 2 |
| 最大 retry | 5 |
| failed task type | `pkm_agent_task: 1` |

| 旅程指标 | 本轮 |
| --- | ---: |
| operation_count | 291 |
| successful_operation_count | 290 |
| operation_success_rate | 99.7% |
| task_wait_operation_count | 231 |
| task_wait_settled_count | 230 |
| operation_settlement_rate | 99.6% |
| record_operation_count | 186 |

## 硬未收敛 Case

### 基本信息

- Case：`journey_real_replay_v3_03_b`
- User：`scale_u_003_1779130206888458_5`
- 失败 operation：`journey_real_replay_v3_03_record_166`
- 时间：`2026-03-01T08:26:00+08:00`
- 输入渠道：`email_snippet`
- 用户旅程阶段：`conflict_resolution`
- 场景族：`schedule`
- Fact id：`2026/03/01.md#ts_1`
- Case 内实际执行操作数：6；后续操作因 case 级熔断停止

原始输入：

```text
下次 上午深度分析 前提醒我检查 hit@3 和 MRR 截图，如果和 Memex 评测看板 冲突就提前一天提示。
```

### 运行时证据

`summary.json` 对该 operation 的记录：

```json
{
  "operation_id": "journey_real_replay_v3_03_record_166",
  "type": "record",
  "tasks_settled": false,
  "task_status_counts": {
    "completed": 45,
    "failed": 1
  },
  "elapsed_ms": 225898,
  "task_wait_timeout_ms": 900000
}
```

`outputs.jsonl` 中该 case 的 cost task 失败摘要：

```text
settled=false, active_tasks=0, failed_tasks=1
failed_details=pkm_agent_task:failed:AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, Tool call loop detected: Same tool called 5 times.)
record_operations=6, min=12
memory_entries=0, min=2
```

Flutter 状态日志显示 retry 过程：

```text
record_166 waiting ... pkm_agent_task:processing
record_166 waiting ... pkm_agent_task:retrying#retry1 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry2 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry3 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry4 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry5 ... loopDetection
record_166 type=record did not settle; stopping remaining operations for this case.
```

### 相关上下文

失败前同 case 已有这些事实：

```text
2026/02/27.md#ts_1: 只是试一下 换一个手机壳，不要写成长记忆，也不要影响 Memex 评测看板。
2026/02/27.md#ts_2: 修正一条：指标解释必须保留英文 metric id 和中文解释。，如果之前记录和这个冲突，以这条为准。
2026/02/28.md#ts_1: 学习/复盘：今天关于 客服话术 的笔记想放进 Analytics，但先等来源补齐。
2026/02/28.md#ts_2: 临时插入：指标口径 有突发变化，先提醒我复核来源，不要自动覆盖长期计划。
2026/02/28.md#ts_3: Memex 评测看板 今天卡在 预算余量，和 小陈 对齐后 同时标注跨域影响和证据缺口，指标看 MRR。
2026/03/01.md#ts_1: 下次 上午深度分析 前提醒我检查 hit@3 和 MRR 截图，如果和 Memex 评测看板 冲突就提前一天提示。
```

当时 PKM 项目文件内容：

```markdown
# Memex评测看板

## 当前状态
- 状态：进行中
- 当前卡点：预算余量

## 待办事项
- 与小陈对齐
- 标注跨域影响和证据缺口

## 关注指标
- MRR（月度经常性收入）
```

卡片侧已经成功完成，说明 card agent 不是根因：

```yaml
status: completed
title: 深度分析前检查hit@3和MRR截图
ui_configs:
  -
    template_id: task
    data:
      title: 深度分析前检查hit@3和MRR截图
      subtasks:
        - title: 检查hit@3截图
        - title: 检查MRR截图
        - title: 检查是否与Memex评测看板冲突，若冲突则提前一天提示
      priority: high
```

Schedule router 也不是阻塞点。它识别该卡片是历史测试数据里的已完成记录，不影响当前日程视图，因此走了 `skip_schedule_refresh`。

PKM agent state 中可见同一个 `Read` 调用重复出现：

```json
{
  "metadata": {
    "factId": "2026/03/01.md#ts_1",
    "scene": "input"
  },
  "totalLoopCount": 10,
  "read_calls": [
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}"
  ]
}
```

PKM agent 的 thought 也反复表达同一个判断：这是提醒请求，“下次 上午深度分析”缺少具体日期/时间，可能需要澄清；但它没有终止，也没有稳定地把澄清请求作为完成证据，而是继续读取 `Projects/Memex评测看板.md` 试图推断上下文。

## 触发机理

这个输入同时包含三类意图：

- 提醒意图：`提醒我检查 hit@3 和 MRR 截图`
- 相对时间锚点：`下次 上午深度分析 前`
- 项目冲突检查：`如果和 Memex 评测看板 冲突就提前一天提示`

其中 `下次 上午深度分析` 没有具体日期和时间。项目文件只包含 `Memex评测看板` 的当前状态、待办和 MRR 指标，没有任何可以解析出“上午深度分析”下一次发生时间的信息。

因此，正确行为应该是：卡片可以生成一个待办；日程侧可以要求澄清或跳过不可调度的刷新；PKM 侧如果没有稳定长期知识需要更新，应完成 no-op，或者只创建一次澄清请求并把该任务视为已完成。

实际行为是：PKM agent 已经意识到信息不足，但没有进入终止路径。它继续反复读取同一个无新增信息的项目文件，直到 agent core 的通用工具循环检测拦截。这个失败不是等待预算不够，也不是 Flutter 代理问题；900 秒 operation 预算内，任务在约 3分46秒就以 failed 结束。

## 问题归类

### 项目逻辑问题

- PKM agent 对“提醒/日程类输入 + 相对时间缺失 + 项目上下文冲突检查”缺少稳定的 terminal action。
- `create_clarification_request` 或 `skip_pkm_organization` 这类动作没有覆盖该路径，或者没有被 handler 作为完成证据可靠接收。
- Agent 在重复读取同一路径且内容不变时，缺少本地去重/强制退出保护，只能依赖 generic loopDetection。
- PKM 组织和提醒调度边界不够清晰：提醒语义已经由 card/schedule 链路处理后，PKM 仍试图从项目文档推断调度细节。

### 测试方法/测试框架问题

本 case 的硬失败不是测试框架问题。原因：

- root invariant 通过，Fact/Card 都写在当前 case data root。
- Flutter replay 完整退出 0，`summary.json` 完成 16 case。
- case 级熔断按预期工作：发现 failed task 后停止该 case 后续操作，避免污染更多观察。
- 代理规避方案生效，没有出现 `flutter_tester` WebSocket 代理异常。
- 动态等待预算足够，该 operation 预算 900 秒，实际 225898 ms 后已经确认 failed task。

有一个框架层观察点需要后续优化：`status.json` 结束后没有写 final completed snapshot，仍停在最后一次活跃状态。这不影响最终评分，但容易误导人工巡检；建议后续让 replay 在 suite 结束时写入 `status: completed`、`completed_case_count` 和最终 active/failed/retrying 计数。

## 改进建议

1. 在 PKM handler 中为 calendar/reminder-like 输入增加明确终止路径：当输入主要是提醒或调度请求，且没有稳定长期知识需要更新时，允许 `skip_pkm_organization(reason: reminder_or_calendar_intent)` 作为完成证据。
2. 对无法解析的相对时间创建一次澄清请求后立即完成 PKM 任务，避免 PKM 继续尝试从项目文件推断具体时间。
3. 让 `create_clarification_request` 返回明确的 terminal metadata，例如 `completion_status: completed_after_clarification`，并由 `pkm_agent_task` handler 接受为 completed。
4. 增加同一 agent turn 内重复工具调用保护：如果连续读取同一个文件且内容哈希不变，下一步必须选择 no-op / clarification / complete，而不是继续读取。
5. 强化职责边界：card agent 可以保存待办卡；schedule router 决定是否调度；PKM 只在输入包含稳定项目知识时更新 P.A.R.A.。相对未来提醒不应该要求 PKM 推断具体日程。
6. 加回归测试：用本 case 的原始输入和 `Projects/Memex评测看板.md` 内容构造 fixture，断言 `pkm_agent_task` completed、failed task 为 0，且不会重复读取同一路径超过阈值。

## 可恢复重试观察

本轮还有两个可恢复的 `Knowledge Insight` 重试：

- `journey_real_replay_v3_04_a` 的 `refresh_knowledge_insights` 曾出现 `Maximum turns reached`，retry 后完成，case 总耗时 18分16秒。
- `journey_real_replay_v3_06_b` 的 `refresh_knowledge_insights` 曾出现 `Maximum turns reached`，retry 后完成，case 总耗时 18分41秒。

这两个不是硬未收敛 case，也没有造成 failed task；先作为稳定性观察项记录。若后续出现不可恢复失败，再单独提主项目 issue。
