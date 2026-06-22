import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final manifestPath = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_SCALE_SHARD_MANIFEST'] ??
          'evals/runs/pr256_next_scale_p12_r600_q50/plan/scale_shard_manifest.json';
  final manifestFile = File(manifestPath);
  if (!await manifestFile.exists()) {
    stderr.writeln('Scale shard manifest does not exist: $manifestPath');
    exitCode = 66;
    return;
  }

  final manifest = jsonDecode(await manifestFile.readAsString()) as JsonMap;
  final audit = await _auditManifest(manifestFile, manifest);
  final outputDir = Directory(
    Platform.environment['MEMEX_EVAL_SCALE_SHARD_AUDIT_OUT_DIR'] ??
        p.dirname(manifestFile.path),
  );
  await outputDir.create(recursive: true);
  await File(p.join(outputDir.path, 'scale_shard_audit.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(audit.toJson()),
    flush: true,
  );
  await File(
    p.join(outputDir.path, 'scale_shard_audit.md'),
  ).writeAsString(_renderMarkdown(audit), flush: true);

  stdout.writeln(_summaryLine(audit));
  if (audit.findings.any((finding) => finding.severity == 'error')) {
    exitCode = 1;
  }
}

Future<_AuditResult> _auditManifest(File manifestFile, JsonMap manifest) async {
  final findings = <_Finding>[];
  final shardResults = <JsonMap>[];
  final expectedDataset = manifest['dataset_path']?.toString();
  final shards = _list(manifest['shards']).map(_map).toList(growable: false);
  final expectedCaseIds = <String>{
    for (final shard in shards)
      ..._list(shard['case_ids']).map((item) => item.toString()),
  };
  final observedCaseIds = <String>{};
  final duplicateObservedCaseIds = <String>{};
  final allowIncomplete = _boolEnv('MEMEX_EVAL_SHARD_AUDIT_ALLOW_INCOMPLETE');
  final expectLlm = _boolEnv('MEMEX_EVAL_SHARD_AUDIT_EXPECT_LLM');
  final expectedModes = _envList('MEMEX_EVAL_SHARD_AUDIT_EXPECT_MODES');
  final expectedRecordsPerCase =
      _intEnv('MEMEX_EVAL_SHARD_AUDIT_EXPECT_RECORDS_PER_CASE') ?? 600;
  final expectedAsksPerCase =
      _intEnv('MEMEX_EVAL_SHARD_AUDIT_EXPECT_AGENT_QUERIES_PER_CASE') ?? 50;

  for (final shard in shards) {
    final result = await _auditShard(
      shard: shard,
      expectedDataset: expectedDataset,
      expectedModes: expectedModes.isEmpty
          ? const ['legacy_pkm', 'memory_primary']
          : expectedModes,
      expectedRecordsPerCase: expectedRecordsPerCase,
      expectedAsksPerCase: expectedAsksPerCase,
      expectLlm: expectLlm,
      missingSeverity: allowIncomplete ? 'warning' : 'error',
      findings: findings,
    );
    shardResults.add(result);
    for (final caseId in _list(result['observed_case_ids'])) {
      final id = caseId.toString();
      if (!observedCaseIds.add(id)) duplicateObservedCaseIds.add(id);
    }
  }

  final missingCaseIds = expectedCaseIds.difference(observedCaseIds).toList()
    ..sort();
  final unexpectedCaseIds = observedCaseIds.difference(expectedCaseIds).toList()
    ..sort();
  if (missingCaseIds.isNotEmpty && !allowIncomplete) {
    findings.add(
      _Finding.error(
        'missing_case_ids',
        'Expected case ids are missing from completed shard artifacts.',
        {'missing': missingCaseIds},
      ),
    );
  } else if (missingCaseIds.isNotEmpty) {
    findings.add(
      _Finding.warning(
        'missing_case_ids',
        'Some expected case ids are not present yet.',
        {'missing': missingCaseIds},
      ),
    );
  }
  if (unexpectedCaseIds.isNotEmpty) {
    findings.add(
      _Finding.error(
        'unexpected_case_ids',
        'Shard artifacts contain unexpected case ids.',
        {'unexpected': unexpectedCaseIds},
      ),
    );
  }
  if (duplicateObservedCaseIds.isNotEmpty) {
    findings.add(
      _Finding.error(
        'duplicate_case_ids',
        'Case ids appear in more than one shard.',
        {'duplicates': duplicateObservedCaseIds.toList()..sort()},
      ),
    );
  }

  final completedShards =
      shardResults.where((result) => result['status'] == 'complete').length;
  final missingShards =
      shardResults.where((result) => result['status'] == 'missing').length;
  final incompleteShards =
      shardResults.where((result) => result['status'] == 'incomplete').length;

  return _AuditResult(
    manifestPath: manifestFile.path,
    findings: findings,
    summary: {
      'shard_count': shards.length,
      'completed_shard_count': completedShards,
      'missing_shard_count': missingShards,
      'incomplete_shard_count': incompleteShards,
      'expected_case_count': expectedCaseIds.length,
      'observed_case_count': observedCaseIds.length,
      'missing_case_count': missingCaseIds.length,
      'unexpected_case_count': unexpectedCaseIds.length,
      'allow_incomplete': allowIncomplete,
      'expect_llm': expectLlm,
    },
    shardResults: shardResults,
  );
}

