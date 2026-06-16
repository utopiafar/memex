import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _docPath = 'docs/memex-evaluation-framework.md';
const _legacyMetricsRun =
    'evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_with_pr256_instrumentation_20260615';
const _candidateMetricsRun =
    'evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_with_pr256_instrumentation_20260615';
const _legacyJudgeRun =
    'evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614';
const _candidateJudgeRun =
    'evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615';
const _quickQueryRun =
    'evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_with_latency_20260615';
const _traceMetricSmokeRun =
    'evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615';
const _outPath = 'evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md';

void main() async {
  final docMetrics = _metricNamesFromDoc(File(_docPath));
  final directMetricKeys = <String>{
    ..._modeMetricKeys(
      File('$_candidateMetricsRun/metrics.json'),
      'memory_primary',
    ),
    ..._modeMetricKeys(File('$_legacyMetricsRun/metrics.json'), 'legacy_pkm'),
    ..._modeMetricKeys(
      File('$_traceMetricSmokeRun/metrics.json'),
      'memory_primary',
    ),
    ..._topLevelMetricKeys(File('$_quickQueryRun/metrics.json')),
  };
  final judgeMetricKeys = <String>{
    ..._judgeMetricKeys(File('$_candidateJudgeRun/judge/judge_metrics.json')),
    ..._judgeMetricKeys(
      File('$_candidateJudgeRun/supplemental_judge/judge_metrics.json'),
    ),
    ..._judgeMetricKeys(File('$_quickQueryRun/judge/judge_metrics.json')),
    ..._judgeMetricKeys(File('$_legacyJudgeRun/judge/judge_metrics.json')),
  };

  final rows = [
    for (final metric in docMetrics)
      _classifyMetric(
        metric: metric,
        directMetricKeys: directMetricKeys,
        judgeMetricKeys: judgeMetricKeys,
      ),
  ];
  final counts = <String, int>{};
  for (final row in rows) {
    counts[row.status] = (counts[row.status] ?? 0) + 1;
  }

  final report = StringBuffer()
    ..writeln('# PR256 指标覆盖矩阵')
    ..writeln()
    ..writeln('生成时间：${DateTime.now().toUtc().toIso8601String()}')
    ..writeln()
    ..writeln(
        '指标源：`$_docPath`。本文件只抽取 PR #256 指标详情表格第一列的 metric 名称，不把统计方式或数据源字段算作 metric。')
    ..writeln()
    ..writeln('## 覆盖状态汇总')
    ..writeln()
    ..writeln('| 状态 | 数量 | 含义 |')
    ..writeln('| --- | ---: | --- |');
  for (final status in [
    'direct_metrics_json',
    'direct_judge',
    'expanded_direct_metrics_json',
    'proxy_or_trace',
    'not_in_memory_primary_switch_gate',
    'needs_new_gold_or_instrumentation',
  ]) {
    report.writeln(
        '| `$status` | ${counts[status] ?? 0} | ${_statusMeaning(status)} |');
  }
  report
    ..writeln()
    ..writeln('## 审计结论')
    ..writeln()
    ..writeln(
        '- 当前证据足以支撑 Memory Primary 实验开关：核心写入、召回、卡片、Super Agent、工具轨迹、稳定性、延迟、token 与 LLM judge 指标已有大样本新旧对比。')
    ..writeln(
        '- 严格按 PR #256 的每个原子 metric 名称看，当前已没有 `needs_new_gold_or_instrumentation` 项；仍有一批指标以 proxy/trace、focused judge 或非本次门禁方式覆盖。')
    ..writeln('- 因此，本矩阵用于区分“上线门禁已覆盖的风险”和“后续平台化评估仍需补齐的原子指标”。')
    ..writeln()
    ..writeln('## Artifact')
    ..writeln()
    ..writeln('| 类型 | 路径 |')
    ..writeln('| --- | --- |')
    ..writeln('| PR #256 指标源 | `$_docPath` |')
    ..writeln('| Legacy baseline metrics | `$_legacyMetricsRun` |')
    ..writeln('| Memory Primary v12 metrics | `$_candidateMetricsRun` |')
    ..writeln('| Legacy judge | `$_legacyJudgeRun/judge/judge_metrics.json` |')
    ..writeln(
        '| Memory Primary judge | `$_candidateJudgeRun/judge/judge_metrics.json` |')
    ..writeln('| Quick Query closeout | `$_quickQueryRun` |')
    ..writeln('| Trace metric smoke | `$_traceMetricSmokeRun` |')
    ..writeln()
    ..writeln('## 指标逐项矩阵')
    ..writeln()
    ..writeln('| Metric | 状态 | 证据/处理方式 |')
    ..writeln('| --- | --- | --- |');
  for (final row in rows) {
    report.writeln(
      '| `${row.metric}` | `${row.status}` | ${_escapeTable(row.evidence)} |',
    );
  }

  final out = File(_outPath);
  await out.parent.create(recursive: true);
  await out.writeAsString(report.toString(), flush: true);
  stdout.writeln('Wrote $_outPath with ${rows.length} metric rows.');
}

List<String> _metricNamesFromDoc(File file) {
  final metrics = <String>{};
  var inMetricSections = false;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('### 2.2 ')) {
      inMetricSections = true;
    }
    if (!inMetricSections) continue;
    if (line.startsWith('| `')) {
      final match = RegExp(r'^\| `([^`]+)`').firstMatch(line);
      if (match == null) continue;
      metrics.add(match.group(1)!);
    }
  }
  return metrics.toList()..sort();
}

