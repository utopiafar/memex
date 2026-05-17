// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/data/services/llm_call_record_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

typedef JsonMap = Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_llmEnabled) {
    HttpOverrides.global = _EvalHttpOverrides();
  }

  test(
    'replays serial single-user operations through Memex full chain',
    () async {
      final repoRoot = Directory.current.path;
      final datasetPath = Platform.environment['MEMEX_EVAL_DATASET'] ??
          p.join(
            repoRoot,
            'evals',
            'datasets',
            'full_chain_serial_smoke',
            'cases.jsonl',
          );
      final runDir = Directory(
        Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
            p.join(repoRoot, 'evals', 'runs', 'full_chain_serial_smoke'),
      );
      if (await runDir.exists()) {
        await runDir.delete(recursive: true);
      }
      await runDir.create(recursive: true);

      final pathProviderRoot = await Directory.systemTemp.createTemp(
        'memex_serial_full_chain_paths_',
      );
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        pathProviderRoot.path,
      );
      WakelockPlusPlatformInterface.instance = _FakeWakelockPlusPlatform();
      SharedPreferences.setMockInitialValues({});
      LocalTaskExecutor.maxConcurrencyOverrideForTesting = 1;

      final router = MemexRouter();
      final allCases = await _loadCases(datasetPath);
      final caseLimit = _intFromEnv('MEMEX_EVAL_CASE_LIMIT');
      final cases =
          caseLimit == null ? allCases : allCases.take(caseLimit).toList();
      final observations = <Map<String, dynamic>>[];
      final summaries = <Map<String, dynamic>>[];
      final suiteStartedAt = DateTime.now();

      stdout.writeln(
        '[serial replay] start dataset=$datasetPath cases=${cases.length} '
        'llm_enabled=$_llmEnabled task_wait_policy=$_taskWaitPolicyDescription '
        'status_interval=${_formatDuration(_statusInterval)} '
        'max_concurrency=1',
      );

      try {
        for (var caseIndex = 0; caseIndex < cases.length; caseIndex++) {
          final evalCase = cases[caseIndex];
          final caseId = evalCase['case_id']?.toString() ?? 'case_$caseIndex';
          final operations = (_list(evalCase['operations'])).map(_map).toList();
          final dataRoot = await Directory.systemTemp.createTemp(
            'memex_serial_${caseId}_',
          );

          LocalTaskExecutor.instance.stop();
          router.resetForLogout();
          final userId = _caseUserId(evalCase, caseIndex);
          await UserStorage.saveUser(userId);
          await UserStorage.setLocale(const Locale('zh', 'CN'));
          await UserStorage.setWorkspaceStorageToCustom(userId, dataRoot.path);
          await _configureOptionalLlm();
          await router.switchUser(userId);
          await CommentSettingsService.save(
            userId,
            const CommentSettings(enableCharacterComment: false),
          );

          stdout.writeln(
            '[serial replay] case ${caseIndex + 1}/${cases.length} '
            'case_id=$caseId user_id=$userId operations=${operations.length}',
          );

          final startedAt = DateTime.now();
          final submittedFactIdsByOperation = <String, String>{};
          final cardsByOperation = <String, dynamic>{};
          final superAgentAnswersByOperation = <String, String>{};
          final superAgentToolCallsByOperation =
              <String, List<Map<String, dynamic>>>{};
          final chatErrorsByOperation = <String, List<String>>{};
          final operationLogs = <Map<String, dynamic>>[];
          Map<String, dynamic> lastTaskStatusCounts = {};
          List<dynamic> lastTasks = const [];
          String superAgentAnswer = '';
          final superAgentToolCalls = <Map<String, dynamic>>[];
          final chatErrors = <String>[];
          var submittedRecords = 0;
          var abortCase = false;

          for (final operation in operations) {
            final opId = operation['id']?.toString() ??
                'op_${operationLogs.length.toString().padLeft(2, '0')}';
            final type = operation['type']?.toString();
            final opStartedAt = DateTime.now();
            stdout.writeln('[serial replay] $caseId op=$opId type=$type start');

            if (type == 'record') {
              submittedRecords++;
              final response = await router.submitInput(
                text: operation['content']?.toString(),
                textHash: opId,
                createdAt: DateTime.parse(operation['time'].toString()),
              );
              final factId = response['fact_id'] as String;
              submittedFactIdsByOperation[opId] = factId;
              final waitTimeout = _taskWaitTimeoutFor(type);
              final waitResult = await _waitForTasksToSettle(
                minTasks: submittedRecords * 4,
                timeout: waitTimeout,
                runDir: runDir,
                caseId: caseId,
                operationId: opId,
                startedAt: opStartedAt,
              );
              lastTasks = waitResult.tasks;
              lastTaskStatusCounts = _statusCounts(waitResult.tasks);
              final card = await router.fetchTimelineCard(factId);
              cardsByOperation[opId] = card?.toJson();
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'channel': operation['channel'] ?? 'text',
                if (operation['journey_stage'] != null)
                  'journey_stage': operation['journey_stage'],
                if (operation['scenario_family'] != null)
                  'scenario_family': operation['scenario_family'],
                if (operation['is_correction'] == true) 'is_correction': true,
                if (operation['is_noise'] == true) 'is_noise': true,
                if (operation['cross_day_link'] == true) 'cross_day_link': true,
                'fact_id': factId,
                'tasks_settled': waitResult.settled,
                'task_status_counts': lastTaskStatusCounts,
                'task_wait_timeout_ms': waitTimeout.inMilliseconds,
                'elapsed_ms':
                    DateTime.now().difference(opStartedAt).inMilliseconds,
              });
              abortCase = !waitResult.settled;
            } else if (type == 'fetch_timeline') {
              final cards = (await router.fetchTimelineCards(
                page: 1,
                limit: (operation['limit'] as num?)?.toInt() ?? 20,
                dateFrom: _parseOptionalDateTime(operation['date_from']),
                dateTo: _parseOptionalDateTime(operation['date_to']),
              ))
                  .valueOrThrow;
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'card_count': cards.length,
                'elapsed_ms':
                    DateTime.now().difference(opStartedAt).inMilliseconds,
              });
            } else if (type == 'post_comment') {
              final targetOperationId =
                  operation['target_operation_id']?.toString();
              final cardId = targetOperationId == null
                  ? (submittedFactIdsByOperation.isEmpty
                      ? null
                      : submittedFactIdsByOperation.values.last)
                  : submittedFactIdsByOperation[targetOperationId];
              if (cardId == null) {
                operationLogs.add({
                  'operation_id': opId,
                  'type': type,
                  'time': operation['time'],
                  'error': 'No target card id resolved.',
                });
              } else {
                final response = await router.postComment(
                  cardId,
                  operation['content']?.toString() ?? '',
                );
                final waitTimeout = _taskWaitTimeoutFor(type);
                final waitResult = await _waitForTasksToSettle(
                  minTasks: lastTasks.length + 1,
                  timeout: waitTimeout,
                  runDir: runDir,
                  caseId: caseId,
                  operationId: opId,
                  startedAt: opStartedAt,
                );
                lastTasks = waitResult.tasks;
                lastTaskStatusCounts = _statusCounts(waitResult.tasks);
                operationLogs.add({
                  'operation_id': opId,
                  'type': type,
                  'time': operation['time'],
                  'target_operation_id': targetOperationId,
                  'card_id': cardId,
                  'comment_id': response['comment_id'],
                  'tasks_settled': waitResult.settled,
                  'task_status_counts': lastTaskStatusCounts,
                  'task_wait_timeout_ms': waitTimeout.inMilliseconds,
                  'elapsed_ms':
                      DateTime.now().difference(opStartedAt).inMilliseconds,
                });
                abortCase = !waitResult.settled;
              }
            } else if (type == 'refresh_schedule_aggregation') {
              (await router.refreshScheduleAggregation()).valueOrThrow;
              final waitTimeout = _taskWaitTimeoutFor(type);
              final waitResult = await _waitForTasksToSettle(
                minTasks: lastTasks.length + 1,
                timeout: waitTimeout,
                runDir: runDir,
                caseId: caseId,
                operationId: opId,
                startedAt: opStartedAt,
              );
              lastTasks = waitResult.tasks;
              lastTaskStatusCounts = _statusCounts(waitResult.tasks);
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'tasks_settled': waitResult.settled,
                'task_status_counts': lastTaskStatusCounts,
                'task_wait_timeout_ms': waitTimeout.inMilliseconds,
                'elapsed_ms':
                    DateTime.now().difference(opStartedAt).inMilliseconds,
              });
              abortCase = !waitResult.settled;
            } else if (type == 'refresh_knowledge_insights') {
              (await router.updateKnowledgeInsights()).valueOrThrow;
              final waitTimeout = _taskWaitTimeoutFor(type);
              final waitResult = await _waitForTasksToSettle(
                minTasks: lastTasks.length + 1,
                timeout: waitTimeout,
                runDir: runDir,
                caseId: caseId,
                operationId: opId,
                startedAt: opStartedAt,
              );
              lastTasks = waitResult.tasks;
              lastTaskStatusCounts = _statusCounts(waitResult.tasks);
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'tasks_settled': waitResult.settled,
                'task_status_counts': lastTaskStatusCounts,
                'task_wait_timeout_ms': waitTimeout.inMilliseconds,
                'elapsed_ms':
                    DateTime.now().difference(opStartedAt).inMilliseconds,
              });
              abortCase = !waitResult.settled;
            } else if (type == 'wait_memory') {
              final timeoutSeconds =
                  (operation['timeout_seconds'] as num?)?.toInt() ?? 120;
              final memoryWait = await _waitForMemory(
                router: router,
                mustIncludeAny: _strings(operation['must_include_any']),
                timeout: Duration(seconds: timeoutSeconds),
              );
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'matched': memoryWait.matched,
                'elapsed_ms': memoryWait.elapsedMs,
                'memory_entries': memoryWait.entries,
              });
            } else if (type == 'ask_super_agent') {
              final query = _queryWithOperationTime(operation);
              final chat = await _askSuperAgent(
                router: router,
                query: query,
                quickQuery: operation['quick_query'] != false,
              );
              superAgentAnswer = chat.answer;
              superAgentAnswersByOperation[opId] = chat.answer;
              superAgentToolCallsByOperation[opId] = chat.toolCalls;
              chatErrorsByOperation[opId] = chat.errors;
              superAgentToolCalls.addAll(chat.toolCalls);
              chatErrors.addAll(chat.errors);
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'answer': chat.answer,
                'tool_calls': chat.toolCalls,
                'errors': chat.errors,
                'elapsed_ms': chat.elapsedMs,
              });
            } else {
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'time': operation['time'],
                'error': 'Unknown operation type.',
              });
            }
            if (abortCase) {
              stdout.writeln(
                '[serial replay] $caseId op=$opId type=$type did not settle; '
                'stopping remaining operations for this case.',
              );
              break;
            }
          }

          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          final memoryData = await _readMemory(router);
          final memoryEntries = _memoryEntries(memoryData);
          final traceEvents = <Map<String, dynamic>>[
            ..._taskTraceEvents(lastTasks),
            ...await _agentActivityTraceEvents(),
          ];
          final llmCalls = await _llmCallsForUser(userId);
          final operationStats = _operationStats(operationLogs);
          final personaMarkers = _personaMarkers(evalCase);
          final featureTriggers = _featureTriggers(
            operationLogs: operationLogs,
            traceEvents: traceEvents,
            memoryEntries: memoryEntries,
            cardsByOperation: cardsByOperation,
          );
          final activeTasks = lastTasks
              .where(
                (task) =>
                    ['pending', 'processing', 'retrying'].contains(task.status),
              )
              .toList();
          final failedTasks =
              lastTasks.where((task) => task.status == 'failed').toList();

          for (final rawTask in _list(evalCase['eval_tasks'])) {
            final task = _map(rawTask);
            final taskId = task['task_id']?.toString() ?? '${caseId}_task';
            final taskType = task['type']?.toString();
            final expected = _map(task['expected']);
            if (taskType == 'card_extraction') {
              final operationId = expected['operation_id']?.toString() ??
                  expected['input_id']?.toString();
              final card = operationId == null
                  ? (cardsByOperation.values.isEmpty
                      ? null
                      : cardsByOperation.values.first)
                  : cardsByOperation[operationId];
              observations.add({
                'case_id': caseId,
                'task_id': taskId,
                'observed': {
                  'card': _cardObservationFromJson(_map(card)),
                  'trace_events': traceEvents,
                  'llm_calls': const [],
                  'case_elapsed_ms': elapsedMs,
                  'suite_elapsed_ms':
                      DateTime.now().difference(suiteStartedAt).inMilliseconds,
                  'input_count': submittedRecords,
                  'task_count': lastTasks.length,
                },
              });
            } else if (taskType == 'cost_trace') {
              observations.add({
                'case_id': caseId,
                'task_id': taskId,
                'observed': {
                  'answer':
                      'Serial full chain 已写入 Facts、Cards，并完成 Super Agent 问答。',
                  'trace_events': traceEvents,
                  'active_tasks': activeTasks.map(_taskSummary).toList(),
                  'failed_tasks': failedTasks.map(_taskSummary).toList(),
                  'task_status_counts': lastTaskStatusCounts,
                  'tasks_settled': activeTasks.isEmpty,
                  'llm_calls': llmCalls,
                  'case_elapsed_ms': elapsedMs,
                  'suite_elapsed_ms':
                      DateTime.now().difference(suiteStartedAt).inMilliseconds,
                  'input_count': submittedRecords,
                  'task_count': lastTasks.length,
                  'operation_logs': operationLogs,
                  ...operationStats,
                  'persona_markers': personaMarkers,
                  'memory_entry_count': memoryEntries.length,
                  'feature_triggers': featureTriggers,
                },
              });
            } else if (taskType == 'memory_write') {
              observations.add({
                'case_id': caseId,
                'task_id': taskId,
                'observed': {
                  'memory_entries': memoryEntries,
                  'trace_events': traceEvents,
                  'llm_calls': const [],
                  'case_elapsed_ms': elapsedMs,
                  'suite_elapsed_ms':
                      DateTime.now().difference(suiteStartedAt).inMilliseconds,
                },
              });
            } else if (taskType == 'super_agent_qa') {
              final operationId = expected['operation_id']?.toString();
              final answer = operationId == null
                  ? superAgentAnswer
                  : superAgentAnswersByOperation[operationId] ??
                      superAgentAnswer;
              final toolCalls = operationId == null
                  ? superAgentToolCalls
                  : superAgentToolCallsByOperation[operationId] ??
                      superAgentToolCalls;
              final errors = operationId == null
                  ? chatErrors
                  : chatErrorsByOperation[operationId] ?? chatErrors;
              final sourceSnippets = _sourceSnippetsFromMemory(memoryEntries);
              observations.add({
                'case_id': caseId,
                'task_id': taskId,
                'observed': {
                  'answer': answer,
                  'tool_calls': toolCalls,
                  'retrieved_sources':
                      sourceSnippets.map((s) => s['source_id']).toList(),
                  'cited_sources':
                      sourceSnippets.map((s) => s['source_id']).toList(),
                  'source_snippets': sourceSnippets,
                  'trace_events': traceEvents,
                  'llm_calls': const [],
                  'case_elapsed_ms': elapsedMs,
                  'suite_elapsed_ms':
                      DateTime.now().difference(suiteStartedAt).inMilliseconds,
                  if (errors.isNotEmpty) 'errors': errors,
                },
              });
            }
          }

          summaries.add({
            'case_id': caseId,
            'user_id': userId,
            'data_root': dataRoot.path,
            'operation_logs': operationLogs,
            'submitted_fact_ids_by_operation': submittedFactIdsByOperation,
            'cards_by_operation': cardsByOperation,
            'memory_entries': memoryEntries,
            'super_agent_answer': superAgentAnswer,
            'super_agent_tool_calls': superAgentToolCalls,
            'task_status_counts': lastTaskStatusCounts,
            'elapsed_ms': elapsedMs,
            'llm_calls': llmCalls,
          });

          await _writeReplayArtifacts(
            runDir: runDir,
            datasetPath: datasetPath,
            observations: observations,
            summaries: summaries,
            suiteStartedAt: suiteStartedAt,
          );
          stdout.writeln(
            '[serial replay] $caseId done elapsed=${_formatDuration(Duration(milliseconds: elapsedMs))} '
            'observations=${observations.length}',
          );
        }
      } finally {
        LocalTaskExecutor.instance.stop();
        LocalTaskExecutor.maxConcurrencyOverrideForTesting = null;
        if (AppDatabase.isInitialized) {
          await AppDatabase.instance.close();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 240)),
  );
}