Future<JsonMap> _auditShard({
  required JsonMap shard,
  required String? expectedDataset,
  required List<String> expectedModes,
  required int expectedRecordsPerCase,
  required int expectedAsksPerCase,
  required bool expectLlm,
  required String missingSeverity,
  required List<_Finding> findings,
}) async {
  final runDir = Directory(shard['run_dir']?.toString() ?? '');
  final shardIndex = _intValue(shard['shard_index']);
  final expectedCaseIds = _list(shard['case_ids'])
      .map((item) => item.toString())
      .toList(growable: false);
  final expectedCaseCount = _intValue(shard['case_limit']);
  final metricsFile = File(p.join(runDir.path, 'metrics.json'));
  if (!await runDir.exists() || !await metricsFile.exists()) {
    findings.add(
      _finding(
        missingSeverity,
        'missing_shard',
        'Shard run directory or metrics.json is missing.',
        {
          'shard_index': shardIndex,
          'run_dir': runDir.path,
          'expected_case_ids': expectedCaseIds,
        },
      ),
    );
    return {
      'shard_index': shardIndex,
      'run_dir': runDir.path,
      'status': 'missing',
      'expected_case_ids': expectedCaseIds,
      'observed_case_ids': const [],
    };
  }

  late final JsonMap metrics;
  try {
    metrics = jsonDecode(await metricsFile.readAsString()) as JsonMap;
  } catch (error) {
    findings.add(
      _Finding.error(
        'metrics_parse',
        'Shard metrics.json is not valid JSON.',
        {'shard_index': shardIndex, 'run_dir': runDir.path, 'error': '$error'},
      ),
    );
    return {
      'shard_index': shardIndex,
      'run_dir': runDir.path,
      'status': 'incomplete',
      'expected_case_ids': expectedCaseIds,
      'observed_case_ids': const [],
    };
  }

  final observedCaseIds = await _caseIdsFromCaseLogs(runDir, expectedModes);
  final modeMetrics = _map(metrics['metrics_by_mode']);
  final modes = _modes(metrics);
  final modeFindings = <JsonMap>[];
  void addShardFindingWithSeverity(
    String severity,
    String check,
    String message,
    JsonMap details,
  ) {
    final finding = _finding(severity, check, message, {
      'shard_index': shardIndex,
      'run_dir': runDir.path,
      ...details,
    });
    findings.add(finding);
    modeFindings.add(finding.toJson());
  }

  void addShardFinding(String check, String message, JsonMap details) {
    addShardFindingWithSeverity('error', check, message, details);
  }

  if (expectedDataset != null &&
      metrics['dataset_path']?.toString() != expectedDataset) {
    addShardFinding('dataset_path', 'Shard dataset path differs from plan.', {
      'expected': expectedDataset,
      'actual': metrics['dataset_path'],
    });
  }
  if (_intValue(metrics['case_offset']) != _intValue(shard['case_offset'])) {
    addShardFinding('case_offset', 'Shard case offset differs from plan.', {
      'expected': shard['case_offset'],
      'actual': metrics['case_offset'],
    });
  }
  if (_intValue(metrics['case_limit']) != expectedCaseCount) {
    addShardFinding('case_limit', 'Shard case limit differs from plan.', {
      'expected': expectedCaseCount,
      'actual': metrics['case_limit'],
    });
  }
  for (final mode in expectedModes) {
    if (!modes.contains(mode)) {
      addShardFinding('mode_missing', 'Expected mode is missing.', {
        'mode': mode,
        'actual_modes': modes,
      });
      continue;
    }
    final m = _map(modeMetrics[mode]);
    if (_intValue(m['case_count']) != expectedCaseCount) {
      addShardFinding('mode_case_count', 'Mode case count mismatch.', {
        'mode': mode,
        'expected': expectedCaseCount,
        'actual': m['case_count'],
      });
    }
    final expectedRecords = expectedCaseCount * expectedRecordsPerCase;
    if (_intValue(m['record_count']) != expectedRecords) {
      addShardFinding('mode_record_count', 'Mode record count mismatch.', {
        'mode': mode,
        'expected': expectedRecords,
        'actual': m['record_count'],
      });
    }
    final expectedAsks = expectedCaseCount * expectedAsksPerCase;
    if (_intValue(m['super_agent_ask_count']) != expectedAsks) {
      addShardFinding(
          'mode_agent_query_count', 'Mode Agent ask count mismatch.', {
        'mode': mode,
        'expected': expectedAsks,
        'actual': m['super_agent_ask_count'],
      });
    }
    final providerInfraTaskErrors =
        _intValue(m['provider_infra_task_error_count']);
    if (providerInfraTaskErrors > 0) {
      addShardFindingWithSeverity(
        'warning',
        'provider_infra_errors',
        'Mode has provider infrastructure errors; rerun this shard before effect-quality conclusions.',
        {
          'mode': mode,
          'provider_infra_task_error_count': providerInfraTaskErrors,
          'provider_rate_limit_task_error_count':
              _intValue(m['provider_rate_limit_task_error_count']),
          'provider_quota_task_error_count':
              _intValue(m['provider_quota_task_error_count']),
          'provider_infra_affected_operation_count':
              _intValue(m['provider_infra_affected_operation_count']),
        },
      );
    }
  }
  if (expectLlm && metrics['llm_enabled'] != true) {
    addShardFinding('llm_enabled', 'Expected real LLM shard.', {
      'actual': metrics['llm_enabled'],
    });
  }
  for (final expectedCaseId in expectedCaseIds) {
    if (!observedCaseIds.contains(expectedCaseId)) {
      addShardFinding('case_log_missing', 'Expected case log is missing.', {
        'case_id': expectedCaseId,
        'observed_case_ids': observedCaseIds.toList()..sort(),
      });
    }
  }

  return {
    'shard_index': shardIndex,
    'run_dir': runDir.path,
    'status': modeFindings.isEmpty ? 'complete' : 'incomplete',
    'expected_case_ids': expectedCaseIds,
    'observed_case_ids': observedCaseIds.toList()..sort(),
    'dataset_path': metrics['dataset_path'],
    'case_offset': metrics['case_offset'],
    'case_limit': metrics['case_limit'],
    'llm_enabled': metrics['llm_enabled'],
    'modes': modes,
    if (modeFindings.isNotEmpty) 'findings': modeFindings,
  };
}

