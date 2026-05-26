# Memex Agent Eval 实验报告

## 结论

- 合成 fixture 整体通过，适合作为小规模回归基线。
- 本轮是 `production_like_retrieval` 的扩展迭代：从 5 个用户、23 条输入、16 个任务扩到 12 个用户、78 条输入、47 个任务，重点验证更复杂、更自然的检索输入是否还能保持 source grounding、citation、拒答和 LLM judge 稳定。
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay。
- 本次覆盖 12 个 case、47 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：87990；LLM 调用次数：47；工具调用次数：166。
- LLM Judge 断言数：47。
- 数据质量审计通过：overall=0.900。
- 审计摘要：数据集整体质量很高。语言稳定为中文且自然，12个职业角色设定可信且体现了领域差异（如医生的诊断边界、编辑的核实要求、SRE的安全意识）。输入内容多样，包含工作记录、语音转写、日历事件等，信息密度适中且有自然噪声。ground_truth_world、input_stream与eval_tasks之间高度一致，预期答案均可从给定信息中合理推出，无明显oracle泄漏。虽有极个别轻微可优化点（如候选人区分），但完全满足作为小规模benchmark数据的要求。
- 人工复核备注：audit 的覆盖备注里把任务结构概括成“每个 case 均包含 3 个检索问答和 1 个拒答”，这不完全准确；建筑 case 只有 3 个任务，编辑 case 没有拒答任务。指标数据本身正确，但后续不能盲信 LLM audit 的自然语言概括。

## 实验问题与背景

- 本次要回答的问题：当生产贴近 Retrieval QA 数据扩到更多职业、更多输入渠道、更多噪声和更多用户后，规则指标、LLM groundedness judge、数据质量审计和报告生成是否仍然稳定。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 本轮仍使用 fixture observed，因此它验证的是 harness、数据闭环和裁判口径，不直接证明真实 Memex Agent 行为。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/production_like_retrieval_v2`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 12 |
| Case | 12 |
| 用户输入 | 78 |
| Eval task | 47 |
| 断言 | 440 |
| LLM 调用 | 47 |
| LLM Judge 断言 | 47 |
| Tool 调用 | 166 |
| 实际 token | 87990 |
| Benchmark 评分耗时 | 13分22秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 87990 tokens；同规模复跑可先按 70392-105588 tokens 预留。

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
| 检索问答 | 440 | 440 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 11 | 11 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 36 | 36 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 11 | 11 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 47 | 47 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 36 | 36 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `llm_grounded_answer_score` | 47 | 47 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 36 | 36 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：47
- 工具调用次数：166
- Token 总量：87990
- 单次 LLM 平均 token：1872.128
- 平均延迟：294.432 ms
- P95 延迟：980.000 ms
- Benchmark 评分耗时：13分22秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-production-like-retrieval-v2-llm-judge`
- 数据集：`evals/datasets/production_like_retrieval_v2`
- 观察适配器：`fixture`
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay
- 本地完整日志：`evals/runs/2026-05-13-production-like-retrieval-v2-llm-judge/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-production-like-retrieval-v2-llm-judge/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-production-like-retrieval-v2-llm-judge/outputs.jsonl`
- 场景样本数：12
- 评估任务数：47
- Benchmark 评分耗时：13分22秒
- 断言通过：440/440 （100.0%）
- LLM Judge：`anthropic` / `mimo-v2-pro` / max_tokens=4096
- LLM Judge 任务策略：`retrieval_and_super_agent_qa_unless_expected_llm_judge_false`
- LLM Judge 断言数：47