bool get _llmEnabled => Platform.environment['MEMEX_EVAL_ENABLE_LLM'] == '1';

Duration _taskWaitTimeoutFor(String? operationType) {
  final fixedSeconds = _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS');
  if (fixedSeconds != null && fixedSeconds > 0) {
    return Duration(seconds: fixedSeconds);
  }
  final unitSeconds = _taskUnitTimeoutSeconds;
  final floorSeconds = _llmEnabled ? 180 : 45;
  final maxSeconds = _taskMaxTimeoutSeconds < floorSeconds
      ? floorSeconds
      : _taskMaxTimeoutSeconds;
  final computedSeconds = _expectedTaskUnits(operationType) * unitSeconds;
  final seconds = computedSeconds < floorSeconds
      ? floorSeconds
      : computedSeconds > maxSeconds
          ? maxSeconds
          : computedSeconds;
  return Duration(seconds: seconds);
}

String get _taskWaitPolicyDescription {
  final fixedSeconds = _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS');
  if (fixedSeconds != null && fixedSeconds > 0) {
    return 'fixed:${_formatDuration(Duration(seconds: fixedSeconds))}';
  }
  return 'dynamic:unit=${_formatDuration(Duration(seconds: _taskUnitTimeoutSeconds))},'
      'max=${_formatDuration(Duration(seconds: _taskMaxTimeoutSeconds))}';
}

