import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final datasetPath = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_SCALE_DATASET'] ??
          'evals/datasets/pr256_full_metric_large_p12_r600_q50/cases.jsonl';
  final dataset = File(datasetPath);
  if (!await dataset.exists()) {
    stderr.writeln('Scale dataset does not exist: $datasetPath');
    exitCode = 66;
    return;
  }

  final cases = await _readCases(dataset);
  final shardSize =
      int.tryParse(Platform.environment['MEMEX_EVAL_SCALE_SHARD_SIZE'] ?? '') ??
          1;
  if (shardSize <= 0) {
    stderr.writeln('MEMEX_EVAL_SCALE_SHARD_SIZE must be positive.');
    exitCode = 64;
    return;
  }
  final runPrefix = Platform.environment['MEMEX_EVAL_SCALE_RUN_PREFIX'] ??
      'evals/runs/pr256_next_scale_p12_r600_q50';
  final outputDir = Directory(
    Platform.environment['MEMEX_EVAL_SCALE_PLAN_DIR'] ??
        p.join(runPrefix, 'plan'),
  );
  await outputDir.create(recursive: true);

  final shards = <JsonMap>[];
  for (var offset = 0; offset < cases.length; offset += shardSize) {
    final limit = (offset + shardSize <= cases.length)
        ? shardSize
        : cases.length - offset;
    final shardIndex = shards.length;
    final runDir =
        '${runPrefix}_shard_${shardIndex.toString().padLeft(2, '0')}_offset_$offset';
    final shardCases = cases.skip(offset).take(limit).toList(growable: false);
    shards.add({
      'shard_index': shardIndex,
      'case_offset': offset,
      'case_limit': limit,
      'run_dir': runDir,
      'case_ids': shardCases.map((item) => item['case_id']).toList(),
      'command': _shardCommand(
        datasetPath: datasetPath,
        runDir: runDir,
        offset: offset,
        limit: limit,
      ),
    });
  }

  final mergeCommand = _mergeCommand(shards);
  final mergedRunDir = '${runPrefix}_merged';
  final manifest = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'dataset_path': datasetPath,
    'case_count': cases.length,
    'shard_size': shardSize,
    'shard_count': shards.length,
    'run_prefix': runPrefix,
    'merged_run_dir': mergedRunDir,
    'shards': shards,
    'commands': {
      'audit_dataset':
          'dart run evals/bin/run_memory_primary_iteration.dart audit-dataset $datasetPath',
      'doctor': 'dart run evals/bin/run_memory_primary_iteration.dart doctor',
      'preflight':
          'dart run evals/bin/run_memory_primary_iteration.dart preflight',
      'status_all':
          'dart run evals/bin/run_memory_primary_iteration.dart status ${shards.map((item) => item['run_dir']).join(' ')}',
      'watch_status':
          'MEMEX_EVAL_STATUS_INTERVAL_SECONDS=300 dart run evals/bin/run_memory_primary_iteration.dart watch-status '
              '${p.join(outputDir.path, 'scale_shard_manifest.json')}',
      'merge': mergeCommand,
      'judge':
          'dart run evals/bin/run_memory_primary_iteration.dart judge $mergedRunDir',
      'badcases':
          'dart run evals/bin/run_memory_primary_iteration.dart badcases $mergedRunDir',
      'strict_audit': 'MEMEX_EVAL_AUDIT_EXPECT_MODES=legacy_pkm,memory_primary '
          'MEMEX_EVAL_AUDIT_EXPECT_LLM=1 '
          'MEMEX_EVAL_AUDIT_EXPECT_JUDGE=1 '
          'MEMEX_EVAL_AUDIT_EXPECT_PAIRWISE=1 '
          'MEMEX_EVAL_AUDIT_EXPECT_BADCASES=1 '
          'MEMEX_EVAL_AUDIT_EXPECT_GATE_PASS=1 '
          'MEMEX_EVAL_AUDIT_EXPECT_CASE_COUNT=${cases.length} '
          'dart run evals/bin/run_memory_primary_iteration.dart audit $mergedRunDir',
      'report':
          'dart run evals/bin/run_memory_primary_iteration.dart report $mergedRunDir '
              'evals/reports/${_dateStamp()}-memory-primary-scale-p12-r600-q50.zh.md',
    },
  };

  await File(p.join(outputDir.path, 'scale_shard_manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File(p.join(outputDir.path, 'scale_shard_commands.sh')).writeAsString(
    _renderShell(manifest),
    flush: true,
  );
  await File(p.join(outputDir.path, 'scale_shard_plan.md')).writeAsString(
    _renderMarkdown(manifest),
    flush: true,
  );
  stdout.writeln(
    'Planned ${shards.length} scale shards for ${cases.length} cases at ${outputDir.path}',
  );
}

Future<List<JsonMap>> _readCases(File dataset) async {
  final cases = <JsonMap>[];
  for (final line in await dataset.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    cases.add(jsonDecode(trimmed) as JsonMap);
  }
  return cases;
}

