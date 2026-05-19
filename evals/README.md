# Memex Agent Eval

## 结论

`evals/` 是 Memex 的独立 Agent 评估工作区。它不承载业务逻辑，只保存评估 Harness、数据集、实验报告和必要的机器可读指标。

这个目录的核心价值不是脚本本身，而是让每次 Agent 迭代都能留下可复核的实验记录：这次要验证什么、怎么验证、看什么指标、结论是否可信、下一步应该修哪里。

## 目录约定

```text
evals/
  README.md                 # 给人和 AI 工具看的总说明
  experiments/              # 每次评估一个独立实验目录
    <date>-<topic>/
      report.md             # 实验报告，给人读
      metrics.json          # 指标快照，给工具复核
  datasets/                 # 可复现数据集
    modules/<module>/       # 分模块小实验数据集
  bin/                      # Harness、数据生成、报告生成脚本
  replay/                   # 接入真实 Memex 链路的 replay 测试
  prompts/                  # LLM judge / 数据审计 prompt
  schemas/                  # 数据集 schema
  runs/                     # 本地运行产物，git 忽略
  HARNESS_ENGINEERING.md    # 每轮实验的工程复盘、避坑和后续原则
```

`experiments/` 是对外最重要的目录。每个实验目录应当像一页实验日志，而不是脚本输出垃圾桶。原始 trace、临时 outputs、API key、本地缓存都不进 git。

每次本地运行会在 `evals/runs/<run-id>/` 里留下完整排查材料：`outputs.jsonl` 记录每个 task 的断言结果，`trace.ndjson` 记录 LLM/tool/task trace，`debug_log.json` 汇总配置、指标、task 结果和 trace。这个目录默认被 git 忽略，只用于本地复盘。

当前保留五条主要实验线：

