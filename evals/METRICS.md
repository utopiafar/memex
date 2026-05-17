# Memex Agent Eval 指标体系

## 结论

Memex 的评估应该按用户旅程组织，而不是只按内部模块组织。内部模块可以单独定位问题，但指标设计要从真实用户如何记录、沉淀、回看、追问、行动出发。

推荐保留两层：

- 模块小实验：小样本、快跑、定位具体能力回归。
- 全链路旅程实验：串行模拟单用户多天/多周操作，看状态是否能跨输入、跨任务、跨查询稳定流转。

评估结论必须同时声明证据等级：

- `fixture_grader_smoke` 只能说明 grader、schema、报告和指标聚合可用。
- `audited_synthetic_fixture` 可以作为小规模合成回归基线，但需要抽样 replay 校准。
- `real_replay` 才能用于判断真实 Agent 行为、任务收敛和成本。

LLM judge 只用于语义质量，例如 groundedness、completeness、unsupported claims 和数据自然度；结构合法性、source id、tool call、时间、任务状态、token/latency 仍然必须规则判。

数据审计抽样必须覆盖场景 family，不能只取文件前 N 条；否则 challenge set 容易只审到一个类别，低估或误判整体数据质量。

## 用户旅程指标总表

| 用户旅程 | 对应模块实验 | 真实数据扩充方向 | 核心指标 |
| --- | --- | --- | --- |
| 随手记录 | Card 抽取 | 中文口语、错别字、相对时间、多人名、地点省略、同一句里混合任务/事件/感受/咨询 | schema 合法率、card type accuracy、time parse accuracy、entity recall、hallucinated field absence、input-to-card latency |
| 形成长期记忆 | Memory | 长期偏好、临时状态、生活习惯、健康/饮食限制、冲突更新、撤销/纠正、重复表达 | must-write recall、write precision、conflict handling、duplicate rate、temporal validity、source grounding、sensitive over-write absence |
| 整理知识与项目 | PKM | 项目周报、会议纪要、读书/学习笔记、旅行计划、购物调研、个人复盘 | path accuracy、content preservation、source grounding、merge/split quality、prohibited content absence、update freshness |
| 回看与检索 | Retrieval QA | 上次、最近、某人、某项目、某时间段、跨 card + memory + PKM 的组合查询、证据不足查询 | hit@1/3/5、MRR、recall@k、filter accuracy、citation coverage、grounded answer rate、abstention accuracy |
| 和 Super Agent 对话 | Super Agent QA | 个性化建议、基于记忆的提醒、跨来源总结、矛盾偏好解释、只读问答、需要澄清的含糊问题 | answer completeness、groundedness、unsupported claim absence、uncertainty calibration、read-only compliance、tool selection accuracy |
| 日程与提醒刷新 | Schedule Router | 新增/修改/取消日程、周期事件、跨时区、临近提醒、只影响 note 不影响 schedule 的输入 | refresh action accuracy、refresh precision/recall、missed refresh absence、unnecessary refresh absence、tool args accuracy、duplicate refresh rate |
| 工具调用与路由 | Router / Tool | 搜索记忆、读卡片、写 PKM、更新记忆、请求日程刷新、禁止写入的只读场景 | router label accuracy、tool selection accuracy、tool args accuracy、prohibited tool absence、tool-call minimality、trace completeness |
| 成本与稳定性 | Cost / Trace | 长输入、多轮输入、低价值闲聊、工具失败重试、模型慢响应、任务队列积压 | total token budget、p95 latency、tool call budget、task completion status、retry rate、failed task rate、queue idle time |
| 单用户多天使用 | Full-chain replay | 1 个 persona 连续几十到几百条输入，覆盖工作/生活/临时情绪/咨询/纠正/追问 | journey pass rate、state consistency、memory carryover、retrieval after write、answer after conflict、cost per input、end-to-end latency |
| App 行为仿真 | Realistic replay | record、timeline browse、comment、schedule refresh、insight refresh、wait memory、Super Agent quick query 串行组合 | record operation coverage、journey time span coverage、app operation sequence completeness、input channel diversity、feature trigger coverage、journey stage coverage、scenario family coverage、cross-day continuity coverage、correction/noise/follow-up coverage |

`production_like_retrieval_v3` 是当前 Retrieval QA 扩充样板：24 个用户、150 条输入、94 个任务，覆盖多来源答案、旧记录/新记录、相似实体干扰、隐私/安全边界和证据不足拒答。v3 证明 retrieval fixture 可以规模化到更丰富的报告指标，但也暴露出 input naturalness 会随扩量下降；后续扩展 Memory、PKM、Super Agent 时，应沿用“按职业场景单独设计 source 结构和噪声”的方式，而不是批量模板替换。

## 场景扩充建议

### 1. 随手记录

真实用户不会只说“帮我记录一个会议”。数据应该加入：

- 半句话和省略：例如“Jason 那个预算周四三点继续”。
- 复合输入：一条里既有安排，也有情绪和背景闲聊。
- 纠错输入：例如“不是周四，是周五下午三点”。
- 低价值输入：例如“今天有点烦，先别管”，避免过度结构化。

优先指标：时间解析、card 类型、实体召回、字段幻觉控制。

### 2. 记忆沉淀

Memory 最贴近产品价值，也最容易误伤。数据应覆盖：

