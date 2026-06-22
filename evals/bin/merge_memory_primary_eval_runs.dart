import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main(List<String> args) async {
  final runDirs = _runDirs(args);
  if (runDirs.isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/merge_memory_primary_eval_runs.dart '
      '<run_dir> [run_dir ...]',
    );
    stderr.writeln(
      'Or set MEMEX_EVAL_MERGE_RUN_DIRS as a comma-separated list.',
    );
    exitCode = 64;
    return;
  }

  final repoRoot = Directory.current.path;
  final runId =
      'memory_primary_merged_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
  final outputDir = Directory(
    Platform.environment['MEMEX_EVAL_MERGE_OUTPUT_DIR'] ??
        p.join(repoRoot, 'evals', 'runs', runId),
  );
  if (await outputDir.exists()) {
    await outputDir.delete(recursive: true);
  }
  await outputDir.create(recursive: true);

  final metricsDocs = <JsonMap>[];
  final observations = <JsonMap>[];
  final failures = <JsonMap>[];
  final judgeTasks = <JsonMap>[];
  for (final dir in runDirs) {
    final metricsFile = File(p.join(dir.path, 'metrics.json'));
    if (!await metricsFile.exists()) {
      throw StateError('Missing metrics.json in ${dir.path}');
    }
    metricsDocs.add(jsonDecode(await metricsFile.readAsString()) as JsonMap);
    observations
        .addAll(await _readJsonl(p.join(dir.path, 'observations.jsonl')));
    failures.addAll(await _readJsonl(p.join(dir.path, 'failures.jsonl')));
    judgeTasks.addAll(await _readJsonl(p.join(dir.path, 'judge_tasks.jsonl')));
    await _copyCaseLogs(
      from: Directory(p.join(dir.path, 'case_logs')),
      to: Directory(p.join(outputDir.path, 'case_logs')),
    );
  }

  final modes = _orderedModes(metricsDocs);
  final metricsByMode = <String, JsonMap>{};
  for (final mode in modes) {
    metricsByMode[mode] =
        _aggregateMode(mode, metricsDocs, observations, failures);
  }
  final comparison = _compareModes(metricsByMode);
  final gate = _evaluateGate(metricsByMode, comparison);

  await _writeJsonl(
      File(p.join(outputDir.path, 'observations.jsonl')), observations);
  await _writeJsonl(File(p.join(outputDir.path, 'failures.jsonl')), failures);
  await _writeJsonl(
      File(p.join(outputDir.path, 'judge_tasks.jsonl')), judgeTasks);
  final mergedMetrics = {
    'dataset_paths': metricsDocs
        .map((doc) => doc['dataset_path']?.toString())
        .whereType<String>()
        .toSet()
        .toList(),
    'llm_enabled_values':
        metricsDocs.map((doc) => doc['llm_enabled']).toSet().toList(),
    'merged_from': runDirs.map((dir) => dir.path).toList(),
    'modes': modes,
    'metrics_by_mode': metricsByMode,
    'comparison': comparison,
    'gate': gate,
    'judge_task_count': judgeTasks.length,
    'pairwise_judge_task_count': _sumTopLevel(
      metricsDocs,
      'pairwise_judge_task_count',
    ),
  };
  await File(p.join(outputDir.path, 'metrics.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(mergedMetrics),
    flush: true,
  );
  await File(p.join(outputDir.path, 'gate.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(gate),
    flush: true,
  );
  await File(p.join(outputDir.path, 'report.md')).writeAsString(
    _renderReport(
      runDirs: runDirs,
      modes: modes,
      metricsByMode: metricsByMode,
      comparison: comparison,
      gate: gate,
      failures: failures,
    ),
    flush: true,
  );
  await File(p.join(outputDir.path, 'case_debug_index.md')).writeAsString(
    _renderCaseDebugIndex(
        modes: modes, observations: observations, failures: failures),
    flush: true,
  );
  stdout.writeln('Merged ${runDirs.length} run dirs into ${outputDir.path}');
  stdout.writeln('Gate status: ${gate['status']}');
}

List<Directory> _runDirs(List<String> args) {
  final raw = args.isNotEmpty
      ? args
      : (Platform.environment['MEMEX_EVAL_MERGE_RUN_DIRS'] ?? '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
  return raw.map(Directory.new).toList(growable: false);
}

Future<List<JsonMap>> _readJsonl(String path) async {
  final file = File(path);
  if (!await file.exists()) return const [];
  final rows = <JsonMap>[];
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    rows.add(jsonDecode(trimmed) as JsonMap);
  }
  return rows;
}

Future<void> _writeJsonl(File file, Iterable<JsonMap> rows) async {
  final sink = file.openWrite();
  try {
    for (final row in rows) {
      sink.writeln(jsonEncode(row));
    }
  } finally {
    await sink.close();
  }
}

Future<void> _copyCaseLogs({
  required Directory from,
  required Directory to,
}) async {
  if (!await from.exists()) return;
  await to.create(recursive: true);
  final sourceRunName = p.basename(p.dirname(from.path));
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: from.path);
    var target = File(p.join(to.path, relative));
    if (await target.exists()) {
      final extension = p.extension(target.path);
      final withoutExtension = p.withoutExtension(target.path);
      target = File('$withoutExtension.$sourceRunName$extension');
    }
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

String _renderCaseDebugIndex({
  required List<String> modes,
  required List<JsonMap> observations,
  required List<JsonMap> failures,
}) {
  final b = StringBuffer();
  b.writeln('# Merged Case Debug Index');
  b.writeln('');
  b.writeln('| Mode | Case | Observations | Failures | Case log |');
  b.writeln('| --- | --- | ---: | ---: | --- |');
  final caseIdsByMode = <String, Set<String>>{};
  for (final observation in observations) {
    final mode = observation['mode']?.toString();
    final caseId = observation['case_id']?.toString();
    if (mode == null || caseId == null) continue;
    caseIdsByMode.putIfAbsent(mode, () => <String>{}).add(caseId);
  }
  for (final failure in failures) {
    final mode = failure['mode']?.toString();
    final caseId = failure['case_id']?.toString();
    if (mode == null || caseId == null) continue;
    caseIdsByMode.putIfAbsent(mode, () => <String>{}).add(caseId);
  }
  for (final mode in modes) {
    final caseIds = (caseIdsByMode[mode] ?? const <String>{}).toList()..sort();
    for (final caseId in caseIds) {
      final observationCount = observations
          .where((row) => row['mode'] == mode && row['case_id'] == caseId)
          .length;
      final failureCount = failures
          .where((row) => row['mode'] == mode && row['case_id'] == caseId)
          .length;
      final logPath = 'case_logs/$mode/$caseId.json';
      b.writeln(
        '| `$mode` | `$caseId` | $observationCount | $failureCount | `$logPath` |',
      );
    }
  }
  return b.toString();
}

List<String> _orderedModes(List<JsonMap> metricsDocs) {
  final seen = <String>{};
  final modes = <String>[];
  for (final doc in metricsDocs) {
    for (final mode in _list(doc['modes']).map((e) => e.toString())) {
      if (seen.add(mode)) modes.add(mode);
    }
  }
  return modes;
}

JsonMap _aggregateMode(
  String mode,
  List<JsonMap> metricsDocs,
  List<JsonMap> observations,
  List<JsonMap> failures,
) {
  final modeMetrics = metricsDocs
      .map((doc) => _map(doc['metrics_by_mode'])[mode])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  int sum(String field) =>
      modeMetrics.fold(0, (total, item) => total + _intValue(item[field]));

  final modeObservations =
      observations.where((obs) => obs['mode'] == mode).toList();
  final recordElapsedMs = modeObservations
      .where((obs) => obs['type'] == 'record')
      .map((obs) => _intValue(obs['elapsed_ms']))
      .where((value) => value > 0)
      .toList();
  final waitObservations = modeObservations
      .where(
          (obs) => obs['type'] == 'record' || obs['type'] == 'para_projection')
      .toList();
  final waitElapsedMs = waitObservations
      .map((obs) => _intValue(obs['elapsed_ms']))
      .where((value) => value > 0)
      .toList();
  final taskQueuePressureSamples = modeObservations
      .map(_activeTaskPressureFromObservation)
      .where((value) => value >= 0)
      .toList();
  final taskSettlementRate = _rate(
    waitObservations.where((obs) => obs['tasks_settled'] == true).length,
    waitObservations.length,
  );

  final taskStatusTotals = <String, int>{};
  for (final item in modeMetrics) {
    for (final entry in _map(item['task_status_totals']).entries) {
      taskStatusTotals[entry.key] =
          (taskStatusTotals[entry.key] ?? 0) + _intValue(entry.value);
    }
  }

  final memoryExpectedHits = sum('memory_expected_hits');
  final memoryExpectedTotal = sum('memory_expected_total');
  final memoryForbiddenHits = sum('memory_forbidden_hits');
  final memoryForbiddenTotal = sum('memory_forbidden_total');
  final cardExpectedHits = sum('card_expected_hits');
  final cardExpectedTotal = sum('card_expected_total');
  final relatedFactExpectedHits = sum('related_fact_expected_hits');
  final relatedFactExpectedTotal = sum('related_fact_expected_total');
  final memoryRecallExpectedHits = sum('memory_recall_expected_hits');
  final memoryRecallExpectedTotal = sum('memory_recall_expected_total');
  final memoryRecallForbiddenHits = sum('memory_recall_forbidden_hits');
  final memoryRecallForbiddenTotal = sum('memory_recall_forbidden_total');
  final recordCount = sum('record_count');
  final materializedCards = sum('materialized_card_count');
  final completedCards = sum('completed_card_count');
  final validCards = sum('valid_card_count');
  final schemaValidCards = sum('card_schema_valid_count');
  final completedCardsWithFailureReason =
      sum('completed_with_failure_reason_count');
  final cardSourceGroundedCount = sum('card_source_fact_grounding_count');
  final cardsWithInsight = sum('cards_with_insight_count');
  final memoryObservedCount = sum('memory_observed_count');
  final memorySourceGroundedCount = sum('memory_source_grounded_count');
  final memoryDuplicateCount = sum('memory_duplicate_count');
  final failedTaskCount = sum('failed_task_count');
  final totalTaskCount = sum('total_task_count');
  final taskNotSettledCount = sum('task_not_settled_count');
  final providerInfraTaskErrorCount = sum('provider_infra_task_error_count');
  final providerRateLimitTaskErrorCount =
      sum('provider_rate_limit_task_error_count');
  final providerQuotaTaskErrorCount = sum('provider_quota_task_error_count');
  final providerNetworkTaskErrorCount =
      sum('provider_network_task_error_count');
  final providerServerTaskErrorCount = sum('provider_server_task_error_count');
  final providerInfraAffectedOperationCount =
      sum('provider_infra_affected_operation_count');
  final retryTaskCount = sum('retry_task_count');
  final superAgentAskCount = sum('super_agent_ask_count');
  final superAgentAnswerSuccessCount = sum('super_agent_answer_success_count');
  final superAgentExpectedHits = sum('super_agent_expected_hits');
  final superAgentExpectedTotal = sum('super_agent_expected_total');
  final superAgentForbiddenHits = sum('super_agent_forbidden_hits');
  final superAgentForbiddenTotal = sum('super_agent_forbidden_total');
  final superAgentUsageTotal = _aggregateUsageTotals(
    modeMetrics.map((item) => _map(item['super_agent_llm_usage_total'])),
  );
  final superAgentProviderAttemptCount =
      sum('super_agent_provider_attempt_count');
  final superAgentProviderRetryCount = sum('super_agent_provider_retry_count');
  final retrievalPositiveSourceTotal = sum('retrieval_positive_source_total');
  final retrievalFtsPositiveHits = sum('retrieval_fts_positive_hits');
  final retrievalVectorPositiveHits = sum('retrieval_vector_positive_hits');
  final retrievalHybridPositiveHits = sum('retrieval_hybrid_positive_hits');
  final retrievalFtsOnlyPositiveHits = _sumBreakdown(
    modeMetrics,
    'retrieval_positive_source_breakdown',
    'fts_only',
  );
  final retrievalVectorOnlyPositiveHits = _sumBreakdown(
    modeMetrics,
    'retrieval_positive_source_breakdown',
    'vector_only',
  );
  final retrievalBothPositiveHits = _sumBreakdown(
    modeMetrics,
    'retrieval_positive_source_breakdown',
    'both',
  );
  final retrievalMissedPositiveCount = _sumBreakdown(
    modeMetrics,
    'retrieval_positive_source_breakdown',
    'missed',
  );
  final retrievalSourceQueryCount = sum('retrieval_source_query_count');
  final retrievalVectorSupportedQueryHits =
      sum('retrieval_vector_supported_query_hits') > 0
          ? sum('retrieval_vector_supported_query_hits')
          : _sumRateNumeratorFromRuns(
              modeMetrics,
              field: 'vector_supported_query_rate',
              denominatorField: 'retrieval_source_query_count',
            );
  final retrievalVectorOnlySupportedQueryHits =
      sum('retrieval_vector_only_supported_query_hits') > 0
          ? sum('retrieval_vector_only_supported_query_hits')
          : _sumRateNumeratorFromRuns(
              modeMetrics,
              field: 'vector_only_supported_query_rate',
              denominatorField: 'retrieval_source_query_count',
            );
  final llmUsageTotal = _aggregateUsageTotals(
    modeMetrics.map((item) => _map(item['llm_usage_total'])),
  );
  final tokensByAgent = _aggregateUsageByAgent(
    modeMetrics.map((item) => _map(item['tokens_by_agent'])),
  );
  final estimatedToolCallCount = modeMetrics.fold<double>(0, (total, item) {
    if (item.containsKey('tool_calls_per_input')) {
      return total +
          _metric(item, 'tool_calls_per_input') * _recordWeight(item);
    }
    return total +
        _metric(item, 'agent_tool_rounds_per_task') * _queryWeight(item);
  });
  final agentLlmTurnsPerTask = _ratioOrZero(
    _intValue(llmUsageTotal['calls']),
    totalTaskCount,
  );
  final maxTurnsAbsence = _allMetricRunsPass(modeMetrics, 'max_turns_absence');
  final agentTurnBudgetViolationRate = maxTurnsAbsence >= 1 ? 0.0 : 1.0;
  final agentFinalizationRate = _ratioOrZero(
    totalTaskCount - failedTaskCount - taskNotSettledCount,
    totalTaskCount,
  );

  return {
    'mode': mode,
    'case_count': sum('case_count'),
    'record_count': recordCount,
    'materialized_card_count': materializedCards,
    'card_materialization_rate': _rate(materializedCards, recordCount),
    'completed_card_count': completedCards,
    'completed_card_rate': _rate(completedCards, recordCount),
    'valid_card_count': validCards,
    'input_to_valid_card_success_rate': _rate(validCards, recordCount),
    'card_completed_rate': _rate(completedCards, recordCount),
    'completed_with_failure_reason_count': completedCardsWithFailureReason,
    'completed_with_failure_reason_rate': _ratioOrZero(
      completedCardsWithFailureReason,
      completedCards,
    ),
    'card_schema_valid_count': schemaValidCards,
    'card_schema_valid_rate': _rate(schemaValidCards, materializedCards),
    'card_source_fact_grounding_count': cardSourceGroundedCount,
    'card_source_fact_grounding_rate': _rate(
      cardSourceGroundedCount,
      materializedCards,
    ),
    'cards_with_insight_count': cardsWithInsight,
    'cards_with_insight_rate': _rate(cardsWithInsight, recordCount),
    'projection_count': sum('projection_count'),
    'memory_expected_hits': memoryExpectedHits,
    'memory_expected_total': memoryExpectedTotal,
    'memory_expected_hit_rate': _rate(memoryExpectedHits, memoryExpectedTotal),
    'memory_must_write_recall': _rate(
      memoryExpectedHits,
      memoryExpectedTotal,
    ),
    'memory_forbidden_hits': memoryForbiddenHits,
    'memory_forbidden_total': memoryForbiddenTotal,
    'memory_must_not_write_precision': _rate(
      memoryForbiddenTotal - memoryForbiddenHits,
      memoryForbiddenTotal,
    ),
    'memory_observed_count': memoryObservedCount,
    'memory_source_grounded_count': memorySourceGroundedCount,
    'memory_source_grounding': _rate(
      memorySourceGroundedCount,
      memoryObservedCount,
    ),
    'memory_duplicate_count': memoryDuplicateCount,
    'memory_duplicate_rate': _ratioOrZero(
      memoryDuplicateCount,
      memoryObservedCount,
    ),
    'card_expected_hits': cardExpectedHits,
    'card_expected_total': cardExpectedTotal,
    'card_expected_hit_rate': _rate(cardExpectedHits, cardExpectedTotal),
    'related_fact_expected_hits': relatedFactExpectedHits,
    'related_fact_expected_total': relatedFactExpectedTotal,
    'related_fact_hit_rate': _rate(
      relatedFactExpectedHits,
      relatedFactExpectedTotal,
    ),
    'memory_recall_query_count': sum('memory_recall_query_count'),
    'memory_recall_expected_hits': memoryRecallExpectedHits,
    'memory_recall_expected_total': memoryRecallExpectedTotal,
    'memory_recall_hit_rate': _rate(
      memoryRecallExpectedHits,
      memoryRecallExpectedTotal,
    ),
    'memory_recall_at_10': _rate(
      memoryRecallExpectedHits,
      memoryRecallExpectedTotal,
    ),
    'memory_recall_forbidden_hits': memoryRecallForbiddenHits,
    'memory_recall_forbidden_total': memoryRecallForbiddenTotal,
    'memory_recall_must_not_precision': _rate(
      memoryRecallForbiddenTotal - memoryRecallForbiddenHits,
      memoryRecallForbiddenTotal,
    ),
    'super_agent_ask_count': superAgentAskCount,
    'super_agent_answer_success_count': superAgentAnswerSuccessCount,
    'super_agent_answer_success_rate': _ratioOrZero(
      superAgentAnswerSuccessCount,
      superAgentAskCount,
    ),
    'super_agent_expected_hits': superAgentExpectedHits,
    'super_agent_expected_total': superAgentExpectedTotal,
    'super_agent_answer_hit_rate': _rate(
      superAgentExpectedHits,
      superAgentExpectedTotal,
    ),
    'super_agent_forbidden_hits': superAgentForbiddenHits,
    'super_agent_forbidden_total': superAgentForbiddenTotal,
    'super_agent_boundary_precision': _rate(
      superAgentForbiddenTotal - superAgentForbiddenHits,
      superAgentForbiddenTotal,
    ),
    'super_agent_llm_usage_total': superAgentUsageTotal,
    'super_agent_tokens_per_ask': _ratioOrZero(
      _intValue(superAgentUsageTotal['total_tokens']),
      superAgentAskCount,
    ),
    'super_agent_provider_attempt_count': superAgentProviderAttemptCount,
    'super_agent_provider_retry_count': superAgentProviderRetryCount,
    'super_agent_provider_retry_rate': _ratioOrZero(
      superAgentProviderRetryCount,
      superAgentProviderAttemptCount,
    ),
    'super_agent_query_family_metrics':
        _aggregateSuperAgentQueryFamilyMetrics(modeMetrics),
    'agent_route_accuracy': _weightedMetric(
      modeMetrics,
      'agent_route_accuracy',
      _operationWeight,
    ),
    'agent_route_miss_rate': _weightedMetric(
      modeMetrics,
      'agent_route_miss_rate',
      _operationWeight,
    ),
    'agent_route_overtrigger_rate': _weightedMetric(
      modeMetrics,
      'agent_route_overtrigger_rate',
      _operationWeight,
    ),
    'card_template_primary_accuracy': _weightedMetric(
      modeMetrics,
      'card_template_primary_accuracy',
      _recordWeight,
    ),
    'card_template_any_accuracy': _weightedMetric(
      modeMetrics,
      'card_template_any_accuracy',
      _recordWeight,
    ),
    'card_field_recall': _weightedMetric(
      modeMetrics,
      'card_field_recall',
      _recordWeight,
    ),
    'card_entity_recall': _weightedMetric(
      modeMetrics,
      'card_entity_recall',
      _recordWeight,
    ),
    'card_time_parse_accuracy': _weightedMetric(
      modeMetrics,
      'card_time_parse_accuracy',
      _recordWeight,
    ),
    'card_hallucinated_field_absence': _weightedMetric(
      modeMetrics,
      'card_hallucinated_field_absence',
      _recordWeight,
    ),
    'retrieval_hit_at_1': _weightedMetric(
      modeMetrics,
      'retrieval_hit_at_1',
      _queryWeight,
    ),
    'retrieval_hit_at_3': _weightedMetric(
      modeMetrics,
      'retrieval_hit_at_3',
      _queryWeight,
    ),
    'retrieval_hit_at_5': _weightedMetric(
      modeMetrics,
      'retrieval_hit_at_5',
      _queryWeight,
    ),
    'retrieval_hit_at_10': _weightedMetric(
      modeMetrics,
      'retrieval_hit_at_10',
      _queryWeight,
    ),
    'retrieval_positive_source_total': retrievalPositiveSourceTotal,
    'retrieval_fts_positive_hits': retrievalFtsPositiveHits,
    'retrieval_vector_positive_hits': retrievalVectorPositiveHits,
    'retrieval_hybrid_positive_hits': retrievalHybridPositiveHits,
    'retrieval_positive_source_breakdown': {
      'both': retrievalBothPositiveHits,
      'fts_only': retrievalFtsOnlyPositiveHits,
      'vector_only': retrievalVectorOnlyPositiveHits,
      'missed': retrievalMissedPositiveCount,
    },
    'fts_positive_coverage_rate': _ratioOrZero(
      retrievalFtsPositiveHits,
      retrievalPositiveSourceTotal,
    ),
    'vector_positive_coverage_rate': _ratioOrZero(
      retrievalVectorPositiveHits,
      retrievalPositiveSourceTotal,
    ),
    'vector_only_positive_hit_rate': _ratioOrZero(
      retrievalVectorOnlyPositiveHits,
      retrievalPositiveSourceTotal,
    ),
    'fts_only_positive_hit_rate': _ratioOrZero(
      retrievalFtsOnlyPositiveHits,
      retrievalPositiveSourceTotal,
    ),
    'hybrid_positive_coverage_rate': _ratioOrZero(
      retrievalHybridPositiveHits,
      retrievalPositiveSourceTotal,
    ),
    'vector_incremental_recall_lift_at_10': _ratioOrZero(
          retrievalHybridPositiveHits,
          retrievalPositiveSourceTotal,
        ) -
        _ratioOrZero(retrievalFtsPositiveHits, retrievalPositiveSourceTotal),
    'vector_supported_query_rate': _ratioOrZero(
      retrievalVectorSupportedQueryHits,
      retrievalSourceQueryCount,
    ),
    'retrieval_vector_supported_query_hits': retrievalVectorSupportedQueryHits,
    'vector_only_supported_query_rate': _ratioOrZero(
      retrievalVectorOnlySupportedQueryHits,
      retrievalSourceQueryCount,
    ),
    'retrieval_vector_only_supported_query_hits':
        retrievalVectorOnlySupportedQueryHits,
    'retrieval_source_query_count': retrievalSourceQueryCount,
    'answer_must_include': _weightedMetric(
      modeMetrics,
      'answer_must_include',
      _queryWeight,
    ),
    'super_agent_read_only_compliance': _weightedMetric(
      modeMetrics,
      'super_agent_read_only_compliance',
      _queryWeight,
    ),
    'tool_selection_accuracy': _weightedMetric(
      modeMetrics,
      'tool_selection_accuracy',
      _queryWeight,
    ),
    'tool_args_accuracy': _weightedMetric(
      modeMetrics,
      'tool_args_accuracy',
      _queryWeight,
    ),
    'tool_call_minimality': _weightedMetric(
      modeMetrics,
      'tool_call_minimality',
      _queryWeight,
    ),
    'tool_call_failure_rate': _weightedMetric(
      modeMetrics,
      'tool_call_failure_rate',
      _taskWeight,
    ),
    'tool_call_retry_rate': _weightedMetric(
      modeMetrics,
      'tool_call_retry_rate',
      _taskWeight,
    ),
    'repeated_tool_call_rate': _weightedMetric(
      modeMetrics,
      'repeated_tool_call_rate',
      _taskWeight,
    ),
    'read_tool_error_rate': _weightedMetric(
      modeMetrics,
      'read_tool_error_rate',
      _taskWeight,
    ),
    'write_tool_error_rate': _weightedMetric(
      modeMetrics,
      'write_tool_error_rate',
      _taskWeight,
    ),
    'context_peek_count_per_task': _weightedMetric(
      modeMetrics,
      'context_peek_count_per_task',
      _taskWeight,
    ),
    'agent_tool_rounds_per_task': _weightedMetric(
      modeMetrics,
      'agent_tool_rounds_per_task',
      _taskWeight,
    ),
    'tool_calls_per_input': _ratioOrZero(
      estimatedToolCallCount.round(),
      recordCount,
    ),
    'agent_llm_turns_per_task': agentLlmTurnsPerTask,
    'agent_llm_turns_per_task_by_agent':
        _llmTurnsPerTaskByAgent(tokensByAgent, totalTaskCount),
    'agent_finalization_rate': agentFinalizationRate,
    'agent_turn_budget_violation_rate': agentTurnBudgetViolationRate,
    'loop_detection_absence': _allMetricRunsPass(
      modeMetrics,
      'loop_detection_absence',
    ),
    'max_turns_absence': _allMetricRunsPass(
      modeMetrics,
      'max_turns_absence',
    ),
    'failed_task_count': failedTaskCount,
    'failed_task_rate': _ratioOrZero(failedTaskCount, totalTaskCount),
    'provider_infra_task_error_count': providerInfraTaskErrorCount,
    'provider_rate_limit_task_error_count': providerRateLimitTaskErrorCount,
    'provider_quota_task_error_count': providerQuotaTaskErrorCount,
    'provider_network_task_error_count': providerNetworkTaskErrorCount,
    'provider_server_task_error_count': providerServerTaskErrorCount,
    'provider_infra_task_error_rate': _ratioOrZero(
      providerInfraTaskErrorCount,
      totalTaskCount,
    ),
    'provider_infra_affected_operation_count':
        providerInfraAffectedOperationCount,
    'provider_infra_affected_operation_rate': _ratioOrZero(
      providerInfraAffectedOperationCount,
      recordCount + sum('projection_count'),
    ),
    'total_task_count': totalTaskCount,
    'task_not_settled_count': taskNotSettledCount,
    'task_settlement_rate': taskSettlementRate,
    'task_completion_status': taskSettlementRate,
    'input_timeout_rate': _ratioOrZero(
      taskNotSettledCount,
      recordCount + sum('projection_count'),
    ),
    'retry_task_count': retryTaskCount,
    'retry_rate': _ratioOrZero(retryTaskCount, totalTaskCount),
    'missing_card_count': sum('missing_card_count'),
    'incomplete_card_count': sum('incomplete_card_count'),
    'task_status_totals': taskStatusTotals,
    'task_type_status_totals': _aggregateTaskTypeStatusTotals(modeMetrics),
    'avg_record_elapsed_ms': recordElapsedMs.isEmpty
        ? 0
        : recordElapsedMs.reduce((a, b) => a + b) ~/ recordElapsedMs.length,
    'p90_record_elapsed_ms': _percentile(recordElapsedMs, 0.90),
    'p95_record_elapsed_ms': _percentile(recordElapsedMs, 0.95),
    'p99_record_elapsed_ms': _percentile(recordElapsedMs, 0.99),
    'max_record_elapsed_ms': _maxInt(recordElapsedMs),
    'input_required_chain_latency_ms': {
      'mean': recordElapsedMs.isEmpty
          ? 0
          : recordElapsedMs.reduce((a, b) => a + b) ~/ recordElapsedMs.length,
      'p90': _percentile(recordElapsedMs, 0.90),
      'p95': _percentile(recordElapsedMs, 0.95),
      'p99': _percentile(recordElapsedMs, 0.99),
      'max': _maxInt(recordElapsedMs),
    },
    'input_full_idle_latency_ms': {
      'mean': waitElapsedMs.isEmpty
          ? 0
          : waitElapsedMs.reduce((a, b) => a + b) ~/ waitElapsedMs.length,
      'p90': _percentile(waitElapsedMs, 0.90),
      'p95': _percentile(waitElapsedMs, 0.95),
      'p99': _percentile(waitElapsedMs, 0.99),
      'max': _maxInt(waitElapsedMs),
    },
    'task_queue_pressure_p95': _percentile(taskQueuePressureSamples, 0.95),
    'tokens_per_input': _ratioOrZero(
      _intValue(llmUsageTotal['total_tokens']),
      recordCount,
    ),
    'tokens_per_successful_input': _ratioOrZero(
      _intValue(llmUsageTotal['total_tokens']),
      completedCards,
    ),
    'llm_usage_total': llmUsageTotal,
    'tokens_by_agent': tokensByAgent,
    'prompt_tokens_by_agent': _usageFieldByAgent(
      tokensByAgent,
      'prompt_tokens',
    ),
    'completion_tokens_by_agent': _usageFieldByAgent(
      tokensByAgent,
      'completion_tokens',
    ),
    'thought_tokens_by_agent': _usageFieldByAgent(
      tokensByAgent,
      'thought_tokens',
    ),
    'prompt_cache_token_hit_rate_by_agent':
        _promptCacheHitRateByAgent(tokensByAgent),
    'prompt_cache_token_hit_rate': _ratioOrZero(
      _intValue(llmUsageTotal['cached_tokens_for_rate']),
      _intValue(llmUsageTotal['effective_prompt_tokens']),
    ),
    'slowest_records': _slowestRecordSummaries(modeObservations),
    'judge_task_count': sum('judge_task_count'),
    'judge_tasks': modeMetrics
        .expand((item) => _list(item['judge_tasks']))
        .toList(growable: false),
    'elapsed_ms': sum('elapsed_ms'),
    'observation_count': modeObservations.length,
    'failure_category_counts': _failureCategoryCounts(
      failures.where((failure) => failure['mode'] == mode),
    ),
    ..._aggregateCoverageMetrics(modeMetrics),
  };
}

JsonMap _aggregateCoverageMetrics(List<JsonMap> modeMetrics) {
  final scenarioFamilies = <String>{};
  final expectedScenarioFamilies = <String>{};
  final agentChains = <String>{};
  final expectedAgentChains = <String>{};
  final journeyStages = <String>{};
  final expectedJourneyStages = <String>{};
  final inputChannels = <String>{};
  final operationTypes = <String>{};
  final expectedOperationTypes = <String>{};
  final agentQueryFamilies = <String>{};
  final expectedAgentQueryFamilies = <String>{};
  final agentQueryRecordGaps = <int>[];
  var caseCount = 0;
  var recordCount = 0;
  var crossDayContinuityCases = 0;
  var correctionCases = 0;
  var noiseCases = 0;
  var followUpQueryCases = 0;
  var relationshipCases = 0;
  var longContextCases = 0;
  var oracleConsistentCases = 0;
  var agentQueryCount = 0;
  var interleavedAgentQueryCount = 0;
  int? minAgentQueriesPerCase;
  var maxAgentQueriesPerCase = 0;

  for (final item in modeMetrics) {
    caseCount += _intValue(item['case_count']);
    recordCount += _intValue(item['record_count']);
    final coverage = _map(item['coverage']);
    scenarioFamilies.addAll(_strings(coverage['covered_scenario_families']));
    expectedScenarioFamilies
        .addAll(_strings(coverage['expected_scenario_families']));
    agentChains.addAll(_strings(coverage['covered_agent_chains']));
    expectedAgentChains.addAll(_strings(coverage['expected_agent_chains']));
    journeyStages.addAll(_strings(coverage['covered_journey_stages']));
    expectedJourneyStages.addAll(_strings(coverage['expected_journey_stages']));
    inputChannels.addAll(_strings(coverage['covered_input_channels']));
    operationTypes.addAll(_strings(coverage['covered_operation_types']));
    expectedOperationTypes
        .addAll(_strings(coverage['expected_operation_types']));
    agentQueryFamilies
        .addAll(_strings(coverage['covered_agent_query_families']));
    expectedAgentQueryFamilies
        .addAll(_strings(coverage['expected_agent_query_families']));
    crossDayContinuityCases +=
        _intValue(coverage['cross_day_continuity_case_count']);
    correctionCases += _intValue(coverage['correction_case_count']);
    noiseCases += _intValue(coverage['noise_resilience_case_count']);
    followUpQueryCases += _intValue(coverage['follow_up_query_case_count']);
    relationshipCases += _intValue(coverage['relationship_case_count']);
    longContextCases += _intValue(coverage['long_context_case_count']);
    oracleConsistentCases +=
        _intValue(coverage['dataset_oracle_consistent_case_count']);
    agentQueryCount += _intValue(coverage['agent_query_count']);
    interleavedAgentQueryCount +=
        _intValue(coverage['interleaved_agent_query_count']);
    for (final gap in _list(coverage['agent_query_record_gaps'])) {
      agentQueryRecordGaps.add(_intValue(gap));
    }
    final itemMinQueries = _intValue(item['agent_query_min_per_case']);
    minAgentQueriesPerCase = minAgentQueriesPerCase == null ||
            itemMinQueries < minAgentQueriesPerCase
        ? itemMinQueries
        : minAgentQueriesPerCase;
    final itemMaxQueries = _intValue(item['agent_query_max_per_case']);
    if (itemMaxQueries > maxAgentQueriesPerCase) {
      maxAgentQueriesPerCase = itemMaxQueries;
    }
  }

  if (expectedScenarioFamilies.isEmpty &&
      expectedAgentChains.isEmpty &&
      expectedJourneyStages.isEmpty &&
      expectedOperationTypes.isEmpty) {
    return const {};
  }

  return {
    'scenario_family_coverage': _setCoverageRate(
      scenarioFamilies,
      expectedScenarioFamilies,
    ),
    'agent_chain_coverage': _setCoverageRate(
      agentChains,
      expectedAgentChains,
    ),
    'journey_stage_coverage': _setCoverageRate(
      journeyStages,
      expectedJourneyStages,
    ),
    'operation_type_coverage': _setCoverageRate(
      operationTypes,
      expectedOperationTypes,
    ),
    'cross_day_continuity_coverage': _rate(
      crossDayContinuityCases,
      caseCount,
    ),
    'correction_operation_coverage': _rate(correctionCases, caseCount),
    'noise_resilience_coverage': _rate(noiseCases, caseCount),
    'follow_up_query_coverage': _rate(followUpQueryCases, caseCount),
    'relationship_case_coverage': _rate(relationshipCases, caseCount),
    'long_context_case_coverage': _rate(longContextCases, caseCount),
    'dataset_oracle_consistency': _rate(oracleConsistentCases, caseCount),
    'agent_query_count': agentQueryCount,
    'interleaved_agent_query_count': interleavedAgentQueryCount,
    'agent_query_interleaving_rate': _ratioOrZero(
      interleavedAgentQueryCount,
      agentQueryCount,
    ),
    'agent_query_density_per_100_records':
        recordCount == 0 ? 0.0 : _round3(agentQueryCount * 100 / recordCount),
    'agent_query_records_per_ask':
        agentQueryCount == 0 ? 0.0 : _round3(recordCount / agentQueryCount),
    'agent_query_family_coverage': _setCoverageRate(
      agentQueryFamilies,
      expectedAgentQueryFamilies,
    ),
    'agent_query_family_count': agentQueryFamilies.length,
    'agent_query_min_per_case': minAgentQueriesPerCase ?? 0,
    'agent_query_max_per_case': maxAgentQueriesPerCase,
    'agent_query_record_gap_p95': _percentile(agentQueryRecordGaps, 0.95),
    'agent_query_record_gap_max': _maxInt(agentQueryRecordGaps),
    'coverage': {
      'covered_scenario_families': scenarioFamilies.toList()..sort(),
      'expected_scenario_families': expectedScenarioFamilies.toList()..sort(),
      'covered_agent_chains': agentChains.toList()..sort(),
      'expected_agent_chains': expectedAgentChains.toList()..sort(),
      'covered_journey_stages': journeyStages.toList()..sort(),
      'expected_journey_stages': expectedJourneyStages.toList()..sort(),
      'covered_input_channels': inputChannels.toList()..sort(),
      'covered_operation_types': operationTypes.toList()..sort(),
      'expected_operation_types': expectedOperationTypes.toList()..sort(),
      'covered_agent_query_families': agentQueryFamilies.toList()..sort(),
      'expected_agent_query_families': expectedAgentQueryFamilies.toList()
        ..sort(),
      'cross_day_continuity_case_count': crossDayContinuityCases,
      'correction_case_count': correctionCases,
      'noise_resilience_case_count': noiseCases,
      'follow_up_query_case_count': followUpQueryCases,
      'relationship_case_count': relationshipCases,
      'long_context_case_count': longContextCases,
      'dataset_oracle_consistent_case_count': oracleConsistentCases,
      'agent_query_count': agentQueryCount,
      'interleaved_agent_query_count': interleavedAgentQueryCount,
      'agent_query_record_gaps': agentQueryRecordGaps,
    },
  };
}

JsonMap _aggregateTaskTypeStatusTotals(List<JsonMap> modeMetrics) {
  final result = <String, Map<String, int>>{};
  for (final item in modeMetrics) {
    for (final typeEntry in _map(item['task_type_status_totals']).entries) {
      final bucket = result.putIfAbsent(typeEntry.key, () => <String, int>{});
      for (final statusEntry in _map(typeEntry.value).entries) {
        bucket[statusEntry.key] =
            (bucket[statusEntry.key] ?? 0) + _intValue(statusEntry.value);
      }
    }
  }
  return result;
}

JsonMap _aggregateSuperAgentQueryFamilyMetrics(List<JsonMap> modeMetrics) {
  const fields = [
    'ask_count',
    'answer_success_count',
    'expected_hits',
    'expected_total',
    'forbidden_hits',
    'forbidden_total',
    'retrieval_hit_at_10_hits',
    'retrieval_hit_at_10_total',
    'positive_source_total',
    'fts_positive_hits',
    'vector_positive_hits',
    'vector_only_positive_hits',
    'hybrid_positive_hits',
    'source_query_count',
    'vector_supported_query_hits',
    'vector_only_supported_query_hits',
    'read_only_hits',
    'read_only_total',
    'tool_selection_hits',
    'tool_selection_total',
    'tool_args_hits',
    'tool_args_total',
  ];
  final buckets = <String, Map<String, int>>{};
  for (final item in modeMetrics) {
    final familyMetrics = _map(item['super_agent_query_family_metrics']);
    for (final entry in familyMetrics.entries) {
      final family = entry.key;
      final source = _map(entry.value);
      final bucket = buckets.putIfAbsent(
          family,
          () => <String, int>{
                for (final field in fields) field: 0,
              });
      for (final field in fields) {
        bucket[field] = (bucket[field] ?? 0) + _intValue(source[field]);
      }
    }
  }
  final result = <String, JsonMap>{};
  final families = buckets.keys.toList()..sort();
  for (final family in families) {
    final b = buckets[family]!;
    final askCount = b['ask_count'] ?? 0;
    final successCount = b['answer_success_count'] ?? 0;
    final expectedHits = b['expected_hits'] ?? 0;
    final expectedTotal = b['expected_total'] ?? 0;
    final forbiddenHits = b['forbidden_hits'] ?? 0;
    final forbiddenTotal = b['forbidden_total'] ?? 0;
    final hitAt10Hits = b['retrieval_hit_at_10_hits'] ?? 0;
    final hitAt10Total = b['retrieval_hit_at_10_total'] ?? 0;
    final positiveSourceTotal = b['positive_source_total'] ?? 0;
    final sourceQueryCount = b['source_query_count'] ?? 0;
    result[family] = {
      'family': family,
      ...b,
      'answer_success_rate': _ratioOrZero(successCount, askCount),
      'answer_hit_rate': _rate(expectedHits, expectedTotal),
      'boundary_precision': _rate(
        forbiddenTotal - forbiddenHits,
        forbiddenTotal,
      ),
      'retrieval_hit_at_10': _rate(hitAt10Hits, hitAt10Total),
      'fts_positive_coverage_rate': _ratioOrZero(
        b['fts_positive_hits'] ?? 0,
        positiveSourceTotal,
      ),
      'vector_positive_coverage_rate': _ratioOrZero(
        b['vector_positive_hits'] ?? 0,
        positiveSourceTotal,
      ),
      'vector_only_positive_hit_rate': _ratioOrZero(
        b['vector_only_positive_hits'] ?? 0,
        positiveSourceTotal,
      ),
      'hybrid_positive_coverage_rate': _ratioOrZero(
        b['hybrid_positive_hits'] ?? 0,
        positiveSourceTotal,
      ),
      'vector_supported_query_rate': _ratioOrZero(
        b['vector_supported_query_hits'] ?? 0,
        sourceQueryCount,
      ),
      'vector_only_supported_query_rate': _ratioOrZero(
        b['vector_only_supported_query_hits'] ?? 0,
        sourceQueryCount,
      ),
      'read_only_compliance': _rate(
        b['read_only_hits'] ?? 0,
        b['read_only_total'] ?? 0,
      ),
      'tool_selection_accuracy': _rate(
        b['tool_selection_hits'] ?? 0,
        b['tool_selection_total'] ?? 0,
      ),
      'tool_args_accuracy': _rate(
        b['tool_args_hits'] ?? 0,
        b['tool_args_total'] ?? 0,
      ),
    };
  }
  return result;
}

int _sumTopLevel(List<JsonMap> docs, String field) {
  return docs.fold(0, (total, doc) => total + _intValue(doc[field]));
}

int _sumBreakdown(List<JsonMap> metrics, String field, String key) {
  return metrics.fold(
    0,
    (total, item) => total + _intValue(_map(item[field])[key]),
  );
}

int _sumRateNumeratorFromRuns(
  List<JsonMap> metrics, {
  required String field,
  required String denominatorField,
}) {
  var total = 0;
  for (final item in metrics) {
    final denominator = _intValue(item[denominatorField]);
    if (denominator <= 0) continue;
    total += (_metric(item, field) * denominator).round();
  }
  return total;
}

JsonMap _emptyUsageBucket() => {
      'calls': 0,
      'prompt_tokens': 0,
      'completion_tokens': 0,
      'cached_tokens': 0,
      'effective_prompt_tokens': 0,
      'cached_tokens_for_rate': 0,
      'thought_tokens': 0,
      'total_tokens': 0,
    };

JsonMap _aggregateUsageTotals(Iterable<JsonMap> usageBuckets) {
  final result = _emptyUsageBucket();
  for (final bucket in usageBuckets) {
    _mergeUsageBucket(result, bucket);
  }
  return result;
}

JsonMap _aggregateUsageByAgent(Iterable<JsonMap> byAgentBuckets) {
  final result = <String, JsonMap>{};
  for (final byAgent in byAgentBuckets) {
    for (final entry in byAgent.entries) {
      final bucket = result.putIfAbsent(entry.key, _emptyUsageBucket);
      _mergeUsageBucket(bucket, _map(entry.value));
    }
  }
  return result;
}

JsonMap _usageFieldByAgent(JsonMap byAgent, String field) {
  return byAgent.map((agent, usage) {
    return MapEntry(agent, _intValue(_map(usage)[field]));
  });
}

JsonMap _promptCacheHitRateByAgent(JsonMap byAgent) {
  return byAgent.map((agent, usage) {
    final bucket = _map(usage);
    return MapEntry(
      agent,
      _ratioOrZero(
        _intValue(bucket['cached_tokens_for_rate']),
        _intValue(bucket['effective_prompt_tokens']),
      ),
    );
  });
}

JsonMap _llmTurnsPerTaskByAgent(JsonMap byAgent, int totalTaskCount) {
  return byAgent.map((agent, usage) {
    final bucket = _map(usage);
    return MapEntry(
      agent,
      _ratioOrZero(_intValue(bucket['calls']), totalTaskCount),
    );
  });
}

int _activeTaskPressureFromObservation(JsonMap observation) {
  final counts = _map(observation['task_status_counts']);
  if (counts.isEmpty) return 0;
  return _intValue(counts['pending']) +
      _intValue(counts['processing']) +
      _intValue(counts['retrying']);
}

double _weightedMetric(
  List<JsonMap> metrics,
  String field,
  int Function(JsonMap metrics) weightFor,
) {
  var weightedTotal = 0.0;
  var weightTotal = 0;
  for (final item in metrics) {
    if (!item.containsKey(field)) continue;
    final value = item[field];
    if (value is! num) continue;
    final weight = weightFor(item);
    final effectiveWeight = weight > 0 ? weight : 1;
    weightedTotal += value.toDouble() * effectiveWeight;
    weightTotal += effectiveWeight;
  }
  if (weightTotal <= 0) return 0;
  return _round3(weightedTotal / weightTotal);
}

double _allMetricRunsPass(List<JsonMap> metrics, String field) {
  var sawMetric = false;
  for (final item in metrics) {
    final value = item[field];
    if (value is! num) continue;
    sawMetric = true;
    if (value < 1.0) return 0.0;
  }
  return sawMetric ? 1.0 : 0.0;
}

int _recordWeight(JsonMap metrics) => _intValue(metrics['record_count']);

int _taskWeight(JsonMap metrics) => _intValue(metrics['total_task_count']);

int _operationWeight(JsonMap metrics) =>
    _intValue(metrics['observation_count']);

int _queryWeight(JsonMap metrics) {
  final queries = _intValue(metrics['super_agent_ask_count']) +
      _intValue(metrics['memory_recall_query_count']);
  return queries > 0 ? queries : _operationWeight(metrics);
}

void _mergeUsageBucket(JsonMap target, JsonMap source) {
  for (final key in [
    'calls',
    'prompt_tokens',
    'completion_tokens',
    'cached_tokens',
    'effective_prompt_tokens',
    'cached_tokens_for_rate',
    'thought_tokens',
    'total_tokens',
  ]) {
    target[key] = _intValue(target[key]) + _intValue(source[key]);
  }
}

JsonMap _compareModes(Map<String, JsonMap> metricsByMode) {
  final legacy = metricsByMode['legacy_pkm'];
  final memory = metricsByMode['memory_primary'];
  if (legacy == null || memory == null) return const {};
  final fields = [
    'card_materialization_rate',
    'completed_card_rate',
    'input_to_valid_card_success_rate',
    'completed_with_failure_reason_rate',
    'card_schema_valid_rate',
    'card_source_fact_grounding_rate',
    'cards_with_insight_rate',
    'memory_expected_hit_rate',
    'memory_must_write_recall',
    'memory_must_not_write_precision',
    'memory_source_grounding',
    'memory_duplicate_rate',
    'card_expected_hit_rate',
    'related_fact_hit_rate',
    'memory_recall_hit_rate',
    'memory_recall_at_10',
    'memory_recall_must_not_precision',
    'super_agent_answer_success_rate',
    'super_agent_answer_hit_rate',
    'super_agent_boundary_precision',
    'super_agent_tokens_per_ask',
    'super_agent_provider_retry_rate',
    'agent_route_accuracy',
    'agent_route_miss_rate',
    'agent_route_overtrigger_rate',
    'card_template_primary_accuracy',
    'card_template_any_accuracy',
    'card_field_recall',
    'card_entity_recall',
    'card_time_parse_accuracy',
    'card_hallucinated_field_absence',
    'retrieval_hit_at_1',
    'retrieval_hit_at_3',
    'retrieval_hit_at_5',
    'retrieval_hit_at_10',
    'fts_positive_coverage_rate',
    'vector_positive_coverage_rate',
    'vector_only_positive_hit_rate',
    'fts_only_positive_hit_rate',
    'hybrid_positive_coverage_rate',
    'vector_incremental_recall_lift_at_10',
    'vector_supported_query_rate',
    'vector_only_supported_query_rate',
    'agent_query_interleaving_rate',
    'agent_query_density_per_100_records',
    'agent_query_family_coverage',
    'answer_must_include',
    'super_agent_read_only_compliance',
    'tool_selection_accuracy',
    'tool_args_accuracy',
    'tool_call_minimality',
    'tool_call_failure_rate',
    'tool_call_retry_rate',
    'repeated_tool_call_rate',
    'read_tool_error_rate',
    'write_tool_error_rate',
    'context_peek_count_per_task',
    'agent_tool_rounds_per_task',
    'loop_detection_absence',
    'max_turns_absence',
    'provider_infra_task_error_rate',
    'provider_infra_affected_operation_rate',
    'scenario_family_coverage',
    'agent_chain_coverage',
    'journey_stage_coverage',
    'operation_type_coverage',
    'cross_day_continuity_coverage',
    'correction_operation_coverage',
    'noise_resilience_coverage',
    'follow_up_query_coverage',
    'task_settlement_rate',
    'failed_task_rate',
    'retry_rate',
    'input_timeout_rate',
    'prompt_cache_token_hit_rate',
  ];
  final deltas = <String, dynamic>{};
  for (final field in fields) {
    deltas['${field}_delta'] = _round3(
      _metric(memory, field) - _metric(legacy, field),
    );
  }
  deltas['avg_record_elapsed_ms_delta'] =
      _metric(memory, 'avg_record_elapsed_ms') -
          _metric(legacy, 'avg_record_elapsed_ms');
  deltas['p90_record_elapsed_ms_delta'] =
      _metric(memory, 'p90_record_elapsed_ms') -
          _metric(legacy, 'p90_record_elapsed_ms');
  deltas['p95_record_elapsed_ms_delta'] =
      _metric(memory, 'p95_record_elapsed_ms') -
          _metric(legacy, 'p95_record_elapsed_ms');
  deltas['p99_record_elapsed_ms_delta'] =
      _metric(memory, 'p99_record_elapsed_ms') -
          _metric(legacy, 'p99_record_elapsed_ms');
  deltas['max_record_elapsed_ms_delta'] =
      _metric(memory, 'max_record_elapsed_ms') -
          _metric(legacy, 'max_record_elapsed_ms');
  return deltas;
}

JsonMap _evaluateGate(Map<String, JsonMap> metricsByMode, JsonMap comparison) {
  final memory = metricsByMode['memory_primary'];
  if (memory == null) {
    return {
      'mode': 'merged_candidate',
      'status': 'fail',
      'failed_rules': ['memory_primary metrics missing'],
    };
  }
  final maxP95RecordMs = _intEnv('MEMEX_EVAL_MAX_P95_RECORD_MS') ?? 180000;
  final rules = <JsonMap>[
    _minRule(memory, 'completed_card_rate', 0.98),
    _minRule(memory, 'cards_with_insight_rate', 0.95),
    _minRule(memory, 'memory_expected_hit_rate', 0.70),
    _minRule(memory, 'memory_must_not_write_precision', 0.95),
    _minRule(memory, 'card_expected_hit_rate', 0.80),
    _minRule(memory, 'related_fact_hit_rate', 0.60),
    _minRule(memory, 'memory_recall_hit_rate', 0.70),
    _minRule(memory, 'memory_recall_must_not_precision', 0.95),
    _minRule(memory, 'super_agent_answer_success_rate', 0.95),
    _minRule(memory, 'super_agent_answer_hit_rate', 0.95),
    _minRule(memory, 'super_agent_boundary_precision', 0.95),
    _minRule(memory, 'task_settlement_rate', 0.98),
    _maxRule(memory, 'failed_task_count', 0),
    _maxRule(memory, 'task_not_settled_count', 0),
    _maxRule(memory, 'p95_record_elapsed_ms', maxP95RecordMs),
    if (comparison.isNotEmpty) ...[
      _minComparisonRule(comparison, 'memory_expected_hit_rate_delta', 0.15),
      _minComparisonRule(comparison, 'related_fact_hit_rate_delta', 0.0),
      _minComparisonRule(comparison, 'memory_recall_hit_rate_delta', 0.15),
    ],
  ];
  final failed = rules.where((rule) => rule['pass'] != true).toList();
  return {
    'mode': 'merged_candidate',
    'status': failed.isEmpty ? 'pass' : 'fail',
    'max_p95_record_ms': maxP95RecordMs,
    'rules': rules,
    'failed_rules': failed.map((rule) => rule['name']).toList(),
  };
}

String _renderReport({
  required List<Directory> runDirs,
  required List<String> modes,
  required Map<String, JsonMap> metricsByMode,
  required JsonMap comparison,
  required JsonMap gate,
  required List<JsonMap> failures,
}) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Merged Eval Report');
  b.writeln('');
  b.writeln('- Merged run dirs: `${runDirs.length}`');
  b.writeln('- Modes: `${modes.join(', ')}`');
  b.writeln('- Gate status: `${gate['status']}`');
  b.writeln('');
  b.writeln('## Run Dirs');
  b.writeln('');
  for (final dir in runDirs) {
    b.writeln('- `${dir.path}`');
  }
  b.writeln('');
  b.writeln('| Metric | ${modes.join(' | ')} |');
  b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} |');
  for (final metric in [
    'case_count',
    'record_count',
    'materialized_card_count',
    'card_materialization_rate',
    'completed_card_rate',
    'input_to_valid_card_success_rate',
    'completed_with_failure_reason_rate',
    'card_schema_valid_rate',
    'card_source_fact_grounding_rate',
    'cards_with_insight_rate',
    'memory_expected_hits',
    'memory_expected_total',
    'memory_expected_hit_rate',
    'memory_must_write_recall',
    'memory_must_not_write_precision',
    'memory_source_grounding',
    'memory_duplicate_rate',
    'card_expected_hit_rate',
    'related_fact_hit_rate',
    'memory_recall_query_count',
    'memory_recall_hit_rate',
    'memory_recall_at_10',
    'memory_recall_must_not_precision',
    'super_agent_ask_count',
    'super_agent_answer_success_rate',
    'super_agent_answer_hit_rate',
    'super_agent_boundary_precision',
    'super_agent_tokens_per_ask',
    'super_agent_provider_attempt_count',
    'super_agent_provider_retry_count',
    'super_agent_provider_retry_rate',
    'agent_route_accuracy',
    'agent_route_miss_rate',
    'agent_route_overtrigger_rate',
    'card_template_primary_accuracy',
    'card_template_any_accuracy',
    'card_field_recall',
    'card_entity_recall',
    'card_time_parse_accuracy',
    'card_hallucinated_field_absence',
    'retrieval_hit_at_1',
    'retrieval_hit_at_3',
    'retrieval_hit_at_5',
    'retrieval_hit_at_10',
    'retrieval_positive_source_total',
    'fts_positive_coverage_rate',
    'vector_positive_coverage_rate',
    'vector_only_positive_hit_rate',
    'fts_only_positive_hit_rate',
    'hybrid_positive_coverage_rate',
    'vector_incremental_recall_lift_at_10',
    'vector_supported_query_rate',
    'vector_only_supported_query_rate',
    'retrieval_source_query_count',
    'agent_query_count',
    'interleaved_agent_query_count',
    'agent_query_interleaving_rate',
    'agent_query_density_per_100_records',
    'agent_query_records_per_ask',
    'agent_query_family_coverage',
    'agent_query_family_count',
    'agent_query_min_per_case',
    'agent_query_max_per_case',
    'agent_query_record_gap_p95',
    'agent_query_record_gap_max',
    'answer_must_include',
    'super_agent_read_only_compliance',
    'tool_selection_accuracy',
    'tool_args_accuracy',
    'tool_call_minimality',
    'tool_call_failure_rate',
    'tool_call_retry_rate',
    'repeated_tool_call_rate',
    'read_tool_error_rate',
    'write_tool_error_rate',
    'context_peek_count_per_task',
    'agent_tool_rounds_per_task',
    'loop_detection_absence',
    'max_turns_absence',
    'judge_task_count',
    'scenario_family_coverage',
    'agent_chain_coverage',
    'journey_stage_coverage',
    'operation_type_coverage',
    'cross_day_continuity_coverage',
    'correction_operation_coverage',
    'noise_resilience_coverage',
    'follow_up_query_coverage',
    'relationship_case_coverage',
    'long_context_case_coverage',
    'dataset_oracle_consistency',
    'failed_task_count',
    'failed_task_rate',
    'provider_infra_task_error_count',
    'provider_rate_limit_task_error_count',
    'provider_quota_task_error_count',
    'provider_network_task_error_count',
    'provider_server_task_error_count',
    'provider_infra_task_error_rate',
    'provider_infra_affected_operation_count',
    'provider_infra_affected_operation_rate',
    'task_not_settled_count',
    'task_settlement_rate',
    'input_timeout_rate',
    'retry_rate',
    'total_task_count',
    'tokens_per_input',
    'prompt_cache_token_hit_rate',
    'avg_record_elapsed_ms',
    'p90_record_elapsed_ms',
    'p95_record_elapsed_ms',
    'p99_record_elapsed_ms',
    'max_record_elapsed_ms',
    'elapsed_ms',
  ]) {
    b.writeln(
      '| `$metric` | ${modes.map((mode) => metricsByMode[mode]?[metric] ?? '-').join(' | ')} |',
    );
  }
  if (comparison.isNotEmpty) {
    b.writeln('');
    b.writeln('## New-vs-Legacy Delta');
    b.writeln('');
    b.writeln('| Delta | Value |');
    b.writeln('| --- | ---: |');
    for (final entry in comparison.entries) {
      b.writeln('| `${entry.key}` | ${entry.value} |');
    }
  }
  b.writeln('');
  b.writeln('## Gate');
  b.writeln('');
  b.writeln('| Rule | Actual | Required | Status |');
  b.writeln('| --- | ---: | ---: | --- |');
  for (final rule in _list(gate['rules']).map(_map)) {
    final required = rule['min'] ?? rule['max'] ?? '-';
    b.writeln(
      '| `${rule['name']}` | ${rule['actual']} | $required | ${rule['pass'] == true ? 'pass' : 'fail'} |',
    );
  }
  final counts = _failureCategoryCounts(failures);
  if (counts.isNotEmpty) {
    b.writeln('');
    b.writeln('## Failure Attribution');
    b.writeln('');
    b.writeln('| Category | ${modes.join(' | ')} | Total |');
    b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} | ---: |');
    for (final entry in counts.entries) {
      final modeCounts = modes.map((mode) {
        return failures
            .where(
              (failure) =>
                  failure['mode'] == mode && failure['category'] == entry.key,
            )
            .length;
      }).join(' | ');
      b.writeln('| `${entry.key}` | $modeCounts | ${entry.value} |');
    }
  }
  _writeSlowestRecordsSection(b, modes, metricsByMode);
  return b.toString();
}

