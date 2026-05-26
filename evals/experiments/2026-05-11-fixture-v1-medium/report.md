# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/v1_medium`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 210 个 case、210 个 eval task，断言通过率 99.2%。
- 失败断言数：10；Token 总量：441550；LLM 调用次数：220；工具调用次数：208。
- 主要失败项：
  - `medium_memory_010_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_010: 用户今天想喝奶茶。
  - `medium_memory_010_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
  - `medium_memory_020_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_020: 用户不喜欢排太满。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 50 |
| Case | 210 |
| 用户输入 | 310 |
| Eval task | 210 |
| 断言 | 1266 |
| LLM 调用 | 220 |
| Tool 调用 | 208 |
| 实际 token | 441550 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 441550 tokens；同规模复跑可先按 353240-529860 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |
| 成本 / Trace | 检查 token、延迟和工具调用数量是否在预算内。 |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| 检索问答 | 检查查询时是否召回正确来源，并基于证据回答。 |
| 路由 / 工具调用 | 检查路由标签、工具选择、工具参数和禁止工具调用。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 |
| Card 抽取 | 字段抽取 | `location_accuracy` | 地点字段是否包含期望地点。 |
| Card 抽取 | 字段抽取 | `participant_recall` | 期望人物是否都被抽取出来。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 时间解析是否落在允许误差内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |
| 成本 / Trace | Token 成本 | `total_token_budget` | 总 token 是否未超过预算。 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 工具调用次数是否未超过预算。 |
| 成本 / Trace | 延迟 | `latency_budget` | 最大延迟是否未超过预算。 |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 成本受控时，回答是否仍覆盖必要结论。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | Top 1 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | Top 3 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | Top 5 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 第一个正确来源排名的倒数，越高越好。 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | Top 5 中覆盖了多少期望来源。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 答案引用的来源是否覆盖期望来源。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 路由分类是否等于期望标签。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 350 | 350 | 100.0% | 1.000 |
| 成本 / Trace | 40 | 40 | 100.0% | 0.688 |
| 记忆写入 | 240 | 250 | 96.0% | 0.983 |
| 检索问答 | 450 | 450 | 100.0% | 1.000 |
| 路由 / 工具调用 | 176 | 176 | 100.0% | - |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 50 | 50 | 100.0% | - |
| Card 抽取 | 字段抽取 | `location_accuracy` | 50 | 50 | 100.0% | - |
| Card 抽取 | 字段抽取 | `participant_recall` | 50 | 50 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 50 | 50 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 50 | 50 | 100.0% | - |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 50 | 50 | 100.0% | 1.000 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 50 | 50 | 100.0% | - |
| 成本 / Trace | Token 成本 | `total_token_budget` | 10 | 10 | 100.0% | 0.376 |
| 成本 / Trace | 工具成本 | `tool_call_budget` | 10 | 10 | 100.0% | - |
| 成本 / Trace | 延迟 | `latency_budget` | 10 | 10 | 100.0% | - |
| 成本 / Trace | 答案完整性 | `cost_answer_must_include` | 10 | 10 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 50 | 50 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 50 | 50 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 50 | 50 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 50 | 50 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 50 | 50 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 45 | 50 | 90.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 45 | 50 | 90.0% | 0.950 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 50 | 50 | 100.0% | 1.000 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 50 | 50 | 100.0% | - |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 38 | 38 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 50 | 50 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 38 | 38 | 100.0% | - |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 50 | 50 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：220
- 工具调用次数：208
- Token 总量：441550
- 单次 LLM 平均 token：2007.045
- 平均延迟：1426.869 ms
- P95 延迟：2633.000 ms

## 失败样本

- `medium_memory_010_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_010: 用户今天想喝奶茶。
- `medium_memory_010_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `medium_memory_020_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_020: 用户不喜欢排太满。
- `medium_memory_020_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `medium_memory_030_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_030: 用户今天上午想安静一会儿。
- `medium_memory_030_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `medium_memory_040_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_040: 用户今天想喝奶茶。
- `medium_memory_040_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.
- `medium_memory_050_t1` / `memory_must_not_write_precision`：把不应该写入的临时信息写成了长期记忆。原始信息：Wrote prohibited memory transient_050: 用户不喜欢排太满。
- `medium_memory_050_t1` / `memory_write_precision`：写入记忆里混入了非长期事实，写入精度不足。Matched 1 required writes across 2 written memories.

## 问题排查与建议

### 排查过程

- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。
- 对 memory 失败，检查写入 memory 的 source_ids 和内容是否来自临时输入或显式“不要当成长期习惯”的输入。

### 结论

- Memory 写入边界仍需加强：临时状态或显式反例会被误写成长记忆。

### 修改建议

- 在 memory write prompt / schema 中显式区分长期偏好、一次性状态和用户明确否定长期化的输入。
- 给 memory 写入增加 temporal_scope / confidence / source span 字段，低置信或短期事实默认不进入长期记忆。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-fixture-v1-medium-expanded`
- 数据集：`evals/datasets/v1_medium`
- 观察适配器：`fixture`
- 场景样本数：210
- 评估任务数：210
- 断言通过：1256/1266 （99.2%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `medium_card_001` | `medium_card_001_t1` | 通过 | 0 |
| `medium_card_002` | `medium_card_002_t1` | 通过 | 0 |
| `medium_card_003` | `medium_card_003_t1` | 通过 | 0 |
| `medium_card_004` | `medium_card_004_t1` | 通过 | 0 |
| `medium_card_005` | `medium_card_005_t1` | 通过 | 0 |
| `medium_card_006` | `medium_card_006_t1` | 通过 | 0 |
| `medium_card_007` | `medium_card_007_t1` | 通过 | 0 |
| `medium_card_008` | `medium_card_008_t1` | 通过 | 0 |
| `medium_card_009` | `medium_card_009_t1` | 通过 | 0 |
| `medium_card_010` | `medium_card_010_t1` | 通过 | 0 |
| `medium_card_011` | `medium_card_011_t1` | 通过 | 0 |
| `medium_card_012` | `medium_card_012_t1` | 通过 | 0 |
| `medium_card_013` | `medium_card_013_t1` | 通过 | 0 |
| `medium_card_014` | `medium_card_014_t1` | 通过 | 0 |
| `medium_card_015` | `medium_card_015_t1` | 通过 | 0 |
| `medium_card_016` | `medium_card_016_t1` | 通过 | 0 |
| `medium_card_017` | `medium_card_017_t1` | 通过 | 0 |
| `medium_card_018` | `medium_card_018_t1` | 通过 | 0 |
| `medium_card_019` | `medium_card_019_t1` | 通过 | 0 |
| `medium_card_020` | `medium_card_020_t1` | 通过 | 0 |
| `medium_card_021` | `medium_card_021_t1` | 通过 | 0 |
| `medium_card_022` | `medium_card_022_t1` | 通过 | 0 |
| `medium_card_023` | `medium_card_023_t1` | 通过 | 0 |
| `medium_card_024` | `medium_card_024_t1` | 通过 | 0 |
| `medium_card_025` | `medium_card_025_t1` | 通过 | 0 |
| `medium_card_026` | `medium_card_026_t1` | 通过 | 0 |
| `medium_card_027` | `medium_card_027_t1` | 通过 | 0 |
| `medium_card_028` | `medium_card_028_t1` | 通过 | 0 |
| `medium_card_029` | `medium_card_029_t1` | 通过 | 0 |
| `medium_card_030` | `medium_card_030_t1` | 通过 | 0 |
| `medium_card_031` | `medium_card_031_t1` | 通过 | 0 |
| `medium_card_032` | `medium_card_032_t1` | 通过 | 0 |
| `medium_card_033` | `medium_card_033_t1` | 通过 | 0 |
| `medium_card_034` | `medium_card_034_t1` | 通过 | 0 |
| `medium_card_035` | `medium_card_035_t1` | 通过 | 0 |
| `medium_card_036` | `medium_card_036_t1` | 通过 | 0 |
| `medium_card_037` | `medium_card_037_t1` | 通过 | 0 |
| `medium_card_038` | `medium_card_038_t1` | 通过 | 0 |
| `medium_card_039` | `medium_card_039_t1` | 通过 | 0 |
| `medium_card_040` | `medium_card_040_t1` | 通过 | 0 |
| `medium_card_041` | `medium_card_041_t1` | 通过 | 0 |
| `medium_card_042` | `medium_card_042_t1` | 通过 | 0 |
| `medium_card_043` | `medium_card_043_t1` | 通过 | 0 |
| `medium_card_044` | `medium_card_044_t1` | 通过 | 0 |
| `medium_card_045` | `medium_card_045_t1` | 通过 | 0 |
| `medium_card_046` | `medium_card_046_t1` | 通过 | 0 |
| `medium_card_047` | `medium_card_047_t1` | 通过 | 0 |
| `medium_card_048` | `medium_card_048_t1` | 通过 | 0 |
| `medium_card_049` | `medium_card_049_t1` | 通过 | 0 |
| `medium_card_050` | `medium_card_050_t1` | 通过 | 0 |

