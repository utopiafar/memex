import 'package:memex/data/services/task_handlers/card_agent_handler.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:test/test.dart';

void main() {
  group('deriveMemoryPrimaryTitleForTest', () {
    test('preserves raw relationship facts without invented summary words', () {
      final title = deriveMemoryPrimaryTitleForTest(
        '关系记录：MayaA 负责产品评审和体验文案；合同付款以前找 LeoA。',
      );

      expect(title, '关系记录：MayaA 负责产品评审和体验文案；合同付款以前找 LeoA。');
      expect(title, isNot(contains('职责说明')));
      expect(title, isNot(contains('联系人信息更新')));
    });

    test('keeps question-style facts as faithful titles', () {
      final title = deriveMemoryPrimaryTitleForTest(
        '问题式记录：我上次是不是说过 Meridian 导出 A 的失败恢复要和 Project Orion A 的回滚演练口径一致？这句话要作为事实保留。',
      );

      expect(title, contains('Meridian 导出 A'));
      expect(title, contains('Project Orion A'));
      expect(title, contains('失败恢复'));
      expect(title, contains('回滚演练'));
      expect(title, contains('事实保留'));
    });

    test('preserves sensitive boundary sample labels', () {
      final title = deriveMemoryPrimaryTitleForTest(
        '高敏边界样本：这是一条财务压力复盘，只记录情绪和事实，不要给确定性投资建议或税务结论。',
      );

      expect(title, startsWith('高敏边界样本：'));
      expect(title, contains('不要给确定性投资建议'));
    });
  });

  group('completeMemoryPrimaryCardForTest', () {
    test('marks fact-like card complete with faithful title and fallback ui',
        () {
      const card = CardData(
        factId: '2026/05/28.md#ts_7',
        timestamp: 1779926400,
        status: 'processing',
        tags: [],
        uiConfigs: [],
        failureReason: 'missing title',
      );

      final completed = completeMemoryPrimaryCardForTest(
        card: card,
        combinedText:
            '长上下文锚点：如果很久以后问 Project Orion E 和 Meridian 导出 E 的 owner，请优先用当前 owner，不要使用旧 owner。',
      );

      expect(completed.status, 'completed');
      expect(completed.title, startsWith('长上下文锚点：'));
      expect(completed.title, contains('Project Orion E'));
      expect(completed.title, contains('Meridian 导出 E'));
      expect(completed.uiConfigs, hasLength(1));
      expect(completed.uiConfigs.single.templateId, 'classic_card');
      expect(completed.uiConfigs.single.data['content'], contains('当前 owner'));
      expect(completed.failureReason, isNull);
    });

    test('preserves existing ui config while repairing status and title', () {
      const card = CardData(
        factId: '2026/05/28.md#ts_8',
        timestamp: 1779926400,
        status: 'processing',
        tags: ['work'],
        title: '',
        uiConfigs: [
          UiConfig(templateId: 'classic_card', data: {'content': 'old'}),
        ],
      );

      final completed = completeMemoryPrimaryCardForTest(
        card: card,
        combinedText: '关系记录：MayaE 是 Meridian 导出 E 的当前 owner。',
      );

      expect(completed.status, 'completed');
      expect(completed.title, '关系记录：MayaE 是 Meridian 导出 E 的当前 owner。');
      expect(completed.uiConfigs.single.data['content'], 'old');
      expect(completed.tags, ['work']);
    });
  });
}
