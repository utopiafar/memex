// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/data/services/chat_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _EvalHttpOverrides();

  test(
    'replays Memory Primary Quick Query asks from case logs',
    () async {
      final repoRoot = Directory.current.path;
      final runId =
          'memory_primary_quick_query_replay_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
      final runDir = Directory(
        Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
            p.join(repoRoot, 'evals', 'runs', runId),
      );
      if (await runDir.exists()) {
        await runDir.delete(recursive: true);
      }
      await runDir.create(recursive: true);

      final pathProviderRoot = await Directory.systemTemp.createTemp(
        'memex_memory_primary_quick_query_paths_',
      );
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        pathProviderRoot.path,
      );

      final caseLogPaths = _caseLogPaths(repoRoot)
          .skip(_caseOffset)
          .take(_caseLimit ?? _caseLogPaths(repoRoot).length)
          .toList(growable: false);
      if (caseLogPaths.isEmpty) {
        throw StateError('No quick-query case logs selected.');
      }

      final observations = <JsonMap>[];
      final failures = <JsonMap>[];
      final judgeTasks = <JsonMap>[];
      final caseLogs = <JsonMap>[];
      final progressFile = File(p.join(runDir.path, 'progress.json'));

      for (var caseIndex = 0; caseIndex < caseLogPaths.length; caseIndex++) {
        final sourceLog =
            jsonDecode(await File(caseLogPaths[caseIndex]).readAsString())
                as JsonMap;
        final evalCase = _map(sourceLog['case']);
        final caseId = evalCase['case_id']?.toString() ??
            sourceLog['case_id']?.toString() ??
            'case_$caseIndex';
        final userId =
            '${caseId}_quick_query_${DateTime.now().microsecondsSinceEpoch}';
        final dataRoot = await Directory.systemTemp.createTemp(
          'memex_quick_query_$caseId',
        );
        SharedPreferences.setMockInitialValues({});
        await UserStorage.initL10n();
        await FileSystemService.init(dataRoot.path);
        await UserStorage.saveUser(userId);
        await UserStorage.saveAgentPipelineConfig(
          const AgentPipelineConfig(mode: AgentPipelineMode.memoryPrimary),
        );
        final restoreMode = _rebuildMemoryFromCaseLog
            ? 'memory_change_replay'
            : 'final_memory_atoms';
        if (_rebuildMemoryFromCaseLog) {
          await _rebuildMemoryFromCaseLogChanges(
            userId: userId,
            sourceLog: sourceLog,
          );
        } else {
          await _writeMemoryAtoms(
            userId: userId,
            atoms: _list(sourceLog['final_memory_atoms']).map(_map).toList(),
          );
        }
        final activeAtoms = await MemoryPrimaryService.instance.listActiveAtoms(
          userId,
        );
        if (activeAtoms.isEmpty) {
          throw StateError(
            'Restored Memory Primary store has no active atoms for $caseId.',
          );
        }

        final chatService = ChatService.instance;
        final caseObservations = <JsonMap>[];
        final caseFailures = <JsonMap>[];
        final operations = _list(evalCase['operations'])
            .map(_map)
            .where((operation) => operation['type'] == 'super_agent_ask')
            .toList(growable: false);

        for (var operationIndex = 0;
            operationIndex < operations.length;
            operationIndex++) {
          final operation = operations[operationIndex];
          final opId = operation['id']?.toString() ?? 'ask';
          final directRecall = await _preflightRecall(
            userId: userId,
            query: operation['query']?.toString() ?? '',
          );
          final ask = await _runSuperAgentAskWithProviderRetries(
            chatService,
            operation,
            userId: userId,
            baseSlot: ((_caseOffset + caseIndex) * 100) + operationIndex,
          );
          final expected = _map(operation['expected']);
          final textEval = _evaluateTextExpectations(
            haystack: ask.answer,
            mustContain: _textExpectations(expected['must_contain']),
            mustNotContain: _textExpectations(expected['must_not_contain']),
            caseId: caseId,
            operationId: opId,
          );
          final toolEval = _evaluateToolExpectations(
            caseId: caseId,
            operationId: opId,
            expected: expected,
            events: ask.events,
          );
          caseFailures
            ..addAll(textEval.failures)
            ..addAll(toolEval.failures);
          if (ask.error != null) {
            caseFailures.add(
              _failure(
                caseId: caseId,
                operationId: opId,
                category: 'super_agent_ask_error',
                message: 'Super Agent ask returned an error.',
                details: {'error': ask.error},
              ),
            );
          }
          final observation = {
            'mode': 'memory_primary',
            'case_id': caseId,
            'operation_id': opId,
            'query': operation['query'],
            'preflight': {
              'active_atom_count': activeAtoms.length,
              'direct_recall': directRecall,
            },
            'answer': ask.answer,
            'error': ask.error,
            'provider_attempts': ask.providerAttempts,
            'events': ask.events,
            'text_eval': textEval.toJson(),
            'tool_eval': toolEval.toJson(),
          };
          observations.add(observation);
          caseObservations.add(observation);
          judgeTasks.addAll(
            _judgeTasksForOperation(
              caseId: caseId,
              operationId: opId,
              operation: operation,
              output: {'answer': ask.answer, 'events': ask.events},
            ),
          );
          await progressFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'case_id': caseId,
              'operation_id': opId,
              'completed_observations': observations.length,
              'failure_count': failures.length + caseFailures.length,
            }),
            flush: true,
          );
        }

        failures.addAll(caseFailures);
        caseLogs.add({
          'case_id': caseId,
          'source_case_log': caseLogPaths[caseIndex],
          'user_id': userId,
          'restore_mode': restoreMode,
          'active_atom_count': activeAtoms.length,
          'observation_count': caseObservations.length,
          'failure_count': caseFailures.length,
          'observations': caseObservations,
          'failures': caseFailures,
        });
      }

      await _writeJsonl(
        File(p.join(runDir.path, 'observations.jsonl')),
        observations,
      );
      await _writeJsonl(File(p.join(runDir.path, 'failures.jsonl')), failures);
      await _writeJsonl(
        File(p.join(runDir.path, 'judge_tasks.jsonl')),
        judgeTasks,
      );
      await Directory(p.join(runDir.path, 'case_logs')).create(recursive: true);
      for (final caseLog in caseLogs) {
        await File(
          p.join(runDir.path, 'case_logs', '${caseLog['case_id']}.json'),
        ).writeAsString(
          const JsonEncoder.withIndent('  ').convert(caseLog),
          flush: true,
        );
      }
      final metrics = _metrics(
        observations: observations,
        failures: failures,
        judgeTasks: judgeTasks,
        caseLogPaths: caseLogPaths,
      );
      await File(p.join(runDir.path, 'metrics.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(metrics),
        flush: true,
      );
      await File(
        p.join(runDir.path, 'report.md'),
      ).writeAsString(_renderReport(metrics), flush: true);

      expect(observations.length, caseLogPaths.length * 4);
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}

