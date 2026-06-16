import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main(List<String> args) async {
  final input = File(
    Platform.environment['MEMEX_EVAL_JUDGE_TASKS'] ??
        (args.isNotEmpty ? args.first : 'judge_tasks.jsonl'),
  );
  if (!await input.exists()) {
    throw StateError('Judge task file does not exist: ${input.path}');
  }
  final outDir = Directory(
    Platform.environment['MEMEX_EVAL_JUDGE_OUT_DIR'] ??
        p.dirname(input.absolute.path),
  );
  await outDir.create(recursive: true);
  final resultFile = File(p.join(outDir.path, 'judge_results.jsonl'));
  final metricFile = File(p.join(outDir.path, 'judge_metrics.json'));

  final tasks = await _readJsonl(input);
  final resume = _boolEnv('MEMEX_EVAL_JUDGE_RESUME');
  final retryFailed = _boolEnv('MEMEX_EVAL_JUDGE_RETRY_FAILED');
  final rawExistingResults = resume && await resultFile.exists()
      ? await _readExistingJudgeResults(resultFile)
      : <JsonMap>[];
  final existingResults = retryFailed
      ? rawExistingResults
          .where((result) =>
              result['ok'] == true && result['retry_exhausted'] != true)
          .toList(growable: false)
      : rawExistingResults;
  final completedTaskIndexes = existingResults
      .map((result) => result['task_index'])
      .whereType<int>()
      .toSet();
  final baseUrls = _envList('MEMEX_EVAL_JUDGE_BASE_URLS');
  final apiKeys = _envList('MEMEX_EVAL_JUDGE_API_KEYS');
  final fallbackBaseUrl = Platform.environment['MEMEX_EVAL_JUDGE_BASE_URL'];
  final fallbackApiKey = Platform.environment['MEMEX_EVAL_JUDGE_API_KEY'];
  final model =
      Platform.environment['MEMEX_EVAL_JUDGE_MODEL'] ?? 'mimo-v2.5-pro';
  final maxTokens =
      int.tryParse(Platform.environment['MEMEX_EVAL_JUDGE_MAX_TOKENS'] ?? '') ??
          4096;
  final providerPriorities =
      _intEnvList('MEMEX_EVAL_JUDGE_PROVIDER_PRIORITIES');
  final configuredConcurrency = int.tryParse(
    Platform.environment['MEMEX_EVAL_JUDGE_CONCURRENCY'] ?? '',
  );
  final configCount = baseUrls.isNotEmpty && apiKeys.isNotEmpty
      ? (baseUrls.length < apiKeys.length ? baseUrls.length : apiKeys.length)
      : 0;
  if (configCount == 0 &&
      ((fallbackBaseUrl == null || fallbackBaseUrl.isEmpty) ||
          (fallbackApiKey == null || fallbackApiKey.isEmpty))) {
    throw StateError(
      'Set MEMEX_EVAL_JUDGE_BASE_URL(S) and MEMEX_EVAL_JUDGE_API_KEY(S).',
    );
  }
  final providers = configCount == 0
      ? [
          _JudgeProvider(
            index: 0,
            baseUrl: fallbackBaseUrl!,
            apiKey: fallbackApiKey!,
            priority: providerPriorities.isEmpty ? 0 : providerPriorities[0],
          ),
        ]
      : [
          for (var i = 0; i < configCount; i++)
            _JudgeProvider(
              index: i,
              baseUrl: baseUrls[i],
              apiKey: apiKeys[i],
              priority:
                  i < providerPriorities.length ? providerPriorities[i] : 0,
            ),
        ];
  final concurrency = tasks.isEmpty
      ? 0
      : (configuredConcurrency ?? providers.length).clamp(1, tasks.length);
  final providerPool = _JudgeProviderPool(
    providers,
    retryCooldown: _judgeProviderRetryCooldown,
    minRequestInterval: _judgeProviderMinRequestInterval,
  );

  final sink = resultFile.openWrite(
    mode: resume ? FileMode.append : FileMode.write,
  );
  final byMetric = <String, _JudgeAggregate>{};
  for (final result in existingResults) {
    final metric = result['metric']?.toString() ?? 'unknown';
    byMetric.putIfAbsent(metric, _JudgeAggregate.new).add(result);
  }
  var nextTaskIndex = 0;
  var completedCount = existingResults.length;
  try {
    await Future.wait([
      for (var workerId = 0; workerId < concurrency; workerId++)
        _runJudgeWorker(
          workerId: workerId,
          tasks: tasks,
          providerPool: providerPool,
          model: model,
          maxTokens: maxTokens,
          takeNextTaskIndex: () {
            while (nextTaskIndex < tasks.length &&
                completedTaskIndexes.contains(nextTaskIndex)) {
              nextTaskIndex += 1;
            }
            return nextTaskIndex++;
          },
          onResult: (result) {
            completedCount += 1;
            sink.writeln(jsonEncode(result));
            final metric = result['metric']?.toString() ?? 'unknown';
            byMetric.putIfAbsent(metric, _JudgeAggregate.new).add(result);
            if (completedCount % 25 == 0 || completedCount == tasks.length) {
              stdout.writeln('Judged $completedCount/${tasks.length} tasks...');
            }
          },
        ),
    ]);
  } finally {
    await sink.close();
  }

  await metricFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'task_count': tasks.length,
      'model': model,
      'max_tokens': maxTokens,
      'provider_count': providers.length,
      'provider_priorities': providers.map((provider) {
        return {
          'index': provider.index,
          'priority': provider.priority,
        };
      }).toList(growable: false),
      'provider_retry_cooldown_ms': _judgeProviderRetryCooldown.inMilliseconds,
      'provider_min_request_interval_ms':
          _judgeProviderMinRequestInterval.inMilliseconds,
      'provider_max_attempts': _judgeProviderMaxAttempts(providerPool.length),
      'provider_dynamic_priority': true,
      'provider_quota_disable_enabled': true,
      'provider_disabled_count': providerPool.disabledCount,
      'provider_disabled_indexes': providerPool.disabledIndexes,
      'request_timeout_seconds': _judgeRequestTimeout.inSeconds,
      'concurrency': concurrency,
      'resume': resume,
      'retry_failed': retryFailed,
      'raw_resumed_result_count': rawExistingResults.length,
      'resumed_result_count': existingResults.length,
      'secrets': {'judge_api_key': '<redacted>'},
      'metrics': byMetric.map((metric, aggregate) {
        return MapEntry(metric, aggregate.toJson());
      }),
    }),
    flush: true,
  );
  stdout.writeln(
    'Judged ${tasks.length} tasks. Results: ${resultFile.path}; metrics: ${metricFile.path}',
  );
}

