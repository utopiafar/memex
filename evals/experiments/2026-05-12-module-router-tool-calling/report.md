# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/router_tool_calling`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 1 个 case、1 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 1 |
| 用户输入 | 0 |
| Eval task | 1 |
| 断言 | 4 |
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
| 路由 / 工具调用 | 检查路由标签、工具选择、工具参数和禁止工具调用。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 工具参数是否包含期望字段和值。 |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 是否没有调用被禁止的工具。 |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 是否调用了期望工具。 |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 路由分类是否等于期望标签。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 路由 / 工具调用 | 4 | 4 | 100.0% | - |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 路由 / 工具调用 | 工具参数 | `tool_args_accuracy` | 1 | 1 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `prohibited_tool_absence` | 1 | 1 | 100.0% | - |
| 路由 / 工具调用 | 工具选择 | `tool_selection_accuracy` | 1 | 1 | 100.0% | - |
| 路由 / 工具调用 | 路由分类 | `router_label_accuracy` | 1 | 1 | 100.0% | - |

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

- 运行 ID：`2026-05-12-module-router-tool-calling`
- 数据集：`evals/datasets/modules/router_tool_calling`
- 观察适配器：`fixture`
- 场景样本数：1
- 评估任务数：1
- Benchmark 评分耗时：0秒
- 断言通过：4/4 （100.0%）

### 场景任务明细

#### 路由 / 工具调用

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_router_tool_001` | `task_router_tool_001` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：0
- Eval task 数：1
- Case family 分布：tool_calling=1
- Task type 分布：tool_calling=1

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_003` | 数据分析师 | 上海 | zh-CN | 1 | 0 | 1 |  |
