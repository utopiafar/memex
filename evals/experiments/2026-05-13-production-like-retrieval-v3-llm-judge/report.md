# Memex Agent Eval 实验报告

## 结论

- 合成 fixture 整体通过，适合作为小规模回归基线。
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay。
- 本次覆盖 24 个 case、94 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：180165；LLM 调用次数：94；工具调用次数：330。
- LLM Judge 断言数：94。
- 数据质量审计通过：overall=0.900。
- 审计摘要：数据集整体质量高。语言稳定为中文（zh-CN），24种职业persona设定可信且体现了领域差异，输入形式多样、自然度较好。ground_truth_world、input_stream与eval_tasks之间逻辑一致，预期答案可从给定信息中合理推出，且通过‘不确定’查询有效防止了oracle泄漏。适合作为小规模benchmark数据。
- 人工复核备注：v3 比 v2 规模扩大约 2 倍，审计分保持 0.900，但 input naturalness 从 0.900 降到 0.850，说明继续扩量会带来领域深度和输入自然度压力。audit 仍把拒答覆盖概括成“每个 case 均包含”，但实际为 23 个拒答任务 / 24 个 case；规则指标和任务表是准的，LLM audit summary 需人工复核。

## 实验问题与背景

- 本次要回答的问题：在 v2 基础上把生产贴近 Retrieval QA 扩到 24 个用户、150 条输入、94 个任务后，规则指标、LLM groundedness judge、数据审计和报告结构是否还能稳定。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 本轮专门复用上一轮问题做修复：慢病随访语音噪声改得更自然，招聘 seed case 加强 Lin/Chen 的 filter 区分，并在 fixture smoke 中验证 expected 与 observed 的 filter 同步。
- 评估仍是 retrieval-only fixture；它证明数据与裁判口径更成熟，不证明真实 Memex Agent 在同等规模下已经可靠。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/production_like_retrieval_v3`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 24 |
| Case | 24 |
| 用户输入 | 150 |
| Eval task | 94 |
| 断言 | 873 |
| LLM 调用 | 94 |
| LLM Judge 断言 | 94 |
| Tool 调用 | 330 |
| 实际 token | 180165 |
| Benchmark 评分耗时 | 29分03秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 180165 tokens；同规模复跑可先按 144132-216198 tokens 预留。

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
| 检索问答 | 873 | 873 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 23 | 23 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 71 | 71 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 23 | 23 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 94 | 94 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 71 | 71 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | 94 | 94 | 100.0% | 0.997 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 71 | 71 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：94
- 工具调用次数：330
- Token 总量：180165
- 单次 LLM 平均 token：1916.649
- 平均延迟：302.292 ms
- P95 延迟：990.000 ms
- Benchmark 评分耗时：29分03秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-production-like-retrieval-v3-llm-judge`
- 数据集：`evals/datasets/production_like_retrieval_v3`
- 观察适配器：`fixture`
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay
- 本地完整日志：`evals/runs/2026-05-13-production-like-retrieval-v3-llm-judge/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-production-like-retrieval-v3-llm-judge/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-production-like-retrieval-v3-llm-judge/outputs.jsonl`
- 场景样本数：24
- 评估任务数：94
- Benchmark 评分耗时：29分03秒
- 断言通过：873/873 （100.0%）
- LLM Judge：`anthropic` / `mimo-v2-pro` / max_tokens=4096
- LLM Judge 任务策略：`retrieval_and_super_agent_qa_unless_expected_llm_judge_false`
- LLM Judge 断言数：94