Future<Set<String>> _caseIdsFromCaseLogs(
  Directory runDir,
  List<String> modes,
) async {
  final result = <String>{};
  for (final mode in modes) {
    final modeDir = Directory(p.join(runDir.path, 'case_logs', mode));
    if (!await modeDir.exists()) continue;
    await for (final entity in modeDir.list(recursive: false)) {
      if (entity is! File || p.extension(entity.path) != '.json') continue;
      result.add(p.basenameWithoutExtension(entity.path));
    }
  }
  return result;
}

String _renderMarkdown(_AuditResult audit) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Scale Shard Audit');
  b.writeln('');
  b.writeln('| Item | Value |');
  b.writeln('| --- | ---: |');
  for (final entry in audit.summary.entries) {
    b.writeln('| `${entry.key}` | ${entry.value} |');
  }
  b.writeln('');
  b.writeln('## Shards');
  b.writeln('');
  b.writeln('| Shard | Status | Run dir | Expected cases | Observed cases |');
  b.writeln('| ---: | --- | --- | --- | --- |');
  for (final shard in audit.shardResults) {
    b.writeln(
      '| ${shard['shard_index']} | `${shard['status']}` | '
      '`${shard['run_dir']}` | ${_list(shard['expected_case_ids']).join(', ')} | '
      '${_list(shard['observed_case_ids']).join(', ')} |',
    );
  }
  b.writeln('');
  b.writeln('## Findings');
  b.writeln('');
  if (audit.findings.isEmpty) {
    b.writeln('No findings.');
  } else {
    b.writeln('| Severity | Check | Message |');
    b.writeln('| --- | --- | --- |');
    for (final finding in audit.findings) {
      b.writeln(
        '| `${finding.severity}` | `${finding.check}` | ${finding.message} |',
      );
    }
  }
  return b.toString();
}

