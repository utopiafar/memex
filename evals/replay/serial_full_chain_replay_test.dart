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
      PathProviderPlatform.instance =
          _FakePathProviderPlatform(pathProviderRoot.path);
      WakelockPlusPlatformInterface.instance = _FakeWakelockPlusPlatform();
      SharedPreferences.setMockInitialValues({});
      LocalTaskExecutor.maxConcurrencyOverrideForTesting = 1;

      final router = MemexRouter();
      final cases = await _loadCases(datasetPath);
      final observations = <Map<String, dynamic>>[];
      final summaries = <Map<String, dynamic>>[];
      final suiteStartedAt = DateTime.now();

      stdout.writeln(
        '[serial replay] start dataset=$datasetPath cases=${cases.length} '
        'llm_enabled=$_llmEnabled task_timeout=${_formatDuration(_taskWaitTimeout)} '
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
          final operationLogs = <Map<String, dynamic>>[];
          Map<String, dynamic> lastTaskStatusCounts = {};
          List<dynamic> lastTasks = const [];
          String superAgentAnswer = '';
          final superAgentToolCalls = <Map<String, dynamic>>[];
          final chatErrors = <String>[];
          var submittedRecords = 0;

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
              final waitResult = await _waitForTasksToSettle(
                minTasks: submittedRecords * 4,
                timeout: _taskWaitTimeout,
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
                'fact_id': factId,
                'tasks_settled': waitResult.settled,
                'task_status_counts': lastTaskStatusCounts,
                'elapsed_ms':
                    DateTime.now().difference(opStartedAt).inMilliseconds,
              });
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
              superAgentToolCalls.addAll(chat.toolCalls);
              chatErrors.addAll(chat.errors);
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'answer': chat.answer,
                'tool_calls': chat.toolCalls,
                'errors': chat.errors,
                'elapsed_ms': chat.elapsedMs,
              });
            } else {
              operationLogs.add({
                'operation_id': opId,
                'type': type,
                'error': 'Unknown operation type.',
              });
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
            if (taskType == 'cost_trace') {
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
              observations.add({
                'case_id': caseId,
                'task_id': taskId,
                'observed': {
                  'answer': superAgentAnswer,
                  'tool_calls': superAgentToolCalls,
                  'trace_events': traceEvents,
                  'llm_calls': const [],
                  'case_elapsed_ms': elapsedMs,
                  'suite_elapsed_ms':
                      DateTime.now().difference(suiteStartedAt).inMilliseconds,
                  if (chatErrors.isNotEmpty) 'errors': chatErrors,
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
    timeout: const Timeout(Duration(minutes: 120)),
  );
}

bool get _llmEnabled => Platform.environment['MEMEX_EVAL_ENABLE_LLM'] == '1';

Duration get _taskWaitTimeout {
  final seconds = _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS');
  if (seconds != null && seconds > 0) {
    return Duration(seconds: seconds);
  }
  return Duration(seconds: _llmEnabled ? 180 : 45);
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
  required String caseId,
  required String operationId,
  required DateTime startedAt,
}) async {
  final deadline = DateTime.now().add(timeout);
  var nextLogAt = DateTime.now().add(const Duration(seconds: 10));
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
    if (now.isAfter(nextLogAt)) {
      stdout.writeln(
        '[serial replay] $caseId/$operationId waiting tasks=${tasks.length}/$minTasks '
        'active=${active.length} status=${_formatStatusCounts(_statusCounts(tasks))} '
        'elapsed=${_formatDuration(now.difference(startedAt))}',
      );
      nextLogAt = now.add(const Duration(seconds: 10));
    }
    if (tasks.length >= minTasks && active.isEmpty) {
      return _TaskWaitResult(tasks: tasks, settled: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return _TaskWaitResult(tasks: lastTasks, settled: false);
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
  return haystack.toLowerCase().replaceAll(RegExp(r'\s+'), '').contains(
        needle.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      );
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
      [
        p.join(rootPath, 'external_storage'),
      ];

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
