import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/chat_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ChatService current-state answer sanitization', () {
    test('removes stale owner history bullets while preserving current answer',
        () {
      final sanitized =
          ChatService.instance.sanitizeCurrentStateAnswerForTesting(
        '''
**最新结论**：Project Orion 当前导出灰度 owner 是 **Bao**。

**依据**：
- 2026-04-01 初期记录 Alex 负责验收口径（`2026/04/01.md#ts_1`）。
- **2026-04-02 用户明确更正**："以这条为准：Project Orion 的导出灰度 owner 是 Bao，此前相关旧说法已被覆盖。"（`2026/04/02.md#ts_3`）。
- 此后多次风险更新均持续确认 Bao 为 owner。

**补充说明：**
- Cary 仅负责历史数据抽样，不涉及接口验收。
''',
        query: 'Project Orion 当前导出灰度 owner 是谁？',
      );

      expect(sanitized, contains('Bao'));
      expect(sanitized, isNot(contains('Alex 负责验收口径')));
      expect(sanitized, isNot(contains('Cary 仅负责历史数据抽样')));
    });

    test('preserves exact multi-project names from the user query', () {
      final updated = ChatService.instance.ensureProjectNameFromQueryForTesting(
        '对于 Project Orion 和 Meridian 的导出技术报告，先给结论、风险、下一步和证据来源。',
        query: '以后给我写 Project Orion 或 Meridian 导出相关技术报告时，格式偏好是什么？',
      );

      expect(updated, contains('Project Orion'));
      expect(updated, contains('Meridian 导出'));
    });

    test('keeps original user query in Memory Primary search traces', () {
      final args =
          ChatService.instance.augmentMemoryPrimarySearchArgsForTraceForTesting(
        toolName: 'search_memory_primary',
        args: '{"query":"Project Orion A Meridian 技术报告 格式偏好"}',
        originalUserQuery:
            '以后给我写 Project Orion A 或 Meridian 导出 A 相关技术报告时，格式偏好是什么？',
      );

      expect(args, contains('Project Orion A'));
      expect(args, contains('Meridian 导出 A'));
      expect(args, contains('original_user_query'));
    });

    test('preloads Memory Primary recall for relationship and routine asks',
        () {
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '产品评审找谁？合同付款和发票确认找谁？',
        ),
        isTrue,
      );
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '我常驻哪里？周四上午一般怎么安排？',
        ),
        isTrue,
      );
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '随便聊两句今天的天气',
        ),
        isFalse,
      );
    });

    test('removes unsupported owner-history and conflict inferences', () {
      final sanitized =
          ChatService.instance.sanitizeMemoryPrimaryPreferenceAnswerForTesting(
        '''
1. **最新结论**
2. **风险**
3. **下一步**
4. **Owner**：标注当前的负责人（**必须使用当前所有者**，不引用历史旧所有者）
5. **owner** — 使用**当前 owner**，不使用历史 owner
5. **证据来源**

**补充规则**
- **关于 owner**：长期owner，不引用旧 owner。
- 如有信息冲突，优先告知最新结论
''',
        query: '以后写 Project Orion A 或 Meridian 导出 A 相关技术报告，格式偏好是什么？',
      );

      expect(sanitized, contains('**owner** — owner'));
      expect(sanitized, isNot(contains('当前 owner')));
      expect(sanitized, isNot(contains('历史 owner')));
      expect(sanitized, isNot(contains('旧 owner')));
      expect(sanitized, isNot(contains('长期owner')));
      expect(sanitized, isNot(contains('当前所有者')));
      expect(sanitized, isNot(contains('历史旧所有者')));
      expect(sanitized, isNot(contains('信息冲突')));
      expect(sanitized, contains('证据来源'));
    });

    test('keeps report-format answers as fields instead of filled facts', () {
      final sanitized =
          ChatService.instance.sanitizeMemoryPrimaryPreferenceAnswerForTesting(
        '''
根据长期协作偏好，技术报告格式如下：
- **最新结论**：先给出最新结论
- **风险**：遵循此格式可确保信息清晰、结构一致
- **下一步**：在实际撰写技术报告时，严格按此结构组织内容
- **Owner**：当前 Project Orion A owner 是 BaoA
- **证据来源**：列出证据来源

**补充偏好**
- 如涉及 Meridian 导出 A 的失败恢复，需与 Project Orion A 的回滚演练口径保持一致。
''',
        query: '以后写 Project Orion A 或 Meridian 导出 A 相关技术报告，格式偏好是什么？',
      );

      expect(sanitized, contains('**风险**'));
      expect(sanitized, contains('**下一步**'));
      expect(sanitized, contains('**Owner**'));
      expect(sanitized, isNot(contains('确保信息清晰')));
      expect(sanitized, isNot(contains('实际撰写')));
      expect(sanitized, isNot(contains('BaoA')));
      expect(sanitized, isNot(contains('失败恢复')));
    });

    test('removes unsupported risk and next-step filler from owner answers',
        () {
      final sanitized =
          ChatService.instance.sanitizeCurrentStateAnswerForTesting(
        '''
**最新结论**：Project Orion A 当前 owner 为 **BaoA**。
**风险**：无额外风险，owner 身份稳定。
**下一步**：继续保持 BaoA 作为 owner，负责后续迭代与复盘。
**证据来源**：`2026/06/01.md#ts_1`
''',
        query: 'Project Orion A 当前 owner 是谁？请给依据。',
      );

      expect(sanitized, contains('BaoA'));
      expect(sanitized, contains('证据来源'));
      expect(sanitized, isNot(contains('无额外风险')));
      expect(sanitized, isNot(contains('继续保持 BaoA')));
    });
  });

  group('ChatService Memory Primary quick-query fallback', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      root = await Directory.systemTemp.createTemp('memex_chat_service_');
      await FileSystemService.init(root.path);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('answers relationship questions from Memory Primary recall only',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: 'MayaA 负责产品评审和体验文案；MayaA 不负责合同付款；付款和发票还是找 NoorA。',
            entityIds: ['MayaA', '产品评审', '体验文案'],
            evidenceFactIds: ['2026/05/02.md#ts_2'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content: '合同付款现在找 NoorA，发票确认也找 NoorA。LeoA 仅适用于旧项目。',
            entityIds: ['NoorA', '合同付款', '发票确认'],
            evidenceFactIds: ['2026/05/02.md#ts_8'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion A 当前 owner 是 BaoA，回滚演练是上线前置项。',
            entityIds: ['Project Orion A', 'BaoA'],
            evidenceFactIds: ['2026/05/02.md#ts_9'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-a',
        query: '产品评审找谁？合同付款和发票确认找谁？',
      );

      expect(answer, contains('MayaA'));
      expect(answer, contains('NoorA'));
      expect(answer, contains('2026/05/02.md#ts_2'));
      expect(answer, contains('2026/05/02.md#ts_8'));
      expect(answer, contains('产品评审/体验文案'));
      expect(answer, contains('合同付款/发票确认'));
      expect(answer, isNot(contains('BaoA')));
      expect(answer, isNot(contains('回滚演练')));
    });
  });
}
