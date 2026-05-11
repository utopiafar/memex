# 全链路 Replay Smoke 基线

## 结论

这里保存小型 full-chain replay smoke 的基线摘要。Flutter replay test 会在隔离临时 workspace 中提交输入，等待 `LocalTaskExecutor` 完成任务，读取 Cards/Facts/tasks/AgentActivity/LLMCallRecord，并把标准化 observation 写到 `evals/runs/`。随后 `replay_file` adapter 使用同一套 grader 生成报告。

当前提交的基线是确定性的 no-LLM smoke。它刻意保留一个已暴露问题：后台任务完成后，fallback 生成的 card 仍是 `status=processing`。

外部模型 replay 对诊断很有价值，但依赖具体 provider/model，当次结果应保留在 `evals/runs/`，不要固化进此 baseline 目录。
