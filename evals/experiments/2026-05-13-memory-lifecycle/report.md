# Memex Agent Eval 实验报告

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 12 个 case、60 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：163200；LLM 调用次数：60；工具调用次数：12。
- 数据质量审计通过：overall=0.900。
- 审计摘要：数据集语言稳定为中文，符合zh-CN场景；12个persona职业、城市、习惯自然可信；ground_truth_world、input_stream、eval_tasks.expected三者高度一致，预期结果均可从输入中合理推出；未发现明显自嗨、文化不自然或oracle泄漏问题。主要不足是案例间结构高度相似，存在模板化倾向，但因其核心测试点（记忆生命周期）明确且细节有变化，不影响作为评估数据集的使用。

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/memory_lifecycle`。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 12 |
| Case | 12 |
| 用户输入 | 1200 |
| Eval task | 60 |
| 断言 | 300 |
| LLM 调用 | 60 |
| Tool 调用 | 12 |
| 实际 token | 163200 |
| Benchmark 评分耗时 | 25秒 |

- 数据语言：zh-CN
- Token 估算：本次实际消耗 163200 tokens；同规模复跑可先按 130560-195840 tokens 预留。

## 指标口径

### 场景口径

| 场景 | 评估目标 |
| --- | --- |
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |
| Super Agent 问答 | 检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 回答是否利用用户偏好、习惯或上下文做个性化表达。 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 只读问答场景下 Super Agent 是否没有调用写入类工具。 |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 答案是否没有出现禁止或无证据断言。 |
| 检索问答 | 答案完整性 | `answer_must_include` | 答案是否包含所有必须提到的信息。 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 记忆写入 | 时效性 | `memory_temporal_validity` | 记忆是否带有正确的有效起止时间。 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 |
| 记忆写入 | 隐私边界 | `sensitive_overwrite_absence` | 敏感或临时状态是否没有被错误写成长记忆。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 记忆写入 | 240 | 240 | 100.0% | 1.000 |
| Super Agent 问答 | 60 | 60 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Super Agent 问答 | 个性化 | `personalization_accuracy` | 12 | 12 | 100.0% | 1.000 |
| Super Agent 问答 | 操作边界 | `super_agent_read_only_compliance` | 12 | 12 | 100.0% | - |
| 检索问答 | 幻觉控制 | `unsupported_claim_absence` | 12 | 12 | 100.0% | - |
| 检索问答 | 答案完整性 | `answer_must_include` | 12 | 12 | 100.0% | 1.000 |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 60 | 60 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 24 | 24 | 100.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 12 | 12 | 100.0% | 1.000 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 12 | 12 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 12 | 12 | 100.0% | 1.000 |
| 记忆写入 | 时效性 | `memory_temporal_validity` | 36 | 36 | 100.0% | - |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 60 | 60 | 100.0% | - |
| 记忆写入 | 隐私边界 | `sensitive_overwrite_absence` | 24 | 24 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 12 | 12 | 100.0% | - |

### 成本与 Trace

- LLM 调用次数：60
- 工具调用次数：12
- Token 总量：163200
- 单次 LLM 平均 token：2720.000
- 平均延迟：968.000 ms
- P95 延迟：1100.000 ms
- Benchmark 评分耗时：25秒

## 失败样本

没有失败断言。

## 实验详情

### 运行信息

- 运行 ID：`2026-05-13-memory-lifecycle`
- 数据集：`evals/datasets/memory_lifecycle`
- 观察适配器：`fixture`
- 本地完整日志：`evals/runs/2026-05-13-memory-lifecycle/debug_log.json`
- 本地 Trace：`evals/runs/2026-05-13-memory-lifecycle/trace.ndjson`
- 本地断言明细：`evals/runs/2026-05-13-memory-lifecycle/outputs.jsonl`
- 场景样本数：12
- 评估任务数：60
- Benchmark 评分耗时：25秒
- 断言通过：300/300 （100.0%）

### 场景任务明细

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `memory_lifecycle_001` | `memory_lifecycle_001_initial_write` | 通过 | 0 |
| `memory_lifecycle_001` | `memory_lifecycle_001_conflict_update` | 通过 | 0 |
| `memory_lifecycle_001` | `memory_lifecycle_001_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_001` | `memory_lifecycle_001_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_002` | `memory_lifecycle_002_initial_write` | 通过 | 0 |
| `memory_lifecycle_002` | `memory_lifecycle_002_conflict_update` | 通过 | 0 |
| `memory_lifecycle_002` | `memory_lifecycle_002_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_002` | `memory_lifecycle_002_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_003` | `memory_lifecycle_003_initial_write` | 通过 | 0 |
| `memory_lifecycle_003` | `memory_lifecycle_003_conflict_update` | 通过 | 0 |
| `memory_lifecycle_003` | `memory_lifecycle_003_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_003` | `memory_lifecycle_003_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_004` | `memory_lifecycle_004_initial_write` | 通过 | 0 |
| `memory_lifecycle_004` | `memory_lifecycle_004_conflict_update` | 通过 | 0 |
| `memory_lifecycle_004` | `memory_lifecycle_004_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_004` | `memory_lifecycle_004_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_005` | `memory_lifecycle_005_initial_write` | 通过 | 0 |
| `memory_lifecycle_005` | `memory_lifecycle_005_conflict_update` | 通过 | 0 |
| `memory_lifecycle_005` | `memory_lifecycle_005_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_005` | `memory_lifecycle_005_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_006` | `memory_lifecycle_006_initial_write` | 通过 | 0 |
| `memory_lifecycle_006` | `memory_lifecycle_006_conflict_update` | 通过 | 0 |
| `memory_lifecycle_006` | `memory_lifecycle_006_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_006` | `memory_lifecycle_006_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_007` | `memory_lifecycle_007_initial_write` | 通过 | 0 |
| `memory_lifecycle_007` | `memory_lifecycle_007_conflict_update` | 通过 | 0 |
| `memory_lifecycle_007` | `memory_lifecycle_007_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_007` | `memory_lifecycle_007_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_008` | `memory_lifecycle_008_initial_write` | 通过 | 0 |
| `memory_lifecycle_008` | `memory_lifecycle_008_conflict_update` | 通过 | 0 |
| `memory_lifecycle_008` | `memory_lifecycle_008_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_008` | `memory_lifecycle_008_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_009` | `memory_lifecycle_009_initial_write` | 通过 | 0 |
| `memory_lifecycle_009` | `memory_lifecycle_009_conflict_update` | 通过 | 0 |
| `memory_lifecycle_009` | `memory_lifecycle_009_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_009` | `memory_lifecycle_009_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_010` | `memory_lifecycle_010_initial_write` | 通过 | 0 |
| `memory_lifecycle_010` | `memory_lifecycle_010_conflict_update` | 通过 | 0 |
| `memory_lifecycle_010` | `memory_lifecycle_010_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_010` | `memory_lifecycle_010_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_011` | `memory_lifecycle_011_initial_write` | 通过 | 0 |
| `memory_lifecycle_011` | `memory_lifecycle_011_conflict_update` | 通过 | 0 |
| `memory_lifecycle_011` | `memory_lifecycle_011_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_011` | `memory_lifecycle_011_sensitive_boundary` | 通过 | 0 |
| `memory_lifecycle_012` | `memory_lifecycle_012_initial_write` | 通过 | 0 |
| `memory_lifecycle_012` | `memory_lifecycle_012_conflict_update` | 通过 | 0 |
| `memory_lifecycle_012` | `memory_lifecycle_012_temporal_scope` | 通过 | 0 |
| `memory_lifecycle_012` | `memory_lifecycle_012_sensitive_boundary` | 通过 | 0 |

#### Super Agent 问答

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `memory_lifecycle_001` | `memory_lifecycle_001_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_002` | `memory_lifecycle_002_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_003` | `memory_lifecycle_003_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_004` | `memory_lifecycle_004_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_005` | `memory_lifecycle_005_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_006` | `memory_lifecycle_006_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_007` | `memory_lifecycle_007_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_008` | `memory_lifecycle_008_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_009` | `memory_lifecycle_009_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_010` | `memory_lifecycle_010_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_011` | `memory_lifecycle_011_super_agent_latest_memory` | 通过 | 0 |
| `memory_lifecycle_012` | `memory_lifecycle_012_super_agent_latest_memory` | 通过 | 0 |

## 数据质量审计

- 总体分：0.900
- 语言一致性：1.000
- Persona 可信度：0.900
- 输入自然度：0.900
- Oracle 一致性：0.900
- 审计结论：数据集语言稳定为中文，符合zh-CN场景；12个persona职业、城市、习惯自然可信；ground_truth_world、input_stream、eval_tasks.expected三者高度一致，预期结果均可从输入中合理推出；未发现明显自嗨、文化不自然或oracle泄漏问题。主要不足是案例间结构高度相似，存在模板化倾向，但因其核心测试点（记忆生命周期）明确且细节有变化，不影响作为评估数据集的使用。
- 覆盖备注：数据集覆盖了12个不同职业和城市的用户，场景多样。；输入流包含长期偏好、临时状态、冲突更新、敏感信息边界等多种记忆生命周期场景。；评估任务覆盖了初始写入、冲突解决、时间范围、敏感信息处理和超级代理问答。

### 审计问题

- `all` / low：案例结构高度模板化；建议：在保持核心测试点不变的前提下，可微调输入顺序、表达方式或增加少量非核心干扰项，以降低模式感。

### 抽样 Case 评价

| Case | 分数 | 理由 |
| --- | ---: | --- |
| `memory_lifecycle_001` | 0.900 | 语言自然，persona可信，输入流丰富且包含多种记忆管理场景，ground truth与输入一致，评估任务设计合理。 |
| `memory_lifecycle_002` | 0.900 | 与001结构类似但细节（职业、城市、项目）不同，同样自然可信，测试点一致，质量稳定。 |
| `memory_lifecycle_003` | 0.900 | 数据分析师角色和‘保留英文metric id’的偏好增加了真实性，其他方面保持高质量。 |
| `memory_lifecycle_004` | 0.900 | 教师角色和‘反馈不超过三条重点’的偏好符合职业特点，整体逻辑自洽。 |
| `memory_lifecycle_005` | 0.900 | 律师角色和‘重要结论要列来源’的偏好合理，案例细节完整。 |
| `memory_lifecycle_006` | 0.900 | 财务主管角色和‘数字先给口径’的偏好贴合实际，案例质量与前几个一致。 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：12
- 输入条数：1200
- Eval task 数：60
- Case family 分布：memory_lifecycle=12
- Task type 分布：memory_write=48，super_agent_qa=12

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `memory_life_u_001` | 产品经理 | 杭州 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是导出项目相关评审。<br>点餐记一下：不要海鲜，少糖，晚上少咖啡。 |
| `memory_life_u_002` | 跨境电商运营 | 深圳 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是北美站增长相关评审。<br>外卖偏好更新：不要海鲜，少糖，生冷先避开。 |
| `memory_life_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是Memex eval相关评审。<br>午饭偏好：少油，别点海鲜，下午不要奶茶。 |
| `memory_life_u_004` | 老师 | 北京 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是公开课改版相关评审。<br>上课前别给我订太辣的，也尽量不要冰饮。 |
| `memory_life_u_005` | 律师 | 广州 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是法务合同库相关评审。<br>加班餐清淡一点，不要海鲜，咖啡只放上午。 |
| `memory_life_u_006` | 财务主管 | 成都 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是预算月结相关评审。<br>月底加班餐别太油，少糖，不要生冷。 |
| `memory_life_u_007` | 内容运营 | 苏州 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是小红书活动相关评审。<br>拍摄当天午饭少糖少油，不要海鲜，避免犯困。 |
| `memory_life_u_008` | 独立开发者 | 厦门 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是个人工具订阅相关评审。<br>写代码时别给我安排高糖饮料，咖啡只上午喝。 |
| `memory_life_u_009` | 医生 | 南京 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是门诊随访系统相关评审。<br>值班餐尽量清淡，不要海鲜，夜里不要咖啡。 |
| `memory_life_u_010` | HRBP | 武汉 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是绩效校准相关评审。<br>面谈前别安排太甜的饮料，午饭尽量少油。 |
| `memory_life_u_011` | 设计师 | 长沙 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是会员页改版相关评审。<br>评审日午饭少糖，不要冰饮，避免下午困。 |
| `memory_life_u_012` | 创业者 | 青岛 | zh-CN | 1 | 100 | 5 | 以后重要会议提前一天提醒我，尤其是B 端试点相关评审。<br>跑客户当天少糖少油，咖啡只上午喝。 |