Future<_EvalLlmConfig> _configureLlm({required int slot}) async {
  final config = _llmConfigForSlot(slot);
  await UserStorage.saveLLMConfigs([
    LLMConfig(
      key: LLMConfig.defaultClientKey,
      type: config.type,
      modelId: config.model,
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      maxTokens: 8192,
      temperature: 0,
    ),
  ]);
  await UserStorage.setDefaultLLMConfigKey(LLMConfig.defaultClientKey);
  return config;
}

Future<void> _writeMemoryAtoms({
  required String userId,
  required List<JsonMap> atoms,
}) async {
  final path = FileSystemService.instance.getMemoryAtomsPath(userId);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'schema_version': 1, 'next_memory_id': 10000, 'atoms': atoms}),
    flush: true,
  );
}

Future<void> _rebuildMemoryFromCaseLogChanges({
  required String userId,
  required JsonMap sourceLog,
}) async {
  var applied = 0;
  for (final observation in _list(
    sourceLog['operation_observations'],
  ).map(_map)) {
    for (final task in _list(observation['new_tasks']).map(_map)) {
      if (task['type']?.toString() != 'memory_primary_task') continue;
      final result = _map(task['result']);
      for (final rawAtom in _list(result['changed_memory_atoms']).map(_map)) {
        final id = rawAtom['id']?.toString();
        if (id == null || id.trim().isEmpty) continue;
        final exists = (await MemoryPrimaryService.instance.listAtoms(
          userId,
        ))
            .any((atom) => atom.id == id);
        await MemoryPrimaryService.instance.applyPatches(
          userId: userId,
          sourceAgent:
              rawAtom['source_agent']?.toString() ?? 'memory_change_replay',
          patches: [
            MemoryPatch(
              op: exists ? 'update' : 'create',
              memoryId: id,
              type: rawAtom['type']?.toString() ?? 'other',
              title: rawAtom['title']?.toString() ?? '',
              content: rawAtom['content']?.toString() ?? '',
              status: rawAtom['status']?.toString() ?? MemoryAtomStatus.active,
              confidence: _doubleValue(rawAtom['confidence']) ?? 0.7,
              importance: _intValue(rawAtom['importance']) ?? 3,
              entityIds: _strings(rawAtom['entity_ids']),
              evidenceFactIds: _strings(rawAtom['evidence_fact_ids']),
              validFrom: rawAtom['valid_from']?.toString(),
              validUntil: rawAtom['valid_until']?.toString(),
              attributes: Map<String, dynamic>.from(
                rawAtom['attributes'] as Map? ?? const {},
              ),
            ),
          ],
        );
        applied += 1;
      }
    }
  }
  if (applied == 0) {
    await _writeMemoryAtoms(
      userId: userId,
      atoms: _list(sourceLog['final_memory_atoms']).map(_map).toList(),
    );
  }
}

Future<JsonMap> _preflightRecall({
  required String userId,
  required String query,
}) async {
  final results = await searchMemoryPrimaryForTool(
    userId: userId,
    query: query,
    limit: 10,
  );
  return {
    'query': query,
    'count': results.length,
    'results': results.map((result) {
      final atom = result.atom;
      return {
        'id': atom.id,
        'type': atom.type,
        'score': double.parse(result.totalScore.toStringAsFixed(3)),
        'content': atom.content.length > 240
            ? '${atom.content.substring(0, 240)}...'
            : atom.content,
        'evidence_fact_ids': atom.evidenceFactIds.take(12).toList(),
        'reasons': result.reasons,
      };
    }).toList(growable: false),
  };
}

Future<_SuperAgentAskResult> _runSuperAgentAsk(
  ChatService chatService,
  JsonMap operation,
) async {
  final answer = StringBuffer();
  final events = <JsonMap>[];
  String? sessionId = operation['session_id']?.toString();
  String? error;
  final startedAt = DateTime.now();

  try {
    final stream = chatService.sendMessage(
      operation['query']?.toString() ?? '',
      sessionId: sessionId,
      agentName: operation['agent_name']?.toString() ?? 'memex_agent',
      scene: operation['scene']?.toString() ?? 'assistant',
      sceneId: operation['scene_id']?.toString(),
      refs: _refs(operation['refs']),
      isQuickQuery: operation['quick_query'] != false,
    );
    await for (final event in stream.timeout(_askTimeout)) {
      events.add({
        ..._serializeChatEvent(event),
        'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
      });
      if (event is ChatSessionCreatedEvent) {
        sessionId = event.sessionId;
      } else if (event is ChatResponseChunkEvent) {
        answer.write(event.text);
      } else if (event is ChatErrorEvent) {
        error = event.error;
      }
    }
  } on TimeoutException catch (e) {
    error = 'timeout_after_${_askTimeout.inSeconds}s: $e';
  } catch (e) {
    error = e.toString();
  }

  return _SuperAgentAskResult(
    sessionId: sessionId,
    answer: answer.toString(),
    events: events,
    error: error,
  );
}