- 中等规模全链路 Journey：`datasets/full_chain_journey_medium`，按单用户串行旅程组织，覆盖多周中文输入、card、memory、Super Agent 和成本 trace。
- 8 用户 Journey Scale：`datasets/full_chain_journey_scale_v1` 和 `datasets/full_chain_journey_scale_v2`，由 `generate_journey_scale_iteration_datasets.dart` 生成。v1 为 8 用户 × 240 record，v2 为 8 用户 × 320 record，并细化用户旅程阶段、场景族、跨日连续性、纠错、噪声和追问闭环指标。当前报告位于 `experiments/2026-05-16-full-chain-journey-scale-v1` 和 `experiments/2026-05-16-full-chain-journey-scale-v2`，证据等级仍是 fixture/grader smoke。
- 8 用户 Real Replay：`datasets/full_chain_journey_real_replay_v1` 和 `datasets/full_chain_journey_real_replay_v2`，由 `generate_real_replay_journey_datasets.dart` 从 scale 数据集切出真实 replay 分片。v1 为 8 用户、64 record、112 operations、32 tasks；v2 为 8 用户、128 record、184 operations、48 tasks。报告位于 `experiments/2026-05-17-full-chain-real-replay-v1` 和 `experiments/2026-05-17-full-chain-real-replay-v2`，证据等级为 `real_replay`。
- V4 scale-up 准备：`datasets/full_chain_journey_scale_v3` 把源数据扩到 12 用户、每用户 480 record，并新增会议纪要、浏览器剪贴、银行短信、日历片段、票据扫描、隐私安全、供应商协作、创意 brief、社区协作等输入形态和场景族。`datasets/full_chain_journey_real_replay_v4` 从中切出下一轮真实 replay：12 用户、每用户 36 record，合计 36 case、432 record、684 operations、216 eval task。建议按 12 case 一组分 3 个 shard 跑。
- Real Replay 等待预算：LLM 模式下默认不再用固定 180 秒窗口，而是按操作预计 task 单元动态等待；`record` 和 `refresh_knowledge_insights` 默认最多 15 分钟。长实验会按 `MEMEX_EVAL_STATUS_INTERVAL_SECONDS` 定期输出状态，并把当前 active task 写到 run 目录的 `status.json`。可用 `MEMEX_EVAL_TASK_TIMEOUT_SECONDS` 固定覆盖，或用 `MEMEX_EVAL_TASK_UNIT_TIMEOUT_SECONDS` / `MEMEX_EVAL_TASK_TIMEOUT_MAX_SECONDS` 调动态预算。
- Real Replay 长跑分片：完整真实 LLM 数据集可能超过 Flutter test 默认 240 分钟预算。可用 `MEMEX_EVAL_TEST_TIMEOUT_MINUTES` 放大单次测试超时；若已经完成前若干 case，可用 `MEMEX_EVAL_CASE_OFFSET` 从指定 0-based case 续跑，配合独立 run 目录保留分片证据，再用 `replay_file` adapter 汇总评分。
- Dynamic-timeout rerun：`experiments/2026-05-17-full-chain-real-replay-v2-dynamic-timeout` 使用 90 秒/task 单元、15 分钟/操作上限和 30 秒状态观测，8 用户真实 replay 用时 3小时29分29秒，181/355 断言通过。该轮证明 180 秒固定窗口偏小，但主要失败仍集中在 card/pkm agent 的 loopDetection 和重试不收敛。
- 长跑观测指标：真实 replay 报告会把操作成功率、等待收敛率、active/failed/retrying task by type、loopDetection/maxTurns、card materialization/completion、memory 产物、LLM calls/tokens by agent 和 tool diversity 单独归类展示，用来解释多小时实验的失败来自哪一层。
- Latest-main observability rerun：`experiments/2026-05-18-full-chain-real-replay-v2-latest-main-observability` 使用最新 `main` 代码和同规模 v2 数据集复跑真实 LLM，Flutter test 用时 1小时52分23秒，198/443 断言通过。该轮把 failed task 也纳入 case 级熔断，并确认主要瓶颈仍是 card/pkm agent 的 loopDetection / max-turns 终止问题。
- Latest-main skipfix v3 rerun：`experiments/2026-05-18-full-chain-real-replay-v3-latest-main-skipfix` 使用合入 `upstream/main` `4268259` 后的代码复跑 v3 真实 LLM 全量数据集。v3 为 16 case、192 record、304 operations、96 eval task；首分片完成 12 case 后被 Flutter test 240 分钟总超时截断，随后用 `MEMEX_EVAL_CASE_OFFSET=12` 续跑剩余 4 case 并合并评分。合并 case 观察耗时 5小时15分02秒，740/894 断言通过；原先“明确不要长期化/噪声/临时状态”的 no-op path 未复现失败，剩余主要问题是 PKM 复杂内容 loop、Knowledge Insight max-turn 可恢复重试和一次 Schedule Aggregator 未收敛。
- Upstream-main agentfix v3 rerun：`experiments/2026-05-19-full-chain-real-replay-v3-upstream-main-agentfix` 使用最新 `upstream/main` `bb4b9e5` 复跑同一 v3 真实 LLM 数据集，单次完整运行耗时 4小时19分16秒，782/894 断言通过。相比上一轮，任务健康从 active/failed/retrying = 1/3/0 改善到 0/1/0，`loopDetection`/`maxTurns` 从 9/6 降到 3/2；`01_a`、`04_a`、`08_b` 和 Schedule Aggregator 未收敛均已修复。唯一硬未收敛 case 是 `03_b/record_166`：PKM agent 对“相对时间提醒 + 项目冲突检查”输入反复读取 `Projects/Memex评测看板.md`，第 5 次 retry 后触发 `loopDetection`，已提 upstream issue `memex-lab/memex#154`。
- Hard Case Challenge：`datasets/hard_case_challenge`，专门保留边界和种子失败，用来验证失败报告、error analysis 和指标敏感度。
- Retrieval / Source Grounding：`datasets/retrieval_source_grounding`，覆盖跨 card、memory、note、PKM 的 hybrid retrieval、source citation、filter 和证据不足拒答。
- Production-like Retrieval：`datasets/production_like_retrieval`、`datasets/production_like_retrieval_v2` 和 `datasets/production_like_retrieval_v3`，用手工策划的异质职业场景验证检索、引用和拒答，重点解决合成数据文风单调、结构过齐的问题。v3 扩到 24 个用户、150 条输入、94 个任务。
- Memory Lifecycle：`datasets/memory_lifecycle`，覆盖 must-write、must-not-write、冲突更新、临时状态、过期范围、source grounding 和 Super Agent 最新记忆问答。
- Realistic Full-chain Smoke：`datasets/full_chain_realistic_smoke`，小样本真实 replay 起点，覆盖跨天记录、timeline browse、comment、schedule aggregation、knowledge insight refresh、memory wait 和 Super Agent quick query。本数据集先用 `case-limit=1` 跑通真实链路，再扩到完整 2 case 和更多 persona。

