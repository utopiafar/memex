import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/memory_extract_agent/memory_extract_agent.dart';

void main() {
  test('generalizes temporary no-long-term boundary memories', () {
    const sourceText = '临时噪声：今天只是想喝临时奶茶，晚上住短期酒店，路上看到网页广告截图；这些都不要长期化。';
    final raw = jsonEncode({
      'patches': [
        {
          'op': 'create',
          'type': 'boundary',
          'title': '临时事件不长期化',
          'content': '用户不希望将临时奶茶、短期酒店、网页广告截图存储为长期记忆。',
          'confidence': 1.0,
          'importance': 1,
          'entity_ids': ['临时奶茶', '短期酒店', '网页广告截图'],
          'evidence_fact_ids': ['2026/05/02.md#ts_4'],
          'attributes': {},
        }
      ],
    });

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/05/02.md#ts_4',
      sourceText: sourceText,
    );

    expect(patches, hasLength(1));
    final patch = patches.single;
    expect(patch.type, 'boundary');
    expect(patch.content, isNot(contains('临时奶茶')));
    expect(patch.content, isNot(contains('短期酒店')));
    expect(patch.content, isNot(contains('网页广告截图')));
    expect(patch.entityIds, isEmpty);
    expect(
      patch.attributes['normalization_rule'],
      'temporary_boundary_generalization',
    );
  });

  test(
      'generalizes temporary no-long-term memories even when typed as preference',
      () {
    const sourceText = '临时噪声：今天只是想喝临时奶茶，晚上住短期酒店，路上看到网页广告截图；这些都不要长期化。';
    final raw = jsonEncode({
      'patches': [
        {
          'op': 'create',
          'type': 'preference',
          'title': '临时内容处理偏好',
          'content': '用户明确要求不要将临时奶茶、短期酒店、网页广告截图长期化为记忆。',
          'confidence': 1.0,
          'importance': 1,
          'entity_ids': ['临时奶茶', '短期酒店', '网页广告截图'],
          'evidence_fact_ids': ['2026/05/02.md#ts_4'],
          'attributes': {},
        }
      ],
    });

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/05/02.md#ts_4',
      sourceText: sourceText,
    );

    expect(patches, hasLength(1));
    final patch = patches.single;
    expect(patch.type, 'boundary');
    expect(patch.content, isNot(contains('临时奶茶')));
    expect(patch.content, isNot(contains('短期酒店')));
    expect(patch.content, isNot(contains('网页广告截图')));
    expect(patch.entityIds, isEmpty);
    expect(
      patch.attributes['normalization_rule'],
      'temporary_boundary_generalization',
    );
  });

  test('creates fallback memory for role and mood transitions', () {
    const sourceText =
        '角色转换和反思不是行动：上午以AI 产品经理 A看 Project Orion A 上线风险，下午切到客户访谈整理者 A整理 Meridian 导出 A 客户反馈；心态从有点焦虑转为谨慎乐观，现在不要创建提醒或行动。';
    final raw = jsonEncode({'patches': []});

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/05/03.md#ts_2',
      sourceText: sourceText,
    );

    final transitionPatch = patches.singleWhere(
      (patch) => patch.attributes['fallback_rule'] == 'role_mood_transition',
    );
    expect(transitionPatch.type, 'project_context');
    expect(transitionPatch.content, contains('AI 产品经理 A'));
    expect(transitionPatch.content, contains('客户访谈整理者 A'));
    expect(transitionPatch.content, contains('谨慎乐观'));
    expect(transitionPatch.entityIds, contains('Project Orion A'));
    expect(transitionPatch.entityIds, contains('Meridian 导出 A'));
    expect(transitionPatch.evidenceFactIds, contains('2026/05/03.md#ts_2'));
  });

  test('preserves exact domain compound terms in memory content', () {
    const sourceText =
        '已解析截图上下文：OCR 文字显示 Project Orion C 的灰度风险列表；MayaC 和 NoorC 对灰度风险优先级有分歧，最终由 BaoC 仲裁。';
    final raw = jsonEncode({
      'patches': [
        {
          'op': 'create',
          'type': 'project_context',
          'title': 'Project Orion C 灰度风险列表与决策流程',
          'content':
              'Project Orion C 的灰度阶段存在正式的灰度风险列表。对于风险优先级，MayaC 与 NoorC 产生了分歧，最终由项目 owner BaoC 进行仲裁。',
          'confidence': 1.0,
          'importance': 3,
          'entity_ids': ['Project Orion C', 'MayaC', 'NoorC', 'BaoC'],
          'evidence_fact_ids': ['2026/05/05.md#ts_4'],
          'attributes': {},
        }
      ],
    });

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/05/05.md#ts_4',
      sourceText: sourceText,
    );

    final patch = patches.single;
    expect(patch.content, contains('灰度风险优先级'));
    expect(patch.content, contains('OCR'));
    expect(patch.content, contains('给定文本'));
    expect(patch.entityIds, contains('灰度风险优先级'));
    expect(patch.entityIds, contains('OCR'));
    expect(patch.entityIds, contains('给定文本'));
    expect(
      patch.attributes['preserved_domain_terms'],
      contains('灰度风险优先级'),
    );
    expect(patch.attributes['source_type'], 'screenshot_ocr');
    expect(patch.attributes['ocr_handling'], 'use_given_text_only');
  });

  test('preserves conflict object terms before rhythm suffix', () {
    const sourceText =
        '已解析截图上下文：OCR 文字显示 Project Orion B 的灰度风险列表；MayaB 和 NoorB 对合同付款节奏有分歧，最终由 BaoB 仲裁。';
    final raw = jsonEncode({
      'patches': [
        {
          'op': 'create',
          'type': 'project_context',
          'title': 'Project Orion B 灰度风险与仲裁',
          'content':
              'Project Orion B 的灰度风险列表包含管理层面的合同支付节奏分歧，MayaB 和 NoorB 有分歧，并由 BaoB 仲裁。',
          'confidence': 1.0,
          'importance': 3,
          'entity_ids': ['Project Orion B', 'MayaB', 'NoorB', 'BaoB'],
          'evidence_fact_ids': ['2026/05/04.md#ts_4'],
          'attributes': {},
        }
      ],
    });

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/05/04.md#ts_4',
      sourceText: sourceText,
    );

    final patch = patches.single;
    expect(patch.content, contains('合同付款节奏'));
    expect(patch.entityIds, contains('合同付款节奏'));
    expect(
      patch.attributes['preserved_domain_terms'],
      contains('合同付款节奏'),
    );
  });

  test('preserves parsed OCR source context and release window terms', () {
    const sourceText =
        '已解析截图上下文：OCR 文字显示 Project Orion G 的灰度风险列表；MayaG 和 NoorG 对发布时间窗口有分歧，最终由 BaoG 仲裁。';
    final raw = jsonEncode({
      'patches': [
        {
          'op': 'create',
          'type': 'project_context',
          'title': 'Project Orion G 灰度风险列表',
          'content': 'Project Orion G 的灰度风险列表；MayaG 和 NoorG 有分歧，最终由 BaoG 仲裁。',
          'confidence': 1.0,
          'importance': 3,
          'entity_ids': ['Project Orion G', 'MayaG', 'NoorG', 'BaoG'],
          'evidence_fact_ids': ['2026/07/15.md#ts_8'],
          'attributes': {},
        }
      ],
    });

    final patches = MemoryExtractAgent.parsePatchesForTest(
      raw,
      fallbackFactId: '2026/07/15.md#ts_8',
      sourceText: sourceText,
    );

    final patch = patches.single;
    expect(patch.content, contains('发布时间窗口'));
    expect(patch.content, isNot(contains('发布时间窗口有分歧')));
    expect(patch.content, contains('OCR'));
    expect(patch.content, contains('给定文本'));
    expect(patch.entityIds, contains('发布时间窗口'));
    expect(patch.entityIds, isNot(contains('发布时间窗口有分歧')));
    expect(patch.entityIds, contains('OCR'));
    expect(patch.entityIds, contains('给定文本'));
    expect(patch.attributes['source_type'], 'screenshot_ocr');
    expect(patch.attributes['ocr_handling'], 'use_given_text_only');
  });

  test('builds a parsed OCR fallback patch when the model returns no patches',
      () {
    const sourceText =
        '已解析截图上下文：OCR 文字显示 Project Orion H 的灰度风险列表；MayaH 和 NoorH 对发布时间窗口有分歧，最终由 BaoH 仲裁。';

    final patches = MemoryExtractAgent.parsePatchesForTest(
      '{"patches":[]}',
      fallbackFactId: '2026/07/16.md#ts_8',
      sourceText: sourceText,
    );

    final patch = patches.single;
    expect(patch.type, 'project_context');
    expect(patch.content, contains('Project Orion H'));
    expect(patch.content, contains('发布时间窗口'));
    expect(patch.content, contains('OCR'));
    expect(patch.content, contains('给定文本'));
    expect(patch.entityIds, contains('Project Orion H'));
    expect(patch.entityIds, contains('发布时间窗口'));
    expect(patch.evidenceFactIds, contains('2026/07/16.md#ts_8'));
    expect(patch.attributes['fallback_rule'], 'parsed_text_context');
    expect(patch.attributes['ocr_handling'], 'use_given_text_only');
  });
}
