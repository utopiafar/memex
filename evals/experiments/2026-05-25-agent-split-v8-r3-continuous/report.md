# Memex Agent Split v8 R3 连续用户实验报告

## 结论

- 本轮新实验使用 `full_chain_journey_real_replay_v8`，数据集已扩到 12 个用户、每用户 200 条输入、共 2400 条输入；本次实际执行同一 shard：`case_offset=0, case_limit=1`，即 1 个连续用户、200 条输入、270 个端到端操作、51 个 eval task。
- `split_primary` 完整跑完 200 条输入和 270 个操作，评分 `353/362 = 97.5%`，0 failed task、0 retrying task、0 loopDetection、0 maxTurns。
- `legacy_pkm` 在同一 shard 的第 120 条输入后，于 `journey_real_replay_v8_01_f_schedule_refresh_001` 触发 `schedule_aggregator_task` max-turn/loop guard，剩余 80 条输入和后半段端到端操作被停止；评分 `292/362 = 80.7%`。
- 本轮修复后，Primary 的 memory source grounding 从 r2 的 `13/23` 提升到 `19/23`；SuperAgent 必答 bit 在中文等价判分修正后全部通过。
- 不建议默认切到 Primary 的理由仍成立：虽然本 shard 明显优于 Legacy，但样本仍是 1 个用户 shard，且 Primary 仍有 4 个 source 精确命中、2 个 card title、3 个不必要不确定问题，需要多用户分片继续确认。

## 数据集

| 项目 | 数值 |
| --- | ---: |
| Dataset | `memex_full_chain_journey_real_replay_v8` |
| 全量用户数 | 12 |
| 全量输入数 | 2400 |
| 全量操作数 | 3240 |
| 全量 eval task | 612 |
| 每用户输入 | 200 |
| 每用户窗口 | 10 |
| 本次执行用户 | 1 |
| 本次执行输入 | 200 |
| 本次执行操作 | 270 |
| 本次执行 eval task | 51 |
| 时间覆盖 | 2026-01-05 到 2026-07-10，约 186 天 |

本次每个用户的 200 条输入由 10 个时间窗口合并成一个连续 case。每个窗口包含 record、timeline browse、comment、schedule refresh、knowledge insight refresh、memory wait、SuperAgent quick query 和 follow-up query。

## 方法

- 两条链路隔离运行，不共存对照：先跑 `split_primary`，再用同一 case 跑 `legacy_pkm`。
- 输入一致：同一份 `evals/datasets/full_chain_journey_real_replay_v8/cases.jsonl`，同一个 `case_offset=0, case_limit=1`。
- 模型一致：评估链路使用 DeepSeek endpoint；embedding 使用 OpenRouter `perplexity/pplx-embed-v1-4b`。
- 评分一致：用 `replay_file` adapter 对真实 Memex replay observation 评分。
- 本轮还修正了评分器的中文等价判断：`不可合并同一条结论` 视为命中 `不能混在同一条结论里`。

## 对比结果

| 指标 | Primary | Legacy |
| --- | ---: | ---: |
| 断言通过率 | 97.5% | 80.7% |
| 通过 / 总断言 | 353 / 362 | 292 / 362 |
| Replay 耗时 | 1h54m34s | 1h23m45s |
| 实际完成输入 | 200 / 200 | 120 / 200 |
| 实际完成操作 | 270 / 270 | 158 / 270 |
| Token 总量 | 7,014,689 | 10,109,550 |
| LLM 调用 | 800 | 901 |
| Tool 调用 | 4,998 | 5,763 |
| 失败任务 | 0 | 1 |
| loopDetection / maxTurns | 0 / 0 | 1 / 1 |
| record 平均耗时 | 23.60s | 30.53s |
| schedule refresh 平均耗时 | 53.75s | 82.34s |
| insight refresh 平均耗时 | 105.32s | 97.71s |
| SuperAgent 平均耗时 | 24.01s | 32.18s |

Legacy 的 Replay 耗时更短是因为它在第 120 条输入后停止了，不代表更快。

## 分场景

| 场景 | Primary | Legacy |
| --- | ---: | ---: |
| Cost / Trace | 33 / 33, 100.0% | 21 / 33, 63.6% |
| Memory Write | 118 / 122, 96.7% | 109 / 122, 89.3% |
| Card Extraction | 98 / 100, 98.0% | 74 / 100, 74.0% |
| SuperAgent QA | 104 / 107, 97.2% | 88 / 107, 82.2% |

## Primary 剩余问题

- `memory_source_grounding`: 19/23。仍有 4 个 source id 未精确命中，集中在 project owner、latest preference、reminder rule 的重复确认/刷新来源。
- `title_constraint_accuracy`: 18/20。两个 card title 没包含期望关键词 `导出灰度`。
- `unnecessary_uncertainty_absence`: 7/10。三次回答在证据足够时仍表达了不必要的不确定。

## Legacy 失败根因

Legacy 的关键失败是 `schedule_aggregator_task`：

```text
NonRetryableAgentLoopException: Schedule aggregation reached the max-turn guard.
```

因此后续 g/h/i/j 窗口没有真实产物，导致 record coverage、time span、cross-day continuity、noise/correction/follow-up coverage、后半段 card / SuperAgent / memory 指标连带下降。

## 本轮改动

- 生成 v8 连续用户数据集：同一 persona 的 10 个窗口合并成一个连续 case，每 case 200 条输入。
- Memory atom 增加最小引用字段：`source_fact_ids`、`kind`、`entities`、`confidence`、`scope` 等。
- Memory tool schema 要求 object-style atom 至少包含 `content` 与 `source_fact_ids`，并兼容 `source_ids` / `source_references` alias。
- MemoryAgent 增加 source refresh 指引：当用户用“最新 / 以这条为准 / 覆盖 / 修正”等语言确认同一长期事实时，保留更新来源。
- 评估器修正连续用户 source grounding：对同一内容匹配的所有 candidate 汇总 source，而不是只看第一个 best match。
- 评估器修正中文等价：边界句允许“不可合并同一条结论”等表达。

## 建议

- 保持产品开关，不默认切：Primary 明显优于 Legacy，但仍需跑更多用户 shard。
- 下一轮优先补 Primary 剩余 9 个失败：source refresh 可以考虑工具层显式 update/merge source；card title 需要检查 card prompt；不必要不确定需要调 SuperAgent 回答策略。
- Legacy 的 schedule aggregation max-turn 应作为旧链路风险记录，不建议为对比强行放宽预算。
