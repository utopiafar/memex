# Memex Agent Eval 实验报告

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 12 个 case、144 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：319680；LLM 调用次数：144；工具调用次数：288。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/retrieval_source_grounding`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 12 |
| Case | 12 |
| 用户输入 | 576 |
| Eval task | 144 |
| 断言 | 1272 |
| LLM 调用 | 144 |
| Tool 调用 | 288 |
| 实际 token | 319680 |
| Benchmark 评分耗时 | 26秒 |

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
- Benchmark 评分耗时：26秒

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
- Benchmark 评分耗时：26秒
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
- Persona 可信度：0.700
- 输入自然度：0.400
- Oracle 一致性：0.900
- 审计结论：数据集在语言一致性和基础结构（oracle一致性）上表现良好，但存在致命的模板化问题。所有persona的输入内容、偏好、习惯高度重复，导致输入自然性和persona可信度大打折扣。这更像是一个‘填空式’生成的数据集，而非反映真实多样用户场景的合成数据。作为小规模benchmark，其评估有效性存疑，必须先解决内容多样性和自然性问题。
- 覆盖备注：覆盖了12种不同职业和城市，结构完整。；所有案例均属于同一任务家族(retrieval_source_grounding)，任务类型单一(retrieval_qa)。；每个案例的输入流(input_stream)和评估任务(eval_tasks)数量固定，模式高度一致。

### 审计问题

- `all` / high：严重的模板化与内容重复；建议：打破模板，为不同persona设计符合其职业、城市、生活习惯的独特输入内容、事实(facts)和笔记(notes)。避免所有persona共享完全相同的偏好、习惯和通用输入语句。
- `all` / medium：文化/职业自然性不足；建议：调整persona的偏好和习惯以更贴合其职业与文化背景。例如，医生的饮食偏好可能更关注健康，律师的习惯可能与案件管理相关，而非所有人均有‘不要海鲜、少糖’等相同偏好。
- `all` / medium：输入流(input_stream)缺乏多样性；建议：输入流中大量条目是通用规则（如‘不要把今天想喝奶茶写成长期饮食偏好’），而非具体、自然的用户记录。应增加更多反映真实工作流和生活的具体事件、笔记和记忆。
- `all` / low：评估任务(eval_tasks)同质化；建议：所有案例的12个评估任务结构完全相同（10个检索，2个未知）。应根据persona和项目特点设计不同的、更具针对性的查询和评估点。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `retrieval_grounding_001` | 0.700 | 结构完整，ground_truth、input、eval_tasks之间一致性高。但作为‘产品经理’，其输入流中大量通用规则（如饮食、咖啡偏好）与工作场景关联弱，显得模板化。 |
| `retrieval_grounding_002` | 0.600 | 与case_001高度相似，仅替换项目名(北美站增长)、人名(Jason)和部分细节(带保温杯和降压药)。persona(跨境电商运营)的独特性未在内容中体现，重复性问题严重。 |
| `retrieval_grounding_003` | 0.600 | 继续重复模板。‘数据分析师’的persona本应有更多关于数据指标、分析方法的独特输入，但实际内容与其它case雷同。 |
| `retrieval_grounding_009` | 0.650 | persona为‘医生’，但输入流中缺乏医疗相关的工作内容（如病例、诊断、会议），仍充斥通用项目管理和个人偏好规则，职业可信度低。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：576
- Eval task 数：144
- Case family 分布：retrieval_source_grounding=12
- Task type 分布：retrieval_qa=144

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `retrieval_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Alex在腾讯会议讨论导出项目预算，重点看 CPA、ROAS 和退款率。<br>导出项目预算复盘 owner 先写Alex，后面问这个项目先找他对齐。 |
| `retrieval_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Jason在腾讯会议讨论北美站增长预算，重点看 CPA、ROAS 和退款率。<br>北美站增长预算复盘 owner 先写Jason，后面问这个项目先找他对齐。 |
| `retrieval_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Grace在腾讯会议讨论Memex eval预算，重点看 CPA、ROAS 和退款率。<br>Memex eval预算复盘 owner 先写Grace，后面问这个项目先找他对齐。 |
| `retrieval_u_004` | 律师 | 广州 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Annie在腾讯会议讨论法务合同库预算，重点看 CPA、ROAS 和退款率。<br>法务合同库预算复盘 owner 先写Annie，后面问这个项目先找他对齐。 |
| `retrieval_u_005` | 财务主管 | 成都 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Mina在腾讯会议讨论预算月结预算，重点看 CPA、ROAS 和退款率。<br>预算月结预算复盘 owner 先写Mina，后面问这个项目先找他对齐。 |
| `retrieval_u_006` | 内容运营 | 苏州 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Grace在腾讯会议讨论小红书活动预算，重点看 CPA、ROAS 和退款率。<br>小红书活动预算复盘 owner 先写Grace，后面问这个项目先找他对齐。 |
| `retrieval_u_007` | 独立开发者 | 厦门 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和小陈在腾讯会议讨论个人工具订阅预算，重点看 CPA、ROAS 和退款率。<br>个人工具订阅预算复盘 owner 先写小陈，后面问这个项目先找他对齐。 |
| `retrieval_u_008` | 老师 | 北京 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Ada在腾讯会议讨论公开课改版预算，重点看 CPA、ROAS 和退款率。<br>公开课改版预算复盘 owner 先写Ada，后面问这个项目先找他对齐。 |
| `retrieval_u_009` | 医生 | 南京 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和周医生在腾讯会议讨论门诊随访系统预算，重点看 CPA、ROAS 和退款率。<br>门诊随访系统预算复盘 owner 先写周医生，后面问这个项目先找他对齐。 |
| `retrieval_u_010` | HRBP | 武汉 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Sophie在腾讯会议讨论绩效校准预算，重点看 CPA、ROAS 和退款率。<br>绩效校准预算复盘 owner 先写Sophie，后面问这个项目先找他对齐。 |
| `retrieval_u_011` | 设计师 | 长沙 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Nora在腾讯会议讨论会员页改版预算，重点看 CPA、ROAS 和退款率。<br>会员页改版预算复盘 owner 先写Nora，后面问这个项目先找他对齐。 |
| `retrieval_u_012` | 创业者 | 青岛 | zh-CN | 1 | 48 | 12 | 5月8日下午三点和Ethan在腾讯会议讨论B 端试点预算，重点看 CPA、ROAS 和退款率。<br>B 端试点预算复盘 owner 先写Ethan，后面问这个项目先找他对齐。 |
