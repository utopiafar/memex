import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/card_insight_agent/card_insight_agent.dart';
import 'package:memex/data/services/related_facts_service.dart';

void main() {
  group('CardInsightAgent', () {
    test('uses deterministic draft by default', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/01.md#ts_1',
        contentText: 'Project Atlas owner 是 Ming，需要补证据来源。',
        card: null,
        relatedFacts: const [
          RelatedFactCandidate(
            factId: '2026/05/01.md#ts_0',
            title: 'Project Atlas 准备',
            snippet: 'Project Atlas 进入灰度准备。',
            source: 'project_anchor',
            lexicalScore: 1,
            vectorScore: 0,
            recencyScore: 1,
            entityScore: 1,
            anchorScore: 1,
            totalScore: 1,
          ),
        ],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('Project Atlas'));
      expect(draft.summary, contains('Ming'));
      expect(draft.text, contains('意义'));
      expect(draft.text, contains('相关上下文'));
      expect(draft.relatedFactIds, ['2026/05/01.md#ts_0']);
    });

    test('keeps memory atom ids out of related fact ids', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/01.md#ts_2',
        contentText: '高敏边界样本：只记录事实和情绪，不给确定性投资建议。',
        card: null,
        relatedFacts: const [
          RelatedFactCandidate(
            factId: 'mem_114',
            title: '财务压力边界',
            snippet: '只记录情绪和事实，不提供确定性投资建议。',
            source: 'memory_evidence',
            lexicalScore: 1,
            vectorScore: 1,
            recencyScore: 1,
            entityScore: 1,
            memoryEvidenceScore: 1,
            totalScore: 1,
          ),
          RelatedFactCandidate(
            factId: '2026/05/01.md#ts_1',
            title: '高敏边界记录',
            snippet: '财务压力复盘只记录事实和情绪。',
            source: 'hybrid_text',
            lexicalScore: 1,
            vectorScore: 1,
            recencyScore: 1,
            entityScore: 1,
            totalScore: 1,
          ),
        ],
      );

      expect(draft.relatedFactIds, ['2026/05/01.md#ts_1']);
      expect(draft.relatedMemoryIds, ['mem_114']);
    });

    test('preserves no-action boundary in deterministic draft', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/02.md#ts_1',
        contentText: '反思不是行动：以后早点准备周报，但现在不要创建提醒或行动，只记录这个反思。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('不应自动创建提醒或行动'));
      expect(draft.text, contains('降级为复盘信号'));
      expect(draft.text, contains('执行授权分开保存'));
    });

    test('turns scheduling preference into an actionable rule', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/01.md#ts_3',
        contentText: '个人长期偏好：我常驻杭州，周三下午通常留给深度工作，不安排评审会。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('可复用偏好'));
      expect(draft.text, contains('日程协作偏好'));
      expect(draft.text, contains('固定时段'));
      expect(draft.text, contains('保护用户明确保留的时间块'));
    });

    test('keeps report format preference separate from scheduling preference',
        () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/02.md#ts_7',
        contentText: '报告偏好：项目报告先给最新结论，再列风险、下一步、owner 和证据来源，背景放在最后。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.text, contains('输出格式偏好'));
      expect(draft.text, contains('最新结论'));
      expect(draft.text, contains('Owner'));
      expect(draft.text, isNot(contains('固定时段')));
      expect(draft.text, isNot(contains('排期')));
    });

    test('adds synthesis for repeated report format confirmation', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/04.md#ts_1',
        contentText:
            '长期协作偏好重复确认：涉及 Project Orion A 或 Meridian 导出 A，回答要先最新结论，再给风险、下一步、owner、证据来源。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.text, contains('重复确认'));
      expect(draft.text, contains('不是新的项目状态'));
      expect(draft.text, contains('优先级和置信度'));
      expect(draft.text, contains('确认后的栏目顺序'));
      expect(draft.text, isNot(contains('固定时段')));
    });

    test('adds routing synthesis for relationship boundaries', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/06.md#ts_6',
        contentText: '关系补充：MayaA 不负责合同付款；付款和发票还是找 NoorA。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.text, contains('负向排除'));
      expect(draft.text, contains('正向联系人'));
      expect(draft.text, contains('防误答边界'));
      expect(draft.text, isNot(contains('LeoA')));
    });

    test('does not over-expand project status into payment context', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/02.md#ts_1',
        contentText: 'Project Orion A 进入灰度准备，早期我误记 AlexA 负责验收，风险集中在回滚演练。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('项目状态信号'));
      expect(draft.text, contains('负责人、验收风险或恢复口径'));
      expect(draft.text, contains('下一步'));
      expect(draft.text, isNot(contains('付款')));
      expect(draft.text, isNot(contains('发票')));
    });

    test('adds specific synthesis for failure recovery alignment', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/03.md#ts_1',
        contentText:
            '问题式记录：我上次是不是说过 Meridian 导出 A 的失败恢复要和 Project Orion A 的回滚演练口径一致？这句话要作为事实保留。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.text, contains('跨项目一致性约束'));
      expect(draft.text, contains('失败恢复'));
      expect(draft.text, contains('回滚演练'));
    });

    test('keeps parsed project risk text actionable', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/03.md#ts_4',
        contentText:
            '已解析截图上下文：OCR 文字显示 Project Orion A 的灰度风险列表，Agent 只需要使用这段已给定文本，不评估 OCR 本身。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('已解析文本证据'));
      expect(draft.text, contains('项目风险清单证据'));
      expect(draft.text, contains('下一步'));
      expect(draft.text, contains('灰度风险追踪'));
      expect(draft.text, contains('风险清单来源'));
      expect(draft.text, contains('重新评估截图或 OCR 本身'));
    });

    test('avoids forbidden stable-memory terms for noise records', () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/02.md#ts_4',
        contentText: '临时噪声：今天只是想喝临时奶茶，晚上住短期酒店，路上看到网页广告截图；这些都不要长期化。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('低信号临时记录'));
      expect(draft.text, contains('稳定偏好'));
      expect(draft.text, isNot(contains('长期偏好')));
    });

    test('preserves sensitive-domain boundary in deterministic draft',
        () async {
      final draft = await CardInsightAgent.generate(
        userId: 'user-a',
        factId: '2026/05/02.md#ts_2',
        contentText: '高敏边界样本：这是一条财务压力复盘，只记录情绪和事实，不要给确定性投资建议或税务结论。',
        card: null,
        relatedFacts: const [],
      );

      expect(draft.fallback, isTrue);
      expect(draft.summary, contains('避免给确定性建议'));
      expect(draft.text, contains('安全使用规则'));
      expect(draft.text, contains('事实、情绪和不确定性'));
      expect(draft.text, contains('保持边界'));
    });
  });
}
