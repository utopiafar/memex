import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final config = RunConfig.parse(args);
  if (config.help) {
    stdout.writeln(RunConfig.usage);
    return;
  }

  final startedAt = DateTime.now().toUtc();
  final runId = config.runId ?? _formatRunId(startedAt);
  final outDir = Directory(config.outDir ?? 'evals/runs/$runId');
  await outDir.create(recursive: true);

  var cases = await DatasetLoader.load(config.datasetPath);
  if (config.caseLimit != null) {
    cases = cases.take(config.caseLimit!).toList();
  }
  final judge = (config.useLlmJudge || config.auditDataset)
      ? JsonJudgeFactory.fromConfig(config)
      : null;
  final runner = BenchmarkRunner(config: config, judge: judge);
  final result = await runner.run(cases, runId: runId, startedAt: startedAt);

  await _writeJsonl(
    File('${outDir.path}/outputs.jsonl'),
    result.taskResults.map((e) => e.toJson()),
  );
  await _writeJsonl(File('${outDir.path}/trace.ndjson'), result.traceEvents);
  await File(
    '${outDir.path}/metrics.json',
  ).writeAsString(_prettyJson(result.metrics), flush: true);
  await File(
    '${outDir.path}/report.md',
  ).writeAsString(ReportRenderer.render(result), flush: true);
  await File('${outDir.path}/debug_log.json').writeAsString(
    _prettyJson(_buildDebugLog(result: result, config: config, outDir: outDir)),
    flush: true,
  );

  stdout.writeln('Memex agent eval complete.');
  stdout.writeln('Run ID: $runId');
  stdout.writeln('Cases: ${result.caseCount}, tasks: ${result.taskCount}');
  stdout.writeln(
    'Assertions: ${result.passedAssertions}/${result.totalAssertions} passed '
    '(${_pct(result.assertionPassRate)})',
  );
  stdout.writeln('Report: ${outDir.path}/report.md');
  stdout.writeln('Debug log: ${outDir.path}/debug_log.json');
}

JsonMap _buildDebugLog({
  required BenchmarkResult result,
  required RunConfig config,
  required Directory outDir,
}) =>
    {
      'run_id': result.runId,
      'artifacts': {
        'report': '${outDir.path}/report.md',
        'metrics': '${outDir.path}/metrics.json',
        'task_outputs': '${outDir.path}/outputs.jsonl',
        'trace': '${outDir.path}/trace.ndjson',
        'debug_log': '${outDir.path}/debug_log.json',
      },
      'config': {
        'dataset_path': config.datasetPath,
        'adapter': config.adapter,
        'case_limit': config.caseLimit,
        'replay_observations_path': config.replayObservationsPath,
        'llm_judge_enabled': config.useLlmJudge,
        'audit_dataset': config.auditDataset,
        'audit_sample_limit': config.auditSampleLimit,
        'llm_provider': config.llmProvider,
        'llm_base_url': config.llmBaseUrl,
        'llm_model': config.llmModel,
        'llm_max_tokens': config.llmMaxTokens,
        'llm_timeout_seconds': config.llmTimeoutSeconds,
        'llm_api_key': config.llmApiKey == null ? null : '<redacted>',
      },
      'metrics': result.metrics,
      'task_results': result.taskResults.map((task) => task.toJson()).toList(),
      'trace_events': result.traceEvents,
    };

class RunConfig {
  RunConfig({
    required this.datasetPath,
    required this.adapter,
    required this.useLlmJudge,
    required this.help,
    this.outDir,
    this.runId,
    this.llmBaseUrl,
    this.llmApiKey,
    this.llmModel,
    this.llmProvider,
    this.llmMaxTokens,
    this.llmTimeoutSeconds,
    this.auditDataset = false,
    this.auditSampleLimit,
    this.replayObservationsPath,
    this.caseLimit,
  });

  final String datasetPath;
  final String adapter;
  final bool useLlmJudge;
  final bool help;
  final String? outDir;
  final String? runId;
  final String? llmBaseUrl;
  final String? llmApiKey;
  final String? llmModel;
  final String? llmProvider;
  final int? llmMaxTokens;
  final int? llmTimeoutSeconds;
  final bool auditDataset;
  final int? auditSampleLimit;
  final String? replayObservationsPath;
  final int? caseLimit;

  static const usage = '''
Memex Agent Eval Harness

Usage:
  dart evals/bin/run_agent_benchmark.dart --dataset evals/datasets/v1_medium

Options:
  --dataset PATH       Dataset directory or JSONL file. Default: evals/datasets/v1_medium
  --adapter NAME       Observation adapter: fixture or replay_file. Default: fixture
  --out PATH           Output directory. Default: evals/runs/<run-id>
  --run-id ID          Stable run id for output metadata.
  --use-llm-judge      Enable JSON judge for eligible retrieval / Super Agent QA tasks
                       unless expected.llm_judge is false.
  --llm-provider NAME  Judge provider: anthropic or openai_chat. Env fallback: EVAL_LLM_PROVIDER.
  --llm-base-url URL   Judge base URL. Env fallback: EVAL_LLM_BASE_URL.
  --llm-api-key KEY    Judge API key. Env fallback: EVAL_LLM_API_KEY.
  --llm-model MODEL    Judge model. Env fallback: EVAL_LLM_MODEL or mimo-v2-pro.
  --llm-max-tokens N   Judge max output tokens. Env fallback: EVAL_LLM_MAX_TOKENS. Default: 8192.
  --llm-timeout-sec N  Judge response timeout seconds. Env fallback: EVAL_LLM_TIMEOUT_SECONDS. Default: 180.
  --audit-dataset      Ask the configured LLM judge to audit generated cases for plausibility.
  --audit-sample-limit N
                       Max cases sent to dataset audit. Env fallback: EVAL_AUDIT_SAMPLE_LIMIT. Default: 12.
  --replay-observations PATH
                       JSONL observations generated by a full-chain replay run.
  --case-limit N       Only run the first N cases. Env fallback: EVAL_CASE_LIMIT.
  --help               Print this help.
''';

  static RunConfig parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        throw ArgumentError('Unexpected argument: $arg');
      }
      final key = arg.substring(2);
      if (key == 'help' || key == 'use-llm-judge' || key == 'audit-dataset') {
        flags.add(key);
        continue;
      }
      if (i + 1 >= args.length) {
        throw ArgumentError('Missing value for --$key');
      }
      values[key] = args[++i];
    }

    return RunConfig(
      datasetPath: values['dataset'] ?? 'evals/datasets/v1_medium',
      adapter: values['adapter'] ?? 'fixture',
      outDir: values['out'],
      runId: values['run-id'],
      useLlmJudge: flags.contains('use-llm-judge'),
      help: flags.contains('help'),
      llmBaseUrl:
          values['llm-base-url'] ?? Platform.environment['EVAL_LLM_BASE_URL'],
      llmApiKey:
          values['llm-api-key'] ?? Platform.environment['EVAL_LLM_API_KEY'],
      llmModel: values['llm-model'] ?? Platform.environment['EVAL_LLM_MODEL'],
      llmProvider:
          values['llm-provider'] ?? Platform.environment['EVAL_LLM_PROVIDER'],
      llmMaxTokens: _parseInt(
        values['llm-max-tokens'] ?? Platform.environment['EVAL_LLM_MAX_TOKENS'],
      ),
      llmTimeoutSeconds: _parseInt(
        values['llm-timeout-sec'] ??
            Platform.environment['EVAL_LLM_TIMEOUT_SECONDS'],
      ),
      auditDataset: flags.contains('audit-dataset'),
      auditSampleLimit: _parseInt(
        values['audit-sample-limit'] ??
            Platform.environment['EVAL_AUDIT_SAMPLE_LIMIT'],
      ),
      replayObservationsPath: values['replay-observations'] ??
          Platform.environment['EVAL_REPLAY_OBSERVATIONS'],
      caseLimit: _parseInt(
        values['case-limit'] ?? Platform.environment['EVAL_CASE_LIMIT'],
      ),
    );
  }
}

class DatasetLoader {
  static Future<List<EvalCase>> load(String datasetPath) async {
    final type = await FileSystemEntity.type(datasetPath);
    final file = type == FileSystemEntityType.directory
        ? File(_join(datasetPath, 'cases.jsonl'))
        : File(datasetPath);

    if (!await file.exists()) {
      throw StateError('Dataset file not found: ${file.path}');
    }

    final cases = <EvalCase>[];
    var lineNo = 0;
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      lineNo++;
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      try {
        final json = jsonDecode(trimmed) as JsonMap;
        cases.add(EvalCase.fromJson(json));
      } catch (e) {
        throw FormatException('Invalid JSONL at ${file.path}:$lineNo: $e');
      }
    }
    return cases;
  }
}

class EvalCase {
  EvalCase({
    required this.caseId,
    required this.family,
    required this.raw,
    required this.tasks,
  });

  final String caseId;
  final String family;
  final JsonMap raw;
  final List<EvalTask> tasks;

  factory EvalCase.fromJson(JsonMap json) {
    return EvalCase(
      caseId: json['case_id'] as String,
      family: json['family'] as String,
      raw: json,
      tasks: _list(
        json['eval_tasks'],
      ).map((e) => EvalTask.fromJson(e as JsonMap)).toList(),
    );
  }
}

class EvalTask {
  EvalTask({
    required this.taskId,
    required this.type,
    required this.expected,
    required this.raw,
  });

  final String taskId;
  final String type;
  final JsonMap expected;
  final JsonMap raw;

  factory EvalTask.fromJson(JsonMap json) {
    return EvalTask(
      taskId: json['task_id'] as String,
      type: json['type'] as String,
      expected: _map(json['expected']),
      raw: json,
    );
  }
}

class DatasetSummary {
  DatasetSummary({
    required this.caseCount,
    required this.personaCount,
    required this.inputCount,
    required this.taskCount,
    required this.languages,
    required this.casesByFamily,
    required this.tasksByType,
    required this.personas,
  });

  final int caseCount;
  final int personaCount;
  final int inputCount;
  final int taskCount;
  final List<String> languages;
  final Map<String, int> casesByFamily;
  final Map<String, int> tasksByType;
  final List<JsonMap> personas;

  factory DatasetSummary.fromCases(List<EvalCase> cases) {
    final casesByFamily = <String, int>{};
    final tasksByType = <String, int>{};
    final languages = <String>{};
    final personas = <String, _PersonaSummary>{};
    var inputCount = 0;
    var taskCount = 0;

    for (final evalCase in cases) {
      casesByFamily.update(
        evalCase.family,
        (value) => value + 1,
        ifAbsent: () => 1,
      );

      final language = (evalCase.raw['language'] ??
              evalCase.raw['locale'] ??
              evalCase.raw['target_language'])
          ?.toString();
      if (language != null && language.trim().isNotEmpty) {
        languages.add(language);
      }

      final inputStream = _list(evalCase.raw['input_stream']);
      final operations = _list(evalCase.raw['operations']);
      final recordOperations = operations
          .map(_map)
          .where((operation) => operation['type'] == 'record')
          .toList();
      inputCount += inputStream.length + recordOperations.length;
      taskCount += evalCase.tasks.length;
      for (final task in evalCase.tasks) {
        tasksByType.update(task.type, (value) => value + 1, ifAbsent: () => 1);
      }

      final persona = _map(evalCase.raw['persona']);
      final profile = _map(persona['profile']);
      final userId = (persona['user_id'] ?? evalCase.caseId).toString();
      final summary = personas.putIfAbsent(
        userId,
        () => _PersonaSummary(
          userId: userId,
          occupation: (profile['occupation'] ?? '').toString(),
          city: (profile['city'] ?? '').toString(),
          language: language ?? '',
        ),
      );
      summary.caseCount += 1;
      summary.inputCount += inputStream.length + recordOperations.length;
      summary.taskCount += evalCase.tasks.length;
      for (final rawInput in inputStream) {
        final content = _map(rawInput)['content']?.toString();
        if (content != null &&
            content.trim().isNotEmpty &&
            summary.sampleInputs.length < 2) {
          summary.sampleInputs.add(content);
        }
      }
      for (final operation in recordOperations) {
        final content = operation['content']?.toString();
        if (content != null &&
            content.trim().isNotEmpty &&
            summary.sampleInputs.length < 2) {
          summary.sampleInputs.add(content);
        }
      }
    }

    return DatasetSummary(
      caseCount: cases.length,
      personaCount: personas.length,
      inputCount: inputCount,
      taskCount: taskCount,
      languages: languages.toList()..sort(),
      casesByFamily: _sortedIntMap(casesByFamily),
      tasksByType: _sortedIntMap(tasksByType),
      personas: personas.values.map((p) => p.toJson()).toList()
        ..sort(
          (a, b) => a['user_id'].toString().compareTo(b['user_id'].toString()),
        ),
    );
  }

  JsonMap toJson() => {
        'case_count': caseCount,
        'persona_count': personaCount,
        'input_count': inputCount,
        'task_count': taskCount,
        'languages': languages,
        'cases_by_family': casesByFamily,
        'tasks_by_type': tasksByType,
        'personas': personas,
      };
}

class _PersonaSummary {
  _PersonaSummary({
    required this.userId,
    required this.occupation,
    required this.city,
    required this.language,
  });

  final String userId;
  final String occupation;
  final String city;
  final String language;
  int caseCount = 0;
  int inputCount = 0;
  int taskCount = 0;
  final List<String> sampleInputs = [];

  JsonMap toJson() => {
        'user_id': userId,
        'occupation': occupation,
        'city': city,
        'language': language,
        'case_count': caseCount,
        'input_count': inputCount,
        'task_count': taskCount,
        'sample_inputs': sampleInputs,
      };
}

abstract class ObservationAdapter {
  Future<JsonMap> observe(EvalCase evalCase, EvalTask task);
}

class FixtureObservationAdapter implements ObservationAdapter {
  @override
  Future<JsonMap> observe(EvalCase evalCase, EvalTask task) async {
    final observed = task.raw['fixture_observed'];
    if (observed is JsonMap) return observed;

    final caseFixtures = evalCase.raw['fixture_observed'];
    if (caseFixtures is JsonMap && caseFixtures[task.taskId] is JsonMap) {
      return caseFixtures[task.taskId] as JsonMap;
    }

    throw StateError(
      'No fixture_observed found for ${evalCase.caseId}/${task.taskId}',
    );
  }
}

class ReplayFileObservationAdapter implements ObservationAdapter {
  ReplayFileObservationAdapter(this.path);

  final String path;
  Future<Map<String, JsonMap>>? _indexFuture;

  @override
  Future<JsonMap> observe(EvalCase evalCase, EvalTask task) async {
    final index = await (_indexFuture ??= _loadIndex());
    final key = '${evalCase.caseId}/${task.taskId}';
    final observed = index[key] ?? index[task.taskId];
    if (observed == null) {
      throw StateError('No replay observation found for $key in $path');
    }
    return observed;
  }

  Future<Map<String, JsonMap>> _loadIndex() async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Replay observation file not found: $path');
    }

    final index = <String, JsonMap>{};
    var lineNo = 0;
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      lineNo++;
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      try {
        final row = jsonDecode(trimmed) as JsonMap;
        final taskId = row['task_id']?.toString();
        if (taskId == null || taskId.isEmpty) {
          throw const FormatException('Missing task_id.');
        }
        final observed =
            _map(row['observed']).isNotEmpty ? _map(row['observed']) : row;
        final caseId = row['case_id']?.toString();
        index[taskId] = observed;
        if (caseId != null && caseId.isNotEmpty) {
          index['$caseId/$taskId'] = observed;
        }
      } catch (e) {
        throw FormatException('Invalid replay JSONL at $path:$lineNo: $e');
      }
    }
    return index;
  }
}

class BenchmarkRunner {
  BenchmarkRunner({required this.config, this.judge})
      : adapter = _buildAdapter(config);

  final RunConfig config;
  final ObservationAdapter adapter;
  final JsonJudge? judge;

  static ObservationAdapter _buildAdapter(RunConfig config) {
    switch (config.adapter) {
      case 'fixture':
        return FixtureObservationAdapter();
      case 'replay_file':
        final path = config.replayObservationsPath;
        if (path == null || path.isEmpty) {
          throw ArgumentError(
            '--adapter replay_file requires --replay-observations PATH.',
          );
        }
        return ReplayFileObservationAdapter(path);
      default:
        throw ArgumentError('Unknown adapter: ${config.adapter}');
    }
  }

  Future<BenchmarkResult> run(
    List<EvalCase> cases, {
    required String runId,
    required DateTime startedAt,
  }) async {
    final taskResults = <TaskResult>[];
    final traceEvents = <JsonMap>[];
    final datasetSummary = DatasetSummary.fromCases(cases);
    final runStopwatch = Stopwatch()..start();

    stdout.writeln(
      '[eval] run=$runId adapter=${config.adapter} '
      'cases=${cases.length} tasks=${datasetSummary.taskCount}',
    );

    for (var caseIndex = 0; caseIndex < cases.length; caseIndex++) {
      final evalCase = cases[caseIndex];
      final caseStopwatch = Stopwatch()..start();
      stdout.writeln(
        '[eval] case ${caseIndex + 1}/${cases.length} '
        '${evalCase.caseId} tasks=${evalCase.tasks.length}',
      );
      for (final task in evalCase.tasks) {
        final observed = await adapter.observe(evalCase, task);
        final assertions = await TaskGrader.grade(
          evalCase: evalCase,
          task: task,
          observed: observed,
          judge: config.useLlmJudge ? judge : null,
        );

        taskResults.add(
          TaskResult(
            caseId: evalCase.caseId,
            family: evalCase.family,
            taskId: task.taskId,
            type: task.type,
            assertions: assertions,
            observedSummary: _summarizeObservation(observed),
          ),
        );

        traceEvents.addAll(
          _normalizeTrace(
            runId: runId,
            caseId: evalCase.caseId,
            task: task,
            observed: observed,
          ),
        );
      }
      stdout.writeln(
        '[eval] case done ${evalCase.caseId} '
        'elapsed=${_duration(caseStopwatch.elapsedMilliseconds)}',
      );
    }

    JsonMap? datasetAudit;
    if (config.auditDataset) {
      final activeJudge = judge;
      if (activeJudge == null) {
        throw StateError('Dataset audit requires an LLM judge configuration.');
      }
      stdout.writeln(
        '[eval] dataset audit start sample_limit=${config.auditSampleLimit ?? 12}',
      );
      datasetAudit = await activeJudge.auditDataset(
        cases: cases,
        sampleLimit: config.auditSampleLimit ?? 12,
      );
      stdout.writeln(
        '[eval] dataset audit done '
        'elapsed=${_duration(runStopwatch.elapsedMilliseconds)}',
      );
    }

    final metrics = MetricsAggregator.aggregate(
      runId: runId,
      startedAt: startedAt,
      config: config,
      caseCount: cases.length,
      taskResults: taskResults,
      traceEvents: traceEvents,
      datasetSummary: datasetSummary,
      datasetAudit: datasetAudit,
    );

    return BenchmarkResult(
      runId: runId,
      datasetPath: config.datasetPath,
      adapter: config.adapter,
      caseCount: cases.length,
      taskResults: taskResults,
      traceEvents: traceEvents,
      metrics: metrics,
      datasetSummary: datasetSummary,
      datasetAudit: datasetAudit,
    );
  }
}

