import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

const _expectedQueryFamilies = [
  'project_owner_current',
  'partner_owner_disambiguation',
  'relationship_responsibility_split',
  'report_preference',
  'location_routine',
  'role_mood_transition',
  'sensitive_boundary',
  'failure_recovery_alignment',
  'ocr_conflict_grounding',
  'owner_only_scope',
];

Future<void> main(List<String> args) async {
  final datasetPath = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_DATASET'] ??
          'evals/datasets/pr256_full_metric_small/cases.jsonl';
  final datasetFile = File(datasetPath);
  if (!await datasetFile.exists()) {
    stderr.writeln('Dataset does not exist: $datasetPath');
    exitCode = 66;
    return;
  }

  final profile = _profileForPath(datasetFile.path);
  final expectations = _Expectations.fromEnv(profile);
  final audit = await _auditDataset(datasetFile, expectations);

  final outDir = Platform.environment['MEMEX_EVAL_DATASET_AUDIT_OUT_DIR'];
  if (outDir != null && outDir.trim().isNotEmpty) {
    final dir = Directory(outDir);
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'dataset_audit.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(audit.toJson()),
      flush: true,
    );
    await File(
      p.join(dir.path, 'dataset_audit.md'),
    ).writeAsString(_renderMarkdown(audit), flush: true);
  }

  stdout.writeln(_oneLineSummary(audit));
  if (audit.findings.any((finding) => finding.severity == 'error')) {
    exitCode = 1;
  }
}

