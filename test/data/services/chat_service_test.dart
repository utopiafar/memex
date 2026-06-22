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
          '我在 Project Orion A 和 Meridian 导出 A 之间切换了哪两个角色？阶段心态是什么？',
        ),
        isTrue,
      );
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '如果我只问 Project Orion A 的 owner，你应该只回答什么？',
        ),
        isTrue,
      );
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '如果问到财务压力复盘，你能不能给确定性投资建议？',
        ),
        isTrue,
      );
      expect(
        ChatService.instance.looksLikeMemoryPrimaryRecallQueryForTesting(
          '最近 OCR 里的 Project Orion A 风险列表，Agent 应该怎么处理？',
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

    test('prefers current payment contact over superseded old owner text',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-relationship-superseded-contact',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content:
                'MayaH 负责产品评审和体验文案；付款和发票的当前联系人是 NoorH；MayaH 不负责合同付款。此信息取代了此前关于合同付款找 LeoH 的说法。',
            entityIds: ['NoorH', 'LeoH', 'MayaH', '合同付款', '发票'],
            evidenceFactIds: ['2026/05/09.md#ts_3', '2026/05/09.md#ts_8'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-relationship-superseded-contact',
        query: '产品评审找谁？合同付款和发票确认找谁？',
      );

      expect(answer, contains('产品评审/体验文案'));
      expect(answer, contains('MayaH'));
      expect(answer, contains('合同付款/发票确认'));
      expect(answer, contains('NoorH'));
      expect(answer, contains('2026/05/09.md#ts_3'));
      expect(answer, isNot(contains('合同付款找 LeoH')));
      expect(answer, isNot(contains('发票确认找 LeoH')));
      expect(answer, isNot(contains('LeoH 负责合同付款')));
    });

    test('answers current project owner without stale correction values',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-owner',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion A 当前 owner 是 BaoA，覆盖了 AlexA 的旧说法。',
            entityIds: ['Project Orion A', 'BaoA', 'AlexA'],
            evidenceFactIds: ['2026/05/01.md#ts_4'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户的报告偏好是项目报告先给出最新结论，再列出风险、下一步、owner和证据来源。',
            evidenceFactIds: ['2026/05/01.md#ts_2'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-owner',
        query: 'Project Orion A 当前 owner 是谁？请给依据。',
      );

      expect(answer, contains('Project Orion A'));
      expect(answer, contains('BaoA'));
      expect(answer, contains('2026/05/01.md#ts_4'));
      expect(answer, isNot(contains('AlexA')));
      expect(answer, isNot(contains('报告偏好')));
    });

    test('keeps current owner when correction tail mentions old facts',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-owner-tail',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content:
                'Project Orion A 的验收负责人不是 AlexA；Project Orion A 的当前 owner 是 BaoA，此信息覆盖了早期关于 AlexA 的错误说法。',
            entityIds: ['Project Orion A', 'AlexA', 'BaoA'],
            evidenceFactIds: ['2026/05/01.md#ts_1', '2026/05/01.md#ts_4'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-owner-tail',
        query: 'Project Orion A 当前 owner 是谁？请给依据。',
      );

      expect(answer, contains('Project Orion A'));
      expect(answer, contains('BaoA'));
      expect(answer, contains('2026/05/01.md#ts_4'));
      expect(answer, isNot(contains('AlexA 的错误说法')));
    });

    test('treats current owner synonyms as current owner answers', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-owner-synonym',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion B 的当前所有者是 BaoB，覆盖了之前 AlexB 的说法。',
            entityIds: ['Project Orion B', 'BaoB', 'AlexB'],
            evidenceFactIds: ['2026/05/02.md#ts_4'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-owner-synonym',
        query: 'Project Orion B 当前 owner 是谁？请给依据。',
      );

      expect(answer, contains('Project Orion B'));
      expect(answer, contains('BaoB'));
      expect(answer, contains('2026/05/02.md#ts_4'));
      expect(answer, isNot(contains('AlexB')));
    });

    test('excludes entities named in do-not-mix current-state queries',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-exclude',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Meridian 导出 A 接口验收当前 owner 是 DanaA。',
            entityIds: ['Meridian 导出 A', 'DanaA', '接口验收'],
            evidenceFactIds: ['2026/05/02.md#ts_6'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion A 当前 owner 是 BaoA。',
            entityIds: ['Project Orion A', 'BaoA'],
            evidenceFactIds: ['2026/05/01.md#ts_4'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-exclude',
        query: 'Meridian 导出 A 现在是谁负责接口验收？不要混到 Project Orion A。',
      );

      expect(answer, contains('Meridian 导出 A'));
      expect(answer, contains('DanaA'));
      expect(answer, isNot(contains('Project Orion A')));
      expect(answer, isNot(contains('BaoA')));
    });

    test('keeps current owner when the same clause has a historical-only tail',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-current-owner-tail',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Meridian导出A当前接口验收的owner是DanaA，CaryA仅负责历史抽样。',
            entityIds: ['Meridian Export A', 'DanaA', 'CaryA'],
            evidenceFactIds: ['2026/05/02.md#ts_1'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion A 当前 owner 是 BaoA。',
            entityIds: ['Project Orion A', 'BaoA'],
            evidenceFactIds: ['2026/05/01.md#ts_4'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-current-owner-tail',
        query: 'Meridian 导出 A 现在是谁负责接口验收？不要混到 Project Orion A。',
      );
      final finalAnswer =
          ChatService.instance.ensureProjectNameFromQueryForTesting(
        answer ?? '',
        query: 'Meridian 导出 A 现在是谁负责接口验收？不要混到 Project Orion A。',
      );

      expect(answer, contains('Meridian导出A'));
      expect(finalAnswer, contains('Meridian 导出 A'));
      expect(answer, contains('DanaA'));
      expect(answer, contains('2026/05/02.md#ts_1'));
      expect(answer, isNot(contains('CaryA')));
      expect(finalAnswer, isNot(contains('Project Orion A：')));
      expect(answer, isNot(contains('BaoA')));
    });

    test('answers owner-only queries without report-risk filler', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-owner-only',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion E 当前 owner 是 BaoE。',
            entityIds: ['Project Orion E', 'BaoE'],
            evidenceFactIds: ['2026/05/04.md#ts_4'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '项目报告偏好是先写最新结论，再写风险、下一步、owner 和证据来源。',
            entityIds: ['Project Orion E'],
            evidenceFactIds: ['2026/05/04.md#ts_2'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-owner-only',
        query: '如果我只问 Project Orion E 的 owner，你应该只回答什么？',
      );

      expect(answer, contains('Project Orion E'));
      expect(answer, contains('BaoE'));
      expect(answer, contains('2026/05/04.md#ts_4'));
      expect(answer, isNot(contains('风险')));
      expect(answer, isNot(contains('下一步')));
      expect(answer, isNot(contains('报告偏好')));
    });

    test('answers sensitive boundary queries from boundary memory', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-sensitive-boundary',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'boundary',
            content: '财务压力复盘只记录情绪和事实，不要给确定性投资建议或税务结论。',
            entityIds: ['财务压力复盘', '投资建议', '税务结论'],
            evidenceFactIds: ['2026/05/05.md#ts_7'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content: 'Project Orion E 当前 owner 是 BaoE。',
            entityIds: ['Project Orion E', 'BaoE'],
            evidenceFactIds: ['2026/05/04.md#ts_4'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-sensitive-boundary',
        query: '如果问到财务压力复盘，你能不能给确定性投资建议？',
      );

      expect(answer, contains('只记录情绪和事实'));
      expect(answer, contains('不要给确定性投资建议'));
      expect(answer, contains('2026/05/05.md#ts_7'));
      expect(answer, isNot(contains('BaoE')));
    });

    test('answers parsed OCR context without evaluating OCR itself', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-ocr-context',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content:
                'Project Orion A 的灰度风险列表中，MayaA 和 NoorA 对数据口径解释存在分歧，最终由 BaoA 仲裁。此为已解析截图上下文，Agent 只需使用给定文本，不评估 OCR 本身。',
            entityIds: [
              'Project Orion A',
              'MayaA',
              'NoorA',
              'BaoA',
              '数据口径解释',
            ],
            evidenceFactIds: ['2026/05/07.md#ts_4'],
            attributes: {
              'source_type': 'screenshot_ocr',
              'ocr_handling': 'use_given_text_only',
            },
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-ocr-context',
        query: '最近 OCR 里的 Project Orion A 风险列表，Agent 应该怎么处理？',
      );

      final traceQuery = ChatService.instance
          .expandedMemoryPrimaryFallbackTraceQueryForTesting(
        '最近 OCR 里的 Project Orion A 风险列表，Agent 应该怎么处理？',
      );

      expect(answer, contains('Project Orion A'));
      expect(answer, contains('OCR'));
      expect(answer, contains('给定文本'));
      expect(answer, contains('数据口径解释'));
      expect(answer, contains('2026/05/07.md#ts_4'));
      expect(answer, isNot(contains('评估 OCR 本身')));
      expect(traceQuery, contains('数据口径解释'));
      expect(traceQuery, contains('给定文本'));
    });

    test('infers parsed OCR handling from risk-list conflict memories',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-ocr-context-without-marker',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content:
                'Project Orion G 的灰度风险列表；MayaG 和 NoorG 对发布时间窗口有分歧，最终由 BaoG 仲裁。',
            entityIds: [
              'Project Orion G',
              'MayaG',
              'NoorG',
              'BaoG',
              '发布时间窗口',
            ],
            evidenceFactIds: ['2026/07/15.md#ts_8'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-ocr-context-without-marker',
        query: '最近 OCR 里的 Project Orion G 风险列表，Agent 应该怎么处理？',
      );

      expect(answer, contains('Project Orion G'));
      expect(answer, contains('OCR'));
      expect(answer, contains('给定文本'));
      expect(answer, contains('发布时间窗口'));
      expect(answer, contains('2026/07/15.md#ts_8'));
      expect(answer, isNot(contains('评估 OCR 本身')));
    });

    test('answers relationship continuations from a pronoun assignment',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-relationship-continuation',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content:
                'MayaB 不负责合同付款和发票确认；此项工作由 NoorB 负责。MayaB 的主要职责是产品评审和体验文案。对于旧项目，仍可能联系 LeoB。',
            entityIds: ['MayaB', 'LeoB', 'NoorB'],
            evidenceFactIds: [
              '2026/05/03.md#ts_2',
              '2026/05/03.md#ts_3',
              '2026/05/03.md#ts_8',
            ],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-relationship-continuation',
        query: '产品评审找谁？合同付款和发票确认找谁？',
      );

      expect(answer, contains('MayaB'));
      expect(answer, contains('NoorB'));
      expect(answer, contains('合同付款/发票确认'));
      expect(answer, isNot(contains('合同付款/发票确认：MayaB 不负责')));
    });

    test('keeps relationship subjects across comma continuations', () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-relationship-comma-continuation',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'relationship',
            content:
                'MayaB 不负责合同付款，负责产品评审和体验文案；合同付款和发票确认的负责人是 NoorB。LeoB 的职责仅限于旧项目。',
            entityIds: ['NoorB', 'LeoB', 'MayaB'],
            evidenceFactIds: ['2026/05/03.md#ts_3', '2026/05/03.md#ts_8'],
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-relationship-comma-continuation',
        query: '产品评审找谁？合同付款和发票确认找谁？',
      );

      expect(answer, contains('产品评审/体验文案：MayaB'));
      expect(answer, contains('合同付款/发票确认'));
      expect(answer, contains('NoorB'));
      expect(answer, isNot(contains('合同付款/发票确认：MayaB')));
    });

    test('answers role and mood transition questions from Memory Primary',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-role',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content:
                '用户在 Project Orion A 和 Meridian 导出 A 之间切换角色：上午以 AI 产品经理 A 处理 Project Orion A，下午切到客户访谈整理者 A 处理 Meridian 导出 A；阶段心态从有点焦虑转为谨慎乐观。',
            entityIds: [
              'Project Orion A',
              'Meridian 导出 A',
              'AI 产品经理 A',
              '客户访谈整理者 A',
              '有点焦虑',
              '谨慎乐观',
            ],
            evidenceFactIds: ['2026/05/03.md#ts_2'],
            attributes: {
              'fallback_rule': 'role_mood_transition',
              'from_role': 'AI 产品经理 A',
              'to_role': '客户访谈整理者 A',
              'from_project': 'Project Orion A',
              'to_project': 'Meridian 导出 A',
              'from_mood': '有点焦虑',
              'to_mood': '谨慎乐观',
            },
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-role',
        query: '我在 Project Orion A 和 Meridian 导出 A 之间切换了哪两个角色？阶段心态是什么？',
      );

      expect(answer, contains('AI 产品经理 A'));
      expect(answer, contains('客户访谈整理者 A'));
      expect(answer, contains('谨慎乐观'));
      expect(answer, contains('2026/05/03.md#ts_2'));
      expect(answer, isNot(contains('提醒已创建')));
    });

    test('keeps location and routine answers scoped away from role mood atoms',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-location-routine',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'preference',
            content: '用户常驻深圳，主要角色是增长运营负责人 C，周三下午通常留给深度工作，不安排评审会。',
            entityIds: ['深圳', '增长运营负责人 C', '周三下午', '深度工作'],
            evidenceFactIds: ['2026/05/03.md#ts_3'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            content:
                '用户在 Project Orion C 和 Meridian 导出 C 之间切换角色：上午以增长运营负责人 C 处理 Project Orion C，下午切到跨团队沟通窗口 C 处理 Meridian 导出 C；阶段心态从兴奋但分散转为重新聚焦。',
            entityIds: [
              'Project Orion C',
              'Meridian 导出 C',
              '增长运营负责人 C',
              '跨团队沟通窗口 C',
              '兴奋但分散',
              '重新聚焦',
              '深圳',
            ],
            evidenceFactIds: [
              '2026/05/06.md#ts_4',
              '2026/05/07.md#ts_6',
            ],
            attributes: {
              'fallback_rule': 'role_mood_transition',
              'from_role': '增长运营负责人 C',
              'to_role': '跨团队沟通窗口 C',
              'from_mood': '兴奋但分散',
              'to_mood': '重新聚焦',
            },
          ),
        ],
      );

      final answer = await ChatService.instance
          .buildMemoryPrimaryQuickQueryFallbackAnswerForTesting(
        userId: 'user-location-routine',
        query: '我常驻哪里？周三下午一般怎么安排？',
      );

      expect(
        ChatService.instance.looksLikeIdentityOrRoutineQueryForTesting(
          '我常驻哪里？周三下午一般怎么安排？',
        ),
        isTrue,
      );
      final formatted =
          ChatService.instance.formatIdentityOrRoutineFallbackAnswerForTesting(
        query: '我常驻哪里？周三下午一般怎么安排？',
        contents: const [
          '用户常驻深圳，主要角色是增长运营负责人 C，周三下午通常留给深度工作，不安排评审会。',
        ],
      );
      expect(formatted, contains('常驻深圳'));
      expect(formatted, contains('周三下午通常留给深度工作'));
      expect(formatted, contains('不安排评审会'));
      expect(answer, contains('常驻深圳'));
      expect(answer, contains('周三下午通常留给深度工作'));
      expect(answer, contains('不安排评审会'));
      expect(answer, contains('2026/05/03.md#ts_3'));
      expect(answer, isNot(contains('Project Orion C')));
      expect(answer, isNot(contains('Meridian 导出 C')));
      expect(answer, isNot(contains('兴奋但分散')));
      expect(answer, isNot(contains('重新聚焦')));
    });
  });
}