Map<String, dynamic> _taskWaitPolicySummary() {
  final fixedSeconds = _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS');
  if (fixedSeconds != null && fixedSeconds > 0) {
    return {
      'mode': 'fixed',
      'timeout_seconds': fixedSeconds,
      'status_interval_seconds': _statusInterval.inSeconds,
    };
  }
  return {
    'mode': 'dynamic',
    'task_unit_timeout_seconds': _taskUnitTimeoutSeconds,
    'max_operation_timeout_seconds': _taskMaxTimeoutSeconds,
    'status_interval_seconds': _statusInterval.inSeconds,
    'expected_task_units': {
      'record': _expectedTaskUnits('record'),
      'post_comment': _expectedTaskUnits('post_comment'),
      'refresh_schedule_aggregation':
          _expectedTaskUnits('refresh_schedule_aggregation'),
      'refresh_knowledge_insights':
          _expectedTaskUnits('refresh_knowledge_insights'),
    },
  };
}

int get _taskUnitTimeoutSeconds =>
    _intFromEnv('MEMEX_EVAL_TASK_UNIT_TIMEOUT_SECONDS') ??
    (_llmEnabled ? 90 : 20);

int get _taskMaxTimeoutSeconds =>
    _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_MAX_SECONDS') ??
    (_llmEnabled ? 900 : 180);