### 场景任务明细

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `production_retrieval_v3_seed_growth_product` | `gp_q_ab_metrics` | 通过 | 0 |
| `production_retrieval_v3_seed_growth_product` | `gp_q_decision` | 通过 | 0 |
| `production_retrieval_v3_seed_growth_product` | `gp_q_old_record_boundary` | 通过 | 0 |
| `production_retrieval_v3_seed_growth_product` | `gp_q_unknown_budget` | 通过 | 0 |
| `production_retrieval_v3_cross_border_ecommerce` | `cb_q_ads_by_site` | 通过 | 0 |
| `production_retrieval_v3_cross_border_ecommerce` | `cb_q_forwarder` | 通过 | 0 |
| `production_retrieval_v3_cross_border_ecommerce` | `cb_q_plan` | 通过 | 0 |
| `production_retrieval_v3_cross_border_ecommerce` | `cb_q_unknown_tariff` | 通过 | 0 |
| `production_retrieval_v3_seed_chronic_care` | `cc_q_feedback` | 通过 | 0 |
| `production_retrieval_v3_seed_chronic_care` | `cc_q_review` | 通过 | 0 |
| `production_retrieval_v3_seed_chronic_care` | `cc_q_next_action` | 通过 | 0 |
| `production_retrieval_v3_seed_chronic_care` | `cc_q_unknown_dose` | 通过 | 0 |
| `production_retrieval_v3_robotics_lab` | `rb_q_test_result` | 通过 | 0 |
| `production_retrieval_v3_robotics_lab` | `rb_q_failures` | 通过 | 0 |
| `production_retrieval_v3_robotics_lab` | `rb_q_calibration` | 通过 | 0 |
| `production_retrieval_v3_robotics_lab` | `rb_q_unknown_root_cause` | 通过 | 0 |
| `production_retrieval_v3_seed_finance_fpna` | `fin_q_latest_forecast` | 通过 | 0 |
| `production_retrieval_v3_seed_finance_fpna` | `fin_q_board` | 通过 | 0 |
| `production_retrieval_v3_seed_finance_fpna` | `fin_q_model_assumption` | 通过 | 0 |
| `production_retrieval_v3_seed_finance_fpna` | `fin_q_unknown_cash` | 通过 | 0 |
| `production_retrieval_v3_climate_analyst` | `cl_q_sensor` | 通过 | 0 |
| `production_retrieval_v3_climate_analyst` | `cl_q_briefing` | 通过 | 0 |
| `production_retrieval_v3_climate_analyst` | `cl_q_threshold` | 通过 | 0 |
| `production_retrieval_v3_climate_analyst` | `cl_q_unknown_alert` | 通过 | 0 |
| `production_retrieval_v3_seed_ops_warehouse` | `ops_q_incident` | 通过 | 0 |
| `production_retrieval_v3_seed_ops_warehouse` | `ops_q_runbook` | 通过 | 0 |
| `production_retrieval_v3_seed_ops_warehouse` | `ops_q_style` | 通过 | 0 |
| `production_retrieval_v3_seed_ops_warehouse` | `ops_q_unknown_compensation` | 通过 | 0 |
| `production_retrieval_v3_museum_curator` | `ms_q_loan` | 通过 | 0 |
| `production_retrieval_v3_museum_curator` | `ms_q_condition` | 通过 | 0 |
| `production_retrieval_v3_museum_curator` | `ms_q_layout` | 通过 | 0 |
| `production_retrieval_v3_museum_curator` | `ms_q_unknown_crate` | 通过 | 0 |
| `production_retrieval_v3_seed_ux_research` | `ux_q_findings` | 通过 | 0 |
| `production_retrieval_v3_seed_ux_research` | `ux_q_synthesis` | 通过 | 0 |
| `production_retrieval_v3_seed_ux_research` | `ux_q_rule` | 通过 | 0 |
| `production_retrieval_v3_seed_ux_research` | `ux_q_unknown_nps` | 通过 | 0 |
| `production_retrieval_v3_podcast_producer` | `pc_q_recording` | 通过 | 0 |
| `production_retrieval_v3_podcast_producer` | `pc_q_edit_points` | 通过 | 0 |
| `production_retrieval_v3_podcast_producer` | `pc_q_publish` | 通过 | 0 |
| `production_retrieval_v3_podcast_producer` | `pc_q_unknown_sponsor` | 通过 | 0 |
| `production_retrieval_v3_seed_investigative_editor` | `ed_q_verified_claims` | 通过 | 0 |
| `production_retrieval_v3_seed_investigative_editor` | `ed_q_interview` | 通过 | 0 |
| `production_retrieval_v3_seed_investigative_editor` | `ed_q_outline` | 通过 | 0 |
| `production_retrieval_v3_seed_investigative_editor` | `ed_q_rumor_boundary` | 通过 | 0 |
| `production_retrieval_v3_patent_agent` | `pt_q_invention` | 通过 | 0 |
| `production_retrieval_v3_patent_agent` | `pt_q_prior_art` | 通过 | 0 |
| `production_retrieval_v3_patent_agent` | `pt_q_claim` | 通过 | 0 |
| `production_retrieval_v3_patent_agent` | `pt_q_unknown_allowance` | 通过 | 0 |
| `production_retrieval_v3_seed_restaurant_owner` | `rs_q_latest_quote` | 通过 | 0 |
| `production_retrieval_v3_seed_restaurant_owner` | `rs_q_private_dinner` | 通过 | 0 |
| `production_retrieval_v3_seed_restaurant_owner` | `rs_q_menu` | 通过 | 0 |
| `production_retrieval_v3_seed_restaurant_owner` | `rs_q_unknown_wine` | 通过 | 0 |
| `production_retrieval_v3_counselor_ops` | `co_q_supervision` | 通过 | 0 |
| `production_retrieval_v3_counselor_ops` | `co_q_feedback` | 通过 | 0 |
| `production_retrieval_v3_counselor_ops` | `co_q_process` | 通过 | 0 |
| `production_retrieval_v3_counselor_ops` | `co_q_unknown_client` | 通过 | 0 |
| `production_retrieval_v3_seed_construction_architect` | `ar_q_site_issues` | 通过 | 0 |
| `production_retrieval_v3_seed_construction_architect` | `ar_q_rectification` | 通过 | 0 |
| `production_retrieval_v3_seed_construction_architect` | `ar_q_unknown_permit` | 通过 | 0 |
| `production_retrieval_v3_travel_planner` | `tv_q_confirmed` | 通过 | 0 |
| `production_retrieval_v3_travel_planner` | `tv_q_constraints` | 通过 | 0 |
| `production_retrieval_v3_travel_planner` | `tv_q_unknown_hotel` | 通过 | 0 |
| `production_retrieval_v3_seed_game_design` | `gd_q_playtest` | 通过 | 0 |
| `production_retrieval_v3_seed_game_design` | `gd_q_bugbash` | 通过 | 0 |
| `production_retrieval_v3_seed_game_design` | `gd_q_balance` | 通过 | 0 |
| `production_retrieval_v3_seed_game_design` | `gd_q_unknown_store` | 通过 | 0 |
| `production_retrieval_v3_open_source_maintainer` | `os_q_release_scope` | 通过 | 0 |
| `production_retrieval_v3_open_source_maintainer` | `os_q_release_checks` | 通过 | 0 |
| `production_retrieval_v3_open_source_maintainer` | `os_q_security_boundary` | 通过 | 0 |
| `production_retrieval_v3_open_source_maintainer` | `os_q_unknown_cve` | 通过 | 0 |
| `production_retrieval_v3_seed_technical_recruiting` | `hr_q_lin_feedback` | 通过 | 0 |
| `production_retrieval_v3_seed_technical_recruiting` | `hr_q_scorecard` | 通过 | 0 |
| `production_retrieval_v3_seed_technical_recruiting` | `hr_q_privacy` | 通过 | 0 |
| `production_retrieval_v3_seed_technical_recruiting` | `hr_q_unknown_salary` | 通过 | 0 |
| `production_retrieval_v3_farm_coop_manager` | `fm_q_observation` | 通过 | 0 |
| `production_retrieval_v3_farm_coop_manager` | `fm_q_visit` | 通过 | 0 |
| `production_retrieval_v3_farm_coop_manager` | `fm_q_action` | 通过 | 0 |
| `production_retrieval_v3_farm_coop_manager` | `fm_q_unknown_pesticide` | 通过 | 0 |
| `production_retrieval_v3_seed_family_caregiver` | `cg_q_checkup` | 通过 | 0 |
| `production_retrieval_v3_seed_family_caregiver` | `cg_q_school_feedback` | 通过 | 0 |
| `production_retrieval_v3_seed_family_caregiver` | `cg_q_allergy` | 通过 | 0 |
| `production_retrieval_v3_seed_family_caregiver` | `cg_q_unknown_insurance` | 通过 | 0 |
| `production_retrieval_v3_insurance_adjuster` | `ia_q_damage` | 通过 | 0 |
| `production_retrieval_v3_insurance_adjuster` | `ia_q_followup` | 通过 | 0 |
| `production_retrieval_v3_insurance_adjuster` | `ia_q_boundary` | 通过 | 0 |
| `production_retrieval_v3_insurance_adjuster` | `ia_q_unknown_fraud` | 通过 | 0 |
| `production_retrieval_v3_seed_sre_incident` | `sre_q_incident` | 通过 | 0 |
| `production_retrieval_v3_seed_sre_incident` | `sre_q_runbook` | 通过 | 0 |
| `production_retrieval_v3_seed_sre_incident` | `sre_q_secret_boundary` | 通过 | 0 |
| `production_retrieval_v3_seed_sre_incident` | `sre_q_unknown_api_key` | 通过 | 0 |
| `production_retrieval_v3_university_lab_manager` | `ul_q_inventory` | 通过 | 0 |
| `production_retrieval_v3_university_lab_manager` | `ul_q_hplc` | 通过 | 0 |
| `production_retrieval_v3_university_lab_manager` | `ul_q_purchase` | 通过 | 0 |
| `production_retrieval_v3_university_lab_manager` | `ul_q_unknown_queue` | 通过 | 0 |