class TaskGrader {
  static Future<List<AssertionResult>> grade({
    required EvalCase evalCase,
    required EvalTask task,
    required JsonMap observed,
    JsonJudge? judge,
  }) async {
    final assertions = <AssertionResult>[];
    switch (task.type) {
      case 'card_extraction':
        assertions.addAll(_gradeCardExtraction(evalCase, task, observed));
        break;
      case 'memory_write':
        assertions.addAll(_gradeMemoryWrite(evalCase, task, observed));
        break;
      case 'retrieval_qa':
        assertions.addAll(_gradeRetrievalQa(evalCase, task, observed));
        if (_shouldUseLlmJudge(task, judge)) {
          assertions.add(
            await _gradeWithLlmJudge(evalCase, task, observed, judge!),
          );
        }
        break;
      case 'tool_calling':
        assertions.addAll(_gradeToolCalling(evalCase, task, observed));
        break;
      case 'schedule_refresh':
        assertions.addAll(_gradeScheduleRefresh(evalCase, task, observed));
        break;
      case 'pkm_organization':
        assertions.addAll(_gradePkmOrganization(evalCase, task, observed));
        break;
      case 'super_agent_qa':
        assertions.addAll(_gradeSuperAgentQa(evalCase, task, observed));
        if (_shouldUseLlmJudge(task, judge)) {
          assertions.add(
            await _gradeWithLlmJudge(evalCase, task, observed, judge!),
          );
        }
        break;
      case 'cost_trace':
        assertions.addAll(_gradeCostTrace(evalCase, task, observed));
        break;
      default:
        assertions.add(
          AssertionResult.fail(
            evalCase: evalCase,
            task: task,
            metric: 'unknown_task_type',
            message: 'Unknown task type: ${task.type}',
          ),
        );
    }
    return assertions;
  }