Future<void> _runJudgeWorker({
  required int workerId,
  required List<JsonMap> tasks,
  required _JudgeProviderPool providerPool,
  required String model,
  required int maxTokens,
  required int Function() takeNextTaskIndex,
  required void Function(JsonMap result) onResult,
}) async {
  while (true) {
    final taskIndex = takeNextTaskIndex();
    if (taskIndex >= tasks.length) return;
    final result = await _judgeTaskWithProviderRetries(
      task: tasks[taskIndex],
      providerPool: providerPool,
      startIndex: (taskIndex + workerId) % providerPool.length,
      model: model,
      maxTokens: maxTokens,
    );
    onResult({
      ...result,
      'task_index': taskIndex,
      'worker_id': workerId,
    });
  }
}

Future<JsonMap> _judgeTaskWithProviderRetries({
  required JsonMap task,
  required _JudgeProviderPool providerPool,
  required int startIndex,
  required String model,
  required int maxTokens,
}) async {
  final maxAttempts = (int.tryParse(
            Platform.environment['MEMEX_EVAL_JUDGE_MAX_ATTEMPTS'] ?? '',
          ) ??
          _judgeProviderMaxAttempts(providerPool.length))
      .clamp(1, providerPool.length * 10);
  final attempts = <JsonMap>[];
  JsonMap? lastResult;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    late final _JudgeProvider provider;
    try {
      provider = await providerPool.acquire(startIndex + attempt);
    } catch (error) {
      return {
        ...task,
        ...?lastResult,
        'ok': false,
        'passed': false,
        'score': 0,
        'error': error.toString(),
        'attempt_count': attempts.length,
        if (attempts.isNotEmpty) 'attempts': attempts,
        'provider_pool_exhausted': true,
      };
    }
    late final JsonMap result;
    try {
      result = {
        ...await _judgeTask(
          task: task,
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
          model: model,
          maxTokens: maxTokens,
        ),
        'judge_provider_index': provider.index,
      };
    } finally {
      providerPool.release(provider);
    }
    attempts.add(_judgeAttemptSummary(result, attempt + 1));
    lastResult = result;
    if (!_shouldRetryJudgeResult(result)) {
      return {
        ...result,
        'attempt_count': attempt + 1,
        if (attempts.length > 1) 'attempts': attempts,
      };
    }
    providerPool.cooldown(provider, result);
  }
  return {
    ...?lastResult,
    'attempt_count': attempts.length,
    'attempts': attempts,
    'retry_exhausted': true,
  };
}