历史模块基线仍保留在 `datasets/modules/<module>`，用于分别验证 Card、Memory、Retrieval、Router/Tool、Schedule、PKM、Super Agent 和成本 Trace 的 grader、指标和报告口径。`full_chain_serial_smoke` 继续用于验证真实单用户操作脚本，从 `submitInput`、后台 task、memory 写入到 Super Agent 问答是否闭环。

中等规模数据集仍可通过 `generate_medium_dataset.dart` / `generate_full_chain_replay_dataset.dart` 扩展，但默认先跑小样本，避免把模型 TPS、任务并发和真实质量问题混在一起。

指标体系与扩充方向见 `METRICS.md`。每轮实验过程、发现的问题和下轮避坑记录在 `HARNESS_ENGINEERING.md`。新增模块实验时，优先补一个独立小数据集和独立报告，再考虑汇总到中等规模回归集。

## 如何读这些实验

不要把所有 100% 通过都读成“Agent 能力已经可靠”。本目录刻意区分三种证据等级：

- `fixture_grader_smoke`：观察结果来自 `fixture_observed`，主要验证 grader、指标聚合和报告结构。它能证明“测试口径能跑通”，不能证明真实 Agent 能做到。
- `audited_synthetic_fixture`：仍是合成 fixture，但经过数据质量审计且 overall >= 0.8。适合做小规模回归基线，仍要用 replay 抽样校准。
- `real_replay`：观察结果来自真实 Memex 链路，例如 submitInput、LocalTaskExecutor、card/memory/trace/Super Agent 输出。它才是判断 Agent 行为和成本收敛的主要证据。

因此报告里的“断言通过率”和“数据质量审计”要一起读：如果 fixture 断言全绿但审计低于 0.8，结论应是 grader smoke 通过，而不是强 benchmark 通过。

数据质量审计的抽样按 `family_round_robin` 分层：同一数据集有多个场景 family 时，会轮流抽取各 family 的 case，避免只审到 JSONL 排在前面的单一类别。

## AI Agent 运行约定

面向 Codex 一类 AI coding agent 时，优先让它读本文件、`METRICS.md` 和目标实验的 `report.md` / `metrics.json`，再决定是否复跑。常用入口：

```bash
dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/modules/card_extraction \
  --out evals/runs/<run-id>

dart evals/bin/generate_journey_scale_iteration_datasets.dart

MEMEX_EVAL_ENABLE_LLM=1 \
flutter test evals/replay/serial_full_chain_replay_test.dart
```

如果本地配置了 WebSocket/HTTP 代理，`flutter_tester` 可能在本地 WebSocket 握手时报 `Invalid WebSocket upgrade request`。真实 replay 可先取消代理环境变量：

```bash
env -u ws_proxy -u wss_proxy -u http_proxy -u https_proxy \
  MEMEX_EVAL_ENABLE_LLM=1 \
  flutter test --no-pub evals/replay/serial_full_chain_replay_test.dart
```

如果启用 LLM judge，使用环境变量传 key 和模型信息：

