# Primary 单链路报告

## Run

- Run dir: `evals/runs/agent-split-v8-r3-primary`
- Score dir: `evals/runs/agent-split-v8-r3-primary-score-v2`
- Pipeline: `split_primary`
- Dataset: `evals/datasets/full_chain_journey_real_replay_v8`
- Case: `journey_real_replay_v8_01`

## 执行结果

| 指标 | 数值 |
| --- | ---: |
| 输入 | 200 |
| 操作 | 270 |
| Eval task | 51 |
| Replay 耗时 | 1h54m34s |
| 断言通过率 | 97.5% |
| 通过 / 总断言 | 353 / 362 |
| Token | 7,014,689 |
| LLM 调用 | 800 |
| Tool 调用 | 4,998 |
| failed task | 0 |
| retrying task | 0 |
| loopDetection / maxTurns | 0 / 0 |

## 关键健康指标

- Operation success rate: 100.0%
- Operation settlement rate: 100.0%
- Card materialization / completed: 100.0% / 100.0%
- Memory entries: 105
- Memory source fact linked entries: 104
- Root invariant failure: 0 / 200

## 分场景得分

| 场景 | 通过 | 总数 | 通过率 |
| --- | ---: | ---: | ---: |
| Cost / Trace | 33 | 33 | 100.0% |
| Memory Write | 118 | 122 | 96.7% |
| Card Extraction | 98 | 100 | 98.0% |
| SuperAgent QA | 104 | 107 | 97.2% |

## 剩余失败

- 4 个 `memory_source_grounding`：重复确认/刷新场景仍有 source id 未精确命中。
- 2 个 `title_constraint_accuracy`：card title 未包含 `导出灰度`。
- 3 个 `unnecessary_uncertainty_absence`：证据足够时仍表达不确定。

## 判断

Primary 已经具备作为可切换旁路继续扩大实验的条件。它完整跑完 200 输入，成本低于预算，总 token 比 Legacy 少约 30.6%，且没有任务失败。仍不建议默认切，因为本轮只执行 1 个用户 shard，且 source/title/uncertainty 仍有小缺口。
