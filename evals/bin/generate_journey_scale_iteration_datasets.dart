import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final variants = args.isEmpty
      ? _variants
      : _variants.where(
          (variant) =>
              args.contains(variant.id) || args.contains(variant.outputDir),
        );

  if (variants.isEmpty) {
    throw ArgumentError(
      'Unknown variant. Use one of: ${_variants.map((v) => v.id).join(', ')}',
    );
  }

  for (final variant in variants) {
    await _writeVariant(variant);
  }
}

Future<void> _writeVariant(_VariantSpec variant) async {
  final outDir = Directory(variant.outputDir);
  await outDir.create(recursive: true);

  final cases = [
    for (var i = 0; i < _personas.length; i++)
      _case(n: i + 1, persona: _personas[i], variant: variant),
  ];

  final operationCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['operations'] as List).length,
  );
  final recordCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        (evalCase['operations'] as List)
            .where(
              (operation) => operation is Map && operation['type'] == 'record',
            )
            .length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_${variant.id}',
    'version': variant.version,
    'description': variant.description,
    'created_at': '2026-05-16',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'records_per_persona': variant.recordsPerPersona,
    'input_count': recordCount,
    'record_operation_count': recordCount,
    'operation_count': operationCount,
    'eval_task_count': taskCount,
    'families': [variant.family],
    'evidence_goal': variant.evidenceGoal,
    'journey_stages': variant.journeyStages,
    'scenario_families': variant.scenarioFamilies,
    'feature_points': _featureTriggers(variant),
    'notes': [
      '${_personas.length} 个 persona，每个 persona 用几百条跨日 record 操作模拟本地优先生活记录。',
      'fixture_observed 用于快速验证 grader、指标聚合和报告结构；它不声称真实 Agent 已完成同等规模 replay。',
      'operations 中保留 fetch_timeline、post_comment、refresh_schedule_aggregation、refresh_knowledge_insights、wait_memory 和 ask_super_agent，方便未来抽样切到真实 replay。',
      'Round 2 在 Round 1 基础上增加输入量、场景族、追问/纠错样本和 journey 指标。',
      if (variant.round >= 3)
        'Round 3 把用户数扩到 12，并增加会议纪要、浏览器剪贴、银行短信、日历片段、票据扫描等输入渠道，为 v4 真实 replay 做源数据池。',
    ],
  };

  await File('${outDir.path}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File(
    '${outDir.path}/cases.jsonl',
  ).writeAsString('${cases.map(jsonEncode).join('\n')}\n', flush: true);

  stdout.writeln(
    'Generated ${variant.id}: ${cases.length} users, '
    '$recordCount records, $taskCount tasks at ${outDir.path}',
  );
}