Future<JsonMap> _judgeTask({
  required JsonMap task,
  required String baseUrl,
  required String apiKey,
  required String model,
  required int maxTokens,
}) async {
  final startedAt = DateTime.now();
  final prompt = '''
You are an evaluator for Memex Agent outputs.

Metric: ${task['metric']}
Rubric: ${task['rubric']}

Input JSON:
${jsonEncode(task['input'])}

Output JSON:
${jsonEncode(task['output'])}

Return strict JSON only:
{"passed": true|false, "score": 0.0-1.0, "rationale": "short reason"}

Do not include reasoning, chain-of-thought, markdown, code fences, or any text
outside that single JSON object. Keep rationale under 40 words.
''';
  try {
    final response = await _postJson(
      _anthropicMessagesEndpoint(baseUrl),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: {
        'model': model,
        'max_tokens': maxTokens,
        'temperature': 0,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      },
    ).timeout(_judgeRequestTimeout);
    final parsed = _parseJudgeResponse(response.body);
    final responseOk = response.statusCode >= 200 && response.statusCode < 300;
    final hasJudgePayload =
        parsed.containsKey('passed') && parsed.containsKey('score');
    return {
      ...task,
      'judge_model': model,
      'judge_base_url': baseUrl,
      'judge_api_key': '<redacted>',
      'status_code': response.statusCode,
      'ok': responseOk && hasJudgePayload,
      'passed': responseOk && hasJudgePayload && parsed['passed'] == true,
      'score': _numValue(parsed['score']) ?? 0,
      'rationale': parsed['rationale']?.toString() ?? '',
      if (responseOk && !hasJudgePayload)
        'error': 'Judge response did not contain strict JSON payload.',
      'raw_response_excerpt': _truncate(response.body, 1000),
      'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
    };
  } catch (error) {
    return {
      ...task,
      'judge_model': model,
      'judge_base_url': baseUrl,
      'judge_api_key': '<redacted>',
      'ok': false,
      'passed': false,
      'score': 0,
      'error': _truncate(error.toString(), 1000),
      'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
    };
  }
}

bool _shouldRetryJudgeResult(JsonMap result) {
  if (result['ok'] == true) return false;
  final status = result['status_code'];
  if (status is int) {
    return status == 408 || status == 429 || status >= 500;
  }
  final error = result['error']?.toString().toLowerCase() ?? '';
  return error.contains('timeout') ||
      error.contains('connection') ||
      error.contains('socket') ||
      error.contains('reset') ||
      error.contains('closed') ||
      error.contains('format') ||
      error.contains('json') ||
      error.contains('unexpected character') ||
      error.contains('tls') ||
      error.contains('decrypt') ||
      error.contains('bad_record_mac');
}

bool _isQuotaExhaustedJudgeResult(JsonMap result) {
  final status = result['status_code'];
  final text = [
    result['error'],
    result['raw_response_excerpt'],
    result['rationale'],
  ].whereType<Object>().map((item) => item.toString().toLowerCase()).join('\n');
  return status == 402 ||
      text.contains('out of quota') ||
      text.contains('over quota') ||
      text.contains('quota exceeded') ||
      text.contains('insufficient_quota') ||
      text.contains('insufficient quota') ||
      text.contains('insufficient balance') ||
      text.contains('balance is insufficient') ||
      text.contains('余额不足') ||
      text.contains('额度不足');
}

Duration get _judgeProviderRetryCooldown {
  final value = int.tryParse(
    Platform.environment['MEMEX_EVAL_JUDGE_PROVIDER_COOLDOWN_MS'] ?? '',
  );
  return Duration(milliseconds: value == null || value < 0 ? 5000 : value);
}

Duration get _judgeProviderMinRequestInterval {
  final value = int.tryParse(
    Platform.environment['MEMEX_EVAL_JUDGE_PROVIDER_MIN_INTERVAL_MS'] ?? '',
  );
  return Duration(milliseconds: value == null || value < 0 ? 0 : value);
}

