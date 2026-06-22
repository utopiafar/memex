import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

const _coreMetricRows = [
  _MetricRow('completed_card_rate', 'Card completed'),
  _MetricRow('cards_with_insight_rate', 'Card insight'),
  _MetricRow('memory_expected_hit_rate', 'Memory must-write hit'),
  _MetricRow('memory_must_not_write_precision', 'Memory must-not precision'),
  _MetricRow('memory_duplicate_rate', 'Memory duplicate'),
  _MetricRow('related_fact_hit_rate', 'Related fact hit'),
  _MetricRow('memory_recall_hit_rate', 'Memory recall hit'),
  _MetricRow('super_agent_answer_hit_rate', 'Agent answer hit'),
  _MetricRow('super_agent_boundary_precision', 'Agent boundary precision'),
  _MetricRow('super_agent_read_only_compliance', 'Agent read-only'),
  _MetricRow('agent_route_accuracy', 'Agent route accuracy'),
  _MetricRow('task_settlement_rate', 'Task settlement'),
  _MetricRow('failed_task_count', 'Failed task count'),
  _MetricRow('provider_infra_task_error_count', 'Provider infra task errors'),
  _MetricRow(
    'provider_infra_affected_operation_rate',
    'Provider-contaminated op rate',
  ),
  _MetricRow('task_not_settled_count', 'Not-settled task count'),
  _MetricRow('p95_record_elapsed_ms', 'P95 record latency ms'),
  _MetricRow('tokens_per_input', 'Tokens/input'),
];

const _retrievalMetricRows = [
  _MetricRow('retrieval_hit_at_1', 'Hit@1'),
  _MetricRow('retrieval_hit_at_3', 'Hit@3'),
  _MetricRow('retrieval_hit_at_5', 'Hit@5'),
  _MetricRow('retrieval_hit_at_10', 'Hit@10'),
  _MetricRow('retrieval_positive_source_total', 'Positive probes'),
  _MetricRow('fts_positive_coverage_rate', 'FTS positive coverage'),
  _MetricRow('vector_positive_coverage_rate', 'Vector positive coverage'),
  _MetricRow('vector_only_positive_hit_rate', 'Vector-only positive hit'),
  _MetricRow('fts_only_positive_hit_rate', 'FTS-only positive hit'),
  _MetricRow('hybrid_positive_coverage_rate', 'Hybrid positive coverage'),
  _MetricRow('vector_incremental_recall_lift_at_10', 'Vector lift@10'),
  _MetricRow('vector_supported_query_rate', 'Vector-supported query'),
  _MetricRow('vector_only_supported_query_rate', 'Vector-only query'),
];

const _agentQueryRows = [
  _MetricRow('agent_query_count', 'Dataset ask count'),
  _MetricRow('interleaved_agent_query_count', 'Interleaved ask count'),
  _MetricRow('agent_query_interleaving_rate', 'Interleaving rate'),
  _MetricRow('agent_query_density_per_100_records', 'Asks / 100 records'),
  _MetricRow('agent_query_records_per_ask', 'Records / ask'),
  _MetricRow('agent_query_family_coverage', 'Query family coverage'),
  _MetricRow('agent_query_min_per_case', 'Min asks / case'),
  _MetricRow('agent_query_record_gap_p95', 'P95 record gap'),
  _MetricRow('super_agent_ask_count', 'Agent ask count'),
  _MetricRow('super_agent_answer_success_rate', 'Answer success'),
  _MetricRow('super_agent_answer_hit_rate', 'Answer hit'),
  _MetricRow('super_agent_boundary_precision', 'Boundary precision'),
  _MetricRow('super_agent_read_only_compliance', 'Read-only compliance'),
  _MetricRow('tool_selection_accuracy', 'Tool selection'),
  _MetricRow('tool_args_accuracy', 'Tool args'),
  _MetricRow('tool_call_minimality', 'Tool minimality'),
  _MetricRow('super_agent_provider_attempt_count', 'Provider attempts'),
  _MetricRow('super_agent_provider_retry_count', 'Provider retries'),
  _MetricRow('super_agent_provider_retry_rate', 'Provider retry rate'),
];