Future<_AuditResult> _auditDataset(
  File datasetFile,
  _Expectations expectations,
) async {
  final findings = <_Finding>[];
  final caseSummaries = <JsonMap>[];
  final queryFamilyCounts = <String, int>{};
  final roles = <String>{};
  final secondaryRoles = <String>{};
  final cities = <String>{};
  final travelCities = <String>{};
  final moodBefore = <String>{};
  final moodAfter = <String>{};
  final conflicts = <String>{};
  final scenarioFamilies = <String>{};
  final journeyStages = <String>{};
  final inputChannels = <String>{};
  final operationTypes = <String>{};
  final recordGaps = <int>[];
  var caseCount = 0;
  var totalRecords = 0;
  var totalAsks = 0;
  var totalRecalls = 0;
  var totalProjections = 0;
  var interleavedAsks = 0;
  var missingFamilyAsks = 0;

  for (final line in await datasetFile.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final evalCase = jsonDecode(trimmed) as JsonMap;
    caseCount += 1;
    final caseId = evalCase['case_id']?.toString() ?? 'case_$caseCount';
    final persona = _map(evalCase['persona']);
    _addIfPresent(roles, persona['role']);
    _addIfPresent(secondaryRoles, persona['secondary_role']);
    _addIfPresent(cities, persona['city']);
    _addIfPresent(travelCities, persona['travel_city']);
    _addIfPresent(moodBefore, persona['mood_before']);
    _addIfPresent(moodAfter, persona['mood_after']);
    _addIfPresent(conflicts, persona['conflict_topic']);

    final coverage = _map(evalCase['coverage']);
    scenarioFamilies.addAll(_strings(coverage['scenario_families']));
    journeyStages.addAll(_strings(coverage['journey_stages']));
    inputChannels.addAll(_strings(coverage['input_channels']));

    final operations = _list(evalCase['operations']).map(_map).toList();
    final recordCount = operations
        .where((operation) => operation['type']?.toString() == 'record')
        .length;
    final askOperations = <JsonMap>[];
    var recallCount = 0;
    var projectionCount = 0;
    for (final operation in operations) {
      final type = operation['type']?.toString();
      if (type != null && type.isNotEmpty) operationTypes.add(type);
      switch (type) {
        case 'super_agent_ask':
          askOperations.add(operation);
          break;
        case 'memory_recall':
          recallCount += 1;
          break;
        case 'para_projection':
          projectionCount += 1;
          break;
      }
    }

    var recordsSeen = 0;
    int? previousAskPosition;
    var caseInterleavedAsks = 0;
    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      final type = operation['type']?.toString();
      if (type == 'record') {
        recordsSeen += 1;
        continue;
      }
      if (type != 'super_agent_ask') continue;
      final family = _map(operation['metadata'])['query_family']?.toString();
      if (family == null || family.isEmpty) {
        missingFamilyAsks += 1;
        findings.add(
          _Finding.error(
            'missing_query_family',
            'Super Agent ask is missing metadata.query_family.',
            {'case_id': caseId, 'operation_id': operation['id']},
          ),
        );
      } else {
        queryFamilyCounts[family] = (queryFamilyCounts[family] ?? 0) + 1;
      }
      final followingRecords = recordCount - recordsSeen;
      if (recordsSeen > 0 && followingRecords > 0) {
        interleavedAsks += 1;
        caseInterleavedAsks += 1;
      } else {
        findings.add(
          _Finding.error(
            'ask_not_interleaved',
            'Super Agent ask is not between record operations.',
            {
              'case_id': caseId,
              'operation_id': operation['id'],
              'records_before': recordsSeen,
              'records_after': followingRecords,
            },
          ),
        );
      }
      recordGaps.add(
        previousAskPosition == null
            ? recordsSeen
            : recordsSeen - previousAskPosition,
      );
      previousAskPosition = recordsSeen;
    }

    totalRecords += recordCount;
    totalAsks += askOperations.length;
    totalRecalls += recallCount;
    totalProjections += projectionCount;

    _checkExpectedCount(
      findings,
      expectations.recordsPerCase,
      recordCount,
      'records_per_case',
      caseId,
    );
    _checkExpectedCount(
      findings,
      expectations.agentQueriesPerCase,
      askOperations.length,
      'agent_queries_per_case',
      caseId,
    );
    _checkExpectedCount(
      findings,
      expectations.memoryRecallsPerCase,
      recallCount,
      'memory_recalls_per_case',
      caseId,
    );
    _checkExpectedCount(
      findings,
      expectations.projectionsPerCase,
      projectionCount,
      'projections_per_case',
      caseId,
    );

    final declaredInterleavedCount = _intValue(
      coverage['interleaved_agent_query_count'],
    );
    if (declaredInterleavedCount > 0 &&
        declaredInterleavedCount != askOperations.length) {
      findings.add(
        _Finding.warning(
          'coverage_interleaved_count_mismatch',
          'coverage.interleaved_agent_query_count differs from ask count.',
          {
            'case_id': caseId,
            'declared': declaredInterleavedCount,
            'actual': askOperations.length,
          },
        ),
      );
    }

    caseSummaries.add({
      'case_id': caseId,
      'records': recordCount,
      'agent_queries': askOperations.length,
      'interleaved_agent_queries': caseInterleavedAsks,
      'memory_recalls': recallCount,
      'projections': projectionCount,
    });
  }

  _checkExpectedCount(
    findings,
    expectations.caseCount,
    caseCount,
    'case_count',
    'dataset',
  );
  _checkMinimumCount(
    findings,
    expectations.queryFamilyCount,
    queryFamilyCounts.length,
    'query_family_count',
  );
  _checkMinimumCount(
    findings,
    expectations.roleCount,
    roles.length,
    'role_diversity',
  );
  _checkMinimumCount(
    findings,
    expectations.cityCount,
    cities.length,
    'city_diversity',
  );
  _checkMinimumCount(
    findings,
    expectations.travelCityCount,
    travelCities.length,
    'travel_city_diversity',
  );
  _checkMinimumCount(
    findings,
    expectations.conflictCount,
    conflicts.length,
    'conflict_diversity',
  );

  final missingExpectedFamilies = _expectedQueryFamilies
      .where((family) => !queryFamilyCounts.containsKey(family))
      .toList();
  if (expectations.requireAllKnownQueryFamilies &&
      missingExpectedFamilies.isNotEmpty) {
    findings.add(
      _Finding.error(
        'missing_expected_query_families',
        'Dataset is missing expected query families.',
        {'missing': missingExpectedFamilies},
      ),
    );
  }

  return _AuditResult(
    datasetPath: datasetFile.path,
    expectations: expectations,
    findings: findings,
    caseSummaries: caseSummaries,
    summary: {
      'case_count': caseCount,
      'record_count': totalRecords,
      'agent_query_count': totalAsks,
      'memory_recall_count': totalRecalls,
      'projection_count': totalProjections,
      'interleaved_agent_query_count': interleavedAsks,
      'agent_query_interleaving_rate': _ratioOrZero(
        interleavedAsks,
        totalAsks,
      ),
      'agent_query_density_per_100_records':
          totalRecords == 0 ? 0.0 : _round3(totalAsks * 100 / totalRecords),
      'agent_query_records_per_ask':
          totalAsks == 0 ? 0.0 : _round3(totalRecords / totalAsks),
      'agent_query_record_gap_p95': _percentile(recordGaps, 0.95),
      'agent_query_record_gap_max': _maxInt(recordGaps),
      'missing_query_family_ask_count': missingFamilyAsks,
      'query_family_count': queryFamilyCounts.length,
      'query_family_counts': queryFamilyCounts,
      'missing_expected_query_families': missingExpectedFamilies,
      'role_count': roles.length,
      'secondary_role_count': secondaryRoles.length,
      'city_count': cities.length,
      'travel_city_count': travelCities.length,
      'mood_before_count': moodBefore.length,
      'mood_after_count': moodAfter.length,
      'conflict_count': conflicts.length,
      'scenario_family_count': scenarioFamilies.length,
      'journey_stage_count': journeyStages.length,
      'input_channel_count': inputChannels.length,
      'operation_types': operationTypes.toList()..sort(),
    },
  );
}

