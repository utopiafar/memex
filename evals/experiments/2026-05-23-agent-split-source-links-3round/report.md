# Agent split source links 三轮实验报告

## 结论

这轮比 5 月 22 日的双链路结果明显收敛：最小 `source_fact_ids` 引用字段已生效，旁路观测足够稳定，`split_primary` 在 smoke 范围内已经能平稳切换。

但我仍不建议现在默认切全量。理由不是 record path，而是默认切换前还要用更大的 replay 覆盖面确认两个点：memory 最新值冲突处理、以及下游 `knowledge_insight_task` 的 recoverable loop 噪声。

本轮目标可以先定为：`split_shadow` 继续作为 debug 旁路常开观测；`split_primary` 可以进入 debug/dogfood 切换验证；默认链路仍保留 `legacy_pkm`，等 v2/v3/v4 或更大真实 replay 不低于 legacy 后再切。

## 本次实现

- 给 memory atom 增加最小引用字段：`source_fact_ids`。
- `append_memories` 工具保持兼容：既支持旧的 string list，也支持 `{content, source_fact_ids}` atom。
- Memory prompt 展示来源：recent buffer 会显示 `(sources: fact_id...)`。
- MemoryAgent 与 ClarificationResolutionAgent 写 memory 时会从输入 fact/evidence 复制 `source_fact_ids`，不让模型凭空编 ID。
- split shadow artifact 增加切换观测字段：
  - `memory_atom_source_fact_ids_expected`
  - `legacy_card_insight`
  - `related_facts`
  - `draft`
  - `comparison`
- split artifact comparison 记录：
  - legacy/split insight 是否存在
  - legacy/split related 数量
  - retrieval candidate 数量
  - related overlap
  - fallback 是否触发
- replay harness 会把 `split_agent_shadow_artifacts` 和 memory `source_fact_ids` 写入 observations/case summary，并纳入观测指标。
- 修了一个 shadow 可比性问题：shadow split 现在等待 legacy PKM 后再写 artifact，且 split draft 会先去掉 legacy card insight，避免被旧链路污染。

## 实验设置

- Dataset: `evals/datasets/full_chain_realistic_smoke/cases.jsonl`
- Cases: 2
- Inputs: 13
- Eval tasks: 6
- Round 1: `split_shadow`
- Round 2: `split_shadow`
- Round 3: `split_primary`
- Embedding: OpenRouter-compatible `perplexity/pplx-embed-v1-4b`
- Embedding store: in-memory
- Eval LLM: Anthropic-compatible endpoint, key 仅通过环境变量传入，没有写入代码或报告。

原始产物：

- Round 1 replay: `evals/runs/agent-split-source-links-r1-shadow`
- Round 1 score: `evals/runs/agent-split-source-links-r1-shadow-score`
- Round 2 replay: `evals/runs/agent-split-source-links-r2-shadow`
- Round 2 score: `evals/runs/agent-split-source-links-r2-shadow-score`
- Round 3 replay: `evals/runs/agent-split-source-links-r3-primary`
- Round 3 score: `evals/runs/agent-split-source-links-r3-primary-score`

## 三轮结果

| 指标 | R1 shadow | R2 shadow | R3 primary |
| --- | ---: | ---: | ---: |
| 断言通过率 | 43/48 = 89.6% | 42/48 = 87.5% | 44/48 = 91.7% |
| replay 总耗时 | 26m30s | 26m58s | 19m22s |
| record 平均耗时 | 89.1s | 97.0s | 47.6s |
| record 最大耗时 | 142.0s | 211.9s | 63.3s |
| total tokens | 119318 | 120616 | 49947 |
| LLM calls | 122 | 148 | 91 |
| tool calls | 387 | 444 | 288 |
| 操作收敛率 | 100% | 100% | 100% |
| active/failed/retrying | 0/0/0 | 0/0/0 | 0/0/0 |
| loopDetection/maxTurns | 0/0 | 0/0 | 1/1 |
| memory entries | 5 | 4 | 5 |
| memory source linked | 5/5 | 4/4 | 5/5 |
| split artifacts | 12 | 12 | 12 |
| legacy insight present | 12/12 | 12/12 | 0/12 |
| split insight present | 12/12 | 12/12 | 12/12 |
| split fallback | 0 | 0 | 0 |
| PKM agent calls | 45 | 51 | 0 |
| PKM agent tokens | 60530 | 68648 | 0 |

`split_primary` 里 `legacy insight present = 0/12` 是预期结果：主写入已经切到拆分链路，旧 PKM 不再负责写 card insight。

