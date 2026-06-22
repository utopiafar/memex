import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final runDirPath = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
          Platform.environment['MEMEX_EVAL_BADCASE_RUN_DIR'] ??
          '';
  if (runDirPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/render_memory_primary_badcases.dart <run_dir>',
    );
    exitCode = 64;
    return;
  }
  final runDir = Directory(runDirPath);
  if (!await runDir.exists()) {
    stderr.writeln('Run directory does not exist: ${runDir.path}');
    exitCode = 66;
    return;
  }

  final metrics = await _readJson(File(p.join(runDir.path, 'metrics.json')));
  final failures =
      await _readJsonl(File(p.join(runDir.path, 'failures.jsonl')));
  final observations =
      await _readJsonl(File(p.join(runDir.path, 'observations.jsonl')));
  final cases = await _loadDatasetCases(metrics);
  final badcases = _buildBadcases(
    runDir: runDir,
    failures: failures,
    observations: observations,
    cases: cases,
  );

  await _writeJsonl(File(p.join(runDir.path, 'badcases.jsonl')), badcases);
  await File(
    p.join(runDir.path, 'badcases.md'),
  ).writeAsString(_renderMarkdown(runDir, badcases), flush: true);
  stdout.writeln(
    'Rendered ${badcases.length} badcases into ${runDir.path}/badcases.md',
  );
}

List<JsonMap> _buildBadcases({
  required Directory runDir,
  required List<JsonMap> failures,
  required List<JsonMap> observations,
  required Map<String, JsonMap> cases,
}) {
  final observationsByKey = <String, JsonMap>{};
  for (final obs in observations) {
    observationsByKey[_key(
      obs['mode']?.toString(),
      obs['case_id']?.toString(),
      obs['operation_id']?.toString(),
    )] = obs;
  }

  final grouped = <String, List<JsonMap>>{};
  for (final failure in failures) {
    final key = _key(
      failure['mode']?.toString(),
      failure['case_id']?.toString(),
      failure['operation_id']?.toString(),
    );
    grouped.putIfAbsent(key, () => <JsonMap>[]).add(failure);
  }

  final result = <JsonMap>[];
  for (final entry in grouped.entries) {
    final first = entry.value.first;
    final mode = first['mode']?.toString() ?? 'unknown';
    final caseId = first['case_id']?.toString() ?? 'unknown';
    final operationId = first['operation_id']?.toString() ?? 'unknown';
    final evalCase = cases[caseId] ?? const {};
    final operation = _operationById(evalCase, operationId);
    final observation = observationsByKey[entry.key] ?? const {};
    final categories = entry.value
        .map((failure) => failure['category']?.toString() ?? 'unknown')
        .toSet()
        .toList()
      ..sort();
    final rootCause = _rootCauseFor(mode, categories, entry.value, observation);
    final caseLog = p.join('case_logs', mode, '$caseId.json');
    result.add({
      'case_id': caseId,
      'persona': _map(evalCase['persona']),
      'mode': mode,
      'operation_id': operationId,
      'operation_type':
          operation['type']?.toString() ?? observation['type']?.toString(),
      'input': _inputFor(operation, observation),
      'expected_result': _expectedFor(operation, observation),
      'actual_result': _actualFor(observation, entry.value),
      'failed_metrics': categories,
      'failure_count': entry.value.length,
      'root_cause_classification': rootCause,
      'fix_point': _fixPointFor(mode, rootCause, categories),
      'verification_artifact': {
        'case_log': caseLog,
        'failures_jsonl': 'failures.jsonl',
        'observations_jsonl': 'observations.jsonl',
        'case_debug_index': 'case_debug_index.md',
      },
      'verification_command':
          'dart run evals/bin/run_memory_primary_iteration.dart status ${runDir.path}',
      'affects_legacy_chain': mode == 'legacy_pkm',
      'requires_scale_retest': mode != 'legacy_pkm' &&
          !categories.every((category) => category == 'super_agent_ask_error'),
      'failures': entry.value,
    });
  }
  result.sort((a, b) {
    final modeCompare = (a['mode'] ?? '').toString().compareTo(
          (b['mode'] ?? '').toString(),
        );
    if (modeCompare != 0) return modeCompare;
    final caseCompare = (a['case_id'] ?? '').toString().compareTo(
          (b['case_id'] ?? '').toString(),
        );
    if (caseCompare != 0) return caseCompare;
    return (a['operation_id'] ?? '').toString().compareTo(
          (b['operation_id'] ?? '').toString(),
        );
  });
  return result;
}

