import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main() async {
  final repoRoot = Directory.current.path;
  final personaCount = math.max(1, _intEnv('MEMEX_EVAL_PERSONA_COUNT') ?? 3);
  final recordsPerPersona = math.max(
    24,
    _intEnv('MEMEX_EVAL_RECORDS_PER_PERSONA') ?? 48,
  );
  final agentQueriesPerPersona = math.max(
    0,
    _intEnv('MEMEX_EVAL_AGENT_QUERIES_PER_PERSONA') ??
        math.max(4, math.min(50, recordsPerPersona ~/ 8)),
  );
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
      _buildPersonaCase(
        index: i,
        records: recordsPerPersona,
        agentQueries: agentQueriesPerPersona,
      ),
  ];
  await File(
    p.join(outDir.path, 'cases.jsonl'),
  ).writeAsString('${cases.map(jsonEncode).join('\n')}\n', flush: true);
  await File(p.join(outDir.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'name': p.basename(outDir.path),
      'description':
          'PR #256 full-metric synthetic dataset. Ground truth is generated together with operations so the replay can compute deterministic GT/Trace metrics and emit LLM judge tasks for subjective metrics.',
      'generated_by': 'evals/bin/generate_pr256_full_metric_dataset.dart',
      'schema_version': 'pr256_full_metric.v1',
      'persona_count': personaCount,
      'records_per_persona': recordsPerPersona,
      'agent_queries_per_persona': agentQueriesPerPersona,
      'record_count': personaCount * recordsPerPersona,
      'agent_query_count': personaCount * agentQueriesPerPersona,
      'recommended_small_gate': {
        'persona_count': 3,
        'records_per_persona': 48,
        'agent_queries_per_persona': 6,
      },
      'required_scale_gate': {
        'persona_count_min': 12,
        'records_per_persona_min': 600,
        'agent_queries_per_persona_min': 50,
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
    '$recordsPerPersona records/persona and '
    '$agentQueriesPerPersona interleaved asks/persona at ${outDir.path}',
  );
}

JsonMap _buildPersonaCase({
  required int index,
  required int records,
  required int agentQueries,
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
    persona.role,
    persona.secondaryRole,
    persona.moodAfter,
    persona.conflictTopic,
    _anyOf('latest conclusion', ['最新结论', '最新的结论', '冲突']),
    _anyOf('evidence source', ['证据来源', 'evidence source', '原始记录']),
  ];
  final memoryMustNotContain = <Object>[
    _staleOwnerAssertion(persona.projectOwnerStale),
    _staleOwnerAssertion(persona.partnerOwnerStale),
    _stalePaymentAssertion(persona.paymentOwnerStale),
    '临时奶茶',
    '短期酒店',
    _tripCityAsPermanentAssertion(persona.travelCity),
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
  var interleavedAskNumber = 0;
  final interleavedAskRecordNumbers = _queryTriggerRecords(
    records: records,
    queryCount: agentQueries,
  );

  String factIdForRecord(int targetRecordNumber) {
    final targetTime = baseDate.add(
      Duration(hours: (targetRecordNumber - 1) * 3),
    );
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

  List<String> factIdsForAvailableRecords(Iterable<int> recordNumbers) {
    final latestRecord = math.max(1, recordNumber);
    return factIdsForRecords(
      recordNumbers.where((record) => record <= latestRecord),
    );
  }

  void maybeAddInterleavedAsk(int completedRecordNumber, DateTime recordTime) {
    if (!interleavedAskRecordNumbers.contains(completedRecordNumber)) return;
    final operation = _interleavedAskOperation(
      persona: persona,
      askIndex: interleavedAskNumber,
      factIdsForRecords: factIdsForAvailableRecords,
      repeatingRecordsForCase: repeatingRecordsForCase,
    );
    operations.add({
      ...operation,
      'time': recordTime.add(const Duration(minutes: 45)).toIso8601String(),
    });
    interleavedAskNumber += 1;
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
            },
          ],
        },
      },
    });
    maybeAddInterleavedAsk(recordNumber, time);
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
    '个人长期偏好：我常驻${persona.city}，主要角色是${persona.role}，${persona.deepWorkWindow}通常留给深度工作，不安排评审会。',
    entities: [persona.city],
    fields: [persona.city, persona.role, persona.deepWorkWindow, '深度工作'],
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
          '角色转换和反思不是行动：上午以${persona.role}看 ${persona.project} 上线风险，下午切到${persona.secondaryRole}整理 ${persona.partnerProject} 客户反馈；心态从${persona.moodBefore}转为${persona.moodAfter}，现在不要创建提醒或行动。',
          fields: [
            persona.role,
            persona.secondaryRole,
            persona.moodAfter,
            '不要创建提醒',
          ],
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
          '已解析截图上下文：OCR 文字显示 ${persona.project} 的灰度风险列表；${persona.reviewOwner} 和 ${persona.paymentOwnerCurrent} 对${persona.conflictTopic}有分歧，最终由 ${persona.projectOwnerCurrent} 仲裁。Agent 只需要使用这段已给定文本，不评估 OCR 本身。',
          entities: [
            persona.project,
            persona.reviewOwner,
            persona.paymentOwnerCurrent,
            persona.projectOwnerCurrent,
          ],
          fields: ['OCR', '灰度风险', persona.conflictTopic, '仲裁'],
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
          '低信号噪声和地点变化：下周去${persona.travelCity}住两晚只是短期行程，不改变常驻${persona.city}；随手广告词也不要写入长期画像。',
          fields: ['短期行程', persona.travelCity, persona.city],
          mustNot: ['常驻${persona.travelCity}'],
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
    1,
  );
  addOperation(
    _recallOperation(
      id: 'recall_partner_owner',
      query: '${persona.partnerProject} 当前接口验收 owner 是谁？',
      must: [persona.partnerProject, persona.partnerOwnerCurrent],
      mustNot: [_staleOwnerAssertion(persona.partnerOwnerStale)],
    ),
    2,
  );
  addOperation(
    _recallOperation(
      id: 'recall_relationship_payment',
      query: '产品评审找谁？合同付款和发票确认找谁？',
      must: [persona.reviewOwner, persona.paymentOwnerCurrent],
      mustNot: [_stalePaymentAssertion(persona.paymentOwnerStale)],
    ),
    3,
  );
  addOperation({'id': 'projection_001', 'type': 'para_projection'}, 4);

  return {
    'case_id': 'pr256_full_metric_persona_${index.toString().padLeft(2, '0')}',
    'persona': {
      'user_id': 'pr256_full_persona_$index',
      'role': persona.role,
      'secondary_role': persona.secondaryRole,
      'city': persona.city,
      'travel_city': persona.travelCity,
      'mood_before': persona.moodBefore,
      'mood_after': persona.moodAfter,
      'conflict_topic': persona.conflictTopic,
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
        'role_transition',
        'location_shift',
        'conflict_resolution',
        'memory_recall',
        'super_agent_ask',
      ],
      'input_channels': [
        'text',
        'meeting_note',
        'browser_clip',
        'relationship_note',
        'parsed_ocr_text',
        'role_shift_note',
        'location_note',
        'conflict_note',
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
        'interleaved_ask',
        'judge',
      ],
      'relationship_case': true,
      'long_context_case': true,
      'interleaved_agent_query_count': interleavedAskNumber,
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
    'expected': {'must_contain': must, 'must_not_contain': mustNot},
  };
}