void _writeSlowestRecordsSection(
  StringBuffer b,
  List<String> modes,
  Map<String, JsonMap> metricsByMode,
) {
  b.writeln('');
  b.writeln('## Slowest Records');
  for (final mode in modes) {
    final records = _list(metricsByMode[mode]?['slowest_records'])
        .map(_map)
        .toList(growable: false);
    if (records.isEmpty) continue;
    b.writeln('');
    b.writeln('### `$mode`');
    b.writeln('');
    b.writeln(
      '| Case | Operation | Elapsed ms | Settled | Task statuses | Atoms | Title |',
    );
    b.writeln('| --- | --- | ---: | --- | --- | ---: | --- |');
    for (final record in records) {
      b.writeln(
        '| `${record['case_id'] ?? '-'}` | `${record['operation_id'] ?? '-'}` | '
        '${record['elapsed_ms'] ?? '-'} | ${record['tasks_settled'] ?? '-'} | '
        '`${_compactJson(record['task_status_counts'])}` | '
        '${record['memory_atom_count'] ?? '-'} | '
        '${_escapeTableText(record['title']?.toString() ?? '-')} |',
      );
    }
  }
}

JsonMap _minRule(JsonMap metrics, String field, double min) {
  final actual = _metric(metrics, field);
  return {
    'name': '$field >= $min',
    'field': field,
    'actual': _round3(actual),
    'min': min,
    'pass': actual >= min,
  };
}

