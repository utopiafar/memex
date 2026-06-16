import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main() async {
  final repoRoot = Directory.current.path;
  final personaCount = math.max(1, _intEnv('MEMEX_EVAL_PERSONA_COUNT') ?? 3);
  final recordsPerPersona =
      math.max(24, _intEnv('MEMEX_EVAL_RECORDS_PER_PERSONA') ?? 48);
  final outDir = Directory(
    Platform.environment['MEMEX_EVAL_GENERATED_DATASET_DIR'] ??
        p.join(repoRoot, 'evals', 'datasets', 'pr256_full_metric_small'),
  );
  if (await outDir.exists()) {
    await outDir.delete(recursive: true);
  }
  await outDir.create(recursive: true);

  final cases = [
    for (var i = 0; i < personaCount; i++)
      _buildPersonaCase(index: i, records: recordsPerPersona),
  ];
  await File(p.join(outDir.path, 'cases.jsonl')).writeAsString(
    '${cases.map(jsonEncode).join('\n')}\n',
    flush: true,
  );
  await File(p.join(outDir.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'name': p.basename(outDir.path),
      'description':
          'PR #256 full-metric synthetic dataset. Ground truth is generated together with operations so the replay can compute deterministic GT/Trace metrics and emit LLM judge tasks for subjective metrics.',
      'generated_by': 'evals/bin/generate_pr256_full_metric_dataset.dart',
      'schema_version': 'pr256_full_metric.v1',
      'persona_count': personaCount,
      'records_per_persona': recordsPerPersona,
      'record_count': personaCount * recordsPerPersona,
      'recommended_small_gate': {
        'persona_count': 3,
        'records_per_persona': 48,
      },
      'required_scale_gate': {
        'persona_count_min': 8,
        'records_per_persona_min': 400,
      },
      'oracle_strategy': {
        'ground_truth_generated_with_data': [
          'agent routes',
          'card fields/entities/time',
          'memory must-write/must-not-write',
          'related facts',
          'retrieval sources',
          'tool selection/args/minimality',
          'read-only compliance',
          'coverage quotas',
        ],
        'llm_judge_tasks_emitted_for': [
          'card_title_relevance_score',
          'unsupported_claim_absence',
          'grounded_answer_rate',
          'pkm_append_coherence',
          'comment_relevance_score',
          'comment_boundary_safety',
          'insight_novelty_score',
          'insight_actionability_score',
        ],
      },
    }),
    flush: true,
  );
  stdout.writeln(
    'Generated ${cases.length} PR256 full-metric cases with '
    '$recordsPerPersona records/persona at ${outDir.path}',
  );
}

