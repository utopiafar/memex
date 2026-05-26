import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _variantSpecs = [
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v1',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v1/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v1',
    recordLimit: 8,
    round: 1,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v2',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v2/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v2',
    recordLimit: 16,
    round: 2,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v3',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v2/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v3',
    recordLimit: 12,
    recordOffsets: [0, 160],
    round: 3,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v4',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v3/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v4',
    recordLimit: 12,
    recordOffsets: [0, 160, 320],
    round: 4,
    sourceCaseLimit: 12,
    createdAt: '2026-05-19',
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v5',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v4/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v5',
    recordLimit: 16,
    recordOffsets: [0, 160, 320, 480],
    round: 5,
    sourceCaseLimit: 12,
    createdAt: '2026-05-23',
    interleaveWindows: true,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v6',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v4/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v6',
    recordLimit: 20,
    recordOffsets: [0, 120, 240, 360, 480],
    round: 6,
    sourceCaseLimit: 12,
    createdAt: '2026-05-23',
    interleaveWindows: true,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v7',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v4/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v7',
    recordLimit: 20,
    recordOffsets: [0, 60, 120, 180, 240, 300, 360, 420, 480, 540],
    round: 7,
    sourceCaseLimit: 12,
    createdAt: '2026-05-25',
    interleaveWindows: false,
  ),
  _ReplayVariantSpec(
    id: 'full_chain_journey_real_replay_v8',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v4/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v8',
    recordLimit: 20,
    recordOffsets: [0, 60, 120, 180, 240, 300, 360, 420, 480, 540],
    round: 8,
    sourceCaseLimit: 12,
    createdAt: '2026-05-25',
    mergeWindows: true,
  ),
];

Future<void> main(List<String> args) async {
  final selectedSpecs = args.isEmpty
      ? _variantSpecs
      : _variantSpecs.where(
          (spec) => args.contains(spec.id) || args.contains(spec.outputDir),
        );
  if (selectedSpecs.isEmpty) {
    throw ArgumentError(
      'Unknown variant. Use one of: '
      '${_variantSpecs.map((spec) => spec.id).join(', ')}',
    );
  }
  for (final spec in selectedSpecs) {
    await _writeVariant(spec);
  }
}

