import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

const _requiredTopLevelArtifacts = [
  'metrics.json',
  'report.md',
  'failures.jsonl',
  'observations.jsonl',
  'judge_tasks.jsonl',
  'gate.json',
  'case_debug_index.md',
];

const _emptyAllowedTopLevelArtifacts = {
  'failures.jsonl',
};

const _requiredModeMetrics = [
  'record_count',
  'completed_card_rate',
  'cards_with_insight_rate',
  'memory_expected_hit_rate',
  'memory_must_not_write_precision',
  'memory_recall_hit_rate',
  'super_agent_ask_count',
  'super_agent_answer_success_rate',
  'super_agent_answer_hit_rate',
  'super_agent_boundary_precision',
  'retrieval_hit_at_1',
  'retrieval_hit_at_3',
  'retrieval_hit_at_5',
  'retrieval_hit_at_10',
  'retrieval_positive_source_total',
  'fts_positive_coverage_rate',
  'vector_positive_coverage_rate',
  'vector_only_positive_hit_rate',
  'hybrid_positive_coverage_rate',
  'vector_incremental_recall_lift_at_10',
  'vector_supported_query_rate',
  'vector_only_supported_query_rate',
  'retrieval_source_query_count',
  'super_agent_provider_attempt_count',
  'super_agent_provider_retry_count',
  'super_agent_provider_retry_rate',
  'super_agent_query_family_metrics',
  'agent_query_count',
  'interleaved_agent_query_count',
  'agent_query_interleaving_rate',
  'agent_query_density_per_100_records',
  'agent_query_records_per_ask',
  'agent_query_family_coverage',
  'agent_query_min_per_case',
  'tool_selection_accuracy',
  'tool_args_accuracy',
  'tool_call_minimality',
  'task_settlement_rate',
  'failed_task_count',
  'provider_infra_task_error_count',
  'provider_rate_limit_task_error_count',
  'provider_quota_task_error_count',
  'provider_network_task_error_count',
  'provider_server_task_error_count',
  'provider_infra_task_error_rate',
  'provider_infra_affected_operation_count',
  'provider_infra_affected_operation_rate',
  'task_not_settled_count',
  'p95_record_elapsed_ms',
  'tokens_per_input',
  'scenario_family_coverage',
  'agent_chain_coverage',
  'journey_stage_coverage',
  'operation_type_coverage',
];

const _secretPatterns = [
  r'tp-[A-Za-z0-9]{12,}',
  r'sk-or-' r'v1-[A-Za-z0-9]{12,}',
  r'Bearer\s+[A-Za-z0-9._-]{20,}',
];