  static List<AssertionResult> _gradeCardExtraction(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final card = _map(observed['card']);
    final assertions = <AssertionResult>[];

    final schemaValid = card['card_type'] is String &&
        card['title'] is String &&
        card['title'].toString().trim().isNotEmpty;
    assertions.add(
      AssertionResult.fromBool(
        evalCase: evalCase,
        task: task,
        metric: 'card_schema_valid',
        passed: schemaValid,
        message: schemaValid
            ? 'Card has required fields.'
            : 'Card schema is incomplete.',
      ),
    );

    final expectedType = expected['card_type']?.toString();
    if (expectedType != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'card_type_accuracy',
          passed: card['card_type'] == expectedType,
          message:
              'Expected card_type=$expectedType, observed=${card['card_type']}.',
        ),
      );
    }

    final expectedStatus = expected['status']?.toString();
    if (expectedStatus != null && expectedStatus.isNotEmpty) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'card_status_accuracy',
          passed: card['status'] == expectedStatus,
          message:
              'Expected card status=$expectedStatus, observed=${card['status']}.',
        ),
      );
    }

    if (expected['time'] != null) {
      final tolerance =
          (expected['time_tolerance_minutes'] as num?)?.toInt() ?? 5;
      final expectedTime = DateTime.parse(expected['time'].toString());
      final observedTimeRaw = card['time'] ?? card['start_time'];
      DateTime? observedTime;
      if (observedTimeRaw != null) {
        observedTime = DateTime.tryParse(observedTimeRaw.toString());
      }
      final diffMinutes = observedTime == null
          ? double.infinity
          : observedTime.difference(expectedTime).inSeconds.abs() / 60.0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'time_parse_accuracy',
          passed: diffMinutes <= tolerance,
          score: observedTime == null ? 0 : max(0, 1 - diffMinutes / tolerance),
          message:
              'Expected time=${expected['time']}, observed=$observedTimeRaw, diff=${diffMinutes.toStringAsFixed(2)}m.',
        ),
      );
    }

    final expectedParticipants = _strings(expected['participants']);
    if (expectedParticipants.isNotEmpty) {
      final observedParticipants = _strings(card['participants']);
      final hits = expectedParticipants
          .where((p) => observedParticipants.any((o) => _contains(o, p)))
          .length;
      final recall = hits / expectedParticipants.length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'participant_recall',
          passed: hits == expectedParticipants.length,
          score: recall,
          message: 'Participant recall $hits/${expectedParticipants.length}.',
        ),
      );
    }

    final expectedLocation = expected['location']?.toString();
    if (expectedLocation != null && expectedLocation.isNotEmpty) {
      final observedLocation = '${card['location'] ?? card['address'] ?? ''}';
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'location_accuracy',
          passed: _contains(observedLocation, expectedLocation),
          message:
              'Expected location contains "$expectedLocation", observed="$observedLocation".',
        ),
      );
    }

    final titleNeedles = _strings(expected['title_contains']);
    if (titleNeedles.isNotEmpty) {
      final title = '${card['title'] ?? ''}';
      final missing = titleNeedles.where((n) => !_contains(title, n)).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'title_constraint_accuracy',
          passed: missing.isEmpty,
          score: titleNeedles.isEmpty
              ? 1
              : (titleNeedles.length - missing.length) / titleNeedles.length,
          message: missing.isEmpty
              ? 'Title constraints satisfied.'
              : 'Title missing: ${missing.join(', ')}.',
        ),
      );
    }

    final mustNotFields = _strings(expected['must_not_fields']);
    if (mustNotFields.isNotEmpty) {
      final present = mustNotFields.where((field) {
        final value = card[field] ?? _map(card['fields'])[field];
        return value != null && value.toString().trim().isNotEmpty;
      }).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'hallucinated_field_absence',
          passed: present.isEmpty,
          message: present.isEmpty
              ? 'No prohibited fields found.'
              : 'Prohibited fields present: ${present.join(', ')}.',
        ),
      );
    }

    final fieldContains = _map(expected['field_contains']);
    for (final entry in fieldContains.entries) {
      final fieldName = entry.key;
      final needles = _strings(entry.value);
      if (needles.isEmpty) continue;
      final value =
          '${card[fieldName] ?? _map(card['fields'])[fieldName] ?? ''}';
      final missing = needles.where((n) => !_contains(value, n)).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'card_field_constraint_accuracy',
          passed: missing.isEmpty,
          score: (needles.length - missing.length) / needles.length,
          message: missing.isEmpty
              ? 'Field $fieldName constraints satisfied.'
              : 'Field $fieldName missing: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedEntities = _strings(expected['entities']);
    if (expectedEntities.isNotEmpty) {
      final entityText = [
        card['title'],
        card['content'],
        card['summary'],
        card['location'],
        card['address'],
        ..._strings(card['participants']),
        ..._map(card['fields']).values,
      ].whereType<Object>().join('\n');
      final hits = expectedEntities.where(
        (entity) => _contains(entityText, entity),
      );
      final recall = hits.length / expectedEntities.length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'entity_recall',
          passed: hits.length == expectedEntities.length,
          score: recall,
          message: 'Entity recall ${hits.length}/${expectedEntities.length}.',
        ),
      );
    }

    final maxLatencyMs = (expected['max_latency_ms'] as num?)?.toInt();
    if (maxLatencyMs != null) {
      final latencyMs = (observed['latency_ms'] as num?)?.toInt() ??
          (card['latency_ms'] as num?)?.toInt() ??
          0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'input_to_card_latency',
          passed: latencyMs <= maxLatencyMs,
          message: 'input_to_card_latency_ms=$latencyMs, max=$maxLatencyMs.',
        ),
      );
    }

    return assertions;
  }

  static List<AssertionResult> _gradeMemoryWrite(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final entries = _list(
      observed['memory_entries'],
    ).map(_memoryEntry).toList();
    final assertions = <AssertionResult>[];

    final mustWrite = _list(expected['must_write']).cast<JsonMap>();
    var matchedMustWrite = 0;
    for (final rule in mustWrite) {
      final match = _findMemoryMatch(entries, _strings(rule['must_include']));
      final passed = match != null;
      if (passed) matchedMustWrite++;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_must_write_recall',
          passed: passed,
          score: passed ? 1 : 0,
          message: passed
              ? 'Found required memory ${rule['id']}.'
              : 'Missing required memory ${rule['id']}.',
        ),
      );

      final sourceIds = _strings(rule['source_ids']);
      if (sourceIds.isNotEmpty) {
        final observedSources = _strings(match?['source_ids']);
        final sourceGrounded = match != null &&
            sourceIds.every((s) => observedSources.contains(s));
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'memory_source_grounding',
            passed: sourceGrounded,
            message: sourceGrounded
                ? 'Memory ${rule['id']} has expected source ids.'
                : 'Memory ${rule['id']} missing expected source ids.',
          ),
        );
      }

      final validFrom = rule['valid_from']?.toString();
      final validUntil = rule['valid_until']?.toString();
      if (validFrom != null || validUntil != null) {
        final observedValidFrom = match?['valid_from']?.toString();
        final observedValidUntil = match?['valid_until']?.toString();
        final fromOk = validFrom == null || observedValidFrom == validFrom;
        final untilOk = validUntil == null || observedValidUntil == validUntil;
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'memory_temporal_validity',
            passed: passed && fromOk && untilOk,
            message:
                'Expected valid_from=$validFrom valid_until=$validUntil, observed valid_from=$observedValidFrom valid_until=$observedValidUntil.',
          ),
        );
      }
    }

    final mustNotWrite = _list(expected['must_not_write']).cast<JsonMap>();
    for (final rule in mustNotWrite) {
      final match = _findMemoryMatch(entries, _strings(rule['must_include']));
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_must_not_write_precision',
          passed: match == null,
          message: match == null
              ? 'Did not write prohibited memory ${rule['id']}.'
              : 'Wrote prohibited memory ${rule['id']}: ${match['content']}',
        ),
      );
    }

    final activeWrittenEntries =
        entries.where((e) => e['status'] != 'superseded').toList();
    final nonEmptyEntries = activeWrittenEntries
        .where((e) => e['content'].toString().trim().isNotEmpty)
        .toList();
    if (expected['evaluate_write_precision'] != false) {
      final writePrecision = nonEmptyEntries.isEmpty
          ? 1.0
          : matchedMustWrite / nonEmptyEntries.length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_write_precision',
          passed: writePrecision >= 0.99,
          score: writePrecision,
          message:
              'Matched $matchedMustWrite required writes across ${nonEmptyEntries.length} written memories.',
        ),
      );
    }

    final duplicateRate = _duplicateRate(
      nonEmptyEntries
          .map((e) => _normalize(e['content'].toString()))
          .where((e) => e.isNotEmpty)
          .toList(),
    );
    final maxDuplicateRate =
        (expected['max_duplicate_rate'] as num?)?.toDouble();
    if (maxDuplicateRate != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_duplicate_rate',
          passed: duplicateRate <= maxDuplicateRate,
          score: 1 - duplicateRate,
          message:
              'Duplicate rate=${duplicateRate.toStringAsFixed(3)}, max=$maxDuplicateRate.',
        ),
      );
    }

    final conflicts = _list(expected['conflicts']);
    for (final rawConflict in conflicts) {
      final conflict = _map(rawConflict);
      final activeEntries = entries.where((e) => e['status'] != 'superseded');
      final latestNeedles = _strings(conflict['latest_should_include']);
      final oldNeedles = _strings(conflict['superseded_should_not_be_active']);
      final latestActive = latestNeedles.isEmpty ||
          _findMemoryMatch(activeEntries, latestNeedles) != null;
      final oldInactive = oldNeedles.isEmpty ||
          _findMemoryMatch(activeEntries, oldNeedles) == null;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_conflict_handling',
          passed: latestActive && oldInactive,
          message:
              'Conflict latestActive=$latestActive oldInactive=$oldInactive.',
        ),
      );
    }

    final sensitiveMustNotWrite = _list(
      expected['sensitive_must_not_write'],
    ).cast<JsonMap>();
    for (final rule in sensitiveMustNotWrite) {
      final match = _findMemoryMatch(entries, _strings(rule['must_include']));
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'sensitive_overwrite_absence',
          passed: match == null,
          message: match == null
              ? 'No sensitive over-write found for ${rule['id']}.'
              : 'Sensitive content was written: ${match['content']}.',
        ),
      );
    }

    return assertions;
  }

  static List<AssertionResult> _gradeRetrievalQa(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final assertions = <AssertionResult>[];
    final expectedSources = _strings(expected['expected_sources']);
    final retrievedSources = _sourceIds(observed['retrieved_sources']);

    if (expectedSources.isNotEmpty) {
      for (final k in [1, 3, 5]) {
        final topK = retrievedSources.take(k).toSet();
        final hit = expectedSources.any(topK.contains);
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'retrieval_hit_at_$k',
            passed: hit,
            score: hit ? 1 : 0,
            message: 'hit@$k=$hit; topK=${topK.join(', ')}.',
          ),
        );
      }

      final firstRank = _firstExpectedRank(retrievedSources, expectedSources);
      final mrr = firstRank == null ? 0.0 : 1.0 / firstRank;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'retrieval_mrr',
          passed: mrr > 0,
          score: mrr,
          message: 'MRR=${mrr.toStringAsFixed(3)}.',
        ),
      );

      final top5 = retrievedSources.take(5).toSet();
      final recallAt5 =
          expectedSources.where(top5.contains).length / expectedSources.length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'retrieval_recall_at_5',
          passed: recallAt5 >= 0.999,
          score: recallAt5,
          message: 'recall@5=${recallAt5.toStringAsFixed(3)}.',
        ),
      );
    }

    final expectedFilters = _map(expected['expected_filters']);
    if (expectedFilters.isNotEmpty) {
      final observedFilters = _map(observed['applied_filters']);
      final filtersOk = _jsonContains(observedFilters, expectedFilters);
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'retrieval_filter_accuracy',
          passed: filtersOk,
          message: filtersOk
              ? 'Observed filters include expected subset.'
              : 'Observed filters did not include expected subset.',
          details: {'expected_subset': expectedFilters},
        ),
      );
    }

    final answer = '${observed['answer'] ?? ''}';
    final mustInclude = _strings(expected['must_include']);
    if (mustInclude.isNotEmpty) {
      final missing = mustInclude.where((n) => !_contains(answer, n)).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'answer_must_include',
          passed: missing.isEmpty,
          score: (mustInclude.length - missing.length) / mustInclude.length,
          message: missing.isEmpty
              ? 'Answer includes required constraints.'
              : 'Answer missing: ${missing.join(', ')}.',
        ),
      );
    }

    final mustNotInclude = _strings(expected['must_not_include']);
    if (mustNotInclude.isNotEmpty) {
      final present =
          mustNotInclude.where((n) => _contains(answer, n)).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'unsupported_claim_absence',
          passed: present.isEmpty,
          message: present.isEmpty
              ? 'No prohibited claims found.'
              : 'Prohibited claims present: ${present.join(', ')}.',
        ),
      );
    }

    if (expected['allowed_uncertainty'] == false) {
      final uncertain = _hasUncertainty(answer);
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'unnecessary_uncertainty_absence',
          passed: !uncertain,
          message: uncertain
              ? 'Answer expressed uncertainty when it was not allowed.'
              : 'Answer did not express unnecessary uncertainty.',
        ),
      );
    }

    if (expected.containsKey('should_abstain')) {
      final shouldAbstain = expected['should_abstain'] == true;
      final abstained = _hasUncertainty(answer);
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'abstention_accuracy',
          passed: abstained == shouldAbstain,
          message:
              'Expected should_abstain=$shouldAbstain, observed_abstained=$abstained.',
        ),
      );
    }

    final citedSources = _sourceIds(observed['cited_sources']);
    if (expectedSources.isNotEmpty) {
      final citedAll = expectedSources.every(citedSources.contains);
      final citedCount = expectedSources.where(citedSources.contains).length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'answer_source_citation',
          passed: citedAll,
          score: citedCount / expectedSources.length,
          message: citedSources.isEmpty
              ? 'No cited sources found; expected ${expectedSources.join(', ')}.'
              : 'Cited sources: ${citedSources.join(', ')}.',
        ),
      );
    }

    if (expected['require_grounded_answer'] == true) {
      final mustNotInclude = _strings(expected['must_not_include']);
      final presentUnsupported = mustNotInclude.where(
        (needle) => _contains(answer, needle),
      );
      final citedExpected = expectedSources.isEmpty ||
          expectedSources.every(citedSources.contains);
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'grounded_answer_rate',
          passed: citedExpected && presentUnsupported.isEmpty,
          score: citedExpected && presentUnsupported.isEmpty ? 1 : 0,
          message:
              'cited_expected=$citedExpected unsupported_claims=${presentUnsupported.join(', ')}.',
        ),
      );
    }

    return assertions;
  }

  static Future<AssertionResult> _gradeWithLlmJudge(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
    JsonJudge judge,
  ) async {
    try {
      final result = await judge.gradeRetrievalQa(
        task: task,
        observed: observed,
      );
      final score = (result['score'] as num?)?.toDouble() ??
          (result['groundedness'] as num?)?.toDouble() ??
          0.0;
      final minScore =
          (task.expected['min_llm_groundedness'] as num?)?.toDouble() ?? 0.75;
      return AssertionResult.fromBool(
        evalCase: evalCase,
        task: task,
        metric: 'llm_grounded_answer_score',
        passed: score >= minScore,
        score: score,
        message: 'LLM judge score=${score.toStringAsFixed(3)}.',
        details: {'judge': result},
      );
    } catch (e) {
      return AssertionResult.fail(
        evalCase: evalCase,
        task: task,
        metric: 'llm_grounded_answer_score',
        message: 'LLM judge failed: ${_redact(e.toString())}',
      );
    }
  }

  static bool _shouldUseLlmJudge(EvalTask task, JsonJudge? judge) {
    if (judge == null) return false;
    if (task.expected['llm_judge'] == false) return false;
    if (task.expected['llm_judge'] == true) return true;
    return task.type == 'retrieval_qa' || task.type == 'super_agent_qa';
  }

  static List<AssertionResult> _gradeToolCalling(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final calls = _list(observed['tool_calls']).map(_map).toList();
    final assertions = <AssertionResult>[];

    final expectedCalls = _list(expected['expected_tool_calls']).map(_map);
    for (final expectedCall in expectedCalls) {
      final name = expectedCall['name']?.toString() ?? '';
      final matching = calls.where((c) => c['name'] == name).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'tool_selection_accuracy',
          passed: matching.isNotEmpty,
          message: matching.isNotEmpty
              ? 'Tool $name was called.'
              : 'Expected tool $name was not called.',
        ),
      );

      final argsContains = _map(expectedCall['args_contains']);
      if (argsContains.isNotEmpty) {
        final argsOk = matching.any(
          (call) => _jsonContains(_map(call['args']), argsContains),
        );
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'tool_args_accuracy',
            passed: argsOk,
            message: argsOk
                ? 'Tool $name args matched expected subset.'
                : 'Tool $name args did not match expected subset.',
            details: {'expected_subset': argsContains},
          ),
        );
      }
    }

    final prohibited = _strings(expected['prohibited_tool_calls']);
    if (prohibited.isNotEmpty) {
      final calledNames = calls.map((c) => c['name']?.toString() ?? '').toSet();
      final present = prohibited.where(calledNames.contains).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'prohibited_tool_absence',
          passed: present.isEmpty,
          message: present.isEmpty
              ? 'No prohibited tools were called.'
              : 'Prohibited tools called: ${present.join(', ')}.',
        ),
      );
    }

    final expectedLabel = expected['router_label']?.toString();
    if (expectedLabel != null && expectedLabel.isNotEmpty) {
      final observedLabel = observed['predicted_router_label']?.toString();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'router_label_accuracy',
          passed: observedLabel == expectedLabel,
          message:
              'Expected router_label=$expectedLabel, observed=$observedLabel.',
        ),
      );
    }

    final maxToolCalls = (expected['max_tool_calls'] as num?)?.toInt();
    if (maxToolCalls != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'tool_call_minimality',
          passed: calls.length <= maxToolCalls,
          message: 'tool_calls=${calls.length}, max=$maxToolCalls.',
        ),
      );
    }

    final expectedTraceEvents = _strings(expected['expected_trace_events']);
    if (expectedTraceEvents.isNotEmpty) {
      final traceTypes = _traceEventNames(observed);
      final missing = expectedTraceEvents
          .where((eventName) => !traceTypes.contains(eventName))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'trace_completeness',
          passed: missing.isEmpty,
          message: missing.isEmpty
              ? 'Trace contains expected events.'
              : 'Trace missing events: ${missing.join(', ')}.',
        ),
      );
    }

    return assertions;
  }

  static List<AssertionResult> _gradeScheduleRefresh(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final assertions = <AssertionResult>[];
    final expectedAction = task.expected['schedule_action']?.toString();
    final observedAction = observed['predicted_schedule_action']?.toString() ??
        observed['predicted_router_label']?.toString();
    if (expectedAction != null && expectedAction.isNotEmpty) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'schedule_refresh_action_accuracy',
          passed: observedAction == expectedAction,
          message:
              'Expected schedule_action=$expectedAction, observed=$observedAction.',
        ),
      );
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'schedule_refresh_unnecessary_absence',
          passed: !(expectedAction == 'skip' && observedAction == 'refresh'),
          message:
              'Expected schedule_action=$expectedAction, observed=$observedAction.',
        ),
      );
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'schedule_refresh_missed_absence',
          passed: !(expectedAction == 'refresh' && observedAction == 'skip'),
          message:
              'Expected schedule_action=$expectedAction, observed=$observedAction.',
        ),
      );
    }
    final maxRefreshCalls =
        (task.expected['max_refresh_tool_calls'] as num?)?.toInt();
    if (maxRefreshCalls != null) {
      final refreshCalls = _list(observed['tool_calls'])
          .map(_map)
          .where((call) => _contains(call['name']?.toString() ?? '', 'refresh'))
          .length;
      final duplicateRate =
          refreshCalls <= 1 ? 0.0 : (refreshCalls - 1) / refreshCalls;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'schedule_refresh_duplicate_rate',
          passed: refreshCalls <= maxRefreshCalls,
          score: 1 - duplicateRate,
          message:
              'refresh_tool_calls=$refreshCalls, max=$maxRefreshCalls, duplicate_rate=${duplicateRate.toStringAsFixed(3)}.',
        ),
      );
    }
    assertions.addAll(_gradeToolCalling(evalCase, task, observed));
    return assertions;
  }

  static List<AssertionResult> _gradePkmOrganization(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final entries = _list(observed['pkm_entries']).map(_map).toList();
    final assertions = <AssertionResult>[];
    final expectedEntries = _list(expected['expected_entries']).map(_map);
    for (final expectedEntry in expectedEntries) {
      final pathNeedles = _strings(expectedEntry['path_contains']);
      final contentNeedles = _strings(expectedEntry['content_contains']);
      final sourceIds = _strings(expectedEntry['source_ids']);
      final matchingByPath = entries.where((entry) {
        final path = entry['path']?.toString() ?? '';
        return pathNeedles.every((needle) => _contains(path, needle));
      }).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'pkm_path_accuracy',
          passed: matchingByPath.isNotEmpty,
          message: matchingByPath.isEmpty
              ? 'No PKM entry path matched ${pathNeedles.join(', ')}.'
              : 'PKM path matched expected constraints.',
        ),
      );
      final contentOk = matchingByPath.any((entry) {
        final content =
            '${entry['title'] ?? ''}\n${entry['content'] ?? ''}'.trim();
        return contentNeedles.every((needle) => _contains(content, needle));
      });
      if (contentNeedles.isNotEmpty) {
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'pkm_content_preservation',
            passed: contentOk,
            score: contentOk ? 1 : 0,
            message: contentOk
                ? 'PKM content preserved expected details.'
                : 'PKM content missing expected details.',
          ),
        );
      }
      if (sourceIds.isNotEmpty) {
        final sourceOk = matchingByPath.any((entry) {
          final observedSources = _strings(entry['source_ids']);
          return sourceIds.every(observedSources.contains);
        });
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'pkm_source_grounding',
            passed: sourceOk,
            message: sourceOk
                ? 'PKM entry has expected source ids.'
                : 'PKM entry missing expected source ids.',
          ),
        );
      }

      final updatedAfter = expectedEntry['updated_after']?.toString();
      if (updatedAfter != null && updatedAfter.isNotEmpty) {
        final freshnessOk = matchingByPath.any((entry) {
          final updatedAt = DateTime.tryParse(
            entry['updated_at']?.toString() ?? '',
          );
          final cutoff = DateTime.tryParse(updatedAfter);
          return updatedAt != null &&
              cutoff != null &&
              !updatedAt.isBefore(cutoff);
        });
        assertions.add(
          AssertionResult.fromBool(
            evalCase: evalCase,
            task: task,
            metric: 'pkm_update_freshness',
            passed: freshnessOk,
            message: freshnessOk
                ? 'PKM entry update time is fresh enough.'
                : 'PKM entry update time is older than expected.',
          ),
        );
      }
    }

    final minEntryCount = (expected['min_entry_count'] as num?)?.toInt();
    final maxEntryCount = (expected['max_entry_count'] as num?)?.toInt();
    if (minEntryCount != null || maxEntryCount != null) {
      final count = entries.length;
      final minOk = minEntryCount == null || count >= minEntryCount;
      final maxOk = maxEntryCount == null || count <= maxEntryCount;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'pkm_merge_split_quality',
          passed: minOk && maxOk,
          message:
              'pkm_entry_count=$count, min=$minEntryCount, max=$maxEntryCount.',
        ),
      );
    }

    final prohibited = _strings(expected['prohibited_content']);
    if (prohibited.isNotEmpty) {
      final allContent = entries
          .map((entry) => '${entry['title'] ?? ''}\n${entry['content'] ?? ''}')
          .join('\n');
      final present = prohibited.where(
        (needle) => _contains(allContent, needle),
      );
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'pkm_prohibited_content_absence',
          passed: present.isEmpty,
          message: present.isEmpty
              ? 'No prohibited PKM content found.'
              : 'Prohibited PKM content found: ${present.join(', ')}.',
        ),
      );
    }

    return assertions;
  }

  static List<AssertionResult> _gradeSuperAgentQa(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final assertions = <AssertionResult>[
      ..._gradeRetrievalQa(evalCase, task, observed),
      ..._gradeToolCalling(evalCase, task, observed),
    ];
    if (task.expected['read_only'] == true) {
      final calls = _list(observed['tool_calls']).map(_map).toList();
      const writeMarkers = [
        'write',
        'update',
        'delete',
        'create',
        'save',
        'add_memory',
        'update_memory',
      ];
      final writeCalls = calls
          .map((call) => call['name']?.toString() ?? '')
          .where(
            (name) => writeMarkers.any((marker) => _contains(name, marker)),
          )
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'super_agent_read_only_compliance',
          passed: writeCalls.isEmpty,
          message: writeCalls.isEmpty
              ? 'Super Agent stayed read-only.'
              : 'Super Agent called write-like tools: ${writeCalls.join(', ')}.',
        ),
      );
    }
    if (task.expected.containsKey('should_clarify') ||
        task.expected.containsKey('should_abstain')) {
      final shouldClarify = task.expected['should_clarify'] == true ||
          task.expected['should_abstain'] == true;
      final answer = '${observed['answer'] ?? ''}';
      final calibrated = _hasUncertainty(answer) == shouldClarify;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'uncertainty_calibration',
          passed: calibrated,
          message:
              'Expected should_clarify_or_abstain=$shouldClarify, observed_uncertain=${_hasUncertainty(answer)}.',
        ),
      );
    }

    final personalizationNeedles = _strings(
      task.expected['personalization_must_include'],
    );
    if (personalizationNeedles.isNotEmpty) {
      final answer = '${observed['answer'] ?? ''}';
      final missing = personalizationNeedles
          .where((needle) => !_contains(answer, needle))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'personalization_accuracy',
          passed: missing.isEmpty,
          score: (personalizationNeedles.length - missing.length) /
              personalizationNeedles.length,
          message: missing.isEmpty
              ? 'Answer contains expected personalized details.'
              : 'Answer missing personalized details: ${missing.join(', ')}.',
        ),
      );
    }
    return assertions;
  }

  static List<AssertionResult> _gradeCostTrace(
    EvalCase evalCase,
    EvalTask task,
    JsonMap observed,
  ) {
    final expected = task.expected;
    final assertions = <AssertionResult>[];
    final llmCalls = _list(observed['llm_calls']).map(_map).toList();
    final traceEvents = _list(observed['trace_events']).map(_map).toList();

    final totalTokens = llmCalls.fold<int>(
      0,
      (sum, call) => sum + ((call['total_tokens'] as num?)?.toInt() ?? 0),
    );
    final maxTotalTokens = (expected['max_total_tokens'] as num?)?.toInt();
    if (maxTotalTokens != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'total_token_budget',
          passed: totalTokens <= maxTotalTokens,
          score: maxTotalTokens == 0
              ? 0
              : max(0, 1 - totalTokens / maxTotalTokens),
          message: 'total_tokens=$totalTokens, max=$maxTotalTokens.',
        ),
      );
    }

    final inputCount = (observed['input_count'] as num?)?.toInt();
    final maxTokensPerInput =
        (expected['max_tokens_per_input'] as num?)?.toDouble();
    if (inputCount != null && inputCount > 0 && maxTokensPerInput != null) {
      final tokensPerInput = totalTokens / inputCount;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'cost_per_input',
          passed: tokensPerInput <= maxTokensPerInput,
          score: max(0, 1 - tokensPerInput / maxTokensPerInput),
          message:
              'tokens_per_input=${tokensPerInput.toStringAsFixed(3)}, max=$maxTokensPerInput.',
        ),
      );
    }

    final latencies = [
      ...llmCalls.map((c) => (c['latency_ms'] as num?)?.toInt() ?? 0),
      ...traceEvents.map((e) => (e['latency_ms'] as num?)?.toInt() ?? 0),
    ];
    final maxLatency = latencies.isEmpty ? 0 : latencies.reduce(max);
    final maxLatencyAllowed = (expected['max_latency_ms'] as num?)?.toInt();
    if (maxLatencyAllowed != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'latency_budget',
          passed: maxLatency <= maxLatencyAllowed,
          message: 'max_latency_ms=$maxLatency, budget=$maxLatencyAllowed.',
        ),
      );
    }

    final toolCalls =
        traceEvents.where((e) => e['event_type'] == 'tool_call').length;
    final maxToolCalls = (expected['max_tool_calls'] as num?)?.toInt();
    if (maxToolCalls != null) {
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'tool_call_budget',
          passed: toolCalls <= maxToolCalls,
          message: 'tool_calls=$toolCalls, max=$maxToolCalls.',
        ),
      );
    }

    if (expected['require_all_tasks_completed'] == true) {
      final taskEvents =
          traceEvents.where((e) => e['event_type'] == 'task').toList();
      final activeTasks = taskEvents
          .where(
            (e) => ['pending', 'processing', 'retrying'].contains(e['status']),
          )
          .length;
      final failedTasks =
          taskEvents.where((e) => e['status'] == 'failed').length;
      final settled = observed['tasks_settled'] != false;
      final activeDetails = _taskIssueSummary(observed['active_tasks']);
      final failedDetails = _taskIssueSummary(observed['failed_tasks']);
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'task_completion_status',
          passed: settled && activeTasks == 0 && failedTasks == 0,
          message:
              'settled=$settled, active_tasks=$activeTasks, failed_tasks=$failedTasks'
              '${activeDetails.isEmpty ? '' : ', active_details=$activeDetails'}'
              '${failedDetails.isEmpty ? '' : ', failed_details=$failedDetails'}.',
        ),
      );
    }

    final maxActiveTaskCount =
        (expected['max_active_task_count'] as num?)?.toInt();
    if (maxActiveTaskCount != null) {
      final activeTaskCount =
          (observed['active_task_count'] as num?)?.toInt() ??
              _list(observed['active_tasks']).length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'active_task_count_budget',
          passed: activeTaskCount <= maxActiveTaskCount,
          message:
              'active_task_count=$activeTaskCount, max=$maxActiveTaskCount.',
        ),
      );
    }

    final maxFailedTaskCount =
        (expected['max_failed_task_count'] as num?)?.toInt();
    if (maxFailedTaskCount != null) {
      final failedTaskCount =
          (observed['failed_task_count'] as num?)?.toInt() ??
              _list(observed['failed_tasks']).length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'failed_task_count_budget',
          passed: failedTaskCount <= maxFailedTaskCount,
          message:
              'failed_task_count=$failedTaskCount, max=$maxFailedTaskCount.',
        ),
      );
    }

    final maxLoopDetectionTasks =
        (expected['max_loop_detection_tasks'] as num?)?.toInt();
    if (maxLoopDetectionTasks != null) {
      final loopDetectionTaskCount =
          (observed['loop_detection_task_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'loop_detection_absence',
          passed: loopDetectionTaskCount <= maxLoopDetectionTasks,
          message:
              'loop_detection_tasks=$loopDetectionTaskCount, max=$maxLoopDetectionTasks.',
        ),
      );
    }

    final maxMaxTurnsTasks = (expected['max_max_turns_tasks'] as num?)?.toInt();
    if (maxMaxTurnsTasks != null) {
      final maxTurnsTaskCount =
          (observed['max_turns_task_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'max_turns_absence',
          passed: maxTurnsTaskCount <= maxMaxTurnsTasks,
          message: 'max_turns_tasks=$maxTurnsTaskCount, max=$maxMaxTurnsTasks.',
        ),
      );
    }

    final taskEvents = traceEvents.where((e) => e['event_type'] == 'task');
    final taskCount = taskEvents.length;
    final retryCount =
        taskEvents.where((e) => e['status'] == 'retrying').length;
    final failedCount = taskEvents.where((e) => e['status'] == 'failed').length;
    final maxRetryRate = (expected['max_retry_rate'] as num?)?.toDouble();
    if (maxRetryRate != null) {
      final retryRate = taskCount == 0 ? 0.0 : retryCount / taskCount;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'retry_rate',
          passed: retryRate <= maxRetryRate,
          score: 1 - retryRate,
          message:
              'retry_rate=${retryRate.toStringAsFixed(3)}, max=$maxRetryRate.',
        ),
      );
    }
    final maxFailedTaskRate =
        (expected['max_failed_task_rate'] as num?)?.toDouble();
    if (maxFailedTaskRate != null) {
      final failedRate = taskCount == 0 ? 0.0 : failedCount / taskCount;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'failed_task_rate',
          passed: failedRate <= maxFailedTaskRate,
          score: 1 - failedRate,
          message:
              'failed_task_rate=${failedRate.toStringAsFixed(3)}, max=$maxFailedTaskRate.',
        ),
      );
    }

    final maxQueueIdleMs = (expected['max_queue_idle_ms'] as num?)?.toInt();
    if (maxQueueIdleMs != null) {
      final queueIdleMs = (observed['queue_idle_ms'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'queue_idle_time',
          passed: queueIdleMs <= maxQueueIdleMs,
          message: 'queue_idle_ms=$queueIdleMs, max=$maxQueueIdleMs.',
        ),
      );
    }

    final maxRootInvariantFailures =
        (expected['max_root_invariant_failures'] as num?)?.toInt();
    if (maxRootInvariantFailures != null) {
      final rootInvariantFailureCount =
          (observed['root_invariant_failure_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'root_invariant_absence',
          passed: rootInvariantFailureCount <= maxRootInvariantFailures,
          message:
              'root_invariant_failures=$rootInvariantFailureCount, max=$maxRootInvariantFailures.',
        ),
      );
    }

    final minRecordOperations =
        (expected['min_record_operations'] as num?)?.toInt();
    if (minRecordOperations != null) {
      final recordOperationCount =
          (observed['record_operation_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'record_operation_coverage',
          passed: recordOperationCount >= minRecordOperations,
          score: min(1, recordOperationCount / max(1, minRecordOperations)),
          message:
              'record_operations=$recordOperationCount, min=$minRecordOperations.',
        ),
      );
    }

    final minOperationSuccessRate =
        (expected['min_operation_success_rate'] as num?)?.toDouble();
    if (minOperationSuccessRate != null) {
      final operationSuccessRate =
          (observed['operation_success_rate'] as num?)?.toDouble() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'operation_success_rate',
          passed: operationSuccessRate >= minOperationSuccessRate,
          score:
              min(1, operationSuccessRate / max(0.01, minOperationSuccessRate)),
          message:
              'operation_success_rate=${operationSuccessRate.toStringAsFixed(3)}, min=$minOperationSuccessRate.',
        ),
      );
    }

    final minOperationSettlementRate =
        (expected['min_operation_settlement_rate'] as num?)?.toDouble();
    if (minOperationSettlementRate != null) {
      final operationSettlementRate =
          (observed['operation_settlement_rate'] as num?)?.toDouble() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'operation_settlement_rate',
          passed: operationSettlementRate >= minOperationSettlementRate,
          score: min(
            1,
            operationSettlementRate / max(0.01, minOperationSettlementRate),
          ),
          message:
              'operation_settlement_rate=${operationSettlementRate.toStringAsFixed(3)}, min=$minOperationSettlementRate.',
        ),
      );
    }

    final minCardMaterializationRate =
        (expected['min_card_materialization_rate'] as num?)?.toDouble();
    if (minCardMaterializationRate != null) {
      final cardMaterializationRate =
          (observed['card_materialization_rate'] as num?)?.toDouble() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'card_materialization_rate',
          passed: cardMaterializationRate >= minCardMaterializationRate,
          score: min(
            1,
            cardMaterializationRate / max(0.01, minCardMaterializationRate),
          ),
          message:
              'card_materialization_rate=${cardMaterializationRate.toStringAsFixed(3)}, min=$minCardMaterializationRate.',
        ),
      );
    }

    final minCardCompletedRate =
        (expected['min_card_completed_rate'] as num?)?.toDouble();
    if (minCardCompletedRate != null) {
      final cardCompletedRate =
          (observed['card_completed_rate'] as num?)?.toDouble() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'card_completed_rate',
          passed: cardCompletedRate >= minCardCompletedRate,
          score: min(1, cardCompletedRate / max(0.01, minCardCompletedRate)),
          message:
              'card_completed_rate=${cardCompletedRate.toStringAsFixed(3)}, min=$minCardCompletedRate.',
        ),
      );
    }

    final minMemoryEntryCount =
        (expected['min_memory_entry_count'] as num?)?.toInt();
    if (minMemoryEntryCount != null) {
      final memoryEntryCount =
          (observed['memory_entry_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'memory_artifact_presence',
          passed: memoryEntryCount >= minMemoryEntryCount,
          score: min(1, memoryEntryCount / max(1, minMemoryEntryCount)),
          message:
              'memory_entries=$memoryEntryCount, min=$minMemoryEntryCount.',
        ),
      );
    }

    final minLlmAgentCount = (expected['min_llm_agent_count'] as num?)?.toInt();
    if (minLlmAgentCount != null) {
      final llmAgentCount = (observed['llm_agent_count'] as num?)?.toInt() ??
          _map(observed['llm_calls_by_agent']).length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'llm_agent_coverage',
          passed: llmAgentCount >= minLlmAgentCount,
          score: min(1, llmAgentCount / max(1, minLlmAgentCount)),
          message: 'llm_agent_count=$llmAgentCount, min=$minLlmAgentCount.',
        ),
      );
    }

    final minToolDiversity = (expected['min_tool_diversity'] as num?)?.toInt();
    if (minToolDiversity != null) {
      final toolDiversity =
          (observed['tool_diversity_count'] as num?)?.toInt() ??
              _map(observed['tool_call_counts_by_name']).length;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'tool_diversity',
          passed: toolDiversity >= minToolDiversity,
          score: min(1, toolDiversity / max(1, minToolDiversity)),
          message: 'tool_diversity=$toolDiversity, min=$minToolDiversity.',
        ),
      );
    }

    final minJourneySpanDays =
        (expected['min_journey_span_days'] as num?)?.toDouble();
    if (minJourneySpanDays != null) {
      final journeySpanDays =
          (observed['journey_span_days'] as num?)?.toDouble() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'journey_time_span_coverage',
          passed: journeySpanDays >= minJourneySpanDays,
          score: min(1, journeySpanDays / max(1, minJourneySpanDays)),
          message:
              'journey_span_days=${journeySpanDays.toStringAsFixed(2)}, min=$minJourneySpanDays.',
        ),
      );
    }

    final expectedOperationTypes = _strings(
      expected['expected_operation_types'],
    );
    if (expectedOperationTypes.isNotEmpty) {
      final observedOperationTypes = _strings(
        observed['operation_types'],
      ).toSet();
      final missing = expectedOperationTypes
          .where((type) => !observedOperationTypes.contains(type))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'app_operation_sequence_completeness',
          passed: missing.isEmpty,
          score: (expectedOperationTypes.length - missing.length) /
              expectedOperationTypes.length,
          message: missing.isEmpty
              ? 'Observed all expected app operation types.'
              : 'Missing operation types: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedChannels = _strings(expected['expected_input_channels']);
    if (expectedChannels.isNotEmpty) {
      final observedChannels = _strings(observed['input_channels']).toSet();
      final missing = expectedChannels.where(
        (type) => !observedChannels.contains(type),
      );
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'input_channel_diversity',
          passed: missing.isEmpty,
          score: (expectedChannels.length - missing.length) /
              expectedChannels.length,
          message: missing.isEmpty
              ? 'Observed all expected input channels.'
              : 'Missing input channels: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedFeatureTriggers = _strings(
      expected['expected_feature_triggers'],
    );
    if (expectedFeatureTriggers.isNotEmpty) {
      final observedFeatureTriggers = _strings(
        observed['feature_triggers'],
      ).toSet();
      final missing = expectedFeatureTriggers
          .where((feature) => !observedFeatureTriggers.contains(feature))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'feature_trigger_coverage',
          passed: missing.isEmpty,
          score: (expectedFeatureTriggers.length - missing.length) /
              expectedFeatureTriggers.length,
          message: missing.isEmpty
              ? 'Observed all expected feature triggers.'
              : 'Missing feature triggers: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedJourneyStages = _strings(expected['expected_journey_stages']);
    if (expectedJourneyStages.isNotEmpty) {
      final observedJourneyStages =
          _strings(observed['journey_stages']).toSet();
      final missing = expectedJourneyStages
          .where((stage) => !observedJourneyStages.contains(stage))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'journey_stage_coverage',
          passed: missing.isEmpty,
          score: (expectedJourneyStages.length - missing.length) /
              expectedJourneyStages.length,
          message: missing.isEmpty
              ? 'Observed all expected journey stages.'
              : 'Missing journey stages: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedScenarioFamilies = _strings(
      expected['expected_scenario_families'],
    );
    if (expectedScenarioFamilies.isNotEmpty) {
      final observedScenarioFamilies = _strings(
        observed['scenario_families'],
      ).toSet();
      final missing = expectedScenarioFamilies
          .where((family) => !observedScenarioFamilies.contains(family))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'scenario_family_coverage',
          passed: missing.isEmpty,
          score: (expectedScenarioFamilies.length - missing.length) /
              expectedScenarioFamilies.length,
          message: missing.isEmpty
              ? 'Observed all expected scenario families.'
              : 'Missing scenario families: ${missing.join(', ')}.',
        ),
      );
    }

    final expectedPersonaMarkers = _strings(
      expected['expected_persona_markers'],
    );
    if (expectedPersonaMarkers.isNotEmpty) {
      final observedPersonaMarkers = _strings(
        observed['persona_markers'],
      ).toSet();
      final missing = expectedPersonaMarkers
          .where((marker) => !observedPersonaMarkers.contains(marker))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'persona_specificity_coverage',
          passed: missing.isEmpty,
          score: (expectedPersonaMarkers.length - missing.length) /
              expectedPersonaMarkers.length,
          message: missing.isEmpty
              ? 'Observed all expected persona-specific markers.'
              : 'Missing persona markers: ${missing.join(', ')}.',
        ),
      );
    }

    final minCrossDayLinks = (expected['min_cross_day_links'] as num?)?.toInt();
    if (minCrossDayLinks != null) {
      final crossDayLinkCount =
          (observed['cross_day_link_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'cross_day_continuity_coverage',
          passed: crossDayLinkCount >= minCrossDayLinks,
          score: min(1, crossDayLinkCount / max(1, minCrossDayLinks)),
          message: 'cross_day_links=$crossDayLinkCount, min=$minCrossDayLinks.',
        ),
      );
    }

    final minCorrectionOperations =
        (expected['min_correction_operations'] as num?)?.toInt();
    if (minCorrectionOperations != null) {
      final correctionOperationCount =
          (observed['correction_operation_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'correction_operation_coverage',
          passed: correctionOperationCount >= minCorrectionOperations,
          score: min(
            1,
            correctionOperationCount / max(1, minCorrectionOperations),
          ),
          message:
              'correction_operations=$correctionOperationCount, min=$minCorrectionOperations.',
        ),
      );
    }

    final minNoiseInputs = (expected['min_noise_inputs'] as num?)?.toInt();
    if (minNoiseInputs != null) {
      final noiseInputCount =
          (observed['noise_input_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'noise_resilience_coverage',
          passed: noiseInputCount >= minNoiseInputs,
          score: min(1, noiseInputCount / max(1, minNoiseInputs)),
          message: 'noise_inputs=$noiseInputCount, min=$minNoiseInputs.',
        ),
      );
    }

    final minFollowUpQueries =
        (expected['min_follow_up_queries'] as num?)?.toInt();
    if (minFollowUpQueries != null) {
      final followUpQueryCount =
          (observed['follow_up_query_count'] as num?)?.toInt() ?? 0;
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'follow_up_query_coverage',
          passed: followUpQueryCount >= minFollowUpQueries,
          score: min(1, followUpQueryCount / max(1, minFollowUpQueries)),
          message:
              'follow_up_queries=$followUpQueryCount, min=$minFollowUpQueries.',
        ),
      );
    }

    final expectedTraceEvents = _strings(expected['expected_trace_events']);
    if (expectedTraceEvents.isNotEmpty) {
      final traceTypes = _traceEventNames(observed);
      final missing = expectedTraceEvents
          .where((eventName) => !traceTypes.contains(eventName))
          .toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'trace_completeness',
          passed: missing.isEmpty,
          message: missing.isEmpty
              ? 'Trace contains expected events.'
              : 'Trace missing events: ${missing.join(', ')}.',
        ),
      );
    }

    final mustInclude = _strings(expected['must_include']);
    if (mustInclude.isNotEmpty) {
      final answer = '${observed['answer'] ?? ''}';
      final missing = mustInclude.where((n) => !_contains(answer, n)).toList();
      assertions.add(
        AssertionResult.fromBool(
          evalCase: evalCase,
          task: task,
          metric: 'cost_answer_must_include',
          passed: missing.isEmpty,
          score: (mustInclude.length - missing.length) / mustInclude.length,
          message: missing.isEmpty
              ? 'Cost trace answer includes required constraints.'
              : 'Cost trace answer missing: ${missing.join(', ')}.',
        ),
      );
    }

    return assertions;
  }
}