Future<void> main(List<String> args) async {
  final runDirPath = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_REPORT_RUN_DIR'] ??
          Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
          '';
  if (runDirPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/render_memory_primary_iteration_report.dart '
      '<run_dir> [output_path]',
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

  final outputPath = args.length > 1
      ? args[1]
      : Platform.environment['MEMEX_EVAL_REPORT_OUTPUT'] ??
          p.join(
            Directory.current.path,
            'evals',
            'reports',
            '${_dateStamp()}-memory-primary-iteration-${p.basename(runDir.path)}.zh.md',
          );
  final output = File(outputPath);
  await output.parent.create(recursive: true);

  final report = await _buildReport(runDir);
  await output.writeAsString(report, flush: true);
  stdout.writeln('Wrote ${output.path}');
}

Future<String> _buildReport(Directory runDir) async {
  final metrics = await _readJson(File(p.join(runDir.path, 'metrics.json')));
  final gate = await _readJson(File(p.join(runDir.path, 'gate.json')));
  final audit =
      await _readJson(File(p.join(runDir.path, 'artifact_audit.json')));
  final judgeMetrics = await _readJson(
    File(p.join(runDir.path, 'judge', 'judge_metrics.json')),
  );
  final failures =
      await _readJsonl(File(p.join(runDir.path, 'failures.jsonl')));

  final modes = _modes(metrics);
  final metricsByMode = _map(metrics['metrics_by_mode']);
  final comparison = _map(metrics['comparison']);
  final memory = _map(metricsByMode['memory_primary']);
  final legacy = _map(metricsByMode['legacy_pkm']);
  final auditSummary = _map(audit['summary']);
  final judgeByMetric = _map(judgeMetrics['metrics']);

  final b = StringBuffer();
  b.writeln('# Memory Primary 新一轮评估报告');
  b.writeln('');
  b.writeln('生成时间：${DateTime.now().toUtc().toIso8601String()}');
  b.writeln('');
  b.writeln('## 摘要');
  b.writeln('');
  b.writeln('| 项 | 值 |');
  b.writeln('| --- | --- |');
  b.writeln('| Run dir | `${runDir.path}` |');
  b.writeln('| Dataset | ${_inlineList(_list(metrics['dataset_paths']))} |');
  b.writeln('| Modes | `${modes.join(', ')}` |');
  b.writeln('| LLM enabled | `${_llmEnabled(metrics)}` |');
  b.writeln(
    '| Gate | `${gate['status'] ?? _map(metrics['gate'])['status'] ?? 'missing'}` |',
  );
  b.writeln('| Artifact audit | `${auditSummary['status'] ?? 'missing'}` |');
  b.writeln('| Judge tasks | `${metrics['judge_task_count'] ?? '-'}` |');
  b.writeln(
    '| Pairwise judge tasks | `${metrics['pairwise_judge_task_count'] ?? '-'}` |',
  );
  b.writeln('| Failures | `${failures.length}` |');
  b.writeln('');
  b.writeln(
    '说明：老链路保持 frozen baseline；新链路可迭代。召回策略采用 FTS + dense embedding 候选和 RRF 融合，向量贡献通过覆盖型指标记录，不依赖 case-by-case 启发式打分。',
  );
  b.writeln('');

  _writeDesignSummary(b, modes, metricsByMode);
  _writeCoreMetricTable(b, modes, metricsByMode, comparison);
  _writeAgentQueryTable(b, modes, metricsByMode, judgeByMetric);
  _writeAgentQueryFamilyTable(b, modes, metricsByMode);
  _writeRetrievalTable(b, memory);
  _writeJudgeSection(b, judgeMetrics, judgeByMetric);
  _writeGateSection(
    b,
    _map(metrics['gate']).isNotEmpty ? _map(metrics['gate']) : gate,
  );
  _writeAuditSection(b, audit);
  _writeFailureSection(b, modes, failures);
  _writeEvidenceSection(b, runDir);
  _writeNextStepSection(b, gate, auditSummary, memory, legacy);

  return b.toString();
}

void _writeDesignSummary(
  StringBuffer b,
  List<String> modes,
  JsonMap metricsByMode,
) {
  b.writeln('## 样本与旅程');
  b.writeln('');
  b.writeln(
    '| Mode | Cases | Records | Agent asks | Recall probes | Projection | Operation coverage |',
  );
  b.writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final mode in modes) {
    final m = _map(metricsByMode[mode]);
    b.writeln(
      '| `$mode` | ${_value(m['case_count'])} | ${_value(m['record_count'])} | '
      '${_value(m['super_agent_ask_count'])} | ${_value(m['memory_recall_query_count'])} | '
      '${_value(m['projection_count'])} | ${_fmt(m['operation_type_coverage'])} |',
    );
  }
  b.writeln('');
}

