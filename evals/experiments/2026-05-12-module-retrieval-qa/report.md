# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/retrieval_qa`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 4 个 case、4 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 4 |
| Case | 4 |
| 用户输入 | 0 |
| Eval task | 4 |
| 断言 | 34 |
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
| 检索问答 | 检查查询时是否召回正确来源，并基于证据回答。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 证据不足时是否正确表达不确定，证据充分时是否不乱拒答。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | Top 1 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | Top 3 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | Top 5 结果中是否命中任一正确来源。 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 第一个正确来源排名的倒数，越高越好。 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | Top 5 中覆盖了多少期望来源。 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 证据充分时是否没有不必要地说不确定。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 答案引用的来源是否覆盖期望来源。 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 答案是否同时满足来源引用和无无证据断言。 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 检索是否应用了期望的人物、时间、类型或项目过滤条件。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 检索问答 | 34 | 34 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 1 | 1 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 3 | 3 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 4 | 4 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 4 | 4 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 3 | 3 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 2 | 2 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 2 | 2 | 100.0% | - |

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

- 运行 ID：`2026-05-12-module-retrieval-qa`
- 数据集：`evals/datasets/modules/retrieval_qa`
- 观察适配器：`fixture`
- 场景样本数：4
- 评估任务数：4
- Benchmark 评分耗时：0秒
- 断言通过：34/34 （100.0%）

### 场景任务明细

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_retrieval_qa_001` | `task_retrieval_qa_001` | 通过 | 0 |
| `module_retrieval_time_filter_002` | `task_retrieval_time_filter_002` | 通过 | 0 |
| `module_retrieval_abstain_003` | `task_retrieval_abstain_003` | 通过 | 0 |
| `module_retrieval_project_filter_004` | `task_retrieval_project_filter_004` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：4
- 输入条数：0
- Eval task 数：4
- Case family 分布：retrieval_qa=4
- Task type 分布：retrieval_qa=4

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 1 | 0 | 1 |  |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 0 | 1 |  |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 0 | 1 |  |
| `module_u_004` | 高校老师 | 北京 | zh-CN | 1 | 0 | 1 |  |
