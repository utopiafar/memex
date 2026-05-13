# Memex Agent Eval 实验报告

## 结论

- 合成 fixture 整体通过，适合作为小规模回归基线。
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay。
- 本次覆盖 5 个 case、16 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：27240；LLM 调用次数：16；工具调用次数：29。
- 数据质量审计通过：overall=0.900。
- 审计摘要：数据集语言稳定为中文，persona 可信且体现职业差异，输入自然多样（含碎碎念和冗余），ground_truth、input_stream 和 eval_tasks 高度一致，无模板化或 oracle 泄漏问题，适合作为小规模 benchmark

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/production_like_retrieval`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 5 |
| Case | 5 |
| 用户输入 | 23 |
| Eval task | 16 |
| 断言 | 139 |
| LLM 调用 | 16 |
| Tool 调用 | 29 |
| 实际 token | 27240 |
| Benchmark 评分耗时 | 32秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 27240 tokens；同规模复跑可先按 21792-32688 tokens 预留。

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
| 检索问答 | 139 | 139 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 检索问答 | 不确定性控制 | `abstention_accuracy` | 3 | 3 | 100.0% | - |
| 检索问答 | 召回排序 | `retrieval_hit_at_1` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_3` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_hit_at_5` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_mrr` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 召回排序 | `retrieval_recall_at_5` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 幻觉控制 | `unnecessary_uncertainty_absence` | 13 | 13 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 3 | 3 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 16 | 16 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `answer_source_citation` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 证据支撑 | `grounded_answer_rate` | 13 | 13 | 100.0% | 1.000 |
| 检索问答 | 过滤准确性 | `retrieval_filter_accuracy` | 13 | 13 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：16
- 工具调用次数：29
- Token 总量：27240
- 单次 LLM 平均 token：1702.500
- 平均延迟：410.222 ms
- P95 延迟：900.000 ms
- Benchmark 评分耗时：32秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-production-like-retrieval-diversity-audit`
- 数据集：`evals/datasets/production_like_retrieval`
- 观察适配器：`fixture`
- 证据等级：已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay
- 本地完整日志：`evals/runs/2026-05-13-production-like-retrieval-diversity-audit/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-production-like-retrieval-diversity-audit/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-production-like-retrieval-diversity-audit/outputs.jsonl`
- 场景样本数：5
- 评估任务数：16
- Benchmark 评分耗时：32秒
- 断言通过：139/139 （100.0%）

### 场景任务明细

#### 检索问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `production_retrieval_product_001` | `pm_q_gray_review` | 通过 | 0 |
| `production_retrieval_product_001` | `pm_q_rollback` | 通过 | 0 |
| `production_retrieval_product_001` | `pm_q_unknown_flight` | 通过 | 0 |
| `production_retrieval_clinic_001` | `clinic_q_complaints` | 通过 | 0 |
| `production_retrieval_clinic_001` | `clinic_q_review` | 通过 | 0 |
| `production_retrieval_clinic_001` | `clinic_q_dose` | 通过 | 0 |
| `production_retrieval_legal_001` | `legal_q_risks` | 通过 | 0 |
| `production_retrieval_legal_001` | `legal_q_annie` | 通过 | 0 |
| `production_retrieval_legal_001` | `legal_q_source_rule` | 通过 | 0 |
| `production_retrieval_teacher_001` | `teacher_q_trial` | 通过 | 0 |
| `production_retrieval_teacher_001` | `teacher_q_feedback` | 通过 | 0 |
| `production_retrieval_teacher_001` | `teacher_q_next` | 通过 | 0 |
| `production_retrieval_indie_dev_001` | `dev_q_feedback` | 通过 | 0 |
| `production_retrieval_indie_dev_001` | `dev_q_bugbash` | 通过 | 0 |
| `production_retrieval_indie_dev_001` | `dev_q_style` | 通过 | 0 |
| `production_retrieval_indie_dev_001` | `dev_q_unknown_hotel` | 通过 | 0 |

## 数据质量审计

- 总体分：0.900
- 语言一致性：0.900
- Persona 可信度：0.900
- 输入自然度：0.900
- Oracle 一致性：0.900
- 审计结论：数据集语言稳定为中文，persona 可信且体现职业差异，输入自然多样（含碎碎念和冗余），ground_truth、input_stream 和 eval_tasks 高度一致，无模板化或 oracle 泄漏问题，适合作为小规模 benchmark
- 覆盖备注：覆盖五个不同职业（医生、独立开发者、律师、产品经理、老师），输入包含噪声、碎碎念和语音转录，增加真实性和多样性

### 审计问题

模型审计未发现明显数据质量问题。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `production_retrieval_product_001` | 0.900 | 产品经理场景自然，输入有噪声（如咖啡洒了），任务与输入一致，oracle 无泄漏 |
| `production_retrieval_clinic_001` | 0.900 | 医生领域差异明显（如医疗谨慎偏好），输入包含投诉和评审细节，任务匹配良好 |
| `production_retrieval_legal_001` | 0.900 | 律师职业体现法律专业（如合同风险、来源要求），输入多样，任务从输入可推出 |
| `production_retrieval_teacher_001` | 0.900 | 老师场景真实（公开课、学生反馈），输入有闲聊（嗓子哑），任务覆盖关键信息 |
| `production_retrieval_indie_dev_001` | 0.900 | 独立开发者风格独特（少写空话、backlog 导向），输入包含 bug bash 和噪声，任务一致 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：5
- 输入条数：23
- Eval task 数：16
- Case family 分布：production_retrieval_clinic=1，production_retrieval_indie_dev=1，production_retrieval_legal=1，production_retrieval_product=1，production_retrieval_teacher=1
- Task type 分布：retrieval_qa=16

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `clinic_u_001` | 医生 | 南京 | zh-CN | 1 | 4 | 3 | 随访系统这两天投诉有点散：问卷提交失败、隐私授权说明不清、复诊提醒重复。先记一下，别写成诊断。<br>5月16日下午三点和周医生评审门诊随访系统表单，记得带隐私授权截图。 |
| `dev_u_001` | 独立开发者 | 厦门 | zh-CN | 1 | 5 | 4 | 个人工具订阅反馈先记：订阅激活失败、支付回调慢、导入报错。别写漂亮话，能进 backlog 就行。<br>5月21日晚上九点做订阅 bug bash，重点看支付回调和退款工单。 |
| `legal_u_001` | 律师 | 广州 | zh-CN | 1 | 5 | 3 | 和 Annie 飞书会议对了一版合同风险清单，5 月 9 日 18:30，别忘。<br>法务合同库这轮重点是 SLA 违约责任、数据删除期限、审计日志保留。客户口述不能当正式意见。 |
| `prod_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 5 | 3 | 刚和 Nora 过完导出灰度，时间是 5 月 12 日 10:30。嗯，重点是失败率和回滚开关，别写得太乐观。<br>导出失败率从 2.1% 到 3.4%，客服说大文件重试和等待时间被问得最多。 |
| `teacher_u_001` | 老师 | 北京 | zh-CN | 1 | 4 | 3 | 公开课改版试听是 5 月 20 日晚上七点，课前两小时检查直播回放和讲义下载。<br>学生反馈有点碎：讲义下载慢、回放入口藏得深、作业入口找不到。 |
