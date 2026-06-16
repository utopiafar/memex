import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main() async {
  final repoRoot = Directory.current.path;
  final records = math.max(
    24,
    _intEnv('MEMEX_EVAL_PR256_SINGLE_USER_RECORDS') ?? 72,
  );
  final outDir = Directory(
    Platform.environment['MEMEX_EVAL_GENERATED_DATASET_DIR'] ??
        p.join(
          repoRoot,
          'evals',
          'datasets',
          'memory_primary_pr256_single_user_scale',
        ),
  );
  if (await outDir.exists()) {
    await outDir.delete(recursive: true);
  }
  await outDir.create(recursive: true);

  final evalCase = _buildSingleUserCase(records);
  await File(p.join(outDir.path, 'cases.jsonl')).writeAsString(
    '${jsonEncode(evalCase)}\n',
    flush: true,
  );

  final operations = (evalCase['operations'] as List).cast<JsonMap>();
  await File(p.join(outDir.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'name': 'memory_primary_pr256_single_user_scale',
      'description':
          'Single-user PR #256 Agent eval dataset with a larger continuous journey, targeted memory writes, corrections, recall probes, Super Agent asks, card insight continuity, and optional PARA projection.',
      'evidence_level': 'audited_synthetic_fixture',
      'language': 'zh-CN',
      'case_count': 1,
      'record_count':
          operations.where((operation) => operation['type'] == 'record').length,
      'memory_recall_operation_count': operations
          .where((operation) => operation['type'] == 'memory_recall')
          .length,
      'super_agent_ask_operation_count': operations
          .where((operation) => operation['type'] == 'super_agent_ask')
          .length,
      'para_projection_operation_count': operations
          .where((operation) => operation['type'] == 'para_projection')
          .length,
      'generated_by':
          'evals/bin/generate_memory_primary_pr256_single_user_dataset.dart',
      'pr_256_agent_metric_coverage': [
        'input_to_valid_card_success_rate',
        'card_completed_rate',
        'card_schema_valid_rate',
        'card_source_fact_grounding_rate',
        'card_expected_hit_rate',
        'cards_with_insight_rate',
        'memory_must_write_recall',
        'memory_must_not_write_precision',
        'memory_recall_at_10',
        'memory_recall_must_not_precision',
        'memory_source_grounding',
        'memory_duplicate_rate',
        'related_fact_hit_rate',
        'super_agent_answer_success_rate',
        'super_agent_answer_hit_rate',
        'super_agent_boundary_precision',
        'task_settlement_rate',
        'failed_task_rate',
        'retry_rate',
        'input_timeout_rate',
        'input_required_chain_latency_ms',
        'tokens_per_input',
        'tokens_by_agent',
        'prompt_cache_token_hit_rate',
        'scenario_family_coverage',
        'agent_chain_coverage',
        'journey_stage_coverage',
        'operation_type_coverage',
        'cross_day_continuity_coverage',
        'correction_operation_coverage',
        'noise_resilience_coverage',
        'follow_up_query_coverage',
      ],
      'product_metric_passes': [
        'speech_recognition_quality',
        'ocr_quality',
        'image_understanding_quality',
      ],
      'notes': [
        'This fixture does not change eval metrics or scoring; it only supplies targeted case input for the existing full-chain runner.',
        'Use the same cases.jsonl for legacy_pkm and memory_primary modes.',
        'The runner assigns one LLM config per case/user; this dataset is intentionally a single case to keep each mode on one provider slot.',
      ],
    }),
    flush: true,
  );

  stdout.writeln(
    'Generated PR256 single-user dataset with ${operations.length} operations '
    '($records records) at ${outDir.path}',
  );
}