### 场景任务明细

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `production_retrieval_v2_growth_product` | `gp_q_ab_metrics` | 通过 | 0 |
| `production_retrieval_v2_growth_product` | `gp_q_decision` | 通过 | 0 |
| `production_retrieval_v2_growth_product` | `gp_q_old_record_boundary` | 通过 | 0 |
| `production_retrieval_v2_growth_product` | `gp_q_unknown_budget` | 通过 | 0 |
| `production_retrieval_v2_chronic_care` | `cc_q_feedback` | 通过 | 0 |
| `production_retrieval_v2_chronic_care` | `cc_q_review` | 通过 | 0 |
| `production_retrieval_v2_chronic_care` | `cc_q_next_action` | 通过 | 0 |
| `production_retrieval_v2_chronic_care` | `cc_q_unknown_dose` | 通过 | 0 |
| `production_retrieval_v2_finance_fpna` | `fin_q_latest_forecast` | 通过 | 0 |
| `production_retrieval_v2_finance_fpna` | `fin_q_board` | 通过 | 0 |
| `production_retrieval_v2_finance_fpna` | `fin_q_model_assumption` | 通过 | 0 |
| `production_retrieval_v2_finance_fpna` | `fin_q_unknown_cash` | 通过 | 0 |
| `production_retrieval_v2_ops_warehouse` | `ops_q_incident` | 通过 | 0 |
| `production_retrieval_v2_ops_warehouse` | `ops_q_runbook` | 通过 | 0 |
| `production_retrieval_v2_ops_warehouse` | `ops_q_style` | 通过 | 0 |
| `production_retrieval_v2_ops_warehouse` | `ops_q_unknown_compensation` | 通过 | 0 |
| `production_retrieval_v2_ux_research` | `ux_q_findings` | 通过 | 0 |
| `production_retrieval_v2_ux_research` | `ux_q_synthesis` | 通过 | 0 |
| `production_retrieval_v2_ux_research` | `ux_q_rule` | 通过 | 0 |
| `production_retrieval_v2_ux_research` | `ux_q_unknown_nps` | 通过 | 0 |
| `production_retrieval_v2_investigative_editor` | `ed_q_verified_claims` | 通过 | 0 |
| `production_retrieval_v2_investigative_editor` | `ed_q_interview` | 通过 | 0 |
| `production_retrieval_v2_investigative_editor` | `ed_q_outline` | 通过 | 0 |
| `production_retrieval_v2_investigative_editor` | `ed_q_rumor_boundary` | 通过 | 0 |
| `production_retrieval_v2_restaurant_owner` | `rs_q_latest_quote` | 通过 | 0 |
| `production_retrieval_v2_restaurant_owner` | `rs_q_private_dinner` | 通过 | 0 |
| `production_retrieval_v2_restaurant_owner` | `rs_q_menu` | 通过 | 0 |
| `production_retrieval_v2_restaurant_owner` | `rs_q_unknown_wine` | 通过 | 0 |
| `production_retrieval_v2_construction_architect` | `ar_q_site_issues` | 通过 | 0 |
| `production_retrieval_v2_construction_architect` | `ar_q_rectification` | 通过 | 0 |
| `production_retrieval_v2_construction_architect` | `ar_q_unknown_permit` | 通过 | 0 |
| `production_retrieval_v2_game_design` | `gd_q_playtest` | 通过 | 0 |
| `production_retrieval_v2_game_design` | `gd_q_bugbash` | 通过 | 0 |
| `production_retrieval_v2_game_design` | `gd_q_balance` | 通过 | 0 |
| `production_retrieval_v2_game_design` | `gd_q_unknown_store` | 通过 | 0 |
| `production_retrieval_v2_technical_recruiting` | `hr_q_lin_feedback` | 通过 | 0 |
| `production_retrieval_v2_technical_recruiting` | `hr_q_scorecard` | 通过 | 0 |
| `production_retrieval_v2_technical_recruiting` | `hr_q_privacy` | 通过 | 0 |
| `production_retrieval_v2_technical_recruiting` | `hr_q_unknown_salary` | 通过 | 0 |
| `production_retrieval_v2_family_caregiver` | `cg_q_checkup` | 通过 | 0 |
| `production_retrieval_v2_family_caregiver` | `cg_q_school_feedback` | 通过 | 0 |
| `production_retrieval_v2_family_caregiver` | `cg_q_allergy` | 通过 | 0 |
| `production_retrieval_v2_family_caregiver` | `cg_q_unknown_insurance` | 通过 | 0 |
| `production_retrieval_v2_sre_incident` | `sre_q_incident` | 通过 | 0 |
| `production_retrieval_v2_sre_incident` | `sre_q_runbook` | 通过 | 0 |
| `production_retrieval_v2_sre_incident` | `sre_q_secret_boundary` | 通过 | 0 |
| `production_retrieval_v2_sre_incident` | `sre_q_unknown_api_key` | 通过 | 0 |

## 数据质量审计

