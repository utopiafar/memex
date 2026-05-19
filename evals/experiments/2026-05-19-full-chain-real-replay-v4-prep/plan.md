# V4 Full-chain Real Replay 实验准备

## 目标

下一轮真实 LLM 全链路实验在 v3 基础上扩大数据量，并补充按场景、按工具、按工具产物质量拆分的指标观察。

## 数据规模

| 项目 | v3 | v4 | 增幅 |
| --- | ---: | ---: | ---: |
| 用户数 | 8 | 12 | +50% |
| 每用户 replay record | 24 | 36 | +50% |
| 总 replay record | 192 | 432 | +125% |
| Case | 16 | 36 | +125% |
| Operations | 304 | 684 | +125% |
| Eval task | 96 | 216 | +125% |

v4 为了控制单 case 的等待风险，仍保持每个 case 12 条 record；每个用户拆成 3 个窗口，所以总 case 为 12 用户 × 3 window = 36。

## 数据多样性

新增 persona：

- 产品设计师 / 厦门 / 智能相册改版
- 独立开发者 / 武汉 / 订阅计费重构
- 咖啡店主理人 / 青岛 / 春季新品菜单
- 公益项目协调人 / 西安 / 社区阅读计划

新增输入渠道：

- `meeting_note`
- `browser_clip`
- `bank_sms`
- `calendar_clip`
- `receipt_scan`

新增场景族：

- `product_research`
- `vendor_ops`
- `privacy_security`
- `creative_brief`
- `career_growth`
- `community`

保留上一轮高价值问题形态：相对时间提醒、项目冲突检查、不要长期化/no-op、来源不足、跨域边界、最新偏好覆盖、Super Agent 只读追问。

## 指标扩展

本轮新增或强化的通用指标：

- `retrieval_precision_at_1/3/5`
- `citation_precision`
- `citation_recall`

已记录到 `evals/METRICS.md` 的下一步指标口径：

- Super Agent：检索召回、答案完整性、引用质量、只读边界、无证据断言。
- Retrieval tools：`hit@k`、`precision@k`、`recall@k`、`MRR`、`filter_accuracy`。
- PKM/Memory/Card/Schedule：分别看产物是否正确，而不是只看任务是否完成。
- No-op/Clarification：单独观察该停时是否能完成，避免只等到 `loopDetection` 才暴露。

## 运行建议

v4 全量预计接近 v3 的 2.25 倍耗时。建议按 12 case 一组分片跑：

```bash
MEMEX_EVAL_CASE_OFFSET=0 MEMEX_EVAL_CASE_LIMIT=12
MEMEX_EVAL_CASE_OFFSET=12 MEMEX_EVAL_CASE_LIMIT=12
MEMEX_EVAL_CASE_OFFSET=24 MEMEX_EVAL_CASE_LIMIT=12
```

真实 LLM replay 基础命令骨架：

```bash
MEMEX_EVAL_ENABLE_LLM=1 \
MEMEX_EVAL_DATASET=evals/datasets/full_chain_journey_real_replay_v4/cases.jsonl \
MEMEX_EVAL_RUN_DIR=evals/runs/<run-id-shard> \
MEMEX_EVAL_STATUS_INTERVAL_SECONDS=30 \
MEMEX_EVAL_TASK_UNIT_TIMEOUT_SECONDS=90 \
MEMEX_EVAL_TASK_TIMEOUT_MAX_SECONDS=900 \
MEMEX_EVAL_TEST_TIMEOUT_MINUTES=720 \
no_proxy=localhost,127.0.0.1,::1 \
NO_PROXY=localhost,127.0.0.1,::1 \
env -u ws_proxy -u wss_proxy \
flutter test --no-pub --concurrency=1 \
  evals/replay/serial_full_chain_replay_test.dart
```

评分命令：

```bash
dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/full_chain_journey_real_replay_v4 \
  --adapter replay_file \
  --replay-observations evals/runs/<merged-or-shard>/observations.jsonl \
  --out evals/runs/<score-run-id>
```

## 准备验证

- `dart evals/bin/generate_journey_scale_iteration_datasets.dart full_chain_journey_scale_v3`
- `dart evals/bin/generate_real_replay_journey_datasets.dart`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/full_chain_journey_scale_v3 --out evals/runs/2026-05-19-v4-scale-fixture-smoke-2`

Fixture smoke 结果：1416/1416，通过率 100.0%。