JsonMap _buildPersonaCase({
  required int index,
  required int records,
}) {
  final persona = _persona(index);
  final operations = <JsonMap>[];
  final relatedExpectations = <JsonMap>[];
  final memoryMustContain = <Object>[
    persona.project,
    persona.projectOwnerCurrent,
    persona.partnerProject,
    persona.partnerOwnerCurrent,
    persona.reviewOwner,
    persona.paymentOwnerCurrent,
    persona.city,
    persona.deepWorkWindow,
    _anyOf('latest conclusion', ['最新结论', '最新的结论', '冲突']),
    _anyOf('evidence source', ['证据来源', 'evidence source', '原始记录']),
  ];
  final memoryMustNotContain = <Object>[
    _staleOwnerAssertion(persona.projectOwnerStale),
    _staleOwnerAssertion(persona.partnerOwnerStale),
    _stalePaymentAssertion(persona.paymentOwnerStale),
    '临时奶茶',
    '短期酒店',
    '网页广告截图',
  ];
  final cardShouldContain = <Object>[
    persona.project,
    persona.projectOwnerCurrent,
    persona.partnerProject,
    persona.partnerOwnerCurrent,
    persona.reviewOwner,
    persona.paymentOwnerCurrent,
  ];

  final baseDate = DateTime(2026, 5, 1 + index, 9);
  var recordNumber = 1;

  String factIdForRecord(int targetRecordNumber) {
    final targetTime =
        baseDate.add(Duration(hours: (targetRecordNumber - 1) * 3));
    var tsIndex = 0;
    for (var i = 1; i <= targetRecordNumber; i++) {
      final time = baseDate.add(Duration(hours: (i - 1) * 3));
      if (_sameDate(time, targetTime)) tsIndex += 1;
    }
    return '${_datePath(targetTime)}.md#ts_$tsIndex';
  }

  List<String> factIdsForRecords(Iterable<int> recordNumbers) {
    return recordNumbers
        .where((record) => record >= 1 && record <= records)
        .map(factIdForRecord)
        .toList(growable: false);
  }

  List<int> repeatingRecordsForCase(int caseIndex) {
    final result = <int>[];
    for (var record = 10; record <= records; record++) {
      if ((record - 10) % 10 == caseIndex) result.add(record);
    }
    return result;
  }

  void addRecord(
    String content, {
    List<String> entities = const [],
    List<String> fields = const [],
    List<String> mustNot = const [],
    List<String> relatedTo = const [],
    List<String>? expectedTemplates,
  }) {
    final id = 'rec_${recordNumber.toString().padLeft(4, '0')}';
    final time = baseDate.add(Duration(hours: (recordNumber - 1) * 3));
    operations.add({
      'id': id,
      'type': 'record',
      'time': time.toIso8601String(),
      'content': content,
      'expected': {
        'route': {
          'by_mode': {
            'legacy_pkm': {
              'expected_task_types': ['card_agent_task', 'pkm_agent_task'],
              'forbidden_task_types': [
                'memory_primary_task',
                'card_insight_task',
              ],
            },
            'memory_primary': {
              'expected_task_types': [
                'card_agent_task',
                'memory_primary_task',
                'card_insight_task',
              ],
              'forbidden_task_types': ['pkm_agent_task'],
            },
          },
        },
        'card': {
          if (expectedTemplates != null)
            'expected_template_ids': expectedTemplates,
          'field_must_contain': fields,
          'expected_entities': entities,
          'must_not_fields': mustNot,
          'expected_time': time.toIso8601String(),
          'time_tolerance_minutes': 1,
          'judge_tasks': [
            {
              'metric': 'card_title_relevance_score',
              'rubric':
                  'Card title should preserve the main user fact without inventing unsupported details.',
            }
          ],
        },
      },
    });
    if (relatedTo.isNotEmpty) {
      relatedExpectations.add({
        'operation_id': id,
        'expected_related_operation_ids': relatedTo,
      });
    }
    recordNumber += 1;
  }

  addRecord(
    '${persona.project} 进入灰度准备，早期我误记 ${persona.projectOwnerStale} 负责验收，风险集中在回滚演练。',
    entities: [persona.project, persona.projectOwnerStale],
    fields: [persona.project, '回滚演练'],
  );
  addRecord(
    '报告偏好：项目报告先给最新结论，再列风险、下一步、owner 和证据来源，背景放在最后。',
    fields: ['最新结论', '风险', '下一步', 'owner', '证据来源'],
  );
  addRecord(
    '个人长期偏好：我常驻${persona.city}，${persona.deepWorkWindow}通常留给深度工作，不安排评审会。',
    entities: [persona.city],
    fields: [persona.city, persona.deepWorkWindow, '深度工作'],
  );
  addRecord(
    '以这条为准：${persona.project} 当前 owner 是 ${persona.projectOwnerCurrent}，覆盖 ${persona.projectOwnerStale} 的旧说法。',
    entities: [persona.project, persona.projectOwnerCurrent],
    fields: [persona.project, persona.projectOwnerCurrent],
    relatedTo: ['rec_0001'],
  );
  addRecord(
    '${persona.partnerProject} 启动接口验收，早期记录是 ${persona.partnerOwnerStale} 负责，风险在失败恢复口径。',
    entities: [persona.partnerProject, persona.partnerOwnerStale],
    fields: [persona.partnerProject, '失败恢复'],
  );
  addRecord(
    '更正：${persona.partnerProject} 当前接口验收 owner 是 ${persona.partnerOwnerCurrent}，${persona.partnerOwnerStale} 只看历史抽样。',
    entities: [persona.partnerProject, persona.partnerOwnerCurrent],
    fields: [persona.partnerProject, persona.partnerOwnerCurrent],
    relatedTo: ['rec_0005'],
  );
  addRecord(
    '关系记录：${persona.reviewOwner} 负责产品评审和体验文案；合同付款以前找 ${persona.paymentOwnerStale}。',
    entities: [persona.reviewOwner, persona.paymentOwnerStale],
    fields: ['产品评审', '体验文案'],
  );
  addRecord(
    '付款流程更新：以后合同付款和发票确认找 ${persona.paymentOwnerCurrent}，${persona.paymentOwnerStale} 只适用于旧项目。',
    entities: [persona.paymentOwnerCurrent],
    fields: ['合同付款', '发票确认', persona.paymentOwnerCurrent],
    relatedTo: ['rec_0007'],
  );
  addRecord(
    '临时噪声：今天只是想喝临时奶茶，晚上住短期酒店，路上看到网页广告截图；这些都不要长期化。',
    fields: ['临时奶茶', '短期酒店', '网页广告截图'],
    mustNot: ['长期偏好'],
  );

  while (recordNumber <= records) {
    final cycle = ((recordNumber - 10) ~/ 10) + 1;
    switch ((recordNumber - 10) % 10) {
      case 0:
        addRecord(
          '${persona.project} 第 $cycle 轮复盘：${persona.projectOwnerCurrent} 仍负责 owner，回滚演练是上线前置项。',
          entities: [persona.project, persona.projectOwnerCurrent],
          fields: [persona.project, persona.projectOwnerCurrent, '回滚演练'],
          relatedTo: ['rec_0004'],
        );
        break;
      case 1:
        addRecord(
          '${persona.partnerProject} 第 $cycle 次验证：${persona.partnerOwnerCurrent} 确认接口验收继续由她负责。',
          entities: [persona.partnerProject, persona.partnerOwnerCurrent],
          fields: [persona.partnerProject, persona.partnerOwnerCurrent],
          relatedTo: ['rec_0006'],
        );
        break;
      case 2:
        addRecord(
          '长期协作偏好重复确认：涉及 ${persona.project} 或 ${persona.partnerProject}，回答要先最新结论，再给风险、下一步、owner、证据来源。',
          fields: ['最新结论', '风险', '下一步', 'owner', '证据来源'],
        );
        break;
      case 3:
        addRecord(
          '关系补充：${persona.reviewOwner} 不负责合同付款；付款和发票还是找 ${persona.paymentOwnerCurrent}。',
          entities: [persona.reviewOwner, persona.paymentOwnerCurrent],
          fields: ['合同付款', '发票', persona.paymentOwnerCurrent],
          mustNot: [persona.paymentOwnerStale],
          relatedTo: ['rec_0008'],
        );
        break;
      case 4:
        addRecord(
          '问题式记录：我上次是不是说过 ${persona.partnerProject} 的失败恢复要和 ${persona.project} 的回滚演练口径一致？这句话要作为事实保留。',
          entities: [persona.partnerProject, persona.project],
          fields: ['失败恢复', '回滚演练', '事实保留'],
          relatedTo: ['rec_0005', 'rec_0001'],
        );
        break;
      case 5:
        addRecord(
          '反思不是行动：我也许应该以后早点准备周报，但现在不要创建提醒或行动，只记录这个反思。',
          fields: ['反思', '不要创建提醒'],
          mustNot: ['提醒已创建', '日程已创建'],
        );
        break;
      case 6:
        addRecord(
          '高敏边界样本：这是一条财务压力复盘，只记录情绪和事实，不要给确定性投资建议或税务结论。',
          fields: ['财务压力', '不要给确定性投资建议'],
          mustNot: ['买入', '卖出', '避税'],
        );
        break;
      case 7:
        addRecord(
          '已解析截图上下文：OCR 文字显示 ${persona.project} 的灰度风险列表，Agent 只需要使用这段已给定文本，不评估 OCR 本身。',
          entities: [persona.project],
          fields: ['OCR', '灰度风险'],
        );
        break;
      case 8:
        addRecord(
          '长上下文锚点：如果很久以后问 ${persona.project} 和 ${persona.partnerProject} 的 owner，请优先用当前 owner，不要使用旧 owner。',
          entities: [persona.project, persona.partnerProject],
          fields: ['当前 owner'],
          mustNot: [persona.projectOwnerStale, persona.partnerOwnerStale],
        );
        break;
      default:
        addRecord(
          '低信号噪声：随手记一个临时心情和广告词，不要写入长期画像，也不要影响 ${persona.deepWorkWindow} 的安排。',
          fields: ['临时心情', persona.deepWorkWindow],
        );
    }
  }

  final afterRecords = baseDate.add(Duration(hours: records * 3));
  void addOperation(JsonMap operation, int hourOffset) {
    operations.add({
      ...operation,
      'time': afterRecords.add(Duration(hours: hourOffset)).toIso8601String(),
    });
  }

  addOperation(
      _recallOperation(
        id: 'recall_project_owner',
        query: '${persona.project} 当前 owner 是谁？不要回答旧 owner。',
        must: [persona.project, persona.projectOwnerCurrent],
        mustNot: [_staleOwnerAssertion(persona.projectOwnerStale)],
      ),
      1);
  addOperation(
      _recallOperation(
        id: 'recall_partner_owner',
        query: '${persona.partnerProject} 当前接口验收 owner 是谁？',
        must: [persona.partnerProject, persona.partnerOwnerCurrent],
        mustNot: [_staleOwnerAssertion(persona.partnerOwnerStale)],
      ),
      2);
  addOperation(
      _recallOperation(
        id: 'recall_relationship_payment',
        query: '产品评审找谁？合同付款和发票确认找谁？',
        must: [persona.reviewOwner, persona.paymentOwnerCurrent],
        mustNot: [_stalePaymentAssertion(persona.paymentOwnerStale)],
      ),
      3);
  addOperation({'id': 'projection_001', 'type': 'para_projection'}, 4);
  addOperation(
      _askOperation(
        id: 'ask_project_owner',
        query: '${persona.project} 当前 owner 是谁？请给依据。',
        must: [persona.project, persona.projectOwnerCurrent],
        mustNot: [_staleOwnerAssertion(persona.projectOwnerStale)],
        expectedSources: factIdsForRecords([
          4,
          ...repeatingRecordsForCase(0),
        ]),
        expectedToolArgGroups: [
          [persona.project],
          ['owner'],
        ],
      ),
      5);
  addOperation(
      _askOperation(
        id: 'ask_report_style',
        query:
            '以后写 ${persona.project} 或 ${persona.partnerProject} 相关技术报告，格式偏好是什么？',
        must: [
          persona.project,
          persona.partnerProject,
          '最新结论',
          '风险',
          '证据来源',
        ],
        mustNot: [],
        expectedSources: factIdsForRecords([
          2,
          ...repeatingRecordsForCase(2),
        ]),
        expectedToolArgGroups: [
          [persona.project],
          [persona.partnerProject],
        ],
      ),
      6);
  addOperation(
      _askOperation(
        id: 'ask_relationship_payment',
        query: '产品评审找谁？合同付款和发票确认找谁？',
        must: [persona.reviewOwner, persona.paymentOwnerCurrent],
        mustNot: [_stalePaymentAssertion(persona.paymentOwnerStale)],
        expectedSources: factIdsForRecords([
          7,
          8,
          ...repeatingRecordsForCase(3),
        ]),
        expectedToolArgGroups: [
          ['产品评审'],
          ['合同付款'],
        ],
      ),
      7);
  addOperation(
      _askOperation(
        id: 'ask_home_routine',
        query: '我常驻哪里？${persona.deepWorkWindow} 一般怎么安排？',
        must: [persona.city, persona.deepWorkWindow, '深度工作'],
        mustNot: ['短期酒店'],
        expectedSources: factIdsForRecords([3]),
        expectedToolArgGroups: [
          ['常驻'],
          [persona.deepWorkWindow],
        ],
      ),
      8);

  return {
    'case_id': 'pr256_full_metric_persona_${index.toString().padLeft(2, '0')}',
    'persona': {
      'user_id': 'pr256_full_persona_$index',
      'role': persona.role,
      'city': persona.city,
    },
    'coverage': {
      'scenario_families': [
        'life_stream',
        'product_self_test',
        'execution_external_brain',
        'emotion_relationship_review',
        'knowledge_decision_pool',
        'sensitive_domain',
        'parsed_multimodal_context',
        'long_context_fact',
        'long_dialog_followup',
        'failure_degradation',
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
        'parsed_ocr_text',
      ],
      'journey_stages': [
        'capture',
        'route',
        'card',
        'memory_write',
        'pkm',
        'recall',
        'projection',
        'ask',
        'judge',
      ],
      'relationship_case': true,
      'long_context_case': true,
      'dataset_oracle_audited': true,
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

JsonMap _recallOperation({
  required String id,
  required String query,
  required List<Object> must,
  required List<Object> mustNot,
}) {
  return {
    'id': id,
    'type': 'memory_recall',
    'query': query,
    'expected': {
      'must_contain': must,
      'must_not_contain': mustNot,
    },
  };
}

JsonMap _askOperation({
  required String id,
  required String query,
  required List<Object> must,
  required List<Object> mustNot,
  required List<String> expectedSources,
  List<List<String>>? expectedToolArgGroups,
}) {
  final toolArgGroups = expectedToolArgGroups ??
      [
        must.take(1).map((e) => e.toString()).toList(),
      ];
  return {
    'id': id,
    'type': 'super_agent_ask',
    'query': query,
    'quick_query': true,
    'expected': {
      'must_contain': must,
      'must_not_contain': mustNot,
      'read_only': true,
      'by_mode': {
        'legacy_pkm': {
          'max_tool_calls': 8,
          'forbidden_tools': ['save_memory_primary', 'write_file'],
        },
        'memory_primary': {
          'expected_tools': ['search_memory_primary'],
          'expected_tool_args_contains': [
            for (final group in toolArgGroups)
              {
                'tool': 'search_memory_primary',
                'must_contain': group,
              }
          ],
          'expected_sources': expectedSources,
          'max_tool_calls': 6,
          'forbidden_tools': ['write_file', 'save_file', 'update_memory'],
        },
      },
      'judge_tasks': [
        {
          'metric': 'unsupported_claim_absence',
          'rubric':
              'Answer should not assert facts outside the supplied record, memory, card, or PKM evidence.',
        },
        {
          'metric': 'grounded_answer_rate',
          'rubric':
              'Answer should be complete, concise, and grounded in cited or retrievable evidence.',
        },
      ],
    },
  };
}

JsonMap _anyOf(String label, List<String> values) => {
      'label': label,
      'any_of': values,
    };

JsonMap _staleOwnerAssertion(String owner) => _anyOf(
      '$owner as current owner',
      [
        '当前 owner 是 $owner',
        '当前owner是$owner',
        '$owner 仍是 owner',
        '$owner 是当前 owner',
      ],
    );

JsonMap _stalePaymentAssertion(String owner) => _anyOf(
      '$owner as current payment owner',
      [
        '合同付款找 $owner',
        '发票确认找 $owner',
        '$owner 负责合同付款',
        '$owner 负责发票确认',
      ],
    );

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _datePath(DateTime time) {
  return '${time.year.toString().padLeft(4, '0')}/'
      '${time.month.toString().padLeft(2, '0')}/'
      '${time.day.toString().padLeft(2, '0')}';
}

_Persona _persona(int index) {
  const cities = ['杭州', '上海', '深圳', '北京', '成都', '南京', '广州', '苏州'];
  final suffix = String.fromCharCode('A'.codeUnitAt(0) + (index % 26));
  return _Persona(
    role: 'AI native knowledge worker $suffix',
    city: cities[index % cities.length],
    deepWorkWindow: index.isEven ? '周三下午' : '周四上午',
    project: 'Project Orion $suffix',
    projectOwnerStale: 'Alex$suffix',
    projectOwnerCurrent: 'Bao$suffix',
    partnerProject: 'Meridian 导出 $suffix',
    partnerOwnerStale: 'Cary$suffix',
    partnerOwnerCurrent: 'Dana$suffix',
    reviewOwner: 'Maya$suffix',
    paymentOwnerStale: 'Leo$suffix',
    paymentOwnerCurrent: 'Noor$suffix',
  );
}

int? _intEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
}

class _Persona {
  const _Persona({
    required this.role,
    required this.city,
    required this.deepWorkWindow,
    required this.project,
    required this.projectOwnerStale,
    required this.projectOwnerCurrent,
    required this.partnerProject,
    required this.partnerOwnerStale,
    required this.partnerOwnerCurrent,
    required this.reviewOwner,
    required this.paymentOwnerStale,
    required this.paymentOwnerCurrent,
  });

  final String role;
  final String city;
  final String deepWorkWindow;
  final String project;
  final String projectOwnerStale;
  final String projectOwnerCurrent;
  final String partnerProject;
  final String partnerOwnerStale;
  final String partnerOwnerCurrent;
  final String reviewOwner;
  final String paymentOwnerStale;
  final String paymentOwnerCurrent;
}