Future<_SuperAgentAskResult> _runSuperAgentAskWithProviderRetries(
  ChatService chatService,
  JsonMap operation, {
  required String userId,
  required int baseSlot,
}) async {
  final maxAttempts = _providerConfigCount <= 1 ? 1 : _providerConfigCount;
  final attempts = <JsonMap>[];
  _SuperAgentAskResult? latest;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await UserStorage.saveUser(userId);
    await UserStorage.saveAgentPipelineConfig(
      const AgentPipelineConfig(mode: AgentPipelineMode.memoryPrimary),
    );
    final config = await _configureLlm(slot: baseSlot + attempt);
    await UserStorage.saveUser(userId);
    final result = await _runSuperAgentAsk(chatService, operation);
    attempts.add({
      'attempt': attempt + 1,
      'provider_index': config.index,
      'base_url': config.baseUrl,
      'model': config.model,
      'retryable_provider_error': _isRetryableProviderError(result.error),
      if (result.error != null) 'error': result.error,
    });
    latest = result.withProviderAttempts(attempts);
    if (!_isRetryableProviderError(result.error)) return latest;
    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(_providerRetryDelay);
    }
  }
  return latest ??
      _SuperAgentAskResult(
        sessionId: null,
        answer: '',
        events: const [],
        error: 'no_provider_attempts_completed',
        providerAttempts: attempts,
      );
}

bool _isRetryableProviderError(String? error) {
  if (error == null || error.trim().isEmpty) return false;
  final normalized = error.toLowerCase();
  return normalized.contains('429') ||
      normalized.contains('too many requests') ||
      normalized.contains('rate limit') ||
      normalized.contains('limitation') ||
      normalized.contains('quota');
}

_TextEval _evaluateTextExpectations({
  required String haystack,
  required List<_TextExpectation> mustContain,
  required List<_TextExpectation> mustNotContain,
  required String caseId,
  required String operationId,
}) {
  final failures = <JsonMap>[];
  var mustHits = 0;
  for (final expectation in mustContain) {
    if (expectation.matches(haystack)) {
      mustHits += 1;
    } else {
      failures.add(
        _failure(
          caseId: caseId,
          operationId: operationId,
          category: 'super_agent_answer_missing',
          message: 'Expected answer text was missing.',
          details: expectation.toJson(),
        ),
      );
    }
  }
  var forbiddenHits = 0;
  for (final expectation in mustNotContain) {
    if (expectation.matches(haystack)) {
      forbiddenHits += 1;
      failures.add(
        _failure(
          caseId: caseId,
          operationId: operationId,
          category: 'super_agent_forbidden_present',
          message: 'Forbidden answer text was present.',
          details: expectation.toJson(),
        ),
      );
    }
  }
  return _TextEval(
    mustHits: mustHits,
    mustTotal: mustContain.length,
    forbiddenHits: forbiddenHits,
    forbiddenTotal: mustNotContain.length,
    failures: failures,
  );
}

_ToolEval _evaluateToolExpectations({
  required String caseId,
  required String operationId,
  required JsonMap expected,
  required List<JsonMap> events,
}) {
  final scoped = _map(_map(expected['by_mode'])['memory_primary']);
  final calls = events.where((event) => event['type'] == 'tool_call').toList();
  final results =
      events.where((event) => event['type'] == 'tool_result').toList();
  final failures = <JsonMap>[];
  final callNames =
      calls.map((event) => event['name']?.toString() ?? '').toSet();

  var toolSelectionHits = 0;
  var toolSelectionTotal = 0;
  for (final tool in _strings(scoped['expected_tools'])) {
    toolSelectionTotal += 1;
    if (callNames.contains(tool)) {
      toolSelectionHits += 1;
    } else {
      failures.add(
        _failure(
          caseId: caseId,
          operationId: operationId,
          category: 'tool_selection_missing',
          message: 'Expected tool was not called.',
          details: {'expected_tool': tool, 'actual_tools': callNames.toList()},
        ),
      );
    }
  }

  var toolArgsHits = 0;
  var toolArgsTotal = 0;
  for (final raw in _list(scoped['expected_tool_args_contains'])) {
    final item = _map(raw);
    final tool = item['tool']?.toString();
    final needles = _strings(item['must_contain']);
    if (tool == null || tool.isEmpty || needles.isEmpty) continue;
    toolArgsTotal += 1;
    final matchingCalls = calls.where(
      (call) => call['name']?.toString() == tool,
    );
    final matched = matchingCalls.any((call) {
      final args = call['arguments']?.toString() ?? '';
      return needles.every((needle) => _contains(args, needle));
    });
    if (matched) {
      toolArgsHits += 1;
    } else {
      failures.add(
        _failure(
          caseId: caseId,
          operationId: operationId,
          category: 'tool_args_mismatch',
          message: 'Expected tool arguments were not observed.',
          details: {
            'tool': tool,
            'must_contain': needles,
            'actual_args':
                matchingCalls.map((call) => call['arguments']).toList(),
          },
        ),
      );
    }
  }

  final forbiddenTools = _strings(scoped['forbidden_tools']);
  final readOnlyViolations = calls.where((call) {
    final name = call['name']?.toString() ?? '';
    return forbiddenTools.contains(name) || _isWriteToolName(name);
  }).toList();
  if (readOnlyViolations.isNotEmpty) {
    failures.add(
      _failure(
        caseId: caseId,
        operationId: operationId,
        category: 'super_agent_read_only_violation',
        message: 'Read-only Super Agent ask used a write-like tool.',
        details: {
          'violating_tools':
              readOnlyViolations.map((call) => call['name']).toList(),
        },
      ),
    );
  }

  final maxToolCalls = _intValue(scoped['max_tool_calls']);
  if (maxToolCalls != null && calls.length > maxToolCalls) {
    failures.add(
      _failure(
        caseId: caseId,
        operationId: operationId,
        category: 'tool_call_minimality_violation',
        message: 'Tool call count exceeded expected maximum.',
        details: {'actual': calls.length, 'max': maxToolCalls},
      ),
    );
  }

  final expectedSources = _strings(scoped['expected_sources']);
  final rankedSources = _rankedSourcesFromToolResults(results);
  final sourceEval = _evaluateToolResultSourceCoverage(
    expectedSources: expectedSources,
    results: results,
  );
  final retrievalHitAt10 = expectedSources.isEmpty ||
      rankedSources.take(10).any(expectedSources.toSet().contains);
  if (!retrievalHitAt10) {
    failures.add(
      _failure(
        caseId: caseId,
        operationId: operationId,
        category: 'retrieval_hit_missing',
        message: 'No expected retrieval source appeared in top 10.',
        details: {
          'expected_sources': expectedSources,
          'ranked_sources': rankedSources.take(10).toList(),
        },
      ),
    );
  }

  return _ToolEval(
    toolSelectionHits: toolSelectionHits,
    toolSelectionTotal: toolSelectionTotal,
    toolArgsHits: toolArgsHits,
    toolArgsTotal: toolArgsTotal,
    readOnlyHits: readOnlyViolations.isEmpty ? 1 : 0,
    readOnlyTotal: 1,
    retrievalHitAt10Hits: retrievalHitAt10 ? 1 : 0,
    retrievalHitAt10Total: expectedSources.isEmpty ? 0 : 1,
    retrievalSourceEval: sourceEval,
    toolCallCount: calls.length,
    failures: failures,
  );
}

