# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/card_extraction`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 4 个 case、4 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 3 |
| Case | 4 |
| 用户输入 | 5 |
| Eval task | 4 |
| 断言 | 29 |
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
| Card 抽取 | 检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 后台任务结束后 card 是否离开 processing 状态。 |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 抽取出的 card 类型是否等于期望类型。 |
| Card 抽取 | 字段抽取 | `card_field_constraint_accuracy` | 指定 card 字段是否包含应保留的细节。 |
| Card 抽取 | 字段抽取 | `entity_recall` | 标题、字段、人物和地点中是否覆盖期望实体。 |
| Card 抽取 | 字段抽取 | `location_accuracy` | 地点字段是否包含期望地点。 |
| Card 抽取 | 字段抽取 | `participant_recall` | 期望人物是否都被抽取出来。 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 标题是否包含关键主题词。 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 是否没有编造禁止字段。 |
| Card 抽取 | 延迟 | `input_to_card_latency` | 从用户输入到 card 产物的延迟是否在预算内。 |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 时间解析是否落在允许误差内。 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | Card 是否具备最小合法结构，例如类型和标题。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| Card 抽取 | 29 | 29 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Card 抽取 | Card 状态 | `card_status_accuracy` | 1 | 1 | 100.0% | - |
| Card 抽取 | Card 状态 | `card_type_accuracy` | 4 | 4 | 100.0% | - |
| Card 抽取 | 字段抽取 | `card_field_constraint_accuracy` | 1 | 1 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `entity_recall` | 3 | 3 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `location_accuracy` | 1 | 1 | 100.0% | - |
| Card 抽取 | 字段抽取 | `participant_recall` | 3 | 3 | 100.0% | 1.000 |
| Card 抽取 | 字段抽取 | `title_constraint_accuracy` | 4 | 4 | 100.0% | 1.000 |
| Card 抽取 | 幻觉控制 | `hallucinated_field_absence` | 3 | 3 | 100.0% | - |
| Card 抽取 | 延迟 | `input_to_card_latency` | 2 | 2 | 100.0% | - |
| Card 抽取 | 时间解析 | `time_parse_accuracy` | 3 | 3 | 100.0% | 1.000 |
| Card 抽取 | 结构合法性 | `card_schema_valid` | 4 | 4 | 100.0% | - |

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

- 运行 ID：`2026-05-12-module-card-extraction`
- 数据集：`evals/datasets/modules/card_extraction`
- 观察适配器：`fixture`
- 场景样本数：4
- 评估任务数：4
- Benchmark 评分耗时：0秒
- 断言通过：29/29 （100.0%）

### 场景任务明细

#### Card 抽取

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_card_event_001` | `task_card_event_001` | 通过 | 0 |
| `module_card_task_002` | `task_card_task_002` | 通过 | 0 |
| `module_card_mixed_003` | `task_card_mixed_003` | 通过 | 0 |
| `module_card_event_correction_004` | `task_card_event_correction_004` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：3
- 输入条数：5
- Eval task 数：4
- Case family 分布：card_extraction=4
- Task type 分布：card_extraction=4

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 2 | 3 | 2 | 下周三晚上七点提醒我去望京和 Jason 讨论投流预算。<br>Jason 那个预算会先记周四三点。 |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 1 | 1 | 今天有点焦虑，不过重点记一下：灰度发布风险是支付回调和老版本兼容。 |
| `module_u_004` | 高校老师 | 北京 | zh-CN | 1 | 1 | 1 | 周五晚上九点前把小林的开题报告反馈写完，别忘了。 |