void _writeCoreMetricTable(
  StringBuffer b,
  List<String> modes,
  JsonMap metricsByMode,
  JsonMap comparison,
) {
  b.writeln('## 核心指标');
  b.writeln('');
  b.writeln('| 指标 | ${modes.join(' | ')} | Delta |');
  b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} | ---: |');
  for (final row in _coreMetricRows) {
    final delta = comparison['${row.key}_delta'];
    b.writeln(
      '| ${row.label} | ${modes.map((mode) => _fmt(_map(metricsByMode[mode])[row.key])).join(' | ')} | ${_fmt(delta)} |',
    );
  }
  b.writeln('');
}

void _writeAgentQueryTable(
  StringBuffer b,
  List<String> modes,
  JsonMap metricsByMode,
  JsonMap judgeByMetric,
) {
  b.writeln('## Agent 间歇问答');
  b.writeln('');
  b.writeln('| 指标 | ${modes.join(' | ')} |');
  b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} |');
  for (final row in _agentQueryRows) {
    b.writeln(
      '| ${row.label} | ${modes.map((mode) => _fmt(_map(metricsByMode[mode])[row.key])).join(' | ')} |',
    );
  }
  final pairwise = _map(judgeByMetric['pairwise_answer_quality']);
  if (pairwise.isNotEmpty) {
    b.writeln('| Pairwise mode wins | ${_modeWins(modes, pairwise)} |');
    b.writeln(
      '| Pairwise match levels | ${modes.isEmpty ? '-' : _span(modes.length, _compactMap(_map(pairwise['match_level_counts'])))} |',
    );
  }
  b.writeln('');
}

void _writeAgentQueryFamilyTable(
  StringBuffer b,
  List<String> modes,
  JsonMap metricsByMode,
) {
  final families = <String>{};
  for (final mode in modes) {
    families.addAll(
      _map(_map(metricsByMode[mode])['super_agent_query_family_metrics']).keys,
    );
  }
  if (families.isEmpty) return;

  b.writeln('## Agent Query Family 明细');
  b.writeln('');
  b.writeln('| Query family | ${modes.join(' | ')} |');
  b.writeln('| --- | ${modes.map((_) => '---').join(' | ')} |');
  for (final family in families.toList()..sort()) {
    b.writeln(
      '| `$family` | ${modes.map((mode) {
        final familyMetrics = _map(
          _map(_map(metricsByMode[mode])['super_agent_query_family_metrics'])[
              family],
        );
        return _familyMetricCell(familyMetrics);
      }).join(' | ')} |',
    );
  }
  b.writeln('');
}

void _writeRetrievalTable(StringBuffer b, JsonMap memory) {
  b.writeln('## 召回与向量收益');
  b.writeln('');
  b.writeln('| 指标 | Memory Primary |');
  b.writeln('| --- | ---: |');
  for (final row in _retrievalMetricRows) {
    b.writeln('| ${row.label} | ${_fmt(memory[row.key])} |');
  }
  b.writeln(
    '| Positive source breakdown | ${_compactMap(_map(memory['retrieval_positive_source_breakdown']))} |',
  );
  b.writeln('');
}

void _writeJudgeSection(
  StringBuffer b,
  JsonMap judgeMetrics,
  JsonMap judgeByMetric,
) {
  b.writeln('## LLM-as-Judge');
  b.writeln('');
  if (judgeMetrics.isEmpty) {
    b.writeln(
        '本 run 尚未发现 `judge/judge_metrics.json`，真实 small/scale 收口时需要补跑 judge。');
    b.writeln('');
    return;
  }
  b.writeln('| 项 | 值 |');
  b.writeln('| --- | --- |');
  b.writeln('| Model | `${judgeMetrics['model'] ?? '-'}` |');
  b.writeln('| Task count | `${judgeMetrics['task_count'] ?? '-'}` |');
  b.writeln('| Provider count | `${judgeMetrics['provider_count'] ?? '-'}` |');
  b.writeln(
    '| Disabled providers | `${judgeMetrics['provider_disabled_count'] ?? '-'}` |',
  );
  b.writeln('| Concurrency | `${judgeMetrics['concurrency'] ?? '-'}` |');
  b.writeln('');
  b.writeln('| Metric | Total | Pass rate | Avg score | Winner/match detail |');
  b.writeln('| --- | ---: | ---: | ---: | --- |');
  for (final entry in judgeByMetric.entries) {
    final aggregate = _map(entry.value);
    final detailParts = [
      if (_map(aggregate['mode_win_counts']).isNotEmpty)
        'wins=${_compactMap(_map(aggregate['mode_win_counts']))}',
      if (_map(aggregate['match_level_counts']).isNotEmpty)
        'match=${_compactMap(_map(aggregate['match_level_counts']))}',
    ];
    b.writeln(
      '| `${entry.key}` | ${_value(aggregate['total'])} | ${_fmt(aggregate['pass_rate'])} | ${_fmt(aggregate['average_score'])} | ${detailParts.isEmpty ? '-' : detailParts.join('; ')} |',
    );
  }
  b.writeln('');
}

