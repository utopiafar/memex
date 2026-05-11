# Memex Agent 评估

## 结论

`evals/` 是独立于业务逻辑的 Agent 评估闭环目录。它负责读取固定数据集、收集 replay 观察结果、执行确定性断言/可选 LLM judge，并输出中文报告。业务代码不依赖这里的 runner、数据集或报告。

当前闭环已经覆盖两类运行方式：

- `fixture`：使用数据集内的固定观察结果，验证 grader、指标聚合和报告生成是否稳定。
- `replay_file`：读取 Flutter replay 写出的真实链路观察结果，复用同一套 grader 和报告。

本目录可以提交数据集、schema、judge prompt 和精选 baseline；本地 run trace、API key、临时输出保留在 `evals/runs/` 或 `evals/.env`，不会进入 git。

## 评估范围

- `card_extraction`：检查 card schema、状态、类型、时间、人物、地点、标题约束和幻觉字段。
- `memory_write`：检查长期事实召回、写入 precision、临时信息误写、重复率、冲突处理和来源追溯。
- `retrieval_qa`：检查 hit@k、MRR、recall@k、答案约束、groundedness 和无证据断言。
- `tool_calling`：检查路由标签、工具选择、工具参数、禁止调用和只读边界。
- `cost_trace`：检查 token、延迟、工具调用数量、重试/错误约束，以及轻量答案内容约束。

## 常用命令

### 小规模 fixture

```bash
dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/v1 \
  --adapter fixture
```

### 中等规模中文 fixture

```bash
dart evals/bin/generate_medium_dataset.dart

dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/v1_medium \
  --adapter fixture \
  --out evals/runs/local_fixture_medium \
  --run-id local_fixture_medium
```

当前中等规模 baseline 覆盖 30 个 persona、126 个 case、186 条输入和 126 个 eval task。

### 小型全链路 replay

```bash
flutter test --no-pub evals/replay/full_chain_replay_test.dart

dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/full_chain_smoke \
  --adapter replay_file \
  --replay-observations evals/runs/full_chain_replay_smoke/observations.jsonl \
  --out evals/runs/full_chain_replay_smoke_report \
  --run-id full_chain_replay_smoke
```

默认 replay 使用 no-LLM fallback，适合稳定 smoke。要走外部模型，把 run 目录单独指定，避免覆盖默认 baseline：

```bash
MEMEX_EVAL_ENABLE_LLM="1" \
MEMEX_EVAL_RUN_DIR="evals/runs/full_chain_replay_smoke_llm" \
EVAL_LLM_PROVIDER="anthropic" \
EVAL_LLM_BASE_URL="https://token-plan-sgp.xiaomimimo.com/anthropic" \
EVAL_LLM_API_KEY="..." \
EVAL_LLM_MODEL="mimo-v2-pro" \
flutter test --no-pub evals/replay/full_chain_replay_test.dart
```

### 中等规模全链路 replay

```bash
dart evals/bin/generate_full_chain_replay_dataset.dart

MEMEX_EVAL_ENABLE_LLM="1" \
MEMEX_EVAL_DATASET="evals/datasets/full_chain_medium/cases.jsonl" \
MEMEX_EVAL_RUN_DIR="evals/runs/full_chain_medium_llm" \
EVAL_LLM_PROVIDER="anthropic" \
EVAL_LLM_BASE_URL="https://token-plan-sgp.xiaomimimo.com/anthropic" \
EVAL_LLM_API_KEY="..." \
EVAL_LLM_MODEL="mimo-v2-pro" \
flutter test --no-pub evals/replay/full_chain_replay_test.dart

dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/full_chain_medium \
  --case-limit 3 \
  --adapter replay_file \
  --replay-observations evals/runs/full_chain_medium_llm/observations.jsonl \
  --out evals/runs/full_chain_medium_llm_report \
  --run-id full_chain_medium_llm
```

可用 `MEMEX_EVAL_CASE_LIMIT` 控制 replay case 数量，例如先跑 3 个 persona 做中等规模验证。生成报告时用 `--case-limit` 保持 runner 的数据集范围和 replay 输出一致。

## LLM 判分器

可选 LLM judge 用于语义质量和数据质量审计，不替代确定性断言。

```bash
EVAL_LLM_PROVIDER="anthropic" \
EVAL_LLM_BASE_URL="https://token-plan-sgp.xiaomimimo.com/anthropic" \
EVAL_LLM_API_KEY="..." \
EVAL_LLM_MODEL="mimo-v2-pro" \
EVAL_LLM_MAX_TOKENS="8192" \
dart evals/bin/run_agent_benchmark.dart \
  --dataset evals/datasets/v1 \
  --adapter fixture \
  --use-llm-judge \
  --audit-dataset
```

支持两类外部协议：

- `anthropic`：Anthropic-compatible `/v1/messages`，别名包括 `claude`、`mimo`、`minimax`。
- `openai_chat`：OpenAI-compatible `/v1/chat/completions`，别名包括 `openai`、`chat_completion`、`openrouter`、`kimi`、`qwen`、`zhipu`、`ollama`。

`EVAL_LLM_TIMEOUT_SECONDS` 可用于高延迟模型。默认 judge 输出预算为 `8192`，因为部分模型会先输出 reasoning/thinking block，再输出最终 JSON。

## 输出文件

每次运行会写出：

- `outputs.jsonl`：每个 eval task 一条评分结果。
- `trace.ndjson`：标准化后的 LLM/tool/task trace。
- `metrics.json`：机器可读聚合指标。
- `report.md`：中文报告，结构为结论、运行信息、分场景结果、关键指标、成本 trace、失败样本、任务明细、数据质量审计和数据集附录。

## 适配器边界

评估 runner 只关心统一 observation shape。新的 replay 生产者只要能输出相同 JSONL，就可以复用已有 graders 和报告。

```text
dataset -> adapter observation -> graders -> trace -> metrics -> report
```

`fixture` 适合验证 eval harness；`replay_file` 适合接真实 Memex 链路，例如 `submitInput`、`LocalTaskExecutor`、Cards/Facts、AgentActivity 和 LLMCallRecord。

## 附录：数据集例子

`evals/datasets/v1_medium/manifest.json` 中的规模摘要：

```json
{
  "dataset_id": "memex_agent_eval_v1_medium",
  "language": "zh-CN",
  "persona_count": 30,
  "case_count": 126,
  "families": [
    "card_extraction",
    "memory_write",
    "retrieval_qa",
    "tool_calling",
    "cost_trace"
  ]
}
```

`evals/datasets/full_chain_medium/cases.jsonl` 中的 case 结构示例：

```json
{
  "case_id": "full_chain_medium_001",
  "family": "full_chain_replay",
  "language": "zh-CN",
  "persona": {
    "user_id": "eval_fc_medium_001",
    "profile": {
      "occupation": "跨境电商运营",
      "city": "深圳"
    }
  },
  "input_stream": [
    {
      "id": "input_fc_a_0910",
      "channel": "text",
      "content": "明天上午十点提醒我和 Ada 过一下投流预算。"
    }
  ],
  "eval_tasks": [
    {
      "task_id": "full_chain_medium_001_card_a",
      "type": "card_extraction",
      "expected": {
        "input_id": "input_fc_a_0910",
        "status": "completed",
        "title_contains": ["投流预算"]
      }
    }
  ]
}
```
