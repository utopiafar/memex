import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('searchMemoryPrimaryForTool', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      root = await Directory.systemTemp.createTemp('memex_common_tools_');
      await FileSystemService.init(root.path);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('expands multi-part relationship queries into grounded sub-recalls',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            title: 'MayaA 的职责',
            content: 'MayaA 负责产品评审和体验文案。',
            entityIds: ['MayaA', '产品评审', '体验文案'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            title: '合同付款联系人',
            content: '合同付款现在找 NoorA，发票确认也找 NoorA。LeoA 仅适用于旧项目。',
            entityIds: ['NoorA', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-a',
        query: '产品评审找谁？合同付款和发票确认找谁？',
        limit: 8,
      );
      final contents = results.map((result) => result.atom.content).join('\n');

      expect(contents, contains('MayaA 负责产品评审和体验文案'));
      expect(contents, contains('合同付款现在找 NoorA'));
      expect(
        results.expand((result) => result.atom.evidenceFactIds),
        containsAll(['2026/05/02.md#ts_2', '2026/05/02.md#ts_8']),
      );
    });

    test('prioritizes project owner atoms over generic relationships',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-b',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            title: 'Project Orion A owner',
            content: 'Project Orion A 当前 owner 是 BaoA，在第3轮复盘中确认继续由BaoA负责。',
            entityIds: ['Project Orion A', 'BaoA'],
            evidenceFactIds: ['2026/05/01.md#ts_4', '2026/05/05.md#ts_1'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            title: '合同付款联系人',
            content: '合同付款和发票确认应联系 NoorA，他是唯一负责人。',
            entityIds: ['NoorA', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-b',
        query: 'Project Orion A 当前 owner 是谁？请给依据。',
        limit: 8,
      );

      expect(results, isNotEmpty);
      expect(results.first.atom.type, 'project_context');
      expect(results.first.atom.content, contains('BaoA'));
      expect(
        results.first.atom.evidenceFactIds,
        containsAll(['2026/05/01.md#ts_4', '2026/05/05.md#ts_1']),
      );
    });

    test('prioritizes identity and routine atoms for home routine queries',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-c',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'boundary',
            title: '高敏边界样本',
            content: '高敏边界样本：财务压力复盘只记录情绪和事实，不给投资建议。',
            entityIds: ['高敏边界', '财务压力复盘'],
            evidenceFactIds: [
              '2026/05/26.md#ts_5',
              '2026/05/27.md#ts_7',
              '2026/05/29.md#ts_1',
            ],
          ),
          MemoryPatch(
            op: 'create',
            type: 'identity',
            title: '常驻地',
            content: '用户常驻深圳，是中国大陆，广东省的城市。',
            entityIds: ['深圳', '广东省'],
            evidenceFactIds: ['2026/05/03.md#ts_3'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'routine',
            title: '周三下午安排',
            content: '用户的周三下午通常留给深度工作，不安排评审会。',
            entityIds: ['周三下午', '深度工作', '评审会'],
            evidenceFactIds: ['2026/05/03.md#ts_3'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-c',
        query: '我常驻哪里？周三下午一般怎么安排？',
        limit: 5,
      );
      final topTypes = results.take(2).map((result) => result.atom.type);

      expect(topTypes, containsAll(['identity', 'routine']));
      expect(
        results.take(2).expand((result) => result.atom.evidenceFactIds),
        contains('2026/05/03.md#ts_3'),
      );
    });

    test('returns report background placement as an explicit constraint',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-d',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            title: '项目报告结构',
            content: '项目报告先给最新结论，再列风险、下一步、owner 和证据来源，背景放在最后。',
            entityIds: ['最新结论', '风险', '下一步', 'owner', '证据来源'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-d',
        query: '以后写 Project Orion D 或 Meridian 导出 D 相关技术报告，格式偏好是什么？',
        limit: 8,
      );

      expect(results, isNotEmpty);
      expect(results.first.atom.content, contains('背景放在最后'));
    });

    test('recalls long merged large-eval relationship atoms', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-e',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            title: '职责分工',
            content:
                'NoorB负责当前项目的合同付款和发票确认；付款和发票事宜统一由 NoorB 负责；MayaB、LeoB与NoorB的职责分工明确：MayaB 负责产品评审和体验文案，不负责合同付款；付款与发票事宜由 NoorB 负责。用户在2026-05-22再次确认：MayaB 不负责合同付款；付款和发票还是找 NoorB。',
            entityIds: ['MayaB', 'NoorB', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/05/03.md#ts_2', '2026/06/15.md#ts_4'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-e',
        query: '产品评审找谁？合同付款和发票确认找谁？',
        limit: 8,
      );
      final contents = results.map((result) => result.atom.content).join('\n');

      expect(contents, contains('MayaB 负责产品评审'));
      expect(contents, contains('NoorB'));
      expect(
        results.expand((result) => result.atom.evidenceFactIds),
        contains('2026/05/03.md#ts_2'),
      );
    });

    test('recalls large-eval report preference atoms by Chinese format query',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-f',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            title: '项目报告结构',
            content: '用户偏好项目报告的结构顺序为：先提供最新结论，再列出风险、下一步、owner 和证据来源，最后才放置背景信息。',
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            title: '技术报告规则',
            content:
                '对于涉及 Project Orion B 或 Meridian 导出 B 的问题或回答，需要遵循固定的汇报结构：先最新结论，再给风险、下一步、owner、证据来源。',
            evidenceFactIds: ['2026/05/03.md#ts_7'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-f',
        query: '以后写 Project Orion B 或 Meridian 导出 B 相关技术报告，格式偏好是什么？',
        limit: 8,
      );
      final contents = results.map((result) => result.atom.content).join('\n');

      expect(contents, contains('最新结论'));
      expect(contents, contains('风险'));
      expect(contents, contains('证据来源'));
      expect(
        results.expand((result) => result.atom.evidenceFactIds),
        contains('2026/05/03.md#ts_7'),
      );
    });

    test('prioritizes report-format preference over owner anchor and OCR',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-report-rank',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            title: 'Owner 长上下文锚点',
            content:
                '长上下文锚点：如果很久以后问 Project Orion A 和 Meridian 导出 A 的 owner，请优先用当前 owner，不要使用旧 owner。',
            evidenceFactIds: ['2026/05/03.md#ts_5'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            title: 'OCR 偏好',
            content:
                '对于 OCR 解析的文本，如 Project Orion A 的灰度风险列表，Agent 应直接使用给定文本，而不评估 OCR 本身。',
            evidenceFactIds: ['2026/06/03.md#ts_6'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'preference',
            title: '报告结构',
            content:
                '涉及 Project Orion A 或 Meridian 导出 A 的协作回答，有长期偏好：顺序为先最新结论，再给风险、下一步、owner、证据来源。',
            evidenceFactIds: ['2026/05/01.md#ts_2'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-report-rank',
        query: '以后写 Project Orion A 或 Meridian 导出 A 相关技术报告，格式偏好是什么？',
        limit: 5,
      );

      expect(results, isNotEmpty);
      expect(results.first.atom.title, '报告结构');
      expect(
          results.first.atom.evidenceFactIds, contains('2026/05/01.md#ts_2'));
    });

    test('recalls location stored as preference plus routine atom', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-g',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            title: '常驻城市',
            content: '用户常驻上海。',
            evidenceFactIds: ['2026/05/02.md#ts_3'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'routine',
            title: '周四上午安排',
            content: '周四上午通常留给深度工作，不安排评审会。 保留用户原词约束：上海。',
            evidenceFactIds: ['2026/05/02.md#ts_3'],
          ),
        ],
      );

      final results = await searchMemoryPrimaryForTool(
        userId: 'user-g',
        query: '我常驻哪里？周四上午 一般怎么安排？',
        limit: 8,
      );
      final contents = results.map((result) => result.atom.content).join('\n');

      expect(contents, contains('上海'));
      expect(contents, contains('周四上午'));
      expect(contents, contains('深度工作'));
    });
  });
}
