# Memex Agent Eval 实验报告

## 结论

- 断言全绿，但只能说明 grader/fixture 口径跑通；数据集需要先补多样性再升级为强 benchmark。
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力。
- 本次覆盖 2 个 case、24 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：53280；LLM 调用次数：24；工具调用次数：48。
- LLM Judge 断言数：24。
- 数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark：overall=0.600。
- 审计摘要：数据集在语言、persona设计和oracle一致性方面基础良好，但存在严重的模板化重复问题，特别是第二个案例几乎完全复制第一个案例的结构和内容，导致输入自然度和整体多样性不足，需大幅修改后方可用于可靠评估。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/retrieval_source_grounding`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 2 |
| Case | 2 |
| 用户输入 | 200 |
| Eval task | 24 |
| 断言 | 236 |
| LLM 调用 | 24 |
| LLM Judge 断言 | 24 |
| Tool 调用 | 48 |
| 实际 token | 53280 |
| Benchmark 评分耗时 | 7分05秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 53280 tokens；同规模复跑可先按 42624-63936 tokens 预留。

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
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | LLM judge 给出的 groundedness/completeness 综合分。 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 检索是否应用了期望的人物、时间、类型或项目过滤条件。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 检索问答 | 236 | 236 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 4 | 4 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 20 | 20 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 6 | 6 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 20 | 20 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | 24 | 24 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 18 | 18 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：24
- 工具调用次数：48
- Token 总量：53280
- 单次 LLM 平均 token：2220.000
- 平均延迟：380.000 ms
- P95 延迟：900.000 ms
- Benchmark 评分耗时：7分05秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-retrieval-source-grounding-llm-sample`
- 数据集：`evals/datasets/retrieval_source_grounding`
- 观察适配器：`fixture`
- 证据等级：fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力
- 本地完整日志：`evals/runs/2026-05-13-retrieval-source-grounding-llm-sample/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-retrieval-source-grounding-llm-sample/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-retrieval-source-grounding-llm-sample/outputs.jsonl`
- 场景样本数：2
- 评估任务数：24
- Benchmark 评分耗时：7分05秒
- 断言通过：236/236 （100.0%）
- LLM Judge：`anthropic` / `mimo-v2-pro` / max_tokens=4096
- LLM Judge 任务策略：`retrieval_and_super_agent_qa_unless_expected_llm_judge_false`
- LLM Judge 断言数：24

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

## 数据质量审计

- 总体分：0.600
- 语言一致性：1.000
- Persona 可信度：0.800
- 输入自然度：0.600
- Oracle 一致性：0.900
- 审计结论：数据集在语言、persona设计和oracle一致性方面基础良好，但存在严重的模板化重复问题，特别是第二个案例几乎完全复制第一个案例的结构和内容，导致输入自然度和整体多样性不足，需大幅修改后方可用于可靠评估。
- 覆盖备注：数据集专注于‘retrieval_source_grounding’家族，任务类型单一（均为retrieval_qa）。；覆盖了记忆、事件、笔记、PKM等多种来源类型，并测试了多源总结和未知问题处理。；两个案例结构高度平行，仅项目名、人名、城市等关键信息不同。

### 审计问题

- `retrieval_grounding_002` / high：案例002的输入流（input_stream）几乎是案例001的复制粘贴，仅替换了项目名（导出项目->北美站增长）和人名（Alex->Jason, Leo->Mina），缺乏独立生成的自然内容。；建议：为案例002重新生成一套独立、多样化的输入流，反映其跨境电商运营的特定场景和对话，避免简单替换关键词。
- `retrieval_grounding_001` / medium：输入流中后期（约从input_13开始）大量条目内容高度重复，反复强调‘不要写成长期偏好’、‘没有记录就说不确定’等规则，显得冗余且不自然。；建议：精简重复的规则性输入，或将其融入更具体、场景化的对话中，增加输入内容的多样性和信息密度。
- `retrieval_grounding_001` / low：部分eval_tasks的查询（如‘unknown_travel’, ‘unknown_medical’）在两个案例中完全相同，虽然测试了不确定性处理，但降低了任务多样性。；建议：为不同persona设计更贴合其职业或生活场景的‘未知问题’查询。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `retrieval_grounding_001` | 0.700 | 语言地道，persona合理，oracle一致性高。主要扣分点在于输入流中后期存在大量重复、模板化的规则强调，降低了自然度。 |
| `retrieval_grounding_002` | 0.500 | 语言和oracle一致性良好，但输入流与案例001高度雷同，存在严重的模板化复制问题，严重影响了数据的自然性和评估价值。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：2
- 输入条数：200
- Eval task 数：24
- Case family 分布：retrieval_source_grounding=2
- Task type 分布：retrieval_qa=24

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `retrieval_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Alex在腾讯会议讨论导出项目预算，重点看 CPA、ROAS 和退款率。<br>导出项目预算复盘 owner 先写Alex，后面问这个项目先找他对齐。 |
| `retrieval_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 100 | 12 | 5月8日下午三点和Jason在腾讯会议讨论北美站增长预算，重点看 CPA、ROAS 和退款率。<br>北美站增长预算复盘 owner 先写Jason，后面问这个项目先找他对齐。 |