Future<void> _writeVariant(_ReplayVariantSpec spec) async {
  final cases = await _loadCases(spec.sourcePath);
  final sourceCases = cases.take(spec.sourceCaseLimit).toList();
  final replayCases = <JsonMap>[];
  if (spec.mergeWindows) {
    for (final evalCase in sourceCases) {
      replayCases.add(_mergedReplayCase(evalCase: evalCase, spec: spec));
    }
  } else {
    void addReplayCase(JsonMap evalCase, int windowIndex) {
      replayCases.add(
        _replayCase(
          evalCase: evalCase,
          recordLimit: spec.recordLimit,
          recordOffset: spec.recordOffsets[windowIndex],
          windowIndex: windowIndex,
          caseSuffix:
              spec.recordOffsets.length == 1 ? null : _caseSuffix(windowIndex),
          round: spec.round,
        ),
      );
    }

    if (spec.interleaveWindows) {
      for (var windowIndex = 0;
          windowIndex < spec.recordOffsets.length;
          windowIndex++) {
        for (final evalCase in sourceCases) {
          addReplayCase(evalCase, windowIndex);
        }
      }
    } else {
      for (final evalCase in sourceCases) {
        for (var windowIndex = 0;
            windowIndex < spec.recordOffsets.length;
            windowIndex++) {
          addReplayCase(evalCase, windowIndex);
        }
      }
    }
  }
  final outDir = Directory(spec.outputDir);
  await outDir.create(recursive: true);

  final operationCount = replayCases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['operations'] as List).length,
  );
  final recordCount = replayCases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        (evalCase['operations'] as List)
            .where((operation) =>
                operation is Map && operation['type'] == 'record')
            .length,
  );
  final taskCount = replayCases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final recordsPerCase =
      spec.recordLimit * (spec.mergeWindows ? spec.recordOffsets.length : 1);
  final manifest = {
    'dataset_id': 'memex_${spec.id}',
    'version': spec.round,
    'description':
        '真实 full-chain replay 数据集：${sourceCases.length} 个 persona，${replayCases.length} 个 case，每 case $recordsPerCase 条 record，加 timeline browse、comment、schedule refresh、knowledge insight refresh、memory wait、Super Agent quick query。',
    'created_at': spec.createdAt,
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': sourceCases.length,
    'case_count': replayCases.length,
    'records_per_case': recordsPerCase,
    'records_per_window': spec.recordLimit,
    'windows_per_case': spec.mergeWindows ? spec.recordOffsets.length : 1,
    'records_per_persona': spec.recordLimit * spec.recordOffsets.length,
    'record_offsets': spec.recordOffsets,
    'interleave_windows': spec.interleaveWindows,
    'merge_windows': spec.mergeWindows,
    'input_count': recordCount,
    'operation_count': operationCount,
    'eval_task_count': taskCount,
    'families': [spec.id],
    'evidence_goal':
        '通过 serial_full_chain_replay_test.dart 走真实 Memex 链路，再用 replay_file adapter 评分为 real_replay。',
    'oracle_scope':
        '每个 replay case 的 expected 只要求当前 record window 中可见的事实，不从完整 source case 泄漏 ground truth。',
    if (spec.round >= 4)
      'scaleup_notes': [
        '相对 v3：用户数从 8 增加到 12，增加 50%。',
        '相对 v3：每用户 replay record 从 24 增加到 36，增加 50%。',
        '为了控制单 case 时长，仍使用 12-record case 窗口，改为每用户 3 个窗口。',
        '建议按 12 case 一组分片运行：offset 0、12、24。',
      ],
    if (spec.round >= 5)
      'methodology_notes': [
        '相对 v4：source fake 数据池扩展到每用户 640 条输入。',
        if (spec.round < 7) '每个 replay 窗口扩展到 16 条 record，提高单 case 内证据密度。',
        if (spec.round < 7)
          '窗口按 offset 交错排列，方便 case-offset 分片覆盖不同 persona，而不是连续打同一用户。',
        'oracle 按窗口证据收敛，避免要求当前链路回答未输入过的历史事实。',
        if (spec.round == 7)
          'v7 使用 10 个窗口 × 20 record，把每用户真实 replay 输入扩大到 200 条；每个窗口保留 timeline/comment/schedule/knowledge/memory/super-agent 操作，使端到端行为随输入规模等比例扩大。',
        if (spec.round == 7)
          'v7 按 persona 连续排列窗口，方便一次 case shard 覆盖完整用户 200 条输入；全量仍可按 offset/limit 分片运行。',
        if (spec.mergeWindows)
          'v8 将同一 persona 的 10 个窗口合并为单个连续用户 case：每 case 200 条 record、70 个端到端 app operation、60 个 eval task，窗口 oracle 仍保持局部证据边界。',
      ],
  };

  await File('${spec.outputDir}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File('${spec.outputDir}/cases.jsonl').writeAsString(
    '${replayCases.map(jsonEncode).join('\n')}\n',
    flush: true,
  );
  stdout.writeln(
    'Generated ${spec.id}: ${replayCases.length} cases, '
    '$recordCount records, $operationCount operations, $taskCount tasks '
    'at ${spec.outputDir}',
  );
}