#### 成本 / Trace

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `medium_cost_005` | `medium_cost_005_t1` | 通过 | 0 |
| `medium_cost_010` | `medium_cost_010_t1` | 通过 | 0 |
| `medium_cost_015` | `medium_cost_015_t1` | 通过 | 0 |
| `medium_cost_020` | `medium_cost_020_t1` | 通过 | 0 |
| `medium_cost_025` | `medium_cost_025_t1` | 通过 | 0 |
| `medium_cost_030` | `medium_cost_030_t1` | 通过 | 0 |
| `medium_cost_035` | `medium_cost_035_t1` | 通过 | 0 |
| `medium_cost_040` | `medium_cost_040_t1` | 通过 | 0 |
| `medium_cost_045` | `medium_cost_045_t1` | 通过 | 0 |
| `medium_cost_050` | `medium_cost_050_t1` | 通过 | 0 |

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `medium_memory_001` | `medium_memory_001_t1` | 通过 | 0 |
| `medium_memory_002` | `medium_memory_002_t1` | 通过 | 0 |
| `medium_memory_003` | `medium_memory_003_t1` | 通过 | 0 |
| `medium_memory_004` | `medium_memory_004_t1` | 通过 | 0 |
| `medium_memory_005` | `medium_memory_005_t1` | 通过 | 0 |
| `medium_memory_006` | `medium_memory_006_t1` | 通过 | 0 |
| `medium_memory_007` | `medium_memory_007_t1` | 通过 | 0 |
| `medium_memory_008` | `medium_memory_008_t1` | 通过 | 0 |
| `medium_memory_009` | `medium_memory_009_t1` | 通过 | 0 |
| `medium_memory_010` | `medium_memory_010_t1` | 未通过 | 2 |
| `medium_memory_011` | `medium_memory_011_t1` | 通过 | 0 |
| `medium_memory_012` | `medium_memory_012_t1` | 通过 | 0 |
| `medium_memory_013` | `medium_memory_013_t1` | 通过 | 0 |
| `medium_memory_014` | `medium_memory_014_t1` | 通过 | 0 |
| `medium_memory_015` | `medium_memory_015_t1` | 通过 | 0 |
| `medium_memory_016` | `medium_memory_016_t1` | 通过 | 0 |
| `medium_memory_017` | `medium_memory_017_t1` | 通过 | 0 |
| `medium_memory_018` | `medium_memory_018_t1` | 通过 | 0 |
| `medium_memory_019` | `medium_memory_019_t1` | 通过 | 0 |
| `medium_memory_020` | `medium_memory_020_t1` | 未通过 | 2 |
| `medium_memory_021` | `medium_memory_021_t1` | 通过 | 0 |
| `medium_memory_022` | `medium_memory_022_t1` | 通过 | 0 |
| `medium_memory_023` | `medium_memory_023_t1` | 通过 | 0 |
| `medium_memory_024` | `medium_memory_024_t1` | 通过 | 0 |
| `medium_memory_025` | `medium_memory_025_t1` | 通过 | 0 |
| `medium_memory_026` | `medium_memory_026_t1` | 通过 | 0 |
| `medium_memory_027` | `medium_memory_027_t1` | 通过 | 0 |
| `medium_memory_028` | `medium_memory_028_t1` | 通过 | 0 |
| `medium_memory_029` | `medium_memory_029_t1` | 通过 | 0 |
| `medium_memory_030` | `medium_memory_030_t1` | 未通过 | 2 |
| `medium_memory_031` | `medium_memory_031_t1` | 通过 | 0 |
| `medium_memory_032` | `medium_memory_032_t1` | 通过 | 0 |
| `medium_memory_033` | `medium_memory_033_t1` | 通过 | 0 |
| `medium_memory_034` | `medium_memory_034_t1` | 通过 | 0 |
| `medium_memory_035` | `medium_memory_035_t1` | 通过 | 0 |
| `medium_memory_036` | `medium_memory_036_t1` | 通过 | 0 |
| `medium_memory_037` | `medium_memory_037_t1` | 通过 | 0 |
| `medium_memory_038` | `medium_memory_038_t1` | 通过 | 0 |
| `medium_memory_039` | `medium_memory_039_t1` | 通过 | 0 |
| `medium_memory_040` | `medium_memory_040_t1` | 未通过 | 2 |
| `medium_memory_041` | `medium_memory_041_t1` | 通过 | 0 |
| `medium_memory_042` | `medium_memory_042_t1` | 通过 | 0 |
| `medium_memory_043` | `medium_memory_043_t1` | 通过 | 0 |
| `medium_memory_044` | `medium_memory_044_t1` | 通过 | 0 |
| `medium_memory_045` | `medium_memory_045_t1` | 通过 | 0 |
| `medium_memory_046` | `medium_memory_046_t1` | 通过 | 0 |
| `medium_memory_047` | `medium_memory_047_t1` | 通过 | 0 |
| `medium_memory_048` | `medium_memory_048_t1` | 通过 | 0 |
| `medium_memory_049` | `medium_memory_049_t1` | 通过 | 0 |
| `medium_memory_050` | `medium_memory_050_t1` | 未通过 | 2 |

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `medium_retrieval_001` | `medium_retrieval_001_t1` | 通过 | 0 |
| `medium_retrieval_002` | `medium_retrieval_002_t1` | 通过 | 0 |
| `medium_retrieval_003` | `medium_retrieval_003_t1` | 通过 | 0 |
| `medium_retrieval_004` | `medium_retrieval_004_t1` | 通过 | 0 |
| `medium_retrieval_005` | `medium_retrieval_005_t1` | 通过 | 0 |
| `medium_retrieval_006` | `medium_retrieval_006_t1` | 通过 | 0 |
| `medium_retrieval_007` | `medium_retrieval_007_t1` | 通过 | 0 |
| `medium_retrieval_008` | `medium_retrieval_008_t1` | 通过 | 0 |
| `medium_retrieval_009` | `medium_retrieval_009_t1` | 通过 | 0 |
| `medium_retrieval_010` | `medium_retrieval_010_t1` | 通过 | 0 |
| `medium_retrieval_011` | `medium_retrieval_011_t1` | 通过 | 0 |
| `medium_retrieval_012` | `medium_retrieval_012_t1` | 通过 | 0 |
| `medium_retrieval_013` | `medium_retrieval_013_t1` | 通过 | 0 |
| `medium_retrieval_014` | `medium_retrieval_014_t1` | 通过 | 0 |
| `medium_retrieval_015` | `medium_retrieval_015_t1` | 通过 | 0 |
| `medium_retrieval_016` | `medium_retrieval_016_t1` | 通过 | 0 |
| `medium_retrieval_017` | `medium_retrieval_017_t1` | 通过 | 0 |
| `medium_retrieval_018` | `medium_retrieval_018_t1` | 通过 | 0 |
| `medium_retrieval_019` | `medium_retrieval_019_t1` | 通过 | 0 |
| `medium_retrieval_020` | `medium_retrieval_020_t1` | 通过 | 0 |
| `medium_retrieval_021` | `medium_retrieval_021_t1` | 通过 | 0 |
| `medium_retrieval_022` | `medium_retrieval_022_t1` | 通过 | 0 |
| `medium_retrieval_023` | `medium_retrieval_023_t1` | 通过 | 0 |
| `medium_retrieval_024` | `medium_retrieval_024_t1` | 通过 | 0 |
| `medium_retrieval_025` | `medium_retrieval_025_t1` | 通过 | 0 |
| `medium_retrieval_026` | `medium_retrieval_026_t1` | 通过 | 0 |
| `medium_retrieval_027` | `medium_retrieval_027_t1` | 通过 | 0 |
| `medium_retrieval_028` | `medium_retrieval_028_t1` | 通过 | 0 |
| `medium_retrieval_029` | `medium_retrieval_029_t1` | 通过 | 0 |
| `medium_retrieval_030` | `medium_retrieval_030_t1` | 通过 | 0 |
| `medium_retrieval_031` | `medium_retrieval_031_t1` | 通过 | 0 |
| `medium_retrieval_032` | `medium_retrieval_032_t1` | 通过 | 0 |
| `medium_retrieval_033` | `medium_retrieval_033_t1` | 通过 | 0 |
| `medium_retrieval_034` | `medium_retrieval_034_t1` | 通过 | 0 |
| `medium_retrieval_035` | `medium_retrieval_035_t1` | 通过 | 0 |
| `medium_retrieval_036` | `medium_retrieval_036_t1` | 通过 | 0 |
| `medium_retrieval_037` | `medium_retrieval_037_t1` | 通过 | 0 |
| `medium_retrieval_038` | `medium_retrieval_038_t1` | 通过 | 0 |
| `medium_retrieval_039` | `medium_retrieval_039_t1` | 通过 | 0 |
| `medium_retrieval_040` | `medium_retrieval_040_t1` | 通过 | 0 |
| `medium_retrieval_041` | `medium_retrieval_041_t1` | 通过 | 0 |
| `medium_retrieval_042` | `medium_retrieval_042_t1` | 通过 | 0 |
| `medium_retrieval_043` | `medium_retrieval_043_t1` | 通过 | 0 |
| `medium_retrieval_044` | `medium_retrieval_044_t1` | 通过 | 0 |
| `medium_retrieval_045` | `medium_retrieval_045_t1` | 通过 | 0 |
| `medium_retrieval_046` | `medium_retrieval_046_t1` | 通过 | 0 |
| `medium_retrieval_047` | `medium_retrieval_047_t1` | 通过 | 0 |
| `medium_retrieval_048` | `medium_retrieval_048_t1` | 通过 | 0 |
| `medium_retrieval_049` | `medium_retrieval_049_t1` | 通过 | 0 |
| `medium_retrieval_050` | `medium_retrieval_050_t1` | 通过 | 0 |