Future<void> main(List<String> args) async {
  final runDir = Directory(
    args.isNotEmpty
        ? args.first
        : Platform.environment['MEMEX_EVAL_AUDIT_RUN_DIR'] ??
            Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
            '',
  );
  if (runDir.path.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/audit_memory_primary_iteration_artifacts.dart <run_dir>',
    );
    exitCode = 64;
    return;
  }

  final findings = <JsonMap>[];
  void addFinding(
    String severity,
    String check,
    String message, [
    JsonMap details = const {},
  ]) {
    findings.add({
      'severity': severity,
      'check': check,
      'message': message,
      if (details.isNotEmpty) 'details': details,
    });
  }

  if (!await runDir.exists()) {
    addFinding('error', 'run_dir_exists', 'Run directory does not exist.', {
      'run_dir': runDir.path,
    });
    await _writeAudit(runDir, findings, const {});
    exitCode = 1;
    return;
  }

  for (final artifact in _requiredTopLevelArtifacts) {
    final file = File(p.join(runDir.path, artifact));
    if (!await file.exists()) {
      addFinding('error', 'required_artifact', 'Missing required artifact.', {
        'path': artifact,
      });
    } else if (await file.length() == 0 &&
        !_emptyAllowedTopLevelArtifacts.contains(artifact)) {
      addFinding('error', 'required_artifact', 'Required artifact is empty.', {
        'path': artifact,
      });
    }
  }

  final metricsFile = File(p.join(runDir.path, 'metrics.json'));
  JsonMap metrics = const {};
  if (await metricsFile.exists()) {
    try {
      metrics = jsonDecode(await metricsFile.readAsString()) as JsonMap;
    } catch (error) {
      addFinding('error', 'metrics_parse', 'metrics.json is not valid JSON.', {
        'error': error.toString(),
      });
    }
  }

  final modes = _modes(metrics);
  final expectedModes = _envList('MEMEX_EVAL_AUDIT_EXPECT_MODES');
  if (expectedModes.isNotEmpty) {
    final missing =
        expectedModes.where((mode) => !modes.contains(mode)).toList();
    if (missing.isNotEmpty) {
      addFinding('error', 'modes', 'Expected modes are missing.', {
        'expected': expectedModes,
        'actual': modes,
        'missing': missing,
      });
    }
  }

  final metricsByMode = _map(metrics['metrics_by_mode']);
  for (final mode in modes) {
    final modeMetrics = _map(metricsByMode[mode]);
    final missingFields = _requiredModeMetrics
        .where((field) => !modeMetrics.containsKey(field))
        .toList();
    if (missingFields.isNotEmpty) {
      addFinding('error', 'mode_metrics', 'Mode is missing required metrics.', {
        'mode': mode,
        'missing_fields': missingFields,
      });
    }
    final expectedCaseCount = _intEnv('MEMEX_EVAL_AUDIT_EXPECT_CASE_COUNT');
    if (expectedCaseCount != null &&
        _intValue(modeMetrics['case_count']) != expectedCaseCount) {
      addFinding('error', 'case_count', 'Unexpected case count.', {
        'mode': mode,
        'actual': _intValue(modeMetrics['case_count']),
        'expected': expectedCaseCount,
      });
    }
    final providerInfraErrors =
        _intValue(modeMetrics['provider_infra_task_error_count']);
    if (providerInfraErrors > 0) {
      addFinding(
        _boolEnv('MEMEX_EVAL_AUDIT_EXPECT_GATE_PASS') ? 'error' : 'warning',
        'provider_infra_errors',
        'Run has record-chain provider infrastructure errors; treat effect metrics as provider-contaminated unless rerun.',
        {
          'mode': mode,
          'provider_infra_task_error_count': providerInfraErrors,
          'provider_rate_limit_task_error_count':
              _intValue(modeMetrics['provider_rate_limit_task_error_count']),
          'provider_quota_task_error_count':
              _intValue(modeMetrics['provider_quota_task_error_count']),
          'provider_network_task_error_count':
              _intValue(modeMetrics['provider_network_task_error_count']),
          'provider_server_task_error_count':
              _intValue(modeMetrics['provider_server_task_error_count']),
          'provider_infra_affected_operation_count': _intValue(
            modeMetrics['provider_infra_affected_operation_count'],
          ),
        },
      );
    }
  }

  final caseLogFindings = await _auditCaseLogs(
    runDir: runDir,
    modes: modes,
    metricsByMode: metricsByMode,
  );
  findings.addAll(caseLogFindings);

  final failureCount =
      await _jsonlCount(File(p.join(runDir.path, 'failures.jsonl')));
  final badcasesMd = File(p.join(runDir.path, 'badcases.md'));
  final badcasesJsonl = File(p.join(runDir.path, 'badcases.jsonl'));
  if (failureCount > 0 &&
      (!await badcasesMd.exists() || !await badcasesJsonl.exists())) {
    addFinding(
      _boolEnv('MEMEX_EVAL_AUDIT_EXPECT_BADCASES') ? 'error' : 'warning',
      'badcase_artifacts',
      'Run has failures but badcase ledger artifacts are missing.',
      {
        'failure_count': failureCount,
        'expected': ['badcases.md', 'badcases.jsonl'],
      },
    );
  }

  if (_boolEnv('MEMEX_EVAL_AUDIT_EXPECT_LLM')) {
    final llmEnabled = metrics['llm_enabled'];
    final values = _list(metrics['llm_enabled_values']);
    final enabled = llmEnabled == true || values.contains(true);
    if (!enabled) {
      addFinding('error', 'llm_enabled',
          'Expected real LLM run, but metrics do not prove it.');
    }
  }

  if (_boolEnv('MEMEX_EVAL_AUDIT_EXPECT_GATE_PASS')) {
    final gate = _map(metrics['gate']);
    if (gate['status'] != 'pass') {
      addFinding('error', 'gate', 'Expected gate pass.', {
        'actual': gate['status'] ?? 'missing',
      });
    }
  }

  final judgeTaskCount = await _jsonlCount(
    File(p.join(runDir.path, 'judge_tasks.jsonl')),
  );
  final expectedJudgeTaskCount = _intValue(metrics['judge_task_count']);
  if (expectedJudgeTaskCount > 0 && judgeTaskCount != expectedJudgeTaskCount) {
    addFinding('error', 'judge_tasks', 'judge_tasks.jsonl count mismatch.', {
      'actual': judgeTaskCount,
      'expected': expectedJudgeTaskCount,
    });
  }
  if (_boolEnv('MEMEX_EVAL_AUDIT_EXPECT_PAIRWISE') &&
      _intValue(metrics['pairwise_judge_task_count']) <= 0) {
    addFinding('error', 'pairwise_judge', 'Expected pairwise judge tasks.');
  }

  if (_boolEnv('MEMEX_EVAL_AUDIT_EXPECT_JUDGE')) {
    final judgeMetricsFile =
        File(p.join(runDir.path, 'judge', 'judge_metrics.json'));
    final judgeResultsFile =
        File(p.join(runDir.path, 'judge', 'judge_results.jsonl'));
    if (!await judgeMetricsFile.exists()) {
      addFinding(
          'error', 'judge_artifacts', 'Missing judge/judge_metrics.json.');
    }
    if (!await judgeResultsFile.exists()) {
      addFinding(
          'error', 'judge_artifacts', 'Missing judge/judge_results.jsonl.');
    }
  }

  final secretFindings = await _scanForSecrets(runDir);
  findings.addAll(secretFindings);

  final summary = {
    'run_dir': runDir.path,
    'status': findings.any((finding) => finding['severity'] == 'error')
        ? 'fail'
        : 'pass',
    'modes': modes,
    'finding_count': findings.length,
    'error_count':
        findings.where((finding) => finding['severity'] == 'error').length,
    'warning_count':
        findings.where((finding) => finding['severity'] == 'warning').length,
  };
  await _writeAudit(runDir, findings, summary);
  stdout.writeln(
    'Artifact audit ${summary['status']} for ${runDir.path} '
    '(${summary['error_count']} errors, ${summary['warning_count']} warnings).',
  );
  if (summary['status'] != 'pass') exitCode = 1;
}

