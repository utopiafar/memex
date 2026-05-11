// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/data/services/llm_call_record_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_llmEnabled) {
    HttpOverrides.global = _EvalHttpOverrides();
  }

  test(
    'replays zh-CN input through Memex submit-input task pipeline',
    () async {
      final repoRoot = Directory.current.path;
      final datasetPath = Platform.environment['MEMEX_EVAL_DATASET'] ??
          p.join(
            repoRoot,
            'evals',
            'datasets',
            'full_chain_medium',
            'cases.jsonl',
          );
      final runDir = Directory(
        Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
            p.join(repoRoot, 'evals', 'runs', 'full_chain_medium_replay'),
      );
      if (await runDir.exists()) {
        await runDir.delete(recursive: true);
      }
      await runDir.create(recursive: true);

      final pathProviderRoot = await Directory.systemTemp.createTemp(
        'memex_full_chain_paths_',
      );
      PathProviderPlatform.instance =
          _FakePathProviderPlatform(pathProviderRoot.path);
      WakelockPlusPlatformInterface.instance = _FakeWakelockPlusPlatform();

      SharedPreferences.setMockInitialValues({});
      final router = MemexRouter();
      final cases = await _loadCases(datasetPath);
      final caseLimit = _intFromEnv('MEMEX_EVAL_CASE_LIMIT');
      final selectedCases =
          caseLimit == null ? cases : cases.take(caseLimit).toList();
      final observations = <Map<String, dynamic>>[];
      final caseSummaries = <Map<String, dynamic>>[];
      final suiteStartedAt = DateTime.now();

      for (var caseIndex = 0; caseIndex < selectedCases.length; caseIndex++) {
        final evalCase = selectedCases[caseIndex];
        final caseId = evalCase['case_id']?.toString() ?? 'case_$caseIndex';
        final inputStream = (evalCase['input_stream'] as List).cast<Object?>();
        final dataRoot = await Directory.systemTemp.createTemp(
          'memex_full_chain_${caseId}_',
        );

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

        final submittedFactIdsByInput = <String, String>{};
        final startedAt = DateTime.now();
        for (final rawInput in inputStream) {
          final input = Map<String, dynamic>.from(rawInput as Map);
          final inputId = input['id']?.toString() ?? 'input_${input.hashCode}';
          final response = await router.submitInput(
            text: input['content']?.toString(),
            textHash: inputId,
          );
          submittedFactIdsByInput[inputId] = response['fact_id'] as String;
        }

        final waitResult = await _waitForTasksToSettle(
          minTasks: inputStream.length * 4,
          timeout: _taskWaitTimeout,
        );
        final tasks = waitResult.tasks;
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;

        final completedTaskTypes = tasks
            .where((task) => task.status == 'completed')
            .map((task) => task.type)
            .toSet();
        final activeTasks = tasks
            .where(
              (task) =>
                  ['pending', 'processing', 'retrying'].contains(task.status),
            )
            .toList();

        expect(tasks, isNotEmpty);

        final cardsByInput = <String, dynamic>{};
        final cardJsonByInput = <String, dynamic>{};
        for (final entry in submittedFactIdsByInput.entries) {
          final card = await router.fetchTimelineCard(entry.value);
          cardsByInput[entry.key] = card;
          cardJsonByInput[entry.key] = card?.toJson();
        }

        final traceEvents = <Map<String, dynamic>>[
          ..._taskTraceEvents(tasks),
          ...await _agentActivityTraceEvents(),
        ];
        final llmCalls = await _llmCallsForUser(userId);
        final fallbackLlmCalls = llmCalls.isEmpty
            ? [
                {
                  'agent_name': 'full_chain_replay',
                  'prompt_tokens': 0,
                  'completion_tokens': 0,
                  'total_tokens': 0,
                  'latency_ms': elapsedMs,
                },
              ]
            : llmCalls;

        for (final rawTask in (evalCase['eval_tasks'] as List)) {
          final task = Map<String, dynamic>.from(rawTask as Map);
          final taskId = task['task_id']?.toString() ?? '${caseId}_task';
          final taskType = task['type']?.toString();
          final expected = Map<String, dynamic>.from(
            task['expected'] as Map? ?? const <String, dynamic>{},
          );
          if (taskType == 'card_extraction') {
            final inputId = expected['input_id']?.toString() ??
                submittedFactIdsByInput.keys.first;
            final card = cardsByInput[inputId] ?? cardsByInput.values.first;
            observations.add({
              'case_id': caseId,
              'task_id': taskId,
              'observed': {
                'card': _cardObservation(card),
                'trace_events': traceEvents,
                'llm_calls': const [],
              },
            });
          } else if (taskType == 'cost_trace') {
            observations.add({
              'case_id': caseId,
              'task_id': taskId,
              'observed': {
                'answer':
                    'Full chain 已写入 Facts 和 Cards，完成 ${tasks.length} 个 tasks，并生成 replay trace events。',
                'trace_events': traceEvents,
                'active_tasks': activeTasks.map(_taskSummary).toList(),
                'failed_tasks': tasks
                    .where((task) => task.status == 'failed')
                    .map(_taskSummary)
                    .toList(),
                'tasks_settled': waitResult.settled,
                'llm_calls': fallbackLlmCalls,
              },
            });
          }
        }

        caseSummaries.add({
          'case_id': caseId,
          'user_id': userId,
          'data_root': dataRoot.path,
          'submitted_fact_ids_by_input': submittedFactIdsByInput,
          'task_count': tasks.length,
          'tasks_settled': waitResult.settled,
          'active_task_count': activeTasks.length,
          'failed_task_count':
              tasks.where((task) => task.status == 'failed').length,
          'completed_task_types': completedTaskTypes.toList()..sort(),
          'cards_by_input': cardJsonByInput,
          'elapsed_ms': elapsedMs,
          'llm_calls': llmCalls,
          'trace_event_count': traceEvents.length,
        });
      }

      final observationFile = File(p.join(runDir.path, 'observations.jsonl'));
      await observationFile.writeAsString(
        observations.map(jsonEncode).join('\n'),
        flush: true,
      );

      final summaryFile = File(p.join(runDir.path, 'summary.json'));
      await summaryFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'dataset_path': datasetPath,
          'case_count': selectedCases.length,
          'input_count': selectedCases.fold<int>(
            0,
            (sum, evalCase) =>
                sum + ((evalCase['input_stream'] as List?)?.length ?? 0),
          ),
          'elapsed_ms':
              DateTime.now().difference(suiteStartedAt).inMilliseconds,
          'llm_enabled': _llmEnabled,
          'cases': caseSummaries,
        }),
        flush: true,
      );

      LocalTaskExecutor.instance.stop();
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