JsonMap _buildSingleUserCase(int records) {
  final operations = <JsonMap>[];
  final memoryMustContain = <Object>[
    'Project Orion',
    'Bao',
    'Meridian 导出',
    'Dana',
    'Maya',
    'Noor',
    '杭州',
    _anyOf('conclusion-first', ['结论', 'conclusion', 'conclusions']),
    _anyOf('risk-first', ['风险', 'risk', 'risks']),
    _anyOf('latest conclusion', ['最新结论', '最新的结论', '冲突']),
    _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
    _anyOf('Wednesday focus block', ['周三下午', 'Wednesday afternoon']),
  ];
  final memoryMustNotContain = <Object>[
    _anyOf('temporary frustration', ['今天只是临时烦躁', 'temporary frustration']),
    _anyOf('one-off latte', ['一次性拿铁', 'one-off latte']),
    _anyOf('window display', ['路过看到的橱窗', 'window display']),
    _anyOf('temporary hotel', ['北京出差酒店', 'conference hotel']),
    _anyOf('casual screenshot', ['随手浏览的截图标题', 'casual screenshot']),
  ];
  final cardShouldContain = <Object>[
    'Project Orion',
    'Bao',
    'Meridian 导出',
    'Dana',
    _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
  ];
  final relatedExpectations = <JsonMap>[];

  final baseDate = DateTime(2026, 4, 1, 9);
  var recordNumber = 1;

  void addRecord(String content) {
    final id = 'rec_${recordNumber.toString().padLeft(3, '0')}';
    final time = baseDate.add(Duration(hours: (recordNumber - 1) * 6));
    operations.add({
      'id': id,
      'type': 'record',
      'time': time.toIso8601String(),
      'content': content,
    });
    recordNumber += 1;
  }

  addRecord(
    'Project Orion 进入导出灰度准备，暂时记录 Alex 负责验收口径，我负责把风险点整理成中文短报告。',
  );
  addRecord(
    '以后看技术或项目报告时，我更喜欢先给结论、风险和下一步，背景放后面；如果有冲突，请优先告诉我最新结论。',
  );
  addRecord(
    '个人长期偏好：我常驻杭州，跨时区安排默认按杭州当地时间理解；周三下午通常留给深度工作，不安排评审会。',
  );
  addRecord(
    '会议纪要：Project Orion 的导出链路还缺回滚演练、埋点检查和客服 FAQ，验收报告明天下午要给到小组。',
  );
  addRecord(
    '今天只是临时烦躁，午后喝了一杯一次性拿铁，路过看到的橱窗挺好看，这些不用长期记。',
  );
  addRecord(
    '以这条为准：Project Orion 的导出灰度 owner 是 Bao，之前关于 Alex 负责的说法都覆盖掉。',
  );
  relatedExpectations.add({
    'operation_id': 'rec_006',
    'expected_related_operation_ids': ['rec_001', 'rec_004'],
  });
  addRecord(
    'Meridian 导出项目今天启动灰度方案评审，早期我记的是 Cary 负责接口验收，风险集中在导出失败恢复。',
  );
  addRecord(
    '更正一下：Meridian 导出的接口验收 owner 现在是 Dana，不是 Cary；Cary 只负责历史数据抽样。',
  );
  relatedExpectations.add({
    'operation_id': 'rec_008',
    'expected_related_operation_ids': ['rec_007'],
  });
  addRecord(
    '关系记录：Maya 是我的设计合伙人，所有产品评审和体验文案先找 Maya；合同付款相关以前先找 Leo。',
  );
  addRecord(
    '合同付款流程更新：以后合同付款和发票确认找 Noor，之前找 Leo 的做法只适用于旧项目。',
  );
  relatedExpectations.add({
    'operation_id': 'rec_010',
    'expected_related_operation_ids': ['rec_009'],
  });
  addRecord(
    '长期报告偏好补充：给我做项目报告时默认列出 owner、风险、下一步和证据来源，证据要能追到原始记录。',
  );
  addRecord(
    '临时状态：这周住在北京出差酒店，只有这几天不方便晚上同步，别把它当成常驻城市或长期作息。',
  );

  while (recordNumber <= records) {
    final cycle = ((recordNumber - 13) ~/ 8) + 1;
    switch ((recordNumber - 13) % 8) {
      case 0:
        addRecord(
          'Project Orion 第 $cycle 轮复盘：只保留会影响后续决策的结论，临时情绪、寒暄和随手浏览的截图标题不要写进长期记忆。',
        );
        break;
      case 1:
        addRecord(
          'Project Orion 风险更新：回滚演练仍是上线前置项，Bao 需要在下周二前补齐灰度失败恢复说明。',
        );
        relatedExpectations.add({
          'operation_id':
              'rec_${(recordNumber - 1).toString().padLeft(3, '0')}',
          'expected_related_operation_ids': ['rec_006'],
        });
        break;
      case 2:
        addRecord(
          '记住一个长期协作偏好：涉及 Project Orion 或 Meridian 导出的总结，先给最新结论，再列风险、下一步、owner 和证据来源。',
        );
        break;
      case 3:
        addRecord(
          '噪声样本：刚刚看到一个随手浏览的截图标题像 Project Orion，但只是网页广告，不要写成项目事实。',
        );
        break;
      case 4:
        addRecord(
          'Meridian 导出第 $cycle 次验证：Dana 确认接口验收仍由她负责，导出失败恢复要和 Project Orion 的回滚演练口径保持一致。',
        );
        relatedExpectations.add({
          'operation_id':
              'rec_${(recordNumber - 1).toString().padLeft(3, '0')}',
          'expected_related_operation_ids': ['rec_008'],
        });
        break;
      case 5:
        addRecord(
          '关系补充：Maya 只负责产品评审和体验文案，不负责合同付款；合同付款和发票确认仍然找 Noor。',
        );
        relatedExpectations.add({
          'operation_id':
              'rec_${(recordNumber - 1).toString().padLeft(3, '0')}',
          'expected_related_operation_ids': ['rec_009', 'rec_010'],
        });
        break;
      case 6:
        addRecord(
          '临时噪声：今天临时想喝高糖奶茶，只是一次性想法，不要覆盖我长期偏好的报告格式或时间安排。',
        );
        break;
      default:
        addRecord(
          'Project Orion 和 Meridian 导出合并复盘：上线证据必须包含原始记录、owner、风险、下一步，尤其是 Bao 与 Dana 的责任边界。',
        );
    }
  }

  final afterRecords = baseDate.add(Duration(hours: records * 6));
  void addOperation(JsonMap operation, int hourOffset) {
    operations.add({
      ...operation,
      'time': afterRecords.add(Duration(hours: hourOffset)).toIso8601String(),
    });
  }

  addOperation({
    'id': 'recall_orion_owner',
    'type': 'memory_recall',
    'query': 'Project Orion 当前导出灰度 owner 是谁？',
    'expected': {
      'must_contain': ['Project Orion', 'Bao'],
      'must_not_contain': [_staleOwnerExpectation('Project Orion', 'Alex')],
    },
  }, 1);
  addOperation({
    'id': 'recall_meridian_owner',
    'type': 'memory_recall',
    'query': 'Meridian 导出当前接口验收 owner 是谁？',
    'expected': {
      'must_contain': ['Meridian 导出', 'Dana'],
      'must_not_contain': [_staleOwnerExpectation('Meridian 导出', 'Cary')],
    },
  }, 2);
  addOperation({
    'id': 'recall_report_style',
    'type': 'memory_recall',
    'query': '我希望项目技术报告怎么写？',
    'expected': {
      'must_contain': [
        _anyOf('conclusion', ['结论', 'conclusion', 'conclusions']),
        _anyOf('risk', ['风险', 'risk', 'risks']),
        _anyOf('latest conclusion', ['最新结论', '最新的结论', '冲突']),
        _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
      ],
      'must_not_contain': [],
    },
  }, 3);
  addOperation({
    'id': 'recall_relationship_payment',
    'type': 'memory_recall',
    'query': '合同付款和发票确认应该找谁？Maya 负责什么？',
    'expected': {
      'must_contain': [
        'Noor',
        'Maya',
        _anyOf('review', ['产品评审', '体验文案'])
      ],
      'must_not_contain': [_staleOwnerExpectation('合同付款', 'Leo')],
    },
  }, 4);
  addOperation({
    'id': 'recall_home_city',
    'type': 'memory_recall',
    'query': '我的常驻城市和周三下午安排偏好是什么？',
    'expected': {
      'must_contain': [
        '杭州',
        _anyOf('Wednesday', ['周三下午', 'Wednesday afternoon'])
      ],
      'must_not_contain': [
        _anyOf('temporary hotel', ['北京出差酒店', 'conference hotel'])
      ],
    },
  }, 5);
  addOperation({
    'id': 'projection_001',
    'type': 'para_projection',
  }, 6);
  addOperation({
    'id': 'ask_orion_owner',
    'type': 'super_agent_ask',
    'query': 'Project Orion 当前导出灰度 owner 是谁？请给出依据。',
    'quick_query': true,
    'expected': {
      'must_contain': ['Project Orion', 'Bao'],
      'must_not_contain': [_staleOwnerExpectation('Project Orion', 'Alex')],
    },
  }, 7);
  addOperation({
    'id': 'ask_meridian_owner',
    'type': 'super_agent_ask',
    'query': 'Meridian 导出当前接口验收 owner 是谁？',
    'quick_query': true,
    'expected': {
      'must_contain': ['Meridian 导出', 'Dana'],
      'must_not_contain': [_staleOwnerExpectation('Meridian 导出', 'Cary')],
    },
  }, 8);
  addOperation({
    'id': 'ask_report_style',
    'type': 'super_agent_ask',
    'query': '以后给我写 Project Orion 或 Meridian 导出相关技术报告时，格式偏好是什么？',
    'quick_query': true,
    'expected': {
      'must_contain': [
        'Project Orion',
        'Meridian 导出',
        _anyOf('conclusion', ['结论', 'conclusion', 'conclusions']),
        _anyOf('risk', ['风险', 'risk', 'risks']),
        _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
      ],
      'must_not_contain': [],
    },
  }, 9);
  addOperation({
    'id': 'ask_relationship_payment',
    'type': 'super_agent_ask',
    'query': '产品评审找谁？合同付款和发票确认找谁？',
    'quick_query': true,
    'expected': {
      'must_contain': ['Maya', 'Noor'],
      'must_not_contain': [_staleOwnerExpectation('合同付款', 'Leo')],
    },
  }, 10);
  addOperation({
    'id': 'ask_home_city',
    'type': 'super_agent_ask',
    'query': '我常驻哪里？周三下午一般怎么安排？',
    'quick_query': true,
    'expected': {
      'must_contain': [
        '杭州',
        _anyOf('Wednesday', ['周三下午', 'Wednesday afternoon'])
      ],
      'must_not_contain': [
        _anyOf('temporary hotel', ['北京出差酒店', 'conference hotel'])
      ],
    },
  }, 11);

  return {
    'case_id': 'memory_primary_pr256_single_user_001',
    'persona': {
      'user_id': 'memory_pr256_single_user',
      'role': 'AI native knowledge worker',
      'city': '杭州',
    },
    'coverage': {
      'scenario_families': [
        'project_status',
        'preference',
        'correction',
        'noise_noop',
        'memory_recall',
        'super_agent_ask',
      ],
      'input_channels': [
        'text',
        'meeting_note',
        'browser_clip',
        'relationship_note',
      ],
      'journey_stages': [
        'capture',
        'memory_write',
        'recall',
        'projection',
        'ask',
      ],
    },
    'operations': operations,
    'expected': {
      'memory_must_contain': memoryMustContain,
      'memory_must_not_contain': memoryMustNotContain,
      'card_title_or_insight_should_contain': cardShouldContain,
      'related_fact_expectations': relatedExpectations,
    },
  };
}

JsonMap _anyOf(String label, List<String> values) => {
      'label': label,
      'any_of': values,
    };

JsonMap _staleOwnerExpectation(String scope, String owner) => {
      'label': 'stale current owner: $owner',
      'regex': '($scope[^\\n。；;]{0,40}(当前|current|现在|最新)[^\\n。；;]{0,40}'
          '(owner|负责人|负责|验收)[^\\n。；;]{0,30}$owner)|'
          '((owner|负责人|负责|验收)[^\\n。；;]{0,20}(是|为|=)[^\\n。；;]{0,10}$owner)|'
          '($owner[^\\n。；;]{0,12}(是|为|担任|负责)[^\\n。；;]{0,20}'
          '(当前|current|现在|最新|owner|负责人|验收))',
    };

int? _intEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
}
