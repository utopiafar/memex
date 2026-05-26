# Agent split 双链路全链路对比报告

## 结论

这条拆分路线是合理的，适合先作为旁路和 debug-only primary 继续推进，但现在还不适合默认切到新主链路。

原因是两面的信号很清楚：

- 正向信号：`split_primary` 把 record 阶段平均耗时从 71.8s 降到 55.5s，下降约 22.7%；总 token 从 148001 降到 66090，下降约 55.3%；旧链路里 `pkm_agent` 的 47 次 LLM 调用和 88730 tokens 在新链路中被完全移除。13 条输入都成功 materialize 成 completed card。
- 风险信号：全链路评分从 87.5% 降到 81.3%。主要不是卡片生成失败，而是第二个 family care case 在 `care_insight_001` 触发 `knowledge_insight_task` retrying/loopDetection 后 15 分钟超时，导致后续 `wait_memory` 和 `ask_super_agent` 没有跑完。
- 记忆信号：`memory_write` 从 5/8 提升到 6/8，说明拆分链路的专门 memory 写入方向是对的；但 care case 仍漏了最新用药时间相关记忆，默认切主链路前需要把“最新事实写入/覆盖/可问答召回”的一致性补齐。

因此建议保留 `legacy_pkm` 为默认，产品 debug 里提供 `split_shadow` 和 `split_primary` 开关。先用 shadow 采旁路产物，再用 primary 做小流量/手动验证；等 Knowledge Insight 超时隔离、memory 最新值召回和评估归档稳定后，再考虑默认切换。

## 本次实现范围

- 增加 `AgentPipelineMode`：`legacy_pkm`、`split_shadow`、`split_primary`。
- 增加 debug 配置页：`Settings > Debug > Agent Pipeline`，可切换链路模式，并配置 embedding enabled、base URL、model、API key、timeout。
- 增加环境变量覆盖：`MEMEX_AGENT_PIPELINE_MODE`、`MEMEX_EMBEDDING_ENABLED`、`MEMEX_EMBEDDING_BASE_URL`、`MEMEX_EMBEDDING_API_KEY`、`MEMEX_EMBEDDING_MODEL`。
- 增加 OpenAI-compatible embedding 服务，第一期 embedding 只存进程内内存 cache。
- 增加 hybrid retrieval：FTS/card 搜索 + recent facts + lexical score + optional embedding cosine score。
- 增加 `CardInsightAgent` 和 `split_agent_pipeline_task`：
  - `split_shadow`：保留旧 PKM 主链路，同时写旁路 shadow artifact。
  - `split_primary`：跳过旧 PKM 处理，由拆分链路写 card insight 并触发 memory sync。
- 从 `utopiafar/memex` 的 `codex/agent-evals-harness` 分支恢复 `evals/`，并跑双链路 replay + score。

## 实验设置

- Dataset: `evals/datasets/full_chain_realistic_smoke/cases.jsonl`
- Cases: 2
- Inputs: 13
- Tasks: 6
- Replay: serial full-chain replay, LLM enabled, max concurrency 1
- Legacy run: `evals/runs/agent-split-legacy-full-chain`
- Legacy score: `evals/runs/agent-split-legacy-score`
- Split run: `evals/runs/agent-split-primary-full-chain`
- Split score: `evals/runs/agent-split-primary-score`
- Split embedding: OpenRouter compatible embeddings, model `perplexity/pplx-embed-v1-4b`

评估 key 和 embedding key 均只通过环境变量传入，没有写入代码、报告或 run 配置。

## 指标对比