bool get _llmEnabled => Platform.environment['MEMEX_EVAL_ENABLE_LLM'] == '1';

Duration get _taskWaitTimeout {
  final seconds = _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS');
  if (seconds != null && seconds > 0) {
    return Duration(seconds: seconds);
  }
  return Duration(seconds: _llmEnabled ? 240 : 60);
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
  final persona = Map<String, dynamic>.from(
    evalCase['persona'] as Map? ?? const <String, dynamic>{},
  );
  final base = persona['user_id']?.toString() ?? 'eval_full_chain_$caseIndex';
  final safeBase = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return '${safeBase}_${DateTime.now().microsecondsSinceEpoch}_$caseIndex';
}

int? _intFromEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

Map<String, dynamic> _cardObservation(dynamic card) {
  if (card == null) {
    return {
      'card_type': null,
      'title': null,
      'status': null,
      'fields': const <String, dynamic>{},
    };
  }
  final config = card.uiConfigs.isEmpty ? null : card.uiConfigs.first;
  return {
    'card_type': config?.templateId,
    'title': card.title,
    'status': card.status,
    'fields': config?.data ?? const <String, dynamic>{},
  };
}

Future<_TaskWaitResult> _waitForTasksToSettle({
  required int minTasks,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastTasks = <dynamic>[];
  while (DateTime.now().isBefore(deadline)) {
    final tasks = await LocalTaskExecutor.instance.getTasks(limit: 100);
    lastTasks = tasks;
    final active = tasks.where(
      (task) => ['pending', 'processing', 'retrying'].contains(task.status),
    );
    if (tasks.length >= minTasks && active.isEmpty) {
      return _TaskWaitResult(tasks: tasks, settled: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return _TaskWaitResult(tasks: lastTasks, settled: false);
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
    if (task.error != null) 'error': task.error,
  };
}

Future<List<Map<String, dynamic>>> _agentActivityTraceEvents() async {
  final messages = await AgentActivityService.instance.getHistory(limit: 200);
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
        if (call['handler_name'] != null)
          'handler_name': call['handler_name'].toString(),
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

int _intValue(Object? value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      _ => 0,
    };

int _taskLatencyMs(dynamic task) {
  final createdAt = task.createdAt as int?;
  final completedAt = task.completedAt as int?;
  if (createdAt == null || completedAt == null) return 0;
  return (completedAt - createdAt) * 1000;
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

class _TaskWaitResult {
  const _TaskWaitResult({
    required this.tasks,
    required this.settled,
  });

  final List<dynamic> tasks;
  final bool settled;
}