String _renderMarkdown(Directory runDir, List<JsonMap> badcases) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Badcase Ledger');
  b.writeln('');
  b.writeln('- Run dir: `${runDir.path}`');
  b.writeln('- Badcases: `${badcases.length}`');
  b.writeln('');
  if (badcases.isEmpty) {
    b.writeln('No badcases recorded.');
    return b.toString();
  }
  b.writeln(
      '| Mode | Case | Operation | Type | Failed metrics | Root cause | Case log |');
  b.writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final badcase in badcases) {
    final artifact = _map(badcase['verification_artifact']);
    b.writeln(
      '| `${badcase['mode']}` | `${badcase['case_id']}` | '
      '`${badcase['operation_id']}` | `${badcase['operation_type'] ?? '-'}` | '
      '${_inlineList(_list(badcase['failed_metrics']))} | '
      '`${badcase['root_cause_classification']}` | '
      '`${artifact['case_log'] ?? '-'}` |',
    );
  }
  b.writeln('');
  for (var i = 0; i < badcases.length; i++) {
    final badcase = badcases[i];
    final persona = _map(badcase['persona']);
    final artifact = _map(badcase['verification_artifact']);
    b.writeln(
        '## ${i + 1}. `${badcase['mode']}` / `${badcase['case_id']}` / `${badcase['operation_id']}`');
    b.writeln('');
    b.writeln('| Field | Value |');
    b.writeln('| --- | --- |');
    b.writeln('| Persona | ${_personaSummary(persona)} |');
    b.writeln('| Input | ${_shortJson(badcase['input'])} |');
    b.writeln(
        '| Expected result | ${_shortJson(badcase['expected_result'])} |');
    b.writeln('| Actual result | ${_shortJson(badcase['actual_result'])} |');
    b.writeln(
        '| Failed metrics | ${_inlineList(_list(badcase['failed_metrics']))} |');
    b.writeln('| Root cause | `${badcase['root_cause_classification']}` |');
    b.writeln('| Fix point | ${badcase['fix_point']} |');
    b.writeln(
        '| Verification command | `${badcase['verification_command']}` |');
    b.writeln('| Verification artifact | `${artifact['case_log'] ?? '-'}` |');
    b.writeln(
        '| Affects legacy chain | `${badcase['affects_legacy_chain']}` |');
    b.writeln('| Needs scale retest | `${badcase['requires_scale_retest']}` |');
    b.writeln('');
  }
  return b.toString();
}

dynamic _inputFor(JsonMap operation, JsonMap observation) {
  final content = operation['content'] ?? operation['query'];
  return {
    if (operation['type'] != null) 'type': operation['type'],
    if (operation['time'] != null) 'time': operation['time'],
    if (content != null) 'content': content,
    if (content == null && observation['query'] != null)
      'content': observation['query'],
  };
}

dynamic _expectedFor(JsonMap operation, JsonMap observation) {
  return operation['expected'] ?? observation['expected'] ?? const {};
}

dynamic _actualFor(JsonMap observation, List<JsonMap> failures) {
  return {
    if (observation['answer'] != null) 'answer': observation['answer'],
    if (observation['error'] != null) 'error': observation['error'],
    if (observation['expected_hits'] != null)
      'expected_hits': observation['expected_hits'],
    if (observation['expected_total'] != null)
      'expected_total': observation['expected_total'],
    if (observation['forbidden_hits'] != null)
      'forbidden_hits': observation['forbidden_hits'],
    if (observation['retrieval_source_eval'] != null)
      'retrieval_source_eval': observation['retrieval_source_eval'],
    'failure_messages': failures
        .map((failure) => {
              'category': failure['category'],
              'message': failure['message'],
              if (failure['details'] != null) 'details': failure['details'],
            })
        .toList(),
  };
}

