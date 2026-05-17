import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main() async {
  await _writeVariant(
    id: 'full_chain_journey_real_replay_v1',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v1/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v1',
    recordLimit: 8,
    round: 1,
  );
  await _writeVariant(
    id: 'full_chain_journey_real_replay_v2',
    sourcePath: 'evals/datasets/full_chain_journey_scale_v2/cases.jsonl',
    outputDir: 'evals/datasets/full_chain_journey_real_replay_v2',
    recordLimit: 16,
    round: 2,
  );
}

Future<void> _writeVariant({
  required String id,
  required String sourcePath,
  required String outputDir,
  required int recordLimit,
  required int round,
}) async {
  final cases = await _loadCases(sourcePath);
  final replayCases = [
    for (final evalCase in cases.take(8))
      _replayCase(evalCase: evalCase, recordLimit: recordLimit, round: round),
  ];
  final outDir = Directory(outputDir);
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

  final manifest = {
    'dataset_id': 'memex_$id',
    'version': round,
    'description':
        '真实 full-chain replay 数据集：8 用户，每用户 $recordLimit 条 record，加 timeline browse、comment、schedule refresh、knowledge insight refresh、memory wait、Super Agent quick query。',
    'created_at': '2026-05-17',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': replayCases.length,
    'case_count': replayCases.length,
    'records_per_persona': recordLimit,
    'input_count': recordCount,
    'operation_count': operationCount,
    'eval_task_count': taskCount,
    'families': [id],
    'evidence_goal':
        '通过 serial_full_chain_replay_test.dart 走真实 Memex 链路，再用 replay_file adapter 评分为 real_replay。',
  };

  await File('$outputDir/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File('$outputDir/cases.jsonl').writeAsString(
    '${replayCases.map(jsonEncode).join('\n')}\n',
    flush: true,
  );
  stdout.writeln(
    'Generated $id: ${replayCases.length} users, $recordCount records, '
    '$operationCount operations, $taskCount tasks at $outputDir',
  );
}

JsonMap _replayCase({
  required JsonMap evalCase,
  required int recordLimit,
  required int round,
}) {
  final caseId = evalCase['case_id'].toString().replaceFirst(
        'journey_scale',
        'journey_real_replay',
      );
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

  final records = _list(evalCase['operations'])
      .map(_map)
      .where((operation) => operation['type'] == 'record')
      .take(recordLimit)
      .map((operation) => {...operation, 'id': _remapId(operation['id'])})
      .toList();
  final lastRecordTime = records.last['time']?.toString();
  final commentTarget = records.length >= 4
      ? records[3]['id'].toString()
      : records.first['id'].toString();
  final askId = '${caseId}_ask_001';
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
      'must_include_any': [
        project,
        primaryPerson,
        '提前一天',
        ..._importantNeedles(latestPreference),
      ].where((value) => value.trim().isNotEmpty).toList(),
    },
    {
      'id': askId,
      'type': 'ask_super_agent',
      'time': lastRecordTime,
      'query': '总结一下 $project 的负责人、提醒偏好和最新边界。只基于已有记录回答。',
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
          'require_all_tasks_completed': true,
          'min_record_operations': recordLimit,
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
          'must_write': [
            {
              'id': '${caseId}_mem_reminder',
              'must_include': ['提前一天'],
            },
            if (project.isNotEmpty && primaryPerson.isNotEmpty)
              {
                'id': '${caseId}_mem_project_owner',
                'must_include': [project, primaryPerson],
              },
            if (latestPreference.isNotEmpty)
              {
                'id': '${caseId}_mem_latest_preference',
                'must_include': _importantNeedles(latestPreference),
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
          ],
          'evaluate_write_precision': false,
          'max_duplicate_rate': 0.35,
        },
      },
      {
        'task_id': '${caseId}_card_project',
        'type': 'card_extraction',
        'expected': {
          'operation_id':
              records.length >= 4 ? records[3]['id'] : records.first['id'],
          'status': 'completed',
          'title_contains': [
            if (project.isNotEmpty) project,
            if (primaryPerson.isNotEmpty) primaryPerson,
          ],
          'must_not_fields': ['stock_price'],
          'max_latency_ms': 600000,
        },
      },
      if (round >= 2 && records.length >= 12)
        {
          'task_id': '${caseId}_card_boundary',
          'type': 'card_extraction',
          'expected': {
            'operation_id': records[11]['id'],
            'status': 'completed',
            'title_contains': [
              if (project.isNotEmpty) project,
            ],
            'must_not_fields': ['stock_price'],
            'max_latency_ms': 600000,
          },
        },
      {
        'task_id': '${caseId}_super_agent',
        'type': 'super_agent_qa',
        'query': '总结一下 $project 的负责人、提醒偏好和最新边界。只基于已有记录回答。',
        'expected': {
          'operation_id': askId,
          'must_include': [
            if (project.isNotEmpty) project,
            if (primaryPerson.isNotEmpty) primaryPerson,
            ..._importantNeedles(latestPreference),
          ],
          if (boundary.isNotEmpty) 'personalization_must_include': [project],
          'allowed_uncertainty': false,
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

String _remapId(Object? id) =>
    id.toString().replaceFirst('journey_scale', 'journey_real_replay');

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