JsonMap _maxRule(JsonMap metrics, String field, num max) {
  final actual = _metric(metrics, field);
  return {
    'name': '$field <= $max',
    'field': field,
    'actual': actual,
    'max': max,
    'pass': actual <= max,
  };
}

JsonMap _minComparisonRule(JsonMap comparison, String field, double min) {
  final actual = _metric(comparison, field);
  return {
    'name': '$field >= $min',
    'field': field,
    'actual': _round3(actual),
    'min': min,
    'pass': actual >= min,
  };
}

Map<String, int> _failureCategoryCounts(Iterable<JsonMap> failures) {
  final counts = <String, int>{};
  for (final failure in failures) {
    final category = failure['category']?.toString() ?? 'unknown';
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
}

double _metric(JsonMap map, String field) {
  final value = map[field];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _rate(int numerator, int denominator) {
  if (denominator <= 0) return 1;
  return _round3(numerator / denominator);
}

double _ratioOrZero(int numerator, int denominator) {
  if (denominator <= 0) return 0;
  return _round3(numerator / denominator);
}

double _round3(double value) => (value * 1000).round() / 1000;

double _setCoverageRate(Set<String> covered, Iterable<String> expected) {
  final expectedSet = expected.toSet();
  if (expectedSet.isEmpty) return 1;
  return _round3(covered.intersection(expectedSet).length / expectedSet.length);
}

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

List<JsonMap> _slowestRecordSummaries(
  Iterable<JsonMap> observations, {
  int limit = 8,
}) {
  final records = observations
      .where((obs) => obs['type'] == 'record')
      .map((obs) => Map<String, dynamic>.from(obs))
      .toList()
    ..sort((a, b) => _intValue(b['elapsed_ms']) - _intValue(a['elapsed_ms']));
  return records.take(limit).map((obs) {
    final card = _map(obs['card']);
    return {
      'case_id': obs['case_id'],
      'operation_id': obs['operation_id'],
      'elapsed_ms': _intValue(obs['elapsed_ms']),
      'tasks_settled': obs['tasks_settled'],
      'task_status_counts': _map(obs['task_status_counts']),
      'memory_atom_count': obs['memory_atom_count'],
      if (card['title'] != null) 'title': card['title'],
    };
  }).toList(growable: false);
}

String _compactJson(Object? value) => jsonEncode(value ?? const {});

String _escapeTableText(String value) => value.replaceAll('|', r'\|');

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _intEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return null;
  return int.tryParse(value);
}

JsonMap _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

List<String> _strings(Object? value) {
  return _list(value).map((item) => item.toString()).toList(growable: false);
}
