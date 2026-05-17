# Memex Eval Harness Engineering Log

## 原则

Harness 的目标不是把分数做漂亮，而是让每次实验的假设、数据、裁判、失败和结论都能被复查、复跑、扩展。

- 先跑 fixture smoke，再跑 LLM judge。规则断言先发现 source id、must_include、schema 和 fixture 闭环问题，避免把低级数据错误交给模型裁判。
- Oracle 必须来自 `ground_truth_world` 和 `expected`，不能从 observed answer 反推。`must_include` 应优先对齐 source snippet，而不是只对齐用户输入里的口语表述。
- 数据审计是实验的一部分。即使断言 100%，只要 audit 指出模板化、自然度不足、source 混淆或 oracle 风险，都要写入报告和本日志。
- LLM judge 只判语义 groundedness、完整性、unsupported claims 和数据自然度；source id、tool call、时间、成本、任务状态仍然规则判。
- fixture 的 `audited_synthetic_fixture` 只能作为小规模合成回归基线，不能替代真实 Memex replay。
- 原始 `debug_log.json`、`outputs.jsonl`、`trace.ndjson` 放到 `evals/runs/<run-id>/`，实验目录只保留 `report.md` 和 `metrics.json`。
- 外部模型 key 只能通过环境变量或本地忽略文件传入，不能进入数据集、报告、trace 或 README。

## 2026-05-13 Production-like Retrieval v2

### 实验目标

上一轮 `production_like_retrieval` 证明了小而精的生产贴近检索数据可以把文风单调问题明显缓解，但规模只有 5 个用户、16 个任务。这一轮扩到 12 个用户、78 条输入、47 个 retrieval QA 任务，增加行业、噪声、旧记录/新记录、拒答和多来源答案。

### 数据设计

- 职业覆盖：增长产品、慢病随访、FP&A、仓配运营、用研、深度报道、餐厅、建筑现场、游戏设计、技术招聘、家庭照护、SRE。
- 输入渠道：普通文本、语音转写、会议记录、日历笔记、OCR、邮件剪辑、事故记录、表格笔记。
- 复杂度：多来源回答、旧记录与最新修正、相似人名/候选人干扰、医疗/隐私/密钥边界、生活噪声、语音识别错听、证据不足拒答。
- 数据集：`evals/datasets/production_like_retrieval_v2`
- 生成器：`evals/bin/generate_production_like_retrieval_v2_dataset.dart`

### 抽样与校验过程

1. 生成后先检查 manifest 和 JSONL 行数：12 case、78 inputs、47 tasks。
2. 用脚本检查所有 `input.source_id` 和 `expected.expected_sources` 都能在 `ground_truth_world` 中找到。
3. 跑 fixture smoke：第一次为 391/393，发现 2 个 `answer_must_include` 失败。
4. 修正失败时没有改 observed answer，而是把 expected 从口语输入短语对齐到 source snippet：
   - `gp_q_old_record_boundary`：`别混` 改为 source 中存在的 `春节裂变`。
   - `ed_q_rumor_boundary`：`不能` 改为 source 中存在的 `不把传闻写成事实`。
5. 复跑 fixture smoke：393/393。
6. 正式 LLM judge + dataset audit：440/440，LLM judge 47/47，audit overall=0.900。

### 结果怎么读

这轮可以证明：

- 更复杂、更自然的合成 Retrieval QA fixture 已经能稳定跑通规则指标、LLM groundedness judge、数据质量审计和报告生成。
- v2 比 v1 更适合展示“如何工程化构造生产贴近数据”：用户数更多，输入渠道更多，噪声和边界条件更复杂，报告中的 token、tool、abstention、citation 指标也更丰富。

这轮不能证明：

- 真实 Memex Agent 在这些输入上一定能完成写入、检索和回答，因为 observed 仍来自 fixture。
- 这不是完整 Agent benchmark。当前任务类型仍是 `retrieval_qa`，还没有把同等复杂度扩到 card、memory、PKM、schedule、Super Agent 和真实 replay。