Duration get _judgeRequestTimeout {
  final value = int.tryParse(
    Platform.environment['MEMEX_EVAL_JUDGE_REQUEST_TIMEOUT_SECONDS'] ?? '',
  );
  return Duration(seconds: value == null || value <= 0 ? 60 : value);
}

int _judgeProviderMaxAttempts(int providerCount) {
  return providerCount * 3;
}

JsonMap _judgeAttemptSummary(JsonMap result, int attempt) {
  return {
    'attempt': attempt,
    'judge_provider_index': result['judge_provider_index'],
    'judge_base_url': result['judge_base_url'],
    'status_code': result['status_code'],
    'ok': result['ok'] == true,
    if (result['error'] != null) 'error': result['error'],
    if (_isQuotaExhaustedJudgeResult(result)) 'provider_disabled': true,
    if (result['raw_response_excerpt'] != null)
      'raw_response_excerpt': result['raw_response_excerpt'],
  };
}

JsonMap _parseJudgeResponse(String body) {
  final decoded = jsonDecode(body);
  Object? text;
  if (decoded is Map && decoded['content'] is List) {
    for (final item in decoded['content'] as List) {
      if (item is Map && item['type'] == 'text') {
        text = item['text'];
        break;
      }
    }
  }
  final raw = text?.toString() ?? body;
  final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
  if (jsonMatch == null) return const {};
  final parsed = jsonDecode(jsonMatch.group(0)!);
  return parsed is Map ? Map<String, dynamic>.from(parsed) : const {};
}

