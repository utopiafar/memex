# Memex Agent Eval 实验报告

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 12 个 case、144 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：319680；LLM 调用次数：144；工具调用次数：288。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.650。
- 审计摘要：数据集语言一致，oracle逻辑自洽，但核心问题在于严重的模板化和重复。不同persona的输入流、评估任务甚至部分世界事实高度雷同，仅进行机械替换，导致数据集多样性差，无法有效测试模型在不同真实场景下的泛化能力。作为小规模benchmark，其‘压力测试’价值有限。

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
| Benchmark 评分耗时 | 35秒 |

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
- Benchmark 评分耗时：35秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-retrieval-source-grounding`
- 数据集：`evals/datasets/retrieval_source_grounding`
- 观察适配器：`fixture`
- 本地完整日志：`evals/runs/2026-05-13-retrieval-source-grounding/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-retrieval-source-grounding/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-retrieval-source-grounding/outputs.jsonl`
- 场景样本数：12
- 评估任务数：144
- Benchmark 评分耗时：35秒
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
- 语言一致性：0.900
- Persona 可信度：0.700
- 输入自然度：0.400
- Oracle 一致性：0.800
- 审计结论：数据集语言一致，oracle逻辑自洽，但核心问题在于严重的模板化和重复。不同persona的输入流、评估任务甚至部分世界事实高度雷同，仅进行机械替换，导致数据集多样性差，无法有效测试模型在不同真实场景下的泛化能力。作为小规模benchmark，其‘压力测试’价值有限。
- 覆盖备注：任务类型单一，全部为`retrieval_qa`，缺乏多样性。；输入流条目数量多（每个case 100条），但内容在不同persona间高度重复，仅替换项目名、人名等少数变量。；所有case共享完全相同的`ground_truth_world.facts`（如饮食、会议提醒偏好），这在不同用户场景下不太自然。；评估任务（eval_tasks）结构一致，但查询和预期答案在不同case间也高度模板化。

### 审计问题

- `retrieval_grounding_001` / high：输入流（input_stream）存在大量模板化、重复性内容，不同case间仅替换少数词汇（如项目名、人名、城市），缺乏自然对话的多样性和随机性。；建议：大幅重写输入流，为不同persona设计更独特、符合其职业和生活习惯的对话内容，减少跨case的句式重复。
- `retrieval_grounding_001` / medium：`ground_truth_world.facts` 中的记忆条目（如饮食偏好、会议提醒偏好）在所有12个case中完全一致，这不符合不同用户应有不同个人偏好的现实。；建议：为不同persona定制不同的个人偏好记忆，增加数据集的真实性。
- `retrieval_grounding_001` / medium：部分职业与项目内容的搭配略显牵强。例如，律师（retrieval_u_004）讨论“法务合同库”预算时，关注点却是通用的“CPA、ROAS、退款率”，这更像是市场或运营指标，与法律合同管理的核心关注点（如合规风险、审核效率）不符。；建议：调整项目内容和评估指标，使其更贴合对应职业的典型工作场景和术语。
- `retrieval_grounding_002` / low：输入流中混杂了大量元指令（如“如果没有记录，回答我时直接说不确定，别猜”），这些更像是系统提示而非用户自然产生的记忆或笔记。；建议：将元指令从`input_stream`中分离，或将其转化为更自然的用户表达（例如，在对话中体现用户对AI回答方式的不满和纠正）。
- `retrieval_grounding_003` / medium：评估任务（eval_tasks）的查询和预期答案在不同case间高度相似，仅替换项目名和人名，导致测试覆盖的场景实质单一。；建议：设计更多样化、更贴近各职业独特场景的查询问题，而不仅仅是同一套问题的变量替换。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `retrieval_grounding_001` | 0.600 | 结构完整，oracle一致性好，但输入流模板化严重，persona习惯（如‘周三下午需求评审’）过于通用，缺乏独特性。 |
| `retrieval_grounding_002` | 0.600 | 与001 case结构高度相似，仅项目名、人名、城市和个别指标（退款率）不同，输入流重复度高，多样性不足。 |
| `retrieval_grounding_003` | 0.600 | 数据分析师persona的‘保留英文metric id’偏好（体现在‘retry rate’）是合理细节，但整体仍受困于跨case的模板化问题。 |
| `retrieval_grounding_004` | 0.600 | 律师persona的‘重要结论要列来源’偏好是好的设计，但项目内容（法务合同库看CPA/ROAS）与职业核心场景匹配度一般。 |
| `retrieval_grounding_005` | 0.600 | 财务主管persona的‘数字先给口径’偏好贴合职业，但输入流和任务与其他case雷同，削弱了评估价值。 |
| `retrieval_grounding_006` | 0.600 | 内容运营persona的‘复盘保留素材来源’偏好合理，但‘小红书活动’看CPA/ROAS的设定与案例001-005逻辑完全一致，缺乏场景特异性。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：1200
- Eval task 数：144
- Case family 分布：retrieval_source_grounding=12
- Task type 分布：retrieval_qa=144

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `retrieval_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Alex在腾讯会议讨论导出项目预算，重点看 CPA、ROAS 和退款率。<br>导出项目预算复盘 owner 先写Alex，后面问这个项目先找他对齐。 |
| `retrieval_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Jason在腾讯会议讨论北美站增长预算，重点看 CPA、ROAS 和退款率。<br>北美站增长预算复盘 owner 先写Jason，后面问这个项目先找他对齐。 |
| `retrieval_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Grace在腾讯会议讨论Memex eval预算，重点看 CPA、ROAS 和退款率。<br>Memex eval预算复盘 owner 先写Grace，后面问这个项目先找他对齐。 |
| `retrieval_u_004` | 律师 | 广州 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Annie在腾讯会议讨论法务合同库预算，重点看 CPA、ROAS 和退款率。<br>法务合同库预算复盘 owner 先写Annie，后面问这个项目先找他对齐。 |
| `retrieval_u_005` | 财务主管 | 成都 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Mina在腾讯会议讨论预算月结预算，重点看 CPA、ROAS 和退款率。<br>预算月结预算复盘 owner 先写Mina，后面问这个项目先找他对齐。 |
| `retrieval_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Grace在腾讯会议讨论小红书活动预算，重点看 CPA、ROAS 和退款率。<br>小红书活动预算复盘 owner 先写Grace，后面问这个项目先找他对齐。 |
| `retrieval_u_007` | 独立开发者 | 厦门 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和小陈在腾讯会议讨论个人工具订阅预算，重点看 CPA、ROAS 和退款率。<br>个人工具订阅预算复盘 owner 先写小陈，后面问这个项目先找他对齐。 |
| `retrieval_u_008` | 老师 | 北京 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Ada在腾讯会议讨论公开课改版预算，重点看 CPA、ROAS 和退款率。<br>公开课改版预算复盘 owner 先写Ada，后面问这个项目先找他对齐。 |
| `retrieval_u_009` | 医生 | 南京 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和周医生在腾讯会议讨论门诊随访系统预算，重点看 CPA、ROAS 和退款率。<br>门诊随访系统预算复盘 owner 先写周医生，后面问这个项目先找他对齐。 |
| `retrieval_u_010` | HRBP | 武汉 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Sophie在腾讯会议讨论绩效校准预算，重点看 CPA、ROAS 和退款率。<br>绩效校准预算复盘 owner 先写Sophie，后面问这个项目先找他对齐。 |
| `retrieval_u_011` | 设计师 | 长沙 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Nora在腾讯会议讨论会员页改版预算，重点看 CPA、ROAS 和退款率。<br>会员页改版预算复盘 owner 先写Nora，后面问这个项目先找他对齐。 |
| `retrieval_u_012` | 创业者 | 青岛 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Ethan在腾讯会议讨论B 端试点预算，重点看 CPA、ROAS 和退款率。<br>B 端试点预算复盘 owner 先写Ethan，后面问这个项目先找他对齐。 |