JsonMap _mergedReplayCase({
  required JsonMap evalCase,
  required _ReplayVariantSpec spec,
}) {
  final sourceCaseId = evalCase['case_id'].toString();
  final caseId = sourceCaseId.replaceFirst(
    RegExp(r'journey_scale_v\d+'),
    'journey_real_replay_v${spec.round}',
  );
  final windowCases = <JsonMap>[];
  for (var windowIndex = 0;
      windowIndex < spec.recordOffsets.length;
      windowIndex++) {
    windowCases.add(
      _replayCase(
        evalCase: evalCase,
        recordLimit: spec.recordLimit,
        recordOffset: spec.recordOffsets[windowIndex],
        windowIndex: windowIndex,
        caseSuffix: _caseSuffix(windowIndex),
        round: spec.round,
      ),
    );
  }

  final operations = <dynamic>[];
  final windowEvalTasks = <JsonMap>[];
  for (final windowCase in windowCases) {
    operations.addAll(_list(windowCase['operations']));
    windowEvalTasks.addAll(_list(windowCase['eval_tasks']).map(_map));
  }
  final evalTasks = <dynamic>[
    _mergedCostTraceTask(
      caseId: caseId,
      evalCase: evalCase,
      operations: operations.map(_map).toList(),
      windowEvalTasks: windowEvalTasks,
      windowCount: spec.recordOffsets.length,
    ),
    ...windowEvalTasks.where((task) => task['type'] != 'cost_trace'),
  ];

  return {
    ...evalCase,
    'case_id': caseId,
    'family': 'full_chain_journey_real_replay_v${spec.round}',
    'evidence_scope': {
      'source_case_id': sourceCaseId,
      'record_offsets': spec.recordOffsets,
      'record_limit_per_window': spec.recordLimit,
      'window_count': spec.recordOffsets.length,
      'records_per_case': spec.recordLimit * spec.recordOffsets.length,
      'window_scoped_oracle': true,
      'continuous_user_replay': true,
      'window_case_ids':
          windowCases.map((windowCase) => windowCase['case_id']).toList(),
    },
    'operations': operations,
    'eval_tasks': evalTasks,
  };
}