### 本轮发现与后续避免

- `must_include` 不要写只存在于用户输入里的随口短语，除非 observed answer 的生成逻辑也会引用输入。更稳的做法是让 must include 对齐 `source_snippets`。
- 有意加入相似实体干扰是好事，例如 Lin 和 Chen；但要在 `expected_filters` 中明确目标实体，否则 audit 会把它标成潜在混淆。
- 语音识别噪声要自然。过于刻意的错听梗会降低 input naturalness；下轮优先使用常见 ASR 错误、断句不完整和口头修正。
- 不要让每个 case 都固定为 4 个任务。v2 已经让建筑场景只有 3 个任务，后续可以进一步让 source 数、task 数、拒答比例更不均匀。
- LLM audit 的自然语言概括也需要人工复核。本轮 audit 说“每个 case 均包含 3 个检索问答和 1 个拒答”，但建筑 case 只有 3 个任务，编辑 case 没有拒答。指标 JSON 是准的，summary 可能过度概括；已更新 dataset quality prompt，要求避免无证据的绝对表述。
- LLM judge 成本会上升：本轮 47 次 LLM 调用、87990 tokens、13分22秒。正式跑前必须保留 case-limit 或 fixture smoke。

### 下一轮建议

- 选 20-50 条真实 replay 输出做人审校准，把 LLM judge 的分数和人工判断对齐。
- 把 production-like 方法扩到 Memory Lifecycle v2：长期事实、临时状态、纠错、撤销、冲突更新、敏感信息不写入。
- 做 Retrieval replay 小样本：用真实 Memex 写入这些输入，再问同样问题，对比 fixture expected 和真实 observed。
- 增加跨任务指标：同一输入先产生 card/memory/PKM，再被 retrieval 和 Super Agent 使用，评估数据闭环而不是单点检索。

## 2026-05-13 Production-like Retrieval v3

### 实验目标

v2 已经把生产贴近 Retrieval QA 扩到 12 个用户、78 条输入、47 个任务，但 audit 仍指出两个低风险问题：招聘场景 Lin/Chen 容易混淆，慢病随访的语音错听略生硬。v3 在保留 v2 seed cases 的基础上新增 12 个行业场景，把规模扩到 24 个用户、150 条输入、94 个任务。

### 数据设计

- 继承 v2 的 12 个 seed case，并在生成 v3 时做轻量修正：
  - 慢病随访的语音噪声改为更常见的“授权后半截被吞掉”。
  - 招聘场景在 expected 与 observed 的 filter 中都显式加入 `candidate=Lin` 和 `exclude_candidate=Chen`。
- 新增 12 个行业：跨境电商、机器人实验室、气候风险、博物馆策展、播客制作、专利代理、心理咨询机构运营、高端旅行顾问、开源维护、农业合作社、保险定损、高校实验室管理。
- 数据集：`evals/datasets/production_like_retrieval_v3`
- 生成器：`evals/bin/generate_production_like_retrieval_v3_dataset.dart`

### 抽样与校验过程

1. 生成后统计：24 case、24 users、150 inputs、94 tasks，其中 23 个拒答任务、71 个有来源任务。
2. 用脚本检查所有 `input.source_id` 和 `expected.expected_sources` 都能在 `ground_truth_world` 中找到。
3. 跑 fixture smoke：第一次为 777/779，失败集中在招聘 seed case 的 `retrieval_filter_accuracy`。
4. 根因：v3 生成器修正了 expected filter，但没有同步 fixture observed 的 `applied_filters`。这类派生数据修复必须 expected 和 observed 同步。
5. 修复后复跑 fixture smoke：779/779。
6. 正式 LLM judge + dataset audit：873/873，LLM judge 94/94，audit overall=0.900。

### 结果怎么读

这轮可以证明：

