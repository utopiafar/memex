# Agent Split DeepSeek v6 三轮复评报告

日期：2026-05-23

## 结论

本轮结论：`split_primary` 在 v6 更大 replay 上稳定优于 `legacy_pkm`，可以继续作为可切换的主链路候选推进；仍建议先走 dogfood/debug 开关，不建议立刻默认切全量用户。

核心证据：

- 三轮同批隔离对比共覆盖 9 个 case、180 条 record、54 个 eval task。
- Primary 总分 592/593，99.83%；Legacy 总分 571/593，96.29%。
- Primary token 400.4 万，Legacy 1069.2 万，降低 62.55%。
- Primary LLM 调用 686 次，Legacy 1302 次，降低 47.31%。
- Primary 工具调用 4410 次，Legacy 5928 次，降低 25.61%。
- Primary replay 实测 85.9 分钟，Legacy 111.4 分钟，降低 22.86%。
- 两条链路三轮均无 failed task、loopDetection、Maximum turns reached。

## 方法

本轮按用户确认的实验方法执行：Legacy 和 Primary 隔离运行，同一批输入先后跑两条链路，最后对比指标；Shadow 不参与评分。

使用配置：

- Dataset: `evals/datasets/full_chain_journey_real_replay_v6`
- App LLM: DeepSeek chat completion, `deepseek-v4-flash`
- Embedding: OpenRouter, `perplexity/pplx-embed-v1-4b`
- R1: offset 0, limit 2
- R2: offset 12, limit 3
- R3: offset 24, limit 4

本轮坚持的实现原则是：让模型拿到更准确、更完整的候选信息，而不是让规则接管模型判断。代码层面的改进集中在候选证据、来源展开、轻量 hint、以及评估指标可信度。

## 已完成迭代

1. Memory atom 增加最小结构化 hint：`kind`、`entities`、`scope`、`confidence`、有效期字段；这些只作为检索和 prompt 线索，不作为硬覆盖规则。
2. Memory archive 保留 structured atom：新增 `archived_atoms`，避免 consolidation 后丢失 source/kind/entity 元数据。
3. Memory prompt 展开 source fact snippets：让模型能看到来源证据，而不是只读抽象总结。
4. Related facts hybrid retrieval 增加 entity hint score：lexical + vector + entity + recency + FTS bonus，目标是提高候选质量。
5. Replay/benchmark 增加观测指标：memory source-linked、kinded、entity-linked，answer bit group recall，entity score。
6. Benchmark 从硬字符串升级为更可信的 rubric：允许边界类等价表述、兼容轻量 kind、避免把用户规则里的“不确定/证据不足”误判为模型拒答。

## 结果总表

| Round | Mode | Score | Pass | Tokens | LLM Calls | Tool Calls | Replay | Failed/Loop/MaxTurns |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | Legacy | 134/140 | 95.71% | 2,464,310 | 300 | 1,374 | 28.9m | 0/0/0 |
| R1 | Primary | 140/140 | 100.00% | 862,415 | 151 | 858 | 19.2m | 0/0/0 |
| R2 | Legacy | 184/190 | 96.84% | 3,424,587 | 422 | 1,926 | 35.8m | 0/0/0 |
| R2 | Primary | 190/190 | 100.00% | 1,396,415 | 232 | 1,554 | 28.6m | 0/0/0 |
| R3 | Legacy | 253/263 | 96.20% | 4,803,085 | 580 | 2,628 | 46.7m | 0/0/0 |
| R3 | Primary | 262/263 | 99.62% | 1,744,814 | 303 | 1,998 | 38.1m | 0/0/0 |

## Bit Loss

Primary 最终只剩 1 个真实失败：`journey_real_replay_v6_02_c_card_project` 的 card content 未包含 `Jason`。原始输入是“等 Jason 反馈”，Primary 生成的 card 只保留了“收集权限边界/重试率”，没有保留等待 Jason；同一轮 Legacy 的 card subtask 保留了 Jason。

这个是 card agent 的抽取漏项，不是 memory 或 SuperAgent 的 bit loss：同 case 的 SuperAgent 回答已经包含 Jason，memory/source 指标也通过。建议后续单独增强 card agent 对“等 X 反馈 / 找 X 对齐 / X 复核”这类协作人字段的保留。

Legacy 的主要失败集中在成本和答案边界：

- `total_token_budget`: 1/9
- `cost_per_input`: 1/9
- `answer_must_include`: 16/18
- `answer_bit_recall_boundary`: 7/8
- `unnecessary_uncertainty_absence`: 7/9

Primary 的失败指标只剩：

- `title_constraint_accuracy`: 17/18

## 产品判断

这轮结果支持继续推进 Primary，但不支持直接全量默认切：

- 支持推进的原因：质量更高、成本显著更低、三轮没有任务失败或 loop，memory source/kind/entity 观测完整。
- 不建议直接默认切的原因：样本仍是 replay/fake journey，不是真实用户长期运行；仍存在 1 个真实 card 抽取漏项；下游 knowledge insight 虽未失败但仍有 60-90 秒长尾；产品默认切需要更多 persona、更多重复 run 和真实 dogfood 观察。

建议产品形态保持：

- Debug/Dogfood 开关提供 `legacy_pkm` 与 `split_primary` 二选一。
- 默认仍保守，但可以给内部用户默认 Primary，外部用户先显式 opt-in。
- 切换时记录 mode、token、LLM calls、tool calls、failed/loop/max-turn、memory source-linked、answer bit recall、card collaborator recall。

## 后续建议

1. 修 card agent 协作人保留：把“等 X 反馈/找 X 对齐/找 X 复核”进入 task subtask 或参与人字段，避免 card 层 bit loss。
2. 给 knowledge insight 做 recoverable loop/slow-tail 观测：本轮无失败，但仍是尾部最长任务。
3. 对 Primary 做重复运行稳定性：同 offset 再跑 2-3 次，量化 stochastic variance。
4. 扩大到 v6 全 60 cases 分批跑，按 persona/window/任务类型分层看 long-tail。
5. 保留当前“模型决策优先”的架构，不引入复杂 key 覆盖；最多继续增强候选 evidence、source snippet、entity hint 与观测指标。

## 验证

- R1/R2/R3 Legacy 与 Primary full-chain replay 均通过。
- 最终评分目录：
  - `evals/runs/agent-split-deepseek-r1-legacy-score-final`
  - `evals/runs/agent-split-deepseek-r1-primary-score-final`
  - `evals/runs/agent-split-deepseek-r2-legacy-score-final`
  - `evals/runs/agent-split-deepseek-r2-primary-score-final`
  - `evals/runs/agent-split-deepseek-r3-legacy-score-final`
  - `evals/runs/agent-split-deepseek-r3-primary-score-final`