void _writeGateSection(StringBuffer b, JsonMap gate) {
  b.writeln('## Gate');
  b.writeln('');
  if (gate.isEmpty) {
    b.writeln('未找到 gate artifact。');
    b.writeln('');
    return;
  }
  b.writeln('| Rule | Actual | Required | Status |');
  b.writeln('| --- | ---: | ---: | --- |');
  for (final rule in _list(gate['rules']).map(_map)) {
    final required = rule['min'] ?? rule['max'] ?? '-';
    b.writeln(
      '| `${rule['name']}` | ${_fmt(rule['actual'])} | ${_fmt(required)} | ${rule['pass'] == true ? 'pass' : 'fail'} |',
    );
  }
  final failed = _list(gate['failed_rules']);
  if (failed.isNotEmpty) {
    b.writeln('');
    b.writeln('Failed rules: ${_inlineList(failed)}');
  }
  b.writeln('');
}

void _writeAuditSection(StringBuffer b, JsonMap audit) {
  b.writeln('## Artifact Audit');
  b.writeln('');
  if (audit.isEmpty) {
    b.writeln('未找到 `artifact_audit.json`。真实证据收口需要补跑 audit。');
    b.writeln('');
    return;
  }
  final summary = _map(audit['summary']);
  b.writeln('| 项 | 值 |');
  b.writeln('| --- | --- |');
  b.writeln('| Status | `${summary['status'] ?? '-'}` |');
  b.writeln('| Findings | `${summary['finding_count'] ?? 0}` |');
  b.writeln('| Errors | `${summary['error_count'] ?? 0}` |');
  b.writeln('| Warnings | `${summary['warning_count'] ?? 0}` |');
  b.writeln('');
  final findings = _list(audit['findings']).map(_map).toList(growable: false);
  if (findings.isNotEmpty) {
    b.writeln('| Severity | Check | Message |');
    b.writeln('| --- | --- | --- |');
    for (final finding in findings.take(12)) {
      b.writeln(
        '| `${finding['severity'] ?? '-'}` | `${finding['check'] ?? '-'}` | ${_escape(finding['message'] ?? '-')} |',
      );
    }
    b.writeln('');
  }
}

void _writeFailureSection(
  StringBuffer b,
  List<String> modes,
  List<JsonMap> failures,
) {
  b.writeln('## Badcase 概览');
  b.writeln('');
  if (failures.isEmpty) {
    b.writeln('当前 `failures.jsonl` 为空。');
    b.writeln('');
    return;
  }
  final categories = <String>{};
  for (final failure in failures) {
    categories.add(failure['category']?.toString() ?? 'unknown');
  }
  final sorted = categories.toList()..sort();
  b.writeln('| Category | ${modes.join(' | ')} | Total |');
  b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} | ---: |');
  for (final category in sorted) {
    final total = failures
        .where(
          (failure) =>
              (failure['category']?.toString() ?? 'unknown') == category,
        )
        .length;
    final modeCounts = modes.map((mode) {
      return failures
          .where(
            (failure) =>
                failure['mode'] == mode &&
                (failure['category']?.toString() ?? 'unknown') == category,
          )
          .length;
    }).join(' | ');
    b.writeln('| `$category` | $modeCounts | $total |');
  }
  b.writeln('');
}

void _writeEvidenceSection(StringBuffer b, Directory runDir) {
  b.writeln('## Artifact 索引');
  b.writeln('');
  for (final artifact in [
    'metrics.json',
    'gate.json',
    'report.md',
    'failures.jsonl',
    'observations.jsonl',
    'judge_tasks.jsonl',
    'judge/judge_metrics.json',
    'judge/judge_results.jsonl',
    'badcases.md',
    'badcases.jsonl',
    'artifact_audit.json',
    'artifact_audit.md',
    'case_debug_index.md',
  ]) {
    final file = File(p.join(runDir.path, artifact));
    b.writeln('- `$artifact`: ${file.existsSync() ? 'present' : 'missing'}');
  }
  b.writeln('');
}