String _summaryLine(_AuditResult audit) {
  final errors =
      audit.findings.where((finding) => finding.severity == 'error').length;
  final warnings =
      audit.findings.where((finding) => finding.severity == 'warning').length;
  return 'Scale shard audit ${errors == 0 ? 'pass' : 'fail'}: '
      'completed=${audit.summary['completed_shard_count']}/'
      '${audit.summary['shard_count']}, '
      'observed_cases=${audit.summary['observed_case_count']}/'
      '${audit.summary['expected_case_count']}, '
      'errors=$errors, warnings=$warnings';
}

_Finding _finding(
  String severity,
  String check,
  String message,
  JsonMap details,
) {
  return severity == 'error'
      ? _Finding.error(check, message, details)
      : _Finding.warning(check, message, details);
}

List<String> _modes(JsonMap metrics) {
  final modes = _list(metrics['modes']).map((item) => item.toString()).toList();
  if (modes.isNotEmpty) return modes;
  return _map(metrics['metrics_by_mode']).keys.toList()..sort();
}

List<String> _envList(String key) {
  return (Platform.environment[key] ?? '')
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

int? _intEnv(String key) {
  return int.tryParse(Platform.environment[key] ?? '');
}

bool _boolEnv(String key) {
  final value = Platform.environment[key]?.toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
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

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _AuditResult {
  const _AuditResult({
    required this.manifestPath,
    required this.findings,
    required this.summary,
    required this.shardResults,
  });

  final String manifestPath;
  final List<_Finding> findings;
  final JsonMap summary;
  final List<JsonMap> shardResults;

  JsonMap toJson() => {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'manifest_path': manifestPath,
        'status': findings.any((finding) => finding.severity == 'error')
            ? 'fail'
            : 'pass',
        'summary': summary,
        'findings': findings.map((finding) => finding.toJson()).toList(),
        'shards': shardResults,
      };
}

class _Finding {
  const _Finding._(this.severity, this.check, this.message, this.details);

  factory _Finding.error(String check, String message, JsonMap details) {
    return _Finding._('error', check, message, details);
  }

  factory _Finding.warning(String check, String message, JsonMap details) {
    return _Finding._('warning', check, message, details);
  }

  final String severity;
  final String check;
  final String message;
  final JsonMap details;

  JsonMap toJson() => {
        'severity': severity,
        'check': check,
        'message': message,
        if (details.isNotEmpty) 'details': details,
      };
}
