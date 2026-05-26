# Memex Agent Eval 体系复盘

## 结论

- 这组实验的核心价值不是“某个模型跑到 100%”，而是把 Agent 能力拆成可复核的证据链：数据、观察来源、规则指标、LLM judge、trace、成本和失败模式。
- 当前最可信的结果是 `real_replay` 暴露的问题：5/11 full-chain replay 只有 50.0% 断言通过，主要失败来自任务不收敛、loopDetection、card 为空和成本超预算。
- 当前最适合保留为小规模回归基线的是 `2026-05-13-memory-lifecycle-llm-judge`：12 个 persona、1200 条输入、60 个任务，规则与 LLM judge 断言 312/312 通过，数据审计 0.900，但仍需要用真实 replay 抽样校准。
- 本轮针对“生成数据文风单调”的问题新增了 `2026-05-13-production-like-retrieval-llm-judge`：5 个异质职业 case、23 条输入、16 个任务，规则与 LLM judge 断言 155/155 通过，数据审计 0.950。它适合展示如何把检索问答数据做得更像真实工作流，但规模仍小，不能替代真实 replay。
- 继续扩展后的 `2026-05-13-production-like-retrieval-v2-llm-judge` 覆盖 12 个用户、78 条输入、47 个任务，规则与 LLM judge 断言 440/440 通过，数据审计 0.900。它比 v1 更适合展示规模化的生产贴近数据构造，但仍是 retrieval-only fixture。
- 最新扩展的 `2026-05-13-production-like-retrieval-v3-llm-judge` 覆盖 24 个用户、150 条输入、94 个任务，规则与 LLM judge 断言 873/873 通过，数据审计 0.900。它把报告指标做得更丰富，但 input naturalness 降到 0.850，说明继续扩量时要引入更真实的原始文档和 replay，而不是只增加行业。
- 多个 100% fixture 实验不能直接当作 Agent 能力证明。旧 `retrieval_source_grounding` 数据虽然已加入口语、碎碎念、冗余背景和领域词，但最新审计仍只有 0.650，说明大规模生成集不是改几句 prompt 就能完全解决，还要重构 case 结构和 task 族。
- `2026-05-13-hard-case-challenge-llm-judge` 保留了种子失败，112 个 case 的断言通过率为 85.5%，数据审计 0.780；本轮修正 PKM source id 后的多样性复审只有 0.550，说明 hard-case 更适合讲失败模式、指标敏感度和下一轮数据重构，不适合作为强 benchmark。
- 本轮已把 eval 体系的默认叙事从“通过率优先”改成“证据等级优先”：报告会声明 fixture smoke、audited synthetic fixture 或 real replay。

## 本轮修复

| 问题 | 修复 |
| --- | --- |
| fixture 100% 容易被误读成真实 Agent 能力 | runner 增加 `evidence_level`，报告结论按证据等级解释通过率。 |
| LLM judge 开关存在但数据集没有触发 | `--use-llm-judge` 现在默认审查 `retrieval_qa` / `super_agent_qa`，单个 task 可用 `expected.llm_judge=false` 关闭。 |
| citation 缺失不会稳定失败 | 只要存在 `expected_sources`，就生成 `answer_source_citation` 断言；没有 `cited_sources` 会失败。 |
| judge prompt 只看答案和 snippets，不知道引用情况 | judge payload 增加 `retrieved_sources` / `cited_sources`，prompt 要求引用覆盖关键来源。 |
| 数据审计抽样只取 JSONL 前 N 条 | 审计 payload 改为 `family_round_robin`，多 family 数据集会分层抽样。 |
| 合成数据文风和结构过于单调 | 数据审计 prompt 明确要求检查碎碎念、语音口吻、心情、冗余背景、弱相关信息和职业领域差异；新增 `production_like_retrieval` 作为更自然的小样本对照。 |
| 实验过程里的隐性问题容易丢失 | 新增 `HARNESS_ENGINEERING.md`，记录每轮实验的校验过程、audit 问题、修复原则和后续避坑。 |
| LLM audit 容易在自然语言总结中过度概括 | `dataset_quality.md` 增加约束：除非所有样本或 summary 支持，否则不能写“每个 case 均...”这类绝对覆盖表述。 |
| 扩量时派生修复容易造成 expected/observed 不同步 | v3 fixture smoke 先捕获招聘 seed case 的 filter mismatch，再同步 `expected_filters` 与 `fixture_observed.applied_filters` 后跑正式 judge。 |
| hard-case Super Agent expected 没有隐藏真相来源 | 补齐 `ground_truth_world.memories` 和 `source_snippets`，让 expected、retrieved source 和裁判输入闭环。 |
| hard-case PKM expected source id 不一致 | 修正 PKM 任务的期望 source id，避免 grader 因数据闭环错误而误判。 |
| schema 落后于新数据形态 | `case.schema.json` 支持 `operations`、`schedule_refresh`、`pkm_organization`、`super_agent_qa`。 |
| 旧 full-chain replay 不使用输入时间 | `full_chain_replay_test.dart` 现在把 `input.time` 传入 `submitInput(createdAt:)`。 |

## 历史实验怎么读

