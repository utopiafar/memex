# PKM agent 对“相对时间提醒 + 项目冲突检查”的输入会重复读取项目文件直到 loopDetection

Upstream issue: https://github.com/memex-lab/memex/issues/154

## 背景

在最新 `upstream/main` 上重新跑 v3 全链路真实 LLM replay 后，前几轮发现的多个 agent 不闭环问题已经明显改善：上一轮未收敛的 `01_a`、`04_a`、`08_b` 本轮都完成了完整 case，Schedule Aggregator 未收敛也没有复现。

但本轮仍有一个硬未收敛 case，集中在 PKM agent：

- 代码基线：`upstream/main` `bb4b9e58d30541585b235aafd416adba226cedb7`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v3`
- 实验：`2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix-full`
- 真实 LLM replay 耗时：4小时19分16秒
- 评分：782/894，87.5%
- 任务健康：active/failed/retrying = 0/1/0
- 唯一 failed task type：`pkm_agent_task`

## 触发场景

Case：`journey_real_replay_v3_03_b`

失败 operation：

- `operation_id`: `journey_real_replay_v3_03_record_166`
- `type`: `record`
- `time`: `2026-03-01T08:26:00+08:00`
- `channel`: `email_snippet`
- `journey_stage`: `conflict_resolution`
- `scenario_family`: `schedule`
- `fact_id`: `2026/03/01.md#ts_1`

原始输入：

```text
下次 上午深度分析 前提醒我检查 hit@3 和 MRR 截图，如果和 Memex 评测看板 冲突就提前一天提示。
```

失败前已有项目文件 `Projects/Memex评测看板.md`：

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

---
<!-- fact_id: 2026/02/28.md#ts_3 -->
```

## 实际行为

Card 侧已经成功完成，生成了待办卡：

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

Schedule router 也不是阻塞点。它判断这是历史测试时间里的已完成任务卡片，不影响当前日程视图，因此走了 `skip_schedule_refresh`。

真正失败的是 PKM agent。Flutter replay 状态日志显示：

```text
record_166 waiting ... pkm_agent_task:processing
record_166 waiting ... pkm_agent_task:retrying#retry1 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry2 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry3 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry4 ... loopDetection
record_166 waiting ... pkm_agent_task:retrying#retry5 ... loopDetection
record_166 type=record did not settle; stopping remaining operations for this case.
```

`outputs.jsonl` 中的 failed task：

```text
pkm_agent_task:failed
retry_count=5
AgentException(code: AgentExceptionCode.loopDetection, message: Loop detected, Tool call loop detected: Same tool called 5 times.)
```

PKM agent state 里能看到同一路径被重复读取：

```json
{
  "factId": "2026/03/01.md#ts_1",
  "totalLoopCount": 10,
  "read_calls": [
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}",
    "{\"file_path\":\"/Projects/Memex评测看板.md\"}"
  ]
}
```

PKM agent 的 thought 反复表达了同一个判断：这是提醒请求，“下次 上午深度分析”缺少具体日期/时间，可能需要澄清；但它没有稳定地进入澄清后完成或 no-op 完成路径，而是继续读取 `Projects/Memex评测看板.md` 试图推断上下文。

## 触发机理

这个输入同时包含：

- 提醒意图：`提醒我检查 hit@3 和 MRR 截图`
- 相对时间锚点：`下次 上午深度分析 前`
- 项目冲突检查：`如果和 Memex 评测看板 冲突就提前一天提示`

其中 `下次 上午深度分析` 没有具体日期、时间或可解析的 recurrence。项目文件只包含 `Memex评测看板` 的状态、待办和 MRR 指标，不包含“上午深度分析”的下一次时间。

因此 PKM agent 能读到项目上下文，但读不到足以完成调度判断的信息。当前逻辑在“知道信息不足”之后，没有选择终止动作，而是继续尝试读取同一个无新增信息的文件，最终被 generic loopDetection 拦截。

## 期望行为

这里不应该让 PKM task failed。可接受的完成路径包括：

1. Card agent 保存待办卡，PKM 识别为提醒/调度请求且无稳定长期知识需要更新，直接 `skip_pkm_organization` 并 completed。
2. 如果产品希望追问，则 PKM 创建一次 clarification request，说明需要“上午深度分析”的具体时间或 recurrence，然后把当前 PKM task 标记 completed。
3. 如果已有 schedule router/card 已处理提醒语义，PKM 不再尝试从项目文档推断具体时间，只在输入提供稳定项目知识时更新 P.A.R.A.。

## 建议解法

1. 给 PKM agent 增加 reminder/calendar-like 输入的 terminal path：
   - 当输入主要是提醒/日程请求；
   - 且相对时间不可解析；
   - 且没有明确的长期知识写入需求；
   - 则允许 `skip_pkm_organization(reason: reminder_or_calendar_intent)` 作为完成证据。
2. 让 `create_clarification_request` 返回明确 terminal metadata，例如 `completion_status: completed_after_clarification`，并在 `pkm_agent_task` handler 中接受它作为 completed。
3. 增加同一任务内的重复工具调用保护：同一路径 `Read` 结果内容哈希不变且连续重复时，强制下一步只能 no-op / clarification / complete，避免依赖 generic loopDetection 才退出。
4. 梳理职责边界：card/schedule 链路负责提醒和调度；PKM 负责稳定长期知识。提醒类输入不应要求 PKM 从项目文件里推断具体日程。
5. 加回归测试：复用上面的原始输入和 `Projects/Memex评测看板.md` 内容，断言 `pkm_agent_task` completed、failed task 为 0，且不会重复读取同一路径超过阈值。

## 为什么不是测试框架问题

- root invariant 全部通过，Fact/Card 都写在当前 case data root。
- Flutter replay 完整退出 0，case 级熔断按预期只停止该 case 后续操作。
- operation 等待预算是 900 秒，实际约 225898 ms 后已经确认 failed task，不是等待时间太短。
- Card 和 schedule router 已有可用产物/完成路径，失败集中在 PKM agent 的终止逻辑。
- 本轮代理规避方案生效，没有出现 Flutter WebSocket 代理异常。