## 旁路观测是否够用

这次新增的观测字段够支撑切换判断：

- shadow 两轮共 24 个 artifact，legacy insight 和 split insight 都是 24/24，说明旁路不会漏产物。
- shadow 两轮 fallback 是 0，说明拆分链路不是靠兜底文本跑过。
- 三轮 memory entries 共 14 条，`source_fact_ids` 覆盖 14/14。
- primary 轮 12 个 artifact 全部有 split insight，fallback 0。
- primary 轮 13 条 record 全部 materialize 为 completed card。

这说明“平稳切换旁路”的核心观测已经具备：能看见旧写入、能看见新写入、能看见检索候选、能看见 fallback、能看见 memory 是否带源。

## 和上一版对比

上一版实验结论是：方向对，但 `split_primary` 全链路从 87.5% 掉到 81.3%，主要被下游 Knowledge Insight 的 retrying/loopDetection 拖垮。

本轮 R3 primary 对比上一版 legacy：

| 指标 | 旧 legacy | 本轮 R3 primary | 变化 |
| --- | ---: | ---: | ---: |
| 断言通过率 | 42/48 = 87.5% | 44/48 = 91.7% | +4.17pp |
| replay 总耗时 | 22m25s | 19m22s | -13.6% |
| record 平均耗时 | 71.8s | 47.6s | -33.7% |
| total tokens | 148001 | 49947 | -66.3% |
| PKM agent calls | 47 | 0 | -47 |
| PKM agent tokens | 88730 | 0 | -88730 |

本轮 R3 primary 对比上一版 split primary：

| 指标 | 上一版 split primary | 本轮 R3 primary | 变化 |
| --- | ---: | ---: | ---: |
| 断言通过率 | 39/48 = 81.3% | 44/48 = 91.7% | +10.42pp |
| replay 总耗时 | 31m01s | 19m22s | -37.5% |
| 操作收敛率 | 94.4% | 100% | +5.56pp |
| active/retrying | 1/1 | 0/0 | 修复 |

## 失败项

R3 primary 仍有 4 个断言失败：

- `realistic_chain_product_release_super_agent` / `llm_grounded_answer_score`: judge 给 0.5。
- `realistic_chain_family_care_super_agent` / `llm_grounded_answer_score`: judge 给 0.0。
- `realistic_chain_family_care_memory` / `memory_must_write_recall`: 漏了最新用药时间 `medicine_time_latest`。
- `realistic_chain_family_care_memory` / `memory_conflict_handling`: 新旧冲突没有按期望把旧 inactive / 新 active 状态处理好。

判断：这几个问题不是 `source_fact_ids` 字段缺失导致的。`source_fact_ids` 解决的是可追踪性和后续引用展开，不自动解决“该写哪条 memory / 冲突如何覆盖”的语义策略。所以这轮最小字段是必要的，但不是 memory 召回与冲突处理的全部答案。

## 风险与建议

`split_primary` 已经可以作为 debug/dogfood 开关继续跑。它在本 smoke 数据上完成 24/24 操作，最终 active/failed/retrying 都为 0，record 成本与 PKM 调用也大幅下降。

我暂时不建议默认切全量，原因有两个：

- R3 有 1 次 recoverable `knowledge_insight_task` loopDetection/maxTurns。它最后恢复并完成了，不再像上一版那样阻断全链路，但默认切换前最好把 Insight refresh 的重试噪声单独隔离或降低。
- family care 的 memory 最新值/冲突覆盖仍未 100%。这不是旁路切换问题，但会影响用户问答体验。

下一轮建议把目标定成：

1. 保持 `split_shadow` 在 debug 环境常开，继续收集 artifact parity。
2. 用 `split_primary` 跑更大的 v2/v3/v4 real replay，不只看 smoke。
3. 单独修 family care 这类 latest memory conflict 策略。
4. 把 `source_fact_ids` 从 recent buffer 扩展到 archived memory 的结构化保留，避免 consolidation 后引用只剩 Markdown 文本。
5. 对 `knowledge_insight_task` 做 loop/retry 预算隔离，避免它再次影响 record/memory 切换判断。

## 验证

- Targeted tests: 18 passed。
- `flutter analyze --no-pub`: 无 error/warning；仍有既有 info lint。
- Non-LLM replay smoke: passed。
- Round 1 `split_shadow` replay + score: passed, 43/48。
- Round 2 `split_shadow` replay + score: passed, 42/48。
- Round 3 `split_primary` replay + score: passed, 44/48。
