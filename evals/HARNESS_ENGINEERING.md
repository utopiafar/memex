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
