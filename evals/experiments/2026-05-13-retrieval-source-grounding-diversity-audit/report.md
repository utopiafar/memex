# Memex Agent Eval 实验报告

## 结论

- 断言全绿，但只能说明 grader/fixture 口径跑通；数据集需要先补多样性再升级为强 benchmark。
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力。
- 本次覆盖 12 个 case、144 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：319680；LLM 调用次数：144；工具调用次数：288。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.650。
- 审计摘要：数据集在语言、persona多样性和oracle一致性上表现良好，但存在致命的模板化问题。输入流和ground_truth结构高度重复，像同一套模具填充不同领域关键词生成，严重损害了数据的自然度和作为评估基准的有效性。需要重构以增加多样性和真实性。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/retrieval_source_grounding`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 12 |
| Case | 12 |
| 用户输入 | 1200 |
| Eval task | 144 |
| 断言 | 1272 |
| LLM 调用 | 144 |
| Tool 调用 | 288 |
| 实际 token | 319680 |
| Benchmark 评分耗时 | 37秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 319680 tokens；同规模复跑可先按 255744-383616 tokens 预留。

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
| 检索问答 | 1272 | 1272 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 24 | 24 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 120 | 120 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 36 | 36 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 144 | 144 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 120 | 120 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 108 | 108 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：144
- 工具调用次数：288
- Token 总量：319680
- 单次 LLM 平均 token：2220.000
- 平均延迟：380.000 ms
- P95 延迟：900.000 ms
- Benchmark 评分耗时：37秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-retrieval-source-grounding-diversity-audit`
- 数据集：`evals/datasets/retrieval_source_grounding`
- 观察适配器：`fixture`
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力
- 本地完整日志：`evals/runs/2026-05-13-retrieval-source-grounding-diversity-audit/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-retrieval-source-grounding-diversity-audit/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-retrieval-source-grounding-diversity-audit/outputs.jsonl`
- 场景样本数：12
- 评估任务数：144
- Benchmark 评分耗时：37秒
- 断言通过：1272/1272 （100.0%）

### 场景任务明细

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `retrieval_grounding_001` | `retrieval_grounding_001_budget_when` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_diet` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_project_risks` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_family_event` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_design_review` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_001` | `retrieval_grounding_001_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_budget_when` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_diet` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_project_risks` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_family_event` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_design_review` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_002` | `retrieval_grounding_002_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_budget_when` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_diet` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_project_risks` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_family_event` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_design_review` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_003` | `retrieval_grounding_003_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_budget_when` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_diet` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_project_risks` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_family_event` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_design_review` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_004` | `retrieval_grounding_004_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_budget_when` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_diet` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_project_risks` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_family_event` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_design_review` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_005` | `retrieval_grounding_005_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_budget_when` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_diet` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_project_risks` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_family_event` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_design_review` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_006` | `retrieval_grounding_006_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_budget_when` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_diet` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_project_risks` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_family_event` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_design_review` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_007` | `retrieval_grounding_007_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_budget_when` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_diet` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_project_risks` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_family_event` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_design_review` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_008` | `retrieval_grounding_008_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_budget_when` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_diet` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_project_risks` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_family_event` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_design_review` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_009` | `retrieval_grounding_009_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_budget_when` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_diet` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_project_risks` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_family_event` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_design_review` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_010` | `retrieval_grounding_010_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_budget_when` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_diet` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_project_risks` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_family_event` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_design_review` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_011` | `retrieval_grounding_011_unknown_medical` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_budget_when` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_meeting_reminder` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_diet` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_coffee_latest` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_project_risks` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_customer_feedback` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_family_event` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_metric_anomaly` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_design_review` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_multi_source_summary` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_unknown_travel` | 通过 | 0 |
| `retrieval_grounding_012` | `retrieval_grounding_012_unknown_medical` | 通过 | 0 |

## 数据质量审计