Future<List<JsonMap>> _auditCaseLogs({
  required Directory runDir,
  required List<String> modes,
  required JsonMap metricsByMode,
}) async {
  final findings = <JsonMap>[];
  final caseLogRoot = Directory(p.join(runDir.path, 'case_logs'));
  if (!await caseLogRoot.exists()) {
    return [
      {
        'severity': 'error',
        'check': 'case_logs',
        'message': 'Missing case_logs directory.',
      },
    ];
  }

  for (final mode in modes) {
    final modeDir = Directory(p.join(caseLogRoot.path, mode));
    final expected = _intValue(_map(metricsByMode[mode])['case_count']);
    if (!await modeDir.exists()) {
      findings.add({
        'severity': 'error',
        'check': 'case_logs',
        'message': 'Missing case log mode directory.',
        'details': {'mode': mode},
      });
      continue;
    }
    final files = await modeDir
        .list(recursive: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (expected > 0 && files.length < expected) {
      findings.add({
        'severity': 'error',
        'check': 'case_logs',
        'message': 'Case log count is lower than case_count.',
        'details': {'mode': mode, 'actual': files.length, 'expected': expected},
      });
    }
  }
  return findings;
}

Future<List<JsonMap>> _scanForSecrets(Directory runDir) async {
  final findings = <JsonMap>[];
  final patterns = _secretPatterns.map(RegExp.new).toList();
  await for (final entity in runDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: runDir.path);
    if (_isLikelyBinary(entity.path)) continue;
    final length = await entity.length();
    if (length > 8 * 1024 * 1024) continue;
    final content =
        utf8.decode(await entity.readAsBytes(), allowMalformed: true);
    for (final pattern in patterns) {
      if (pattern.hasMatch(content)) {
        findings.add({
          'severity': 'error',
          'check': 'secret_redaction',
          'message': 'Potential secret material found in artifact.',
          'details': {'path': relative, 'pattern': pattern.pattern},
        });
      }
    }
  }
  return findings;
}