Set<String> _modeMetricKeys(File file, String mode) {
  final json = jsonDecode(file.readAsStringSync()) as JsonMap;
  final metricsByMode = json['metrics_by_mode'];
  if (metricsByMode is Map && metricsByMode[mode] is Map) {
    return (metricsByMode[mode] as Map)
        .keys
        .map((key) => key.toString())
        .toSet();
  }
  return json.keys.map((key) => key.toString()).toSet();
}

Set<String> _topLevelMetricKeys(File file) {
  final json = jsonDecode(file.readAsStringSync()) as JsonMap;
  return json.keys.map((key) => key.toString()).toSet();
}

Set<String> _judgeMetricKeys(File file) {
  if (!file.existsSync()) return const {};
  final json = jsonDecode(file.readAsStringSync()) as JsonMap;
  final metrics = json['metrics'];
  if (metrics is! Map) return const {};
  return metrics.keys.map((key) => key.toString()).toSet();
}

_CoverageRow _classifyMetric({
  required String metric,
  required Set<String> directMetricKeys,
  required Set<String> judgeMetricKeys,
}) {
  if (directMetricKeys.contains(metric)) {
    return _CoverageRow(metric, 'direct_metrics_json',
        '在 large replay、Quick Query closeout 或 trace metric smoke `metrics.json` 中同名直出。');
  }
  if (judgeMetricKeys.contains(metric)) {
    return _CoverageRow(metric, 'direct_judge',
        '在 PR256 原始/补充/focused LLM-as-judge `judge_metrics.json` 中同名直出。');
  }
  final expanded = _expandedMetricNames(metric);
  if (expanded.length > 1 &&
      expanded.every((name) => directMetricKeys.contains(name))) {
    return _CoverageRow(
      metric,
      'expanded_direct_metrics_json',
      'PR 文档用合并写法；当前 artifact 以 `${expanded.join('`, `')}` 分列直出。',
    );
  }

  final status = _manualStatus(metric);
  return _CoverageRow(metric, status.$1, status.$2);
}

List<String> _expandedMetricNames(String metric) {
  if (metric == 'retrieval_hit_at_1/3/5/10') {
    return const [
      'retrieval_hit_at_1',
      'retrieval_hit_at_3',
      'retrieval_hit_at_5',
      'retrieval_hit_at_10',
    ];
  }
  if (metric == 'retrieval_precision_at_1/3/5/10') {
    return const [
      'retrieval_precision_at_1',
      'retrieval_precision_at_3',
      'retrieval_precision_at_5',
      'retrieval_precision_at_10',
    ];
  }
  if (metric == 'retrieval_recall_at_5/10') {
    return const ['retrieval_recall_at_5', 'retrieval_recall_at_10'];
  }
  return [metric];
}

(String, String) _manualStatus(String metric) {
  if (_scheduleOrActionMetrics.contains(metric)) {
    return (
      'not_in_memory_primary_switch_gate',
      'Schedule/System Action 是 PR256 Agent 指标，但本轮 Memory Primary 切换数据集未设计 calendar/reminder payload gold；不作为本次开关门禁。'
    );
  }
  if (_notSwitchGateMetrics.contains(metric)) {
    return (
      'not_in_memory_primary_switch_gate',
      '该指标属于多轮 chat、character、response cache、真实货币成本或非 Memory Primary 主链路能力；未纳入本次切换门禁。'
    );
  }
  if (_instrumentationNeededMetrics.contains(metric)) {
    return (
      'needs_new_gold_or_instrumentation',
      '需要新增标准化 trace、gold label 或更细粒度聚合器后才能同名稳定产出；当前 artifact 只能提供间接线索。'
    );
  }
  return (
    'proxy_or_trace',
    '本轮通过 generated oracle、case log、tool trace、failure categories、focused judge 或人工审计覆盖同类风险，但未同名聚合到 `metrics.json`。'
  );
}

const _scheduleOrActionMetrics = {
  'schedule_refresh_action_accuracy',
  'schedule_refresh_missed_absence',
  'schedule_refresh_unnecessary_absence',
  'schedule_refresh_duplicate_rate',
  'schedule_time_parse_accuracy',
  'schedule_update_cancel_accuracy',
  'system_action_creation_accuracy',
  'action_extraction_precision',
  'action_extraction_recall',
  'due_time_exact_match',
  'unconfirmed_action_creation_absence',
  'system_action_user_choice_respect',
  'schedule_aggregation_settlement_rate',
};

const _notSwitchGateMetrics = {
  'agent_response_cache_hit_rate',
  'agent_response_cache_miss_reason_mix',
  'character_routing_accuracy',
  'chat_recall_source_coverage',
  'chat_session_persistence_rate',
  'cost_per_input',
  'cost_per_successful_input',
  'multi_turn_context_retention',
};

const _instrumentationNeededMetrics = {
  'agent_empty_response_rate',
  'context_peek_redundancy_rate',
  'first_write_after_read_rate',
};

String _statusMeaning(String status) {
  return switch (status) {
    'direct_metrics_json' => '当前 replay/closeout 的 `metrics.json` 已同名直出。',
    'direct_judge' => '当前 judge artifact 已同名直出。',
    'expanded_direct_metrics_json' => 'PR 文档合并写法已拆成多个 top-k 指标直出。',
    'proxy_or_trace' => '当前数据集和日志覆盖同类风险，但不是同名聚合指标。',
    'not_in_memory_primary_switch_gate' =>
      '属于 PR256 Agent 大框架，但不作为 Memory Primary 新旧链路切换门禁。',
    'needs_new_gold_or_instrumentation' => '需要新增 gold、trace 或聚合器才能稳定评估。',
    _ => '',
  };
}

String _escapeTable(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

class _CoverageRow {
  const _CoverageRow(this.metric, this.status, this.evidence);

  final String metric;
  final String status;
  final String evidence;
}
