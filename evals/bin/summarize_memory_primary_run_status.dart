import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final runDirs = args.isNotEmpty
      ? args
      : (Platform.environment['MEMEX_EVAL_STATUS_RUN_DIRS'] ??
              Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
              '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
  if (runDirs.isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/summarize_memory_primary_run_status.dart '
      '<run_dir> [run_dir ...]',
    );
    exitCode = 64;
    return;
  }

  for (var i = 0; i < runDirs.length; i++) {
    if (i > 0) stdout.writeln('');
    await _printRunStatus(Directory(runDirs[i]));
  }
}

Future<void> _printRunStatus(Directory runDir) async {
  stdout.writeln('## ${runDir.path}');
  if (!await runDir.exists()) {
    stdout.writeln('status: missing run dir');
    return;
  }

  final progress = await _readJson(File(p.join(runDir.path, 'progress.json')));
  final metrics = await _readJson(File(p.join(runDir.path, 'metrics.json')));
  final gate = await _readJson(File(p.join(runDir.path, 'gate.json')));
  final audit =
      await _readJson(File(p.join(runDir.path, 'artifact_audit.json')));
  final judgeMetrics = await _readJson(
    File(p.join(runDir.path, 'judge', 'judge_metrics.json')),
  );
  final failuresCount =
      await _lineCount(File(p.join(runDir.path, 'failures.jsonl')));
  final observationsCount =
      await _lineCount(File(p.join(runDir.path, 'observations.jsonl')));
  final judgeTaskCount =
      await _lineCount(File(p.join(runDir.path, 'judge_tasks.jsonl')));
  final badcaseCount =
      await _lineCount(File(p.join(runDir.path, 'badcases.jsonl')));

  final last = _map(progress['last_observation']);
  if (progress.isNotEmpty) {
    stdout.writeln(
      'progress: updated=${progress['updated_at'] ?? '-'} '
      'last=${last['mode'] ?? '-'}/${last['case_id'] ?? '-'}/'
      '${last['operation_id'] ?? '-'} type=${last['type'] ?? '-'} '
      'settled=${last['tasks_settled'] ?? '-'}',
    );
  } else {
    stdout.writeln('progress: missing');
  }

  final modes = _modes(metrics);
  stdout.writeln(
    'artifacts: metrics=${metrics.isNotEmpty ? 'yes' : 'no'} '
    'gate=${gate.isNotEmpty ? gate['status'] ?? 'yes' : 'no'} '
    'audit=${_map(audit['summary'])['status'] ?? (audit.isEmpty ? 'no' : 'yes')} '
    'judge=${judgeMetrics.isNotEmpty ? 'yes' : 'no'} '
    'failures=$failuresCount observations=$observationsCount '
    'judge_tasks=$judgeTaskCount badcases=$badcaseCount',
  );

  final dataset = metrics['dataset_path'] ?? _list(metrics['dataset_paths']);
  if (dataset != null) stdout.writeln('dataset: $dataset');
  if (metrics.containsKey('llm_enabled')) {
    stdout.writeln('llm_enabled: ${metrics['llm_enabled']}');
  } else if (metrics.containsKey('llm_enabled_values')) {
    stdout.writeln('llm_enabled_values: ${metrics['llm_enabled_values']}');
  }

  final metricsByMode = _map(metrics['metrics_by_mode']);
  if (modes.isNotEmpty) {
    stdout.writeln('modes: ${modes.join(', ')}');
    stdout.writeln(
      '| Mode | Cases | Records | Asks | Query interleave | Query families | '
      'Memory hit | Recall hit | Agent hit | Settlement | Failed/Unsettled | P95 ms |',
    );
    stdout.writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
    for (final mode in modes) {
      final m = _map(metricsByMode[mode]);
      stdout.writeln(
        '| `$mode` | ${_fmt(m['case_count'])} | ${_fmt(m['record_count'])} | '
        '${_fmt(m['super_agent_ask_count'])} | '
        '${_fmt(m['agent_query_interleaving_rate'])} | '
        '${_fmt(m['agent_query_family_coverage'])} | '
        '${_fmt(m['memory_expected_hit_rate'])} | '
        '${_fmt(m['memory_recall_hit_rate'])} | '
        '${_fmt(m['super_agent_answer_hit_rate'])} | '
        '${_fmt(m['task_settlement_rate'])} | '
        '${_fmt(m['failed_task_count'])}/${_fmt(m['task_not_settled_count'])} | '
        '${_fmt(m['p95_record_elapsed_ms'])} |',
      );
    }
  }

  final failedRules = _list(gate['failed_rules']);
  if (gate.isNotEmpty) {
    stdout.writeln(
      'gate: ${gate['status'] ?? '-'} '
      'failed_rules=${failedRules.length}',
    );
  }
  if (failedRules.isNotEmpty) {
    stdout.writeln('failed_rules: ${failedRules.join('; ')}');
  }

  if (judgeMetrics.isNotEmpty) {
    final pairwise =
        _map(_map(judgeMetrics['metrics'])['pairwise_answer_quality']);
    stdout.writeln(
      'judge: tasks=${judgeMetrics['task_count'] ?? '-'} '
      'providers=${judgeMetrics['provider_count'] ?? '-'} '
      'disabled=${judgeMetrics['provider_disabled_count'] ?? '-'}',
    );
    if (pairwise.isNotEmpty) {
      stdout.writeln(
        'pairwise: wins=${_compactMap(_map(pairwise['mode_win_counts']))} '
        'match=${_compactMap(_map(pairwise['match_level_counts']))}',
      );
    }
  }
}

Future<JsonMap> _readJson(File file) async {
  if (!await file.exists()) return const {};
  final content = await file.readAsString();
  if (content.trim().isEmpty) return const {};
  return jsonDecode(content) as JsonMap;
}

Future<int> _lineCount(File file) async {
  if (!await file.exists()) return 0;
  var count = 0;
  for (final line in await file.readAsLines()) {
    if (line.trim().isNotEmpty) count += 1;
  }
  return count;
}

List<String> _modes(JsonMap metrics) {
  final modes = _list(metrics['modes']).map((item) => item.toString()).toList();
  if (modes.isNotEmpty) return modes;
  return _map(metrics['metrics_by_mode']).keys.toList()..sort();
}

String _compactMap(JsonMap map) {
  if (map.isEmpty) return '-';
  final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}:${entry.value}').join(',');
}

String _fmt(dynamic value) {
  if (value == null) return '-';
  if (value is num) {
    if (value is int) return value.toString();
    final rounded = (value * 1000).round() / 1000;
    return rounded.toStringAsFixed(
      rounded == rounded.truncateToDouble() ? 0 : 3,
    );
  }
  return value.toString();
}

JsonMap _map(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  return const [];
}