abstract class JsonJudge {
  Future<JsonMap> gradeRetrievalQa({
    required EvalTask task,
    required JsonMap observed,
  });

  Future<JsonMap> auditDataset({
    required List<EvalCase> cases,
    required int sampleLimit,
  });
}

class JsonJudgeFactory {
  static JsonJudge fromConfig(RunConfig config) {
    final baseUrl = config.llmBaseUrl;
    final apiKey = config.llmApiKey;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw StateError('Missing judge base URL. Set EVAL_LLM_BASE_URL.');
    }
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('Missing judge API key. Set EVAL_LLM_API_KEY.');
    }

    final provider = _normalizeProvider(config.llmProvider ?? 'anthropic');
    final maxTokens = config.llmMaxTokens ?? 8192;
    final timeoutSeconds = config.llmTimeoutSeconds ?? 180;
    switch (provider) {
      case 'anthropic':
        return AnthropicJsonJudge(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: config.llmModel?.isNotEmpty == true
              ? config.llmModel!
              : 'mimo-v2-pro',
          maxTokens: maxTokens,
          timeoutSeconds: timeoutSeconds,
        );
      case 'openai_chat':
        return OpenAiChatJsonJudge(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: config.llmModel?.isNotEmpty == true
              ? config.llmModel!
              : 'gpt-5.4',
          maxTokens: maxTokens,
          timeoutSeconds: timeoutSeconds,
        );
      default:
        throw ArgumentError(
          'Unsupported judge provider: ${config.llmProvider}. '
          'Use anthropic or openai_chat.',
        );
    }
  }
}

abstract class BaseJsonJudge implements JsonJudge {
  BaseJsonJudge({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.timeoutSeconds,
    HttpClient? client,
  }) : client = client ?? HttpClient();

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final int timeoutSeconds;
  final HttpClient client;

  Future<String> loadJudgePrompt() async {
    final file = File('evals/prompts/judges/grounded_answer.md');
    if (await file.exists()) return file.readAsString();
    return 'Return strict JSON with groundedness, completeness, unsupported_claims, score, reason.';
  }

  Future<String> loadDatasetQualityPrompt() async {
    final file = File('evals/prompts/judges/dataset_quality.md');
    if (await file.exists()) return file.readAsString();
    return 'Audit this eval dataset for plausibility and oracle consistency. Return strict JSON only.';
  }

  JsonMap buildJudgePayload(EvalTask task, JsonMap observed) {
    return {
      'query': task.raw['query'],
      'expected': task.expected,
      'answer': observed['answer'],
      'retrieved_sources': observed['retrieved_sources'],
      'cited_sources': observed['cited_sources'],
      'source_snippets': observed['source_snippets'],
    };
  }

  JsonMap buildDatasetAuditPayload(List<EvalCase> cases, int sampleLimit) {
    final sampledCases = _selectAuditCases(cases, sampleLimit);
    final sampleCases = sampledCases.map(_caseForDatasetAudit).toList();
    return {
      'audit_language_requirement': 'zh-CN',
      'sample_strategy': 'family_round_robin',
      'case_count': cases.length,
      'sample_case_count': sampleCases.length,
      'sampled_case_ids': sampledCases.map((c) => c.caseId).toList(),
      'sampled_families': sampledCases.map((c) => c.family).toSet().toList(),
      'dataset_summary': DatasetSummary.fromCases(cases).toJson(),
      'sample_cases': sampleCases,
    };
  }

  Future<HttpClientResponse> postJson(
    String endpoint,
    JsonMap body, {
    required Map<String, String> headers,
  }) async {
    final request = await client
        .postUrl(Uri.parse(endpoint))
        .timeout(const Duration(seconds: 30));
    request.headers.contentType = ContentType.json;
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode(body));
    return request.close().timeout(Duration(seconds: timeoutSeconds));
  }
}

class AnthropicJsonJudge extends BaseJsonJudge {
  AnthropicJsonJudge({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.maxTokens,
    required super.timeoutSeconds,
    super.client,
  });

  @override
  Future<JsonMap> gradeRetrievalQa({
    required EvalTask task,
    required JsonMap observed,
  }) async {
    final system = await loadJudgePrompt();
    final userPayload = buildJudgePayload(task, observed);
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'temperature': 0,
      'system': system,
      'messages': [
        {
          'role': 'user',
          'content':
              'Grade this Memex retrieval answer. Return JSON only.\n\n${_prettyJson(userPayload)}',
        },
      ],
    };
    final endpoint = _anthropicMessagesEndpoint(baseUrl);
    final response = await postJson(
      endpoint,
      body,
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
    );
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Judge HTTP ${response.statusCode}: ${_redact(responseBody)}',
      );
    }

    final decoded = jsonDecode(responseBody) as JsonMap;
    final text = _extractAnthropicText(decoded);
    final jsonText = _extractJsonObject(text);
    return jsonDecode(jsonText) as JsonMap;
  }

  @override
  Future<JsonMap> auditDataset({
    required List<EvalCase> cases,
    required int sampleLimit,
  }) async {
    final system = await loadDatasetQualityPrompt();
    final userPayload = buildDatasetAuditPayload(cases, sampleLimit);
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'temperature': 0,
      'system': system,
      'messages': [
        {
          'role': 'user',
          'content':
              'Audit this Memex synthetic eval dataset. Return JSON only.\n\n${_prettyJson(userPayload)}',
        },
      ],
    };
    final response = await postJson(
      _anthropicMessagesEndpoint(baseUrl),
      body,
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
    );
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Dataset audit HTTP ${response.statusCode}: ${_redact(responseBody)}',
      );
    }

    final decoded = jsonDecode(responseBody) as JsonMap;
    final text = _extractAnthropicText(decoded);
    final jsonText = _extractJsonObject(text);
    return jsonDecode(jsonText) as JsonMap;
  }
}

class OpenAiChatJsonJudge extends BaseJsonJudge {
  OpenAiChatJsonJudge({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.maxTokens,
    required super.timeoutSeconds,
    super.client,
  });

  @override
  Future<JsonMap> gradeRetrievalQa({
    required EvalTask task,
    required JsonMap observed,
  }) async {
    final system = await loadJudgePrompt();
    final userPayload = buildJudgePayload(task, observed);
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'temperature': 0,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content':
              'Grade this Memex retrieval answer. Return JSON only.\n\n${_prettyJson(userPayload)}',
        },
      ],
    };
    final response = await postJson(
      _openAiChatCompletionsEndpoint(baseUrl),
      body,
      headers: {'authorization': 'Bearer $apiKey'},
    );
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Judge HTTP ${response.statusCode}: ${_redact(responseBody)}',
      );
    }

    final decoded = jsonDecode(responseBody) as JsonMap;
    final text = _extractOpenAiChatText(decoded);
    final jsonText = _extractJsonObject(text);
    return jsonDecode(jsonText) as JsonMap;
  }

  @override
  Future<JsonMap> auditDataset({
    required List<EvalCase> cases,
    required int sampleLimit,
  }) async {
    final system = await loadDatasetQualityPrompt();
    final userPayload = buildDatasetAuditPayload(cases, sampleLimit);
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'temperature': 0,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content':
              'Audit this Memex synthetic eval dataset. Return JSON only.\n\n${_prettyJson(userPayload)}',
        },
      ],
    };
    final response = await postJson(
      _openAiChatCompletionsEndpoint(baseUrl),
      body,
      headers: {'authorization': 'Bearer $apiKey'},
    );
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Dataset audit HTTP ${response.statusCode}: ${_redact(responseBody)}',
      );
    }

    final decoded = jsonDecode(responseBody) as JsonMap;
    final text = _extractOpenAiChatText(decoded);
    final jsonText = _extractJsonObject(text);
    return jsonDecode(jsonText) as JsonMap;
  }
}

class AssertionResult {
  AssertionResult({
    required this.caseId,
    required this.family,
    required this.taskId,
    required this.taskType,
    required this.metric,
    required this.passed,
    required this.message,
    this.score,
    this.details = const {},
  });

  final String caseId;
  final String family;
  final String taskId;
  final String taskType;
  final String metric;
  final bool passed;
  final String message;
  final num? score;
  final JsonMap details;

  factory AssertionResult.fromBool({
    required EvalCase evalCase,
    required EvalTask task,
    required String metric,
    required bool passed,
    required String message,
    num? score,
    JsonMap details = const {},
  }) {
    return AssertionResult(
      caseId: evalCase.caseId,
      family: task.type,
      taskId: task.taskId,
      taskType: task.type,
      metric: metric,
      passed: passed,
      message: message,
      score: score,
      details: details,
    );
  }

  factory AssertionResult.fail({
    required EvalCase evalCase,
    required EvalTask task,
    required String metric,
    required String message,
    JsonMap details = const {},
  }) {
    return AssertionResult.fromBool(
      evalCase: evalCase,
      task: task,
      metric: metric,
      passed: false,
      message: message,
      score: 0,
      details: details,
    );
  }

  JsonMap toJson() => {
        'case_id': caseId,
        'family': family,
        'task_id': taskId,
        'task_type': taskType,
        'metric': metric,
        'passed': passed,
        if (score != null) 'score': score,
        'message': message,
        if (details.isNotEmpty) 'details': details,
      };
}

class TaskResult {
  TaskResult({
    required this.caseId,
    required this.family,
    required this.taskId,
    required this.type,
    required this.assertions,
    required this.observedSummary,
  });

  final String caseId;
  final String family;
  final String taskId;
  final String type;
  final List<AssertionResult> assertions;
  final JsonMap observedSummary;

  bool get passed => assertions.every((a) => a.passed);

  JsonMap toJson() => {
        'case_id': caseId,
        'family': family,
        'task_id': taskId,
        'type': type,
        'passed': passed,
        'observed_summary': observedSummary,
        'assertions': assertions.map((a) => a.toJson()).toList(),
      };
}

class BenchmarkResult {
  BenchmarkResult({
    required this.runId,
    required this.datasetPath,
    required this.adapter,
    required this.caseCount,
    required this.taskResults,
    required this.traceEvents,
    required this.metrics,
    required this.datasetSummary,
    this.datasetAudit,
  });

  final String runId;
  final String datasetPath;
  final String adapter;
  final int caseCount;
  final List<TaskResult> taskResults;
  final List<JsonMap> traceEvents;
  final JsonMap metrics;
  final DatasetSummary datasetSummary;
  final JsonMap? datasetAudit;

  int get taskCount => taskResults.length;
  int get totalAssertions =>
      taskResults.fold(0, (sum, task) => sum + task.assertions.length);
  int get passedAssertions => taskResults.fold(
        0,
        (sum, task) => sum + task.assertions.where((a) => a.passed).length,
      );
  double get assertionPassRate =>
      totalAssertions == 0 ? 0 : passedAssertions / totalAssertions;
}