Duration get _statusInterval {
  final seconds = _intFromEnv('MEMEX_EVAL_STATUS_INTERVAL_SECONDS');
  return Duration(seconds: seconds != null && seconds > 0 ? seconds : 30);
}

int _expectedTaskUnits(String? operationType) {
  if (!_llmEnabled) {
    return switch (operationType) {
      'record' => 4,
      'refresh_knowledge_insights' => 2,
      _ => 1,
    };
  }
  return switch (operationType) {
    'record' => 10,
    'post_comment' => 3,
    'refresh_schedule_aggregation' => 2,
    'refresh_knowledge_insights' => 10,
    _ => 1,
  };
}

Future<void> _configureOptionalLlm() async {
  if (!_llmEnabled) {
    await UserStorage.resetLLMConfigs();
    return;
  }

  final baseUrl = Platform.environment['EVAL_LLM_BASE_URL'];
  final apiKey = Platform.environment['EVAL_LLM_API_KEY'];
  final model = Platform.environment['EVAL_LLM_MODEL'] ?? 'mimo-v2-pro';
  if (baseUrl == null || baseUrl.isEmpty || apiKey == null || apiKey.isEmpty) {
    throw StateError(
      'MEMEX_EVAL_ENABLE_LLM=1 requires EVAL_LLM_BASE_URL and EVAL_LLM_API_KEY.',
    );
  }

  await UserStorage.saveLLMConfigs([
    LLMConfig(
      key: LLMConfig.defaultClientKey,
      type: LLMConfig.typeMimo,
      modelId: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      maxTokens: 8192,
      temperature: 0,
    ),
  ]);
}

