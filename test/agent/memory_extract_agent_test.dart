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
}