List<JsonMap> _judgeTasksForOperation({
  required String caseId,
  required String operationId,
  required JsonMap operation,
  required JsonMap output,
}) {
  return _list(_map(operation['expected'])['judge_tasks'])
      .map(_map)
      .map((task) {
    return {
      'mode': 'memory_primary',
      'case_id': caseId,
      'operation_id': operationId,
      'metric': task['metric'],
      'rubric': task['rubric'],
      'input': _sanitizeForLog(operation),
      'output': _sanitizeForLog(output),
    };
  }).toList(growable: false);
}

JsonMap _metrics({
  required List<JsonMap> observations,
  required List<JsonMap> failures,
  required List<JsonMap> judgeTasks,
  required List<String> caseLogPaths,
}) {
  final textEvals = observations.map((obs) => _map(obs['text_eval']));
  final toolEvals = observations.map((obs) => _map(obs['tool_eval']));
  final mustHits = textEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['must_hits']) ?? 0),
  );
  final mustTotal = textEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['must_total']) ?? 0),
  );
  final forbiddenHits = textEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['forbidden_hits']) ?? 0),
  );
  final forbiddenTotal = textEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['forbidden_total']) ?? 0),
  );
  final toolSelectionHits = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['tool_selection_hits']) ?? 0),
  );
  final toolSelectionTotal = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['tool_selection_total']) ?? 0),
  );
  final toolArgsHits = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['tool_args_hits']) ?? 0),
  );
  final toolArgsTotal = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['tool_args_total']) ?? 0),
  );
  final readOnlyHits = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['read_only_hits']) ?? 0),
  );
  final readOnlyTotal = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['read_only_total']) ?? 0),
  );
  final retrievalHits = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['retrieval_hit_at_10_hits']) ?? 0),
  );
  final retrievalTotal = toolEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['retrieval_hit_at_10_total']) ?? 0),
  );
  final sourceEvals = toolEvals.map(
    (item) => _map(item['retrieval_source_eval']),
  );
  final positiveSourceTotal = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['positive_source_total']) ?? 0),
  );
  final ftsPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['fts_positive_hits']) ?? 0),
  );
  final vectorPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['vector_positive_hits']) ?? 0),
  );
  final hybridPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['hybrid_positive_hits']) ?? 0),
  );
  final bothPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(_map(item['breakdown'])['both']) ?? 0),
  );
  final ftsOnlyPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(_map(item['breakdown'])['fts_only']) ?? 0),
  );
  final vectorOnlyPositiveHits = sourceEvals.fold<int>(
    0,
    (sum, item) =>
        sum + (_intValue(_map(item['breakdown'])['vector_only']) ?? 0),
  );
  final missedPositiveCount = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(_map(item['breakdown'])['missed']) ?? 0),
  );
  final sourceQueryTotal = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['query_total']) ?? 0),
  );
  final vectorSupportedQueryHits = sourceEvals.fold<int>(
    0,
    (sum, item) => sum + (_intValue(item['vector_supported_query_hits']) ?? 0),
  );
  final vectorOnlySupportedQueryHits = sourceEvals.fold<int>(
    0,
    (sum, item) =>
        sum + (_intValue(item['vector_only_supported_query_hits']) ?? 0),
  );
  final toolLatencyByTool = _toolCallLatencyByTool(observations);

  return {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'mode': 'memory_primary',
    'source_case_logs': caseLogPaths,
    'case_count': caseLogPaths.length,
    'super_agent_ask_count': observations.length,
    'super_agent_answer_success_rate': _ratioOrZero(
      observations
          .where((obs) => (obs['answer']?.toString() ?? '').trim().isNotEmpty)
          .length,
      observations.length,
    ),
    'super_agent_answer_hit_rate': _ratioOrZero(mustHits, mustTotal),
    'super_agent_boundary_precision': _ratioOrZero(
      forbiddenTotal - forbiddenHits,
      forbiddenTotal,
    ),
    'tool_selection_accuracy': _ratioOrZero(
      toolSelectionHits,
      toolSelectionTotal,
    ),
    'tool_args_accuracy': _ratioOrZero(toolArgsHits, toolArgsTotal),
    'super_agent_read_only_compliance': _ratioOrZero(
      readOnlyHits,
      readOnlyTotal,
    ),
    'retrieval_hit_at_10': _ratioOrZero(retrievalHits, retrievalTotal),
    'retrieval_positive_source_total': positiveSourceTotal,
    'retrieval_fts_positive_hits': ftsPositiveHits,
    'retrieval_vector_positive_hits': vectorPositiveHits,
    'retrieval_hybrid_positive_hits': hybridPositiveHits,
    'retrieval_positive_source_breakdown': {
      'both': bothPositiveHits,
      'fts_only': ftsOnlyPositiveHits,
      'vector_only': vectorOnlyPositiveHits,
      'missed': missedPositiveCount,
    },
    'fts_positive_coverage_rate': _ratioOrZero(
      ftsPositiveHits,
      positiveSourceTotal,
    ),
    'vector_positive_coverage_rate': _ratioOrZero(
      vectorPositiveHits,
      positiveSourceTotal,
    ),
    'vector_only_positive_hit_rate': _ratioOrZero(
      vectorOnlyPositiveHits,
      positiveSourceTotal,
    ),
    'fts_only_positive_hit_rate': _ratioOrZero(
      ftsOnlyPositiveHits,
      positiveSourceTotal,
    ),
    'hybrid_positive_coverage_rate': _ratioOrZero(
      hybridPositiveHits,
      positiveSourceTotal,
    ),
    'vector_incremental_recall_lift_at_10':
        _ratioOrZero(hybridPositiveHits, positiveSourceTotal) -
            _ratioOrZero(ftsPositiveHits, positiveSourceTotal),
    'vector_supported_query_rate': _ratioOrZero(
      vectorSupportedQueryHits,
      sourceQueryTotal,
    ),
    'retrieval_vector_supported_query_hits': vectorSupportedQueryHits,
    'vector_only_supported_query_rate': _ratioOrZero(
      vectorOnlySupportedQueryHits,
      sourceQueryTotal,
    ),
    'retrieval_vector_only_supported_query_hits': vectorOnlySupportedQueryHits,
    'retrieval_source_query_count': sourceQueryTotal,
    'tool_call_latency_p95_by_tool': toolLatencyByTool,
    'failure_count': failures.length,
    'failure_category_counts': _failureCategoryCounts(failures),
    'judge_task_count': judgeTasks.length,
    'judge_task_metrics': _countsBy(judgeTasks, 'metric'),
    'secrets': {'llm_api_key': '<redacted>'},
  };
}