| 实验 | 观察来源 | 通过率 | 数据审计 | 可靠读法 |
| --- | --- | ---: | ---: | --- |
| `2026-05-11-fixture-v1-medium` | fixture | 99.2% | - | 大规模 grader smoke。失败集中在临时状态被写成长记忆。 |
| `2026-05-11-full-chain-medium-llm` | replay_file | 50.0% | - | 最有诊断价值的真实失败：task 未收敛、loopDetection、card null、成本超预算。 |
| `2026-05-12-module-*` | fixture | 100.0% | - | 模块 grader smoke，证明指标口径和报告可跑。 |
| `2026-05-13-hard-case-challenge` | fixture | 86.1% | 0.600 | 专门保留失败，适合讲 error analysis，不适合作为强 benchmark。 |
| `2026-05-13-memory-lifecycle` | fixture | 100.0% | 0.900 | 当前最好的合成小基线，覆盖长期/临时/冲突/时效/敏感边界。 |
| `2026-05-13-retrieval-source-grounding` | fixture | 100.0% | 0.650 | 检索指标设计完整，但数据模板化严重，只能作为口径 smoke。 |
| `2026-05-13-full-chain-journey-medium` | fixture | 100.0% | 0.700 | 多周 journey 方向正确，但 persona 和输入结构同质化，需要重做多样性。 |
| `2026-05-13-retrieval-source-grounding-llm-sample` | fixture + LLM judge | 100.0% | 0.600 | 24 个 LLM judge 断言全过，但审计说明数据多样性不足。 |
| `2026-05-13-memory-lifecycle-llm-judge` | fixture + LLM judge | 100.0% | 0.900 | 当前最可展示的小规模合成回归基线。 |
| `2026-05-13-hard-case-challenge-llm-judge` | fixture + LLM judge | 85.5% | 0.780 | 失败保留型 challenge set，适合讲 error analysis 和下一步数据改造。 |
| `2026-05-13-production-like-retrieval-llm-judge` | fixture + LLM judge | 100.0% | 0.950 | 当前最适合展示“数据更像生产输入”的检索小基线；小而精，仍需扩到真实 replay。 |
| `2026-05-13-production-like-retrieval-v2-llm-judge` | fixture + LLM judge | 100.0% | 0.900 | v1 的扩展迭代：12 用户、78 输入、47 任务，适合讲 harness engineering 和规模化数据构造。 |
| `2026-05-13-production-like-retrieval-v3-llm-judge` | fixture + LLM judge | 100.0% | 0.900 | v2 的扩量迭代：24 用户、150 输入、94 任务，指标更丰富；input naturalness 下降提示下一步应转向真实 replay/原始文档。 |
| `2026-05-13-retrieval-source-grounding-diversity-audit` | fixture + audit | 100.0% | 0.650 | 已改善文风，但结构仍过齐，适合作为旧大集待重构证据。 |
| `2026-05-13-hard-case-challenge-diversity-audit` | fixture + audit | 86.1% | 0.550 | source id 闭环已修，但数据仍高度模板化，只适合保留失败样本和重构优先级。 |

## 可以在面试里讲的项目观点

AI coding 时代，代码本身不是最稀缺的部分。更重要的是把一个 Agent 系统的质量问题表达成 AI agent 能理解、能复跑、能扩展的实验协议。

这个项目可以讲三层能力：

1. 我没有只看最终回答，而是把 Agent 链路拆成 card、memory、retrieval、tool routing、PKM、Super Agent、task 收敛和成本。
2. 我没有把 100% 通过包装成成功，而是区分 fixture smoke、合成基线和真实 replay。一个好 eval 应该能解释“为什么这个分数可信或不可信”。
3. 我把 LLM judge 放在合适的位置：语义 groundedness 和数据自然度交给 judge，source id、tool call、任务状态和成本仍然规则判。
4. 我没有把“prompt 里要求多样化”当成终点，而是让数据审计反过来检查模板化问题；旧大集低分、新小集高分，说明评估体系能区分表面改写和真实场景多样性。

## 后续优先级

1. 选 20-50 条真实 replay 输出，开启 LLM judge，并做人工抽样校准。
2. 用 `production_like_retrieval_v3` 的方式扩写 retrieval / journey：每个职业场景单独设计 source 结构、输入密度、噪声、跨天状态、相似干扰源和证据不足问题，而不是批量模板替换。
3. 把 `full_chain_medium` 的 loopDetection 失败作为下一轮真实产品问题入口，优先看 card_agent / pkm_agent 的工具调用终止条件。
4. 给 hard-case 做分族重构：保留种子失败，但每个 family 单独设计 persona、输入形态、ground truth 和 source 闭环。
5. 为每个新增 benchmark 明确写 `evidence_level`、适用范围和不能证明什么。

## 运行验证

- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/modules/card_extraction --run-id review-smoke-v2 --out /tmp/memex_eval_review_smoke_v2`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/retrieval_source_grounding --case-limit 1 --use-llm-judge --run-id retrieval-judge-smoke-v3 --out /tmp/memex_retrieval_judge_smoke_v3`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/memory_lifecycle --case-limit 1 --use-llm-judge --run-id memory-judge-smoke --out /tmp/memex_memory_judge_smoke`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/production_like_retrieval --use-llm-judge --run-id 2026-05-13-production-like-retrieval-llm-judge --out evals/experiments/2026-05-13-production-like-retrieval-llm-judge`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/production_like_retrieval_v2 --use-llm-judge --audit-dataset --run-id 2026-05-13-production-like-retrieval-v2-llm-judge --out evals/experiments/2026-05-13-production-like-retrieval-v2-llm-judge`
- `dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/production_like_retrieval_v3 --use-llm-judge --audit-dataset --run-id 2026-05-13-production-like-retrieval-v3-llm-judge --out evals/experiments/2026-05-13-production-like-retrieval-v3-llm-judge`
- `flutter analyze evals`
- `git diff --check`