String _rootCauseFor(
  String mode,
  List<String> categories,
  List<JsonMap> failures,
  JsonMap observation,
) {
  if (_hasSkippedWithoutLlm(failures, observation)) return 'provider_not_run';
  if (_hasProviderInfrastructureFailure(failures, observation)) {
    return 'provider_infrastructure';
  }
  if (mode == 'legacy_pkm') {
    if (_hasLegacyChainFailure(categories, failures, observation)) {
      return 'legacy_chain_failure';
    }
    return 'legacy_baseline_gap';
  }
  if (categories.any((category) => category.contains('route'))) {
    return 'agent_orchestration';
  }
  if (categories.any((category) => category.startsWith('memory_expected'))) {
    return 'memory_write_missing';
  }
  if (categories.any((category) =>
      category.contains('recall') || category.contains('retrieval'))) {
    return 'memory_recall_or_ranking';
  }
  if (categories.any((category) => category.contains('tool'))) {
    return 'super_agent_tool_grounding';
  }
  if (categories.any((category) => category.startsWith('super_agent'))) {
    return 'super_agent_answer_quality';
  }
  if (categories.any((category) => category.contains('related_fact'))) {
    return 'card_insight_related_fact';
  }
  return 'unknown';
}

bool _hasSkippedWithoutLlm(List<JsonMap> failures, JsonMap observation) {
  if (observation['error'] == 'skipped_without_llm') return true;
  return failures.any((failure) {
    final details = _map(failure['details']);
    return details['error'] == 'skipped_without_llm';
  });
}

bool _hasProviderInfrastructureFailure(
  List<JsonMap> failures,
  JsonMap observation,
) {
  final haystacks = <String>[
    observation['error']?.toString() ?? '',
    for (final failure in failures) ...[
      failure['message']?.toString() ?? '',
      jsonEncode(_map(failure['details'])),
    ],
  ].join('\n').toLowerCase();
  return haystacks.contains('429') ||
      haystacks.contains('too many requests') ||
      haystacks.contains('out of quota') ||
      haystacks.contains('quota') ||
      haystacks.contains('rate limit') ||
      haystacks.contains('connection') ||
      haystacks.contains('timeout');
}

bool _hasLegacyChainFailure(
  List<String> categories,
  List<JsonMap> failures,
  JsonMap observation,
) {
  if (categories.any((category) =>
      category == 'task_not_settled' ||
      category == 'task_failed' ||
      category.contains('loop') ||
      category.contains('max_turns'))) {
    return true;
  }
  final counts = _map(observation['task_status_counts']);
  if ((_intValue(counts['failed']) ?? 0) > 0 ||
      (_intValue(counts['processing']) ?? 0) > 0 ||
      (_intValue(counts['retrying']) ?? 0) > 0) {
    return true;
  }
  final haystack = failures
      .map((failure) => [
            failure['message']?.toString() ?? '',
            jsonEncode(_map(failure['details'])),
          ].join('\n'))
      .join('\n')
      .toLowerCase();
  return haystack.contains('agentexception') ||
      haystack.contains('max turns') ||
      haystack.contains('loop') ||
      haystack.contains('deadlock') ||
      haystack.contains('exception');
}