String _renderReport(JsonMap metrics) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Quick Query Replay');
  b.writeln('');
  b.writeln('- Cases: `${metrics['case_count']}`');
  b.writeln('- Asks: `${metrics['super_agent_ask_count']}`');
  b.writeln('- Judge tasks: `${metrics['judge_task_count']}`');
  b.writeln('');
  b.writeln('| Metric | Value |');
  b.writeln('| --- | ---: |');
  for (final key in [
    'super_agent_answer_success_rate',
    'super_agent_answer_hit_rate',
    'super_agent_boundary_precision',
    'tool_selection_accuracy',
    'tool_args_accuracy',
    'super_agent_read_only_compliance',
    'retrieval_hit_at_10',
    'vector_positive_coverage_rate',
    'vector_only_positive_hit_rate',
    'hybrid_positive_coverage_rate',
    'vector_incremental_recall_lift_at_10',
    'tool_call_latency_p95_by_tool',
    'failure_count',
  ]) {
    b.writeln('| `$key` | ${metrics[key]} |');
  }
  return b.toString();
}

List<String> _caseLogPaths(String repoRoot) {
  final raw = Platform.environment['MEMEX_EVAL_QUICK_QUERY_CASE_LOGS'];
  if (raw == null || raw.trim().isEmpty) {
    throw StateError('Set MEMEX_EVAL_QUICK_QUERY_CASE_LOGS.');
  }
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .map((item) => p.isAbsolute(item) ? item : p.join(repoRoot, item))
      .toList(growable: false);
}

_EvalLlmConfig _llmConfigForSlot(int slot) {
  final baseUrls = _envList('MEMEX_EVAL_LLM_BASE_URLS');
  final apiKeys = _envList('MEMEX_EVAL_LLM_API_KEYS');
  final configCount = baseUrls.isNotEmpty && apiKeys.isNotEmpty
      ? (baseUrls.length < apiKeys.length ? baseUrls.length : apiKeys.length)
      : 0;
  if (configCount == 0) {
    final baseUrl = Platform.environment['MEMEX_EVAL_LLM_BASE_URL'];
    final apiKey = Platform.environment['MEMEX_EVAL_LLM_API_KEY'];
    if (baseUrl == null || apiKey == null) {
      throw StateError('Set MEMEX_EVAL_LLM_BASE_URL(S) and API_KEY(S).');
    }
    return _EvalLlmConfig(
      index: 0,
      type: Platform.environment['MEMEX_EVAL_LLM_TYPE'] ?? LLMConfig.typeMimo,
      model: Platform.environment['MEMEX_EVAL_LLM_MODEL'] ?? 'mimo-v2.5',
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
  }
  final configIndex = slot % configCount;
  return _EvalLlmConfig(
    index: configIndex,
    type: Platform.environment['MEMEX_EVAL_LLM_TYPE'] ?? LLMConfig.typeMimo,
    model: Platform.environment['MEMEX_EVAL_LLM_MODEL'] ?? 'mimo-v2.5',
    baseUrl: baseUrls[configIndex],
    apiKey: apiKeys[configIndex],
  );
}

List<Map<String, String>>? _refs(Object? value) {
  final refs = _list(value)
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      )
      .toList(growable: false);
  return refs.isEmpty ? null : refs;
}