String _shardCommand({
  required String datasetPath,
  required String runDir,
  required int offset,
  required int limit,
}) {
  return 'MEMEX_EVAL_DATASET=$datasetPath '
      'MEMEX_EVAL_CASE_OFFSET=$offset '
      'MEMEX_EVAL_CASE_LIMIT=$limit '
      'MEMEX_EVAL_RUN_DIR=$runDir '
      'dart run evals/bin/run_memory_primary_iteration.dart scale-shard';
}

String _mergeCommand(List<JsonMap> shards) {
  final runDirs = shards.map((item) => item['run_dir']).join(' ');
  final first = shards.isEmpty ? 'evals/runs/pr256_next_scale_merged' : null;
  final output =
      first ?? _mergedFromRunPrefix(shards.first['run_dir'].toString());
  return 'MEMEX_EVAL_MERGE_OUTPUT_DIR=$output '
      'dart run evals/bin/run_memory_primary_iteration.dart merge $runDirs';
}

String _mergedFromRunPrefix(String runDir) {
  final marker = RegExp(r'_shard_\d+_offset_\d+$');
  return runDir.replaceFirst(marker, '_merged');
}

String _renderShell(JsonMap manifest) {
  final b = StringBuffer();
  b.writeln('#!/usr/bin/env bash');
  b.writeln('set -euo pipefail');
  b.writeln('');
  b.writeln(
      '# Export provider env vars in your shell before running this file.');
  b.writeln('# This script intentionally contains no API keys.');
  b.writeln('');
  b.writeln(_map(manifest['commands'])['audit_dataset']);
  b.writeln(_map(manifest['commands'])['doctor']);
  b.writeln(_map(manifest['commands'])['preflight']);
  b.writeln('');
  b.writeln(
      '# Run shards. Start with low concurrency, then increase after provider health is clear.');
  b.writeln(
      '# If provider_infra_task_error_count is nonzero, rerun affected shards after lowering concurrency or changing provider priorities.');
  for (final shard in _list(manifest['shards']).map(_map)) {
    b.writeln(shard['command']);
  }
  b.writeln('');
  b.writeln(_map(manifest['commands'])['status_all']);
  b.writeln(_map(manifest['commands'])['watch_status']);
  b.writeln(_map(manifest['commands'])['merge']);
  b.writeln(_map(manifest['commands'])['judge']);
  b.writeln(_map(manifest['commands'])['badcases']);
  b.writeln(_map(manifest['commands'])['strict_audit']);
  b.writeln(_map(manifest['commands'])['report']);
  return b.toString();
}

String _renderMarkdown(JsonMap manifest) {
  final commands = _map(manifest['commands']);
  final b = StringBuffer();
  b.writeln('# Memory Primary Scale Shard Plan');
  b.writeln('');
  b.writeln('| Item | Value |');
  b.writeln('| --- | ---: |');
  b.writeln('| Case count | ${manifest['case_count']} |');
  b.writeln('| Shard size | ${manifest['shard_size']} |');
  b.writeln('| Shard count | ${manifest['shard_count']} |');
  b.writeln('| Merged run dir | `${manifest['merged_run_dir']}` |');
  b.writeln('');
  b.writeln('## Provider Pool Guardrails');
  b.writeln('');
  b.writeln(
      '- Run record-chain shards serially or with very low concurrency until provider health is proven.');
  b.writeln(
      '- Keep a single persona on one configured provider slot for comparability; use `MEMEX_EVAL_LLM_PROVIDER_PRIORITIES` to avoid unhealthy slots before launch.');
  b.writeln(
      '- If a shard reports nonzero `provider_infra_task_error_count` or `provider_infra_affected_operation_rate`, treat it as provider-contaminated evidence and rerun that shard after lowering concurrency or removing/quarantining the provider.');
  b.writeln(
      '- Judge can run with higher concurrency because it has independent provider fallback and randomized answer order does not mutate persona state.');
  b.writeln('');
  b.writeln('## Shards');
  b.writeln('');
  b.writeln('| Shard | Offset | Limit | Cases | Run dir |');
  b.writeln('| ---: | ---: | ---: | --- | --- |');
  for (final shard in _list(manifest['shards']).map(_map)) {
    b.writeln(
      '| ${shard['shard_index']} | ${shard['case_offset']} | '
      '${shard['case_limit']} | ${_list(shard['case_ids']).join(', ')} | '
      '`${shard['run_dir']}` |',
    );
  }
  b.writeln('');
  b.writeln('## Commands');
  b.writeln('');
  for (final entry in commands.entries) {
    b.writeln('### `${entry.key}`');
    b.writeln('');
    b.writeln('```bash');
    b.writeln(entry.value);
    b.writeln('```');
    b.writeln('');
  }
  return b.toString();
}

String _dateStamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
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