Future<List<Map<String, dynamic>>> _loadCases(String datasetPath) async {
  final lines = await File(datasetPath).readAsLines();
  final cases = <Map<String, dynamic>>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    cases.add(jsonDecode(trimmed) as Map<String, dynamic>);
  }
  if (cases.isEmpty) {
    throw StateError('No cases found in $datasetPath');
  }
  return cases;
}

String _caseUserId(Map<String, dynamic> evalCase, int caseIndex) {
  final persona = _map(evalCase['persona']);
  final base = persona['user_id']?.toString() ?? 'eval_serial_$caseIndex';
  final safeBase = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return '${safeBase}_${DateTime.now().microsecondsSinceEpoch}_$caseIndex';
}

Future<_TaskWaitResult> _waitForTasksToSettle({
  required int minTasks,
  required Duration timeout,
  required Directory runDir,
  required String caseId,
  required String operationId,
  required DateTime startedAt,
}) async {
  final deadline = DateTime.now().add(timeout);
  var nextStatusAt = DateTime.now();
  var lastTasks = <dynamic>[];
  while (DateTime.now().isBefore(deadline)) {
    final tasks = await LocalTaskExecutor.instance.getTasks(limit: 2000);
    lastTasks = tasks;
    final active = tasks
        .where(
          (task) => ['pending', 'processing', 'retrying'].contains(task.status),
        )
        .toList();
    final now = DateTime.now();
    if (!now.isBefore(nextStatusAt)) {
      await _writeStatusSnapshot(
        runDir: runDir,
        caseId: caseId,
        operationId: operationId,
        minTasks: minTasks,
        timeout: timeout,
        startedAt: startedAt,
        tasks: tasks,
        activeTasks: active,
      );
      stdout.writeln(
        '[serial replay] $caseId/$operationId waiting tasks=${tasks.length}/$minTasks '
        'active=${active.length} status=${_formatStatusCounts(_statusCounts(tasks))} '
        'elapsed=${_formatDuration(now.difference(startedAt))}/'
        '${_formatDuration(timeout)} active_details=${_formatActiveTasks(active)}',
      );
      nextStatusAt = now.add(_statusInterval);
    }
    if (tasks.length >= minTasks && active.isEmpty) {
      return _TaskWaitResult(tasks: tasks, settled: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return _TaskWaitResult(tasks: lastTasks, settled: false);
}

Future<void> _writeStatusSnapshot({
  required Directory runDir,
  required String caseId,
  required String operationId,
  required int minTasks,
  required Duration timeout,
  required DateTime startedAt,
  required List<dynamic> tasks,
  required List<dynamic> activeTasks,
}) async {
  final now = DateTime.now();
  await File(p.join(runDir.path, 'status.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'case_id': caseId,
      'operation_id': operationId,
      'updated_at': now.toIso8601String(),
      'elapsed_ms': now.difference(startedAt).inMilliseconds,
      'timeout_ms': timeout.inMilliseconds,
      'task_count': tasks.length,
      'min_tasks': minTasks,
      'status_counts': _statusCounts(tasks),
      'active_count': activeTasks.length,
      'active_tasks': activeTasks.take(20).map(_taskSummary).toList(),
    }),
    flush: true,
  );
}

Future<_MemoryWaitResult> _waitForMemory({
  required MemexRouter router,
  required List<String> mustIncludeAny,
  required Duration timeout,
}) async {
  final startedAt = DateTime.now();
  final deadline = startedAt.add(timeout);
  var entries = <Map<String, dynamic>>[];
  while (DateTime.now().isBefore(deadline)) {
    entries = _memoryEntries(await _readMemory(router));
    final text = entries.map((entry) => entry['content']).join('\n');
    final matched = mustIncludeAny.isEmpty ||
        mustIncludeAny.any((needle) => _contains(text, needle));
    if (matched) {
      return _MemoryWaitResult(
        matched: true,
        entries: entries,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return _MemoryWaitResult(
    matched: false,
    entries: entries,
    elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
  );
}

Future<Map<String, dynamic>> _readMemory(MemexRouter router) async {
  final result = await router.getMemory();
  return result.valueOrThrow;
}

List<Map<String, dynamic>> _memoryEntries(Map<String, dynamic> memoryData) {
  final entries = <Map<String, dynamic>>[];
  final archived = memoryData['archived_memory']?.toString() ?? '';
  if (archived.trim().isNotEmpty) {
    entries.add({'id': 'archived_memory', 'content': archived});
  }
  for (final raw in _list(memoryData['recent_buffer'])) {
    final map = _map(raw);
    if (map.isNotEmpty) {
      entries.add({
        'id': map['id'] ?? map['source_id'] ?? 'recent_buffer',
        'content': map['content']?.toString() ?? map.toString(),
        if (map['source_ids'] != null) 'source_ids': map['source_ids'],
      });
    } else if (raw.toString().trim().isNotEmpty) {
      entries.add({'id': 'recent_buffer', 'content': raw.toString()});
    }
  }
  return entries;
}

List<Map<String, dynamic>> _sourceSnippetsFromMemory(
  List<Map<String, dynamic>> memoryEntries,
) {
  final snippets = <Map<String, dynamic>>[];
  for (var i = 0; i < memoryEntries.length; i++) {
    final entry = memoryEntries[i];
    final content = entry['content']?.toString() ?? '';
    if (content.trim().isEmpty) continue;
    final id = entry['id']?.toString();
    snippets.add({
      'source_id': id == null || id.isEmpty ? 'memory_${i + 1}' : '$id:$i',
      'snippet': content,
    });
  }
  return snippets;
}

Map<String, dynamic> _cardObservationFromJson(Map<String, dynamic> card) {
  if (card.isEmpty) {
    return {
      'card_type': null,
      'title': null,
      'status': null,
      'fields': const <String, dynamic>{},
    };
  }
  final configs = _list(card['ui_configs']).map(_map).toList();
  final firstConfig = configs.isEmpty ? const <String, dynamic>{} : configs[0];
  return {
    'card_type': firstConfig['template_id'] ?? card['card_type'],
    'title': card['title'],
    'status': card['status'],
    'time': card['time'] ?? card['timestamp'],
    'location': card['address'] ?? card['location'],
    'fields': _map(firstConfig['data']),
  };
}

Future<_ChatObservation> _askSuperAgent({
  required MemexRouter router,
  required String query,
  required bool quickQuery,
}) async {
  final startedAt = DateTime.now();
  final answer = StringBuffer();
  final toolCalls = <Map<String, dynamic>>[];
  final errors = <String>[];
  String? sessionId;
  await for (final event in router.sendMessage(
    query,
    sessionId: sessionId,
    agentName: 'memex_agent',
    scene: 'assistant',
    isQuickQuery: quickQuery,
  )) {
    if (event is ChatSessionCreatedEvent) {
      sessionId = event.sessionId;
    } else if (event is ChatResponseChunkEvent) {
      answer.write(event.text);
    } else if (event is ChatToolCallEvent) {
      toolCalls.add({'name': event.toolName, 'args': _tryDecode(event.args)});
    } else if (event is ChatErrorEvent) {
      errors.add(event.error);
    }
  }
  return _ChatObservation(
    answer: answer.toString(),
    toolCalls: toolCalls,
    errors: errors,
    elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
  );
}

String _queryWithOperationTime(Map<String, dynamic> operation) {
  final query = operation['query']?.toString() ?? '';
  final time = operation['time']?.toString();
  if (time == null || time.isEmpty) return query;
  return '现在是 $time。$query';
}

List<Map<String, dynamic>> _taskTraceEvents(List<dynamic> tasks) {
  return tasks
      .map(
        (task) => {
          'event_type': 'task',
          'task_id': task.id,
          'task_type': task.type,
          'status': task.status,
          'latency_ms': _taskLatencyMs(task),
        },
      )
      .toList();
}

Map<String, dynamic> _operationStats(List<Map<String, dynamic>> operationLogs) {
  final operationTypes = <String>{};
  final inputChannels = <String>{};
  final journeyStages = <String>{};
  final scenarioFamilies = <String>{};
  DateTime? firstTime;
  DateTime? lastTime;
  var recordOperationCount = 0;
  var correctionOperationCount = 0;
  var noiseInputCount = 0;
  var crossDayLinkCount = 0;
  var followUpQueryCount = 0;

  for (final operation in operationLogs) {
    final type = operation['type']?.toString();
    if (type != null && type.isNotEmpty) {
      operationTypes.add(type);
      if (type == 'record') recordOperationCount++;
      if (type == 'ask_super_agent') followUpQueryCount++;
    }
    final channel = operation['channel']?.toString();
    if (channel != null && channel.isNotEmpty) {
      inputChannels.add(channel);
    }
    final journeyStage = operation['journey_stage']?.toString();
    if (journeyStage != null && journeyStage.isNotEmpty) {
      journeyStages.add(journeyStage);
    }
    final scenarioFamily = operation['scenario_family']?.toString();
    if (scenarioFamily != null && scenarioFamily.isNotEmpty) {
      scenarioFamilies.add(scenarioFamily);
    }
    if (operation['is_correction'] == true) correctionOperationCount++;
    if (operation['is_noise'] == true) noiseInputCount++;
    if (operation['cross_day_link'] == true) crossDayLinkCount++;
    final time = DateTime.tryParse(operation['time']?.toString() ?? '');
    if (time != null) {
      firstTime =
          firstTime == null || time.isBefore(firstTime) ? time : firstTime;
      lastTime = lastTime == null || time.isAfter(lastTime) ? time : lastTime;
    }
  }

  final journeySpanDays = firstTime == null || lastTime == null
      ? 0.0
      : lastTime.difference(firstTime).inHours / 24.0;

  return {
    'operation_count': operationLogs.length,
    'operation_types': operationTypes.toList()..sort(),
    'record_operation_count': recordOperationCount,
    'input_channels': inputChannels.toList()..sort(),
    'journey_stages': journeyStages.toList()..sort(),
    'scenario_families': scenarioFamilies.toList()..sort(),
    'correction_operation_count': correctionOperationCount,
    'noise_input_count': noiseInputCount,
    'cross_day_link_count': crossDayLinkCount,
    'follow_up_query_count': followUpQueryCount,
    'journey_start_time': firstTime?.toIso8601String(),
    'journey_end_time': lastTime?.toIso8601String(),
    'journey_span_days': journeySpanDays,
  };
}

List<String> _personaMarkers(Map<String, dynamic> evalCase) {
  final persona = _map(evalCase['persona']);
  final profile = _map(persona['profile']);
  return [
    profile['occupation'],
    profile['city'],
    profile['project'],
    ..._strings(profile['habits']),
  ]
      .whereType<Object>()
      .map((value) => value.toString())
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

List<String> _featureTriggers({
  required List<Map<String, dynamic>> operationLogs,
  required List<Map<String, dynamic>> traceEvents,
  required List<Map<String, dynamic>> memoryEntries,
  required Map<String, dynamic> cardsByOperation,
}) {
  final triggers = <String>{};
  final operationTypes =
      operationLogs.map((operation) => operation['type']?.toString()).toSet();
  final traceNames = <String>{};
  for (final event in traceEvents) {
    for (final key in ['event_type', 'task_type', 'tool_name', 'agent_name']) {
      final value = event[key]?.toString();
      if (value != null && value.isNotEmpty) traceNames.add(value);
    }
  }

  if (operationTypes.contains('record')) triggers.add('record_input');
  if (cardsByOperation.values.any((card) => _map(card).isNotEmpty) ||
      traceNames.contains('card_agent_task')) {
    triggers.add('timeline_card');
  }
  if (memoryEntries.isNotEmpty) triggers.add('memory');
  if (traceNames.contains('pkm_agent_task')) triggers.add('pkm');
  if (traceNames.contains('schedule_refresh_router_task') ||
      traceNames.contains('schedule_aggregator_task') ||
      operationTypes.contains('refresh_schedule_aggregation')) {
    triggers.add('schedule');
  }
  if (traceNames.contains('knowledge_insight_task') ||
      operationTypes.contains('refresh_knowledge_insights')) {
    triggers.add('knowledge_insight');
  }
  if (operationTypes.contains('fetch_timeline')) {
    triggers.add('timeline_browse');
  }
  if (operationTypes.contains('post_comment') ||
      traceNames.contains('process_ai_reply')) {
    triggers.add('comment');
  }
  if (operationTypes.contains('ask_super_agent')) triggers.add('super_agent');
  if (operationTypes.isNotEmpty) triggers.add('cost_trace');

  return triggers.toList()..sort();
}

DateTime? _parseOptionalDateTime(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

Map<String, dynamic> _taskSummary(dynamic task) {
  return {
    'task_id': task.id,
    'task_type': task.type,
    'status': task.status,
    if (task.retryCount != null) 'retry_count': task.retryCount,
    if (task.error != null) 'error': task.error,
  };
}

Future<List<Map<String, dynamic>>> _agentActivityTraceEvents() async {
  final messages = await AgentActivityService.instance.getHistory(limit: 300);
  return messages.reversed
      .map(
        (message) => {
          'event_type': _activityEventType(message.type),
          'activity_type': message.type.name,
          'agent_name': message.agentName,
          'agent_id': message.agentId,
          'scene': message.scene,
          'scene_id': message.sceneId,
          'title': message.title,
          if (_extractToolName(message.content) != null)
            'tool_name': _extractToolName(message.content),
          'latency_ms': 0,
        },
      )
      .toList();
}

String _activityEventType(AgentActivityType type) {
  return switch (type) {
    AgentActivityType.tool_call_reqeust => 'tool_call',
    AgentActivityType.tool_call_response => 'tool_call_response',
    AgentActivityType.agent_start => 'agent_start',
    AgentActivityType.agent_stop => 'agent_stop',
    AgentActivityType.error => 'agent_error',
    AgentActivityType.warn => 'agent_warn',
    AgentActivityType.plan => 'agent_plan',
    AgentActivityType.thought => 'agent_thought',
    AgentActivityType.info => 'agent_info',
    AgentActivityType.thought_chunk => 'agent_thought_chunk',
    AgentActivityType.output_chunk => 'agent_output_chunk',
  };
}

String? _extractToolName(String? content) {
  if (content == null) return null;
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('## ')) {
      final name = trimmed.substring(3).trim();
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

Future<List<Map<String, dynamic>>> _llmCallsForUser(String userId) async {
  final records = await LLMCallRecordService.instance.getAllRecords(
    userId: userId,
  );
  final calls = <Map<String, dynamic>>[];
  for (final record in records) {
    final scene = record['scene']?.toString();
    final sceneId = record['scene_id']?.toString();
    for (final rawCall in (record['calls'] as List? ?? const [])) {
      final call = Map<String, dynamic>.from(rawCall as Map);
      final usage = Map<String, dynamic>.from(
        call['usage'] as Map? ?? const <String, dynamic>{},
      );
      calls.add({
        'agent_name': call['agent_name']?.toString() ?? 'unknown',
        if (call['model'] != null) 'model': call['model'].toString(),
        if (scene != null) 'scene': scene,
        if (sceneId != null) 'scene_id': sceneId,
        'prompt_tokens': _intValue(usage['prompt_tokens']),
        'completion_tokens': _intValue(usage['completion_tokens']),
        'cached_tokens': _intValue(usage['cached_tokens']),
        'thought_tokens': _intValue(usage['thought_tokens']),
        'total_tokens': _intValue(usage['total_tokens']),
        'latency_ms': 0,
      });
    }
  }
  return calls;
}

Future<void> _writeReplayArtifacts({
  required Directory runDir,
  required String datasetPath,
  required List<Map<String, dynamic>> observations,
  required List<Map<String, dynamic>> summaries,
  required DateTime suiteStartedAt,
}) async {
  await File(p.join(runDir.path, 'observations.jsonl')).writeAsString(
    observations.isEmpty ? '' : '${observations.map(jsonEncode).join('\n')}\n',
    flush: true,
  );
  await File(p.join(runDir.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'dataset_path': datasetPath,
      'completed_case_count': summaries.length,
      'elapsed_ms': DateTime.now().difference(suiteStartedAt).inMilliseconds,
      'llm_enabled': _llmEnabled,
      'max_concurrency': 1,
      'task_wait_policy': _taskWaitPolicySummary(),
      'cases': summaries,
    }),
    flush: true,
  );
}

Map<String, int> _statusCounts(List<dynamic> tasks) {
  final counts = <String, int>{};
  for (final task in tasks) {
    final status = task.status?.toString() ?? 'unknown';
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

String _formatStatusCounts(Map<String, dynamic> counts) {
  if (counts.isEmpty) return '-';
  final keys = counts.keys.toList()..sort();
  return keys.map((key) => '$key=${counts[key]}').join(',');
}

String _formatActiveTasks(List<dynamic> tasks) {
  if (tasks.isEmpty) return '-';
  return tasks.take(6).map((task) {
    final retrySuffix = task.retryCount == null || task.retryCount == 0
        ? ''
        : '#retry${task.retryCount}';
    final error = task.error?.toString();
    final errorSuffix = error == null || error.isEmpty
        ? ''
        : ':${error.length > 80 ? '${error.substring(0, 80)}...' : error}';
    return '${task.type}:${task.status}$retrySuffix$errorSuffix';
  }).join(' | ');
}

int _taskLatencyMs(dynamic task) {
  final createdAt = task.createdAt as int?;
  final completedAt = task.completedAt as int?;
  if (createdAt == null || completedAt == null) return 0;
  return (completedAt - createdAt) * 1000;
}

int _intValue(Object? value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      _ => 0,
    };

int? _intFromEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

Object _tryDecode(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

JsonMap _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

List<String> _strings(Object? value) =>
    _list(value).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();

bool _contains(String haystack, String needle) {
  return haystack
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .contains(needle.toLowerCase().replaceAll(RegExp(r'\s+'), ''));
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  if (minutes > 0) {
    return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
  }
  return '${seconds}s';
}

class _TaskWaitResult {
  const _TaskWaitResult({required this.tasks, required this.settled});
  final List<dynamic> tasks;
  final bool settled;
}

class _MemoryWaitResult {
  const _MemoryWaitResult({
    required this.matched,
    required this.entries,
    required this.elapsedMs,
  });
  final bool matched;
  final List<Map<String, dynamic>> entries;
  final int elapsedMs;
}

class _ChatObservation {
  const _ChatObservation({
    required this.answer,
    required this.toolCalls,
    required this.errors,
    required this.elapsedMs,
  });
  final String answer;
  final List<Map<String, dynamic>> toolCalls;
  final List<String> errors;
  final int elapsedMs;
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getTemporaryPath() async => p.join(rootPath, 'tmp');

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(rootPath, 'support');

  @override
  Future<String?> getLibraryPath() async => p.join(rootPath, 'library');

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(rootPath, 'documents');

  @override
  Future<String?> getApplicationCachePath() async => p.join(rootPath, 'cache');

  @override
  Future<String?> getExternalStoragePath() async =>
      p.join(rootPath, 'external');

  @override
  Future<List<String>?> getExternalCachePaths() async => [
        p.join(rootPath, 'external_cache'),
      ];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [p.join(rootPath, 'external_storage')];

  @override
  Future<String?> getDownloadsPath() async => p.join(rootPath, 'downloads');
}

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  var _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

class _EvalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 60);
  }
}
