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
  bin/                      # Harness、数据生成、报告生成脚本
  replay/                   # 接入真实 Memex 链路的 replay 测试
  prompts/                  # LLM judge / 数据审计 prompt
  schemas/                  # 数据集 schema
  runs/                     # 本地运行产物，git 忽略
```

`experiments/` 是对外最重要的目录。每个实验目录应当像一页实验日志，而不是脚本输出垃圾桶。原始 trace、临时 outputs、API key、本地缓存都不进 git。

每次本地运行会在 `evals/runs/<run-id>/` 里留下完整排查材料：`outputs.jsonl` 记录每个 task 的断言结果，`trace.ndjson` 记录 LLM/tool/task trace，`debug_log.json` 汇总配置、指标、task 结果和 trace。这个目录默认被 git 忽略，只用于本地复盘。

当前保留两条实验线：`v1_medium` 用于验证 fixture adapter、grader、指标和报告稳定性；`full_chain_medium` 用于验证真实 submitInput 到后台任务和 trace 的全链路稳定性。数据集由 `evals/bin/generate_medium_dataset.dart` 和 `evals/bin/generate_full_chain_replay_dataset.dart` 确定性生成；小样本 smoke 数据集不提交，只在需要时用 `--case-limit` 临时截取。

## Harness 原则

- 和业务逻辑隔离：评估代码只能依赖业务入口，不把测试逻辑塞回产品链路。
- 从用户输入开始：全链路 replay 应尽量经过 `submitInput`、后台任务、card/fact/memory 写入、trace 收集。
- Oracle 来自 ground truth：标准答案只能来自隐藏真相和评估约束，不能从 Memex 输出反推。
- 先确定性，后 LLM judge：schema、时间、source、tool、router、token、latency 用规则判；语义质量才交给 LLM。
- 中文优先：当前 persona、用户输入、报告和 judge prompt 默认使用 `zh-CN`，贴近主要用户场景。
- 留失败样本：失败不是噪音。报告里要保留主要失败模式，尤其是任务未收敛、错误写长记忆、检索漏召回、过度 tool call。

## 实验报告格式

每个 `experiments/<date>-<topic>/report.md` 至少包含：

1. 实验问题与背景：这次为什么跑，要回答什么问题。
2. 关键结论：能不能作为基线，最重要的失败是什么。
3. 数据集与成本规模：persona、case、输入、task、断言、token、LLM/tool 调用量。
4. 指标口径：每个场景和关键指标到底在衡量什么。
5. 结果数据：分场景结果、关键指标表、成本 trace。
6. 失败样本：优先列会影响产品判断的失败。
7. 实验详情：adapter、run id、数据集路径、任务明细。
8. 附录：数据集、persona 和输入示例放在最后。

这个格式比“跑了一个脚本”更重要。它让后续的人或 AI 工具能快速判断：这次实验是否可信，是否能对比下一次实验，是否暴露了真实回归。

## 给 AI 工具看的约束

- 默认只改 `evals/`；除非用户明确要求，不改 Memex 业务逻辑。
- 新增一次评估时，新建 `evals/experiments/<date>-<short-topic>/`，至少提交 `report.md` 和 `metrics.json`。
- 不把 `evals/runs/`、`.env`、API key、完整 LLM 原始响应或临时 trace 提交进 git。
- 报告用中文，结论靠前，数据集/persona 示例放在最后。
- 指标大表必须包含“场景”和“类别”，避免只看 metric id 猜含义。
- 如果用外部模型，key 只能通过环境变量或本地忽略文件传入。
- 如果某次实验不是全绿，也要如实写进结论；评估发现真实失败，比粉饰通过更有价值。
