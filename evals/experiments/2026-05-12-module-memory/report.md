# Memex Agent Eval 实验报告

## 实验问题与背景

- 本次要回答的问题：固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。
- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。
- 评估对象：`fixture` adapter，数据集 `evals/datasets/modules/memory`。

## 结论

- 整体通过，适合作为当前基线。
- 本次覆盖 2 个 case、2 个 eval task，断言通过率 100.0%。
- 失败断言数：0；Token 总量：0；LLM 调用次数：0；工具调用次数：0。

## 数据集与成本规模

| 项目 | 数值 |
| --- | ---: |
| Persona | 1 |
| Case | 2 |
| 用户输入 | 4 |
| Eval task | 2 |
| 断言 | 10 |
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
| 记忆写入 | 检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。 |

### 关键指标口径

| 场景 | 类别 | 指标 | 含义 |
| --- | --- | --- | --- |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 应该写入的长期记忆是否被写入。 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 临时/噪声信息是否没有被写成长记忆。 |
| 记忆写入 | 写入精度 | `memory_write_precision` | 写入的记忆中有多少属于期望长期事实。 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 新旧偏好冲突时是否保留最新事实、停用旧事实。 |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 重复或近似重复记忆的比例。 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 记忆是否能追溯到期望输入来源。 |

## 结果数据

### 分场景结果

| 场景 | 通过 | 总数 | 通过率 | 平均分 |
| --- | ---: | ---: | ---: | ---: |
| 记忆写入 | 10 | 10 | 100.0% | 1.000 |

### 关键指标结果

| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 记忆写入 | 写入召回 | `memory_must_write_recall` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 写入精度 | `memory_must_not_write_precision` | 1 | 1 | 100.0% | - |
| 记忆写入 | 写入精度 | `memory_write_precision` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 冲突处理 | `memory_conflict_handling` | 1 | 1 | 100.0% | - |
| 记忆写入 | 去重 | `memory_duplicate_rate` | 2 | 2 | 100.0% | 1.000 |
| 记忆写入 | 来源追溯 | `memory_source_grounding` | 2 | 2 | 100.0% | - |

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

- 运行 ID：`2026-05-12-module-memory`
- 数据集：`evals/datasets/modules/memory`
- 观察适配器：`fixture`
- 场景样本数：2
- 评估任务数：2
- Benchmark 评分耗时：0秒
- 断言通过：10/10 （100.0%）

### 场景任务明细

#### 记忆写入

| Case | Task | 结果 | 失败断言数 |
| --- | --- | --- | ---: |
| `module_memory_write_001` | `task_memory_write_001` | 通过 | 0 |
| `module_memory_conflict_001` | `task_memory_conflict_001` | 通过 | 0 |

## 附录：数据集与 Persona 示例

- 数据语言：zh-CN
- Persona 数：1
- 输入条数：4
- Eval task 数：2
- Case family 分布：memory_conflict=1，memory_write=1
- Task type 分布：memory_write=2

| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `module_u_002` | 产品经理 | 杭州 | zh-CN | 2 | 4 | 2 | 以后重要会议尽量提前一天提醒我，别临近了才说。<br>我今天上午想安静一会儿，这只是今天。 |