- 数据量翻倍后，规则指标、LLM groundedness judge、citation、abstention、filter 和报告生成仍能稳定工作。
- 从 v2 继承问题到 v3 修复的过程可以展示 harness engineering：先记录 audit 发现，再把问题转成生成器约束，再用 fixture smoke 防止闭环错误进入正式 judge。
- 报告指标更丰富：94 次 LLM judge、330 次 tool call、180165 tokens、23 个拒答任务、71 个 source-grounded 任务。

这轮不能证明：

- 真实 Memex Agent 已经能在 24 用户、150 输入规模下完成写入和检索。observed 仍来自 fixture。
- Retrieval-only 继续扩量的边际价值开始下降；下一步更应该扩到 Memory、PKM、Super Agent 或真实 replay。

### 本轮发现与后续避免

- 复用旧数据集并做派生修复时，必须同步 expected 和 fixture observed。只改 expected 会导致 filter、source 或 answer 断言失败。
- audit overall 维持 0.900，但 input naturalness 从 v2 的 0.900 降到 0.850，说明扩量后需要更多真实口语、真实文档碎片和领域深度，不能只加行业名。
- LLM audit 仍会在 summary 里过度概括。本轮它写“每个 case 均包含一个拒答任务”，但真实计数是 23/24。已进一步更新 `dataset_quality.md`，要求涉及数量时优先引用 `dataset_summary`，不能从样本模式推断全量。
- 气候风险和慢病随访被 audit 标为低风险：前者需要更深的模型参数/历史对比/预警流程，后者需要更丰富的患者反馈和表单设计上下文。
- 成本继续上升：94 次 LLM 调用、180165 tokens、29分03秒。继续扩大 retrieval fixture 前，应明确是否真的能带来新能力信号。

### 下一轮建议

- 不建议继续单纯扩大 retrieval fixture。更有价值的下一轮是 Memory Lifecycle v2 或 Retrieval replay。
- 如果继续做 retrieval，应引入真实文档风格：邮件原文、表格行、会议纪要片段、截图 OCR 错行，而不是人工总结句。
- 为 LLM audit 增加后处理校验：把 audit summary 里的“每个/所有/均”类表述与 metrics 计数做规则交叉检查。

## 2026-05-16 Realistic Full-chain Smoke

### 实验目标

这轮从“更大 fixture”转向“更真实 App 行为”。目标是先用小样本跑通：跨天记录、timeline browse、post comment、schedule aggregation refresh、knowledge insight refresh、wait memory、Super Agent quick query、replay_file 评分和 LLM judge。

### 数据与指标

- 数据集：`evals/datasets/full_chain_realistic_smoke`
- 生成器：`evals/bin/generate_realistic_full_chain_smoke_dataset.dart`
- 完整数据：2 persona、13 record、24 operations。
- 本轮实际运行：`MEMEX_EVAL_CASE_LIMIT=1`，首个 persona 6 record、12 operations。
- 新增指标：
  - `record_operation_coverage`
  - `journey_time_span_coverage`
  - `app_operation_sequence_completeness`
  - `input_channel_diversity`
  - `feature_trigger_coverage`

### 运行结果

- 真实 replay：7分47秒，60 个 task 全部 completed。
- replay_file + LLM judge + dataset audit：24/24 断言通过，overall audit=0.900。
- 成本：58 次 LLM 调用、177 次工具调用、59825 tokens。

### 本轮发现与后续避免

- 本地代理变量会破坏 `flutter_tester` 的 WebSocket 握手。运行 Flutter replay 前取消 `ws_proxy`、`wss_proxy`、`http_proxy`、`https_proxy`，或至少验证最小 Flutter test 能启动。
- Super Agent replay observation 必须带 `source_snippets`。第一次评分中答案文本正确，但 LLM judge 因看不到 memory 证据只给 0.5；修复后把 memory entries 作为 source snippets，groundedness 通过。
- Knowledge Insight 刷新在 PR 105 合入后可在真实 replay 中收敛，但本轮还没有专门断言 state 文件清理和下一次 refresh 的 fresh-run 语义。下一轮要把它变成明确指标。
- 先跑小样本是必要的：单个 persona 已消耗约 60k tokens 和 8 分钟。扩量前要保留 case-limit、timeout、run dir 和详细日志。

