import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryPrimaryService', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      root = await Directory.systemTemp.createTemp('memex_memory_primary_');
      await FileSystemService.init(root.path);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('creates memory atoms and deduplicates exact content', () async {
      final changed = await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            title: 'Launch',
            content: 'User is preparing Project Atlas launch.',
            entityIds: ['Project Atlas'],
            evidenceFactIds: ['2026/06/09.md#ts_1'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            title: 'Launch',
            content: 'User is preparing Project Atlas launch.',
            entityIds: ['Atlas'],
            evidenceFactIds: ['2026/06/09.md#ts_2'],
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(changed, hasLength(2));
      expect(atoms, hasLength(1));
      expect(atoms.single.id, 'mem_101');
      expect(atoms.single.entityIds, containsAll(['Project Atlas', 'Atlas']));
      expect(
        atoms.single.evidenceFactIds,
        containsAll(['2026/06/09.md#ts_1', '2026/06/09.md#ts_2']),
      );
    });

    test('updates and soft deletes atoms', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: 'User prefers concise reports.',
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_101',
            type: 'interaction_preference',
            content: 'User prefers concise Chinese technical reports.',
            evidenceFactIds: ['2026/06/09.md#ts_3'],
          ),
          MemoryPatch(op: 'delete', memoryId: 'mem_101'),
        ],
      );

      final atoms = await MemoryPrimaryService.instance.listAtoms('user-a');
      final active =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.status, MemoryAtomStatus.deleted);
      expect(active, isEmpty);
    });

    test('updates preserve explicit report terms from previous patches',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户希望技术报告先写结论和风险。 保留用户原词偏好：影响面。',
            attributes: {
              'preserved_report_terms': ['影响面'],
            },
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_101',
            type: 'preference',
            content: '用户希望技术报告先写结论和风险，保留验收依据。',
            attributes: {
              'preserved_report_terms': ['必要证据'],
            },
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('影响面'));
      expect(atoms.single.content, contains('必要证据'));
      expect(
        atoms.single.attributes['preserved_report_terms'],
        containsAll(['影响面', '必要证据']),
      );
    });

    test('updates keep report terms that were already present in content',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            content: '用户希望技术报告先给结论、风险和下一步，行动项按 owner 和截止时间拆开。',
            attributes: {
              'preserved_report_terms': ['截止时间'],
            },
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_101',
            type: 'interaction_preference',
            content: '用户希望技术报告先给结论和风险，背景后置。',
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('截止时间'));
      expect(
        atoms.single.attributes['preserved_report_terms'],
        contains('截止时间'),
      );
    });

    test('creates append preserved report terms from attributes', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            content: '用户希望技术报告先给结论和风险。',
            attributes: {
              'preserved_report_terms': ['影响面', '证据来源'],
            },
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('影响面'));
      expect(atoms.single.content, contains('证据来源'));
    });

    test('creates append preserved personal terms from attributes', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'boundary',
            content: '用户晚上通常不安排高强度会议。',
            attributes: {
              'preserved_personal_terms': ['九点后'],
            },
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('九点后'));
      expect(
        atoms.single.attributes['preserved_personal_terms'],
        contains('九点后'),
      );
    });

    test('duplicate creates append newly preserved report terms', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            content: '用户希望技术报告先给结论和风险。',
            attributes: {
              'preserved_report_terms': ['影响面'],
            },
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'interaction_preference',
            content: '用户希望技术报告先给结论和风险。',
            attributes: {
              'preserved_report_terms': ['证据来源'],
            },
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms, hasLength(1));
      expect(atoms.single.content, contains('影响面'));
      expect(atoms.single.content, contains('证据来源'));
      expect(
        atoms.single.attributes['preserved_report_terms'],
        containsAll(['影响面', '证据来源']),
      );
    });

    test('superseding report memories inherits preserved terms', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户希望技术报告先写结论和风险，涉及客户影响时单独列出影响面。',
            attributes: {
              'preserved_report_terms': ['影响面'],
            },
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户纠正报告风格：先写结论和风险，并保留必要证据。',
            supersedesMemoryIds: ['mem_101'],
            attributes: {
              'preserved_report_terms': ['必要证据'],
            },
          ),
        ],
      );

      final active =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');
      final atoms = await MemoryPrimaryService.instance.listAtoms('user-a');

      expect(atoms.first.status, MemoryAtomStatus.superseded);
      expect(active.single.content, contains('影响面'));
      expect(active.single.content, contains('必要证据'));
      expect(
        active.single.attributes['preserved_report_terms'],
        containsAll(['影响面', '必要证据']),
      );
    });

    test('searchMemory recalls by lexical/entity match with evidence',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'User is coordinating Project Atlas with Ming.',
            entityIds: ['Project Atlas', 'Ming'],
            evidenceFactIds: ['2026/06/09.md#ts_4'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: 'User dislikes cilantro.',
            entityIds: ['cilantro'],
          ),
        ],
      );

      final results = await MemoryPrimaryService.instance.searchMemory(
        userId: 'user-a',
        query: 'Atlas 项目和 Ming 的上下文',
      );

      expect(results, isNotEmpty);
      expect(results.first.atom.id, 'mem_101');
      expect(results.first.reasons, contains('entity_match'));
      expect(results.first.atom.evidenceFactIds, ['2026/06/09.md#ts_4']);
    });

    test('searchMemory recalls Chinese report-style preference queries',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户偏好在看技术或项目报告时，先给出结论、风险和下一步，背景放后面。',
            attributes: {
              'preserved_report_terms': ['结论', '风险'],
            },
          ),
        ],
      );

      final results = await MemoryPrimaryService.instance.searchMemory(
        userId: 'user-a',
        query: '我希望技术报告怎么写？',
      );

      expect(results, isNotEmpty);
      expect(results.first.atom.content, contains('结论'));
      expect(results.first.atom.content, contains('风险'));
      expect(results.first.reasons, contains('lexical_match'));
    });

    test('relationship updates preserve non-conflicting responsibilities',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 负责产品评审和体验文案；合同付款以前找 LeoA。',
            entityIds: ['MayaA', 'LeoA'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_101',
            type: 'relationship',
            content: 'MayaA 不负责合同付款。合同付款和发票确认仍由 NoorA 负责。',
            entityIds: ['MayaA', 'NoorA', '合同付款'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('MayaA 负责产品评审和体验文案'));
      expect(atoms.single.content, contains('MayaA 不负责合同付款'));
      expect(atoms.single.content, isNot(contains('合同付款以前找 LeoA')));
    });

    test('relationship superseding creates preserve non-conflicting scopes',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 负责产品评审和体验文案；合同付款以前找 LeoA。',
            entityIds: ['MayaA', 'LeoA', '产品评审', '体验文案'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 不负责合同付款；付款和发票还是找 NoorA。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
            supersedesMemoryIds: ['mem_101'],
          ),
        ],
      );

      final atoms = await MemoryPrimaryService.instance.listAtoms('user-a');
      final active = atoms.where((atom) => atom.isActive).toList();

      expect(active, hasLength(1));
      expect(active.single.content, contains('MayaA 负责产品评审和体验文案'));
      expect(active.single.content, contains('MayaA 不负责合同付款'));
      expect(active.single.content, contains('NoorA'));
      expect(active.single.content, isNot(contains('合同付款以前找 LeoA')));
    });

    test('relationship preservation splits mixed positive and negative clauses',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 负责产品评审和体验文案，但不负责合同付款；付款和发票确认仍由 NoorA 负责。',
            entityIds: ['MayaA', 'NoorA', '产品评审', '体验文案', '合同付款'],
            evidenceFactIds: ['2026/05/09.md#ts_2'],
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_101',
            type: 'relationship',
            content: '付款和发票事宜仍然由 NoorA 负责；MayaA 不负责合同付款。该职责分工再次得到补充确认。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/06/26.md#ts_4'],
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('MayaA 负责产品评审和体验文案'));
      expect(atoms.single.content, contains('MayaA 不负责合同付款'));
      expect(atoms.single.content, contains('NoorA'));
      expect(atoms.single.content, isNot(contains('合同付款以前找 LeoA')));
    });

    test('relationship creates without supersedes merge by shared actor',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 的职责是产品评审和体验文案。',
            entityIds: ['MayaA', '产品评审', '体验文案'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 不负责合同付款；付款和发票还是找 NoorA。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms, hasLength(1));
      expect(atoms.single.content, contains('MayaA 的职责是产品评审和体验文案'));
      expect(atoms.single.content, contains('MayaA 不负责合同付款'));
      expect(atoms.single.content, contains('NoorA'));
      expect(
        atoms.single.evidenceFactIds,
        containsAll(['2026/05/02.md#ts_2', '2026/05/02.md#ts_8']),
      );
    });

    test('relationship-like other updates preserve positive responsibilities',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            memoryId: 'mem_106',
            type: 'relationship',
            content: 'MayaA 负责产品评审和体验文案，不负责合同付款与发票确认。合同付款与发票确认事务的固定联系人为 NoorA。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
        ],
      );

      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_106',
            type: 'other',
            content: 'MayaA 不负责合同付款；付款和发票还是找 NoorA。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
          MemoryPatch(
            op: 'update',
            memoryId: 'mem_106',
            type: 'relationship',
            content: '付款和发票由 NoorA 负责；MayaA 不负责合同付款。',
            entityIds: ['MayaA', 'NoorA', '合同付款', '发票'],
            evidenceFactIds: ['2026/05/03.md#ts_2'],
          ),
        ],
      );

      final atoms =
          await MemoryPrimaryService.instance.listActiveAtoms('user-a');

      expect(atoms.single.content, contains('MayaA 负责产品评审和体验文案'));
      expect(atoms.single.content, contains('NoorA'));
      expect(atoms.single.content, contains('MayaA 不负责合同付款'));
    });
  });
}