## 数据质量审计

- 总体分：0.900
- 语言一致性：0.950
- Persona 可信度：0.900
- 输入自然度：0.850
- Oracle 一致性：0.900
- 审计结论：数据集整体质量高。语言稳定为中文（zh-CN），24种职业persona设定可信且体现了领域差异，输入形式多样、自然度较好。ground_truth_world、input_stream与eval_tasks之间逻辑一致，预期答案可从给定信息中合理推出，且通过‘不确定’查询有效防止了oracle泄漏。适合作为小规模benchmark数据。
- 覆盖备注：所有 case 语言均为 zh-CN。；抽样中观察到 persona 覆盖了 24 种不同职业，城市分布合理。；多数 case 的输入包含会议笔记、语音转录、日历提醒等多种形式，文风多样。；所有 eval_tasks 类型均为 retrieval_qa，且每个 case 均包含一个要求模型‘不确定’时应 abstain 的边界测试任务。；抽样中观察到 ground_truth_world、input_stream 与 eval_tasks.expected 之间逻辑一致，预期答案可从隐藏真相或输入中推出。
- 人工复核：拒答任务实际为 23 个，不是每个 case 都有；这是 LLM audit 自然语言概括的错误。已在 `dataset_quality.md` 进一步要求优先引用 `dataset_summary` 计数，避免从样本模式推断全量。