JsonMap _serializeChatEvent(ChatEvent event) {
  if (event is ChatSessionCreatedEvent) {
    return {'type': 'session_created', 'session_id': event.sessionId};
  }
  if (event is ChatResponseChunkEvent) {
    return {
      'type': 'response_chunk',
      'text': event.text,
      'is_done': event.isDone,
    };
  }
  if (event is ChatThoughtChunkEvent) {
    return {'type': 'thought', 'text': event.text};
  }
  if (event is ChatToolCallEvent) {
    return {
      'type': 'tool_call',
      'name': event.toolName,
      'arguments': event.args,
    };
  }
  if (event is ChatToolResultEvent) {
    return {
      'type': 'tool_result',
      'name': event.toolName,
      'result': event.result,
      'is_error': event.isError,
    };
  }
  if (event is ChatErrorEvent) return {'type': 'error', 'error': event.error};
  if (event is ChatAgentStartedEvent) return {'type': 'agent_started'};
  if (event is ChatAgentStoppedEvent) return {'type': 'agent_stopped'};
  if (event is ChatTokenUsageEvent) {
    return {
      'type': 'token_usage',
      'prompt_tokens': event.promptTokens,
      'completion_tokens': event.completionTokens,
      'cached_tokens': event.cachedTokens,
      'effective_prompt_tokens': event.effectivePromptTokens,
      'cached_tokens_for_rate': event.cachedTokensForRate,
      'total_tokens': event.totalTokens,
      'estimated_cost': event.estimatedCost,
    };
  }
  return {'type': event.runtimeType.toString()};
}

List<String> _rankedSourcesFromToolResults(Iterable<JsonMap> results) {
  final seen = <String>{};
  final ranked = <String>[];
  void addSource(String? source) {
    if (source != null && seen.add(source)) ranked.add(source);
  }

  final sourcePattern = RegExp(r'\d{4}/\d{2}/\d{2}\.md#ts_\d+|mem_\d+');
  for (final result in results) {
    final text = result['result']?.toString() ?? '';
    for (final match in sourcePattern.allMatches(text)) {
      addSource(match.group(0));
    }
  }
  return ranked;
}

_RetrievalSourceEval _evaluateToolResultSourceCoverage({
  required List<String> expectedSources,
  required List<JsonMap> results,
}) {
  return _evaluateExpectedSourceCoverage(
    expectedSources: expectedSources,
    sourceIndex: _retrievalSourceIndexFromToolResults(results),
  );
}

_RetrievalSourceEval _evaluateExpectedSourceCoverage({
  required List<String> expectedSources,
  required Map<String, Set<String>> sourceIndex,
}) {
  if (expectedSources.isEmpty) return const _RetrievalSourceEval();
  var ftsHits = 0;
  var vectorHits = 0;
  var hybridHits = 0;
  var bothHits = 0;
  var ftsOnlyHits = 0;
  var vectorOnlyHits = 0;
  var missed = 0;
  var queryHasVector = false;
  var queryHasVectorOnly = false;
  final details = <JsonMap>[];

  for (final source in expectedSources) {
    final channels = sourceIndex[source] ?? const <String>{};
    final appeared = sourceIndex.containsKey(source);
    final fts = channels.contains('fts');
    final vector = channels.contains('vector');
    if (appeared) hybridHits += 1;
    if (fts) ftsHits += 1;
    if (vector) {
      vectorHits += 1;
      queryHasVector = true;
    }
    if (fts && vector) {
      bothHits += 1;
    } else if (fts) {
      ftsOnlyHits += 1;
    } else if (vector) {
      vectorOnlyHits += 1;
      queryHasVectorOnly = true;
    } else {
      missed += 1;
    }
    details.add({
      'source': source,
      'appeared': appeared,
      'channels': channels.toList()..sort(),
    });
  }

  return _RetrievalSourceEval(
    positiveSourceTotal: expectedSources.length,
    ftsPositiveHits: ftsHits,
    vectorPositiveHits: vectorHits,
    hybridPositiveHits: hybridHits,
    bothPositiveHits: bothHits,
    ftsOnlyPositiveHits: ftsOnlyHits,
    vectorOnlyPositiveHits: vectorOnlyHits,
    missedPositiveCount: missed,
    queryTotal: 1,
    vectorSupportedQueryHits: queryHasVector ? 1 : 0,
    vectorOnlySupportedQueryHits: queryHasVectorOnly ? 1 : 0,
    details: details,
  );
}

Map<String, Set<String>> _retrievalSourceIndexFromToolResults(
  List<JsonMap> results,
) {
  final sourceIndex = <String, Set<String>>{};
  final memoryBlockPattern = RegExp(
    r'- \[(mem_\d+)\][\s\S]*?(?=\n- \[mem_\d+\]|\n</memory_primary_context>|\z)',
  );
  final evidencePattern = RegExp(r'\d{4}/\d{2}/\d{2}\.md#ts_\d+');
  for (final result in results) {
    final text = result['result']?.toString() ?? '';
    for (final block in memoryBlockPattern.allMatches(text)) {
      final blockText = block.group(0) ?? '';
      final sources = _retrievalSourcesFromMemoryBlock(blockText);
      _addRetrievalSource(sourceIndex, block.group(1), sources);
      for (final match in evidencePattern.allMatches(blockText)) {
        _addRetrievalSource(sourceIndex, match.group(0), sources);
      }
    }
  }
  return sourceIndex;
}

