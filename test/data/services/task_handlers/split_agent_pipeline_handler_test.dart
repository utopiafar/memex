import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/task_handlers/split_agent_pipeline_handler.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'split_pipeline_user';
  const factId = '2026/05/21.md#ts_1';
  late Directory tempRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('memex_split_pipeline_');
    await FileSystemService.init(tempRoot.path);
    await FileSystemService.instance.safeWriteCardFile(
      userId,
      factId,
      const CardData(
        factId: factId,
        timestamp: 1779322800,
        status: 'completed',
        tags: [],
        uiConfigs: [],
      ),
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'shadow mode writes artifact without changing primary card insight',
    () async {
      await FileSystemService.instance.updateCardFile(
        userId,
        factId,
        (card) => card.copyWith(
          insight: const CardInsight(
            text: '旧链路洞察',
            summary: '旧摘要',
            relatedFacts: [RelatedFact(id: '2026/05/20.md#ts_1')],
          ),
        ),
      );

      await processWithSplitAgentPipeline(
        userId: userId,
        factId: factId,
        contentText: '今天继续整理开题报告。',
        writePrimary: false,
      );

      final card = await FileSystemService.instance.readCardFile(
        userId,
        factId,
      );
      expect(card!.insight!.summary, '旧摘要');

      final shadowPath = FileSystemService.instance.getSplitAgentShadowPath(
        userId,
      );
      final shadowFile = File(
        '$shadowPath/${FileSystemService.instance.makeFactIdSafe(factId)}.json',
      );
      expect(await shadowFile.exists(), isTrue);
      final artifact = jsonDecode(await shadowFile.readAsString());
      expect(artifact['write_primary'], isFalse);
      expect(artifact['memory_atom_source_fact_ids_expected'], [factId]);
      expect(artifact['legacy_card_insight']['summary'], '旧摘要');
      expect(artifact['draft']['fallback'], isTrue);
      expect(artifact['comparison']['legacy_insight_present'], isTrue);
      expect(artifact['comparison']['split_insight_present'], isTrue);
    },
  );

  test('primary mode writes card insight', () async {
    await processWithSplitAgentPipeline(
      userId: userId,
      factId: factId,
      contentText: '今天继续整理开题报告。',
      writePrimary: true,
    );

    final card = await FileSystemService.instance.readCardFile(userId, factId);
    expect(card!.insight, isNotNull);
    expect(card.insight!.summary, contains('开题报告'));
  });
}