String _renderMarkdown(_AuditResult audit) {
  final b = StringBuffer();
  final summary = audit.summary;
  b.writeln('# PR256 Dataset Shape Audit');
  b.writeln('');
  b.writeln('| Item | Value |');
  b.writeln('| --- | ---: |');
  for (final key in [
    'case_count',
    'record_count',
    'agent_query_count',
    'interleaved_agent_query_count',
    'agent_query_interleaving_rate',
    'agent_query_density_per_100_records',
    'agent_query_records_per_ask',
    'agent_query_record_gap_p95',
    'query_family_count',
    'role_count',
    'city_count',
    'travel_city_count',
    'conflict_count',
  ]) {
    b.writeln('| `$key` | ${summary[key] ?? '-'} |');
  }
  b.writeln('');
  b.writeln('## Query Families');
  b.writeln('');
  b.writeln('| Family | Count |');
  b.writeln('| --- | ---: |');
  for (final entry in _sortedEntries(_map(summary['query_family_counts']))) {
    b.writeln('| `${entry.key}` | ${entry.value} |');
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

String _oneLineSummary(_AuditResult audit) {
  final errors =
      audit.findings.where((finding) => finding.severity == 'error').length;
  final warnings =
      audit.findings.where((finding) => finding.severity == 'warning').length;
  final summary = audit.summary;
  return 'Dataset audit ${errors == 0 ? 'pass' : 'fail'} for '
      '${audit.datasetPath}: cases=${summary['case_count']}, '
      'records=${summary['record_count']}, asks=${summary['agent_query_count']}, '
      'interleaved=${summary['agent_query_interleaving_rate']}, '
      'families=${summary['query_family_count']}, '
      'errors=$errors, warnings=$warnings';
}

void _checkExpectedCount(
  List<_Finding> findings,
  int? expected,
  int actual,
  String check,
  String caseId,
) {
  if (expected == null || actual == expected) return;
  findings.add(
    _Finding.error(
      check,
      'Unexpected count.',
      {'case_id': caseId, 'expected': expected, 'actual': actual},
    ),
  );
}

void _checkMinimumCount(
  List<_Finding> findings,
  int? minimum,
  int actual,
  String check,
) {
  if (minimum == null || actual >= minimum) return;
  findings.add(
    _Finding.error(
      check,
      'Observed count is below minimum.',
      {'expected_min': minimum, 'actual': actual},
    ),
  );
}

void _addIfPresent(Set<String> target, dynamic value) {
  final text = value?.toString();
  if (text != null && text.isNotEmpty) target.add(text);
}

_DatasetProfile _profileForPath(String path) {
  if (path.contains('large_p12_r600_q50')) {
    return const _DatasetProfile(
      caseCount: 12,
      recordsPerCase: 600,
      agentQueriesPerCase: 50,
      queryFamilyCount: 10,
      roleCount: 12,
      cityCount: 12,
      travelCityCount: 12,
      conflictCount: 6,
      requireAllKnownQueryFamilies: true,
    );
  }
  if (path.contains('pr256_full_metric_small')) {
    return const _DatasetProfile(
      caseCount: 3,
      recordsPerCase: 48,
      agentQueriesPerCase: 6,
      queryFamilyCount: 6,
      roleCount: 3,
      cityCount: 3,
      travelCityCount: 3,
      conflictCount: 3,
    );
  }
  return const _DatasetProfile();
}

List<MapEntry<String, dynamic>> _sortedEntries(JsonMap map) {
  return map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
}

double _ratioOrZero(int numerator, int denominator) {
  if (denominator <= 0) return 0;
  return _round3(numerator / denominator);
}

double _round3(num value) => (value * 1000).round() / 1000;

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = values.toList()..sort();
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index.clamp(0, sorted.length - 1).toInt()];
}

int _maxInt(List<int> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a > b ? a : b);
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