JsonMap _mergedCostTraceTask({
  required String caseId,
  required JsonMap evalCase,
  required List<JsonMap> operations,
  required List<JsonMap> windowEvalTasks,
  required int windowCount,
}) {
  final persona = _map(evalCase['persona']);
  final profile = _map(persona['profile']);
  final project = profile['project']?.toString() ?? '';
  final city = profile['city']?.toString() ?? '';
  final occupation = profile['occupation']?.toString() ?? '';
  final records =
      operations.where((operation) => operation['type'] == 'record').toList();
  final operationTypes = operations
      .map((operation) => operation['type']?.toString() ?? '')
      .where((type) => type.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final channels = records
      .map((operation) => operation['channel']?.toString() ?? '')
      .where((channel) => channel.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final stages = records
      .map((operation) => operation['journey_stage']?.toString() ?? '')
      .where((stage) => stage.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final scenarioFamilies = records
      .map((operation) => operation['scenario_family']?.toString() ?? '')
      .where((family) => family.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final memoryMustWriteCount =
      windowEvalTasks.where((task) => task['type'] == 'memory_write').fold<int>(
            0,
            (sum, task) =>
                sum + _list(_map(task['expected'])['must_write']).length,
          );
  final minMemoryEntryCount =
      memoryMustWriteCount < 12 ? memoryMustWriteCount : 12;
  final crossDayLinks =
      records.where((operation) => operation['cross_day_link'] == true).length;
  final corrections =
      records.where((operation) => operation['is_correction'] == true).length;
  final noiseInputs =
      records.where((operation) => operation['is_noise'] == true).length;
  final journeySpanDays = _spanDays(records);

  return {
    'task_id': '${caseId}_cost',
    'type': 'cost_trace',
    'expected': {
      'max_total_tokens': records.length * 50000,
      'max_tokens_per_input': 50000,
      'max_latency_ms': 9000000,
      'max_tool_calls': 5000 * windowCount,
      'max_retry_rate': 0.2,
      'max_failed_task_rate': 0.05,
      'max_active_task_count': 0,
      'max_failed_task_count': 0,
      'max_root_invariant_failures': 0,
      'max_loop_detection_tasks': 0,
      'max_max_turns_tasks': 0,
      'require_all_tasks_completed': true,
      'min_record_operations': records.length,
      'min_operation_success_rate': 0.95,
      'min_operation_settlement_rate': 0.95,
      'min_card_materialization_rate': 0.90,
      'min_card_completed_rate': 0.90,
      'min_memory_entry_count': minMemoryEntryCount,
      'min_llm_agent_count': 3,
      'min_tool_diversity': 3,
      'min_journey_span_days': journeySpanDays.floor(),
      'expected_operation_types': operationTypes,
      'expected_input_channels': channels,
      'expected_feature_triggers': [
        'record_input',
        'timeline_card',
        'timeline_browse',
        'comment',
        'memory',
        'schedule',
        'knowledge_insight',
        'super_agent',
        'cost_trace',
      ],
      'expected_journey_stages': stages,
      'expected_scenario_families': scenarioFamilies,
      'expected_persona_markers': [
        occupation,
        city,
        project,
      ].where((value) => value.trim().isNotEmpty).toList(),
      'min_cross_day_links': crossDayLinks,
      'min_correction_operations': corrections,
      'min_noise_inputs': noiseInputs,
      'min_follow_up_queries': windowCount * 2,
      'expected_trace_events': ['card_agent_task'],
      'must_include': ['Facts', 'Cards', 'Super Agent'],
    },
  };
}

JsonMap _replayCase({
  required JsonMap evalCase,
  required int recordLimit,
  required int recordOffset,
  required int windowIndex,
  required String? caseSuffix,
  required int round,
}) {
  final sourceCaseId = evalCase['case_id'].toString();
  final baseCaseId = evalCase['case_id'].toString().replaceFirst(
        RegExp(r'journey_scale_v\d+'),
        'journey_real_replay_v$round',
      );
  final caseId = caseSuffix == null ? baseCaseId : '${baseCaseId}_$caseSuffix';
  final persona = _map(evalCase['persona']);
  final profile = _map(persona['profile']);
  final project = profile['project']?.toString() ?? '';
  final city = profile['city']?.toString() ?? '';
  final occupation = profile['occupation']?.toString() ?? '';
  final facts =
      _list(_map(evalCase['ground_truth_world'])['facts']).map(_map).toList();
  final ownerFact = facts
      .map((fact) => fact['content']?.toString() ?? '')
      .firstWhere((content) => content.contains('主要找'), orElse: () => '');
  final primaryPerson = _extractBetween(ownerFact, '主要找 ', ' 对齐');
  final latestPreference =
      facts.map((fact) => fact['content']?.toString() ?? '').firstWhere(
            (content) =>
                content.contains('最新') ||
                content.contains('上午') ||
                content.contains('9 点半') ||
                content.contains('低于') ||
                content.contains('来源编号') ||
                content.contains('周五下午'),
            orElse: () => '',
          );
  final boundary = facts
      .map((fact) => fact['content']?.toString() ?? '')
      .firstWhere((content) => content.contains('不能'), orElse: () => '');
  final latestNeedles = _importantNeedles(latestPreference);

  final records = _list(evalCase['operations'])
      .map(_map)
      .where((operation) => operation['type'] == 'record')
      .skip(recordOffset)
      .take(recordLimit)
      .map(
          (operation) => {...operation, 'id': _remapId(operation['id'], round)})
      .toList();
  if (records.length < recordLimit) {
    throw StateError(
      'Case $caseId only has ${records.length} records after offset '
      '$recordOffset, expected $recordLimit.',
    );
  }
  final windowContent = records
      .map((record) => record['content']?.toString() ?? '')
      .where((content) => content.trim().isNotEmpty)
      .join('\n');
  final projectAvailable =
      project.isNotEmpty && _contains(windowContent, project);
  final primaryPersonAvailable =
      primaryPerson.isNotEmpty && _contains(windowContent, primaryPerson);
  final ownerAvailable = projectAvailable && primaryPersonAvailable;
  final reminderAvailable = _contains(windowContent, '提前一天');
  final latestPreferenceAvailable = latestNeedles.isNotEmpty &&
      latestNeedles.every((needle) => _contains(windowContent, needle));
  final boundaryNeedles = _importantNeedles(boundary);
  final boundaryAvailable = boundary.isNotEmpty &&
      (_contains(windowContent, boundary) ||
          boundaryNeedles.any((needle) => _contains(windowContent, needle)));
  final waitNeedles = [
    if (projectAvailable) project,
    if (primaryPersonAvailable) primaryPerson,
    if (reminderAvailable) '提前一天',
    if (latestPreferenceAvailable) ...latestNeedles,
  ].where((value) => value.trim().isNotEmpty).toList();
  final predictedFactIdsByRecordId = _predictedFactIdsByRecordId(records);
  final memoryMustWrite = <JsonMap>[
    if (reminderAvailable)
      {
        'id': '${caseId}_mem_reminder',
        'must_include': ['提前一天'],
        'kind': 'reminder_rule',
        'entities': ['提前一天'],
        'source_ids': _sourceIdsForNeedles(
          records,
          predictedFactIdsByRecordId,
          ['提前一天'],
        ),
      },
    if (ownerAvailable)
      {
        'id': '${caseId}_mem_project_owner',
        'must_include': [project, primaryPerson],
        'kind': 'project_context',
        'entities': [project, primaryPerson],
        'source_ids': _sourceIdsForNeedles(
          records,
          predictedFactIdsByRecordId,
          [project, primaryPerson],
        ),
      },
    if (latestPreferenceAvailable)
      {
        'id': '${caseId}_mem_latest_preference',
        'must_include': latestNeedles,
        'kind': latestNeedles.any((needle) => needle.contains('提醒'))
            ? 'reminder_rule'
            : 'preference',
        'entities': latestNeedles,
        'source_ids': _sourceIdsForNeedles(
          records,
          predictedFactIdsByRecordId,
          latestNeedles,
        ),
      },
  ];
  final answerBitGroups = <String, List<String>>{
    if (ownerAvailable) 'project_owner': [project, primaryPerson],
    if (reminderAvailable) 'reminder_rule': ['提前一天'],
    if (latestPreferenceAvailable) 'latest_preference': latestNeedles,
    if (boundaryAvailable) 'boundary': boundaryNeedles.take(1).toList(),
  };
  final superAgentMustInclude = [
    if (projectAvailable) project,
    if (primaryPersonAvailable) primaryPerson,
    if (reminderAvailable) '提前一天',
    if (latestPreferenceAvailable) ...latestNeedles,
    if (boundaryAvailable) ...boundaryNeedles.take(1),
  ].where((value) => value.trim().isNotEmpty).toList();
  final projectCardRecord = _selectExpectationRecord(
    records,
    [project, primaryPerson],
    fallbackIndex: 3,
  );
  final projectTitleNeedles =
      _needlesPresentInRecord(projectCardRecord, [project, primaryPerson]);
  final boundaryCardRecord = round >= 2 && records.length >= 12
      ? _selectStableCardRecord(records, [project], fallbackIndex: 11)
      : null;
  final boundaryTitleNeedles = boundaryCardRecord == null
      ? const <String>[]
      : _needlesPresentInRecord(boundaryCardRecord, [project]);
  final lastRecordTime = records.last['time']?.toString();
  final commentTarget = records.length >= 4
      ? records[3]['id'].toString()
      : records.first['id'].toString();
  final askId = '${caseId}_ask_001';
  final superAgentQuery =
      '总结一下 $project 的负责人、提醒偏好，以及同一窗口里明确生效的全局最新偏好和边界。只基于已有记录回答。';
  final operations = [
    ...records,
    {
      'id': '${caseId}_fetch_001',
      'type': 'fetch_timeline',
      'time': lastRecordTime,
      'date_from': records.first['time'],
      'date_to': lastRecordTime,
      'limit': 80,
    },
    {
      'id': '${caseId}_comment_001',
      'type': 'post_comment',
      'time': lastRecordTime,
      'target_operation_id': commentTarget,
      'content': '补充：这条真实 replay 要保留来源，并在后续问答中能被引用。',
    },
    {
      'id': '${caseId}_schedule_refresh_001',
      'type': 'refresh_schedule_aggregation',
      'time': lastRecordTime,
    },
    {
      'id': '${caseId}_insight_refresh_001',
      'type': 'refresh_knowledge_insights',
      'time': lastRecordTime,
    },
    {
      'id': '${caseId}_wait_memory_001',
      'type': 'wait_memory',
      'time': lastRecordTime,
      'timeout_seconds': 120,
      'must_include_any': waitNeedles.isEmpty
          ? [project].where((value) => value.trim().isNotEmpty).toList()
          : waitNeedles,
    },
    {
      'id': askId,
      'type': 'ask_super_agent',
      'time': lastRecordTime,
      'query': superAgentQuery,
      'quick_query': true,
    },
    if (round >= 2)
      {
        'id': '${caseId}_ask_followup_001',
        'type': 'ask_super_agent',
        'time': lastRecordTime,
        'query': '回看这段记录，哪些内容不应该写成长记忆？给出原因。',
        'quick_query': true,
      },
  ];

  final operationTypes = operations
      .map((operation) => operation['type']?.toString() ?? '')
      .where((type) => type.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final channels = records
      .map((operation) => operation['channel']?.toString() ?? '')
      .where((channel) => channel.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final stages = records
      .map((operation) => operation['journey_stage']?.toString() ?? '')
      .where((stage) => stage.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final scenarioFamilies = records
      .map((operation) => operation['scenario_family']?.toString() ?? '')
      .where((family) => family.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final crossDayLinks =
      records.where((operation) => operation['cross_day_link'] == true).length;
  final corrections =
      records.where((operation) => operation['is_correction'] == true).length;
  final noiseInputs =
      records.where((operation) => operation['is_noise'] == true).length;
  final journeySpanDays = _spanDays(records);

  return {
    ...evalCase,
    'case_id': caseId,
    'family': 'full_chain_journey_real_replay_v$round',
    'evidence_scope': {
      'source_case_id': sourceCaseId,
      'record_offset': recordOffset,
      'record_limit': recordLimit,
      'window_index': windowIndex,
      'window_scoped_oracle': true,
      'available_fact_markers': [
        if (reminderAvailable) 'reminder',
        if (ownerAvailable) 'project_owner',
        if (latestPreferenceAvailable) 'latest_preference',
        if (boundaryAvailable) 'boundary',
      ],
      'unavailable_fact_markers': [
        if (!reminderAvailable) 'reminder',
        if (!ownerAvailable) 'project_owner',
        if (!latestPreferenceAvailable) 'latest_preference',
        if (!boundaryAvailable) 'boundary',
      ],
    },
    'operations': operations,
    'eval_tasks': [
      {
        'task_id': '${caseId}_cost',
        'type': 'cost_trace',
        'expected': {
          'max_total_tokens': recordLimit * 50000,
          'max_tokens_per_input': 50000,
          'max_latency_ms': 9000000,
          'max_tool_calls': 5000,
          'max_retry_rate': 0.2,
          'max_failed_task_rate': 0.05,
          'max_active_task_count': 0,
          'max_failed_task_count': 0,
          'max_root_invariant_failures': 0,
          'max_loop_detection_tasks': 0,
          'max_max_turns_tasks': 0,
          'require_all_tasks_completed': true,
          'min_record_operations': recordLimit,
          'min_operation_success_rate': 0.95,
          'min_operation_settlement_rate': 0.95,
          'min_card_materialization_rate': 0.90,
          'min_card_completed_rate': 0.90,
          'min_memory_entry_count':
              memoryMustWrite.length >= 2 ? 2 : memoryMustWrite.length,
          'min_llm_agent_count': 3,
          'min_tool_diversity': 3,
          'min_journey_span_days': journeySpanDays.floor(),
          'expected_operation_types': operationTypes,
          'expected_input_channels': channels,
          'expected_feature_triggers': [
            'record_input',
            'timeline_card',
            'timeline_browse',
            'comment',
            'memory',
            'schedule',
            'knowledge_insight',
            'super_agent',
            'cost_trace',
          ],
          'expected_journey_stages': stages,
          'expected_scenario_families': scenarioFamilies,
          'expected_persona_markers': [
            occupation,
            city,
            project,
          ].where((value) => value.trim().isNotEmpty).toList(),
          'min_cross_day_links': crossDayLinks,
          'min_correction_operations': corrections,
          'min_noise_inputs': noiseInputs,
          'min_follow_up_queries': round >= 2 ? 2 : 1,
          'expected_trace_events': ['card_agent_task'],
          'must_include': ['Facts', 'Cards', 'Super Agent'],
        },
      },
      {
        'task_id': '${caseId}_memory',
        'type': 'memory_write',
        'expected': {
          'must_write': memoryMustWrite,
          'must_not_write': [
            {
              'id': '${caseId}_temp_mood',
              'must_include': ['今天有点烦'],
            },
            {
              'id': '${caseId}_one_off_trial',
              'must_include': ['只是试一下'],
            },
          ],
          'evaluate_write_precision': false,
          'max_duplicate_rate': 0.35,
        },
      },
      {
        'task_id': '${caseId}_card_project',
        'type': 'card_extraction',
        'expected': {
          'operation_id': projectCardRecord['id'],
          'status': 'completed',
          'title_contains': projectTitleNeedles,
          'must_not_fields': ['stock_price'],
          'max_latency_ms': 600000,
        },
      },
      if (boundaryCardRecord != null && boundaryTitleNeedles.isNotEmpty)
        {
          'task_id': '${caseId}_card_boundary',
          'type': 'card_extraction',
          'expected': {
            'operation_id': boundaryCardRecord['id'],
            'status': 'completed',
            'title_contains': boundaryTitleNeedles,
            'must_not_fields': ['stock_price'],
            'max_latency_ms': 600000,
          },
        },
      {
        'task_id': '${caseId}_super_agent',
        'type': 'super_agent_qa',
        'query': superAgentQuery,
        'expected': {
          'operation_id': askId,
          'must_include': superAgentMustInclude,
          'bit_groups': answerBitGroups,
          if (boundaryAvailable && projectAvailable)
            'personalization_must_include': [project],
          'allowed_uncertainty':
              superAgentMustInclude.isNotEmpty ? false : true,
          'read_only': true,
          'prohibited_tool_calls': [
            'update_memory',
            'delete_memory',
            'save_timeline_card',
          ],
          'llm_judge': false,
        },
      },
      if (round >= 2)
        {
          'task_id': '${caseId}_super_agent_followup',
          'type': 'super_agent_qa',
          'query': '回看这段记录，哪些内容不应该写成长记忆？给出原因。',
          'expected': {
            'operation_id': '${caseId}_ask_followup_001',
            'must_include': ['不要', '长期记忆'],
            'read_only': true,
            'prohibited_tool_calls': [
              'update_memory',
              'delete_memory',
              'save_timeline_card',
            ],
            'llm_judge': false,
          },
        },
    ],
  };
}

Future<List<JsonMap>> _loadCases(String path) async {
  final cases = <JsonMap>[];
  for (final line in await File(path).readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    cases.add(jsonDecode(trimmed) as JsonMap);
  }
  return cases;
}

String _caseSuffix(int index) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz';
  if (index < alphabet.length) return alphabet[index];
  return 'window_${index + 1}';
}

String _remapId(Object? id, int round) => id.toString().replaceFirst(
      RegExp(r'journey_scale_v\d+'),
      'journey_real_replay_v$round',
    );

JsonMap _selectExpectationRecord(
  List<JsonMap> records,
  List<String> needles, {
  required int fallbackIndex,
}) {
  final requiredNeedles =
      needles.where((needle) => needle.trim().isNotEmpty).toList();
  for (final record in records) {
    final content = record['content']?.toString() ?? '';
    if (requiredNeedles.every((needle) => _contains(content, needle))) {
      return record;
    }
  }
  for (final record in records) {
    final content = record['content']?.toString() ?? '';
    if (requiredNeedles.any((needle) => _contains(content, needle))) {
      return record;
    }
  }
  final index = fallbackIndex.clamp(0, records.length - 1).toInt();
  return records[index];
}

JsonMap? _selectStableCardRecord(
  List<JsonMap> records,
  List<String> needles, {
  required int fallbackIndex,
}) {
  final candidates = records
      .where((record) =>
          record['is_noise'] != true && record['is_correction'] != true)
      .toList();
  if (candidates.isEmpty) return null;
  return _selectExpectationRecord(
    candidates,
    needles,
    fallbackIndex: fallbackIndex.clamp(0, candidates.length - 1).toInt(),
  );
}

List<String> _needlesPresentInRecord(JsonMap record, List<String> needles) {
  final content = record['content']?.toString() ?? '';
  return needles
      .where((needle) => needle.trim().isNotEmpty)
      .where((needle) => _contains(content, needle))
      .toList();
}

Map<String, String> _predictedFactIdsByRecordId(List<JsonMap> records) {
  final countsByDate = <String, int>{};
  final result = <String, String>{};
  for (final record in records) {
    final id = record['id']?.toString();
    final rawTime = record['time']?.toString();
    if (id == null || rawTime == null) continue;
    final parsed = DateTime.tryParse(rawTime);
    if (parsed == null) continue;
    final datePath =
        '${parsed.year.toString().padLeft(4, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}.md';
    final next = (countsByDate[datePath] ?? 0) + 1;
    countsByDate[datePath] = next;
    result[id] = '$datePath#ts_$next';
  }
  return result;
}

List<String> _sourceIdsForNeedles(
  List<JsonMap> records,
  Map<String, String> predictedFactIdsByRecordId,
  List<String> needles,
) {
  final requiredNeedles =
      needles.where((needle) => needle.trim().isNotEmpty).toList();
  if (requiredNeedles.isEmpty) return const [];
  final exact = <String>[];
  final partial = <String>[];
  for (final record in records) {
    final content = record['content']?.toString() ?? '';
    final recordId = record['id']?.toString();
    final factId =
        recordId == null ? null : predictedFactIdsByRecordId[recordId];
    if (factId == null) continue;
    if (requiredNeedles.every((needle) => _contains(content, needle))) {
      exact.add(factId);
    } else if (requiredNeedles.any((needle) => _contains(content, needle))) {
      partial.add(factId);
    }
  }
  final seen = <String>{};
  return [...exact, ...partial]
      .where((id) => seen.add(id))
      .take(3)
      .toList(growable: false);
}

bool _contains(String haystack, String needle) {
  return haystack
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .contains(needle.toLowerCase().replaceAll(RegExp(r'\s+'), ''));
}

String _extractBetween(String text, String start, String end) {
  final startIndex = text.indexOf(start);
  if (startIndex < 0) return '';
  final body = text.substring(startIndex + start.length);
  final endIndex = body.indexOf(end);
  return endIndex < 0 ? body.trim() : body.substring(0, endIndex).trim();
}

List<String> _importantNeedles(String value) {
  if (value.contains('下午不喝')) return ['上午', '下午不喝'];
  if (value.contains('低于 2.2')) return ['低于 2.2'];
  if (value.contains('英文 metric id')) return ['英文 metric id'];
  if (value.contains('来源编号')) return ['来源编号'];
  if (value.contains('超过三万')) return ['超过三万'];
  if (value.contains('收藏率')) return ['收藏率'];
  if (value.contains('9 点半')) return ['9 点半'];
  if (value.contains('周五下午')) return ['周五下午'];
  return value
      .split(RegExp('[，。,；;]'))
      .map((part) => part.trim())
      .where((part) => part.length >= 3)
      .take(2)
      .toList();
}

double _spanDays(List<JsonMap> records) {
  DateTime? first;
  DateTime? last;
  for (final record in records) {
    final time = DateTime.tryParse(record['time']?.toString() ?? '');
    if (time == null) continue;
    first = first == null || time.isBefore(first) ? time : first;
    last = last == null || time.isAfter(last) ? time : last;
  }
  if (first == null || last == null) return 0;
  return last.difference(first).inHours / 24.0;
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class _ReplayVariantSpec {
  const _ReplayVariantSpec({
    required this.id,
    required this.sourcePath,
    required this.outputDir,
    required this.recordLimit,
    required this.round,
    this.sourceCaseLimit = 8,
    this.createdAt = '2026-05-17',
    this.recordOffsets = const [0],
    this.interleaveWindows = false,
    this.mergeWindows = false,
  });

  final String id;
  final String sourcePath;
  final String outputDir;
  final int recordLimit;
  final int round;
  final int sourceCaseLimit;
  final String createdAt;
  final List<int> recordOffsets;
  final bool interleaveWindows;
  final bool mergeWindows;
}