Future<int> _jsonlCount(File file) async {
  if (!await file.exists()) return 0;
  var count = 0;
  for (final line in await file.readAsLines()) {
    if (line.trim().isNotEmpty) count += 1;
  }
  return count;
}

Future<void> _writeAudit(
  Directory runDir,
  List<JsonMap> findings,
  JsonMap summary,
) async {
  await runDir.create(recursive: true);
  final effectiveSummary = summary.isEmpty
      ? {
          'run_dir': runDir.path,
          'status': 'fail',
          'finding_count': findings.length,
          'error_count': findings
              .where((finding) => finding['severity'] == 'error')
              .length,
        }
      : summary;
  final payload = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'summary': effectiveSummary,
    'findings': findings,
  };
  await File(p.join(runDir.path, 'artifact_audit.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
  await File(p.join(runDir.path, 'artifact_audit.md')).writeAsString(
    _renderAuditMarkdown(payload),
    flush: true,
  );
}

String _renderAuditMarkdown(JsonMap payload) {
  final summary = _map(payload['summary']);
  final findings = _list(payload['findings']).map(_map).toList();
  final b = StringBuffer();
  b.writeln('# Memory Primary Artifact Audit');
  b.writeln('');
  b.writeln('- Generated at: `${payload['generated_at']}`');
  b.writeln('- Run dir: `${summary['run_dir'] ?? '-'}`');
  b.writeln('- Status: `${summary['status'] ?? 'fail'}`');
  b.writeln('- Errors: `${summary['error_count'] ?? 0}`');
  b.writeln('- Warnings: `${summary['warning_count'] ?? 0}`');
  b.writeln('');
  b.writeln('## Findings');
  b.writeln('');
  if (findings.isEmpty) {
    b.writeln('No findings.');
  } else {
    b.writeln('| Severity | Check | Message | Details |');
    b.writeln('| --- | --- | --- | --- |');
    for (final finding in findings) {
      b.writeln(
        '| `${finding['severity']}` | `${finding['check']}` | '
        '${_escapeTable(finding['message']?.toString() ?? '')} | '
        '`${jsonEncode(finding['details'] ?? const {})}` |',
      );
    }
  }
  return b.toString();
}

List<String> _modes(JsonMap metrics) {
  final explicit =
      _list(metrics['modes']).map((item) => item.toString()).toList();
  if (explicit.isNotEmpty) return explicit;
  return _map(metrics['metrics_by_mode']).keys.toList()..sort();
}

JsonMap _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

List<String> _envList(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int? _intEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
}

bool _boolEnv(String key) {
  final raw = Platform.environment[key]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes';
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _isLikelyBinary(String path) {
  final extension = p.extension(path).toLowerCase();
  return {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.pdf',
    '.zip',
    '.gz',
  }.contains(extension);
}

String _escapeTable(String value) => value.replaceAll('|', r'\|');