JsonMap _askOperation({
  required String id,
  required String queryFamily,
  required String query,
  required List<Object> must,
  required List<Object> mustNot,
  required List<String> expectedSources,
  List<List<String>>? expectedToolArgGroups,
}) {
  final toolArgGroups =
      expectedToolArgGroups ?? [must.take(1).map((e) => e.toString()).toList()];
  return {
    'id': id,
    'type': 'super_agent_ask',
    'query': query,
    'quick_query': true,
    'metadata': {'query_family': queryFamily, 'interleaved': true},
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
              {'tool': 'search_memory_primary', 'must_contain': group},
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

Set<int> _queryTriggerRecords({required int records, required int queryCount}) {
  if (records <= 0 || queryCount <= 0) return const {};
  final start = math.min(records, 4);
  if (queryCount == 1) return {start};
  final result = <int>{};
  final end = math.max(start, records - 1);
  final span = math.max(1, end - start);
  for (var i = 0; i < queryCount; i++) {
    var record = start + (span * i / (queryCount - 1)).round();
    record = record.clamp(start, end).toInt();
    while (result.contains(record) && record < end) {
      record += 1;
    }
    result.add(record);
  }
  return result;
}

JsonMap _interleavedAskOperation({
  required _Persona persona,
  required int askIndex,
  required List<String> Function(Iterable<int>) factIdsForRecords,
  required List<int> Function(int) repeatingRecordsForCase,
}) {
  final id = 'ask_interleaved_${(askIndex + 1).toString().padLeft(3, '0')}';
  switch (askIndex % 10) {
    case 0:
      return _askOperation(
        id: id,
        queryFamily: 'project_owner_current',
        query: '${persona.project} 当前 owner 是谁？请给依据。',
        must: [persona.project, persona.projectOwnerCurrent],
        mustNot: [_staleOwnerAssertion(persona.projectOwnerStale)],
        expectedSources: factIdsForRecords([4, ...repeatingRecordsForCase(0)]),
        expectedToolArgGroups: [
          [persona.project],
          ['owner'],
        ],
      );
    case 1:
      return _askOperation(
        id: id,
        queryFamily: 'partner_owner_disambiguation',
        query: '${persona.partnerProject} 现在是谁负责接口验收？不要混到 ${persona.project}。',
        must: [persona.partnerProject, persona.partnerOwnerCurrent],
        mustNot: [_staleOwnerAssertion(persona.partnerOwnerStale)],
        expectedSources: factIdsForRecords([6, ...repeatingRecordsForCase(1)]),
        expectedToolArgGroups: [
          [persona.partnerProject],
          ['接口验收'],
        ],
      );
    case 2:
      return _askOperation(
        id: id,
        queryFamily: 'relationship_responsibility_split',
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
      );
    case 3:
      return _askOperation(
        id: id,
        queryFamily: 'report_preference',
        query:
            '以后写 ${persona.project} 或 ${persona.partnerProject} 相关技术报告，格式偏好是什么？',
        must: [persona.project, persona.partnerProject, '最新结论', '风险', '证据来源'],
        mustNot: [],
        expectedSources: factIdsForRecords([2, ...repeatingRecordsForCase(2)]),
        expectedToolArgGroups: [
          [persona.project],
          [persona.partnerProject],
        ],
      );
    case 4:
      return _askOperation(
        id: id,
        queryFamily: 'location_routine',
        query: '我常驻哪里？${persona.deepWorkWindow} 一般怎么安排？',
        must: [persona.city, persona.deepWorkWindow, '深度工作'],
        mustNot: ['短期酒店'],
        expectedSources: factIdsForRecords([3]),
        expectedToolArgGroups: [
          ['常驻'],
          [persona.deepWorkWindow],
        ],
      );
    case 5:
      return _askOperation(
        id: id,
        queryFamily: 'role_mood_transition',
        query:
            '我在 ${persona.project} 和 ${persona.partnerProject} 之间切换了哪两个角色？阶段心态是什么？',
        must: [persona.role, persona.secondaryRole, persona.moodAfter],
        mustNot: ['提醒已创建', '日程已创建'],
        expectedSources: factIdsForRecords([15, ...repeatingRecordsForCase(5)]),
        expectedToolArgGroups: [
          [persona.project],
          [persona.partnerProject],
          ['角色'],
          ['心态'],
        ],
      );
    case 6:
      return _askOperation(
        id: id,
        queryFamily: 'sensitive_boundary',
        query: '如果问到财务压力复盘，你能不能给确定性投资建议？',
        must: ['只记录情绪和事实', '不要给确定性投资建议'],
        mustNot: ['买入', '卖出', '避税'],
        expectedSources: factIdsForRecords([16, ...repeatingRecordsForCase(6)]),
        expectedToolArgGroups: [
          ['财务压力'],
          ['投资建议'],
        ],
      );
    case 7:
      return _askOperation(
        id: id,
        queryFamily: 'failure_recovery_alignment',
        query: '失败恢复和回滚演练这两个口径之前是不是要求保持一致？',
        must: ['失败恢复', '回滚演练'],
        mustNot: [],
        expectedSources: factIdsForRecords([14, ...repeatingRecordsForCase(4)]),
        expectedToolArgGroups: [
          ['失败恢复'],
          ['回滚演练'],
        ],
      );
    case 8:
      return _askOperation(
        id: id,
        queryFamily: 'ocr_conflict_grounding',
        query: '最近 OCR 里的 ${persona.project} 风险列表，Agent 应该怎么处理？',
        must: [persona.project, 'OCR', '给定文本', persona.conflictTopic],
        mustNot: ['评估 OCR 本身'],
        expectedSources: factIdsForRecords([17, ...repeatingRecordsForCase(7)]),
        expectedToolArgGroups: [
          [persona.project],
          ['OCR'],
          [persona.conflictTopic],
        ],
      );
    default:
      return _askOperation(
        id: id,
        queryFamily: 'owner_only_scope',
        query: '如果我只问 ${persona.project} 的 owner，你应该只回答什么？',
        must: [persona.project, persona.projectOwnerCurrent],
        mustNot: ['风险', '下一步'],
        expectedSources: factIdsForRecords([4, ...repeatingRecordsForCase(0)]),
        expectedToolArgGroups: [
          [persona.project],
          ['owner'],
        ],
      );
  }
}

JsonMap _anyOf(String label, List<String> values) => {
      'label': label,
      'any_of': values,
    };

JsonMap _staleOwnerAssertion(String owner) =>
    _anyOf('$owner as current owner', [
      '当前 owner 是 $owner',
      '当前owner是$owner',
      '$owner 仍是 owner',
      '$owner 是当前 owner',
    ]);

JsonMap _stalePaymentAssertion(String owner) => _anyOf(
      '$owner as current payment owner',
      ['合同付款找 $owner', '发票确认找 $owner', '$owner 负责合同付款', '$owner 负责发票确认'],
    );

JsonMap _tripCityAsPermanentAssertion(String city) => _anyOf(
      '$city as permanent city',
      ['常驻$city', '常驻城市是$city', '$city 是常驻地', '长期住在$city'],
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
  const roles = [
    'AI 产品经理',
    '远程工程负责人',
    '增长运营负责人',
    '内容策略负责人',
    '数据分析师',
    '客户成功负责人',
    '创始人助理',
    '独立设计顾问',
    '本地生活商家',
    '研究型产品顾问',
    '供应链项目经理',
    '教育产品运营',
  ];
  const secondaryRoles = [
    '客户访谈整理者',
    '上线风险协调人',
    '跨团队沟通窗口',
    '预算复核人',
    '文案审校人',
    '数据口径守门人',
    '现场排期协调人',
    '外部合作接口人',
    '用户反馈归纳者',
    '复盘主持人',
    '验收清单维护者',
    '灰度公告负责人',
  ];
  const cities = [
    '杭州',
    '上海',
    '深圳',
    '北京',
    '成都',
    '南京',
    '广州',
    '苏州',
    '新加坡',
    '东京',
    '柏林',
    '温哥华',
  ];
  const travelCities = [
    '厦门',
    '香港',
    '首尔',
    '台北',
    '武汉',
    '青岛',
    '重庆',
    '伦敦',
    '巴黎',
    '曼谷',
    '洛杉矶',
    '墨尔本',
  ];
  const moodBefore = [
    '有点焦虑',
    '明显疲惫',
    '兴奋但分散',
    '谨慎怀疑',
    '压力偏高',
    '有些失落',
  ];
  const moodAfter = [
    '谨慎乐观',
    '更稳定',
    '重新聚焦',
    '保留疑问但愿意推进',
    '压力下降',
    '恢复耐心',
  ];
  const conflictTopics = [
    '发布时间窗口',
    '合同付款节奏',
    '灰度风险优先级',
    '客户沟通口径',
    '数据口径解释',
    '发票确认顺序',
  ];
  final suffix = String.fromCharCode('A'.codeUnitAt(0) + (index % 26));
  return _Persona(
    role: '${roles[index % roles.length]} $suffix',
    secondaryRole: '${secondaryRoles[index % secondaryRoles.length]} $suffix',
    city: cities[index % cities.length],
    travelCity: travelCities[index % travelCities.length],
    moodBefore: moodBefore[index % moodBefore.length],
    moodAfter: moodAfter[index % moodAfter.length],
    conflictTopic: conflictTopics[index % conflictTopics.length],
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
    required this.secondaryRole,
    required this.city,
    required this.travelCity,
    required this.moodBefore,
    required this.moodAfter,
    required this.conflictTopic,
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
  final String secondaryRole;
  final String city;
  final String travelCity;
  final String moodBefore;
  final String moodAfter;
  final String conflictTopic;
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