class MetricsAggregator {
  static JsonMap aggregate({
    required String runId,
    required DateTime startedAt,
    required RunConfig config,
    required int caseCount,
    required List<TaskResult> taskResults,
    required List<JsonMap> traceEvents,
    required DatasetSummary datasetSummary,
    JsonMap? datasetAudit,
  }) {
    final byFamily = <String, _Bucket>{};
    final byMetric = <String, _Bucket>{};
    final total = _Bucket();

    for (final task in taskResults) {
      for (final assertion in task.assertions) {
        total.add(assertion);
        byFamily.putIfAbsent(assertion.family, _Bucket.new).add(assertion);
        byMetric.putIfAbsent(assertion.metric, _Bucket.new).add(assertion);
      }
    }

    final llmCalls =
        traceEvents.where((e) => e['event_type'] == 'llm_call').toList();
    final llmJudgeAssertionCount =
        byMetric['llm_grounded_answer_score']?.total ?? 0;
    final latencies = traceEvents
        .map((e) => (e['latency_ms'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final tokenTotals = llmCalls
        .map((e) => (e['total_tokens'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    var replayElapsedMs = 0.0;
    var replayCaseElapsedTotalMs = 0.0;
    for (final task in taskResults) {
      final summary = task.observedSummary;
      final suiteElapsed = summary['suite_elapsed_ms'];
      if (suiteElapsed is num && suiteElapsed > replayElapsedMs) {
        replayElapsedMs = suiteElapsed.toDouble();
      }
      final caseElapsed = summary['case_elapsed_ms'];
      if (task.type == 'cost_trace' && caseElapsed is num) {
        replayCaseElapsedTotalMs += caseElapsed.toDouble();
      }
    }
    final benchmarkElapsedMs =
        DateTime.now().toUtc().difference(startedAt.toUtc()).inMilliseconds;
    final observability = _aggregateObservability(taskResults);

    return {
      'run_id': runId,
      'started_at': startedAt.toIso8601String(),
      'benchmark_elapsed_ms': benchmarkElapsedMs,
      if (replayElapsedMs > 0) 'replay_elapsed_ms': replayElapsedMs.round(),
      if (replayCaseElapsedTotalMs > 0)
        'replay_case_elapsed_total_ms': replayCaseElapsedTotalMs.round(),
      'dataset_path': config.datasetPath,
      'adapter': config.adapter,
      'evidence_level': _evidenceLevel(
        adapter: config.adapter,
        datasetAudit: datasetAudit,
      ),
      'observation_contract':
          config.adapter == 'fixture' ? 'fixture_observed' : 'replay_observed',
      'llm_judge_enabled': config.useLlmJudge,
      'llm_judge_policy': config.useLlmJudge
          ? 'retrieval_and_super_agent_qa_unless_expected_llm_judge_false'
          : 'disabled',
      'llm_judge_assertion_count': llmJudgeAssertionCount,
      if (config.useLlmJudge) ...{
        'llm_judge_provider': _normalizeProvider(
          config.llmProvider ?? 'anthropic',
        ),
        'llm_judge_model': config.llmModel,
        'llm_judge_max_tokens': config.llmMaxTokens ?? 8192,
        'llm_judge_timeout_seconds': config.llmTimeoutSeconds ?? 180,
      },
      'case_count': caseCount,
      'task_count': taskResults.length,
      'dataset_summary': datasetSummary.toJson(),
      if (datasetAudit != null) 'dataset_audit': datasetAudit,
      if (observability.isNotEmpty) 'observability': observability,
      'assertions': total.toJson(),
      'by_family': byFamily.map((k, v) => MapEntry(k, v.toJson())),
      'by_metric': byMetric.map((k, v) => MapEntry(k, v.toJson())),
      'cost_trace': {
        'llm_call_count': llmCalls.length,
        'tool_call_count':
            traceEvents.where((e) => e['event_type'] == 'tool_call').length,
        'avg_latency_ms': _average(latencies),
        'p95_latency_ms': _percentile(latencies, 0.95),
        'avg_total_tokens': _average(tokenTotals),
        'total_tokens': tokenTotals.fold<double>(0, (a, b) => a + b).round(),
      },
    };
  }

  static JsonMap _aggregateObservability(List<TaskResult> taskResults) {
    final summaries = taskResults
        .where((task) => task.type == 'cost_trace')
        .map((task) => task.observedSummary)
        .toList();
    if (summaries.isEmpty) return {};

    int sumInt(String key) => summaries.fold<int>(
          0,
          (sum, summary) => sum + ((summary[key] as num?)?.toInt() ?? 0),
        );

    double ratio({
      required String numeratorKey,
      required String denominatorKey,
    }) {
      final denominator = sumInt(denominatorKey);
      if (denominator == 0) return 0;
      return sumInt(numeratorKey) / denominator;
    }

    Map<String, int> sumCountMap(String key) {
      final result = <String, int>{};
      for (final summary in summaries) {
        for (final entry in _map(summary[key]).entries) {
          result[entry.key] =
              (result[entry.key] ?? 0) + ((entry.value as num?)?.toInt() ?? 0);
        }
      }
      return _sortedIntMap(result);
    }

    return {
      'case_count': summaries.length,
      'journey_execution': {
        'operation_count': sumInt('operation_count'),
        'successful_operation_count': sumInt('successful_operation_count'),
        'errored_operation_count': sumInt('errored_operation_count'),
        'operation_success_rate': ratio(
          numeratorKey: 'successful_operation_count',
          denominatorKey: 'operation_count',
        ),
        'task_wait_operation_count': sumInt('task_wait_operation_count'),
        'task_wait_settled_count': sumInt('task_wait_settled_count'),
        'operation_settlement_rate': ratio(
          numeratorKey: 'task_wait_settled_count',
          denominatorKey: 'task_wait_operation_count',
        ),
        'record_operation_count': sumInt('record_operation_count'),
        'operation_elapsed_ms_by_type': _aggregateOperationElapsed(summaries),
      },
      'task_health': {
        'active_task_count': sumInt('active_task_count'),
        'failed_task_count': sumInt('failed_task_count'),
        'retrying_task_count': sumInt('retrying_task_count'),
        'loop_detection_task_count': sumInt('loop_detection_task_count'),
        'max_turns_task_count': sumInt('max_turns_task_count'),
        'max_retry_count': summaries.fold<int>(
          0,
          (maxRetry, summary) => max(
            maxRetry,
            (summary['max_retry_count'] as num?)?.toInt() ?? 0,
          ),
        ),
        'task_type_counts': sumCountMap('task_type_counts'),
        'active_task_type_counts': sumCountMap('active_task_type_counts'),
        'failed_task_type_counts': sumCountMap('failed_task_type_counts'),
        'retrying_task_type_counts': sumCountMap('retrying_task_type_counts'),
      },
      'test_framework': {
        'root_invariant_checked_count': sumInt('root_invariant_checked_count'),
        'root_invariant_failure_count': sumInt('root_invariant_failure_count'),
      },
      'artifact_health': {
        'submitted_record_count': sumInt('submitted_record_count'),
        'resolved_card_count': sumInt('resolved_card_count'),
        'completed_card_count': sumInt('completed_card_count'),
        'titled_card_count': sumInt('titled_card_count'),
        'missing_card_count': sumInt('missing_card_count'),
        'card_materialization_rate': ratio(
          numeratorKey: 'resolved_card_count',
          denominatorKey: 'submitted_record_count',
        ),
        'card_completed_rate': ratio(
          numeratorKey: 'completed_card_count',
          denominatorKey: 'submitted_record_count',
        ),
        'card_status_counts': sumCountMap('card_status_counts'),
        'memory_entry_count': sumInt('memory_entry_count'),
        'memory_source_linked_entry_count':
            sumInt('memory_source_linked_entry_count'),
        'memory_content_chars': sumInt('memory_content_chars'),
      },
      'llm_and_tool': {
        'llm_calls_by_agent': sumCountMap('llm_calls_by_agent'),
        'llm_tokens_by_agent': sumCountMap('llm_tokens_by_agent'),
        'cached_token_count': sumInt('cached_token_count'),
        'thought_token_count': sumInt('thought_token_count'),
        'tool_call_counts_by_name': sumCountMap('tool_call_counts_by_name'),
      },
    };
  }

  static JsonMap _aggregateOperationElapsed(List<JsonMap> summaries) {
    final byType = <String, _ElapsedBucket>{};
    for (final summary in summaries) {
      for (final entry
          in _map(summary['operation_elapsed_ms_by_type']).entries) {
        final value = _map(entry.value);
        final count = (value['count'] as num?)?.toInt() ?? 0;
        final avgMs = (value['avg_ms'] as num?)?.toDouble() ?? 0;
        final maxMs = (value['max_ms'] as num?)?.toInt() ?? 0;
        if (count == 0) continue;
        byType.putIfAbsent(entry.key, _ElapsedBucket.new).add(
              count: count,
              totalMs: avgMs * count,
              maxMs: maxMs,
            );
      }
    }
    final entries = byType.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(
      entries.map((entry) => MapEntry(entry.key, entry.value.toJson())),
    );
  }

  static Map<String, int> _sortedIntMap(Map<String, int> values) {
    return Map.fromEntries(
      values.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
}

class _Bucket {
  int passed = 0;
  int total = 0;
  double scoreSum = 0;
  int scoreCount = 0;

  void add(AssertionResult assertion) {
    total++;
    if (assertion.passed) passed++;
    if (assertion.score != null) {
      scoreSum += assertion.score!.toDouble();
      scoreCount++;
    }
  }

  JsonMap toJson() => {
        'passed': passed,
        'total': total,
        'pass_rate': total == 0 ? 0 : passed / total,
        if (scoreCount > 0) 'avg_score': scoreSum / scoreCount,
      };
}

class _ElapsedBucket {
  int count = 0;
  double totalMs = 0;
  int maxMs = 0;

  void add({
    required int count,
    required double totalMs,
    required int maxMs,
  }) {
    this.count += count;
    this.totalMs += totalMs;
    if (maxMs > this.maxMs) this.maxMs = maxMs;
  }

  JsonMap toJson() => {
        'count': count,
        'avg_ms': count == 0 ? 0 : totalMs / count,
        'max_ms': maxMs,
      };
}

class ReportRenderer {
  static String render(BenchmarkResult result) {
    final buffer = StringBuffer();
    final assertions = _map(result.metrics['assertions']);
    final cost = _map(result.metrics['cost_trace']);
    buffer.writeln('# Memex Agent Eval 实验报告');
    buffer.writeln();

    _writeConclusion(buffer, result, assertions, cost);
    _writeExperimentQuestion(buffer, result);
    _writeDatasetAndCost(buffer, result, assertions, cost);
    _writeMetricDefinitions(buffer, result);
    _writeResultData(buffer, result, cost);
    _writeObservabilityBreakdown(buffer, result);

    final failures = _failures(result);
    buffer.writeln('## 失败样本');
    buffer.writeln();
    if (failures.isEmpty) {
      buffer.writeln('没有失败断言。');
    } else {
      for (final failure in failures) {
        buffer.writeln(
          '- `${failure.taskId}` / `${failure.metric}`：${_zhFailureMessage(failure)}',
        );
      }
    }
    buffer.writeln();

    _writeFailureInvestigation(buffer, failures);
    _writeExperimentDetails(buffer, result, assertions);
    _writeDatasetAudit(buffer, result.datasetAudit);
    _writeDatasetAppendix(buffer, result);
    return '${buffer.toString().trimRight()}\n';
  }

  static void _writeExperimentQuestion(
    StringBuffer buffer,
    BenchmarkResult result,
  ) {
    final question = result.adapter == 'replay_file'
        ? '真实 Memex 链路从用户输入到后台任务、卡片产物和 trace 记录是否能稳定闭环。'
        : '固定观察数据能否稳定验证 grader、指标聚合和报告结构，作为后续回归对照。';

    buffer.writeln('## 实验问题与背景');
    buffer.writeln();
    buffer.writeln('- 本次要回答的问题：$question');
    buffer.writeln(
      '- 背景：Agent 系统的质量不能只看最终回答，需要同时看 memory、retrieval、router、tool call、trace、成本和失败模式。',
    );
    buffer.writeln(
      '- 评估对象：`${result.adapter}` adapter，数据集 `${result.datasetPath}`。',
    );
    buffer.writeln();
  }

  static void _writeDatasetAndCost(
    StringBuffer buffer,
    BenchmarkResult result,
    JsonMap assertions,
    JsonMap cost,
  ) {
    final summary = result.datasetSummary;
    buffer.writeln('## 数据集与成本规模');
    buffer.writeln();
    buffer.writeln('| 项目 | 数值 |');
    buffer.writeln('| --- | ---: |');
    buffer.writeln('| Persona | ${summary.personaCount} |');
    buffer.writeln('| Case | ${summary.caseCount} |');
    buffer.writeln('| 用户输入 | ${summary.inputCount} |');
    buffer.writeln('| Eval task | ${summary.taskCount} |');
    buffer.writeln('| 断言 | ${assertions['total']} |');
    buffer.writeln('| LLM 调用 | ${cost['llm_call_count']} |');
    if ((result.metrics['llm_judge_assertion_count'] as num? ?? 0) > 0) {
      buffer.writeln(
        '| LLM Judge 断言 | ${result.metrics['llm_judge_assertion_count']} |',
      );
    }
    buffer.writeln('| Tool 调用 | ${cost['tool_call_count']} |');
    buffer.writeln('| 实际 token | ${cost['total_tokens'] ?? 0} |');
    if (result.metrics['replay_elapsed_ms'] != null) {
      buffer.writeln(
        '| ${_replayTimeLabel(result)} | ${_duration(result.metrics['replay_elapsed_ms'])} |',
      );
    }
    buffer.writeln(
      '| Benchmark 评分耗时 | ${_duration(result.metrics['benchmark_elapsed_ms'])} |',
    );
    buffer.writeln();
    buffer.writeln(
      '- 数据语言：${summary.languages.isEmpty ? '未声明' : summary.languages.join(', ')}',
    );
    buffer.writeln('- Token 估算：${_tokenEstimate(cost)}');
    buffer.writeln();
  }

  static void _writeMetricDefinitions(
    StringBuffer buffer,
    BenchmarkResult result,
  ) {
    buffer.writeln('## 指标口径');
    buffer.writeln();
    buffer.writeln('### 场景口径');
    buffer.writeln();
    buffer.writeln('| 场景 | 评估目标 |');
    buffer.writeln('| --- | --- |');
    final byFamily = _map(result.metrics['by_family']);
    for (final key in byFamily.keys.toList()..sort()) {
      buffer.writeln(
        '| ${_scenarioLabel(key)} | ${_scenarioDescription(key)} |',
      );
    }
    buffer.writeln();

    buffer.writeln('### 关键指标口径');
    buffer.writeln();
    buffer.writeln('| 场景 | 类别 | 指标 | 含义 |');
    buffer.writeln('| --- | --- | --- | --- |');
    final byMetric = _map(result.metrics['by_metric']);
    for (final key in byMetric.keys.toList()
      ..sort((a, b) => _metricSortKey(a).compareTo(_metricSortKey(b)))) {
      buffer.writeln(
        '| ${_metricScenario(key)} | ${_metricCategory(key)} | `$key` | '
        '${_metricDescription(key)} |',
      );
    }
    buffer.writeln();
  }

  static void _writeResultData(
    StringBuffer buffer,
    BenchmarkResult result,
    JsonMap cost,
  ) {
    buffer.writeln('## 结果数据');
    buffer.writeln();
    buffer.writeln('### 分场景结果');
    buffer.writeln();
    buffer.writeln('| 场景 | 通过 | 总数 | 通过率 | 平均分 |');
    buffer.writeln('| --- | ---: | ---: | ---: | ---: |');
    final byFamily = _map(result.metrics['by_family']);
    for (final entry in byFamily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final bucket = _map(entry.value);
      buffer.writeln(
        '| ${_scenarioLabel(entry.key)} | ${bucket['passed']} | '
        '${bucket['total']} | '
        '${_pct((bucket['pass_rate'] as num?)?.toDouble() ?? 0)} | '
        '${_score(bucket['avg_score'])} |',
      );
    }
    buffer.writeln();

    buffer.writeln('### 关键指标结果');
    buffer.writeln();
    buffer.writeln('| 场景 | 类别 | 指标 | 通过 | 总数 | 通过率 | 平均分 |');
    buffer.writeln('| --- | --- | --- | ---: | ---: | ---: | ---: |');
    final byMetric = _map(result.metrics['by_metric']);
    for (final entry in byMetric.entries.toList()
      ..sort(
        (a, b) => _metricSortKey(a.key).compareTo(_metricSortKey(b.key)),
      )) {
      final bucket = _map(entry.value);
      buffer.writeln(
        '| ${_metricScenario(entry.key)} | ${_metricCategory(entry.key)} | '
        '`${entry.key}` | ${bucket['passed']} | ${bucket['total']} | '
        '${_pct((bucket['pass_rate'] as num?)?.toDouble() ?? 0)} | '
        '${_score(bucket['avg_score'])} |',
      );
    }
    buffer.writeln();

    buffer.writeln('### 成本与 Trace');
    buffer.writeln();
    buffer.writeln('- LLM 调用次数：${cost['llm_call_count']}');
    buffer.writeln('- 工具调用次数：${cost['tool_call_count']}');
    buffer.writeln('- Token 总量：${cost['total_tokens']}');
    buffer.writeln('- 单次 LLM 平均 token：${_score(cost['avg_total_tokens'])}');
    buffer.writeln('- 平均延迟：${_score(cost['avg_latency_ms'])} ms');
    buffer.writeln('- P95 延迟：${_score(cost['p95_latency_ms'])} ms');
    if (result.metrics['replay_elapsed_ms'] != null) {
      buffer.writeln(
        '- ${_replayTimeLabel(result)}：${_duration(result.metrics['replay_elapsed_ms'])}',
      );
    }
    if (result.metrics['replay_case_elapsed_total_ms'] != null) {
      buffer.writeln(
        '- Case 观察耗时累计：${_duration(result.metrics['replay_case_elapsed_total_ms'])}',
      );
    }
    buffer.writeln(
      '- Benchmark 评分耗时：${_duration(result.metrics['benchmark_elapsed_ms'])}',
    );
    buffer.writeln();
  }

  static void _writeObservabilityBreakdown(
    StringBuffer buffer,
    BenchmarkResult result,
  ) {
    final observability = _map(result.metrics['observability']);
    if (observability.isEmpty) return;

    final journey = _map(observability['journey_execution']);
    final taskHealth = _map(observability['task_health']);
    final testFramework = _map(observability['test_framework']);
    final artifactHealth = _map(observability['artifact_health']);
    final llmAndTool = _map(observability['llm_and_tool']);
    buffer.writeln('### 观测指标分层');
    buffer.writeln();
    buffer.writeln('| 类别 | 指标 | 数值 |');
    buffer.writeln('| --- | --- | ---: |');
    _writeObservationRow(
      buffer,
      '旅程执行',
      '操作成功率',
      _pct((journey['operation_success_rate'] as num?)?.toDouble() ?? 0),
    );
    _writeObservationRow(
      buffer,
      '旅程执行',
      '需等待操作收敛率',
      _pct((journey['operation_settlement_rate'] as num?)?.toDouble() ?? 0),
    );
    _writeObservationRow(
      buffer,
      '旅程执行',
      '记录操作数',
      '${journey['record_operation_count'] ?? 0}',
    );
    _writeObservationRow(
      buffer,
      '后台任务',
      'active / failed / retrying',
      '${taskHealth['active_task_count'] ?? 0} / '
          '${taskHealth['failed_task_count'] ?? 0} / '
          '${taskHealth['retrying_task_count'] ?? 0}',
    );
    _writeObservationRow(
      buffer,
      '后台任务',
      'loopDetection / maxTurns',
      '${taskHealth['loop_detection_task_count'] ?? 0} / '
          '${taskHealth['max_turns_task_count'] ?? 0}',
    );
    _writeObservationRow(
      buffer,
      '测试框架',
      'root invariant failures / checks',
      '${testFramework['root_invariant_failure_count'] ?? 0} / '
          '${testFramework['root_invariant_checked_count'] ?? 0}',
    );
    _writeObservationRow(
      buffer,
      '产物健康',
      'Card materialized / completed',
      '${_pct((artifactHealth['card_materialization_rate'] as num?)?.toDouble() ?? 0)} / '
          '${_pct((artifactHealth['card_completed_rate'] as num?)?.toDouble() ?? 0)}',
    );
    _writeObservationRow(
      buffer,
      '产物健康',
      'Memory entries / sourced',
      '${artifactHealth['memory_entry_count'] ?? 0} / '
          '${artifactHealth['memory_source_linked_entry_count'] ?? 0}',
    );
    _writeObservationRow(
      buffer,
      '成本行为',
      '缓存 token / thought token',
      '${llmAndTool['cached_token_count'] ?? 0} / '
          '${llmAndTool['thought_token_count'] ?? 0}',
    );
    buffer.writeln();

    _writeTopCountMap(
      buffer,
      title: '任务类型分布',
      counts: _map(taskHealth['task_type_counts']),
    );
    _writeTopCountMap(
      buffer,
      title: 'Active 任务类型',
      counts: _map(taskHealth['active_task_type_counts']),
    );
    _writeTopCountMap(
      buffer,
      title: '失败任务类型',
      counts: _map(taskHealth['failed_task_type_counts']),
    );
    _writeTopCountMap(
      buffer,
      title: 'LLM 调用 by agent',
      counts: _map(llmAndTool['llm_calls_by_agent']),
    );
    _writeTopCountMap(
      buffer,
      title: 'Token by agent',
      counts: _map(llmAndTool['llm_tokens_by_agent']),
    );
    _writeTopCountMap(
      buffer,
      title: 'Tool 调用 by name',
      counts: _map(llmAndTool['tool_call_counts_by_name']),
    );

    final elapsedByType = _map(journey['operation_elapsed_ms_by_type']);
    if (elapsedByType.isNotEmpty) {
      buffer.writeln('#### 操作耗时分布');
      buffer.writeln();
      buffer.writeln('| Operation | Count | Avg | Max |');
      buffer.writeln('| --- | ---: | ---: | ---: |');
      for (final entry in elapsedByType.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
        final bucket = _map(entry.value);
        buffer.writeln(
          '| `${entry.key}` | ${bucket['count'] ?? 0} | '
          '${_duration(bucket['avg_ms'])} | ${_duration(bucket['max_ms'])} |',
        );
      }
      buffer.writeln();
    }
  }

  static void _writeObservationRow(
    StringBuffer buffer,
    String category,
    String metric,
    String value,
  ) {
    buffer.writeln('| $category | $metric | $value |');
  }

  static void _writeTopCountMap(
    StringBuffer buffer, {
    required String title,
    required JsonMap counts,
  }) {
    if (counts.isEmpty) return;
    buffer.writeln('#### $title');
    buffer.writeln();
    buffer.writeln('| Item | Count |');
    buffer.writeln('| --- | ---: |');
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = ((b.value as num?)?.toInt() ?? 0)
            .compareTo((a.value as num?)?.toInt() ?? 0);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    for (final entry in entries.take(12)) {
      buffer.writeln(
        '| `${_escapeTable(entry.key)}` | ${(entry.value as num?)?.toInt() ?? 0} |',
      );
    }
    buffer.writeln();
  }

  static void _writeExperimentDetails(
    StringBuffer buffer,
    BenchmarkResult result,
    JsonMap assertions,
  ) {
    buffer.writeln('## 实验详情');
    buffer.writeln();
    buffer.writeln('### 运行信息');
    buffer.writeln();
    buffer.writeln('- 运行 ID：`${result.runId}`');
    buffer.writeln('- 数据集：`${result.datasetPath}`');
    buffer.writeln('- 观察适配器：`${result.adapter}`');
    buffer.writeln(
      '- 证据等级：${_evidenceLevelDescription(result.metrics['evidence_level']?.toString())}',
    );
    buffer.writeln('- 本地完整日志：`evals/runs/${result.runId}/debug_log.json`');
    buffer.writeln('- 本地 Trace：`evals/runs/${result.runId}/trace.ndjson`');
    buffer.writeln('- 本地断言明细：`evals/runs/${result.runId}/outputs.jsonl`');
    buffer.writeln('- 场景样本数：${result.caseCount}');
    buffer.writeln('- 评估任务数：${result.taskCount}');
    if (result.metrics['replay_elapsed_ms'] != null) {
      buffer.writeln(
        '- ${_replayTimeLabel(result)}：${_duration(result.metrics['replay_elapsed_ms'])}',
      );
    }
    buffer.writeln(
      '- Benchmark 评分耗时：${_duration(result.metrics['benchmark_elapsed_ms'])}',
    );
    buffer.writeln(
      '- 断言通过：${assertions['passed']}/${assertions['total']} '
      '（${_pct((assertions['pass_rate'] as num?)?.toDouble() ?? 0)}）',
    );
    if (result.metrics['llm_judge_enabled'] == true) {
      buffer.writeln(
        '- LLM Judge：`${result.metrics['llm_judge_provider']}` / '
        '`${result.metrics['llm_judge_model'] ?? '(未指定)'}` / '
        'max_tokens=${result.metrics['llm_judge_max_tokens']}',
      );
      buffer.writeln(
        '- LLM Judge 任务策略：`${result.metrics['llm_judge_policy']}`',
      );
      buffer.writeln(
        '- LLM Judge 断言数：${result.metrics['llm_judge_assertion_count']}',
      );
    }
    buffer.writeln();

    buffer.writeln('### 场景任务明细');
    buffer.writeln();
    final tasksByType = <String, List<TaskResult>>{};
    for (final task in result.taskResults) {
      tasksByType.putIfAbsent(task.type, () => []).add(task);
    }
    for (final entry in tasksByType.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      buffer.writeln('#### ${_scenarioLabel(entry.key)}');
      buffer.writeln();
      buffer.writeln('| Case | Task | 结果 | 失败断言数 |');
      buffer.writeln('| --- | --- | --- | ---: |');
      for (final task in entry.value) {
        final failed = task.assertions.where((a) => !a.passed).length;
        buffer.writeln(
          '| `${task.caseId}` | `${task.taskId}` | ${task.passed ? '通过' : '未通过'} | $failed |',
        );
      }
      buffer.writeln();
    }
  }

  static void _writeConclusion(
    StringBuffer buffer,
    BenchmarkResult result,
    JsonMap assertions,
    JsonMap cost,
  ) {
    final passRate = (assertions['pass_rate'] as num?)?.toDouble() ?? 0;
    final failed = ((assertions['total'] as num?)?.toInt() ?? 0) -
        ((assertions['passed'] as num?)?.toInt() ?? 0);
    final evidenceLevel = result.metrics['evidence_level']?.toString();
    final verdict = _runVerdict(
      passRate: passRate,
      evidenceLevel: evidenceLevel,
    );

    buffer.writeln('## 结论');
    buffer.writeln();
    buffer.writeln('- $verdict');
    buffer.writeln('- 证据等级：${_evidenceLevelDescription(evidenceLevel)}。');
    buffer.writeln(
      '- 本次覆盖 ${result.caseCount} 个 case、${result.taskCount} 个 eval task，'
      '断言通过率 ${_pct(passRate)}。',
    );
    buffer.writeln(
      '- 失败断言数：$failed；Token 总量：${cost['total_tokens'] ?? 0}；'
      'LLM 调用次数：${cost['llm_call_count'] ?? 0}；'
      '工具调用次数：${cost['tool_call_count'] ?? 0}。',
    );
    if ((result.metrics['llm_judge_assertion_count'] as num? ?? 0) > 0) {
      buffer.writeln(
        '- LLM Judge 断言数：${result.metrics['llm_judge_assertion_count']}。',
      );
    }
    final audit = result.datasetAudit;
    final auditScore = (audit?['overall_score'] as num?)?.toDouble();
    if (auditScore != null) {
      final auditVerdict = auditScore >= 0.8
          ? '数据质量审计通过'
          : '数据质量审计未达 0.8，不能只按断言全绿判断为强 benchmark';
      buffer.writeln('- $auditVerdict：overall=${_score(auditScore)}。');
      final reason = audit?['reason']?.toString();
      if (reason != null && reason.isNotEmpty) {
        buffer.writeln('- 审计摘要：$reason');
      }
    }
    if (result.metrics['replay_elapsed_ms'] != null) {
      buffer.writeln(
        '- ${_replayTimeLabel(result)}：${_duration(result.metrics['replay_elapsed_ms'])}；'
        'Benchmark 评分耗时：${_duration(result.metrics['benchmark_elapsed_ms'])}。',
      );
    }
    final firstFailures = result.taskResults
        .expand((task) => task.assertions)
        .where((assertion) => !assertion.passed)
        .take(3)
        .toList();
    if (firstFailures.isNotEmpty) {
      buffer.writeln('- 主要失败项：');
      for (final failure in firstFailures) {
        buffer.writeln(
          '  - `${failure.taskId}` / `${failure.metric}`：${_zhFailureMessage(failure)}',
        );
      }
    }
    buffer.writeln();
  }

  static String _replayTimeLabel(BenchmarkResult result) =>
      result.adapter == 'replay_file' ? 'Replay 实测耗时' : '观察数据耗时';

  static void _writeDatasetAppendix(
    StringBuffer buffer,
    BenchmarkResult result,
  ) {
    final summary = result.datasetSummary;
    buffer.writeln('## 附录：数据集与 Persona 示例');
    buffer.writeln();
    buffer.writeln(
      '- 数据语言：${summary.languages.isEmpty ? '未声明' : summary.languages.join(', ')}',
    );
    buffer.writeln('- Persona 数：${summary.personaCount}');
    buffer.writeln('- 输入条数：${summary.inputCount}');
    buffer.writeln('- Eval task 数：${summary.taskCount}');
    buffer.writeln(
      '- Case family 分布：${_formatCountMap(summary.casesByFamily)}',
    );
    buffer.writeln('- Task type 分布：${_formatCountMap(summary.tasksByType)}');
    buffer.writeln();
    buffer.writeln('| Persona | 职业 | 城市 | 语言 | Case | 输入 | Task | 示例输入 |');
    buffer.writeln('| --- | --- | --- | --- | ---: | ---: | ---: | --- |');
    final personaRows = summary.personas.take(20);
    for (final persona in personaRows) {
      final samples = _strings(persona['sample_inputs']).take(2).join('<br>');
      buffer.writeln(
        '| `${persona['user_id']}` | ${persona['occupation']} | ${persona['city']} | '
        '${persona['language']} | ${persona['case_count']} | ${persona['input_count']} | '
        '${persona['task_count']} | ${_escapeTable(samples)} |',
      );
    }
    if (summary.personas.length > 20) {
      buffer.writeln();
      buffer.writeln('仅展示前 20 个 Persona。');
    }
    buffer.writeln();
  }

  static void _writeDatasetAudit(StringBuffer buffer, JsonMap? audit) {
    if (audit == null) return;

    buffer.writeln('## 数据质量审计');
    buffer.writeln();
    buffer.writeln('- 总体分：${_score(audit['overall_score'])}');
    buffer.writeln('- 语言一致性：${_score(audit['language_consistency'])}');
    buffer.writeln('- Persona 可信度：${_score(audit['persona_plausibility'])}');
    buffer.writeln('- 输入自然度：${_score(audit['input_naturalness'])}');
    buffer.writeln('- Oracle 一致性：${_score(audit['oracle_consistency'])}');
    if (audit['reason'] != null) {
      buffer.writeln('- 审计结论：${audit['reason']}');
    }
    final notes = _strings(audit['coverage_notes']);
    if (notes.isNotEmpty) {
      buffer.writeln('- 覆盖备注：${notes.join('；')}');
    }
    buffer.writeln();

    final issues = _list(audit['issues']).map(_map).toList();
    buffer.writeln('### 审计问题');
    buffer.writeln();
    if (issues.isEmpty) {
      buffer.writeln('模型审计未发现明显数据质量问题。');
    } else {
      for (final issue in issues.take(12)) {
        buffer.writeln(
          '- `${issue['case_id'] ?? '-'}` / ${issue['severity'] ?? '-'}：'
          '${issue['issue'] ?? '-'}；建议：${issue['suggestion'] ?? '-'}',
        );
      }
    }
    buffer.writeln();

    final reviews = _list(audit['sample_reviews']).map(_map).toList();
    if (reviews.isNotEmpty) {
      buffer.writeln('### 抽样 Case 评价');
      buffer.writeln();
      buffer.writeln('| Case | 分数 | 理由 |');
      buffer.writeln('| --- | ---: | --- |');
      for (final review in reviews.take(12)) {
        buffer.writeln(
          '| `${review['case_id'] ?? '-'}` | ${_score(review['score'])} | '
          '${_escapeTable(review['reason']?.toString() ?? '-')} |',
        );
      }
      buffer.writeln();
    }
  }

  static List<AssertionResult> _failures(BenchmarkResult result) {
    return result.taskResults
        .expand((task) => task.assertions)
        .where((assertion) => !assertion.passed)
        .take(20)
        .toList();
  }

  static void _writeFailureInvestigation(
    StringBuffer buffer,
    List<AssertionResult> failures,
  ) {
    if (failures.isEmpty) return;

    final metrics = failures.map((failure) => failure.metric).toSet();
    buffer.writeln('## 问题排查与建议');
    buffer.writeln();
    buffer.writeln('### 排查过程');
    buffer.writeln();
    buffer.writeln(
      '- 先按失败 metric 分组，再回看 `outputs.jsonl` / `debug_log.json` 中的 task result、assertion message 和 trace events。',
    );
    if (metrics.contains('task_completion_status')) {
      buffer.writeln(
        '- 对全链路失败，优先查看 cost task 中的 `settled`、`active_tasks`、`failed_tasks`，再关联同一 case 的 card 断言。',
      );
    }
    if (metrics.contains('root_invariant_absence')) {
      buffer.writeln(
        '- 对 root invariant 失败，先看 `operation_logs[].root_invariant`，确认当前 `FileSystemService.dataRoot`、Fact 文件路径和 case data root 是否一致。',
      );
    }
    if (metrics.contains('card_schema_valid') ||
        metrics.contains('card_status_accuracy') ||
        metrics.contains('title_constraint_accuracy')) {
      buffer.writeln(
        '- 对 card 失败，检查对应 `input_id` 是否能通过提交返回的 fact id 找到 card，以及 card 是否停留在 processing/null。',
      );
    }
    if (metrics.contains('memory_must_not_write_precision') ||
        metrics.contains('memory_write_precision')) {
      buffer.writeln(
        '- 对 memory 失败，检查写入 memory 的 source_ids 和内容是否来自临时输入或显式“不要当成长期习惯”的输入。',
      );
    }
    buffer.writeln();

    buffer.writeln('### 结论');
    buffer.writeln();
    final conclusions = <String>[];
    if (metrics.contains('task_completion_status')) {
      conclusions.add(
        '全链路主要问题是后台任务未在预算时间内全部收敛，后续 card 断言出现 null/缺字段更像链路未完成的下游现象。',
      );
      if (failures.any(
        (failure) => failure.message.contains('loopDetection'),
      )) {
        conclusions.add(
          'active task 中出现 loopDetection，说明至少部分 agent task 卡在重复工具调用保护上，而不是普通网络超时。',
        );
      }
    }
    if (metrics.contains('root_invariant_absence')) {
      conclusions.add(
        '测试框架观测到 data root 不变量失败；这类问题优先归类为实验框架/环境隔离问题，不能直接当作 agent 能力退化。',
      );
    }
    if (metrics.contains('card_schema_valid') ||
        metrics.contains('card_status_accuracy')) {
      conclusions.add(
        'Card 相关失败集中在未生成、未完成或无法按输入来源取回，优先怀疑 task 生命周期、card agent 落盘和 fact_id/card_id 关联。',
      );
    }
    if (metrics.contains('title_constraint_accuracy')) {
      conclusions.add('标题关键词缺失说明即使 card 生成成功，也需要继续验证输入关键信息是否进入标题或结构化字段。');
    }
    if (metrics.contains('memory_must_not_write_precision') ||
        metrics.contains('memory_write_precision')) {
      conclusions.add('Memory 写入边界仍需加强：临时状态或显式反例会被误写成长记忆。');
    }
    if (metrics.contains('total_token_budget') ||
        metrics.contains('latency_budget') ||
        metrics.contains('tool_call_budget')) {
      conclusions.add('成本类失败需要和 trace 一起看，判断是必要工具链过长还是重复调用。');
    }
    if (conclusions.isEmpty) {
      conclusions.add('当前失败未命中特定内置模式，需要结合 debug log 逐 case 追 trace。');
    }
    for (final conclusion in conclusions) {
      buffer.writeln('- $conclusion');
    }
    buffer.writeln();

    buffer.writeln('### 修改建议');
    buffer.writeln();
    final suggestions = <String>[];
    if (metrics.contains('task_completion_status')) {
      suggestions.add(
        '给 LocalTaskExecutor / task handler 增加按 case 可检索的任务状态摘要，明确 pending、processing、retrying 的阻塞点和最后一次错误。',
      );
      suggestions.add(
        '在 replay harness 里保留每个 active task 的 type、status、attempt、updated_at，便于区分真实超时和观察窗口太短。',
      );
      if (failures.any(
        (failure) => failure.message.contains('loopDetection'),
      )) {
        suggestions.add(
          '针对 loopDetection case，优先检查 card_agent / pkm_agent 的工具调用终止条件，避免同一工具连续调用 5 次后进入 retrying。',
        );
      }
    }
    if (metrics.contains('root_invariant_absence')) {
      suggestions.add(
        '先修复 replay harness 的用户切换、workspace root 初始化和 FileSystemService root 切换，再重新跑同一数据集。',
      );
    }
    if (metrics.contains('card_schema_valid') ||
        metrics.contains('card_status_accuracy') ||
        metrics.contains('title_constraint_accuracy')) {
      suggestions.add(
        '检查 submitInput 返回的 fact_id 到 TimelineCard 的关联路径，确认 card agent 完成后会把 status 从 processing 推进到 completed。',
      );
      suggestions.add(
        '为 card agent 增加最小字段契约测试：title、status、source/fact 关联、关键主题词进入 title 或结构化字段。',
      );
    }
    if (metrics.contains('memory_must_not_write_precision') ||
        metrics.contains('memory_write_precision')) {
      suggestions.add(
        '在 memory write prompt / schema 中显式区分长期偏好、一次性状态和用户明确否定长期化的输入。',
      );
      suggestions.add(
        '给 memory 写入增加 temporal_scope / confidence / source span 字段，低置信或短期事实默认不进入长期记忆。',
      );
    }
    if (metrics.contains('total_token_budget') ||
        metrics.contains('latency_budget') ||
        metrics.contains('tool_call_budget')) {
      suggestions.add('对高成本 case 按 trace 聚合 agent/tool 调用，优先消除重复检索和重复 PKM 整理。');
    }
    if (suggestions.isEmpty) {
      suggestions.add('保留失败 case 的 debug log，下一轮按 case_id 从 trace 入口继续定位。');
    }
    for (final suggestion in suggestions) {
      buffer.writeln('- $suggestion');
    }
    buffer.writeln();
  }
}

String _scenarioLabel(String key) {
  switch (key) {
    case 'card_extraction':
      return 'Card 抽取';
    case 'memory_write':
      return '记忆写入';
    case 'retrieval_qa':
      return '检索问答';
    case 'tool_calling':
      return '路由 / 工具调用';
    case 'schedule_refresh':
      return '日程刷新';
    case 'pkm_organization':
      return 'PKM 整理';
    case 'super_agent_qa':
      return 'Super Agent 问答';
    case 'cost_trace':
      return '成本 / Trace';
    case 'full_chain_replay':
      return '全链路 Replay';
    default:
      return key;
  }
}

String _scenarioDescription(String key) {
  switch (key) {
    case 'card_extraction':
      return '检查输入是否生成正确 card，覆盖类型、时间、人物、地点、标题和幻觉字段。';
    case 'memory_write':
      return '检查长期事实该写是否写、不该写是否不写、是否重复、是否保留来源。';
    case 'retrieval_qa':
      return '检查查询时是否召回正确来源，并基于证据回答。';
    case 'tool_calling':
      return '检查路由标签、工具选择、工具参数和禁止工具调用。';
    case 'schedule_refresh':
      return '检查日程相关输入是否正确 skip / dirty / refresh，并控制不必要刷新。';
    case 'pkm_organization':
      return '检查 PKM 条目是否放到正确路径、保留关键信息并引用来源。';
    case 'super_agent_qa':
      return '检查 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。';
    case 'cost_trace':
      return '检查 token、延迟和工具调用数量是否在预算内。';
    case 'full_chain_replay':
      return '检查真实 submitInput 到后台任务、卡片、trace 和成本统计的链路稳定性。';
    default:
      return '自定义评估场景。';
  }
}

String _metricSortKey(String metric) =>
    '${_metricScenario(metric)}|${_metricCategory(metric)}|$metric';

String _metricScenario(String metric) {
  if (metric.startsWith('card_') ||
      metric == 'time_parse_accuracy' ||
      metric == 'participant_recall' ||
      metric == 'location_accuracy' ||
      metric == 'title_constraint_accuracy' ||
      metric == 'entity_recall' ||
      metric == 'input_to_card_latency' ||
      metric == 'hallucinated_field_absence') {
    return 'Card 抽取';
  }
  if (metric.startsWith('memory_') || metric == 'sensitive_overwrite_absence') {
    return '记忆写入';
  }
  if (metric.startsWith('retrieval_') ||
      metric.startsWith('answer_') ||
      metric == 'grounded_answer_rate' ||
      metric == 'abstention_accuracy' ||
      metric == 'unsupported_claim_absence' ||
      metric == 'unnecessary_uncertainty_absence' ||
      metric == 'llm_grounded_answer_score') {
    return '检索问答';
  }
  if (metric == 'total_token_budget' ||
      metric == 'cost_per_input' ||
      metric == 'latency_budget' ||
      metric == 'tool_call_budget' ||
      metric == 'task_completion_status' ||
      metric == 'active_task_count_budget' ||
      metric == 'failed_task_count_budget' ||
      metric == 'loop_detection_absence' ||
      metric == 'max_turns_absence' ||
      metric == 'retry_rate' ||
      metric == 'failed_task_rate' ||
      metric == 'queue_idle_time' ||
      metric == 'root_invariant_absence' ||
      metric == 'operation_success_rate' ||
      metric == 'operation_settlement_rate' ||
      metric == 'card_materialization_rate' ||
      metric == 'card_completed_rate' ||
      metric == 'memory_artifact_presence' ||
      metric == 'llm_agent_coverage' ||
      metric == 'tool_diversity' ||
      metric == 'record_operation_coverage' ||
      metric == 'journey_time_span_coverage' ||
      metric == 'app_operation_sequence_completeness' ||
      metric == 'input_channel_diversity' ||
      metric == 'feature_trigger_coverage' ||
      metric == 'journey_stage_coverage' ||
      metric == 'scenario_family_coverage' ||
      metric == 'persona_specificity_coverage' ||
      metric == 'cross_day_continuity_coverage' ||
      metric == 'correction_operation_coverage' ||
      metric == 'noise_resilience_coverage' ||
      metric == 'follow_up_query_coverage' ||
      metric == 'trace_completeness' ||
      metric == 'cost_answer_must_include') {
    return '成本 / Trace';
  }
  if (metric.startsWith('schedule_refresh_')) {
    return '日程刷新';
  }
  if (metric.startsWith('pkm_')) {
    return 'PKM 整理';
  }
  if (metric.startsWith('super_agent_') ||
      metric == 'uncertainty_calibration' ||
      metric == 'personalization_accuracy') {
    return 'Super Agent 问答';
  }
  if (metric.startsWith('tool_') ||
      metric == 'prohibited_tool_absence' ||
      metric == 'router_label_accuracy') {
    return '路由 / 工具调用';
  }
  return '自定义';
}

String _metricCategory(String metric) {
  switch (metric) {
    case 'card_schema_valid':
      return '结构合法性';
    case 'card_type_accuracy':
    case 'card_status_accuracy':
    case 'card_completed_rate':
      return 'Card 状态';
    case 'card_materialization_rate':
      return '产物生成';
    case 'time_parse_accuracy':
      return '时间解析';
    case 'input_to_card_latency':
      return '延迟';
    case 'participant_recall':
    case 'location_accuracy':
    case 'title_constraint_accuracy':
    case 'card_field_constraint_accuracy':
    case 'entity_recall':
      return '字段抽取';
    case 'hallucinated_field_absence':
    case 'unsupported_claim_absence':
    case 'unnecessary_uncertainty_absence':
      return '幻觉控制';
    case 'memory_must_write_recall':
      return '写入召回';
    case 'memory_must_not_write_precision':
    case 'memory_write_precision':
      return '写入精度';
    case 'memory_source_grounding':
      return '来源追溯';
    case 'memory_temporal_validity':
      return '时效性';
    case 'memory_duplicate_rate':
      return '去重';
    case 'memory_conflict_handling':
      return '冲突处理';
    case 'memory_artifact_presence':
      return '产物生成';
    case 'sensitive_overwrite_absence':
      return '隐私边界';
    case 'retrieval_hit_at_1':
    case 'retrieval_hit_at_3':
    case 'retrieval_hit_at_5':
    case 'retrieval_mrr':
    case 'retrieval_recall_at_5':
      return '召回排序';
    case 'retrieval_filter_accuracy':
      return '过滤准确性';
    case 'abstention_accuracy':
      return '不确定性控制';
    case 'answer_must_include':
    case 'cost_answer_must_include':
      return '答案完整性';
    case 'answer_source_citation':
    case 'llm_grounded_answer_score':
    case 'grounded_answer_rate':
      return '证据支撑';
    case 'tool_selection_accuracy':
    case 'prohibited_tool_absence':
    case 'tool_call_minimality':
      return '工具选择';
    case 'tool_args_accuracy':
      return '工具参数';
    case 'router_label_accuracy':
      return '路由分类';
    case 'trace_completeness':
      return 'Trace 完整性';
    case 'schedule_refresh_action_accuracy':
      return '刷新决策';
    case 'schedule_refresh_unnecessary_absence':
      return '刷新精度';
    case 'schedule_refresh_missed_absence':
      return '刷新召回';
    case 'schedule_refresh_duplicate_rate':
      return '去重';
    case 'pkm_path_accuracy':
      return '路径分类';
    case 'pkm_content_preservation':
      return '内容保真';
    case 'pkm_source_grounding':
      return '来源追溯';
    case 'pkm_prohibited_content_absence':
      return '幻觉控制';
    case 'pkm_merge_split_quality':
      return '组织质量';
    case 'pkm_update_freshness':
      return '时效性';
    case 'super_agent_read_only_compliance':
      return '操作边界';
    case 'uncertainty_calibration':
      return '不确定性控制';
    case 'personalization_accuracy':
      return '个性化';
    case 'total_token_budget':
    case 'cost_per_input':
      return 'Token 成本';
    case 'latency_budget':
      return '延迟';
    case 'tool_call_budget':
      return '工具成本';
    case 'task_completion_status':
    case 'active_task_count_budget':
    case 'failed_task_count_budget':
    case 'operation_settlement_rate':
      return '任务收敛';
    case 'loop_detection_absence':
    case 'max_turns_absence':
      return 'Agent 循环控制';
    case 'retry_rate':
    case 'failed_task_rate':
      return '稳定性';
    case 'queue_idle_time':
      return '队列等待';
    case 'root_invariant_absence':
      return '测试框架不变量';
    case 'record_operation_coverage':
    case 'operation_success_rate':
    case 'journey_time_span_coverage':
    case 'journey_stage_coverage':
    case 'scenario_family_coverage':
      return '用户旅程覆盖';
    case 'llm_agent_coverage':
      return 'Agent 覆盖';
    case 'tool_diversity':
      return '工具覆盖';
    case 'persona_specificity_coverage':
      return '用户画像区分';
    case 'cross_day_continuity_coverage':
      return '跨日连续性';
    case 'correction_operation_coverage':
      return '修正 / 冲突更新';
    case 'noise_resilience_coverage':
      return '噪声鲁棒性';
    case 'follow_up_query_coverage':
      return '追问闭环';
    case 'app_operation_sequence_completeness':
      return 'App 行为仿真';
    case 'input_channel_diversity':
      return '输入多样性';
    case 'feature_trigger_coverage':
      return '功能触发覆盖';
    default:
      return '自定义';
  }
}

String _metricDescription(String metric) {
  switch (metric) {
    case 'card_schema_valid':
      return 'Card 是否具备最小合法结构，例如类型和标题。';
    case 'card_type_accuracy':
      return '抽取出的 card 类型是否等于期望类型。';
    case 'card_status_accuracy':
      return '后台任务结束后 card 是否离开 processing 状态。';
    case 'card_materialization_rate':
      return '真实提交记录中有多少能取回对应 card 产物。';
    case 'card_completed_rate':
      return '真实提交记录中有多少对应 card 已进入 completed 状态。';
    case 'time_parse_accuracy':
      return '时间解析是否落在允许误差内。';
    case 'input_to_card_latency':
      return '从用户输入到 card 产物的延迟是否在预算内。';
    case 'participant_recall':
      return '期望人物是否都被抽取出来。';
    case 'location_accuracy':
      return '地点字段是否包含期望地点。';
    case 'title_constraint_accuracy':
      return '标题是否包含关键主题词。';
    case 'card_field_constraint_accuracy':
      return '指定 card 字段是否包含应保留的细节。';
    case 'entity_recall':
      return '标题、字段、人物和地点中是否覆盖期望实体。';
    case 'hallucinated_field_absence':
      return '是否没有编造禁止字段。';
    case 'memory_must_write_recall':
      return '应该写入的长期记忆是否被写入。';
    case 'memory_source_grounding':
      return '记忆是否能追溯到期望输入来源。';
    case 'memory_must_not_write_precision':
      return '临时/噪声信息是否没有被写成长记忆。';
    case 'memory_write_precision':
      return '写入的记忆中有多少属于期望长期事实。';
    case 'memory_duplicate_rate':
      return '重复或近似重复记忆的比例。';
    case 'memory_conflict_handling':
      return '新旧偏好冲突时是否保留最新事实、停用旧事实。';
    case 'memory_temporal_validity':
      return '记忆是否带有正确的有效起止时间。';
    case 'memory_artifact_presence':
      return '真实旅程是否沉淀出最低数量的 memory 产物。';
    case 'sensitive_overwrite_absence':
      return '敏感或临时状态是否没有被错误写成长记忆。';
    case 'retrieval_hit_at_1':
      return 'Top 1 结果中是否命中任一正确来源。';
    case 'retrieval_hit_at_3':
      return 'Top 3 结果中是否命中任一正确来源。';
    case 'retrieval_hit_at_5':
      return 'Top 5 结果中是否命中任一正确来源。';
    case 'retrieval_mrr':
      return '第一个正确来源排名的倒数，越高越好。';
    case 'retrieval_recall_at_5':
      return 'Top 5 中覆盖了多少期望来源。';
    case 'retrieval_filter_accuracy':
      return '检索是否应用了期望的人物、时间、类型或项目过滤条件。';
    case 'answer_must_include':
      return '答案是否包含所有必须提到的信息。';
    case 'unsupported_claim_absence':
      return '答案是否没有出现禁止或无证据断言。';
    case 'unnecessary_uncertainty_absence':
      return '证据充分时是否没有不必要地说不确定。';
    case 'abstention_accuracy':
      return '证据不足时是否正确表达不确定，证据充分时是否不乱拒答。';
    case 'answer_source_citation':
      return '答案引用的来源是否覆盖期望来源。';
    case 'grounded_answer_rate':
      return '答案是否同时满足来源引用和无无证据断言。';
    case 'llm_grounded_answer_score':
      return 'LLM judge 给出的 groundedness/completeness 综合分。';
    case 'tool_selection_accuracy':
      return '是否调用了期望工具。';
    case 'tool_args_accuracy':
      return '工具参数是否包含期望字段和值。';
    case 'prohibited_tool_absence':
      return '是否没有调用被禁止的工具。';
    case 'tool_call_minimality':
      return '工具调用数量是否没有超过完成任务所需的上限。';
    case 'router_label_accuracy':
      return '路由分类是否等于期望标签。';
    case 'trace_completeness':
      return 'Trace 是否包含期望的关键事件或工具调用节点。';
    case 'schedule_refresh_action_accuracy':
      return '日程刷新决策是否等于期望的 skip / dirty / refresh。';
    case 'schedule_refresh_unnecessary_absence':
      return '无需刷新时是否没有触发重刷新。';
    case 'schedule_refresh_missed_absence':
      return '必须刷新时是否没有漏掉刷新。';
    case 'schedule_refresh_duplicate_rate':
      return '是否没有对同一日程变化触发重复刷新。';
    case 'pkm_path_accuracy':
      return 'PKM 条目路径是否包含期望目录或项目名。';
    case 'pkm_content_preservation':
      return 'PKM 条目是否保留关键事实、结论和下一步。';
    case 'pkm_source_grounding':
      return 'PKM 条目是否保留期望来源 id。';
    case 'pkm_prohibited_content_absence':
      return 'PKM 条目是否没有写入明确禁止的临时信息。';
    case 'pkm_merge_split_quality':
      return 'PKM 条目数量是否符合合并/拆分预期。';
    case 'pkm_update_freshness':
      return 'PKM 条目是否反映最新输入或更新。';
    case 'super_agent_read_only_compliance':
      return '只读问答场景下 Super Agent 是否没有调用写入类工具。';
    case 'uncertainty_calibration':
      return 'Super Agent 是否在信息不足时澄清，在信息充分时给出结论。';
    case 'personalization_accuracy':
      return '回答是否利用用户偏好、习惯或上下文做个性化表达。';
    case 'total_token_budget':
      return '总 token 是否未超过预算。';
    case 'cost_per_input':
      return '平均每条用户输入消耗的 token 是否在预算内。';
    case 'latency_budget':
      return '最大延迟是否未超过预算。';
    case 'tool_call_budget':
      return '工具调用次数是否未超过预算。';
    case 'task_completion_status':
      return '全链路后台任务是否全部结束且没有 failed/processing/retrying/pending。';
    case 'active_task_count_budget':
      return '观察结束时仍 active 的后台任务数量是否在预算内。';
    case 'failed_task_count_budget':
      return '观察结束时 failed 的后台任务数量是否在预算内。';
    case 'loop_detection_absence':
      return '后台任务是否没有触发 loopDetection 保护。';
    case 'max_turns_absence':
      return '后台任务是否没有触发 Maximum turns reached。';
    case 'retry_rate':
      return '任务 retry 比例是否低于预算。';
    case 'failed_task_rate':
      return '任务失败比例是否低于预算。';
    case 'queue_idle_time':
      return '任务队列等待或空转时间是否在预算内。';
    case 'root_invariant_absence':
      return 'Replay harness 每条 record 是否写入并观测在当前 case 的 data root。';
    case 'record_operation_coverage':
      return '全链路 replay 中真实提交记录的数量是否达到本轮样本要求。';
    case 'operation_success_rate':
      return '真实用户旅程操作是否大多无错误且等待型操作能继续推进。';
    case 'operation_settlement_rate':
      return '需要等待后台任务的操作中，有多少在预算窗口内完成收敛。';
    case 'journey_time_span_coverage':
      return '模拟用户操作是否跨越足够多天，避免只测单日短上下文。';
    case 'app_operation_sequence_completeness':
      return '是否执行了预期 App 行为类型，例如记录、回看、评论、刷新和问答。';
    case 'input_channel_diversity':
      return '输入是否覆盖文本、语音转写、OCR/剪贴等不同真实来源形态。';
    case 'feature_trigger_coverage':
      return 'trace 和操作记录是否覆盖本轮预期功能触发点。';
    case 'llm_agent_coverage':
      return '真实链路中调用 LLM 的 agent 种类是否达到预期，避免只跑到单点链路。';
    case 'tool_diversity':
      return '真实链路中被调用的工具种类是否达到预期，反映跨功能路径覆盖。';
    case 'journey_stage_coverage':
      return '用户旅程是否覆盖捕获、组织、回看、追问、修正和洞察等阶段。';
    case 'scenario_family_coverage':
      return '输入是否覆盖本 persona 预期的工作、生活、健康、家庭、财务等场景族。';
    case 'persona_specificity_coverage':
      return 'trace 摘要是否保留能区分该用户职业、城市、项目或习惯的特征。';
    case 'cross_day_continuity_coverage':
      return '跨日输入之间是否形成足够的连续引用、复盘或后续行动链。';
    case 'correction_operation_coverage':
      return '是否包含足够的用户修正、偏好更新或冲突覆盖样本。';
    case 'noise_resilience_coverage':
      return '是否包含足够的临时情绪、一次性尝试、OCR 噪声等不应长期化输入。';
    case 'follow_up_query_coverage':
      return '是否覆盖用户回看后继续追问、澄清或要求综合总结的闭环。';
    case 'cost_answer_must_include':
      return '成本受控时，回答是否仍覆盖必要结论。';
    default:
      return '自定义指标。';
  }
}

String _zhFailureMessage(AssertionResult failure) {
  switch (failure.metric) {
    case 'card_schema_valid':
      return 'Card 缺少最小合法结构，通常是未生成 card、缺少类型或缺少标题。';
    case 'card_status_accuracy':
      return 'Card 状态不符合预期。${_cardStatusMessage(failure.message)}';
    case 'title_constraint_accuracy':
      return '标题没有覆盖期望关键词。${_titleMissingMessage(failure.message)}';
    case 'task_completion_status':
      return '后台任务没有全部正常结束。${failure.message}';
    case 'active_task_count_budget':
    case 'failed_task_count_budget':
    case 'loop_detection_absence':
    case 'max_turns_absence':
    case 'operation_settlement_rate':
      return '后台任务收敛或 Agent 循环控制不达标。${failure.message}';
    case 'operation_success_rate':
      return '真实用户旅程操作成功率不足。${failure.message}';
    case 'root_invariant_absence':
      return '测试框架 data root 不变量失败。${failure.message}';
    case 'card_materialization_rate':
    case 'card_completed_rate':
      return '记录到 Card 的产物链路不完整。${failure.message}';
    case 'memory_artifact_presence':
      return '旅程没有沉淀出足够的 memory 产物。${failure.message}';
    case 'llm_agent_coverage':
    case 'tool_diversity':
      return '真实链路覆盖的 agent/tool 广度不足。${failure.message}';
    case 'total_token_budget':
      return 'Token 成本超过预算或余量不足。${failure.message}';
    case 'latency_budget':
      return '延迟超过预算。${failure.message}';
    case 'tool_call_budget':
      return '工具调用次数超过预算。${failure.message}';
    case 'memory_must_not_write_precision':
      return '把不应该写入的临时信息写成了长期记忆。原始信息：${failure.message}';
    case 'memory_write_precision':
      return '写入记忆里混入了非长期事实，写入精度不足。${failure.message}';
    case 'llm_grounded_answer_score':
      return 'LLM judge 认为答案证据支撑不足或完整性不足。${failure.message}';
    default:
      return failure.message;
  }
}

String _cardStatusMessage(String message) {
  final match = RegExp(
    r'Expected card status=([^,]+), observed=([^\.]+)',
  ).firstMatch(message);
  if (match == null) return message;
  return '期望状态 ${match.group(1)}，实际状态 ${match.group(2)}。';
}

String _titleMissingMessage(String message) {
  if (!message.startsWith('Title missing:')) return message;
  return '缺少关键词：${message.substring('Title missing:'.length).trim()}';
}

List<JsonMap> _normalizeTrace({
  required String runId,
  required String caseId,
  required EvalTask task,
  required JsonMap observed,
}) {
  final events = <JsonMap>[];
  for (final raw in _list(observed['trace_events'])) {
    final event = _map(raw);
    events.add({
      'run_id': runId,
      'case_id': caseId,
      'task_id': task.taskId,
      'task_type': task.type,
      ...event,
    });
  }
  for (final raw in _list(observed['llm_calls'])) {
    final call = _map(raw);
    events.add({
      'run_id': runId,
      'case_id': caseId,
      'task_id': task.taskId,
      'task_type': task.type,
      'event_type': 'llm_call',
      ...call,
    });
  }
  return events;
}

JsonMap _summarizeObservation(JsonMap observed) {
  return {
    if (observed['case_elapsed_ms'] != null)
      'case_elapsed_ms': observed['case_elapsed_ms'],
    if (observed['suite_elapsed_ms'] != null)
      'suite_elapsed_ms': observed['suite_elapsed_ms'],
    if (observed['input_count'] != null) 'input_count': observed['input_count'],
    if (observed['task_count'] != null) 'task_count': observed['task_count'],
    if (observed['tasks_settled'] != null)
      'tasks_settled': observed['tasks_settled'],
    if (observed['task_status_counts'] != null)
      'task_status_counts': observed['task_status_counts'],
    if (observed['task_type_counts'] != null)
      'task_type_counts': observed['task_type_counts'],
    if (observed['task_status_counts_by_type'] != null)
      'task_status_counts_by_type': observed['task_status_counts_by_type'],
    if (observed['active_task_count'] != null)
      'active_task_count': observed['active_task_count'],
    if (observed['failed_task_count'] != null)
      'failed_task_count': observed['failed_task_count'],
    if (observed['retrying_task_count'] != null)
      'retrying_task_count': observed['retrying_task_count'],
    if (observed['active_task_type_counts'] != null)
      'active_task_type_counts': observed['active_task_type_counts'],
    if (observed['failed_task_type_counts'] != null)
      'failed_task_type_counts': observed['failed_task_type_counts'],
    if (observed['retrying_task_type_counts'] != null)
      'retrying_task_type_counts': observed['retrying_task_type_counts'],
    if (observed['loop_detection_task_count'] != null)
      'loop_detection_task_count': observed['loop_detection_task_count'],
    if (observed['max_turns_task_count'] != null)
      'max_turns_task_count': observed['max_turns_task_count'],
    if (observed['max_retry_count'] != null)
      'max_retry_count': observed['max_retry_count'],
    if (observed['active_tasks'] != null)
      'active_tasks': observed['active_tasks'],
    if (observed['failed_tasks'] != null)
      'failed_tasks': observed['failed_tasks'],
    if (observed['operation_count'] != null)
      'operation_count': observed['operation_count'],
    if (observed['record_operation_count'] != null)
      'record_operation_count': observed['record_operation_count'],
    if (observed['successful_operation_count'] != null)
      'successful_operation_count': observed['successful_operation_count'],
    if (observed['errored_operation_count'] != null)
      'errored_operation_count': observed['errored_operation_count'],
    if (observed['operation_success_rate'] != null)
      'operation_success_rate': observed['operation_success_rate'],
    if (observed['task_wait_operation_count'] != null)
      'task_wait_operation_count': observed['task_wait_operation_count'],
    if (observed['task_wait_settled_count'] != null)
      'task_wait_settled_count': observed['task_wait_settled_count'],
    if (observed['operation_settlement_rate'] != null)
      'operation_settlement_rate': observed['operation_settlement_rate'],
    if (observed['operation_elapsed_ms_by_type'] != null)
      'operation_elapsed_ms_by_type': observed['operation_elapsed_ms_by_type'],
    if (observed['root_invariant_checked_count'] != null)
      'root_invariant_checked_count': observed['root_invariant_checked_count'],
    if (observed['root_invariant_failure_count'] != null)
      'root_invariant_failure_count': observed['root_invariant_failure_count'],
    if (observed['card'] != null)
      'card': {
        'card_type': _map(observed['card'])['card_type'],
        'title': _map(observed['card'])['title'],
      },
    if (observed['submitted_record_count'] != null)
      'submitted_record_count': observed['submitted_record_count'],
    if (observed['resolved_card_count'] != null)
      'resolved_card_count': observed['resolved_card_count'],
    if (observed['completed_card_count'] != null)
      'completed_card_count': observed['completed_card_count'],
    if (observed['titled_card_count'] != null)
      'titled_card_count': observed['titled_card_count'],
    if (observed['missing_card_count'] != null)
      'missing_card_count': observed['missing_card_count'],
    if (observed['card_status_counts'] != null)
      'card_status_counts': observed['card_status_counts'],
    if (observed['card_materialization_rate'] != null)
      'card_materialization_rate': observed['card_materialization_rate'],
    if (observed['card_completed_rate'] != null)
      'card_completed_rate': observed['card_completed_rate'],
    if (observed['memory_entries'] != null &&
        observed['memory_entry_count'] == null)
      'memory_entry_count': _list(observed['memory_entries']).length,
    if (observed['memory_entry_count'] != null)
      'memory_entry_count': observed['memory_entry_count'],
    if (observed['memory_source_linked_entry_count'] != null)
      'memory_source_linked_entry_count':
          observed['memory_source_linked_entry_count'],
    if (observed['memory_content_chars'] != null)
      'memory_content_chars': observed['memory_content_chars'],
    if (observed['llm_calls_by_agent'] != null)
      'llm_calls_by_agent': observed['llm_calls_by_agent'],
    if (observed['llm_tokens_by_agent'] != null)
      'llm_tokens_by_agent': observed['llm_tokens_by_agent'],
    if (observed['llm_agent_count'] != null)
      'llm_agent_count': observed['llm_agent_count'],
    if (observed['cached_token_count'] != null)
      'cached_token_count': observed['cached_token_count'],
    if (observed['thought_token_count'] != null)
      'thought_token_count': observed['thought_token_count'],
    if (observed['tool_call_counts_by_name'] != null)
      'tool_call_counts_by_name': observed['tool_call_counts_by_name'],
    if (observed['tool_diversity_count'] != null)
      'tool_diversity_count': observed['tool_diversity_count'],
    if (observed['retrieved_sources'] != null)
      'retrieved_sources': _sourceIds(observed['retrieved_sources']),
    if (observed['tool_calls'] != null)
      'tool_calls': _list(
        observed['tool_calls'],
      ).map((e) => _map(e)['name']).toList(),
  };
}

List<EvalCase> _selectAuditCases(List<EvalCase> cases, int sampleLimit) {
  if (sampleLimit <= 0 || cases.length <= sampleLimit) return cases;

  final byFamily = <String, List<EvalCase>>{};
  for (final evalCase in cases) {
    byFamily.putIfAbsent(evalCase.family, () => []).add(evalCase);
  }

  final selected = <EvalCase>[];
  var offset = 0;
  while (selected.length < sampleLimit) {
    var addedInRound = false;
    for (final familyCases in byFamily.values) {
      if (offset >= familyCases.length) continue;
      selected.add(familyCases[offset]);
      addedInRound = true;
      if (selected.length >= sampleLimit) break;
    }
    if (!addedInRound) break;
    offset += 1;
  }
  return selected;
}

JsonMap _caseForDatasetAudit(EvalCase evalCase) {
  final inputStream = _list(evalCase.raw['input_stream']);
  final operationInputs = _list(evalCase.raw['operations'])
      .map(_map)
      .where((operation) => operation['type'] == 'record')
      .map(
        (operation) => {
          'id': operation['id'],
          'time': operation['time'],
          'channel': operation['channel'] ?? 'text',
          'content': operation['content'],
        },
      )
      .toList();
  return {
    'case_id': evalCase.caseId,
    'family': evalCase.family,
    'language': evalCase.raw['language'] ?? evalCase.raw['locale'],
    'persona': evalCase.raw['persona'],
    'ground_truth_world': evalCase.raw['ground_truth_world'],
    'input_stream': inputStream.isNotEmpty ? inputStream : operationInputs,
    'eval_tasks': evalCase.tasks
        .map(
          (task) => {
            'task_id': task.taskId,
            'type': task.type,
            if (task.raw['query'] != null) 'query': task.raw['query'],
            'expected': task.expected,
          },
        )
        .toList(),
  };
}

JsonMap _memoryEntry(Object? raw) {
  if (raw is String) return {'content': raw};
  return _map(raw);
}

JsonMap? _findMemoryMatch(Iterable<JsonMap> entries, List<String> needles) {
  if (needles.isEmpty) return null;
  for (final entry in entries) {
    final content = entry['content']?.toString() ?? '';
    if (needles.every((needle) => _contains(content, needle))) {
      return entry;
    }
  }
  return null;
}

double _duplicateRate(List<String> values) {
  if (values.isEmpty) return 0;
  final seen = <String>{};
  var duplicates = 0;
  for (final value in values) {
    if (!seen.add(value)) duplicates++;
  }
  return duplicates / values.length;
}

List<String> _sourceIds(Object? raw) {
  return _list(raw)
      .map((e) {
        if (e is String) return e;
        final map = _map(e);
        return (map['source_id'] ?? map['id'] ?? map['document_id'] ?? '')
            .toString();
      })
      .where((e) => e.isNotEmpty)
      .toList();
}

int? _firstExpectedRank(List<String> retrieved, List<String> expected) {
  for (var i = 0; i < retrieved.length; i++) {
    if (expected.contains(retrieved[i])) return i + 1;
  }
  return null;
}

bool _jsonContains(JsonMap actual, JsonMap expectedSubset) {
  for (final entry in expectedSubset.entries) {
    if (!actual.containsKey(entry.key)) return false;
    if (!_valueMatches(actual[entry.key], entry.value)) return false;
  }
  return true;
}

bool _hasUncertainty(String text) {
  const uncertaintyMarkers = [
    '不确定',
    '不知道',
    '无法确认',
    '没有记录',
    '没有找到',
    '需要更多信息',
    '需要你补充',
    'uncertain',
    'not sure',
    'no record',
    'need more information',
  ];
  return uncertaintyMarkers.any((marker) => _contains(text, marker));
}

Set<String> _traceEventNames(JsonMap observed) {
  final names = <String>{};
  for (final raw in _list(observed['trace_events'])) {
    final event = _map(raw);
    for (final key in ['event_type', 'tool_name', 'task_type']) {
      final value = event[key]?.toString();
      if (value != null && value.isNotEmpty) names.add(value);
    }
  }
  for (final raw in _list(observed['tool_calls'])) {
    final name = _map(raw)['name']?.toString();
    if (name != null && name.isNotEmpty) names.add(name);
  }
  for (final raw in _list(observed['llm_calls'])) {
    final agentName = _map(raw)['agent_name']?.toString();
    if (agentName != null && agentName.isNotEmpty) names.add(agentName);
    names.add('llm_call');
  }
  return names;
}

bool _valueMatches(Object? actual, Object? expected) {
  if (expected is JsonMap) {
    return actual is JsonMap && _jsonContains(actual, expected);
  }
  if (expected is List) {
    if (actual is! List) return false;
    return expected.every(
      (expectedItem) =>
          actual.any((actualItem) => _valueMatches(actualItem, expectedItem)),
    );
  }
  if (expected is String) {
    return actual != null && _contains(actual.toString(), expected);
  }
  return actual == expected;
}

String _extractAnthropicText(JsonMap response) {
  final content = response['content'];
  if (content is List) {
    return content.map((part) {
      if (part is JsonMap && part['text'] != null) {
        return part['text'].toString();
      }
      return '';
    }).join('\n');
  }
  return response.toString();
}

String _extractOpenAiChatText(JsonMap response) {
  final choices = response['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = _map(choices.first);
    final message = _map(first['message']);
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content.map((part) {
        final map = _map(part);
        return (map['text'] ?? map['content'] ?? '').toString();
      }).join('\n');
    }
  }
  return response.toString();
}

String _extractJsonObject(String text) {
  final first = text.indexOf('{');
  final last = text.lastIndexOf('}');
  if (first < 0 || last < first) {
    throw FormatException('No JSON object found in judge response: $text');
  }
  return text.substring(first, last + 1);
}

String _anthropicMessagesEndpoint(String baseUrl) {
  final trimmed = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  if (trimmed.endsWith('/v1')) return '$trimmed/messages';
  return '$trimmed/v1/messages';
}

String _openAiChatCompletionsEndpoint(String baseUrl) {
  final trimmed = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  if (trimmed.endsWith('/chat/completions')) return trimmed;
  if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
  return '$trimmed/v1/chat/completions';
}

String _normalizeProvider(String value) {
  switch (value.trim().toLowerCase()) {
    case 'anthropic':
    case 'claude':
    case 'mimo':
    case 'minimax':
      return 'anthropic';
    case 'openai':
    case 'openai_chat':
    case 'chat_completion':
    case 'chat_completions':
    case 'openrouter':
    case 'kimi':
    case 'qwen':
    case 'zhipu':
    case 'ollama':
      return 'openai_chat';
    default:
      return value.trim().toLowerCase();
  }
}

int? _parseInt(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return int.tryParse(value.trim());
}

Future<void> _writeJsonl(File file, Iterable<JsonMap> rows) async {
  final sink = file.openWrite(encoding: utf8);
  for (final row in rows) {
    sink.writeln(jsonEncode(row));
  }
  await sink.flush();
  await sink.close();
}

JsonMap _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

List<String> _strings(Object? value) => _list(
      value,
    ).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();

Map<String, int> _sortedIntMap(Map<String, int> map) {
  return Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

bool _contains(String haystack, String needle) {
  return _normalize(haystack).contains(_normalize(needle));
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

String _formatRunId(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String _join(String a, String b) => a.endsWith('/') ? '$a$b' : '$a/$b';

String _prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _score(Object? value) {
  if (value is num) return value.toStringAsFixed(3);
  return '-';
}

String _duration(Object? value) {
  if (value is! num) return '-';
  final duration = Duration(milliseconds: value.round());
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours小时${minutes.toString().padLeft(2, '0')}分'
        '${seconds.toString().padLeft(2, '0')}秒';
  }
  if (minutes > 0) {
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
  return '$seconds秒';
}

String _tokenEstimate(JsonMap cost) {
  final totalTokens = (cost['total_tokens'] as num?)?.toInt() ?? 0;
  if (totalTokens <= 0) {
    return '本次没有可靠 token 记录，通常表示 fixture 或 no-LLM replay；真实模型实验需要用同规模 replay 重新估算。';
  }
  final lower = (totalTokens * 0.8).round();
  final upper = (totalTokens * 1.2).round();
  return '本次实际消耗 $totalTokens tokens；同规模复跑可先按 $lower-$upper tokens 预留。';
}

String _taskIssueSummary(Object? rawTasks) {
  final tasks = _list(rawTasks).map(_map).toList();
  if (tasks.isEmpty) return '';
  return tasks.take(4).map((task) {
    final type = task['task_type'] ?? task['type'] ?? 'unknown_task';
    final status = task['status'] ?? 'unknown_status';
    final error = task['error']?.toString();
    if (error == null || error.isEmpty) return '$type:$status';
    final normalizedError = error.replaceAll(RegExp(r'\s+'), ' ');
    final shortError = normalizedError.length > 100
        ? '${normalizedError.substring(0, 100)}...'
        : normalizedError;
    return '$type:$status:$shortError';
  }).join(' | ');
}

String _formatCountMap(Map<String, int> counts) {
  if (counts.isEmpty) return '-';
  return counts.entries.map((e) => '${e.key}=${e.value}').join('，');
}

String _evidenceLevel({required String adapter, JsonMap? datasetAudit}) {
  if (adapter == 'replay_file') return 'real_replay';
  final auditScore = (datasetAudit?['overall_score'] as num?)?.toDouble();
  if (auditScore == null) return 'fixture_grader_smoke';
  if (auditScore >= 0.8) return 'audited_synthetic_fixture';
  return 'fixture_smoke_needs_dataset_work';
}

String _evidenceLevelDescription(String? level) {
  switch (level) {
    case 'real_replay':
      return '真实 replay，观察来自 Memex 链路产物，可用于判断 Agent 行为';
    case 'audited_synthetic_fixture':
      return '已审计合成 fixture，可作为小规模回归基线，但仍不等同真实 replay';
    case 'fixture_smoke_needs_dataset_work':
      return 'fixture/grader smoke，断言可验证口径，但数据质量不足以证明 Agent 泛化能力';
    case 'fixture_grader_smoke':
      return 'fixture/grader smoke，主要验证 grader、报告和指标聚合能否工作';
    default:
      return '未声明';
  }
}

String _runVerdict({required double passRate, String? evidenceLevel}) {
  if (passRate < 0.9) {
    return '未达到稳定基线标准，需要优先分析失败项。';
  }
  if (passRate < 0.98) {
    return '基本可用，但存在需要跟踪的失败项。';
  }
  switch (evidenceLevel) {
    case 'real_replay':
      return '真实链路整体通过，适合作为当前 replay 基线。';
    case 'audited_synthetic_fixture':
      return '合成 fixture 整体通过，适合作为小规模回归基线。';
    case 'fixture_smoke_needs_dataset_work':
      return '断言全绿，但只能说明 grader/fixture 口径跑通；数据集需要先补多样性再升级为强 benchmark。';
    default:
      return '断言全绿，适合作为 grader smoke；如需证明 Agent 能力，应接真实 replay 或补数据审计。';
  }
}

String _escapeTable(String value) {
  return value.replaceAll('|', '\\|').replaceAll('\n', '<br>');
}

double _average(List<double> values) {
  if (values.isEmpty) return 0;
  return values.fold<double>(0, (a, b) => a + b) / values.length;
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
  return sorted[index];
}

String _redact(String value) {
  return value.replaceAll(RegExp(r'(tp-)[A-Za-z0-9_-]+'), r'$1[redacted]');
}