JsonMap _case({
  required int n,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) {
  final caseId = '${variant.casePrefix}_${_two(n)}';
  final records = _recordOperations(
    caseId: caseId,
    persona: persona,
    variant: variant,
  );
  final appOperations = _appOperations(
    caseId: caseId,
    persona: persona,
    variant: variant,
  );
  final operations = [...records, ...appOperations];
  final tasks = [
    _costTask(
      caseId: caseId,
      persona: persona,
      variant: variant,
      records: records,
      operationCount: operations.length,
    ),
    _memoryTask(caseId: caseId, persona: persona, variant: variant),
    _retrievalTask(caseId: caseId, persona: persona, variant: variant),
    _scheduleTask(caseId: caseId, persona: persona, variant: variant),
    _pkmTask(caseId: caseId, persona: persona, variant: variant),
    _superAgentTask(caseId: caseId, persona: persona, variant: variant),
    _toolTask(caseId: caseId, persona: persona, variant: variant),
    _cardTask(
      caseId: caseId,
      taskId: '${caseId}_card_project_milestone',
      operationId: _recordId(caseId, 48),
      titleContains: [persona.project, persona.primaryPerson],
      fieldContains: {
        'summary': [persona.project, persona.primaryPerson, persona.artifact],
      },
    ),
    if (variant.round >= 2)
      _retrievalTask(
        caseId: caseId,
        persona: persona,
        variant: variant,
        followUp: true,
      ),
    if (variant.round >= 2)
      _cardTask(
        caseId: caseId,
        taskId: '${caseId}_card_cross_domain_review',
        operationId: _recordId(caseId, 160),
        titleContains: [persona.scenarioAnchor, persona.secondaryPerson],
        fieldContains: {
          'summary': [
            persona.scenarioAnchor,
            persona.secondaryPerson,
            persona.personalBoundary,
          ],
        },
      ),
  ];

  return {
    'case_id': caseId,
    'family': variant.family,
    'language': 'zh-CN',
    'persona': {
      'user_id': persona.userId,
      'profile': {
        'occupation': persona.occupation,
        'city': persona.city,
        'project': persona.project,
        'habits': persona.habits,
        'preferences': [
          '偏好中文输出',
          '结论先行',
          persona.responsePreference,
        ],
      },
    },
    'ground_truth_world': {
      'facts': [
        {
          'id': '${caseId}_fact_reminder',
          'type': 'preference',
          'content': '重要安排需要提前一天提醒，并带上来源或材料。',
          'source_ids': [_recordId(caseId, 1)],
        },
        {
          'id': '${caseId}_fact_correction_latest',
          'type': 'preference',
          'content': persona.newPreference,
          'source_ids': [_recordId(caseId, 5), _recordId(caseId, 120)],
        },
        {
          'id': '${caseId}_fact_project_owner',
          'type': 'project',
          'content':
              '${persona.project} 主要找 ${persona.primaryPerson} 对齐，材料看 ${persona.artifact}。',
          'source_ids': [_recordId(caseId, 6), _recordId(caseId, 48)],
        },
        {
          'id': '${caseId}_fact_boundary',
          'type': 'boundary',
          'content': persona.personalBoundary,
          'source_ids': [_recordId(caseId, 18)],
        },
      ],
      'events': [
        {
          'id': _recordId(caseId, 4),
          'title': '和 ${persona.primaryPerson} 讨论 ${persona.project}',
          'time': _recordTime(4),
        },
        {
          'id': _recordId(caseId, 48),
          'title': '${persona.project} 里程碑复盘',
          'time': _recordTime(48),
        },
        {
          'id': _recordId(caseId, 160),
          'title': '${persona.scenarioAnchor} 跨域复盘',
          'time': _recordTime(160),
        },
      ],
      'scenario_notes': persona.scenarioNotes,
    },
    'operations': operations,
    'eval_tasks': tasks,
  };
}

List<JsonMap> _recordOperations({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    [
      for (var index = 1; index <= variant.recordsPerPersona; index++)
        {
          'id': _recordId(caseId, index),
          'type': 'record',
          'time': _recordTime(index),
          'channel': _channelFor(index, variant),
          'content': _recordContent(
            index: index,
            persona: persona,
            variant: variant,
          ),
          'journey_stage': _journeyStageFor(index, variant),
          'scenario_family': _scenarioFamilyFor(index, persona, variant),
          if (_isCorrection(index)) 'is_correction': true,
          if (_isNoise(index)) 'is_noise': true,
          if (_isCrossDayLink(index)) 'cross_day_link': true,
        },
    ];

List<JsonMap> _appOperations({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) {
  final lastRecordTime = _recordTime(variant.recordsPerPersona);
  return [
    {
      'id': '${caseId}_fetch_month_001',
      'type': 'fetch_timeline',
      'time': lastRecordTime,
      'date_from': _recordTime(max(1, variant.recordsPerPersona - 90)),
      'date_to': lastRecordTime,
      'limit': 120,
    },
    {
      'id': '${caseId}_comment_001',
      'type': 'post_comment',
      'time': _recordTime(variant.recordsPerPersona + 1),
      'target_operation_id': _recordId(caseId, 48),
      'content':
          '补充：这条要和 ${persona.primaryPerson} 二次确认，并标注 ${persona.artifact} 来源。',
    },
    {
      'id': '${caseId}_schedule_refresh_001',
      'type': 'refresh_schedule_aggregation',
      'time': _recordTime(variant.recordsPerPersona + 2),
    },
    {
      'id': '${caseId}_insight_refresh_001',
      'type': 'refresh_knowledge_insights',
      'time': _recordTime(variant.recordsPerPersona + 3),
    },
    {
      'id': '${caseId}_wait_memory_001',
      'type': 'wait_memory',
      'time': _recordTime(variant.recordsPerPersona + 4),
      'timeout_seconds': 240,
      'must_include_any': [persona.project, persona.primaryPerson, '提前一天'],
    },
    {
      'id': '${caseId}_ask_001',
      'type': 'ask_super_agent',
      'time': _recordTime(variant.recordsPerPersona + 5),
      'query':
          '总结一下 ${persona.project} 的负责人、提醒偏好和我最新的 ${persona.preferenceTopic} 边界。',
      'quick_query': true,
    },
    if (variant.round >= 2)
      {
        'id': '${caseId}_ask_followup_001',
        'type': 'ask_super_agent',
        'time': _recordTime(variant.recordsPerPersona + 6),
        'query':
            '只基于已有记录，把 ${persona.scenarioAnchor} 和 ${persona.project} 之间的冲突点列出来，不确定就说明缺证据。',
        'quick_query': true,
      },
  ];
}

JsonMap _costTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
  required List<JsonMap> records,
  required int operationCount,
}) {
  final channels = records
      .map((record) => record['channel']?.toString() ?? '')
      .where((channel) => channel.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final scenarioFamilies = records
      .map((record) => record['scenario_family']?.toString() ?? '')
      .where((family) => family.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final correctionCount =
      records.where((record) => record['is_correction'] == true).length;
  final noiseCount =
      records.where((record) => record['is_noise'] == true).length;
  final crossDayCount =
      records.where((record) => record['cross_day_link'] == true).length;
  final followUpCount = variant.round >= 2 ? 7 : 4;

  return {
    'task_id': '${caseId}_cost',
    'type': 'cost_trace',
    'expected': {
      'max_total_tokens': variant.recordsPerPersona * 1600,
      'max_tokens_per_input': 1800,
      'max_latency_ms': 3600000,
      'max_tool_calls': 140,
      'max_retry_rate': 0.03,
      'max_failed_task_rate': 0,
      'max_queue_idle_ms': 2000,
      'require_all_tasks_completed': true,
      'min_record_operations': variant.recordsPerPersona,
      'min_journey_span_days': variant.minJourneySpanDays,
      'expected_operation_types': [
        'record',
        'fetch_timeline',
        'post_comment',
        'refresh_schedule_aggregation',
        'refresh_knowledge_insights',
        'wait_memory',
        'ask_super_agent',
      ],
      'expected_input_channels': variant.channels,
      'expected_feature_triggers': _featureTriggers(variant),
      'expected_journey_stages': variant.journeyStages,
      'expected_scenario_families': {
        ...variant.scenarioFamilies,
        ...persona.extraScenarioFamilies,
      }.toList(),
      'expected_persona_markers': [
        persona.occupation,
        persona.city,
        persona.project,
        persona.scenarioAnchor,
      ],
      'min_cross_day_links': variant.minCrossDayLinks,
      'min_correction_operations': variant.minCorrections,
      'min_noise_inputs': variant.minNoiseInputs,
      'min_follow_up_queries': variant.minFollowUps,
      'expected_trace_events': [
        'card_agent_task',
        'memory_sync_task',
        'pkm_agent_task',
        'schedule_refresh_router_task',
        'knowledge_insight_task',
        'search_memory',
      ],
      'must_include': ['Facts', 'Cards', 'PKM', 'Super Agent'],
    },
    'fixture_observed': {
      'answer':
          'Journey 已覆盖 Facts、Cards、PKM、日程刷新和 Super Agent 问答，记录数 ${variant.recordsPerPersona}。',
      'input_count': variant.recordsPerPersona,
      'operation_count': operationCount,
      'record_operation_count': variant.recordsPerPersona,
      'journey_span_days': variant.observedJourneySpanDays,
      'operation_types': [
        'record',
        'fetch_timeline',
        'post_comment',
        'refresh_schedule_aggregation',
        'refresh_knowledge_insights',
        'wait_memory',
        'ask_super_agent',
      ],
      'input_channels': channels,
      'feature_triggers': _featureTriggers(variant),
      'journey_stages': variant.journeyStages,
      'scenario_families': scenarioFamilies,
      'persona_markers': [
        persona.occupation,
        persona.city,
        persona.project,
        persona.scenarioAnchor,
      ],
      'cross_day_link_count': crossDayCount,
      'correction_operation_count': correctionCount,
      'noise_input_count': noiseCount,
      'follow_up_query_count': followUpCount,
      'queue_idle_ms': 640,
      'active_tasks': const [],
      'failed_tasks': const [],
      'task_status_counts': {
        'completed': variant.recordsPerPersona * 2 + 12,
      },
      'tasks_settled': true,
      'trace_events': [
        for (var i = 0; i < 18; i++)
          _taskTrace(
            i % 5 == 0
                ? 'knowledge_insight_task'
                : i % 4 == 0
                    ? 'schedule_refresh_router_task'
                    : i.isEven
                        ? 'card_agent_task'
                        : 'memory_sync_task',
            i,
          ),
        for (var i = 0; i < 10; i++)
          _toolTrace(i.isEven ? 'search_memory' : 'save_timeline_card', i),
        _taskTrace('pkm_agent_task', 99),
      ],
      'llm_calls': [
        for (var i = 0; i < 24; i++)
          _llmCall('journey_scale_agent', 4200 + i * 19, 380),
      ],
      'case_elapsed_ms': variant.recordsPerPersona * 1800,
      'suite_elapsed_ms': variant.recordsPerPersona * 1800 * _personas.length,
      'task_count': variant.recordsPerPersona * 2 + 12,
    },
  };
}

JsonMap _memoryTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    {
      'task_id': '${caseId}_memory',
      'type': 'memory_write',
      'expected': {
        'must_write': [
          {
            'id': '${caseId}_mem_reminder',
            'must_include': ['重要安排', '提前一天'],
            'source_ids': [_recordId(caseId, 1)],
          },
          {
            'id': '${caseId}_mem_latest_preference',
            'must_include': [persona.latestNeedle],
            'source_ids': [_recordId(caseId, 5)],
          },
          {
            'id': '${caseId}_mem_project_owner',
            'must_include': [persona.project, persona.primaryPerson],
            'source_ids': [_recordId(caseId, 6)],
          },
          if (variant.round >= 2)
            {
              'id': '${caseId}_mem_boundary',
              'must_include': [persona.boundaryNeedle],
              'source_ids': [_recordId(caseId, 18)],
            },
        ],
        'must_not_write': [
          {
            'id': '${caseId}_temp_mood',
            'must_include': ['今天有点烦'],
          },
          {
            'id': '${caseId}_one_off_trial',
            'must_include': ['只是试一下'],
          },
          {
            'id': '${caseId}_ocr_noise',
            'must_include': ['OCR 可能识别错'],
          },
        ],
        'conflicts': [
          {
            'latest_should_include': [persona.latestNeedle],
            'superseded_should_not_be_active': [persona.oldNeedle],
          },
        ],
        'evaluate_write_precision': false,
        'max_duplicate_rate': 0.2,
      },
      'fixture_observed': {
        'memory_entries': [
          {
            'id': '${caseId}_mem_reminder',
            'content': '重要安排需要提前一天提醒，并带上来源或材料。',
            'status': 'active',
            'source_ids': [_recordId(caseId, 1)],
          },
          {
            'id': '${caseId}_mem_old_preference',
            'content': persona.oldPreference,
            'status': 'superseded',
            'source_ids': [_recordId(caseId, 2)],
          },
          {
            'id': '${caseId}_mem_latest_preference',
            'content': persona.newPreference,
            'status': 'active',
            'source_ids': [_recordId(caseId, 5), _recordId(caseId, 120)],
          },
          {
            'id': '${caseId}_mem_project_owner',
            'content':
                '${persona.project} 主要找 ${persona.primaryPerson} 对齐，材料看 ${persona.artifact}。',
            'status': 'active',
            'source_ids': [_recordId(caseId, 6), _recordId(caseId, 48)],
          },
          if (variant.round >= 2)
            {
              'id': '${caseId}_mem_boundary',
              'content': persona.personalBoundary,
              'status': 'active',
              'source_ids': [_recordId(caseId, 18)],
            },
        ],
        'trace_events': [_taskTrace('memory_sync_task', 1)],
        'llm_calls': [_llmCall('memory_agent', 3600, 420)],
      },
    };

JsonMap _retrievalTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
  bool followUp = false,
}) {
  final sources = followUp
      ? [
          '${caseId}_mem_project_owner',
          '${caseId}_mem_boundary',
          '${caseId}_pkm_project',
        ]
      : [
          '${caseId}_mem_reminder',
          '${caseId}_mem_latest_preference',
          '${caseId}_mem_project_owner',
        ];
  return {
    'task_id':
        followUp ? '${caseId}_retrieval_followup' : '${caseId}_retrieval',
    'type': 'retrieval_qa',
    'query': followUp
        ? '${persona.scenarioAnchor} 和 ${persona.project} 有什么冲突点？'
        : '${persona.project} 负责人是谁，我的提醒和 ${persona.preferenceTopic} 偏好是什么？',
    'expected': {
      'expected_sources': sources,
      'expected_filters': {
        'user_id': persona.userId,
        if (followUp) 'mode': 'cross_domain',
      },
      'must_include': followUp
          ? [persona.project, persona.scenarioAnchor, persona.boundaryNeedle]
          : [persona.primaryPerson, '提前一天', persona.latestNeedle],
      'must_not_include': [persona.oldNeedle, '随便猜'],
      if (!followUp) 'allowed_uncertainty': false,
      'require_grounded_answer': true,
      'llm_judge': false,
    },
    'fixture_observed': {
      'retrieved_sources': sources,
      'cited_sources': sources,
      'applied_filters': {
        'user_id': persona.userId,
        if (followUp) 'mode': 'cross_domain',
      },
      'answer': followUp
          ? '${persona.project} 要和 ${persona.scenarioAnchor} 分开看：${persona.boundaryNeedle}，已有记录支持这个边界。'
          : '${persona.project} 主要找 ${persona.primaryPerson} 对齐；重要安排提前一天提醒；最新 ${persona.preferenceTopic} 是 ${persona.latestNeedle}。',
      'source_snippets': [
        for (final source in sources)
          {
            'source_id': source,
            'text':
                '${persona.project} / ${persona.scenarioAnchor} / ${persona.latestNeedle}',
          },
      ],
      'trace_events': [_toolTrace('search_memory', 1)],
      'llm_calls': [_llmCall('retrieval_agent', 2600, 360)],
    },
  };
}

JsonMap _scheduleTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    {
      'task_id': '${caseId}_schedule',
      'type': 'schedule_refresh',
      'expected': {
        'schedule_action': 'refresh',
        'expected_tool_calls': [
          {
            'name': 'refresh_schedule_aggregation',
            'args_contains': {'user_id': persona.userId},
          },
        ],
        'max_refresh_tool_calls': 1,
        'max_tool_calls': 2,
      },
      'fixture_observed': {
        'predicted_schedule_action': 'refresh',
        'tool_calls': [
          {
            'name': 'refresh_schedule_aggregation',
            'args': {
              'user_id': persona.userId,
              'source_id': _recordId(caseId, 4)
            },
          },
        ],
        'trace_events': [
          _taskTrace('schedule_refresh_router_task', 1),
          _toolTrace('refresh_schedule_aggregation', 2),
        ],
      },
    };

JsonMap _pkmTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    {
      'task_id': '${caseId}_pkm',
      'type': 'pkm_organization',
      'expected': {
        'expected_entries': [
          {
            'path_contains': ['PKM', persona.pkmArea, persona.project],
            'content_contains': [
              persona.project,
              persona.primaryPerson,
              persona.artifact,
            ],
            'source_ids': [_recordId(caseId, 48)],
            'updated_after': '2026-02-01T00:00:00+08:00',
          },
          if (variant.round >= 2)
            {
              'path_contains': ['PKM', persona.pkmArea, persona.scenarioAnchor],
              'content_contains': [
                persona.scenarioAnchor,
                persona.boundaryNeedle,
              ],
              'source_ids': [_recordId(caseId, 160)],
              'updated_after': '2026-03-01T00:00:00+08:00',
            },
        ],
        'min_entry_count': variant.round >= 2 ? 2 : 1,
        'max_entry_count': variant.round >= 2 ? 5 : 4,
        'prohibited_content': ['今天有点烦', '只是试一下', 'OCR 可能识别错'],
      },
      'fixture_observed': {
        'pkm_entries': [
          {
            'path': 'PKM/${persona.pkmArea}/${persona.project}/里程碑复盘.md',
            'title': '${persona.project} 里程碑复盘',
            'content':
                '${persona.project} 由 ${persona.primaryPerson} 对齐，关键材料是 ${persona.artifact}，下一步保留风险 owner。',
            'source_ids': [_recordId(caseId, 48)],
            'updated_at': '2026-04-01T12:00:00+08:00',
          },
          if (variant.round >= 2)
            {
              'path':
                  'PKM/${persona.pkmArea}/${persona.scenarioAnchor}/跨域边界.md',
              'title': '${persona.scenarioAnchor} 边界',
              'content':
                  '${persona.scenarioAnchor} 与 ${persona.project} 关联时要保留边界：${persona.boundaryNeedle}。',
              'source_ids': [_recordId(caseId, 160)],
              'updated_at': '2026-04-10T12:00:00+08:00',
            },
        ],
        'trace_events': [_taskTrace('pkm_agent_task', 1)],
        'llm_calls': [_llmCall('pkm_agent', 3000, 440)],
      },
    };

JsonMap _superAgentTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    {
      'task_id': '${caseId}_super_agent',
      'type': 'super_agent_qa',
      'query':
          '总结一下 ${persona.project} 的负责人、提醒偏好和我最新的 ${persona.preferenceTopic} 边界。',
      'expected': {
        'expected_sources': [
          '${caseId}_mem_reminder',
          '${caseId}_mem_latest_preference',
          '${caseId}_mem_project_owner',
        ],
        'must_include': [
          persona.primaryPerson,
          '提前一天',
          persona.latestNeedle,
          persona.project,
        ],
        'must_not_include': [persona.oldNeedle, '没有记录'],
        'allowed_uncertainty': false,
        'read_only': true,
        'prohibited_tool_calls': [
          'update_memory',
          'delete_memory',
          'save_timeline_card',
        ],
        'personalization_must_include': [persona.project, persona.city],
        'llm_judge': false,
      },
      'fixture_observed': {
        'answer':
            '${persona.city}这组记录里，${persona.project} 主要找 ${persona.primaryPerson} 对齐；重要安排提前一天提醒；最新 ${persona.preferenceTopic} 是 ${persona.latestNeedle}。',
        'retrieved_sources': [
          '${caseId}_mem_reminder',
          '${caseId}_mem_latest_preference',
          '${caseId}_mem_project_owner',
        ],
        'cited_sources': [
          '${caseId}_mem_reminder',
          '${caseId}_mem_latest_preference',
          '${caseId}_mem_project_owner',
        ],
        'source_snippets': [
          {
            'source_id': '${caseId}_mem_project_owner',
            'text': '${persona.project} 主要找 ${persona.primaryPerson} 对齐。',
          },
        ],
        'tool_calls': [
          {
            'name': 'search_memory',
            'args': {'query': '${persona.project} ${persona.primaryPerson}'},
          },
        ],
        'trace_events': [_toolTrace('search_memory', 3)],
        'llm_calls': [_llmCall('super_agent', 4200, 620)],
      },
    };

JsonMap _toolTask({
  required String caseId,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) =>
    {
      'task_id': '${caseId}_tool_route',
      'type': 'tool_calling',
      'query': '查一下 ${persona.project} 最近相关记录，先不要写入新内容。',
      'expected': {
        'router_label': 'memory_search',
        'expected_tool_calls': [
          {
            'name': 'search_memory',
            'args_contains': {'query': persona.project},
          },
        ],
        'prohibited_tool_calls': ['update_memory', 'save_timeline_card'],
        'max_tool_calls': 1,
        'expected_trace_events': ['search_memory'],
      },
      'fixture_observed': {
        'predicted_router_label': 'memory_search',
        'tool_calls': [
          {
            'name': 'search_memory',
            'args': {'query': persona.project, 'user_id': persona.userId},
          },
        ],
        'trace_events': [_toolTrace('search_memory', 4)],
      },
    };

JsonMap _cardTask({
  required String caseId,
  required String taskId,
  required String operationId,
  required List<String> titleContains,
  required JsonMap fieldContains,
}) =>
    {
      'task_id': taskId,
      'type': 'card_extraction',
      'expected': {
        'operation_id': operationId,
        'status': 'completed',
        'title_contains': titleContains,
        'field_contains': fieldContains,
        'must_not_fields': ['weather', 'stock_price'],
        'max_latency_ms': 120000,
      },
      'fixture_observed': {
        'latency_ms': 24000,
        'card': {
          'card_type': 'classic_card',
          'title': titleContains.join(' / '),
          'status': 'completed',
          'fields': {
            'source_id': operationId,
            'summary': fieldContains.values
                .whereType<List>()
                .expand((values) => values)
                .join(' '),
          },
        },
        'trace_events': [
          _taskTrace('card_agent_task', 1),
          _toolTrace('save_timeline_card', 5),
        ],
        'llm_calls': [_llmCall('card_agent', 2200, 320)],
      },
    };

String _recordContent({
  required int index,
  required _PersonaSpec persona,
  required _VariantSpec variant,
}) {
  switch (index) {
    case 1:
      return '以后 ${persona.project} 这种重要安排提前一天提醒我，最好把 ${persona.artifact} 一起列出来。';
    case 2:
      return '先记一下旧规则：${persona.oldPreference}，等我后面确认再改。';
    case 3:
      return '今天有点烦，主要是临时事情太碎，这只是今天状态，不要写成长记忆。';
    case 4:
      return '下周二上午十点和 ${persona.primaryPerson} 讨论 ${persona.project}，提醒我带 ${persona.artifact}。';
    case 5:
      return '改一下，最新规则是：${persona.newPreference}，之前那条旧规则要覆盖掉。';
    case 6:
      return '${persona.project} 主要找 ${persona.primaryPerson} 对齐，备选找 ${persona.secondaryPerson}。';
    case 12:
      return '周末要处理 ${persona.familyFocus}，提醒我不要和 ${persona.project} 的深度工作冲突。';
    case 18:
      return persona.personalBoundary;
    case 24:
      return '${persona.project} 复盘模板保留背景、决策、风险、owner、下一步，尤其标出 ${persona.artifact}。';
    case 36:
      return 'OCR 可能识别错：${persona.financeFocus} 金额旁边那个符号不确定，先别写成长记忆。';
    case 48:
      return '${persona.project} 里程碑复盘找 ${persona.primaryPerson}，材料带 ${persona.artifact}，下一步按风险 owner 拆。';
    case 80:
      return '回看这两周记录时，帮我把 ${persona.project}、${persona.healthFocus} 和 ${persona.familyFocus} 分开总结。';
    case 120:
      return '再次确认 ${persona.preferenceTopic}：${persona.newPreference}，旧说法 ${persona.oldNeedle} 不再适用。';
    case 160:
      return '${persona.scenarioAnchor} 要和 ${persona.secondaryPerson} 复盘，注意 ${persona.personalBoundary}';
    case 220:
      return '只是试一下 ${persona.travelFocus} 的行程想法，还没决定，不要当成长期偏好。';
    case 280:
      return '如果没有 ${persona.project} 的来源记录，回答时直接说不确定，别替我猜。';
  }

  final scenario = _scenarioFamilyFor(index, persona, variant);
  final detail = _details[index % _details.length];
  final metric = _metrics[index % _metrics.length];
  final habit = persona.habits[index % persona.habits.length];
  final colleague =
      index.isEven ? persona.primaryPerson : persona.secondaryPerson;
  final variantNeedle = variant.round >= 2 ? '同时标注跨域影响和证据缺口' : '先保留来源和下一步';

  switch (scenario) {
    case 'work_project':
      return '${persona.project} 今天卡在 $detail，和 $colleague 对齐后 $variantNeedle，指标看 $metric。';
    case 'schedule':
      return '下次 $habit 前提醒我检查 ${persona.artifact}，如果和 ${persona.project} 冲突就提前一天提示。';
    case 'family_care':
      return '${persona.familyFocus} 这件事要留在家庭清单，别混进 ${persona.project} 的工作复盘。';
    case 'health':
      return '${persona.healthFocus} 只是本周观察，除非我连续提三次，否则不要写成长记忆。';
    case 'finance':
      return '${persona.financeFocus} 需要月底再核对，先记录凭证和口径，别直接下结论。';
    case 'travel':
      return '${persona.travelFocus} 可能下月安排，先收集交通和时间，不要生成确定计划。';
    case 'home_admin':
      return '家里行政事项：${persona.homeFocus} 要和 $habit 分开提醒，别占用深度工作时间。';
    case 'learning':
      return '学习/复盘：今天关于 $detail 的笔记想放进 ${persona.pkmArea}，但先等来源补齐。';
    case 'social_relationship':
      return '和 $colleague 沟通 $detail 时语气要温和，结论先行，分歧留到复盘里。';
    case 'legal_policy':
      return '涉及 $detail 的合规边界先按已有记录回答，不确定就标证据不足。';
    case 'emergency':
      return '临时插入：${persona.scenarioAnchor} 有突发变化，先提醒我复核来源，不要自动覆盖长期计划。';
    case 'product_research':
      return '${persona.project} 的用户反馈里提到 $detail，先关联 ${persona.artifact}，不要只凭一句话下结论。';
    case 'vendor_ops':
      return '${persona.financeFocus} 和 ${persona.scenarioAnchor} 要分开核对，找 $colleague 补来源后再更新长期计划。';
    case 'privacy_security':
      return '涉及 ${persona.personalBoundary}，回答时必须标明证据来源，不要把敏感信息写进公开总结。';
    case 'creative_brief':
      return '${persona.project} 的创意方向先收集 $detail 和 $metric，别急着定稿，等 ${persona.primaryPerson} 反馈。';
    case 'career_growth':
      return '复盘一下最近 ${persona.project} 里的协作方式，重点看 $colleague 的反馈和我自己的表达边界。';
    case 'community':
      return '${persona.project} 的社区协作要确认 ${persona.artifact}，志愿者反馈和公开材料要分开记录。';
    case 'noise':
      return '只是试一下 ${_noiseItems[index % _noiseItems.length]}，不要写成长记忆，也不要影响 ${persona.project}。';
    case 'correction':
      return '修正一条：${persona.newPreference}，如果之前记录和这个冲突，以这条为准。';
    default:
      return '${persona.project} 的 $detail 先记一笔，后续找 $colleague 看 $metric。';
  }
}

String _scenarioFamilyFor(
  int index,
  _PersonaSpec persona,
  _VariantSpec variant,
) {
  if (_isNoise(index)) return 'noise';
  if (_isCorrection(index)) return 'correction';
  final families = [
    ...variant.scenarioFamilies,
    ...persona.extraScenarioFamilies,
  ];
  return families[index % families.length];
}

String _journeyStageFor(int index, _VariantSpec variant) {
  final stages = variant.journeyStages;
  return stages[index % stages.length];
}

String _channelFor(int index, _VariantSpec variant) =>
    variant.channels[index % variant.channels.length];

bool _isCorrection(int index) =>
    index == 5 || index == 120 || index % 53 == 0 || index % 89 == 0;

bool _isNoise(int index) =>
    index == 3 ||
    index == 36 ||
    index == 220 ||
    index % 13 == 0 ||
    index % 17 == 0;

bool _isCrossDayLink(int index) =>
    index >= 8 && (index % 4 == 0 || index % 9 == 0);

List<String> _featureTriggers(_VariantSpec variant) => [
      'record_input',
      'timeline_card',
      'timeline_browse',
      'comment',
      'memory',
      'pkm',
      'schedule',
      'knowledge_insight',
      'super_agent',
      'cost_trace',
      if (variant.round >= 2) ...[
        'multi_hop_retrieval',
        'conflict_resolution',
        'abstention_boundary',
      ],
    ];

String _recordId(String caseId, int index) =>
    '${caseId}_record_${index.toString().padLeft(3, '0')}';

String _recordTime(int index) {
  final dayOffset = (index - 1) ~/ 3;
  final slot = (index - 1) % 3;
  final base = DateTime(2026, 1, 5).add(Duration(days: dayOffset));
  final hour = [8, 14, 21][slot];
  final minute = (index * 11) % 60;
  return '${base.year}-${_two(base.month)}-${_two(base.day)}T'
      '${_two(hour)}:${_two(minute)}:00+08:00';
}

JsonMap _taskTrace(String type, int index) => {
      'event_type': 'task',
      'task_id': '${type}_$index',
      'task_type': type,
      'status': 'completed',
      'latency_ms': 900 + index * 37,
    };

JsonMap _toolTrace(String name, int index) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': 240 + index * 19,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 1100,
    };

String _two(int n) => n.toString().padLeft(2, '0');

int max(int a, int b) => a > b ? a : b;

class _VariantSpec {
  const _VariantSpec({
    required this.id,
    required this.outputDir,
    required this.casePrefix,
    required this.family,
    required this.description,
    required this.evidenceGoal,
    required this.version,
    required this.round,
    required this.recordsPerPersona,
    required this.channels,
    required this.journeyStages,
    required this.scenarioFamilies,
    required this.minJourneySpanDays,
    required this.observedJourneySpanDays,
    required this.minCrossDayLinks,
    required this.minCorrections,
    required this.minNoiseInputs,
    required this.minFollowUps,
  });

  final String id;
  final String outputDir;
  final String casePrefix;
  final String family;
  final String description;
  final String evidenceGoal;
  final int version;
  final int round;
  final int recordsPerPersona;
  final List<String> channels;
  final List<String> journeyStages;
  final List<String> scenarioFamilies;
  final int minJourneySpanDays;
  final int observedJourneySpanDays;
  final int minCrossDayLinks;
  final int minCorrections;
  final int minNoiseInputs;
  final int minFollowUps;
}

class _PersonaSpec {
  const _PersonaSpec({
    required this.userId,
    required this.occupation,
    required this.city,
    required this.project,
    required this.primaryPerson,
    required this.secondaryPerson,
    required this.artifact,
    required this.familyFocus,
    required this.healthFocus,
    required this.financeFocus,
    required this.travelFocus,
    required this.homeFocus,
    required this.pkmArea,
    required this.scenarioAnchor,
    required this.preferenceTopic,
    required this.oldPreference,
    required this.newPreference,
    required this.oldNeedle,
    required this.latestNeedle,
    required this.personalBoundary,
    required this.boundaryNeedle,
    required this.responsePreference,
    required this.habits,
    required this.extraScenarioFamilies,
    required this.scenarioNotes,
  });

  final String userId;
  final String occupation;
  final String city;
  final String project;
  final String primaryPerson;
  final String secondaryPerson;
  final String artifact;
  final String familyFocus;
  final String healthFocus;
  final String financeFocus;
  final String travelFocus;
  final String homeFocus;
  final String pkmArea;
  final String scenarioAnchor;
  final String preferenceTopic;
  final String oldPreference;
  final String newPreference;
  final String oldNeedle;
  final String latestNeedle;
  final String personalBoundary;
  final String boundaryNeedle;
  final String responsePreference;
  final List<String> habits;
  final List<String> extraScenarioFamilies;
  final List<String> scenarioNotes;
}

const _variants = [
  _VariantSpec(
    id: 'full_chain_journey_scale_v1',
    outputDir: 'evals/datasets/full_chain_journey_scale_v1',
    casePrefix: 'journey_scale_v1',
    family: 'full_chain_journey_scale_v1',
    description:
        'Round 1：8 用户、每人 240 条跨日输入，覆盖工作/生活/家庭/健康/财务/旅行/噪声/纠错的用户旅程 fixture。',
    evidenceGoal: '先把 8 用户几百输入规模、旅程阶段和成本 trace 指标跑通。',
    version: 1,
    round: 1,
    recordsPerPersona: 240,
    channels: [
      'text',
      'voice_transcript',
      'ocr_clip',
      'clipboard',
      'photo_note'
    ],
    journeyStages: [
      'capture',
      'card_generation',
      'memory_write',
      'pkm_organize',
      'timeline_review',
      'comment_correction',
      'schedule_refresh',
      'knowledge_insight',
      'super_agent_qa',
    ],
    scenarioFamilies: [
      'work_project',
      'schedule',
      'family_care',
      'health',
      'finance',
      'travel',
      'noise',
      'correction',
    ],
    minJourneySpanDays: 70,
    observedJourneySpanDays: 80,
    minCrossDayLinks: 48,
    minCorrections: 6,
    minNoiseInputs: 18,
    minFollowUps: 3,
  ),
  _VariantSpec(
    id: 'full_chain_journey_scale_v2',
    outputDir: 'evals/datasets/full_chain_journey_scale_v2',
    casePrefix: 'journey_scale_v2',
    family: 'full_chain_journey_scale_v2',
    description:
        'Round 2：8 用户、每人 320 条输入，在 Round 1 基础上增加跨域场景、多跳检索、冲突修正、证据不足边界和追问闭环。',
    evidenceGoal: '用更大输入量和更多旅程指标验证第二轮数据/指标迭代。',
    version: 2,
    round: 2,
    recordsPerPersona: 320,
    channels: [
      'text',
      'voice_transcript',
      'ocr_clip',
      'clipboard',
      'photo_note',
      'email_snippet',
      'health_import',
    ],
    journeyStages: [
      'capture',
      'card_generation',
      'memory_write',
      'pkm_organize',
      'timeline_review',
      'comment_correction',
      'schedule_refresh',
      'knowledge_insight',
      'super_agent_qa',
      'multi_hop_retrieval',
      'conflict_resolution',
      'abstention_boundary',
    ],
    scenarioFamilies: [
      'work_project',
      'schedule',
      'family_care',
      'health',
      'finance',
      'travel',
      'home_admin',
      'learning',
      'social_relationship',
      'legal_policy',
      'emergency',
      'noise',
      'correction',
    ],
    minJourneySpanDays: 100,
    observedJourneySpanDays: 107,
    minCrossDayLinks: 78,
    minCorrections: 9,
    minNoiseInputs: 25,
    minFollowUps: 6,
  ),
  _VariantSpec(
    id: 'full_chain_journey_scale_v3',
    outputDir: 'evals/datasets/full_chain_journey_scale_v3',
    casePrefix: 'journey_scale_v3',
    family: 'full_chain_journey_scale_v3',
    description:
        'Round 3：12 用户、每人 480 条输入，在 Round 2 基础上增加 50% 用户、50% 抽样输入空间，并扩展会议、票据、安全、供应商、创意和社区协作场景。',
    evidenceGoal: '为 v4 真实 LLM replay 准备更大、更多样的源数据池，并验证工具产物质量指标的 fixture 口径。',
    version: 3,
    round: 3,
    recordsPerPersona: 480,
    channels: [
      'text',
      'voice_transcript',
      'ocr_clip',
      'clipboard',
      'photo_note',
      'email_snippet',
      'health_import',
      'meeting_note',
      'browser_clip',
      'bank_sms',
      'calendar_clip',
      'receipt_scan',
    ],
    journeyStages: [
      'capture',
      'card_generation',
      'memory_write',
      'pkm_organize',
      'timeline_review',
      'comment_correction',
      'schedule_refresh',
      'knowledge_insight',
      'super_agent_qa',
      'multi_hop_retrieval',
      'conflict_resolution',
      'abstention_boundary',
      'source_grounding',
      'retrieval_check',
      'clarification_needed',
      'noop_boundary',
    ],
    scenarioFamilies: [
      'work_project',
      'schedule',
      'family_care',
      'health',
      'finance',
      'travel',
      'home_admin',
      'learning',
      'social_relationship',
      'legal_policy',
      'emergency',
      'product_research',
      'vendor_ops',
      'privacy_security',
      'creative_brief',
      'career_growth',
      'community',
      'noise',
      'correction',
    ],
    minJourneySpanDays: 150,
    observedJourneySpanDays: 160,
    minCrossDayLinks: 150,
    minCorrections: 14,
    minNoiseInputs: 55,
    minFollowUps: 7,
  ),
];

const _personas = [
  _PersonaSpec(
    userId: 'scale_u_001',
    occupation: '增长产品经理',
    city: '上海',
    project: '导出灰度',
    primaryPerson: 'Mina',
    secondaryPerson: 'Leo',
    artifact: '失败率截图',
    familyFocus: '爸妈体检报告复印件',
    healthFocus: '下午咖啡影响睡眠',
    financeFocus: '云服务预算余量',
    travelFocus: '杭州周末短途',
    homeFocus: '房租发票',
    pkmArea: 'Product',
    scenarioAnchor: '发布窗口',
    preferenceTopic: '咖啡',
    oldPreference: '下午也可以喝咖啡。',
    newPreference: '上午可以喝一杯咖啡，下午不喝。',
    oldNeedle: '下午也可以喝咖啡',
    latestNeedle: '下午不喝',
    personalBoundary: '发布窗口不能和家庭照护提醒混在同一条结论里。',
    boundaryNeedle: '家庭照护',
    responsePreference: '发布复盘要拆出风险 owner',
    habits: ['周三需求评审', '晚上复盘当天工作'],
    extraScenarioFamilies: ['home_admin', 'learning'],
    scenarioNotes: ['导出入口可发现性', '灰度和回滚窗口', '家庭照护提醒边界'],
  ),
  _PersonaSpec(
    userId: 'scale_u_002',
    occupation: '跨境电商运营',
    city: '深圳',
    project: '北美站增长',
    primaryPerson: 'Jason',
    secondaryPerson: 'Ada',
    artifact: 'ROAS 分层表',
    familyFocus: '妈妈降压药补货',
    healthFocus: '夜间颈椎酸痛',
    financeFocus: '广告预算上限',
    travelFocus: '香港展会行程',
    homeFocus: '快递退货单',
    pkmArea: 'Growth',
    scenarioAnchor: '投流预算',
    preferenceTopic: '投流提醒',
    oldPreference: 'ROAS 低于 1.8 才提醒。',
    newPreference: 'ROAS 低于 2.2 就提醒，先看高消耗广告组。',
    oldNeedle: '低于 1.8',
    latestNeedle: '低于 2.2',
    personalBoundary: '投流预算不能自动推断成个人消费偏好。',
    boundaryNeedle: '个人消费',
    responsePreference: '投放复盘先讲异常，再讲建议',
    habits: ['周一看广告异常', '周五整理素材反馈'],
    extraScenarioFamilies: ['social_relationship', 'legal_policy'],
    scenarioNotes: ['广告素材', '汇率和预算', '家庭药品提醒'],
  ),
  _PersonaSpec(
    userId: 'scale_u_003',
    occupation: '数据分析师',
    city: '杭州',
    project: 'Memex 评测看板',
    primaryPerson: 'Grace',
    secondaryPerson: '小陈',
    artifact: 'hit@3 和 MRR 截图',
    familyFocus: '孩子疫苗预约',
    healthFocus: '午休十分钟',
    financeFocus: '报销数据口径',
    travelFocus: '北京答辩行程',
    homeFocus: '物业维修单',
    pkmArea: 'Analytics',
    scenarioAnchor: '指标口径',
    preferenceTopic: '指标命名',
    oldPreference: '指标解释可以只写中文名。',
    newPreference: '指标解释必须保留英文 metric id 和中文解释。',
    oldNeedle: '只写中文名',
    latestNeedle: '英文 metric id',
    personalBoundary: '指标口径不完整时必须说不确定，不能补数字。',
    boundaryNeedle: '不确定',
    responsePreference: '结论要带 metric id',
    habits: ['上午深度分析', '周四 dashboard review'],
    extraScenarioFamilies: ['learning', 'emergency'],
    scenarioNotes: ['MRR', 'hit@3', '证据不足时拒绝编数'],
  ),
  _PersonaSpec(
    userId: 'scale_u_004',
    occupation: '律师',
    city: '广州',
    project: '合同条款库',
    primaryPerson: 'Annie',
    secondaryPerson: '老王',
    artifact: '条款来源编号',
    familyFocus: '父亲复诊材料',
    healthFocus: '晚间低盐饮食',
    financeFocus: '律所开票清单',
    travelFocus: '深圳庭审交通',
    homeFocus: '证件续期',
    pkmArea: 'Legal',
    scenarioAnchor: '保密条款',
    preferenceTopic: '法律回答边界',
    oldPreference: '合同问题可以直接给结论。',
    newPreference: '合同问题先列来源编号，再给风险等级。',
    oldNeedle: '直接给结论',
    latestNeedle: '来源编号',
    personalBoundary: '没有条款来源时不要给法律结论，只能提示需人工复核。',
    boundaryNeedle: '人工复核',
    responsePreference: '法律结论必须带来源编号',
    habits: ['下午审合同', '周末陪家人'],
    extraScenarioFamilies: ['legal_policy', 'home_admin'],
    scenarioNotes: ['保密条款', '法律边界', '复诊材料'],
  ),
  _PersonaSpec(
    userId: 'scale_u_005',
    occupation: '财务主管',
    city: '成都',
    project: '预算月结',
    primaryPerson: 'Mina',
    secondaryPerson: 'Ada',
    artifact: '付款审批表',
    familyFocus: '血压计袖带',
    healthFocus: '低糖早餐',
    financeFocus: '供应商付款批次',
    travelFocus: '重庆出差票据',
    homeFocus: '水电账单',
    pkmArea: 'Finance',
    scenarioAnchor: '付款审批',
    preferenceTopic: '付款提醒',
    oldPreference: '付款超过五万再提醒。',
    newPreference: '付款超过三万就提醒，并列审批人。',
    oldNeedle: '超过五万',
    latestNeedle: '超过三万',
    personalBoundary: '公司付款不能和家庭账单合并统计。',
    boundaryNeedle: '家庭账单',
    responsePreference: '数字先给口径',
    habits: ['月底结账', '早上核对付款'],
    extraScenarioFamilies: ['home_admin', 'legal_policy'],
    scenarioNotes: ['付款审批', '预算余量', '家庭账单隔离'],
  ),
  _PersonaSpec(
    userId: 'scale_u_006',
    occupation: '内容运营',
    city: '苏州',
    project: '小红书活动',
    primaryPerson: 'Grace',
    secondaryPerson: 'Jason',
    artifact: '素材来源链接',
    familyFocus: '外婆生日礼物',
    healthFocus: '眼睛干涩休息',
    financeFocus: '达人合作费用',
    travelFocus: '南京探店计划',
    homeFocus: '快递收纳',
    pkmArea: 'Content',
    scenarioAnchor: '素材版权',
    preferenceTopic: '素材复盘',
    oldPreference: '素材复盘只看点赞数。',
    newPreference: '素材复盘要同时看收藏率和评论情绪。',
    oldNeedle: '只看点赞数',
    latestNeedle: '收藏率',
    personalBoundary: '素材版权不清楚时不能生成可发布结论。',
    boundaryNeedle: '版权',
    responsePreference: '复盘保留素材来源',
    habits: ['晚上看评论', '周五整理选题'],
    extraScenarioFamilies: ['social_relationship', 'learning'],
    scenarioNotes: ['素材版权', '评论情绪', '达人费用'],
  ),
  _PersonaSpec(
    userId: 'scale_u_007',
    occupation: '家庭照护者',
    city: '南京',
    project: '妈妈康复计划',
    primaryPerson: '李医生',
    secondaryPerson: '妹妹',
    artifact: '血压记录表',
    familyFocus: '妈妈晚间用药',
    healthFocus: '青霉素过敏',
    financeFocus: '医保报销材料',
    travelFocus: '医院复诊路线',
    homeFocus: '药盒整理',
    pkmArea: 'Care',
    scenarioAnchor: '用药提醒',
    preferenceTopic: '用药时间',
    oldPreference: '晚间用药按 8 点提醒。',
    newPreference: '晚间用药改到 9 点半提醒。',
    oldNeedle: '8 点',
    latestNeedle: '9 点半',
    personalBoundary: '医疗记录只能提醒和整理，不能替代医生判断。',
    boundaryNeedle: '医生判断',
    responsePreference: '照护事项要明确时间',
    habits: ['早晚量血压', '周末陪诊'],
    extraScenarioFamilies: ['emergency', 'legal_policy'],
    scenarioNotes: ['用药时间冲突', '过敏信息', '医生判断边界'],
  ),
  _PersonaSpec(
    userId: 'scale_u_008',
    occupation: '研究生',
    city: '北京',
    project: '论文开题',
    primaryPerson: '赵老师',
    secondaryPerson: '同门小林',
    artifact: '文献矩阵',
    familyFocus: '奶奶视频通话',
    healthFocus: '晚间跑步后拉伸',
    financeFocus: '奖学金材料',
    travelFocus: '上海会议投稿',
    homeFocus: '宿舍维修申请',
    pkmArea: 'Research',
    scenarioAnchor: '文献综述',
    preferenceTopic: '论文提醒',
    oldPreference: '文献综述每周日提醒。',
    newPreference: '文献综述改到每周五下午提醒，周日只做轻量回顾。',
    oldNeedle: '每周日提醒',
    latestNeedle: '周五下午',
    personalBoundary: '导师意见和个人猜测要分开记录。',
    boundaryNeedle: '导师意见',
    responsePreference: '学术总结要区分证据和猜测',
    habits: ['上午读论文', '周五组会'],
    extraScenarioFamilies: ['learning', 'social_relationship'],
    scenarioNotes: ['论文开题', '导师意见', '会议投稿'],
  ),
  _PersonaSpec(
    userId: 'scale_u_009',
    occupation: '产品设计师',
    city: '厦门',
    project: '智能相册改版',
    primaryPerson: 'Ivan',
    secondaryPerson: '小周',
    artifact: '用户访谈摘录',
    familyFocus: '儿子钢琴课',
    healthFocus: '手腕酸痛',
    financeFocus: '设计外包报价',
    travelFocus: '福州周末摄影',
    homeFocus: '家具安装',
    pkmArea: 'Design',
    scenarioAnchor: '隐私权限',
    preferenceTopic: '设计评审',
    oldPreference: '评审只看视觉稿。',
    newPreference: '评审先看用户任务，再看视觉稿和可访问性。',
    oldNeedle: '只看视觉稿',
    latestNeedle: '用户任务',
    personalBoundary: '隐私权限不清楚时不能默认用户已授权。',
    boundaryNeedle: '用户已授权',
    responsePreference: '设计结论先讲用户任务',
    habits: ['周二走查原型', '上午看访谈'],
    extraScenarioFamilies: ['product_research', 'privacy_security'],
    scenarioNotes: ['智能相册', '隐私授权', '可访问性'],
  ),
  _PersonaSpec(
    userId: 'scale_u_010',
    occupation: '独立开发者',
    city: '武汉',
    project: '订阅计费重构',
    primaryPerson: 'Nora',
    secondaryPerson: 'Ben',
    artifact: 'Stripe webhook 日志',
    familyFocus: '父母宽带续费',
    healthFocus: '久坐腰背疼',
    financeFocus: '云账单异常',
    travelFocus: '长沙黑客松行程',
    homeFocus: 'NAS 硬盘巡检',
    pkmArea: 'Engineering',
    scenarioAnchor: '计费回调',
    preferenceTopic: '告警阈值',
    oldPreference: '失败回调超过 20 次再提醒。',
    newPreference: '失败回调超过 8 次就提醒，并附带 request id。',
    oldNeedle: '超过 20 次',
    latestNeedle: '超过 8 次',
    personalBoundary: '支付日志里的用户邮箱不能写进公开复盘。',
    boundaryNeedle: '用户邮箱',
    responsePreference: '工程复盘要列 request id',
    habits: ['晚上处理 issue', '周六发 beta'],
    extraScenarioFamilies: ['vendor_ops', 'privacy_security'],
    scenarioNotes: ['Stripe', 'webhook', '支付隐私'],
  ),
  _PersonaSpec(
    userId: 'scale_u_011',
    occupation: '咖啡店主理人',
    city: '青岛',
    project: '春季新品菜单',
    primaryPerson: '阿岚',
    secondaryPerson: '供应商老许',
    artifact: '试饮反馈表',
    familyFocus: '姥姥复诊陪同',
    healthFocus: '晚间少喝浓缩',
    financeFocus: '豆子采购成本',
    travelFocus: '崂山门店探访',
    homeFocus: '门店水电缴费',
    pkmArea: 'Retail',
    scenarioAnchor: '供应商报价',
    preferenceTopic: '菜单复盘',
    oldPreference: '新品复盘只看销量。',
    newPreference: '新品复盘同时看复购率、毛利和试饮反馈。',
    oldNeedle: '只看销量',
    latestNeedle: '复购率',
    personalBoundary: '供应商报价不能和个人家庭开销混算。',
    boundaryNeedle: '家庭开销',
    responsePreference: '经营建议要先讲毛利',
    habits: ['早上盘库存', '周四杯测'],
    extraScenarioFamilies: ['vendor_ops', 'creative_brief'],
    scenarioNotes: ['新品菜单', '供应商报价', '试饮反馈'],
  ),
  _PersonaSpec(
    userId: 'scale_u_012',
    occupation: '公益项目协调人',
    city: '西安',
    project: '社区阅读计划',
    primaryPerson: '小赵',
    secondaryPerson: 'Luna',
    artifact: '报名名单',
    familyFocus: '孩子托管时间',
    healthFocus: '嗓子发炎少讲话',
    financeFocus: '捐赠票据',
    travelFocus: '宝鸡乡村学校走访',
    homeFocus: '社区活动室钥匙',
    pkmArea: 'Community',
    scenarioAnchor: '志愿者排班',
    preferenceTopic: '活动提醒',
    oldPreference: '活动前一天晚上提醒。',
    newPreference: '活动提前两天提醒，并附带报名名单和物资清单。',
    oldNeedle: '前一天晚上',
    latestNeedle: '提前两天',
    personalBoundary: '未成年人信息不能出现在公开总结里。',
    boundaryNeedle: '未成年人信息',
    responsePreference: '公益总结要区分公开和内部信息',
    habits: ['周三确认场地', '周日整理志愿者反馈'],
    extraScenarioFamilies: ['community', 'privacy_security'],
    scenarioNotes: ['社区阅读', '志愿者排班', '未成年人隐私'],
  ),
];

const _details = [
  '入口文案',
  '权限边界',
  '回滚预案',
  '客服话术',
  '异常监控',
  '预算余量',
  '数据口径',
  '跨端兼容',
  '素材反馈',
  '用户路径',
  '风险 owner',
  '灰度节奏',
  '查询 SQL',
  '指标解释',
  '会议纪要',
  '来源标注',
];

const _metrics = [
  '失败率',
  '重试率',
  'P95 延迟',
  'token 成本',
  '工具调用次数',
  'MRR',
  'hit@3',
  '用户反馈',
];

const _noiseItems = [
  '低糖咖啡',
  '换一个手机壳',
  '午休十分钟',
  '临时想看展',
  '整理书桌',
  '今天早点睡',
  '下班听播客',
  '试试新路线',
];
