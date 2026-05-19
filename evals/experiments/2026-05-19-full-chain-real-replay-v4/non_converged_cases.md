# V4 未收敛 Case 复盘

## 结论

本轮 v4 真实 LLM 全链路实验完整跑完了 36 个 case，三个 shard 的 Flutter test 都正常退出，合并后完成 216 条 observation 评分。硬未收敛 case 为 12 个，全部由 `pkm_agent_task` failed 触发；没有发现 card、schedule、comment、fts 或 root invariant 造成的 hard fail。

这轮失败不是“没等够”或 Flutter 代理问题。每个 record operation 的动态等待上限是 900 秒，12 个 hard fail 都在 3-9 分钟内进入 failed；`root_invariant_absence` 36/36，`card_materialization_rate` 和 `card_completed_rate` 都是 36/36。主问题是 PKM agent 在高密度、多主题项目上下文里缺少稳定的 no-op / clarification / delegated completion path，遇到信息不足或已由其他链路处理的输入时，会持续 `Read` / `Grep` / `BatchRead` 同一上下文，直到 generic loopDetection 兜底。

已提 upstream issue：[memex-lab/memex#163](https://github.com/memex-lab/memex/issues/163)。

## 实验上下文

- 实验目录：`evals/experiments/2026-05-19-full-chain-real-replay-v4`
- 数据集：`evals/datasets/full_chain_journey_real_replay_v4`
- 本地 run：`evals/runs/2026-05-19-full-chain-real-replay-v4-merged`
- Flutter 状态日志：
  - `evals/runs/2026-05-19-full-chain-real-replay-v4-shard-1.flutter.log`
  - `evals/runs/2026-05-19-full-chain-real-replay-v4-shard-2.flutter.log`
  - `evals/runs/2026-05-19-full-chain-real-replay-v4-shard-3.flutter.log`
- 真实 LLM：`mimo-v2-pro`
- 长跑时产品代码基线：当前 eval 分支合入 `upstream/main` `545e50e393a76e1d0a0a393ea6fb0d267393c01d` 后的 `5fc5f433503aa8c3d289b271d95bb284087871bc`
- 长跑完成后同步的最新 upstream：`e63d4dbdc5c5c28b971e0b31c91c4c02eb446e29`，仅涉及 Android launcher shortcut 资源和 Gradle shortcut 配置，不触及 agent/evals 链路
- 数据规模：12 persona、36 case、432 条 record、684 个计划操作、216 个 eval task
- 实际评分：1563/2013 断言通过，pass rate 77.6%
- 成本：3,245,437 tokens、3,260 次 LLM 调用、19,650 次 tool 调用
- Replay 实测耗时：3小时54分02秒；三个 shard 的 summary elapsed 合计约 10小时31分38秒

## 总体任务健康

| 指标 | 本轮 |
| --- | ---: |
| active task | 0 |
| failed task | 12 |
| retrying task | 0 |
| hard failed task type | `pkm_agent_task: 12` |
| loopDetection task | 21 |
| maxTurns task | 8 |
| `task_completion_status` | 24/36 |
| `operation_settlement_rate` | 24/36 |
| `loop_detection_absence` | 16/36 |
| `max_turns_absence` | 28/36 |
| `root_invariant_absence` | 36/36 |
| `card_materialization_rate` | 36/36 |
| `card_completed_rate` | 36/36 |

## 硬未收敛 Case 明细

| Case | Persona / 项目 | 触发输入 | 早停点 | 错误形态 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `journey_real_replay_v4_01_c` | 增长产品经理 / 导出灰度 | 复盘一下最近 导出灰度 里的协作方式，重点看 Mina 的反馈和我自己的表达边界。 | record 10/12，3m53s | Same tool x5 | PKM 24 次连续 `Read`；log shard1:168-174 |
| `journey_real_replay_v4_02_a` | 跨境电商运营 / 北美站增长 | 北美站增长 主要找 Jason 对齐，备选找 Ada。 | record 6/12，3m35s | Same tool x5 | PKM 24 次连续 `Read`；log shard1:198-204 |
| `journey_real_replay_v4_02_b` | 跨境电商运营 / 北美站增长 | 复盘一下最近 北美站增长 里的协作方式，重点看 Jason 的反馈和我自己的表达边界。 | record 2/12，3m37s | Same tool x5 | PKM 24 次连续 `Read`；log shard1:213-219 |
| `journey_real_replay_v4_03_b` | 数据分析师 / Memex 评测看板 | 修正一条：指标解释必须保留英文 metric id 和中文解释。，如果之前记录和这个冲突，以这条为准。 | record 5/12，3m46s | Same tool x5 | PKM 24 次连续 `Read`；log shard1:382-388 |
| `journey_real_replay_v4_03_c` | 数据分析师 / Memex 评测看板 | Memex 评测看板 的社区协作要确认 hit@3 和 MRR 截图，志愿者反馈和公开材料要分开记录。 | record 11/12，3m52s | Same tool x5 | PKM 24 次连续 `BatchRead`；log shard1:429-435 |
| `journey_real_replay_v4_04_c` | 律师 / 合同条款库 | 涉及 异常监控 的合规边界先按已有记录回答，不确定就标证据不足。 | record 4/12，3m47s | Same tool x5 | PKM 24 次连续 `Grep`；log shard1:586-592 |
| `journey_real_replay_v4_07_c` | 家庭照护者 / 妈妈康复计划 | 涉及 医疗记录只能提醒和整理，不能替代医生判断。，回答时必须标明证据来源，不要把敏感信息写进公开总结。 | record 8/12，9m01s | Maximum turns 后 LLM diagnosis loop | PKM 366 次工具调用，`Read` 192 / `Grep` 174；log shard2:536-547 |
| `journey_real_replay_v4_10_a` | 独立开发者 / 订阅计费重构 | 订阅计费重构 的用户反馈里提到 灰度节奏，先关联 Stripe webhook 日志，不要只凭一句话下结论。 | record 11/12，4m09s | Same tool x5 | PKM 24 次连续 `Read`；log shard3:234-241 |
| `journey_real_replay_v4_10_b` | 独立开发者 / 订阅计费重构 | 复盘一下最近 订阅计费重构 里的协作方式，重点看 Nora 的反馈和我自己的表达边界。 | record 2/12，3m33s | Same tool x5 | PKM 24 次连续 `Read`；log shard3:250-256 |
| `journey_real_replay_v4_10_c` | 独立开发者 / 订阅计费重构 | 复盘一下最近 订阅计费重构 里的协作方式，重点看 Nora 的反馈和我自己的表达边界。 | record 10/12，3m36s | Same tool x5 | PKM 24 次连续 `Read`；log shard3:294-300 |
| `journey_real_replay_v4_12_a` | 公益项目协调人 / 社区阅读计划 | 周末要处理 孩子托管时间，提醒我不要和 社区阅读计划 的深度工作冲突。 | record 12/12，8m14s | Maximum turns 后 LLM diagnosis loop | PKM 360 次 `Read`；错误指出反复读 `提醒规则.md` 和 `社区阅读计划.md`；log shard3:539-550 |
| `journey_real_replay_v4_12_b` | 公益项目协调人 / 社区阅读计划 | 社区阅读计划 今天卡在 素材反馈，和 小赵 对齐后 同时标注跨域影响和证据缺口，指标看 失败率。 | record 8/12，7m54s | Maximum turns 后 LLM diagnosis loop | PKM 360 次 `Read`；错误指出反复读 `创意方向收集.md` 和 `社区协作任务.md`；log shard3:584-594 |

## 触发模式

这 12 个 case 不是同一个模板简单重复，而是同一类 PKM 终止条件缺口在多场景下放大：

- **复盘/协作表达边界**：`01_c`、`02_b`、`10_b`、`10_c`。输入要求“复盘最近项目里的协作方式”，通常已有联系人、反馈、表达边界上下文；PKM 找得到项目文件，但不知道应该更新项目、写 rule、还是 no-op，于是反复读。
- **联系人/项目主责信息**：`02_a`。看似可以写入项目联系人，但 PKM 在已有项目上下文和提醒/日程链路之间反复判断，最终读同一文件到 loop。
- **纠错/覆盖旧规则**：`03_b`。输入明确说“如果之前记录冲突，以这条为准”，正确行为应该只更新对应 preference/rule；实际仍在上下文搜索里循环。
- **公开/内部/隐私边界**：`03_c`、`04_c`、`07_c`、`12_b`。这些输入常常不是要改某个具体项目字段，而是要形成边界规则或确认已有规则覆盖；PKM 缺 no-op/边界规则完成路径。
- **提醒/调度与项目冲突**：`12_a`。与 #154 类似，提醒和 schedule 应由 card/schedule 链路处理；PKM 不应为了推断具体提醒继续读项目文件。
- **来源不足/只读约束**：`10_a`。输入要求“不要只凭一句话下结论”，更像 source grounding 规则；如果没有足够来源，PKM 应写轻量规则或 no-op，而不是持续搜索。

## 为什么会没有收敛

“没有收敛”不是指 Flutter test 没跑完，而是指某个用户旅程 case 内的一条 operation 结束时后台任务已进入 failed。为了避免污染后续观察，harness 对该 case 早停并继续下一个 case。因此本轮 36 个 case 都有 summary，但其中 12 个 case 没有执行完自己计划的后续 timeline/comment/schedule/insight/Super Agent 操作。

具体机理是：

1. 用户 record 提交后，card、comment、schedule、PKM 等任务被 LocalTaskExecutor 串行处理。
2. 同一 record 的 card/comment/schedule 多数已 completed，PKM 进入 processing/retrying。
3. PKM agent 反复调用同一种上下文工具，常见是 `Read`，也有 `Grep` / `BatchRead`。
4. 工具返回没有给 agent 带来新的可执行信息，但 agent 没有选择 terminal action。
5. agent core 触发 `AgentExceptionCode.loopDetection`，任务 retry。
6. retry 到 5 次后 `pkm_agent_task` 标记 failed。
7. Harness 看到 failed task，把该 operation 标为 `tasks_settled=false`，停止该 case 后续操作。

## 项目问题 vs 测试方法/框架问题

### 项目问题

- PKM agent 对“找得到上下文但无唯一写入动作”的输入缺少 terminal path。
- `skip_pkm_organization` 的 reason 和 handler 完成证据还不足，不能覆盖 `already_covered`、`handled_by_schedule`、`insufficient_source`、`privacy_boundary_no_public_write` 等情况。
- `create_clarification_request` 或类似澄清动作没有成为稳定 completed 证据，agent 容易继续分析而不是结束。
- 重复工具调用保护在 agent 业务层太弱，只靠 generic loopDetection 兜底；这会把本可 no-op 的输入变成 failed task。
- PKM 和 card/schedule/comment 的职责边界还不够硬：提醒、调度、只读回答边界等语义已经由其他链路处理时，PKM 仍会尝试从项目文件继续推断。

### 测试方法/框架问题

这些不是 hard fail 根因，但已记录为后续规避项：

- 长跑前必须检查磁盘空间。本轮第一次 shard 因本机磁盘满导致 `tee: No space left on device` 和 SQLite `unable to open database file`，该尝试已丢弃重跑，不能计入产品问题。
- 清理缓存后 `.dart_tool/package_config.json` 可能缺失；真实 replay 用 `--no-pub` 时会直接失败。恢复方式是用 Flutter 代理规避环境跑 `flutter pub get --offline`。
- Flutter 代理规避仍然必要：保留外部 LLM 所需 HTTP(S) 代理，但取消 `ws_proxy` / `wss_proxy`，并设置 localhost `no_proxy` / `NO_PROXY`，避免 `flutter_tester` WebSocket 走代理。
- `status.json` 是运行中状态快照，不保证 suite 结束后写 final completed snapshot；最终结论以 `summary.json`、`metrics.json` 和 `outputs.jsonl` 为准。
- 长跑期间 upstream main 可能继续前进；报告必须写清楚“长跑实际代码基线”，不要把后续无关 merge 伪装成实验基线。

## 可恢复 Loop 观察

除了 12 个 hard fail，本轮还有可恢复 retry：

- Knowledge Insight：`01_b`、`02_c`、`04_a`、`05_c`、`07_a`、`09_b`、`11_a`、`12_c` 都出现过 `Maximum turns reached` 后 retry，最终 completed。
- PKM：`12_c/record_326` 出现一次 `Loop detected` retry，最终 completed。

这些没有造成 failed task，但说明 `loopDetection` / `maxTurns` 不能只看 hard fail。后续指标应继续按 agent、工具和场景拆分：

- `loop_detection_by_agent`
- `max_turns_by_agent`
- `recoverable_retry_count_by_agent`
- `redundant_tool_call_rate`
- `terminal_action_distribution`
- `noop_completion_rate`
- `clarification_completion_rate`

## 改进建议

1. 给 PKM agent 增加候选动作决策阶段：每条输入先分类为 `write_rule` / `update_project` / `noop` / `clarify` / `delegate_to_schedule`，后续必须落到一个 terminal action。
2. 扩展 `skip_pkm_organization`：支持 `already_covered`、`not_long_term`、`handled_by_schedule`、`insufficient_source`、`privacy_boundary_no_public_write` 等 reason，并由 task handler 作为 completed 接收。
3. 对 clarification path 做成真正完成路径：创建一次澄清请求后任务 completed，而不是继续读取上下文。
4. 加 per-fact 工具预算和内容哈希去重：同一 fact 内连续读取同一路径或同一查询结果内容不变时，下一步强制选择 no-op / clarification / complete。
5. 强化职责边界：提醒和调度交给 card/schedule，Super Agent 只读问答交给检索/回答链路，PKM 只沉淀稳定长期知识或项目结构更新。
6. 回归测试应覆盖本轮四类代表样例：协作复盘、纠错覆盖、隐私/公开边界、提醒与项目冲突；断言 `pkm_agent_task` completed、failed task 为 0，同一工具连续调用不超过阈值。