String _fixPointFor(
  String mode,
  String rootCause,
  List<String> categories,
) {
  if (rootCause == 'provider_not_run') {
    return '注入 MiMo/OpenRouter provider env 后重跑；这不是效果修复点。';
  }
  if (rootCause == 'provider_infrastructure') {
    return '剔除或降级触发 429/out-of-quota/连接异常的 provider 后重跑；不作为链路效果修复点。';
  }
  if (rootCause == 'legacy_chain_failure') {
    return '老链路冻结；将死循环、max-turns、未退出、任务异常等固有链路失败计入 legacy failure，不修改 legacy_pkm。';
  }
  if (mode == 'legacy_pkm') {
    return '老链路冻结；只记录 baseline 差距，不修改 legacy_pkm。';
  }
  switch (rootCause) {
    case 'agent_orchestration':
      return '检查 Memory Primary task 编排、route expectation 或 task settlement instrumentation。';
    case 'memory_write_missing':
      return '检查 MemoryExtractAgent patch、Memory schema、dedupe/supersede/update 合并逻辑。';
    case 'memory_recall_or_ranking':
      return '检查 FTS + embedding 候选、RRF 融合、chunk 表达、retrieval source instrumentation。';
    case 'super_agent_tool_grounding':
      return '检查 search_memory_primary tool 输出、Super Agent Quick Query 工具选择和参数 grounding。';
    case 'super_agent_answer_quality':
      return '检查 Quick Query prompt、answer grounding、unsupported-claim 抑制和引用证据可见性。';
    case 'card_insight_related_fact':
      return '检查 CardInsightAgent 的相关 fact 召回和 evidence 绑定。';
  }
  return '需要人工查看 case log 后补充精确修复点。';
}

JsonMap _operationById(JsonMap evalCase, String operationId) {
  for (final operation in _list(evalCase['operations']).map(_map)) {
    if (operation['id'] == operationId) return operation;
  }
  return const {};
}

Future<Map<String, JsonMap>> _loadDatasetCases(JsonMap metrics) async {
  final paths = <String>{
    if (metrics['dataset_path'] != null) metrics['dataset_path'].toString(),
    ..._list(metrics['dataset_paths']).map((item) => item.toString()),
  };
  final cases = <String, JsonMap>{};
  for (final path in paths) {
    final file = File(path);
    if (!await file.exists()) continue;
    for (final line in await file.readAsLines()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final evalCase = jsonDecode(trimmed) as JsonMap;
      final caseId = evalCase['case_id']?.toString();
      if (caseId != null && caseId.isNotEmpty) cases[caseId] = evalCase;
    }
  }
  return cases;
}

Future<JsonMap> _readJson(File file) async {
  if (!await file.exists()) return const {};
  final content = await file.readAsString();
  if (content.trim().isEmpty) return const {};
  return jsonDecode(content) as JsonMap;
}

Future<List<JsonMap>> _readJsonl(File file) async {
  if (!await file.exists()) return const [];
  final rows = <JsonMap>[];
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    rows.add(jsonDecode(trimmed) as JsonMap);
  }
  return rows;
}

Future<void> _writeJsonl(File file, List<JsonMap> rows) async {
  final sink = file.openWrite();
  try {
    for (final row in rows) {
      sink.writeln(jsonEncode(row));
    }
  } finally {
    await sink.close();
  }
}

String _key(String? mode, String? caseId, String? operationId) {
  return '${mode ?? ''}|${caseId ?? ''}|${operationId ?? ''}';
}

String _personaSummary(JsonMap persona) {
  if (persona.isEmpty) return '-';
  final parts = [
    if (persona['user_id'] != null) 'user=${persona['user_id']}',
    if (persona['role'] != null) 'role=${persona['role']}',
    if (persona['secondary_role'] != null)
      'secondary=${persona['secondary_role']}',
    if (persona['city'] != null) 'city=${persona['city']}',
    if (persona['travel_city'] != null) 'travel=${persona['travel_city']}',
    if (persona['mood_before'] != null) 'mood_before=${persona['mood_before']}',
    if (persona['mood_after'] != null) 'mood_after=${persona['mood_after']}',
    if (persona['conflict_topic'] != null)
      'conflict=${persona['conflict_topic']}',
  ];
  return parts.map(_escape).join('<br>');
}

String _inlineList(List<dynamic> values) {
  if (values.isEmpty) return '-';
  return values.map((value) => '`${_escape(value)}`').join(', ');
}

String _shortJson(dynamic value) {
  final encoded = jsonEncode(value);
  const maxLength = 900;
  final text = encoded.length <= maxLength
      ? encoded
      : '${encoded.substring(0, maxLength)}...';
  return _escape(text);
}

String _escape(Object? value) {
  return (value ?? '-').toString().replaceAll('|', r'\|').replaceAll('\n', ' ');
}

JsonMap _map(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  return const [];
}