Future<_HttpJsonResponse> _postJson(
  Uri uri, {
  required Map<String, String> headers,
  required JsonMap body,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode(body));
    final response = await request.close();
    return _HttpJsonResponse(
      response.statusCode,
      await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Uri _anthropicMessagesEndpoint(String baseUrl) {
  final base = _stripTrailingSlash(baseUrl);
  return Uri.parse(
      base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages');
}

String _stripTrailingSlash(String value) {
  var trimmed = value.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Future<List<JsonMap>> _readJsonl(File file) async {
  final rows = <JsonMap>[];
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    rows.add(jsonDecode(trimmed) as JsonMap);
  }
  return rows;
}

Future<List<JsonMap>> _readExistingJudgeResults(File file) async {
  final rows = <JsonMap>[];
  final latestByTaskIndex = <int, JsonMap>{};
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final row = Map<String, dynamic>.from(decoded);
        final taskIndex = row['task_index'];
        if (taskIndex is int) {
          latestByTaskIndex[taskIndex] = row;
        } else {
          rows.add(row);
        }
      }
    } catch (_) {
      // A killed run can leave a partial tail line; keep completed rows.
    }
  }
  rows.addAll(latestByTaskIndex.values);
  return rows;
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

List<int> _intEnvList(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((item) => int.tryParse(item.trim()))
      .whereType<int>()
      .toList(growable: false);
}

bool _boolEnv(String key) {
  final raw = Platform.environment[key]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes';
}

num? _numValue(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...<truncated ${value.length - maxLength} chars>';
}

class _HttpJsonResponse {
  const _HttpJsonResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _JudgeProviderPool {
  _JudgeProviderPool(
    List<_JudgeProvider> providers, {
    required this.retryCooldown,
    required this.minRequestInterval,
  }) : _providers = providers;

  final List<_JudgeProvider> _providers;
  final Duration retryCooldown;
  final Duration minRequestInterval;
  final Map<int, DateTime> _cooldownUntilByProvider = {};
  final Map<int, DateTime> _nextAvailableAtByProvider = {};
  final Map<int, int> _transientPenaltyByProvider = {};
  final Map<int, int> _inFlightByProvider = {};
  final Set<int> _disabledProviders = {};

  int get length => _providers.length;
  int get disabledCount => _disabledProviders.length;
  List<int> get disabledIndexes => _disabledProviders.toList()..sort();

  Future<_JudgeProvider> acquire(int startIndex) async {
    while (true) {
      if (_disabledProviders.length >= _providers.length) {
        throw StateError('All judge providers are disabled by quota errors.');
      }
      final now = DateTime.now();
      DateTime? earliestAvailableAt;
      final available = <_JudgeProvider>[];
      for (var offset = 0; offset < _providers.length; offset++) {
        final provider = _providers[(startIndex + offset) % _providers.length];
        if (_disabledProviders.contains(provider.index)) continue;
        final cooldownUntil = _cooldownUntilByProvider[provider.index];
        final cooldownActive =
            cooldownUntil != null && cooldownUntil.isAfter(now);
        if (!cooldownActive) {
          _cooldownUntilByProvider.remove(provider.index);
          _transientPenaltyByProvider.remove(provider.index);
        }

        final nextAvailableAt = _nextAvailableAtByProvider[provider.index];
        final rateLimited =
            nextAvailableAt != null && nextAvailableAt.isAfter(now);
        if (!cooldownActive && !rateLimited) {
          available.add(provider);
          continue;
        }

        final blockedUntil = _earlierNonNull(cooldownUntil, nextAvailableAt);
        if (blockedUntil != null &&
            (earliestAvailableAt == null ||
                blockedUntil.isBefore(earliestAvailableAt))) {
          earliestAvailableAt = blockedUntil;
        }
      }

      if (available.isNotEmpty) {
        available.sort((a, b) {
          final priorityComparison =
              _effectivePriority(b).compareTo(_effectivePriority(a));
          if (priorityComparison != 0) return priorityComparison;

          final inFlightComparison = (_inFlightByProvider[a.index] ?? 0)
              .compareTo(_inFlightByProvider[b.index] ?? 0);
          if (inFlightComparison != 0) return inFlightComparison;

          final distanceComparison = _cyclicDistance(a, startIndex)
              .compareTo(_cyclicDistance(b, startIndex));
          if (distanceComparison != 0) return distanceComparison;
          return a.index.compareTo(b.index);
        });
        final selected = available.first;
        if (minRequestInterval.inMilliseconds > 0) {
          _nextAvailableAtByProvider[selected.index] =
              now.add(minRequestInterval);
        }
        _inFlightByProvider[selected.index] =
            (_inFlightByProvider[selected.index] ?? 0) + 1;
        return selected;
      }

      final wait = earliestAvailableAt!.difference(now);
      await Future.delayed(
        wait.isNegative ? const Duration(milliseconds: 10) : wait,
      );
    }
  }

  void release(_JudgeProvider provider) {
    final current = _inFlightByProvider[provider.index] ?? 0;
    if (current <= 1) {
      _inFlightByProvider.remove(provider.index);
    } else {
      _inFlightByProvider[provider.index] = current - 1;
    }
  }

  void cooldown(_JudgeProvider provider, JsonMap result) {
    if (retryCooldown.inMilliseconds <= 0 || !_shouldRetryJudgeResult(result)) {
      return;
    }
    if (_isQuotaExhaustedJudgeResult(result)) {
      _disabledProviders.add(provider.index);
      _transientPenaltyByProvider.remove(provider.index);
      _cooldownUntilByProvider.remove(provider.index);
      _nextAvailableAtByProvider.remove(provider.index);
      return;
    }
    _transientPenaltyByProvider[provider.index] =
        _retryPenaltyForResult(result);
    _cooldownUntilByProvider[provider.index] =
        DateTime.now().add(retryCooldown);
  }

  int _effectivePriority(_JudgeProvider provider) {
    return provider.priority -
        (_transientPenaltyByProvider[provider.index] ?? 0);
  }

  int _cyclicDistance(_JudgeProvider provider, int startIndex) {
    final normalizedStart = startIndex % _providers.length;
    final distance = provider.index - normalizedStart;
    return distance >= 0 ? distance : distance + _providers.length;
  }

  int _retryPenaltyForResult(JsonMap result) {
    if (result['status_code'] == 429) return 3;
    if (result['status_code'] == 408) return 2;
    if (result['status_code'] is int) return 1;
    return 2;
  }

  DateTime? _earlierNonNull(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}

class _JudgeProvider {
  const _JudgeProvider({
    required this.index,
    required this.baseUrl,
    required this.apiKey,
    required this.priority,
  });

  final int index;
  final String baseUrl;
  final String apiKey;
  final int priority;
}

class _JudgeAggregate {
  var total = 0;
  var passed = 0;
  num scoreSum = 0;
  var errorCount = 0;

  void add(JsonMap result) {
    total += 1;
    if (result['passed'] == true) passed += 1;
    scoreSum += _numValue(result['score']) ?? 0;
    if (result['ok'] != true) errorCount += 1;
  }

  JsonMap toJson() => {
        'total': total,
        'passed': passed,
        'pass_rate': total == 0 ? 1 : _round3(passed / total),
        'average_score': total == 0 ? 1 : _round3(scoreSum / total),
        'error_count': errorCount,
      };
}

double _round3(num value) => (value * 1000).round() / 1000;
