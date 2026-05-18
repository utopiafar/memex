# Memex Agent Eval 体系复盘与新一轮实验计划

## 结论

- 本轮已在 `codex/agent-evals-harness` 上合入最新 `upstream/main`，并提前合入 PR 105（Knowledge Insight fresh-run / 残留 state 清理）。
- 已复查 `evals/experiments/` 下 28 个实验目录、`evals/README.md`、`evals/METRICS.md` 和 `evals/HARNESS_ENGINEERING.md`。结论不变：历史实验的最大问题不是缺 benchmark，而是 fixture 证据太多、真实 App replay 太少。
- 新一轮已补一个小规模真实链路实验：`evals/datasets/full_chain_realistic_smoke`。完整数据集含 2 个 persona、13 条 record、24 个 App 操作；本轮先按 `case-limit=1` 跑通首个 persona。
- 新增指标覆盖用户要求的 App 行为仿真：`record_operation_coverage`、`journey_time_span_coverage`、`app_operation_sequence_completeness`、`input_channel_diversity`、`feature_trigger_coverage`。
- 真实 replay 首个 persona 通过：24/24 断言，真实链路耗时 7分47秒，58 次 LLM 调用，177 次工具调用，59825 tokens，数据审计 overall=0.900。
- 本轮暴露并修复一个 harness 问题：Super Agent replay 观察最初没有把 memory snippets 传给 LLM judge，导致回答虽正确但 groundedness 被判 0.5；已把 memory entries 作为 `source_snippets` 写入 Super Agent observation。

## 历史实验问题

| 问题 | 证据 | 影响 |
| --- | --- | --- |
| fixture 结果容易被误读成真实 Agent 能力 | 多个 `2026-05-12-module-*` 和 retrieval fixture 100% 通过，但观察来自 `fixture_observed` | 只能证明 grader/报告可跑，不能证明 App 链路可靠 |
| 真实 full-chain 证据不足 | 旧 `2026-05-11-full-chain-medium-llm` 只有 50.0% 通过，主要是 task 不收敛、loopDetection、card null、成本超预算 | 真问题集中在任务生命周期和真实 agent 调用，而不是 fixture 断言 |
| 数据扩量后自然度下降 | `production_like_retrieval_v3` 审计 overall=0.900，但 input naturalness 从 v2 的 0.900 降到 0.850 | 继续只加行业名会稀释真实信号，需要原始文档、语音、OCR、碎片化记录 |
| Retrieval-only 扩量边际收益下降 | v3 已到 24 用户、150 输入、94 retrieval QA task | 下一轮应转向 Memory、PKM、Schedule、Super Agent 和真实 replay |
| Hard-case 保留失败但不够真实 | `hard_case_challenge` / LLM judge 约 85.5%，数据审计 0.780；diversity audit 更低 | 适合错误分析，不适合当强 benchmark |
| Memory lifecycle 结构完整但模板化 | `memory_lifecycle` LLM judge 100%，audit 0.900，但提示 case 间句式/逻辑重复 | 可做小回归，仍需要生产贴近数据和真实 replay 校准 |
| 旧 full-chain journey 仍偏 fixture | `full_chain_journey_medium` audit 0.700 | 时间跨度方向正确，但 persona 和输入结构同质，且不等同真实 App 行为 |
| 指标以前缺少 App 行为维度 | 成本/trace 指标已有 token、latency、task status，但没有操作类型、渠道、时间跨度、功能触发覆盖 | 无法证明“像用户在 App 里真实操作” |

## 本轮新增实验

### 数据设计

- 数据集：`evals/datasets/full_chain_realistic_smoke`
- 生成器：`evals/bin/generate_realistic_full_chain_smoke_dataset.dart`
- 完整规模：2 persona、13 record、24 App operations、6 eval tasks。
- 本轮实际运行：`MEMEX_EVAL_CASE_LIMIT=1`，先跑 `realistic_chain_product_release`。
- 输入形态：`text`、`voice_transcript`、`ocr_clip`。
- App 行为：record、timeline browse、post comment、schedule aggregation refresh、knowledge insight refresh、wait memory、Super Agent quick query。
- 时间跨度：首个 persona 覆盖 2026-04-28 到 2026-05-11，约 13 天。

### 指标新增

| 指标 | 衡量点 |
| --- | --- |
| `record_operation_coverage` | 实际提交记录数是否达到样本要求 |
| `journey_time_span_coverage` | 是否跨越足够多天，避免单日短上下文 |
| `app_operation_sequence_completeness` | 是否执行预期 App 操作类型 |
| `input_channel_diversity` | 是否覆盖文本、语音转写、OCR/剪贴等来源形态 |
| `feature_trigger_coverage` | trace/operation 是否覆盖 card、memory、PKM、schedule、insight、comment、Super Agent 等触发点 |

### 运行结果

- 正式报告：`evals/experiments/2026-05-16-realistic-full-chain-smoke/report.md`
- metrics：`evals/experiments/2026-05-16-realistic-full-chain-smoke/metrics.json`
- 本地详细日志：`evals/runs/2026-05-16-realistic-full-chain-smoke/debug_log.json`
- 本地 replay 现场：`evals/runs/2026-05-16-realistic-full-chain-smoke-replay/summary.json` 和 `observations.jsonl`
- 结果：24/24 断言通过，证据等级 `real_replay`。
- 成本：58 次 LLM 调用、177 次工具调用、59825 tokens、P95 延迟 53 秒。
- 任务收敛：60 个 task 全部 completed，retry/failed 均为 0。

### 运行注意

本地环境的 `ws_proxy/wss_proxy/http_proxy/https_proxy` 会破坏 `flutter_tester` 的 WebSocket 握手，错误为 `Invalid WebSocket upgrade request`。真实 replay 使用以下模式跑通：

```bash
env -u ws_proxy -u wss_proxy -u http_proxy -u https_proxy \
  MEMEX_EVAL_ENABLE_LLM=1 \
  EVAL_LLM_PROVIDER=anthropic \
  EVAL_LLM_BASE_URL=<provider-url> \
  EVAL_LLM_API_KEY=<redacted> \
  EVAL_LLM_MODEL=mimo-v2-pro \
  MEMEX_EVAL_DATASET=evals/datasets/full_chain_realistic_smoke/cases.jsonl \
  MEMEX_EVAL_CASE_LIMIT=1 \
  MEMEX_EVAL_RUN_DIR=evals/runs/2026-05-16-realistic-full-chain-smoke-replay \
  MEMEX_EVAL_TASK_TIMEOUT_SECONDS=240 \
  flutter test --no-pub evals/replay/serial_full_chain_replay_test.dart -r expanded --concurrency=1
```

## 下一轮计划

1. 先跑完整 `full_chain_realistic_smoke` 的 2 个 case，确认家庭照护 persona 的 memory conflict、schedule、insight 和 Super Agent 闭环。
2. 扩到 6-12 persona，每人 20-40 条 record，保留串行 App 行为，不做多用户并发压测。
3. 给每个功能点继续补规则指标：card status per operation、memory source grounding、schedule action accuracy in replay、insight fresh-run state cleanup、comment response grounding、per-operation p95 latency。
4. 把 PR 105 的 Knowledge Insight fresh-run 专门变成 replay 断言：刷新后 state 清理、下一次 refresh 不复用旧 conversation、summary card 存在、任务无 retry。
5. 每轮都保留 `evals/runs/<run-id>/debug_log.json`、`trace.ndjson`、`outputs.jsonl`，报告只提交 `report.md` / `metrics.json`，不提交 key 或原始模型密钥。
