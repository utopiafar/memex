# v1 固定观察基线

## 结论

这里保存 `evals/datasets/v1` 在确定性 `fixture` adapter 下的基线摘要，用来确认 grader、指标聚合和中文报告结构没有回归。

原始 run 输出应保留在 `evals/runs/`，并由 git 忽略。LLM judge / 数据审计依赖外部模型，结果可能随模型状态轻微波动，因此不作为此目录的固定基线。
