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
```

`experiments/` 是对外最重要的目录。每个实验目录应当像一页实验日志，而不是脚本输出垃圾桶。原始 trace、临时 outputs、API key、本地缓存都不进 git。

每次本地运行会在 `evals/runs/<run-id>/` 里留下完整排查材料：`outputs.jsonl` 记录每个 task 的断言结果，`trace.ndjson` 记录 LLM/tool/task trace，`debug_log.json` 汇总配置、指标、task 结果和 trace。这个目录默认被 git 忽略，只用于本地复盘。

当前保留四条主要实验线：

- 中等规模全链路 Journey：`datasets/full_chain_journey_medium`，按单用户串行旅程组织，覆盖多周中文输入、card、memory、Super Agent 和成本 trace。
- Hard Case Challenge：`datasets/hard_case_challenge`，专门保留边界和种子失败，用来验证失败报告、error analysis 和指标敏感度。
- Retrieval / Source Grounding：`datasets/retrieval_source_grounding`，覆盖跨 card、memory、note、PKM 的 hybrid retrieval、source citation、filter 和证据不足拒答。
- Memory Lifecycle：`datasets/memory_lifecycle`，覆盖 must-write、must-not-write、冲突更新、临时状态、过期范围、source grounding 和 Super Agent 最新记忆问答。

历史模块基线仍保留在 `datasets/modules/<module>`，用于分别验证 Card、Memory、Retrieval、Router/Tool、Schedule、PKM、Super Agent 和成本 Trace 的 grader、指标和报告口径。`full_chain_serial_smoke` 继续用于验证真实单用户操作脚本，从 `submitInput`、后台 task、memory 写入到 Super Agent 问答是否闭环。

中等规模数据集仍可通过 `generate_medium_dataset.dart` / `generate_full_chain_replay_dataset.dart` 扩展，但默认先跑小样本，避免把模型 TPS、任务并发和真实质量问题混在一起。

指标体系与扩充方向见 `METRICS.md`。新增模块实验时，优先补一个独立小数据集和独立报告，再考虑汇总到中等规模回归集。

## Harness 原则

- 和业务逻辑隔离：评估代码只能依赖业务入口，不把测试逻辑塞回产品链路。
- 从用户输入开始：全链路 replay 应尽量经过 `submitInput`、后台任务、card/fact/memory 写入、trace 收集。
- Oracle 来自 ground truth：标准答案只能来自隐藏真相和评估约束，不能从 Memex 输出反推。
- 先确定性，后 LLM judge：schema、时间、source、tool、router、token、latency 用规则判；语义质量才交给 LLM。
- 中文优先：当前 persona、用户输入、报告和 judge prompt 默认使用 `zh-CN`，贴近主要用户场景。
- 留失败样本：失败不是噪音。报告里要保留主要失败模式，尤其是任务未收敛、错误写长记忆、检索漏召回、过度 tool call。

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