- 总体分：0.900
- 语言一致性：1.000
- Persona 可信度：0.950
- 输入自然度：0.900
- Oracle 一致性：0.950
- 审计结论：数据集整体质量很高。语言稳定为中文且自然，12个职业角色设定可信且体现了领域差异（如医生的诊断边界、编辑的核实要求、SRE的安全意识）。输入内容多样，包含工作记录、语音转写、日历事件等，信息密度适中且有自然噪声。ground_truth_world、input_stream与eval_tasks之间高度一致，预期答案均可从给定信息中合理推出，无明显oracle泄漏。虽有极个别轻微可优化点（如候选人区分），但完全满足作为小规模benchmark数据的要求。
- 覆盖备注：覆盖12种不同职业，地域分布广泛（北京、上海、深圳、重庆、南京、苏州、杭州、厦门、武汉、成都、广州、西安），场景多样。；输入类型丰富，包含会议记录、语音转文字、日历笔记、OCR结果、邮件剪辑等，符合真实工作场景。；每个案例均包含3个检索问答任务和1个需要拒绝回答（abstain）的任务，结构完整。；噪声条目设计合理，能模拟真实环境中的无关信息、语音识别错误和用户情绪表达。
- 人工复核：上面“每个案例均包含3个检索问答任务和1个需要拒绝回答任务”的概括不完全准确；该数据集刻意保留了不等长结构。下轮已要求 dataset quality prompt 避免无证据的绝对表述。

### 审计问题

- `production_retrieval_v2_technical_recruiting` / low：候选人信息（Lin 和 Chen）在输入中同时出现，虽有区分提示，但对模型检索的精确性要求较高，可能造成轻微混淆。；建议：可考虑在评估任务的 `expected_filters` 中更明确地强调 `candidate: "Lin"`，或在输入中增加一条更明确的区分指令。
- `production_retrieval_v2_chronic_care` / low：噪声条目 `cc_noise_02` 中提到的语音识别错误（“隐私瘦全”）可能过于具体和生硬，略微降低了自然度。；建议：可以调整为更通用的表述，如“语音识别常把‘授权’听错，注意结合上下文判断”。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `production_retrieval_v2_growth_product` | 0.950 | 角色（增长产品经理）专业性强，输入包含具体数据（8.2%，4.7%）和决策，噪声（如地铁噪音、预算焦虑）自然，评估任务能很好检验对新老用户拆分、决策依据和信息边界（旧数据、未知预算）的理解。 |
| `production_retrieval_v2_ops_warehouse` | 0.900 | 仓配运营场景真实，输入包含精确时间线（3:18, 3:42）和影响数据（错分17单），噪声（语音识别混淆“手工”与“收工”）贴合实际。评估任务覆盖事件复盘、流程查询和用户偏好记忆。 |
| `production_retrieval_v2_investigative_editor` | 0.900 | 深度报道编辑的角色设定和职业操守（区分已核实、待核实、传闻）非常真实。输入内容（线人访谈、线索验证）和评估任务（验证线索、引用限制、处理传闻）高度契合，体现了领域特殊性。 |
| `production_retrieval_v2_restaurant_owner` | 0.850 | 餐厅主理人场景生活化，输入包含报价更新、过敏提醒等关键信息。评估任务能有效检验对最新信息、过敏优先级和未知信息（配酒）的处理。噪声（语音识别“青口”为“清口”）合理。 |
| `production_retrieval_v2_sre_incident` | 0.900 | SRE事故复盘场景专业，输入包含精确时间线、影响范围和处理流程。评估任务覆盖事件复盘、runbook查询和安全边界（密钥）。噪声（语音识别错误、疲劳状态）自然。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：78
- Eval task 数：47
- Case family 分布：production_retrieval_v2_chronic_care=1，production_retrieval_v2_construction_architect=1，production_retrieval_v2_family_caregiver=1，production_retrieval_v2_finance_fpna=1，production_retrieval_v2_game_design=1，production_retrieval_v2_growth_product=1，production_retrieval_v2_investigative_editor=1，production_retrieval_v2_ops_warehouse=1，production_retrieval_v2_restaurant_owner=1，production_retrieval_v2_sre_incident=1，production_retrieval_v2_technical_recruiting=1，production_retrieval_v2_ux_research=1
- Task type 分布：retrieval_qa=47

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