| 指标 | legacy_pkm | split_primary | 变化 |
| --- | ---: | ---: | ---: |
| 总通过率 | 42/48 = 87.5% | 39/48 = 81.3% | -6.25pp |
| cost_trace | 28/28 = 100.0% | 24/28 = 85.7% | -14.3pp |
| memory_write | 5/8 = 62.5% | 6/8 = 75.0% | +12.5pp |
| super_agent_qa | 9/12 = 75.0% | 9/12 = 75.0% | 持平 |
| record 平均耗时 | 71.8s | 55.5s | -22.7% |
| record 最大耗时 | 105.5s | 63.7s | -41.8s |
| product case 总耗时 | 10m15s | 8m30s | -17.1% |
| replay 总耗时 | 22m25s | 31m01s | +8m36s |
| total tokens | 148001 | 66090 | -55.3% |
| tool calls | 378 | 291 | -23.0% |
| LLM calls | 122 | 112 | -10 |
| PKM agent 调用 | 47 | 0 | -47 |
| PKM agent tokens | 88730 | 0 | -88730 |
| completed cards | 13/13 | 13/13 | 持平 |
| memory entries | 4 | 6 | +2 |
| active/retrying tasks | 0/0 | 1/1 | split 有未收敛 |
| loopDetection tasks | 0 | 1 | split 有风险 |

## 失败归因

1. `split_primary` 的 record path 本身表现是正向的。13 条输入全部有 completed card，record 平均耗时和 token 成本都明显下降，这说明“把 PARA/PKM 整理从主干剥离，让 card/memory 等专门 agent 处理”的方向成立。

2. `split_primary` 的全链路失败主要集中在 downstream `knowledge_insight_task`。第二个 family care case 在 `care_insight_001` 之后停在 retrying，最后一次操作耗时 900471ms，summary 里有 1 个 active/retrying `knowledge_insight_task` 和 1 个 loopDetection。这会拖累 operation settlement、cost_trace、feature coverage，并阻断后续问答。

3. 这次 `knowledge_insight_task` 不是新拆分链路专属模块，但 split primary 改变了上游写入节奏和可见上下文，可能让 Insight agent 更容易进入长循环。下一步评估需要把 record/memory path 与 insight refresh path 拆开计分，避免 downstream 非目标模块把主结论冲掉，同时也要修 Insight agent 的 loopDetection。

4. memory 方向有改善但还不够。`split_primary` 的 `memory_must_write_recall` 是 3/4，高于旧链路 2/4；但 family care 的最新用药时间/冲突覆盖仍未稳定。默认切主链路前，需要保证 latest fact 覆盖后可被 Super Agent 问答读到。

5. `llm_grounded_answer_score` 本次不作为有效结论。两个 run 的 LLM judge 都使用 `openai_chat` provider 指向 Anthropic-compatible 评估 endpoint，触发 HTTP 404，因此这个 0/2 是 judge 配置问题，不是产品链路本身的语义失败。主结论以 replay 规则指标、artifact health、task health 和 cost trace 为准。

## 演进路径

1. 短期保留 `legacy_pkm` 默认，只在 debug 里开放 `split_shadow` 和 `split_primary`。
2. 先用 `split_shadow` 跑真实样本，采集 split artifact、retrieval candidates、memory draft，不改变线上主写入。
3. 给 eval harness 增加 shadow artifact 归档和 workspace memory/card snapshot，这样可以离线比较“同一输入下两条链路写了什么”，而不只看最终问答。
4. 修两个稳定性点：一是 `knowledge_insight_task` loopDetection/timeout；二是拆分链路写入 memory 后，最新值必须在问答前稳定可召回。
5. 扩大到 v2/v3/v4 real replay 数据集，单独看 record path、memory path、Super Agent QA、Insight refresh 四类指标。
6. 当 split shadow 连续稳定，并且 split primary 在全链路通过率不低于旧链路、record 成本持续下降时，再把默认链路从 `legacy_pkm` 切过去。

## 验证

- Targeted tests: 16 passed。
- `flutter analyze --no-pub`: 无 error/warning；仍有 324 个既有 info 级 lint。
- Non-LLM replay smoke: passed。
- LLM full-chain replay:
  - `legacy_pkm`: 2/2 cases completed, 24/24 operations, all tasks settled。
  - `split_primary`: 2/2 cases started, 21/22 successful operations, family care case 在 `care_insight_001` 后因为 `knowledge_insight_task` retrying 超时而提前结束。
- Replay-file scoring:
  - `legacy_pkm`: 42/48, 87.5%。
  - `split_primary`: 39/48, 81.3%。