```bash
EVAL_LLM_PROVIDER=openai_chat \
EVAL_LLM_BASE_URL=https://api.openai.com/v1 \
EVAL_LLM_API_KEY=... \
EVAL_LLM_MODEL=gpt-5.4 \
dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/retrieval_source_grounding \
  --use-llm-judge
```

`--use-llm-judge` 会默认审查 `retrieval_qa` 和 `super_agent_qa` 的语义质量；如果某个 task 只想走规则断言，在 `expected` 里写 `"llm_judge": false`。

## Harness 原则

- 和业务逻辑隔离：评估代码只能依赖业务入口，不把测试逻辑塞回产品链路。
- 从用户输入开始：全链路 replay 应尽量经过 `submitInput`、后台任务、card/fact/memory 写入、trace 收集。
- 先验隔离检查：真实 replay 长跑前必须先跑 root-switch smoke，并在每个 case 第一条输入后断言 Facts/Cards 写入当前 case root；若 root invariant 失败，本轮应标记为 harness/project consistency failure，而不是 LLM/agent 能力失败。详细规避清单见 `HARNESS_ENGINEERING.md` 的 `2026-05-18 Post-run Log Audit`。
- Oracle 来自 ground truth：标准答案只能来自隐藏真相和评估约束，不能从 Memex 输出反推。
- 先确定性，后 LLM judge：schema、时间、source、tool、router、token、latency 用规则判；语义质量才交给 LLM。
- 中文优先：当前 persona、用户输入、报告和 judge prompt 默认使用 `zh-CN`，贴近主要用户场景。
- 留失败样本：失败不是噪音。报告里要保留主要失败模式，尤其是任务未收敛、错误写长记忆、检索漏召回、过度 tool call。
- 数据不要写成整齐模板：允许碎碎念、语音口吻、心情、冗余背景、无意义闲聊和弱相关信息；不同职业 persona 要有领域差异，不能只替换人名、城市和项目名。

## 实验报告格式

每个 `experiments/<date>-<topic>/report.md` 至少包含：

1. 关键结论：能不能作为基线，最重要的失败是什么。
2. 实验问题与背景：这次为什么跑，要回答什么问题。
3. 数据集与成本规模：persona、case、输入、task、断言、token、LLM/tool 调用量。
4. 指标口径：每个场景和关键指标到底在衡量什么。
5. 结果数据：分场景结果、关键指标表、成本 trace。
6. 失败样本：优先列会影响产品判断的失败。
7. 实验详情：adapter、run id、数据集路径、任务明细。
8. 附录：数据集、persona 和输入示例放在最后。

这个格式比“跑了一个脚本”更重要。它让后续的人或 AI 工具能快速判断：这次实验是否可信，是否能对比下一次实验，是否暴露了真实回归。

## 给 AI 工具看的约束

- 默认只改 `evals/`；除非用户明确要求，不改 Memex 业务逻辑。
- 如果为了评估真实性必须触碰主逻辑，只允许加默认不改变产品行为的测试钩子，例如可选时间注入或测试并发覆盖。
- 新增一次评估时，新建 `evals/experiments/<date>-<short-topic>/`，至少提交 `report.md` 和 `metrics.json`。
- 不把 `evals/runs/`、`.env`、API key、完整 LLM 原始响应或临时 trace 提交进 git。
- 报告用中文，结论靠前，数据集/persona 示例放在最后。
- 指标大表必须包含“场景”和“类别”，避免只看 metric id 猜含义。
- 如果用外部模型，key 只能通过环境变量或本地忽略文件传入。
- 如果某次实验不是全绿，也要如实写进结论；评估发现真实失败，比粉饰通过更有价值。
- 全链路 replay 默认按单用户串行执行：一个 persona、一个操作、一轮 idle，再进入下一步；不把多用户并发压测混入 Agent 质量评估。
- 讲项目时先讲实验设计和证据等级，再讲分数。分数只是结论的一部分，trace、失败模式和数据审计决定这个分数能不能被相信。
