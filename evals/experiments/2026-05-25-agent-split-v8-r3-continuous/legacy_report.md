# Legacy 单链路报告

## Run

- Run dir: `evals/runs/agent-split-v8-r3-legacy`
- Score dir: `evals/runs/agent-split-v8-r3-legacy-score`
- Pipeline: `legacy_pkm`
- Dataset: `evals/datasets/full_chain_journey_real_replay_v8`
- Case: `journey_real_replay_v8_01`

## 执行结果

| 指标 | 数值 |
| --- | ---: |
| 计划输入 | 200 |
| 实际完成输入 | 120 |
| 计划操作 | 270 |
| 实际完成操作 | 158 |
| Eval task | 51 |
| Replay 耗时 | 1h23m45s |
| 断言通过率 | 80.7% |
| 通过 / 总断言 | 292 / 362 |
| Token | 10,109,550 |
| LLM 调用 | 901 |
| Tool 调用 | 5,763 |
| failed task | 1 |
| loopDetection / maxTurns | 1 / 1 |

## 中止点

Legacy 在 `journey_real_replay_v8_01_f_schedule_refresh_001` 未收敛，并停止后续操作：

```text
schedule_aggregator_task:failed:NonRetryableAgentLoopException: Schedule aggregation reached the max-turn guard.
```

## 分场景得分

| 场景 | 通过 | 总数 | 通过率 |
| --- | ---: | ---: | ---: |
| Cost / Trace | 21 | 33 | 63.6% |
| Memory Write | 109 | 122 | 89.3% |
| Card Extraction | 74 | 100 | 74.0% |
| SuperAgent QA | 88 | 107 | 82.2% |

## 主要失败

- Cost 超预算：`10,109,550 > 10,000,000`。
- 每输入 token 超预算：`84,246 > 50,000`。
- Task completion 失败：1 个 schedule aggregator failed task。
- Coverage 不足：只完成 120/200 records，journey span 106.25 天，未达到 186 天要求。
- 后续窗口缺产物：g/h/i/j 窗口 card schema/status/title 和 SuperAgent bit recall 大量失败。

## 判断

Legacy 在这个连续用户 shard 上没有稳定跑完整条旅程。它不是“质量略低”，而是在后半程被 schedule aggregation max-turn guard 截断；因此不能作为默认链路的可靠基线，也不能拿未完成后的后半段质量指标和 Primary 做公平逐项内容比较，只能作为旧链路稳定性/成本风险证据。