### 审计问题

- `production_retrieval_v3_seed_chronic_care` / low：输入内容相对简短，信息密度可进一步提升。；建议：可增加更多关于患者反馈细节或表单设计上下文的输入，以丰富场景。
- `production_retrieval_v3_climate_analyst` / low：专业领域（气候风险）的术语和场景深度有提升空间。；建议：可引入更具体的模型参数、历史数据对比或预警发布流程的输入，以增强领域真实性。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `production_retrieval_v3_seed_growth_product` | 0.920 | persona 设定（增长产品经理）与输入内容（A/B测试、数据指标）高度契合，输入包含会议、笔记、语音等多种形式，自然且有噪声。eval_tasks 设计合理，能有效测试信息检索和边界判断。 |
| `production_retrieval_v3_cross_border_ecommerce` | 0.900 | 跨境电商场景真实，输入包含广告数据、物流沟通、运营计划，体现了领域特点。任务要求按站点拆分数据并区分已确认/未确认信息，符合职业习惯。 |
| `production_retrieval_v3_seed_chronic_care` | 0.850 | 医疗随访场景清晰，强调了记录与诊断的边界，符合职业伦理。输入内容稍显简略，但核心要素（症状、会议、流程）齐全。 |
| `production_retrieval_v3_robotics_lab` | 0.900 | 工程师 persona 真实，输入包含实验时间、固件版本、测试结果、校准计划等专业细节。任务要求保留版本和样本量，体现了严谨性。 |
| `production_retrieval_v3_seed_finance_fpna` | 0.910 | FP&A 分析师场景专业，输入包含预测数据、会议、模型假设。任务设计能测试对数据版本、假设和未知信息的处理能力。 |
| `production_retrieval_v3_climate_analyst` | 0.860 | 气候风险分析场景成立，输入包含传感器数据、会议、阈值规则。任务要求区分观测、预测和预警，符合领域规范。 |
| `production_retrieval_v3_seed_ops_warehouse` | 0.890 | 仓配运营场景具体，输入包含事件时间线、影响数据、处理流程。任务要求区分临时绕行和长期改造，体现了运营思维。 |
| `production_retrieval_v3_museum_curator` | 0.900 | 策展人 persona 细致，输入包含借展沟通、文物状况报告、展陈规划。任务要求区分借展方、馆藏状态、保险和保存条件，专业性强。 |
| `production_retrieval_v3_seed_ux_research` | 0.880 | 用户研究员场景典型，输入包含访谈安排、观察记录、综合计划。任务强调匿名化和区分观察与推断，符合研究伦理。 |
| `production_retrieval_v3_podcast_producer` | 0.870 | 播客制作人场景生动，输入包含录制安排、剪辑点、发布计划。任务要求区分录制与上线，并测试对未知广告信息的处理。 |
| `production_retrieval_v3_seed_investigative_editor` | 0.910 | 调查编辑 persona 刻画到位，输入包含线人访谈、已验证线索、未核实传闻。任务严格要求区分信息核实状态，防止将传闻写成事实。 |
| `production_retrieval_v3_patent_agent` | 0.890 | 专利代理人场景专业，输入包含发明人沟通、初步检索结果、权利要求规划。任务要求区分客户描述和检索证据，符合职业操守。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：24
- 输入条数：150
- Eval task 数：94
- Case family 分布：production_retrieval_v3_climate_analyst=1，production_retrieval_v3_counselor_ops=1，production_retrieval_v3_cross_border_ecommerce=1，production_retrieval_v3_farm_coop_manager=1，production_retrieval_v3_insurance_adjuster=1，production_retrieval_v3_museum_curator=1，production_retrieval_v3_open_source_maintainer=1，production_retrieval_v3_patent_agent=1，production_retrieval_v3_podcast_producer=1，production_retrieval_v3_robotics_lab=1，production_retrieval_v3_seed_chronic_care=1，production_retrieval_v3_seed_construction_architect=1，production_retrieval_v3_seed_family_caregiver=1，production_retrieval_v3_seed_finance_fpna=1，production_retrieval_v3_seed_game_design=1，production_retrieval_v3_seed_growth_product=1，production_retrieval_v3_seed_investigative_editor=1，production_retrieval_v3_seed_ops_warehouse=1，production_retrieval_v3_seed_restaurant_owner=1，production_retrieval_v3_seed_sre_incident=1，production_retrieval_v3_seed_technical_recruiting=1，production_retrieval_v3_seed_ux_research=1，production_retrieval_v3_travel_planner=1，production_retrieval_v3_university_lab_manager=1
- Task type 分布：retrieval_qa=94

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `v2_architect_site_001` | 建筑设计项目经理 | 重庆 | zh-CN | 1 | 6 | 3 | 南塔现场巡检是 5月15日下午四点，照片 P12 到 P18 都是幕墙龙骨偏差，别只写“外立面问题”。<br>照片 OCR 可用信息：临边防护缺两处，材料堆放挡消防通道，幕墙龙骨最大偏差 8mm。 |
| `v2_caregiver_001` | 双职工家长 | 苏州 | zh-CN | 1 | 6 | 4 | 5月24日早上九点儿童医院复查，带过敏记录和上次化验单，别忘。<br>老师今天反馈三件事：午睡短，体育课后咳嗽一次，手工课找不到蓝色文件夹。先别紧张。 |
| `v2_clinic_followup_001` | 慢病随访医生 | 南京 | zh-CN | 1 | 6 | 4 | 随访反馈有点散：三位说夜间咳嗽，两位找不到问卷入口，还有一位一直问隐私授权，先记成反馈，不是诊断。<br>5月16日下午三点和周医生评审门诊随访表单，带隐私授权截图，还有问卷漏斗。 |
| `v2_editor_001` | 深度报道编辑 | 北京 | zh-CN | 1 | 7 | 4 | 5月6日晚上 7:30 和线人 M 电话，对方只愿意匿名引用，别写实名。<br>M 的两条线索目前交叉验证过：采购绕过二次审批，验收记录晚于付款日期。语气克制点。 |
| `v2_finance_fpna_001` | FP&A 分析师 | 深圳 | zh-CN | 1 | 7 | 4 | Q2 最新 forecast：保守 1280 万，乐观 1410 万，云成本上涨会压毛利率。这个是今晚版本。<br>5月13日早上九点半预算委员会，看 Q2 forecast、云成本、续费率，别只讲收入。 |
| `v2_game_designer_001` | 独立游戏设计师 | 武汉 | zh-CN | 1 | 6 | 4 | 第 4 章 playtest：12 个人里 7 个卡灯塔谜题，平均通关 38 分钟，还有 2 个说音乐太压迫。<br>5月21日晚上九点章节 4 bug bash，重点看存档丢失和灯塔交互提示。 |
| `v2_ops_warehouse_001` | 仓配运营负责人 | 成都 | zh-CN | 1 | 6 | 4 | 夜里 3:18 西区分拣线扫码枪离线，3:42 临时切手工复核。我有点困，先把时间线记准。<br>异常影响复盘：错分 17 单，延迟出库 43 单，投诉主要是生鲜延误。 |
| `v2_prod_growth_001` | 增长产品经理 | 上海 | zh-CN | 1 | 7 | 4 | Kai 那场邀请链路 A/B 评审是 5 月 11 日下午两点。低线城市新用户转化不行，别只看总盘。<br>邀请链路今天的数据有点拧巴：老用户邀请转化 8.2%，新用户 4.7%，弹窗关闭率 31%，大图文投诉更多。 |
| `v2_recruiter_001` | 技术招聘负责人 | 广州 | zh-CN | 1 | 7 | 4 | 5月22日下午三点面 Lin，Agent 算法工程师，面试官 Tao 和 Mina。<br>Lin 面试反馈：检索评估讲得清楚，工程落地一般，追问 LLM judge 校准的时候有点虚。 |
| `v2_restaurant_001` | 餐厅主理人 | 厦门 | zh-CN | 1 | 7 | 4 | 旧报价先留着：三文鱼 68 元/斤，但后面供应商应该会更新。<br>供应商邮件：5月12日最新，三文鱼 74 一斤，青口 22 一斤；三文鱼到货不稳定。 |
| `v2_sre_001` | 数据平台 SRE | 西安 | zh-CN | 1 | 7 | 4 | 2:17 数据同步延迟告警，2:41 暂停低优先级回填，3:05 恢复。时间线别写乱。<br>事故影响：最大延迟 48 分钟，影响 BI 看板 6 个，没有影响线上交易链路。 |
| `v2_ux_research_001` | 用户研究员 | 杭州 | zh-CN | 1 | 6 | 4 | 5月18日上午访了 P03、P07、P11 三个新手用户，时间 10 点到 12 点。<br>访谈观察先记：P03 找不到导入入口，P07 误解同步状态，P11 一直担心历史记录丢失。别写真名。 |
| `v3_climate_analyst_001` | 气候风险分析师 | 昆明 | zh-CN | 1 | 6 | 4 | 雨量 digest：滇池北岸三个站过去 6 小时 41、38、44mm，南岸都低于 20mm。<br>9:30 给社区应急小组讲内涝风险，重点是北岸低洼片区，不要泛泛讲全市。 |
| `v3_counselor_ops_001` | 心理咨询机构运营 | 杭州 | zh-CN | 1 | 6 | 4 | 5月16日晚上 7:30 督导会，讲青少年团体课排班和危机转介流程。<br>家长反馈三点：报名入口难找，课前提醒太晚，保密边界说明不清楚。 |
| `v3_cross_border_ecommerce_001` | 跨境电商运营 | 义乌 | zh-CN | 1 | 6 | 4 | 欧洲站广告先记：德国 ACOS 31%、退货率 6.4%，法国 ACOS 27%、退货率 4.1%。德国差评主要说尺码偏小。<br>5月14日下午四点和货代 Leo 对德国站补货，清关资料、欧盟责任人标签都要问。 |
| `v3_farm_coop_manager_001` | 农业合作社负责人 | 大理 | zh-CN | 1 | 6 | 4 | 早上巡田：3 号茶园新梢卷曲率大概 18%，叶背少量虫卵；2 号没明显扩散。<br>5月13日早上八点农技员到 3 号茶园复查，带黄板记录和有机认证用药清单。 |
| `v3_insurance_adjuster_001` | 保险理赔定损员 | 郑州 | zh-CN | 1 | 6 | 4 | 5月14日上午十点勘查 C-7821，北环路停车场，车主 Wei 在场。<br>照片 P04 到 P09：右前翼子板擦伤，保险杠卡扣断，维修站初报 4200。 |
| `v3_museum_curator_001` | 博物馆策展人 | 西安 | zh-CN | 1 | 6 | 4 | 5月20日下午三点和洛阳馆确认青铜镜借展清单，借展期 6月3日 到 8月28日。<br>condition report OCR：A17 边缘有旧修补痕，运输湿度 45%-55%，保险估值 120 万。 |
| `v3_open_source_maintainer_001` | 开源项目维护者 | 南京 | zh-CN | 1 | 6 | 4 | GitHub digest：#428 Windows 路径，#431 tokenizer cache，#433 文档拼写，不影响发布。<br>5月21日晚上十点准备 0.9.4 release，Windows matrix 和 tokenizer cache regression 必跑。 |
| `v3_patent_agent_001` | 专利代理人 | 上海 | zh-CN | 1 | 6 | 4 | 5月9日下午两点和 Dr. Xu 聊柔性传感器，重点是低温封装、可重复弯折。<br>初检：CN1128 有低温封装，但没覆盖 5000 次弯折后的电阻漂移补偿。 |

仅展示前 20 个 Persona。
