# Schedule Aggregator 对空时间窗/历史 dirty card 缺少 no-op completion path，真实 replay 中 max-turn 后未收敛

GitHub issue: https://github.com/memex-lab/memex/issues/147

## 背景

在 `2026-05-18-full-chain-real-replay-v3-latest-main-skipfix` 真实 LLM 全链路实验中，`journey_real_replay_v3_04_a` 的 record、timeline fetch、comment 都已完成，但显式 `refresh_schedule_aggregation` 操作未收敛。最终 case 停在 active `schedule_aggregator_task`：

```text
active_tasks=1
active_task_type_counts={"schedule_aggregator_task":1}
retry_count=1
error=AgentExceptionCode.loopDetection: Maximum turns reached (20). Possible infinite loop.
```

## 触发场景

前置输入：

```text
周末要处理 父亲复诊材料，提醒我不要和 合同条款库 的深度工作冲突。
```

未收敛操作：

```text
journey_real_replay_v3_04_a_schedule_refresh_001
type=refresh_schedule_aggregation
```

Flutter log：

```text
schedule_refresh_001 type=refresh_schedule_aggregation start
schedule_aggregator_task:pending
schedule_aggregator_task:processing
schedule_aggregator_task:retrying#retry1 ... Maximum turns reached ...
schedule_aggregator_task:processing#retry1 ... Maximum turns reached ...
schedule_refresh_001 did not settle; stopping remaining operations for this case.
```

## 原始状态证据

Schedule Aggregator state 的工具调用：

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

assistant thought 中已经识别到矛盾：

```text
The refresh_state mentions card IDs like "2026/01/05.md#ts_1"... These are from January 2026,
not within the May 2026 date range. ... get_schedule_cards returned no temporal cards.
```

## 触发条件

- replay case 的用户输入时间在 `2026-01`，dirty state 里关联的 card 也是 `2026-01`。
- 实验运行时真实 wall clock 是 `2026-05-18`。
- Aggregator 默认按当前真实时间取 `2026-05-15` 到 `2026-05-25` 时间窗。
- `get_schedule_cards` 在这个 May 窗口里返回空，但 dirty state 仍指向 January cards。

## 触发机理

Schedule Aggregator 同时看到两组互相冲突的上下文：

1. 当前聚合窗口是 May 15-25，窗口内没有 temporal cards。
2. dirty state 说 January 的若干 cards 需要刷新。

agent 之后回读 January cards，尝试理解为何 dirty，但没有一个合法工具路径表达“当前窗口无可聚合内容，本次刷新 no-op / dirty state 已消费”。由于没有保存空 aggregation、没有标记完成，也没有把 dirty card 在窗口外作为终止条件，最终在思考和读取之间耗尽 max turns。

这不是测试窗口太短导致的误报：在 3 分钟内 task 已经触发 `Maximum turns reached` 并进入 retry1，但仍保持 processing，导致 case 无法继续后续 insight/memory/QA 操作。

## 建议解法

1. 明确 schedule aggregation 的目标时间窗来源。
   - replay/历史 card 场景应使用 case clock 或 dirty card timestamp 推导目标窗口。
   - 不应只依赖真实 wall clock，否则历史输入会被聚合到错误窗口。

2. 增加空窗口 no-op completion path。
   - 当 `get_schedule_cards` 返回空时，保存一个空 aggregation 或 no-op result。
   - no-op result 应包含原因，例如 `no_temporal_cards_in_window`。
   - 同时标记本次 dirty state 已消费，避免下次继续刷同一批 card。

3. 处理 dirty card 在目标窗口外的情况。
   - 如果 dirty card 全部在窗口外，生成诊断 summary 并完成。
   - 如果部分在窗口内，只聚合窗口内 cards，对窗口外 cards 记录 skipped reason。

4. max-turn 后要进入终态。
   - task handler 应把 `Maximum turns reached` 转成 failed 或 degraded completion，而不是保持 active processing。
   - 这样 UI 和 replay harness 可以明确区分“聚合失败”与“仍在执行”。

## 验收建议

- 单测：`get_schedule_cards` 空结果时，`schedule_aggregator_task` 应 completed，并保存 no-op aggregation。
- 单测：dirty card timestamp 与当前 wall clock 不一致时，Aggregator 应使用传入窗口或 card timestamp，不应无限回读历史 card。
- replay 回归：复用 `journey_real_replay_v3_04_a_schedule_refresh_001`，期望 3 分钟内 task settled，后续 insight/memory/QA 操作继续执行。