## 2026-05-16 Journey Scale v1/v2

### 实验目标

按“8 个用户、每个用户几百条输入”的要求补两轮大规模 fixture 旅程实验。目标是扩大数据形态和指标口径，而不是声称真实 Agent 已能完整处理 2k+ 输入 replay。

### 数据与指标

- 生成器：`evals/bin/generate_journey_scale_iteration_datasets.dart`
- Round 1：`evals/datasets/full_chain_journey_scale_v1`，8 persona、1920 record、64 task。
- Round 2：`evals/datasets/full_chain_journey_scale_v2`，8 persona、2560 record、80 task。
- 新增用户旅程指标：
  - `journey_stage_coverage`
  - `scenario_family_coverage`
  - `persona_specificity_coverage`
  - `cross_day_continuity_coverage`
  - `correction_operation_coverage`
  - `noise_resilience_coverage`
  - `follow_up_query_coverage`

### 运行结果

- Round 1：648/648 断言通过，报告在 `evals/experiments/2026-05-16-full-chain-journey-scale-v1/report.md`。
- Round 2：824/824 断言通过，报告在 `evals/experiments/2026-05-16-full-chain-journey-scale-v2/report.md`。
- 两轮证据等级都是 `fixture_grader_smoke`。它们验证 grader、指标聚合、数据规模和报告结构；真实能力判断仍要抽样接 `serial_full_chain_replay_test.dart` 或 replay_file。

### 本轮发现与后续避免

- 不再复用旧 `journey_medium` 的同质模板；8 个 persona 的职业、城市、项目、家庭/健康/财务/法律边界和偏好冲突都独立建模。
- Fixture 指标要显式声明“观察数据耗时”和 token 都是 fixture observation 的规模估算，不是实际线上 API 消耗。
- 下一轮真实化优先做小抽样 replay：例如每轮选 1-2 persona、每人 20-40 条输入，先验证真实 LocalTaskExecutor/task trace 是否能支撑这些 journey 指标。

## 2026-05-17 8-user Real Replay v1/v2

### 实验目标

把 8 用户 journey 从 fixture 改成真实 full-chain replay。所有观察都来自 `serial_full_chain_replay_test.dart`：`submitInput`、LocalTaskExecutor、card/memory/PKM/schedule/knowledge insight task、Super Agent quick query，再通过 `replay_file` adapter 评分。

### 数据与指标

- 生成器：`evals/bin/generate_real_replay_journey_datasets.dart`
- Round 1：`evals/datasets/full_chain_journey_real_replay_v1`，8 persona、64 record、112 operations、32 task。
- Round 2：`evals/datasets/full_chain_journey_real_replay_v2`，8 persona、128 record、184 operations、48 task。
- replay harness 增加真实 observation 字段：journey stage、scenario family、cross-day link、correction/noise counts、follow-up query count、persona markers。
- replay harness 增加 per-case 熔断：某个操作在本轮等待预算内未收敛时停止该 case 的剩余操作，保留 active/retrying task 摘要并继续下一个用户，避免一个卡住的用户拖垮整轮实验。

### 运行结果

- Round 1：`evals/experiments/2026-05-17-full-chain-real-replay-v1/report.md`
  - 8 用户真实 replay，用时 30分38秒。
  - 153/291 断言通过，pass rate 52.6%。
  - 217130 tokens，158 次 LLM 调用，612 次 tool 调用。
  - 只有 `journey_real_replay_v1_01` 完整跑到 Super Agent；其余 7 个用户首条 record 后 task 未收敛并熔断。
- Round 2：`evals/experiments/2026-05-17-full-chain-real-replay-v2/report.md`
  - 8 用户真实 replay，用时 39分56秒。
  - 182/355 断言通过，pass rate 51.3%。
  - 329236 tokens，257 次 LLM 调用，1284 次 tool 调用。
  - `journey_real_replay_v2_01` 跑完 16 条 record 和 timeline/comment/schedule，但卡在 knowledge insight refresh；其余 7 个用户首条 record 后 task 未收敛。