List<String> _strings(dynamic value) {
  return _list(value).map((item) => item.toString()).toList();
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _AuditResult {
  const _AuditResult({
    required this.datasetPath,
    required this.expectations,
    required this.findings,
    required this.caseSummaries,
    required this.summary,
  });

  final String datasetPath;
  final _Expectations expectations;
  final List<_Finding> findings;
  final List<JsonMap> caseSummaries;
  final JsonMap summary;

  JsonMap toJson() => {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'dataset_path': datasetPath,
        'status': findings.any((finding) => finding.severity == 'error')
            ? 'fail'
            : 'pass',
        'expectations': expectations.toJson(),
        'summary': summary,
        'findings': findings.map((finding) => finding.toJson()).toList(),
        'case_summaries': caseSummaries,
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

class _Expectations {
  const _Expectations({
    this.caseCount,
    this.recordsPerCase,
    this.agentQueriesPerCase,
    this.memoryRecallsPerCase,
    this.projectionsPerCase,
    this.queryFamilyCount,
    this.roleCount,
    this.cityCount,
    this.travelCityCount,
    this.conflictCount,
    this.requireAllKnownQueryFamilies = false,
  });

  factory _Expectations.fromEnv(_DatasetProfile profile) {
    return _Expectations(
      caseCount: _intEnv('MEMEX_EVAL_AUDIT_EXPECT_CASES') ?? profile.caseCount,
      recordsPerCase: _intEnv('MEMEX_EVAL_AUDIT_EXPECT_RECORDS_PER_CASE') ??
          profile.recordsPerCase,
      agentQueriesPerCase:
          _intEnv('MEMEX_EVAL_AUDIT_EXPECT_AGENT_QUERIES_PER_CASE') ??
              profile.agentQueriesPerCase,
      memoryRecallsPerCase:
          _intEnv('MEMEX_EVAL_AUDIT_EXPECT_MEMORY_RECALLS_PER_CASE') ?? 3,
      projectionsPerCase:
          _intEnv('MEMEX_EVAL_AUDIT_EXPECT_PROJECTIONS_PER_CASE') ?? 1,
      queryFamilyCount: _intEnv('MEMEX_EVAL_AUDIT_EXPECT_QUERY_FAMILY_COUNT') ??
          profile.queryFamilyCount,
      roleCount:
          _intEnv('MEMEX_EVAL_AUDIT_EXPECT_ROLE_COUNT') ?? profile.roleCount,
      cityCount:
          _intEnv('MEMEX_EVAL_AUDIT_EXPECT_CITY_COUNT') ?? profile.cityCount,
      travelCityCount: _intEnv('MEMEX_EVAL_AUDIT_EXPECT_TRAVEL_CITY_COUNT') ??
          profile.travelCityCount,
      conflictCount: _intEnv('MEMEX_EVAL_AUDIT_EXPECT_CONFLICT_COUNT') ??
          profile.conflictCount,
      requireAllKnownQueryFamilies:
          _boolEnv('MEMEX_EVAL_AUDIT_EXPECT_ALL_QUERY_FAMILIES') ||
              profile.requireAllKnownQueryFamilies,
    );
  }

  final int? caseCount;
  final int? recordsPerCase;
  final int? agentQueriesPerCase;
  final int? memoryRecallsPerCase;
  final int? projectionsPerCase;
  final int? queryFamilyCount;
  final int? roleCount;
  final int? cityCount;
  final int? travelCityCount;
  final int? conflictCount;
  final bool requireAllKnownQueryFamilies;

  JsonMap toJson() => {
        if (caseCount != null) 'case_count': caseCount,
        if (recordsPerCase != null) 'records_per_case': recordsPerCase,
        if (agentQueriesPerCase != null)
          'agent_queries_per_case': agentQueriesPerCase,
        if (memoryRecallsPerCase != null)
          'memory_recalls_per_case': memoryRecallsPerCase,
        if (projectionsPerCase != null)
          'projections_per_case': projectionsPerCase,
        if (queryFamilyCount != null) 'query_family_count': queryFamilyCount,
        if (roleCount != null) 'role_count': roleCount,
        if (cityCount != null) 'city_count': cityCount,
        if (travelCityCount != null) 'travel_city_count': travelCityCount,
        if (conflictCount != null) 'conflict_count': conflictCount,
        'require_all_known_query_families': requireAllKnownQueryFamilies,
      };
}

class _DatasetProfile {
  const _DatasetProfile({
    this.caseCount,
    this.recordsPerCase,
    this.agentQueriesPerCase,
    this.queryFamilyCount,
    this.roleCount,
    this.cityCount,
    this.travelCityCount,
    this.conflictCount,
    this.requireAllKnownQueryFamilies = false,
  });

  final int? caseCount;
  final int? recordsPerCase;
  final int? agentQueriesPerCase;
  final int? queryFamilyCount;
  final int? roleCount;
  final int? cityCount;
  final int? travelCityCount;
  final int? conflictCount;
  final bool requireAllKnownQueryFamilies;
}

int? _intEnv(String key) {
  return int.tryParse(Platform.environment[key] ?? '');
}

bool _boolEnv(String key) {
  final value = Platform.environment[key]?.toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}
