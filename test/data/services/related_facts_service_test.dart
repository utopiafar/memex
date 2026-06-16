import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/data/services/related_facts_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RelatedFactsService', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      root = await Directory.systemTemp.createTemp('memex_related_facts_');
      await FileSystemService.init(root.path);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('prioritizes Memory Primary evidence as related fact anchors',
        () async {
      const userId = 'user-a';
      const anchorFactId = '2026/05/01.md#ts_1';
      const currentFactId = '2026/05/04.md#ts_4';

      await _writeFact(
        userId: userId,
        factId: anchorFactId,
        time: DateTime(2026, 5, 1, 9),
        content: 'Project Atlas 这周进入灰度准备，Ming 负责验收口径，我负责风险点中文短报告。',
      );
      await _writeFact(
        userId: userId,
        factId: '2026/05/02.md#ts_1',
        time: DateTime(2026, 5, 2, 10),
        content: 'Project Atlas 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: userId,
        sourceAgent: 'test',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Atlas 于 2026 年 5 月初进入灰度准备阶段。',
            entityIds: ['Project Atlas'],
            evidenceFactIds: [anchorFactId],
          ),
        ],
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: 'Project Atlas 客服 FAQ 需要增加导出失败恢复和灰度回滚章节。',
        limit: 2,
      );

      expect(candidates.map((candidate) => candidate.factId),
          contains(anchorFactId));
      final anchor = candidates.firstWhere(
        (candidate) => candidate.factId == anchorFactId,
      );
      expect(anchor.source, 'memory_evidence');
      expect(anchor.memoryEvidenceScore, 1.0);
    });

    test('keeps earliest same-entity facts as project anchors', () async {
      const userId = 'user-a';
      const anchorFactId = '2026/05/01.md#ts_1';
      const currentFactId = '2026/05/04.md#ts_4';

      await _writeFact(
        userId: userId,
        factId: anchorFactId,
        time: DateTime(2026, 5, 1, 9),
        content: 'Project Atlas 这周进入灰度准备，Jason 负责验收口径，我负责风险点中文短报告。',
      );
      await _writeFact(
        userId: userId,
        factId: '2026/05/02.md#ts_1',
        time: DateTime(2026, 5, 2, 10),
        content: 'Project Atlas 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );
      await _writeFact(
        userId: userId,
        factId: '2026/05/03.md#ts_1',
        time: DateTime(2026, 5, 3, 10),
        content: '临时状态：这周我在外地开会，别把它当成长期作息。',
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: 'Project Atlas 客服 FAQ 需要增加导出失败恢复和灰度回滚章节。',
        limit: 2,
      );

      expect(
        candidates.map((candidate) => candidate.factId),
        contains(anchorFactId),
      );
      final anchor = candidates.firstWhere(
        (candidate) => candidate.factId == anchorFactId,
      );
      expect(anchor.source, 'project_anchor');
      expect(anchor.anchorScore, 1.0);
      expect(candidates.first.factId, anchorFactId);
    });

    test('extracts mixed-language project names for anchors', () async {
      const userId = 'user-a';
      const anchorFactId = '2026/05/02.md#ts_1';
      const currentFactId = '2026/05/05.md#ts_4';

      await _writeFact(
        userId: userId,
        factId: anchorFactId,
        time: DateTime(2026, 5, 2, 9),
        content: 'Nimbus 迁移 这周进入灰度准备，暂时我记的是 Lina 负责验收口径。',
      );
      await _writeFact(
        userId: userId,
        factId: '2026/05/03.md#ts_1',
        time: DateTime(2026, 5, 3, 12),
        content: 'Nimbus 迁移 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: 'Nimbus 迁移 的客服 FAQ 需要增加导出失败恢复和灰度回滚章节。',
        limit: 2,
      );

      expect(candidates.first.factId, anchorFactId);
      expect(candidates.first.anchorScore, 1.0);
    });

    test('keeps early meeting anchors when repeated project updates compete',
        () async {
      const userId = 'user-a';
      const projectStartFactId = '2026/05/04.md#ts_1';
      const meetingAnchorFactId = '2026/05/05.md#ts_2';
      const ownerCorrectionFactId = '2026/05/06.md#ts_2';
      const currentFactId = '2026/05/09.md#ts_4';

      await _writeFact(
        userId: userId,
        factId: projectStartFactId,
        time: DateTime(2026, 5, 4, 9),
        content: 'SoloKit 发布 这周进入灰度准备，Wei 负责验收口径，我负责风险点中文短报告。',
      );
      await _writeFact(
        userId: userId,
        factId: meetingAnchorFactId,
        time: DateTime(2026, 5, 5, 12),
        content: '会议纪要：SoloKit 发布 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );
      await _writeFact(
        userId: userId,
        factId: ownerCorrectionFactId,
        time: DateTime(2026, 5, 6, 13),
        content: '以这条为准：SoloKit 发布 的导出灰度 owner 是 Rui，之前关于 Wei 负责的说法都覆盖掉。',
      );

      for (final entry in [
        ('2026/05/07.md#ts_4', DateTime(2026, 5, 7, 16)),
        ('2026/05/08.md#ts_4', DateTime(2026, 5, 8, 16)),
        ('2026/05/09.md#ts_1', DateTime(2026, 5, 9, 10)),
        ('2026/05/09.md#ts_2', DateTime(2026, 5, 9, 12)),
      ]) {
        await _writeFact(
          userId: userId,
          factId: entry.$1,
          time: entry.$2,
          content: 'SoloKit 发布 的客服 FAQ 需要增加“导出失败如何恢复”和“灰度期间如何回滚”的两段，Rui 会看最终版。',
        );
      }

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText:
            'SoloKit 发布 的客服 FAQ 需要增加“导出失败如何恢复”和“灰度期间如何回滚”的两段，Rui 会看最终版。',
        limit: 8,
      );

      expect(
        candidates.map((candidate) => candidate.factId),
        containsAll([
          projectStartFactId,
          meetingAnchorFactId,
          ownerCorrectionFactId,
        ]),
      );
      final meetingAnchor = candidates.firstWhere(
        (candidate) => candidate.factId == meetingAnchorFactId,
      );
      expect(meetingAnchor.anchorScore, 1.0);
    });

    test('uses a strong Chinese project name as a single anchor hint',
        () async {
      const userId = 'user-a';
      const anchorFactId = '2026/05/05.md#ts_1';
      const currentFactId = '2026/05/08.md#ts_4';

      await _writeFact(
        userId: userId,
        factId: anchorFactId,
        time: DateTime(2026, 5, 5, 9),
        content: '社区物资协作 这周进入灰度准备，Tara 负责验收口径。',
      );
      await _writeFact(
        userId: userId,
        factId: '2026/05/05.md#ts_2',
        time: DateTime(2026, 5, 5, 12),
        content: '会议纪要：社区物资协作 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: '社区物资协作 的客服 FAQ 需要增加导出失败恢复和灰度回滚章节。',
        limit: 2,
      );

      expect(candidates.first.factId, anchorFactId);
      expect(candidates.first.anchorScore, 1.0);
    });

    test('prioritizes original owner fact when a later record overwrites it',
        () async {
      const userId = 'user-a';
      const originalOwnerFactId = '2026/05/06.md#ts_1';
      const meetingFactId = '2026/05/07.md#ts_2';
      const currentFactId = '2026/05/08.md#ts_2';

      await _writeFact(
        userId: userId,
        factId: originalOwnerFactId,
        time: DateTime(2026, 5, 6, 9),
        content: '烘焙订阅系统 这周进入灰度准备，暂时我记的是 Noah 负责验收口径。',
      );
      await _writeFact(
        userId: userId,
        factId: meetingFactId,
        time: DateTime(2026, 5, 7, 12),
        content: '会议纪要：烘焙订阅系统 的导出链路还缺回滚演练、埋点检查和客服 FAQ。',
      );

      final candidates = await RelatedFactsService.instance.findRelatedFacts(
        userId: userId,
        factId: currentFactId,
        contentText: '以这条为准：烘焙订阅系统 的导出灰度 owner 是 Hao，之前关于 Noah 负责的说法都覆盖掉。',
        limit: 3,
      );

      expect(candidates.map((candidate) => candidate.factId),
          contains(originalOwnerFactId));
      expect(candidates.first.factId, originalOwnerFactId);
      expect(candidates.first.anchorScore, 1.0);
    });
  });
}

Future<void> _writeFact({
  required String userId,
  required String factId,
  required DateTime time,
  required String content,
}) async {
  final fs = FileSystemService.instance;
  final simpleId = fs.extractSimpleFactId(factId);
  await fs.appendToDailyFactFile(
    userId,
    time,
    '## <id:$simpleId> ${_timeString(time)}\n\n$content',
  );
  await fs.safeWriteCardFile(
    userId,
    factId,
    CardData(
      factId: factId,
      timestamp: time.millisecondsSinceEpoch ~/ 1000,
      status: 'completed',
      tags: const ['Project'],
      uiConfigs: const [],
      title: content,
    ),
  );
}

String _timeString(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