### 本轮发现与后续避免

- 多用户连续 replay 暴露出真实任务收敛问题：card_agent_task、pkm_agent_task、comment_agent_task、fts_index_update 和 knowledge_insight_task 会停在 processing/pending/retrying。
- 部分 retrying 带 `AgentExceptionCode.loopDetection` 或 `Maximum turns reached (20)`，说明不是单纯超时，还存在 agent 工具调用终止条件问题。
- 扩量前应先修 task 收敛和 loop detection，否则增加用户和输入只会放大同一失败。
- 真实 replay 报告必须保留失败，不再用 fixture 通过率替代真实链路结论。

## Real Replay 等待预算与状态观测

真实 full-chain replay 不能再使用固定 180 秒作为所有后台操作的统一等待窗口。前两轮实测中，单条 record 的正常收敛多在 40-90 秒，knowledge insight 曾需要 106 秒；同时 LLM P95 延迟到 40-52 秒。由于 replay 为了稳定复现把 LocalTaskExecutor 并发降到 1，一个 record 会串行触发多类 LocalTaskExecutor task，固定 3 分钟会把慢但正常的 case 误判成未收敛。

默认策略改成按预计 task 单元动态计算等待时间：

- LLM real replay 默认每个 task 单元给 90 秒。
- `record` 预计 10 个 task 单元，默认最多等 15 分钟。
- `post_comment` 预计 3 个 task 单元，默认等 4 分半。
- `refresh_schedule_aggregation` 预计 2 个 task 单元，默认等 3 分钟。
- `refresh_knowledge_insights` 预计 10 个 task 单元，默认最多等 15 分钟。
- 如需固定窗口，可继续用 `MEMEX_EVAL_TASK_TIMEOUT_SECONDS` 覆盖。
- 如需调动态预算，可用 `MEMEX_EVAL_TASK_UNIT_TIMEOUT_SECONDS` 和 `MEMEX_EVAL_TASK_TIMEOUT_MAX_SECONDS`。

长实验要定期检查实验状态，而不是只等最终报告。`serial_full_chain_replay_test.dart` 会按 `MEMEX_EVAL_STATUS_INTERVAL_SECONDS`，默认 30 秒，输出 active task 摘要，并写入当前 run 目录的 `status.json`。中途如果看到同一 task 长时间停在 `processing`，要区分两类情况：普通慢响应可以继续等；`retrying` 或带 `loopDetection` / `Maximum turns reached` 的 processing 则应按真实 agent 终止条件问题处理，不能简单归因于 timeout 太短。

### 2026-05-17 v2 Dynamic-timeout Rerun

- Run：`2026-05-17-full-chain-real-replay-v2-dynamic-timeout`
- 等待策略：dynamic，`task_unit_timeout_seconds=90`，`max_operation_timeout_seconds=900`，`status_interval_seconds=30`。
- Replay 结果：8 case 全部执行到 case 级终态，用时 3小时29分29秒；Flutter test 通过。
- 评分结果：181/355 断言通过，pass rate 51.0%，证据等级 `real_replay`。
- 成本：947245 tokens，710 次 LLM 调用，3942 次 tool 调用，P95 LLM 延迟 100000ms。
- 对比 180 秒固定窗口：第一用户完整跑到 follow-up，第二用户从 1 条 record 推进到 4 条，部分 card 慢尾在 4-7 分钟后才返回；因此 180 秒确实偏小。
- 但主结论没有变：多数失败不是单纯 timeout。多个用户在 15 分钟窗口内仍停在 `card_agent_task` / `pkm_agent_task` 的 `processing` / `retrying`，错误集中为 `AgentExceptionCode.loopDetection` / `Maximum turns reached`。后续应优先修 agent 工具循环和终止条件，再继续扩量。
