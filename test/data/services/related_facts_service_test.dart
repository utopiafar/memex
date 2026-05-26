import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/related_facts_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'related_user';
  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('memex_related_facts_');
    await FileSystemService.init(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'returns lexically related fact candidates and excludes current fact',
    () async {
      const relatedFactId = '2026/05/20.md#ts_1';
      const unrelatedFactId = '2026/05/20.md#ts_2';
      const currentFactId = '2026/05/21.md#ts_1';

      await FileSystemService.instance.appendToDailyFactFile(
        userId,
        DateTime(2026, 5, 20),
        '## <id:ts_1> 09:00:00 "{}"\n\n论文开题和赵老师反馈：需要重写研究问题。\n',
      );
      await FileSystemService.instance.appendToDailyFactFile(
        userId,
        DateTime(2026, 5, 20),
        '## <id:ts_2> 10:00:00 "{}"\n\n晚上买了牛奶和面包。\n',
      );
      await FileSystemService.instance.appendToDailyFactFile(
        userId,
        DateTime(2026, 5, 21),
        '## <id:ts_1> 11:00:00 "{}"\n\n论文开题材料今天继续改。\n',
      );

      await FileSystemService.instance.safeWriteCardFile(
        userId,
        relatedFactId,
        const CardData(
          factId: relatedFactId,
          timestamp: 1779238800,
          status: 'completed',
          title: '论文开题反馈',
          tags: ['论文'],
          uiConfigs: [],
        ),
      );
      await FileSystemService.instance.safeWriteCardFile(
        userId,
        unrelatedFactId,
        const CardData(
          factId: unrelatedFactId,
          timestamp: 1779242400,
          status: 'completed',
          title: '购物',
          tags: ['生活'],
          uiConfigs: [],
        ),
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: '论文开题材料继续整理，赵老师提醒研究问题还要聚焦。',
        limit: 3,
      );

      expect(candidates.map((e) => e.factId), contains(relatedFactId));
      expect(candidates.map((e) => e.factId), isNot(contains(currentFactId)));
      expect(candidates.first.factId, relatedFactId);
      expect(candidates.first.entityScore, greaterThan(0));
      expect(candidates.first.matchedHints, contains('赵老师'));
    },
  );
}