void _writeNextStepSection(
  StringBuffer b,
  JsonMap gate,
  JsonMap auditSummary,
  JsonMap memory,
  JsonMap legacy,
) {
  b.writeln('## 当前判断');
  b.writeln('');
  final gatePass = gate['status'] == 'pass';
  final auditPass = auditSummary['status'] == 'pass';
  if (gatePass && auditPass) {
    b.writeln('- Gate 与 artifact audit 均通过，可以把本 run 作为本轮上线证据候选。');
  } else {
    b.writeln('- 本 run 还不能作为最终上线证据，需要先处理 gate/audit 中的失败项。');
  }
  if (_num(memory['vector_positive_coverage_rate']) == 0 &&
      _num(memory['retrieval_positive_source_total']) > 0) {
    b.writeln('- 向量召回暂未覆盖正样本，需要检查 embedding provider、query 构造或 chunk 表达。');
  }
  if (_num(memory['super_agent_provider_retry_rate']) > 0.2) {
    b.writeln(
        '- Agent provider retry 偏高，scale run 前建议降低单 provider 并发或下调低健康 provider 优先级。');
  }
  if (_num(memory['provider_infra_task_error_count']) > 0 ||
      _num(legacy['provider_infra_task_error_count']) > 0) {
    b.writeln(
        '- Record-chain 出现 provider infra 错误，本 run 的效果指标可能被 429/配额/网络污染；需要降并发或调整 provider priority 后重跑受影响 shard。');
  }
  if (legacy.isNotEmpty && _num(legacy['task_settlement_rate']) < 0.98) {
    b.writeln('- 老链路 settlement 低于门禁时，只作为 frozen baseline 事实记录，不反向修改老链路。');
  }
  b.writeln('');
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

List<String> _modes(JsonMap metrics) {
  final modes = _list(metrics['modes']).map((item) => item.toString()).toList();
  if (modes.isNotEmpty) return modes;
  return _map(metrics['metrics_by_mode']).keys.toList()..sort();
}

String _llmEnabled(JsonMap metrics) {
  if (metrics.containsKey('llm_enabled')) {
    return metrics['llm_enabled'].toString();
  }
  final values = _list(metrics['llm_enabled_values']);
  if (values.isEmpty) return 'unknown';
  return values.join(', ');
}

String _modeWins(List<String> modes, JsonMap pairwise) {
  final wins = _map(pairwise['mode_win_counts']);
  if (wins.isEmpty) return modes.map((_) => '-').join(' | ');
  return modes.map((mode) => _value(wins[mode])).join(' | ');
}

String _span(int modeCount, String value) {
  if (modeCount <= 1) return value;
  return [value, ...List.filled(modeCount - 1, '')].join(' | ');
}

String _inlineList(List<dynamic> values) {
  if (values.isEmpty) return '`-`';
  return values.map((value) => '`${_escape(value)}`').join(', ');
}

String _compactMap(JsonMap map) {
  if (map.isEmpty) return '-';
  final entries = map.entries.toList()
    ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
  return entries.map((entry) => '${entry.key}:${entry.value}').join(', ');
}

String _familyMetricCell(JsonMap metrics) {
  if (metrics.isEmpty) return '-';
  return [
    'asks=${_value(metrics['ask_count'])}',
    'hit=${_fmt(metrics['answer_hit_rate'])}',
    'boundary=${_fmt(metrics['boundary_precision'])}',
    'r10=${_fmt(metrics['retrieval_hit_at_10'])}',
    'vec=${_fmt(metrics['vector_positive_coverage_rate'])}',
    'vec_only=${_fmt(metrics['vector_only_positive_hit_rate'])}',
  ].join('<br>');
}

String _fmt(dynamic value) {
  if (value == null) return '-';
  if (value is num) {
    if (value.isNaN || value.isInfinite) return value.toString();
    if (value is int) return value.toString();
    final rounded = (value * 1000).round() / 1000;
    return rounded.toStringAsFixed(
      rounded == rounded.truncateToDouble() ? 0 : 3,
    );
  }
  return _escape(value);
}

String _value(dynamic value) => value == null ? '-' : _fmt(value);

String _escape(Object value) {
  return value.toString().replaceAll('|', r'\|').replaceAll('\n', ' ');
}

num _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
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

String _dateStamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

class _MetricRow {
  const _MetricRow(this.key, this.label);

  final String key;
  final String label;
}
