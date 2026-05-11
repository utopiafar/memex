# v1 中等规模固定观察基线

## 结论

这里保存 `evals/datasets/v1_medium` 在确定性 `fixture` adapter 下的基线摘要。它用于中等规模回归检查，重点验证中文数据集、grader、成本 trace 和分场景报告是否稳定。

当前数据集由 `evals/bin/generate_medium_dataset.dart` 生成，所有 persona、用户输入、隐藏真相和 oracle 约束均使用 `zh-CN`。规模为 30 个 persona、126 个 case、186 条输入和 126 个 eval task。

原始 run 输出应保留在 `evals/runs/`，并由 git 忽略。