#### 路由 / 工具调用

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `medium_tool_001` | `medium_tool_001_t1` | 通过 | 0 |
| `medium_tool_002` | `medium_tool_002_t1` | 通过 | 0 |
| `medium_tool_003` | `medium_tool_003_t1` | 通过 | 0 |
| `medium_tool_004` | `medium_tool_004_t1` | 通过 | 0 |
| `medium_tool_005` | `medium_tool_005_t1` | 通过 | 0 |
| `medium_tool_006` | `medium_tool_006_t1` | 通过 | 0 |
| `medium_tool_007` | `medium_tool_007_t1` | 通过 | 0 |
| `medium_tool_008` | `medium_tool_008_t1` | 通过 | 0 |
| `medium_tool_009` | `medium_tool_009_t1` | 通过 | 0 |
| `medium_tool_010` | `medium_tool_010_t1` | 通过 | 0 |
| `medium_tool_011` | `medium_tool_011_t1` | 通过 | 0 |
| `medium_tool_012` | `medium_tool_012_t1` | 通过 | 0 |
| `medium_tool_013` | `medium_tool_013_t1` | 通过 | 0 |
| `medium_tool_014` | `medium_tool_014_t1` | 通过 | 0 |
| `medium_tool_015` | `medium_tool_015_t1` | 通过 | 0 |
| `medium_tool_016` | `medium_tool_016_t1` | 通过 | 0 |
| `medium_tool_017` | `medium_tool_017_t1` | 通过 | 0 |
| `medium_tool_018` | `medium_tool_018_t1` | 通过 | 0 |
| `medium_tool_019` | `medium_tool_019_t1` | 通过 | 0 |
| `medium_tool_020` | `medium_tool_020_t1` | 通过 | 0 |
| `medium_tool_021` | `medium_tool_021_t1` | 通过 | 0 |
| `medium_tool_022` | `medium_tool_022_t1` | 通过 | 0 |
| `medium_tool_023` | `medium_tool_023_t1` | 通过 | 0 |
| `medium_tool_024` | `medium_tool_024_t1` | 通过 | 0 |
| `medium_tool_025` | `medium_tool_025_t1` | 通过 | 0 |
| `medium_tool_026` | `medium_tool_026_t1` | 通过 | 0 |
| `medium_tool_027` | `medium_tool_027_t1` | 通过 | 0 |
| `medium_tool_028` | `medium_tool_028_t1` | 通过 | 0 |
| `medium_tool_029` | `medium_tool_029_t1` | 通过 | 0 |
| `medium_tool_030` | `medium_tool_030_t1` | 通过 | 0 |
| `medium_tool_031` | `medium_tool_031_t1` | 通过 | 0 |
| `medium_tool_032` | `medium_tool_032_t1` | 通过 | 0 |
| `medium_tool_033` | `medium_tool_033_t1` | 通过 | 0 |
| `medium_tool_034` | `medium_tool_034_t1` | 通过 | 0 |
| `medium_tool_035` | `medium_tool_035_t1` | 通过 | 0 |
| `medium_tool_036` | `medium_tool_036_t1` | 通过 | 0 |
| `medium_tool_037` | `medium_tool_037_t1` | 通过 | 0 |
| `medium_tool_038` | `medium_tool_038_t1` | 通过 | 0 |
| `medium_tool_039` | `medium_tool_039_t1` | 通过 | 0 |
| `medium_tool_040` | `medium_tool_040_t1` | 通过 | 0 |
| `medium_tool_041` | `medium_tool_041_t1` | 通过 | 0 |
| `medium_tool_042` | `medium_tool_042_t1` | 通过 | 0 |
| `medium_tool_043` | `medium_tool_043_t1` | 通过 | 0 |
| `medium_tool_044` | `medium_tool_044_t1` | 通过 | 0 |
| `medium_tool_045` | `medium_tool_045_t1` | 通过 | 0 |
| `medium_tool_046` | `medium_tool_046_t1` | 通过 | 0 |
| `medium_tool_047` | `medium_tool_047_t1` | 通过 | 0 |
| `medium_tool_048` | `medium_tool_048_t1` | 通过 | 0 |
| `medium_tool_049` | `medium_tool_049_t1` | 通过 | 0 |
| `medium_tool_050` | `medium_tool_050_t1` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：50
- 输入条数：310
- Eval task 数：210
- Case family 分布：card_extraction=50，cost_trace=10，memory_write=50，retrieval_qa=50，tool_calling=50
- Task type 分布：card_extraction=50，cost_trace=10，memory_write=50，retrieval_qa=50，tool_calling=50

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `eval_medium_001` | 跨境电商运营 | 深圳 | zh-CN | 4 | 6 | 4 | 帮我记一下，周三上午10点半和Ada在飞书会议讨论版本灰度。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_002` | 产品经理 | 杭州 | zh-CN | 4 | 6 | 4 | 帮我记一下，周四上午11点半和老王在望京讨论客户续约。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_003` | 独立开发者 | 上海 | zh-CN | 4 | 6 | 4 | 帮我记一下，周五中午12点半和Annie在深圳湾办公室讨论活动复盘。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_004` | 市场经理 | 北京 | zh-CN | 4 | 6 | 4 | 帮我记一下，周二下午1点半和Leo在公司 12 楼会议室讨论合同风险。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_005` | 律师 | 广州 | zh-CN | 5 | 7 | 5 | 帮我记一下，周三下午2点半和Mina在线上会议讨论数据看板。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_006` | 财务主管 | 成都 | zh-CN | 4 | 6 | 4 | 帮我记一下，周四下午3点半和小陈在腾讯会议讨论投流预算。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_007` | 内容运营 | 苏州 | zh-CN | 4 | 6 | 4 | 帮我记一下，周五下午4点半和Grace在飞书会议讨论版本灰度。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_008` | 咨询顾问 | 厦门 | zh-CN | 4 | 6 | 4 | 帮我记一下，周二上午9点半和Jason在望京讨论客户续约。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_009` | 游戏策划 | 南京 | zh-CN | 4 | 6 | 4 | 帮我记一下，周三上午10点半和Ada在深圳湾办公室讨论活动复盘。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_010` | 数据分析师 | 武汉 | zh-CN | 5 | 7 | 5 | 帮我记一下，周四上午11点半和老王在公司 12 楼会议室讨论合同风险。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_011` | 跨境电商运营 | 深圳 | zh-CN | 4 | 6 | 4 | 帮我记一下，周五中午12点半和Annie在线上会议讨论数据看板。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_012` | 产品经理 | 杭州 | zh-CN | 4 | 6 | 4 | 帮我记一下，周二下午1点半和Leo在腾讯会议讨论投流预算。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_013` | 独立开发者 | 上海 | zh-CN | 4 | 6 | 4 | 帮我记一下，周三下午2点半和Mina在飞书会议讨论版本灰度。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_014` | 市场经理 | 北京 | zh-CN | 4 | 6 | 4 | 帮我记一下，周四下午3点半和小陈在望京讨论客户续约。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_015` | 律师 | 广州 | zh-CN | 5 | 7 | 5 | 帮我记一下，周五下午4点半和Grace在深圳湾办公室讨论活动复盘。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_016` | 财务主管 | 成都 | zh-CN | 4 | 6 | 4 | 帮我记一下，周二上午9点半和Jason在公司 12 楼会议室讨论合同风险。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_017` | 内容运营 | 苏州 | zh-CN | 4 | 6 | 4 | 帮我记一下，周三上午10点半和Ada在线上会议讨论数据看板。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |
| `eval_medium_018` | 咨询顾问 | 厦门 | zh-CN | 4 | 6 | 4 | 帮我记一下，周四上午11点半和老王在腾讯会议讨论投流预算。<br>以后重要会议尽量提前一天提醒我，别临近了才说。 |
| `eval_medium_019` | 游戏策划 | 南京 | zh-CN | 4 | 6 | 4 | 帮我记一下，周五中午12点半和Annie在飞书会议讨论版本灰度。<br>我一般上午适合深度工作，下午再安排同步会。 |
| `eval_medium_020` | 数据分析师 | 武汉 | zh-CN | 5 | 7 | 5 | 帮我记一下，周二下午1点半和Leo在望京讨论客户续约。<br>以后给我项目结论时，最好带上来源，不要只给判断。 |

仅展示前 20 个 Persona。