- 长期事实：饮食禁忌、工作习惯、提醒偏好、家庭关系。
- 临时事实：今天心情、临时地点、一次性任务。
- 冲突事实：旧偏好被明确覆盖，或者只在特定时间段有效。
- 重复表达：用户多次用不同说法表达同一偏好。

优先指标：must-write recall、write precision、conflict handling、duplicate rate、source grounding。

### 3. 回看检索

检索不能只测向量命中。真实问题常带时间、人、项目和类型约束：

- 时间过滤：上周、上次、最近一次、5 月初。
- 人物过滤：和 Jason、和爸妈、和某项目 owner。
- 类型过滤：只看会议、只看购买决策、只看饮食偏好。
- 证据不足：没有记录时应该说不确定，而不是编。

优先指标：hit@k、MRR、recall@k、filter accuracy、citation coverage、abstention accuracy。

### 4. Super Agent 问答

Super Agent 应该从“会回答”升级到“会带边界地行动”：

- 只读问答不能调用写入工具。
- 个性化建议要引用来源或明确基于记忆。
- 矛盾记忆要使用最新有效事实，并能解释冲突。
- 信息不足时先澄清，不能强行给结论。

优先指标：groundedness、completeness、unsupported claim absence、read-only compliance、tool selection accuracy。

### 5. 日程与提醒

Schedule router 要用 confusion matrix 看：

- true skip：闲聊、普通 note、临时感受。
- true dirty：修改已有日程但不需要立刻全量刷新。
- true refresh：新增关键日程、取消/改期、影响今日/明日安排。

优先指标：refresh action accuracy、missed refresh absence、unnecessary refresh absence、tool args accuracy。

### 6. 全链路旅程

全链路不建议先做多用户并发。更贴近现有产品的是单用户串行：

- 一个 persona 连续多天输入，先写入，再等待任务收敛，再追问。
- 输入类型混合工作、生活、闲聊、咨询、纠错和偏好变化。
- 每个关键节点都产出 observations：card、memory、PKM、tool trace、Super Agent answer。

优先指标：journey pass rate、memory carryover、retrieval after write、answer after conflict、task completion status、cost per input。

### 7. App 行为仿真

真实 replay 不能只把多条输入塞给 `submitInput`。它还应该模拟用户在 App 里自然触发的动作：

- 回看时间线：按时间范围读取卡片，确认记录能够被页面取回。
- 评论卡片：触发 comment / reply 相关链路。
- 手动刷新：触发 schedule aggregation 和 knowledge insight。
- 等待后台任务：每个关键动作后等待 task idle，记录 active/failed/retry。真实 LLM replay 使用按预计 task 单元计算的动态等待预算，并定期输出/落盘 active task 状态，避免把慢响应误判成未收敛。
- 追问：用 Super Agent quick query 检查 memory / card / PKM 写入后的可用性。

优先指标：record operation coverage、journey time span coverage、app operation sequence completeness、input channel diversity、feature trigger coverage、journey stage coverage、scenario family coverage、persona specificity coverage、cross-day continuity coverage、correction operation coverage、noise resilience coverage、follow-up query coverage。

### 8. 用户旅程细化

8 用户 scale fixture 用来验证“数据集和指标口径”是否能承载更真实的长期使用形态，不等同真实 Agent 能力证明：

- journey stage coverage：输入和操作是否覆盖 capture、card generation、memory write、PKM organize、timeline review、comment correction、schedule refresh、knowledge insight、Super Agent QA。
- scenario family coverage：每个 persona 是否覆盖工作项目、日程、家庭照护、健康、财务、旅行、家庭行政、学习、社交关系、法律/合规、突发事件、噪声和纠错等场景族。
- cross-day continuity coverage：跨天输入是否有复盘、回看、后续行动和前文引用。
- correction operation coverage：用户明确修正旧偏好、覆盖旧事实或更新边界的样本是否足够。
- noise resilience coverage：临时情绪、一次性尝试、OCR 不确定内容是否足够，并通过 must-not-write 验证不长期化。
- follow-up query coverage：回看后继续追问、要求跨域总结或要求证据不足说明的闭环是否足够。
- persona specificity coverage：trace 摘要是否保留职业、城市、项目和领域锚点，避免 8 个用户只是替换姓名。

## 数据量分层

| 层级 | 用途 | 建议规模 |
| --- | --- | --- |
| 模块 smoke | 每次改 prompt / grader / 小逻辑后快速定位 | 每模块 1-5 cases |
| 模块 medium | 看模块稳定性和错误分布 | 每模块 30-80 cases |
| 单用户 full-chain smoke | 验证真实链路能跑通 | 1 persona，5-20 条输入 |
| 单用户 full-chain journey | 贴近真实使用 | 8-12 persona，每人 200-350 条输入 |
| 回归大集 | 重要版本前跑 | 20+ persona，总输入 2000+，但仍建议串行或限速 |

## 读报告时的优先级

先看“失败是否影响产品判断”，再看平均分。比如：

- Memory 写错长期偏好，比普通回答少一个细节严重。
- Schedule 漏刷新，比多刷新一次严重。
- Retrieval 召回错来源但答案碰巧正确，不应算真正通过。
- Token 成本飙升但答案不变，属于隐藏回归。