Set<String> _retrievalSourcesFromMemoryBlock(String block) {
  final sourceLine = RegExp(
    r'retrieval_sources:\s*([^\n]+)',
  ).firstMatch(block)?.group(1);
  final sources = <String>{};
  if (sourceLine != null) {
    for (final raw in sourceLine.split(',')) {
      final source = raw.trim().toLowerCase();
      if (source == 'fts' || source == 'vector') sources.add(source);
    }
  }
  if (sources.isEmpty) {
    final lower = block.toLowerCase();
    if (lower.contains('fts_match') || lower.contains('lexical_match')) {
      sources.add('fts');
    }
    if (lower.contains('vector_match') || lower.contains('embedding_rerank')) {
      sources.add('vector');
    }
  }
  return sources;
}

void _addRetrievalSource(
  Map<String, Set<String>> sourceIndex,
  String? key,
  Set<String> sources,
) {
  final normalized = key?.trim();
  if (normalized == null || normalized.isEmpty) return;
  sourceIndex.putIfAbsent(normalized, () => <String>{}).addAll(sources);
}

List<_TextExpectation> _textExpectations(Object? value) {
  return _list(value).map((item) {
    if (item is Map) {
      final map = _map(item);
      return _TextExpectation(
        label: map['label']?.toString(),
        anyOf: _strings(map['any_of']),
      );
    }
    return _TextExpectation(anyOf: [item.toString()]);
  }).toList(growable: false);
}

bool _contains(String text, String needle) {
  final normalizedText = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final normalizedNeedle = needle.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return normalizedText.contains(normalizedNeedle);
}

bool _isWriteToolName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('write') ||
      normalized.contains('save') ||
      normalized.contains('update') ||
      normalized.contains('delete') ||
      normalized.contains('create') ||
      normalized.contains('append') ||
      normalized.contains('replace');
}

