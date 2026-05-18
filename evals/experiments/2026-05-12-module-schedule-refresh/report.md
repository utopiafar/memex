# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/schedule_refresh`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 6 个 case、6 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 4 |
| Case | 6 |
| 用户输入 | 220 |
| Eval task | 6 |
| 断言 | 38 |
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
| 日程刷新 | 检查日程相关输入是否正确 skip / dirty / refresh，并控制不必要刷新。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 日程刷新决策是否等于期望的 skip / dirty / refresh。 |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 必须刷新时是否没有漏掉刷新。 |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 无需刷新时是否没有触发重刷新。 |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 是否没有对同一日程变化触发重复刷新。 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 路由分类是否等于期望标签。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 日程刷新 | 38 | 38 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 日程刷新 | 刷新决策 | `schedule_refresh_action_accuracy` | 6 | 6 | 100.0% | - |
| 日程刷新 | 刷新召回 | `schedule_refresh_missed_absence` | 6 | 6 | 100.0% | - |
| 日程刷新 | 刷新精度 | `schedule_refresh_unnecessary_absence` | 6 | 6 | 100.0% | - |
| 日程刷新 | 去重 | `schedule_refresh_duplicate_rate` | 4 | 4 | 100.0% | 1.000 |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 4 | 4 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 2 | 2 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 4 | 4 | 100.0% | - |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 6 | 6 | 100.0% | - |

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

- 运行 ID：`2026-05-12-module-schedule-refresh`
- 数据集：`evals/datasets/modules/schedule_refresh`
- 观察适配器：`fixture`
- 场景样本数：6
- 评估任务数：6
- Benchmark 评分耗时：0秒
- 断言通过：38/38 （100.0%）

### 场景任务明细

#### 日程刷新

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_schedule_refresh_001` | `task_schedule_refresh_001` | 通过 | 0 |
| `module_schedule_skip_001` | `task_schedule_skip_001` | 通过 | 0 |
| `module_schedule_dirty_003` | `task_schedule_dirty_003` | 通过 | 0 |
| `module_schedule_cancel_004` | `task_schedule_cancel_004` | 通过 | 0 |
| `module_schedule_skip_note_005` | `task_schedule_skip_note_005` | 通过 | 0 |
| `module_schedule_recurring_006` | `task_schedule_recurring_006` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：4
- 输入条数：220
- Eval task 数：6
- Case family 分布：schedule_refresh=6
- Task type 分布：schedule_refresh=6

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_001` | 跨境电商运营 | 深圳 | zh-CN | 2 | 72 | 2 | 早上先看一下昨天广告账户的消耗，今天预算别太激进。<br>午饭别订海鲜，最近过敏又有点反复。 |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 1 | 37 | 1 | 早上先过一遍版本风险，今天别被零碎需求打散。<br>以后评审材料希望结论先行，细节放后面。 |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 37 | 1 | 早上先跑昨天的数据质量检查，看有没有埋点延迟。<br>以后异常分析先看样本量，再看比例变化。 |
| `module_u_004` | 高校老师 | 北京 | zh-CN | 2 | 74 | 2 | 早上先看学生发来的论文摘要，今天课前只能粗读。<br>公开课提醒要提前两天准备讲义。 |
