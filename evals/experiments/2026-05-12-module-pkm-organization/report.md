# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/pkm_organization`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 4 个 case、4 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 4 |
| Case | 4 |
| 用户输入 | 149 |
| Eval task | 4 |
| 断言 | 19 |
| LLM 调用 | 0 |
| Tool 调用 | 0 |
| 实际 token | 0 |
| Benchmark 评分耗时 | 0秒 |

- 数据语言：zh-CN
- Token 估算：本次没有可靠 token 记录，通常表示 fixture 或 no-LLM replay；真实模型实验需要用同规模 replay 重新估算。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| PKM 整理 | 检查 PKM 条目是否放到正确路径、保留关键信息并引用来源。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | PKM 条目是否保留关键事实、结论和下一步。 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | PKM 条目是否没有写入明确禁止的临时信息。 |
| PKM 整理 | 时效性 | `pkm_update_freshness` | PKM 条目是否反映最新输入或更新。 |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | PKM 条目是否保留期望来源 id。 |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | PKM 条目数量是否符合合并/拆分预期。 |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | PKM 条目路径是否包含期望目录或项目名。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| PKM 整理 | 19 | 19 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| PKM 整理 | 内容保真 | `pkm_content_preservation` | 4 | 4 | 100.0% | 1.000 |
| PKM 整理 | 幻觉控制 | `pkm_prohibited_content_absence` | 3 | 3 | 100.0% | - |
| PKM 整理 | 时效性 | `pkm_update_freshness` | 1 | 1 | 100.0% | - |
| PKM 整理 | 来源追溯 | `pkm_source_grounding` | 4 | 4 | 100.0% | - |
| PKM 整理 | 组织质量 | `pkm_merge_split_quality` | 3 | 3 | 100.0% | - |
| PKM 整理 | 路径分类 | `pkm_path_accuracy` | 4 | 4 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：0
- 工具调用次数：0
- Token 总量：0
- 单次 LLM 平均 token：0.000
- 平均延迟：0.000 ms
- P95 延迟：0.000 ms
- Benchmark 评分耗时：0秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-12-module-pkm-organization`
- 数据集：`evals/datasets/modules/pkm_organization`
- 观察适配器：`fixture`
- 场景样本数：4
- 评估任务数：4
- Benchmark 评分耗时：0秒
- 断言通过：19/19 （100.0%）

### 场景任务明细

#### PKM 整理

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_pkm_organization_001` | `task_pkm_organization_001` | 通过 | 0 |
| `module_pkm_meeting_002` | `task_pkm_meeting_002` | 通过 | 0 |
| `module_pkm_learning_003` | `task_pkm_learning_003` | 通过 | 0 |
| `module_pkm_travel_004` | `task_pkm_travel_004` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：4
- 输入条数：149
- Eval task 数：4
- Case family 分布：pkm_organization=4
- Task type 分布：pkm_organization=4

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 37 | 1 | 早上先看一下昨天广告账户的消耗，今天预算别太激进。<br>午饭别订海鲜，最近过敏又有点反复。 |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 37 | 1 | 早上先过一遍版本风险，今天别被零碎需求打散。<br>以后评审材料希望结论先行，细节放后面。 |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 37 | 1 | 早上先跑昨天的数据质量检查，看有没有埋点延迟。<br>以后异常分析先看样本量，再看比例变化。 |
| `module_u_004` | 高校老师 | 北京 | zh-CN | 1 | 38 | 1 | 早上先看学生发来的论文摘要，今天课前只能粗读。<br>公开课提醒要提前两天准备讲义。 |