- 总体分：0.650
- 语言一致性：1.000
- Persona 可信度：0.800
- 输入自然度：0.400
- Oracle 一致性：0.900
- 审计结论：数据集在语言、persona多样性和oracle一致性上表现良好，但存在致命的模板化问题。输入流和ground_truth结构高度重复，像同一套模具填充不同领域关键词生成，严重损害了数据的自然度和作为评估基准的有效性。需要重构以增加多样性和真实性。
- 覆盖备注：覆盖了12种不同职业和城市，体现了领域差异。；所有任务均为检索问答，类型单一。；输入流长度充足（100条），但内容模板化严重。

### 审计问题

- `all` / high：数据集存在严重的模板化和结构重复问题。；建议：打破固定模板，为不同persona设计差异化的输入流结构、ground_truth构成和eval_task模式。
- `all` / medium：输入流中从第13条开始，大量内容是高度同质化的‘碎碎念’，仅替换项目名和关键词列表，缺乏真实对话的多样性和随机性。；建议：大幅减少或重构这些模板化输入，增加更多反映真实工作场景的、非结构化的、带有噪音的对话或笔记。
- `all` / medium：ground_truth_world的结构（4 facts, 3 events, 3 notes, 2 pkm）在所有case中完全一致，过于规整，降低了模拟真实记忆库的复杂性。；建议：引入不同数量和类型的记忆条目，模拟更真实、不均衡的个人知识库状态。
- `all` / low：eval_tasks的12个问题类型和结构在所有case中完全一致，可能导致评估过于机械。；建议：为不同persona设计更贴合其领域特点的、多样化的评估任务，而不仅仅是替换项目名和指标名。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `retrieval_grounding_001` | 0.700 | persona和领域细节（产品经理，导出项目）可信，eval_tasks与ground_truth一致。但输入流后半段模板化严重，自然度扣分。 |
| `retrieval_grounding_003` | 0.700 | 数据分析师的领域术语（retry rate, p95 latency）准确。问题同case_001，输入流存在大量模板化‘碎碎念’。 |
| `retrieval_grounding_009` | 0.700 | 医生的persona和医疗相关约束（区分记录和建议）设计得好。但整体结构与其他case无异，模板化问题突出。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：1200
- Eval task 数：144
- Case family 分布：retrieval_source_grounding=12
- Task type 分布：retrieval_qa=144

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `retrieval_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 100 | 12 | 刚开完会脑子有点乱，但重点是： 5月8日下午三点，和Alex在腾讯会议过了一遍导出项目预算；先别写成大结论，会上主要盯CPA、ROAS、退款率。<br>补一条，不然我后面肯定忘：导出项目预算复盘 owner 暂时按Alex，问这个项目先找 TA 对齐。结论先行，但证据和来源不要丢。 |
| `retrieval_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 100 | 12 | 先记个不太工整的版本： 5月8日下午三点，和Jason在腾讯会议过了一遍北美站增长预算；先别写成大结论，会上主要盯广告花费、ROAS、退款率。<br>补一条，不然我后面肯定忘：北美站增长预算复盘 owner 暂时按Jason，问这个项目先找 TA 对齐。顺带看一下广告组和物流口径，别把退款率和投诉率混了。 |
| `retrieval_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 100 | 12 | 先记个不太工整的版本： 5月8日下午三点，和Grace在腾讯会议过了一遍Memex eval预算；先别写成大结论，会上主要盯样本覆盖率、retry rate、p95 latency。<br>补一条，不然我后面肯定忘：Memex eval预算复盘 owner 暂时按Grace，问这个项目先找 TA 对齐。如果后面写分析，metric id 保留英文，口径写清楚。 |
| `retrieval_u_004` | 律师 | 广州 | zh-CN | 1 | 100 | 12 | 刚开完会脑子有点乱，但重点是： 5月8日下午三点，和Annie在腾讯会议过了一遍法务合同库预算；先别写成大结论，会上主要盯合同风险数、审批时长、条款争议。<br>补一条，不然我后面肯定忘：法务合同库预算复盘 owner 暂时按Annie，问这个项目先找 TA 对齐。风险结论必须列来源，别只写一句“需要注意”。 |
| `retrieval_u_005` | 财务主管 | 成都 | zh-CN | 1 | 100 | 12 | 嗯，这条可能以后会问到： 5月8日下午三点，和Mina在腾讯会议过了一遍预算月结预算；先别写成大结论，会上主要盯预算差异率、付款延迟、发票异常。<br>补一条，不然我后面肯定忘：预算月结预算复盘 owner 暂时按Mina，问这个项目先找 TA 对齐。数字先给口径，再给差异，不然月结会对不上。 |
| `retrieval_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 100 | 12 | 顺手记一下，别嫌碎： 5月8日下午三点，和Grace在腾讯会议过了一遍小红书活动预算；先别写成大结论，会上主要盯互动率、素材消耗、转化评论。<br>补一条，不然我后面肯定忘：小红书活动预算复盘 owner 暂时按Grace，问这个项目先找 TA 对齐。素材来源和投放反馈分开放，别混进一个结论。 |
| `retrieval_u_007` | 独立开发者 | 厦门 | zh-CN | 1 | 100 | 12 | 顺手记一下，别嫌碎： 5月8日下午三点，和小陈在腾讯会议过了一遍个人工具订阅预算；先别写成大结论，会上主要盯激活率、退款工单、订阅续费。<br>补一条，不然我后面肯定忘：个人工具订阅预算复盘 owner 暂时按小陈，问这个项目先找 TA 对齐。少写空话，最好直接能变成 backlog 或 changelog。 |
| `retrieval_u_008` | 老师 | 北京 | zh-CN | 1 | 100 | 12 | 嗯，这条可能以后会问到： 5月8日下午三点，和Ada在腾讯会议过了一遍公开课改版预算；先别写成大结论，会上主要盯完课率、试听转化、作业提交率。<br>补一条，不然我后面肯定忘：公开课改版预算复盘 owner 暂时按Ada，问这个项目先找 TA 对齐。如果涉及课程反馈，别超过三条重点。 |
| `retrieval_u_009` | 医生 | 南京 | zh-CN | 1 | 100 | 12 | 刚开完会脑子有点乱，但重点是： 5月8日下午三点，和周医生在腾讯会议过了一遍门诊随访系统预算；先别写成大结论，会上主要盯随访完成率、预约爽约率、问卷回收。<br>补一条，不然我后面肯定忘：门诊随访系统预算复盘 owner 暂时按周医生，问这个项目先找 TA 对齐。医疗相关只能区分记录和建议，别自动下结论。 |
| `retrieval_u_010` | HRBP | 武汉 | zh-CN | 1 | 100 | 12 | 嗯，这条可能以后会问到： 5月8日下午三点，和Sophie在腾讯会议过了一遍绩效校准预算；先别写成大结论，会上主要盯校准争议数、面评完成率、敏感反馈。<br>补一条，不然我后面肯定忘：绩效校准预算复盘 owner 暂时按Sophie，问这个项目先找 TA 对齐。敏感信息少写细节，只保留必要上下文。 |
| `retrieval_u_011` | 设计师 | 长沙 | zh-CN | 1 | 100 | 12 | 刚开完会脑子有点乱，但重点是： 5月8日下午三点，和Nora在腾讯会议过了一遍会员页改版预算；先别写成大结论，会上主要盯点击率、首屏停留、转化路径。<br>补一条，不然我后面肯定忘：会员页改版预算复盘 owner 暂时按Nora，问这个项目先找 TA 对齐。视觉反馈最好带截图来源，不然之后对不上版本。 |
| `retrieval_u_012` | 创业者 | 青岛 | zh-CN | 1 | 100 | 12 | 顺手记一下，别嫌碎： 5月8日下午三点，和Ethan在腾讯会议过了一遍B 端试点预算；先别写成大结论，会上主要盯试点转化率、客单价、回款周期。<br>补一条，不然我后面肯定忘：B 端试点预算复盘 owner 暂时按Ethan，问这个项目先找 TA 对齐。商务复盘先列风险和下一步，别写成鸡汤。 |