JsonMap _failure({
  required String caseId,
  required String operationId,
  required String category,
  required String message,
  JsonMap details = const {},
}) {
  return {
    'mode': 'memory_primary',
    'case_id': caseId,
    'operation_id': operationId,
    'category': category,
    'message': message,
    if (details.isNotEmpty) 'details': details,
  };
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

JsonMap _sanitizeForLog(Object? value) {
  if (value is Map) {
    return value.map((key, item) {
      final keyText = key.toString();
      final lowered = keyText.toLowerCase();
      if (lowered.contains('key') || lowered.contains('token')) {
        return MapEntry(keyText, '<redacted>');
      }
      return MapEntry(keyText, _sanitizeValue(item));
    });
  }
  return {'value': _sanitizeValue(value)};
}

Object? _sanitizeValue(Object? value) {
  if (value is Map) return _sanitizeForLog(value);
  if (value is List) return value.map(_sanitizeValue).toList(growable: false);
  return value;
}

Map<String, int> _failureCategoryCounts(Iterable<JsonMap> failures) =>
    _countsBy(failures, 'category');

Map<String, int> _countsBy(Iterable<JsonMap> rows, String field) {
  final counts = <String, int>{};
  for (final row in rows) {
    final key = row[field]?.toString() ?? 'unknown';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> _strings(Object? value) => _list(value)
    .map((item) => item.toString().trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

List<String> _envList(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int get _providerConfigCount {
  final baseUrls = _envList('MEMEX_EVAL_LLM_BASE_URLS');
  final apiKeys = _envList('MEMEX_EVAL_LLM_API_KEYS');
  if (baseUrls.isNotEmpty && apiKeys.isNotEmpty) {
    return baseUrls.length < apiKeys.length ? baseUrls.length : apiKeys.length;
  }
  final baseUrl = Platform.environment['MEMEX_EVAL_LLM_BASE_URL'];
  final apiKey = Platform.environment['MEMEX_EVAL_LLM_API_KEY'];
  return baseUrl != null && apiKey != null ? 1 : 0;
}

int? _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _intEnv(String key) => _intValue(Platform.environment[key]);

bool _boolEnv(String key) {
  final value = Platform.environment[key]?.toLowerCase().trim();
  return value == '1' || value == 'true' || value == 'yes';
}

int get _caseOffset => _intEnv('MEMEX_EVAL_CASE_OFFSET') ?? 0;

int? get _caseLimit => _intEnv('MEMEX_EVAL_CASE_LIMIT');

bool get _rebuildMemoryFromCaseLog =>
    _boolEnv('MEMEX_EVAL_REBUILD_MEMORY_FROM_CASE_LOG');

Duration get _askTimeout =>
    Duration(seconds: _intEnv('MEMEX_EVAL_ASK_TIMEOUT_SECONDS') ?? 240);

Duration get _providerRetryDelay => Duration(
      milliseconds: _intEnv('MEMEX_EVAL_PROVIDER_RETRY_DELAY_MS') ?? 1500,
    );

JsonMap _toolCallLatencyByTool(List<JsonMap> observations) {
  final samplesByTool = <String, List<int>>{};

  for (final observation in observations) {
    final pendingByTool = <String, List<int>>{};
    for (final event in _list(observation['events']).map(_map)) {
      final eventType = event['type']?.toString();
      final toolName = event['name']?.toString();
      final elapsedMs = _intValue(event['elapsed_ms']);
      if (toolName == null || toolName.isEmpty || elapsedMs == null) {
        continue;
      }

      if (eventType == 'tool_call') {
        pendingByTool.putIfAbsent(toolName, () => <int>[]).add(elapsedMs);
        continue;
      }
      if (eventType != 'tool_result') continue;

      final pendingCalls = pendingByTool[toolName];
      if (pendingCalls == null || pendingCalls.isEmpty) continue;
      final startedAtMs = pendingCalls.removeAt(0);
      final durationMs = elapsedMs - startedAtMs;
      if (durationMs < 0) continue;
      samplesByTool.putIfAbsent(toolName, () => <int>[]).add(durationMs);
    }
  }

  return samplesByTool.map((tool, samples) {
    return MapEntry(tool, {
      'count': samples.length,
      'mean': _meanInt(samples),
      'p95': _percentile(samples, 0.95),
      'max': _maxInt(samples),
    });
  });
}

int _meanInt(List<int> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) ~/ values.length;
}

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

int _maxInt(List<int> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a > b ? a : b);
}

double _ratioOrZero(num numerator, num denominator) {
  if (denominator == 0) return 0;
  return double.parse((numerator / denominator).toStringAsFixed(3));
}

class _TextExpectation {
  const _TextExpectation({this.label, required this.anyOf});

  final String? label;
  final List<String> anyOf;

  bool matches(String haystack) =>
      anyOf.any((needle) => _contains(haystack, needle));

  JsonMap toJson() => {if (label != null) 'label': label, 'any_of': anyOf};
}

class _TextEval {
  const _TextEval({
    required this.mustHits,
    required this.mustTotal,
    required this.forbiddenHits,
    required this.forbiddenTotal,
    required this.failures,
  });

  final int mustHits;
  final int mustTotal;
  final int forbiddenHits;
  final int forbiddenTotal;
  final List<JsonMap> failures;

  JsonMap toJson() => {
        'must_hits': mustHits,
        'must_total': mustTotal,
        'forbidden_hits': forbiddenHits,
        'forbidden_total': forbiddenTotal,
      };
}

class _ToolEval {
  const _ToolEval({
    required this.toolSelectionHits,
    required this.toolSelectionTotal,
    required this.toolArgsHits,
    required this.toolArgsTotal,
    required this.readOnlyHits,
    required this.readOnlyTotal,
    required this.retrievalHitAt10Hits,
    required this.retrievalHitAt10Total,
    required this.retrievalSourceEval,
    required this.toolCallCount,
    required this.failures,
  });

  final int toolSelectionHits;
  final int toolSelectionTotal;
  final int toolArgsHits;
  final int toolArgsTotal;
  final int readOnlyHits;
  final int readOnlyTotal;
  final int retrievalHitAt10Hits;
  final int retrievalHitAt10Total;
  final _RetrievalSourceEval retrievalSourceEval;
  final int toolCallCount;
  final List<JsonMap> failures;

  JsonMap toJson() => {
        'tool_selection_hits': toolSelectionHits,
        'tool_selection_total': toolSelectionTotal,
        'tool_args_hits': toolArgsHits,
        'tool_args_total': toolArgsTotal,
        'read_only_hits': readOnlyHits,
        'read_only_total': readOnlyTotal,
        'retrieval_hit_at_10_hits': retrievalHitAt10Hits,
        'retrieval_hit_at_10_total': retrievalHitAt10Total,
        'retrieval_source_eval': retrievalSourceEval.toJson(),
        'tool_call_count': toolCallCount,
      };
}

class _RetrievalSourceEval {
  const _RetrievalSourceEval({
    this.positiveSourceTotal = 0,
    this.ftsPositiveHits = 0,
    this.vectorPositiveHits = 0,
    this.hybridPositiveHits = 0,
    this.bothPositiveHits = 0,
    this.ftsOnlyPositiveHits = 0,
    this.vectorOnlyPositiveHits = 0,
    this.missedPositiveCount = 0,
    this.queryTotal = 0,
    this.vectorSupportedQueryHits = 0,
    this.vectorOnlySupportedQueryHits = 0,
    this.details = const [],
  });

  final int positiveSourceTotal;
  final int ftsPositiveHits;
  final int vectorPositiveHits;
  final int hybridPositiveHits;
  final int bothPositiveHits;
  final int ftsOnlyPositiveHits;
  final int vectorOnlyPositiveHits;
  final int missedPositiveCount;
  final int queryTotal;
  final int vectorSupportedQueryHits;
  final int vectorOnlySupportedQueryHits;
  final List<JsonMap> details;

  JsonMap toJson() {
    return {
      'positive_source_total': positiveSourceTotal,
      'fts_positive_hits': ftsPositiveHits,
      'vector_positive_hits': vectorPositiveHits,
      'hybrid_positive_hits': hybridPositiveHits,
      'breakdown': {
        'both': bothPositiveHits,
        'fts_only': ftsOnlyPositiveHits,
        'vector_only': vectorOnlyPositiveHits,
        'missed': missedPositiveCount,
      },
      'query_total': queryTotal,
      'vector_supported_query_hits': vectorSupportedQueryHits,
      'vector_only_supported_query_hits': vectorOnlySupportedQueryHits,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

class _SuperAgentAskResult {
  const _SuperAgentAskResult({
    required this.sessionId,
    required this.answer,
    required this.events,
    required this.error,
    this.providerAttempts = const [],
  });

  final String? sessionId;
  final String answer;
  final List<JsonMap> events;
  final String? error;
  final List<JsonMap> providerAttempts;

  _SuperAgentAskResult withProviderAttempts(List<JsonMap> attempts) {
    return _SuperAgentAskResult(
      sessionId: sessionId,
      answer: answer,
      events: events,
      error: error,
      providerAttempts: attempts.map(JsonMap.from).toList(growable: false),
    );
  }
}

class _EvalLlmConfig {
  const _EvalLlmConfig({
    required this.index,
    required this.type,
    required this.model,
    required this.baseUrl,
    required this.apiKey,
  });

  final int index;
  final String type;
  final String model;
  final String baseUrl;
  final String apiKey;
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
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(rootPath, 'docs');

  @override
  Future<String?> getApplicationCachePath() async => p.join(rootPath, 'cache');

  @override
  Future<String?> getDownloadsPath() async => p.join(rootPath, 'downloads');

  @override
  Future<List<String>?> getExternalCachePaths() async => [
        p.join(rootPath, 'external_cache'),
      ];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [p.join(rootPath, 'external_storage')];
}

class _EvalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
        return 'DIRECT';
      }
      return HttpClient.findProxyFromEnvironment(uri);
    };
    return client;
  }
}
