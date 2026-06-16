// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/model/chat_events.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/comment_settings_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/llm_call_record_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';
import 'package:memex/domain/models/llm_config.dart';
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

  test('compares legacy PKM and Memory Primary through real full chain',
      () async {
    final repoRoot = Directory.current.path;
    final datasetPath = Platform.environment['MEMEX_EVAL_DATASET'] ??
        p.join(repoRoot, 'evals', 'datasets', 'memory_primary_smoke',
            'cases.jsonl');
    final runId =
        'memory_primary_full_chain_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
    final runDir = Directory(
      Platform.environment['MEMEX_EVAL_RUN_DIR'] ??
          p.join(repoRoot, 'evals', 'runs', runId),
    );
    if (await runDir.exists()) {
      await runDir.delete(recursive: true);
    }
    await runDir.create(recursive: true);

    final pathProviderRoot = await Directory.systemTemp.createTemp(
      'memex_memory_primary_eval_paths_',
    );
    PathProviderPlatform.instance =
        _FakePathProviderPlatform(pathProviderRoot.path);
    WakelockPlusPlatformInterface.instance = _FakeWakelockPlusPlatform();
    final router = MemexRouter();
    final cases = await _loadCases(datasetPath);
    final changedCaseIds = _changedCaseIds;
    final candidateCases = changedCaseIds == null
        ? cases
        : cases
            .where((evalCase) => changedCaseIds.contains(evalCase['case_id']))
            .toList(growable: false);
    final selectedCases = candidateCases
        .skip(_caseOffset)
        .take(_caseLimit ?? candidateCases.length)
        .toList(growable: false);
    if (selectedCases.isEmpty) {
      throw StateError(
        'No eval cases selected. total=${cases.length}, '
        'changed=${changedCaseIds?.join(',') ?? 'all'}, '
        'offset=$_caseOffset, limit=${_caseLimit ?? 'all'}',
      );
    }
    final modes = _pipelineModes();
    final datasetCoverage = _datasetCoverageMetrics(selectedCases, modes);
    final observations = <JsonMap>[];
    final failures = <JsonMap>[];
    final allJudgeTasks = <JsonMap>[];
    final metricsByMode = <String, JsonMap>{};
    final progressFile = File(p.join(runDir.path, 'progress.json'));
    final selectedSlotOffset = _caseOffset;
    final llmPreflight = await _runLlmPreflight(
      runDir: runDir,
      slotOffset: selectedSlotOffset,
      slotCount: selectedCases.length,
    );
    if (_llmPreflightOnly) {
      await File(p.join(runDir.path, 'report.md')).writeAsString(
        _renderPreflightOnlyReport(llmPreflight),
        flush: true,
      );
      expect(llmPreflight?['passed'] ?? !_llmEnabled, isTrue);
      return;
    }

    for (final mode in modes) {
      final modeStartedAt = DateTime.now();
      final modeObservations = <JsonMap>[];
      final taskStatusTotals = <String, int>{};
      final taskTypeStatusTotals = <String, Map<String, int>>{};
      final llmUsageTotals = _emptyUsageBucket();
      final llmUsageByAgent = <String, JsonMap>{};
      final recordElapsedMs = <int>[];
      var recordCount = 0;
      var materializedCards = 0;
      var completedCards = 0;
      var validCards = 0;
      var schemaValidCards = 0;
      var completedCardsWithFailureReason = 0;
      var cardSourceGroundedCount = 0;
      var cardsWithInsight = 0;
      var projectionCount = 0;
      var memoryExpectedHits = 0;
      var memoryExpectedTotal = 0;
      var memoryForbiddenHits = 0;
      var memoryForbiddenTotal = 0;
      var memoryObservedCount = 0;
      var memorySourceGroundedCount = 0;
      var memoryDuplicateCount = 0;
      var cardExpectedHits = 0;
      var cardExpectedTotal = 0;
      var relatedFactExpectedHits = 0;
      var relatedFactExpectedTotal = 0;
      var memoryRecallQueryCount = 0;
      var memoryRecallExpectedHits = 0;
      var memoryRecallExpectedTotal = 0;
      var memoryRecallForbiddenHits = 0;
      var memoryRecallForbiddenTotal = 0;
      var superAgentAskCount = 0;
      var superAgentAnswerSuccessCount = 0;
      var superAgentExpectedHits = 0;
      var superAgentExpectedTotal = 0;
      var superAgentForbiddenHits = 0;
      var superAgentForbiddenTotal = 0;
      final superAgentUsageTotals = _emptyUsageBucket();
      var failedTaskCount = 0;
      var totalTaskCount = 0;
      var retryTaskCount = 0;
      var taskNotSettledCount = 0;
      var missingCardCount = 0;
      var incompleteCardCount = 0;
      var agentRouteAccuracyHits = 0;
      var agentRouteAccuracyTotal = 0;
      var agentRouteMissCount = 0;
      var agentRouteExpectedCount = 0;
      var agentRouteOvertriggerCount = 0;
      var agentRouteObservedCount = 0;
      var cardTemplatePrimaryHits = 0;
      var cardTemplateAnyHits = 0;
      var cardTemplateTotal = 0;
      var cardFieldRecallHits = 0;
      var cardFieldRecallTotal = 0;
      var cardEntityRecallHits = 0;
      var cardEntityRecallTotal = 0;
      var cardTimeParseHits = 0;
      var cardTimeParseTotal = 0;
      var cardHallucinatedAbsenceHits = 0;
      var cardHallucinatedAbsenceTotal = 0;
      var retrievalHitAt1Hits = 0;
      var retrievalHitAt1Total = 0;
      var retrievalHitAt3Hits = 0;
      var retrievalHitAt3Total = 0;
      var retrievalHitAt5Hits = 0;
      var retrievalHitAt5Total = 0;
      var retrievalHitAt10Hits = 0;
      var retrievalHitAt10Total = 0;
      var answerMustIncludeHits = 0;
      var answerMustIncludeTotal = 0;
      var superAgentReadOnlyHits = 0;
      var superAgentReadOnlyTotal = 0;
      var toolSelectionHits = 0;
      var toolSelectionTotal = 0;
      var toolArgsHits = 0;
      var toolArgsTotal = 0;
      var toolCallMinimalityHits = 0;
      var toolCallMinimalityTotal = 0;
      var toolCallCount = 0;
      var toolCallFailureCount = 0;
      var toolCallRetryCount = 0;
      var repeatedToolCallCount = 0;
      var readToolCallCount = 0;
      var readToolErrorCount = 0;
      var writeToolCallCount = 0;
      var writeToolErrorCount = 0;
      var contextPeekCount = 0;
      var contextPeekTaskCount = 0;
      var contextPeekRedundantCount = 0;
      var contextPeekRedundancyTotal = 0;
      var firstWriteAfterReadHits = 0;
      var firstWriteAfterReadTotal = 0;
      var agentToolRoundCount = 0;
      var agentToolRoundTaskCount = 0;
      var loopDetectionFailureCount = 0;
      var maxTurnsFailureCount = 0;
      final judgeTasks = <JsonMap>[];

      for (var caseIndex = 0; caseIndex < selectedCases.length; caseIndex++) {
        final evalCase = selectedCases[caseIndex];
        final caseId = evalCase['case_id']?.toString() ?? 'case_$caseIndex';
        final userId = _caseUserId(evalCase, mode, caseIndex);
        final dataRoot = await Directory.systemTemp.createTemp(
          'memex_${mode.storageValue}_$caseId',
        );

        LocalTaskExecutor.instance.stop();
        router.resetForLogout();
        SharedPreferences.setMockInitialValues({});
        await UserStorage.initL10n();
        await UserStorage.saveUser(userId);
        await UserStorage.setLocale(const Locale('zh', 'CN'));
        await UserStorage.setWorkspaceStorageToCustom(userId, dataRoot.path);
        await UserStorage.saveAgentPipelineConfig(
          AgentPipelineConfig(mode: mode),
        );
        await _configureOptionalLlm(slot: selectedSlotOffset + caseIndex);
        await router.switchUser(userId);
        await CommentSettingsService.save(
          userId,
          const CommentSettings(enableCharacterComment: false),
        );

        final operations = _list(evalCase['operations']).map(_map).toList();
        final factIdsByOperation = <String, String>{};
        final caseObservations = <JsonMap>[];
        final caseFailureStart = failures.length;

        for (final operation in operations) {
          final opId =
              operation['id']?.toString() ?? 'op_${modeObservations.length}';
          final type = operation['type']?.toString();
          final opStartedAt = DateTime.now();
          final beforeTasks =
              await LocalTaskExecutor.instance.getTasks(limit: 4000);

          if (type == 'record') {
            final opExpected = _modeSpecificExpected(
              _map(operation['expected']),
              mode.storageValue,
            );
            final response = await router.submitInput(
              text: operation['content']?.toString(),
              textHash: opId,
              createdAt: DateTime.parse(operation['time'].toString()),
            );
            final factId = response['fact_id'] as String;
            factIdsByOperation[opId] = factId;
            final wait = await _waitForTasksToSettle(
              previousTaskCount: beforeTasks.length,
              timeout: _taskTimeout,
            );
            final card =
                await FileSystemService.instance.readCardFile(userId, factId);
            final activeAtoms =
                await MemoryPrimaryService.instance.listActiveAtoms(userId);

            recordCount += 1;
            if (card?.status == 'completed') completedCards += 1;
            if ((card?.insight?.text?.trim().isNotEmpty ?? false) ||
                (card?.insight?.summary?.trim().isNotEmpty ?? false)) {
              cardsWithInsight += 1;
            }
            recordElapsedMs
                .add(DateTime.now().difference(opStartedAt).inMilliseconds);
            failedTaskCount += wait.failedTaskCount;
            _mergeTaskTypeStatusCounts(taskTypeStatusTotals, wait.newTasks);
            if (!wait.settled) {
              taskNotSettledCount += 1;
              failures.add(_failure(
                mode: mode.storageValue,
                caseId: caseId,
                operationId: opId,
                category: 'task_not_settled',
                message: 'Record operation did not settle before timeout.',
                details: {
                  'task_status_counts': wait.statusCounts,
                  'active_tasks': wait.activeTaskSummaries,
                },
              ));
            }
            totalTaskCount += wait.newTasks.length;
            retryTaskCount += wait.newTasks
                .where((task) => (_intValue(task.retryCount) ?? 0) > 0)
                .length;
            _mergeStatusCounts(taskStatusTotals, wait.statusCounts);
            final taskErrorFlags = _taskErrorFlags(wait.newTasks);
            loopDetectionFailureCount += taskErrorFlags.loopDetection ? 1 : 0;
            maxTurnsFailureCount += taskErrorFlags.maxTurns ? 1 : 0;
            final routeEval = _evaluateRouteExpectation(
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              expected: _map(opExpected['route']),
              tasks: wait.newTasks,
            );
            agentRouteAccuracyHits += routeEval.accuracyHits;
            agentRouteAccuracyTotal += routeEval.accuracyTotal;
            agentRouteMissCount += routeEval.missCount;
            agentRouteExpectedCount += routeEval.expectedCount;
            agentRouteOvertriggerCount += routeEval.overtriggerCount;
            agentRouteObservedCount += routeEval.observedCount;
            failures.addAll(routeEval.failures);
            if (card == null) {
              missingCardCount += 1;
              failures.add(_failure(
                mode: mode.storageValue,
                caseId: caseId,
                operationId: opId,
                category: 'card_missing',
                message: 'Card file was not materialized.',
                details: {'fact_id': factId},
              ));
            } else if (card.status != 'completed') {
              incompleteCardCount += 1;
              failures.add(_failure(
                mode: mode.storageValue,
                caseId: caseId,
                operationId: opId,
                category: 'card_incomplete',
                message: 'Card did not reach completed status.',
                details: {'fact_id': factId, 'status': card.status},
              ));
            } else {
              completedCardsWithFailureReason +=
                  (card.failureReason?.trim().isNotEmpty ?? false) ? 1 : 0;
            }
            if (card != null) {
              materializedCards += 1;
              if (_isSchemaValidCard(card)) schemaValidCards += 1;
              if (card.factId == factId) cardSourceGroundedCount += 1;
              if (card.status == 'completed' &&
                  !(card.failureReason?.trim().isNotEmpty ?? false)) {
                validCards += 1;
              }
            }
            final cardMetricEval = _evaluateCardMetricExpectations(
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              expected: _map(opExpected['card']),
              card: card,
            );
            cardTemplatePrimaryHits += cardMetricEval.templatePrimaryHits;
            cardTemplateAnyHits += cardMetricEval.templateAnyHits;
            cardTemplateTotal += cardMetricEval.templateTotal;
            cardFieldRecallHits += cardMetricEval.fieldRecallHits;
            cardFieldRecallTotal += cardMetricEval.fieldRecallTotal;
            cardEntityRecallHits += cardMetricEval.entityRecallHits;
            cardEntityRecallTotal += cardMetricEval.entityRecallTotal;
            cardTimeParseHits += cardMetricEval.timeParseHits;
            cardTimeParseTotal += cardMetricEval.timeParseTotal;
            cardHallucinatedAbsenceHits +=
                cardMetricEval.hallucinatedAbsenceHits;
            cardHallucinatedAbsenceTotal +=
                cardMetricEval.hallucinatedAbsenceTotal;
            failures.addAll(cardMetricEval.failures);
            judgeTasks.addAll(_judgeTasksForOperation(
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              operation: operation,
              output: {
                'card': card?.toJson(),
              },
            ));

            final obs = {
              'mode': mode.storageValue,
              'case_id': caseId,
              'operation_id': opId,
              'type': type,
              'fact_id': factId,
              'tasks_settled': wait.settled,
              'task_status_counts': wait.statusCounts,
              'new_tasks': wait.newTasks.map(_taskSummary).toList(),
              'new_task_count': wait.newTasks.length,
              'card': card?.toJson(),
              'memory_atom_count': activeAtoms.length,
              if (!wait.settled) 'active_tasks': wait.activeTaskSummaries,
              'elapsed_ms':
                  DateTime.now().difference(opStartedAt).inMilliseconds,
            };
            observations.add(obs);
            modeObservations.add(obs);
            caseObservations.add(obs);
            await _writeProgress(progressFile, obs);
          } else if (type == 'para_projection') {
            await router.enqueueParaProjection();
            final wait = await _waitForTasksToSettle(
              previousTaskCount: beforeTasks.length,
              timeout: _taskTimeout,
            );
            projectionCount += 1;
            failedTaskCount += wait.failedTaskCount;
            _mergeTaskTypeStatusCounts(taskTypeStatusTotals, wait.newTasks);
            if (!wait.settled) {
              taskNotSettledCount += 1;
              failures.add(_failure(
                mode: mode.storageValue,
                caseId: caseId,
                operationId: opId,
                category: 'task_not_settled',
                message:
                    'PARA projection operation did not settle before timeout.',
                details: {
                  'task_status_counts': wait.statusCounts,
                  'active_tasks': wait.activeTaskSummaries,
                },
              ));
            }
            totalTaskCount += wait.newTasks.length;
            retryTaskCount += wait.newTasks
                .where((task) => (_intValue(task.retryCount) ?? 0) > 0)
                .length;
            _mergeStatusCounts(taskStatusTotals, wait.statusCounts);
            final taskErrorFlags = _taskErrorFlags(wait.newTasks);
            loopDetectionFailureCount += taskErrorFlags.loopDetection ? 1 : 0;
            maxTurnsFailureCount += taskErrorFlags.maxTurns ? 1 : 0;
            final obs = {
              'mode': mode.storageValue,
              'case_id': caseId,
              'operation_id': opId,
              'type': type,
              'tasks_settled': wait.settled,
              'task_status_counts': wait.statusCounts,
              'new_tasks': wait.newTasks.map(_taskSummary).toList(),
              'new_task_count': wait.newTasks.length,
              if (!wait.settled) 'active_tasks': wait.activeTaskSummaries,
              'elapsed_ms':
                  DateTime.now().difference(opStartedAt).inMilliseconds,
            };
            observations.add(obs);
            modeObservations.add(obs);
            caseObservations.add(obs);
            await _writeProgress(progressFile, obs);
          } else if (type == 'memory_recall') {
            final recall = await MemoryPrimaryService.instance.searchMemory(
              userId: userId,
              query: operation['query']?.toString() ?? '',
              limit: _intValue(operation['limit']) ?? 10,
            );
            final expected = _map(operation['expected']);
            final eval = _evaluateTextExpectations(
              haystack: recall.map((e) => e.atom.content).join('\n'),
              mustContain: _textExpectations(expected['must_contain']),
              mustNotContain: _textExpectations(expected['must_not_contain']),
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              missingCategory: 'memory_recall_missing',
              forbiddenCategory: 'memory_recall_forbidden_present',
            );
            memoryRecallQueryCount += 1;
            memoryRecallExpectedHits += eval.mustHits;
            memoryRecallExpectedTotal += eval.mustTotal;
            memoryRecallForbiddenHits += eval.forbiddenHits;
            memoryRecallForbiddenTotal += eval.forbiddenTotal;
            failures.addAll(eval.failures);
            final obs = {
              'mode': mode.storageValue,
              'case_id': caseId,
              'operation_id': opId,
              'type': type,
              'query': operation['query'],
              'result_count': recall.length,
              'results': recall
                  .map((e) => {
                        'memory_id': e.atom.id,
                        'score': e.totalScore,
                        'content': e.atom.content,
                      })
                  .toList(),
              'expected_hits': eval.mustHits,
              'expected_total': eval.mustTotal,
              'forbidden_hits': eval.forbiddenHits,
              'forbidden_total': eval.forbiddenTotal,
              'elapsed_ms':
                  DateTime.now().difference(opStartedAt).inMilliseconds,
            };
            observations.add(obs);
            modeObservations.add(obs);
            caseObservations.add(obs);
            await _writeProgress(progressFile, obs);
          } else if (type == 'super_agent_ask') {
            final ask = await _runSuperAgentAsk(router, operation);
            _mergeUsageBucket(
              superAgentUsageTotals,
              _sumChatTokenUsage(ask.tokenUsageEvents),
            );
            final expected = _map(operation['expected']);
            final eval = _evaluateTextExpectations(
              haystack: ask.answer,
              mustContain: _textExpectations(expected['must_contain']),
              mustNotContain: _textExpectations(expected['must_not_contain']),
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              missingCategory: 'super_agent_answer_missing',
              forbiddenCategory: 'super_agent_forbidden_present',
            );
            superAgentAskCount += 1;
            if (ask.error == null && ask.answer.trim().isNotEmpty) {
              superAgentAnswerSuccessCount += 1;
            }
            superAgentExpectedHits += eval.mustHits;
            superAgentExpectedTotal += eval.mustTotal;
            superAgentForbiddenHits += eval.forbiddenHits;
            superAgentForbiddenTotal += eval.forbiddenTotal;
            failures.addAll(eval.failures);
            answerMustIncludeHits += eval.mustHits;
            answerMustIncludeTotal += eval.mustTotal;
            final toolEval = _evaluateSuperAgentToolExpectations(
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              expected: expected,
              events: ask.events,
            );
            retrievalHitAt1Hits += toolEval.retrievalHitAt1Hits;
            retrievalHitAt1Total += toolEval.retrievalHitAt1Total;
            retrievalHitAt3Hits += toolEval.retrievalHitAt3Hits;
            retrievalHitAt3Total += toolEval.retrievalHitAt3Total;
            retrievalHitAt5Hits += toolEval.retrievalHitAt5Hits;
            retrievalHitAt5Total += toolEval.retrievalHitAt5Total;
            retrievalHitAt10Hits += toolEval.retrievalHitAt10Hits;
            retrievalHitAt10Total += toolEval.retrievalHitAt10Total;
            superAgentReadOnlyHits += toolEval.readOnlyHits;
            superAgentReadOnlyTotal += toolEval.readOnlyTotal;
            toolSelectionHits += toolEval.toolSelectionHits;
            toolSelectionTotal += toolEval.toolSelectionTotal;
            toolArgsHits += toolEval.toolArgsHits;
            toolArgsTotal += toolEval.toolArgsTotal;
            toolCallMinimalityHits += toolEval.toolCallMinimalityHits;
            toolCallMinimalityTotal += toolEval.toolCallMinimalityTotal;
            toolCallCount += toolEval.toolCallCount;
            toolCallFailureCount += toolEval.toolCallFailureCount;
            toolCallRetryCount += toolEval.toolCallRetryCount;
            repeatedToolCallCount += toolEval.repeatedToolCallCount;
            readToolCallCount += toolEval.readToolCallCount;
            readToolErrorCount += toolEval.readToolErrorCount;
            writeToolCallCount += toolEval.writeToolCallCount;
            writeToolErrorCount += toolEval.writeToolErrorCount;
            contextPeekCount += toolEval.contextPeekCount;
            contextPeekTaskCount += toolEval.contextPeekTaskCount;
            agentToolRoundCount += toolEval.agentToolRoundCount;
            agentToolRoundTaskCount += toolEval.agentToolRoundTaskCount;
            failures.addAll(toolEval.failures);
            judgeTasks.addAll(_judgeTasksForOperation(
              mode: mode.storageValue,
              caseId: caseId,
              operationId: opId,
              operation: operation,
              output: {
                'answer': ask.answer,
                'events': ask.events,
              },
            ));
            if (ask.error != null) {
              failures.add(_failure(
                mode: mode.storageValue,
                caseId: caseId,
                operationId: opId,
                category: 'super_agent_ask_error',
                message: 'Super Agent ask returned an error.',
                details: {'error': ask.error},
              ));
            }
            final obs = {
              'mode': mode.storageValue,
              'case_id': caseId,
              'operation_id': opId,
              'type': type,
              'query': operation['query'],
              'session_id': ask.sessionId,
              'answer': ask.answer,
              'error': ask.error,
              'events': ask.events,
              'token_usage_events': ask.tokenUsageEvents,
              'expected_hits': eval.mustHits,
              'expected_total': eval.mustTotal,
              'forbidden_hits': eval.forbiddenHits,
              'forbidden_total': eval.forbiddenTotal,
              'elapsed_ms':
                  DateTime.now().difference(opStartedAt).inMilliseconds,
            };
            observations.add(obs);
            modeObservations.add(obs);
            caseObservations.add(obs);
            await _writeProgress(progressFile, obs);
          }
        }

        final expected = _map(evalCase['expected']);
        final activeAtoms =
            await MemoryPrimaryService.instance.listActiveAtoms(userId);
        final memoryText = activeAtoms.map((atom) => atom.content).join('\n');
        final cardTexts = <String>[];
        for (final factId in factIdsByOperation.values) {
          final card = await FileSystemService.instance.readCardFile(
            userId,
            factId,
          );
          if (card == null) continue;
          cardTexts.add([
            card.title,
            card.insight?.text,
            card.insight?.summary,
          ].whereType<String>().join('\n'));
        }
        final memoryEval = _evaluateTextExpectations(
          haystack: memoryText,
          mustContain: _textExpectations(expected['memory_must_contain']),
          mustNotContain:
              _textExpectations(expected['memory_must_not_contain']),
          mode: mode.storageValue,
          caseId: caseId,
          operationId: 'case_memory',
          missingCategory: 'memory_expected_missing',
          forbiddenCategory: 'memory_forbidden_present',
        );
        final cardEval = _evaluateTextExpectations(
          haystack: cardTexts.join('\n'),
          mustContain: _textExpectations(
            expected['card_title_or_insight_should_contain'],
          ),
          mustNotContain: const [],
          mode: mode.storageValue,
          caseId: caseId,
          operationId: 'case_cards',
          missingCategory: 'card_expected_missing',
          forbiddenCategory: 'card_forbidden_present',
        );
        final relatedEval = await _evaluateRelatedFactExpectations(
          mode: mode.storageValue,
          caseId: caseId,
          userId: userId,
          expectations: _list(expected['related_fact_expectations']),
          factIdsByOperation: factIdsByOperation,
        );
        memoryExpectedHits += memoryEval.mustHits;
        memoryExpectedTotal += memoryEval.mustTotal;
        memoryForbiddenHits += memoryEval.forbiddenHits;
        memoryForbiddenTotal += memoryEval.forbiddenTotal;
        cardExpectedHits += cardEval.mustHits;
        cardExpectedTotal += cardEval.mustTotal;
        relatedFactExpectedHits += relatedEval.mustHits;
        relatedFactExpectedTotal += relatedEval.mustTotal;
        memoryObservedCount += activeAtoms.length;
        memorySourceGroundedCount +=
            activeAtoms.where((atom) => atom.evidenceFactIds.isNotEmpty).length;
        memoryDuplicateCount += _duplicateTextCount(
          activeAtoms.map((atom) => atom.content),
        );
        failures.addAll(memoryEval.failures);
        failures.addAll(cardEval.failures);
        failures.addAll(relatedEval.failures);

        final summaryObs = {
          'mode': mode.storageValue,
          'case_id': caseId,
          'operation_id': 'case_summary',
          'type': 'case_summary',
          'active_memory_atom_count': activeAtoms.length,
          'active_memory_atoms': activeAtoms
              .map((atom) => {
                    'id': atom.id,
                    'type': atom.type,
                    'content': atom.content,
                    'evidence_fact_ids': atom.evidenceFactIds,
                  })
              .toList(),
          'memory_expected_hits': memoryEval.mustHits,
          'memory_expected_total': memoryEval.mustTotal,
          'memory_forbidden_hits': memoryEval.forbiddenHits,
          'memory_forbidden_total': memoryEval.forbiddenTotal,
          'card_expected_hits': cardEval.mustHits,
          'card_expected_total': cardEval.mustTotal,
          'related_fact_expected_hits': relatedEval.mustHits,
          'related_fact_expected_total': relatedEval.mustTotal,
        };
        observations.add(summaryObs);
        modeObservations.add(summaryObs);
        caseObservations.add(summaryObs);

        final caseDebugLog = await _writeCaseDebugLog(
          runDir: runDir,
          mode: mode.storageValue,
          caseId: caseId,
          userId: userId,
          dataRoot: dataRoot.path,
          evalCase: evalCase,
          factIdsByOperation: factIdsByOperation,
          observations: caseObservations,
          failures: failures.sublist(caseFailureStart),
        );
        _mergeLlmUsage(
            llmUsageTotals, llmUsageByAgent, _map(caseDebugLog['llm_usage']));
        final activityTraceMetrics = _agentActivityTraceMetrics(
          _list(caseDebugLog['agent_activity_trace'])
              .map(_map)
              .toList(growable: false),
        );
        contextPeekRedundantCount +=
            _intValue(activityTraceMetrics['context_peek_redundant_count']) ??
                0;
        contextPeekRedundancyTotal +=
            _intValue(activityTraceMetrics['context_peek_total']) ?? 0;
        firstWriteAfterReadHits +=
            _intValue(activityTraceMetrics['first_write_after_read_hits']) ?? 0;
        firstWriteAfterReadTotal +=
            _intValue(activityTraceMetrics['first_write_total']) ?? 0;
      }

      final elapsed = DateTime.now().difference(modeStartedAt);
      final completedCardRate = _rate(completedCards, recordCount);
      final cardsWithInsightRate = _rate(cardsWithInsight, recordCount);
      final memoryHitRate = _rate(memoryExpectedHits, memoryExpectedTotal);
      final memoryForbiddenPrecision = _rate(
        memoryForbiddenTotal - memoryForbiddenHits,
        memoryForbiddenTotal,
      );
      final cardHitRate = _rate(cardExpectedHits, cardExpectedTotal);
      final relatedFactHitRate = _rate(
        relatedFactExpectedHits,
        relatedFactExpectedTotal,
      );
      final memoryRecallHitRate = _rate(
        memoryRecallExpectedHits,
        memoryRecallExpectedTotal,
      );
      final memoryRecallForbiddenPrecision = _rate(
        memoryRecallForbiddenTotal - memoryRecallForbiddenHits,
        memoryRecallForbiddenTotal,
      );
      final taskSettlementRate = _rate(
        modeObservations
            .where((obs) =>
                obs['type'] == 'record' || obs['type'] == 'para_projection')
            .where((obs) => obs['tasks_settled'] == true)
            .length,
        modeObservations
            .where((obs) =>
                obs['type'] == 'record' || obs['type'] == 'para_projection')
            .length,
      );
      final waitElapsedMs = modeObservations
          .where((obs) =>
              obs['type'] == 'record' || obs['type'] == 'para_projection')
          .map((obs) => _intValue(obs['elapsed_ms']) ?? 0)
          .where((value) => value > 0)
          .toList();
      final taskQueuePressureSamples = modeObservations
          .map(_activeTaskPressureFromObservation)
          .where((value) => value >= 0)
          .toList();
      final llmCallCount = _intValue(llmUsageTotals['calls']) ?? 0;
      final emptyResponseTurnCount =
          _intValue(llmUsageTotals['empty_response_turns']) ?? 0;
      metricsByMode[mode.storageValue] = {
        'mode': mode.storageValue,
        'case_count': selectedCases.length,
        'record_count': recordCount,
        'materialized_card_count': materializedCards,
        'card_materialization_rate': _rate(materializedCards, recordCount),
        'completed_card_count': completedCards,
        'completed_card_rate': completedCardRate,
        'valid_card_count': validCards,
        'input_to_valid_card_success_rate': _rate(validCards, recordCount),
        'card_completed_rate': completedCardRate,
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
        'cards_with_insight_rate': cardsWithInsightRate,
        'projection_count': projectionCount,
        'memory_expected_hits': memoryExpectedHits,
        'memory_expected_total': memoryExpectedTotal,
        'memory_expected_hit_rate': memoryHitRate,
        'memory_must_write_recall': memoryHitRate,
        'memory_forbidden_hits': memoryForbiddenHits,
        'memory_forbidden_total': memoryForbiddenTotal,
        'memory_must_not_write_precision': memoryForbiddenPrecision,
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
        'card_expected_hit_rate': cardHitRate,
        'related_fact_expected_hits': relatedFactExpectedHits,
        'related_fact_expected_total': relatedFactExpectedTotal,
        'related_fact_hit_rate': relatedFactHitRate,
        'memory_recall_query_count': memoryRecallQueryCount,
        'memory_recall_expected_hits': memoryRecallExpectedHits,
        'memory_recall_expected_total': memoryRecallExpectedTotal,
        'memory_recall_hit_rate': memoryRecallHitRate,
        'memory_recall_at_10': memoryRecallHitRate,
        'memory_recall_forbidden_hits': memoryRecallForbiddenHits,
        'memory_recall_forbidden_total': memoryRecallForbiddenTotal,
        'memory_recall_must_not_precision': memoryRecallForbiddenPrecision,
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
        'super_agent_llm_usage_total': superAgentUsageTotals,
        'super_agent_tokens_per_ask': _ratioOrZero(
          _intValue(superAgentUsageTotals['total_tokens']) ?? 0,
          superAgentAskCount,
        ),
        'agent_route_accuracy': _rate(
          agentRouteAccuracyHits,
          agentRouteAccuracyTotal,
        ),
        'agent_route_miss_rate': _ratioOrZero(
          agentRouteMissCount,
          agentRouteExpectedCount,
        ),
        'agent_route_overtrigger_rate': _ratioOrZero(
          agentRouteOvertriggerCount,
          agentRouteObservedCount,
        ),
        'card_template_primary_accuracy': _rate(
          cardTemplatePrimaryHits,
          cardTemplateTotal,
        ),
        'card_template_any_accuracy': _rate(
          cardTemplateAnyHits,
          cardTemplateTotal,
        ),
        'card_field_recall': _rate(
          cardFieldRecallHits,
          cardFieldRecallTotal,
        ),
        'card_entity_recall': _rate(
          cardEntityRecallHits,
          cardEntityRecallTotal,
        ),
        'card_time_parse_accuracy': _rate(
          cardTimeParseHits,
          cardTimeParseTotal,
        ),
        'card_hallucinated_field_absence': _rate(
          cardHallucinatedAbsenceHits,
          cardHallucinatedAbsenceTotal,
        ),
        'retrieval_hit_at_1': _rate(retrievalHitAt1Hits, retrievalHitAt1Total),
        'retrieval_hit_at_3': _rate(retrievalHitAt3Hits, retrievalHitAt3Total),
        'retrieval_hit_at_5': _rate(retrievalHitAt5Hits, retrievalHitAt5Total),
        'retrieval_hit_at_10': _rate(
          retrievalHitAt10Hits,
          retrievalHitAt10Total,
        ),
        'answer_must_include': _rate(
          answerMustIncludeHits,
          answerMustIncludeTotal,
        ),
        'super_agent_read_only_compliance': _rate(
          superAgentReadOnlyHits,
          superAgentReadOnlyTotal,
        ),
        'tool_selection_accuracy': _rate(
          toolSelectionHits,
          toolSelectionTotal,
        ),
        'tool_args_accuracy': _rate(toolArgsHits, toolArgsTotal),
        'tool_call_minimality': _rate(
          toolCallMinimalityHits,
          toolCallMinimalityTotal,
        ),
        'tool_call_failure_rate': _ratioOrZero(
          toolCallFailureCount,
          toolCallCount,
        ),
        'tool_call_retry_rate': _ratioOrZero(
          toolCallRetryCount,
          toolCallFailureCount,
        ),
        'repeated_tool_call_rate': _ratioOrZero(
          repeatedToolCallCount,
          toolCallCount,
        ),
        'read_tool_error_rate': _ratioOrZero(
          readToolErrorCount,
          readToolCallCount,
        ),
        'write_tool_error_rate': _ratioOrZero(
          writeToolErrorCount,
          writeToolCallCount,
        ),
        'context_peek_count_per_task': _ratioOrZero(
          contextPeekCount,
          contextPeekTaskCount,
        ),
        'context_peek_redundant_count': contextPeekRedundantCount,
        'context_peek_total': contextPeekRedundancyTotal,
        'context_peek_redundancy_rate': _ratioOrZero(
          contextPeekRedundantCount,
          contextPeekRedundancyTotal,
        ),
        'first_write_after_read_hits': firstWriteAfterReadHits,
        'first_write_total': firstWriteAfterReadTotal,
        'first_write_after_read_rate': _rate(
          firstWriteAfterReadHits,
          firstWriteAfterReadTotal,
        ),
        'agent_tool_rounds_per_task': _ratioOrZero(
          agentToolRoundCount,
          agentToolRoundTaskCount,
        ),
        'tool_calls_per_input': _ratioOrZero(toolCallCount, recordCount),
        'agent_llm_turns_per_task': _ratioOrZero(
          llmCallCount,
          totalTaskCount,
        ),
        'agent_llm_turns_per_task_by_agent':
            _llmTurnsPerTaskByAgent(llmUsageByAgent, totalTaskCount),
        'agent_finalization_rate': _ratioOrZero(
          totalTaskCount - failedTaskCount - taskNotSettledCount,
          totalTaskCount,
        ),
        'agent_turn_budget_violation_rate': _ratioOrZero(
          maxTurnsFailureCount,
          totalTaskCount,
        ),
        'agent_empty_response_count': emptyResponseTurnCount,
        'agent_empty_response_rate': _ratioOrZero(
          emptyResponseTurnCount,
          llmCallCount,
        ),
        'loop_detection_absence': loopDetectionFailureCount == 0 ? 1.0 : 0.0,
        'max_turns_absence': maxTurnsFailureCount == 0 ? 1.0 : 0.0,
        'failed_task_count': failedTaskCount,
        'failed_task_rate': _ratioOrZero(failedTaskCount, totalTaskCount),
        'total_task_count': totalTaskCount,
        'task_not_settled_count': taskNotSettledCount,
        'task_settlement_rate': taskSettlementRate,
        'task_completion_status': taskSettlementRate,
        'input_timeout_rate': _ratioOrZero(
          taskNotSettledCount,
          recordCount + projectionCount,
        ),
        'retry_task_count': retryTaskCount,
        'retry_rate': _ratioOrZero(retryTaskCount, totalTaskCount),
        'missing_card_count': missingCardCount,
        'incomplete_card_count': incompleteCardCount,
        'task_status_totals': taskStatusTotals,
        'task_type_status_totals': taskTypeStatusTotals,
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
              : recordElapsedMs.reduce((a, b) => a + b) ~/
                  recordElapsedMs.length,
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
          _intValue(llmUsageTotals['total_tokens']) ?? 0,
          recordCount,
        ),
        'tokens_per_successful_input': _ratioOrZero(
          _intValue(llmUsageTotals['total_tokens']) ?? 0,
          completedCards,
        ),
        'llm_usage_total': llmUsageTotals,
        'tokens_by_agent': llmUsageByAgent,
        'prompt_tokens_by_agent': _usageFieldByAgent(
          llmUsageByAgent,
          'prompt_tokens',
        ),
        'completion_tokens_by_agent': _usageFieldByAgent(
          llmUsageByAgent,
          'completion_tokens',
        ),
        'thought_tokens_by_agent': _usageFieldByAgent(
          llmUsageByAgent,
          'thought_tokens',
        ),
        'prompt_cache_token_hit_rate_by_agent':
            _promptCacheHitRateByAgent(llmUsageByAgent),
        'prompt_cache_token_hit_rate': _ratioOrZero(
          _intValue(llmUsageTotals['cached_tokens_for_rate']) ?? 0,
          _intValue(llmUsageTotals['effective_prompt_tokens']) ?? 0,
        ),
        'slowest_records': _slowestRecordSummaries(modeObservations),
        'judge_task_count': judgeTasks.length,
        'judge_tasks': judgeTasks,
        'elapsed_ms': elapsed.inMilliseconds,
        'observation_count': modeObservations.length,
        'failure_category_counts': _failureCategoryCounts(
          failures.where((failure) => failure['mode'] == mode.storageValue),
        ),
        ...datasetCoverage,
      };
      allJudgeTasks.addAll(judgeTasks);
    }

    final comparison = _compareModes(metricsByMode);
    final gate = _evaluateGate(metricsByMode, comparison);

    await _writeJsonl(
        File(p.join(runDir.path, 'observations.jsonl')), observations);
    await _writeJsonl(File(p.join(runDir.path, 'failures.jsonl')), failures);
    await _writeJsonl(
      File(p.join(runDir.path, 'judge_tasks.jsonl')),
      allJudgeTasks,
    );
    await File(p.join(runDir.path, 'metrics.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'dataset_path': datasetPath,
        'llm_enabled': _llmEnabled,
        'modes': modes.map((mode) => mode.storageValue).toList(),
        'case_offset': _caseOffset,
        'case_limit': _caseLimit,
        'iteration': _iterationMetadata(),
        'dataset_coverage': datasetCoverage,
        'llm_preflight': llmPreflight,
        'metrics_by_mode': metricsByMode,
        'comparison': comparison,
        'gate': gate,
        'judge_task_count': allJudgeTasks.length,
        'secrets': {
          'llm_api_key': _llmEnabled ? '<redacted>' : null,
          'embedding_api_key':
              Platform.environment['MEMEX_EVAL_EMBEDDING_API_KEY'] == null
                  ? null
                  : '<redacted>',
        },
      }),
      flush: true,
    );
    await File(p.join(runDir.path, 'gate.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(gate),
      flush: true,
    );
    await File(p.join(runDir.path, 'report.md')).writeAsString(
      _renderReport(
        datasetPath: datasetPath,
        modes: modes.map((mode) => mode.storageValue).toList(),
        caseOffset: _caseOffset,
        caseLimit: _caseLimit,
        llmPreflight: llmPreflight,
        metricsByMode: metricsByMode,
        comparison: comparison,
        gate: gate,
        failures: failures,
      ),
      flush: true,
    );
    await File(p.join(runDir.path, 'case_debug_index.md')).writeAsString(
      _renderCaseDebugIndex(
        modes: modes.map((mode) => mode.storageValue).toList(),
        observations: observations,
        failures: failures,
      ),
      flush: true,
    );

    expect(File(p.join(runDir.path, 'metrics.json')).existsSync(), isTrue);
    expect(File(p.join(runDir.path, 'gate.json')).existsSync(), isTrue);
    expect(File(p.join(runDir.path, 'report.md')).existsSync(), isTrue);
    expect(File(p.join(runDir.path, 'failures.jsonl')).existsSync(), isTrue);
    expect(File(p.join(runDir.path, 'judge_tasks.jsonl')).existsSync(), isTrue);
    expect(
        File(p.join(runDir.path, 'case_debug_index.md')).existsSync(), isTrue);
    if (Platform.environment['MEMEX_EVAL_ENFORCE_GATE'] == '1') {
      expect(gate['status'], equals('pass'));
    }
  }, timeout: Timeout(_suiteTimeout));
}

bool get _llmEnabled =>
    Platform.environment['MEMEX_EVAL_ENABLE_LLM'] == '1' ||
    Platform.environment['EVAL_LLM_ENABLE'] == '1';

bool get _llmPreflightOnly =>
    Platform.environment['MEMEX_EVAL_LLM_PREFLIGHT_ONLY'] == '1';

bool get _skipLlmPreflight =>
    Platform.environment['MEMEX_EVAL_SKIP_LLM_PREFLIGHT'] == '1';

bool get _llmPreflightWarnOnly =>
    Platform.environment['MEMEX_EVAL_LLM_PREFLIGHT_WARN_ONLY'] == '1';

int? get _caseLimit => _intFromEnv('MEMEX_EVAL_CASE_LIMIT');

int get _caseOffset => _intFromEnv('MEMEX_EVAL_CASE_OFFSET') ?? 0;

Set<String>? get _changedCaseIds {
  final raw = _firstEnv(['MEMEX_EVAL_CHANGED_CASES']);
  if (raw == null || raw.trim().isEmpty) return null;
  final ids = raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
  return ids.isEmpty ? null : ids;
}

Duration get _taskTimeout => Duration(
      seconds: _intFromEnv('MEMEX_EVAL_TASK_TIMEOUT_SECONDS') ?? 120,
    );

Duration get _askTimeout => Duration(
      seconds: _intFromEnv('MEMEX_EVAL_ASK_TIMEOUT_SECONDS') ?? 180,
    );

Duration get _suiteTimeout => Duration(
      seconds: _intFromEnv('MEMEX_EVAL_SUITE_TIMEOUT_SECONDS') ?? 900,
    );

List<AgentPipelineMode> _pipelineModes() {
  final raw = Platform.environment['MEMEX_EVAL_PIPELINE_MODES'] ??
      Platform.environment['MEMEX_EVAL_MODES'] ??
      'legacy_pkm,memory_primary';
  return raw
      .split(',')
      .map((item) => AgentPipelineMode.fromStorageValue(item.trim()))
      .toSet()
      .toList(growable: false);
}

Future<void> _configureOptionalLlm({int slot = 0}) async {
  if (!_llmEnabled) {
    await UserStorage.resetLLMConfigs();
    return;
  }

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
}

_EvalLlmConfig _llmConfigForSlot(int slot) {
  final baseUrls = _envList('MEMEX_EVAL_LLM_BASE_URLS');
  final apiKeys = _envList('MEMEX_EVAL_LLM_API_KEYS');
  final fallbackBaseUrl =
      _firstEnv(['MEMEX_EVAL_LLM_BASE_URL', 'EVAL_LLM_BASE_URL']);
  final fallbackApiKey =
      _firstEnv(['MEMEX_EVAL_LLM_API_KEY', 'EVAL_LLM_API_KEY']);
  final configCount = baseUrls.isNotEmpty && apiKeys.isNotEmpty
      ? (baseUrls.length < apiKeys.length ? baseUrls.length : apiKeys.length)
      : 0;
  final providerOrder = _llmProviderOrder(configCount);
  final configIndex =
      configCount == 0 ? 0 : providerOrder[slot % providerOrder.length];
  final baseUrl = configCount == 0 ? fallbackBaseUrl : baseUrls[configIndex];
  final apiKey = configCount == 0 ? fallbackApiKey : apiKeys[configIndex];
  final model =
      _firstEnv(['MEMEX_EVAL_LLM_MODEL', 'EVAL_LLM_MODEL']) ?? 'mimo-v2.5';
  final type =
      _firstEnv(['MEMEX_EVAL_LLM_TYPE', 'EVAL_LLM_TYPE']) ?? LLMConfig.typeMimo;
  if (baseUrl == null || apiKey == null) {
    throw StateError(
      'MEMEX_EVAL_ENABLE_LLM=1 requires MEMEX_EVAL_LLM_BASE_URL and '
      'MEMEX_EVAL_LLM_API_KEY.',
    );
  }

  return _EvalLlmConfig(
    slot: slot,
    configIndex: configIndex,
    type: type,
    model: model,
    baseUrl: baseUrl,
    apiKey: apiKey,
    priority: _llmProviderPriority(configIndex),
  );
}

List<int> _llmProviderOrder(int configCount) {
  if (configCount <= 0) return const [0];
  final indexes = List<int>.generate(configCount, (index) => index);
  indexes.sort((a, b) {
    final priorityComparison =
        _llmProviderPriority(b).compareTo(_llmProviderPriority(a));
    if (priorityComparison != 0) return priorityComparison;
    return a.compareTo(b);
  });
  return indexes;
}

int _llmProviderPriority(int index) {
  final priorities = _intEnvList('MEMEX_EVAL_LLM_PROVIDER_PRIORITIES');
  if (index < 0 || index >= priorities.length) return 0;
  return priorities[index];
}

Future<JsonMap?> _runLlmPreflight({
  required Directory runDir,
  required int slotOffset,
  required int slotCount,
}) async {
  if (!_llmEnabled) return null;

  final artifactFile = File(p.join(runDir.path, 'llm_preflight.json'));
  if (_skipLlmPreflight) {
    final skipped = {
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'skipped': true,
      'reason': 'MEMEX_EVAL_SKIP_LLM_PREFLIGHT=1',
      'passed': true,
    };
    await artifactFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(skipped),
      flush: true,
    );
    return skipped;
  }

  final configs = _uniqueLlmConfigsForSlots(
    slotOffset: slotOffset,
    slotCount: slotCount,
  );
  final results = <JsonMap>[];
  for (final config in configs) {
    results.add(await _preflightLlmConfig(config));
  }
  final passed = results.every((result) => result['ok'] == true);
  final artifact = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'skipped': false,
    'required': !_llmPreflightWarnOnly,
    'passed': passed,
    'result_count': results.length,
    'results': results,
  };
  await artifactFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
    flush: true,
  );

  if (!passed) {
    await File(p.join(runDir.path, 'report.md')).writeAsString(
      _renderPreflightFailureReport(artifact),
      flush: true,
    );
    if (!_llmPreflightWarnOnly) {
      final failed = results
          .where((result) => result['ok'] != true)
          .map(
            (result) =>
                '${result['type']}/${result['model']} at ${result['base_url']}: '
                '${result['status_code'] ?? 'no_status'} ${result['error'] ?? ''}',
          )
          .join('; ');
      throw StateError(
        'LLM preflight failed. Fix provider/model config before full replay. '
        '$failed',
      );
    }
  }

  return artifact;
}

List<_EvalLlmConfig> _uniqueLlmConfigsForSlots({
  required int slotOffset,
  required int slotCount,
}) {
  final slots = slotCount <= 0 ? 1 : slotCount;
  final configs = <_EvalLlmConfig>[];
  final seen = <String>{};
  for (var slot = 0; slot < slots; slot++) {
    final config = _llmConfigForSlot(slotOffset + slot);
    final key =
        '${config.configIndex}|${config.type}|${config.baseUrl}|${config.model}|${config.apiKey.hashCode}';
    if (seen.add(key)) configs.add(config);
  }
  return configs;
}

Future<JsonMap> _preflightLlmConfig(_EvalLlmConfig config) async {
  final startedAt = DateTime.now();
  final underlying = LLMConfig.underlyingClientType(config.type) ?? config.type;
  final result = {
    'slot': config.slot,
    'config_index': config.configIndex,
    'provider_priority': config.priority,
    'type': config.type,
    'underlying_type': underlying,
    'model': config.model,
    'base_url': config.baseUrl,
    'api_key': '<redacted>',
  };
  try {
    late final _HttpJsonResponse response;
    if (underlying == LLMConfig.typeClaude) {
      response = await _postJson(
        _anthropicMessagesEndpoint(config.baseUrl),
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          'model': config.model,
          'max_tokens': 8,
          'messages': [
            {
              'role': 'user',
              'content': 'Return ok.',
            }
          ],
        },
      );
    } else if (underlying == LLMConfig.typeChatCompletion) {
      response = await _postJson(
        _openAiChatCompletionsEndpoint(config.baseUrl),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        body: {
          'model': config.model,
          'messages': [
            {
              'role': 'user',
              'content': 'Return ok.',
            }
          ],
          'max_tokens': 8,
          'temperature': 0,
        },
      );
    } else if (underlying == LLMConfig.typeResponses) {
      response = await _postJson(
        _openAiResponsesEndpoint(config.baseUrl),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        body: {
          'model': config.model,
          'input': 'Return ok.',
          'max_output_tokens': 8,
        },
      );
    } else {
      return {
        ...result,
        'ok': true,
        'skipped': true,
        'reason': 'No eval preflight request implemented for $underlying',
        'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
      };
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    return {
      ...result,
      'ok': ok,
      'status_code': response.statusCode,
      'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
      if (!ok) 'error': _summarizeProviderError(response.body),
      if (ok) 'response_excerpt': _truncateString(response.body, 500),
    };
  } catch (error) {
    return {
      ...result,
      'ok': false,
      'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
      'error': _truncateString(error.toString(), 1000),
    };
  }
}

Future<_HttpJsonResponse> _postJson(
  Uri uri, {
  required Map<String, String> headers,
  required JsonMap body,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.postUrl(uri).timeout(
          const Duration(seconds: 20),
        );
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode(body));
    final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
    final responseBody = await utf8.decoder.bind(response).join();
    return _HttpJsonResponse(response.statusCode, responseBody);
  } finally {
    client.close(force: true);
  }
}

Uri _anthropicMessagesEndpoint(String baseUrl) {
  final base = _stripTrailingSlash(baseUrl);
  final endpoint =
      base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages';
  return Uri.parse(endpoint);
}

Uri _openAiChatCompletionsEndpoint(String baseUrl) {
  final base = _stripTrailingSlash(baseUrl);
  final endpoint = base.endsWith('/v1')
      ? '$base/chat/completions'
      : '$base/v1/chat/completions';
  return Uri.parse(endpoint);
}

Uri _openAiResponsesEndpoint(String baseUrl) {
  final base = _stripTrailingSlash(baseUrl);
  final endpoint =
      base.endsWith('/v1') ? '$base/responses' : '$base/v1/responses';
  return Uri.parse(endpoint);
}

String _stripTrailingSlash(String value) {
  var trimmed = value.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

String _summarizeProviderError(String body) {
  try {
    final decoded = jsonDecode(body);
    return _truncateString(jsonEncode(_sanitizeForLog(decoded)), 1000);
  } catch (_) {
    return _truncateString(body, 1000);
  }
}

Future<List<JsonMap>> _loadCases(String datasetPath) async {
  final lines = await File(datasetPath).readAsLines();
  final cases = <JsonMap>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    cases.add(jsonDecode(trimmed) as JsonMap);
  }
  if (cases.isEmpty) throw StateError('No eval cases found: $datasetPath');
  return cases;
}

Future<_SuperAgentAskResult> _runSuperAgentAsk(
  MemexRouter router,
  JsonMap operation,
) async {
  if (!_llmEnabled && operation['requires_llm'] != false) {
    return const _SuperAgentAskResult(
      answer: '',
      events: [
        {
          'type': 'skipped',
          'reason': 'MEMEX_EVAL_ENABLE_LLM is not enabled',
        }
      ],
      tokenUsageEvents: [],
      error: 'skipped_without_llm',
    );
  }

  final answer = StringBuffer();
  final events = <JsonMap>[];
  final tokenUsageEvents = <JsonMap>[];
  String? sessionId = operation['session_id']?.toString();
  String? error;
  final startedAt = DateTime.now();

  try {
    final stream = router.sendMessage(
      operation['query']?.toString() ?? '',
      sessionId: sessionId,
      agentName: operation['agent_name']?.toString() ?? 'memex_agent',
      scene: operation['scene']?.toString() ?? 'assistant',
      sceneId: operation['scene_id']?.toString(),
      refs: _refs(operation['refs']),
      isQuickQuery: operation['quick_query'] != false,
    );
    await for (final event in stream.timeout(_askTimeout)) {
      final serialized = {
        ..._serializeChatEvent(event),
        'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
      };
      events.add(serialized);
      if (event is ChatSessionCreatedEvent) {
        sessionId = event.sessionId;
      } else if (event is ChatResponseChunkEvent) {
        answer.write(event.text);
      } else if (event is ChatTokenUsageEvent) {
        tokenUsageEvents.add(serialized);
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
    tokenUsageEvents: tokenUsageEvents,
    error: error,
  );
}

List<Map<String, String>>? _refs(Object? value) {
  final refs = _list(value)
      .whereType<Map>()
      .map((item) => item.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ))
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
  if (event is ChatErrorEvent) {
    return {'type': 'error', 'error': event.error};
  }
  if (event is ChatAgentStartedEvent) {
    return {'type': 'agent_started'};
  }
  if (event is ChatAgentStoppedEvent) {
    return {'type': 'agent_stopped'};
  }
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

String _caseUserId(JsonMap evalCase, AgentPipelineMode mode, int index) {
  final persona = _map(evalCase['persona']);
  final base = persona['user_id']?.toString() ?? 'eval_user_$index';
  final safeBase = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return '${safeBase}_${mode.storageValue}_${DateTime.now().microsecondsSinceEpoch}';
}

Future<_TaskWaitResult> _waitForTasksToSettle({
  required int previousTaskCount,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastTasks = <dynamic>[];
  while (DateTime.now().isBefore(deadline)) {
    final tasks = await LocalTaskExecutor.instance.getTasks(limit: 4000);
    lastTasks = tasks;
    final active = tasks
        .where((task) =>
            ['pending', 'processing', 'retrying'].contains(task.status))
        .toList();
    if (tasks.length > previousTaskCount && active.isEmpty) {
      return _TaskWaitResult(
        tasks: tasks,
        newTaskCount: tasks.length - previousTaskCount,
        settled: true,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return _TaskWaitResult(
    tasks: lastTasks,
    newTaskCount: (lastTasks.length - previousTaskCount)
        .clamp(
          0,
          lastTasks.length,
        )
        .toInt(),
    settled: false,
  );
}

void _mergeStatusCounts(Map<String, int> target, Map<String, int> source) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

void _mergeTaskTypeStatusCounts(
  Map<String, Map<String, int>> target,
  Iterable<dynamic> tasks,
) {
  for (final task in tasks) {
    final type = task.type?.toString() ?? 'unknown';
    final status = task.status?.toString() ?? 'unknown';
    final bucket = target.putIfAbsent(type, () => <String, int>{});
    bucket[status] = (bucket[status] ?? 0) + 1;
  }
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
      'empty_response_turns': 0,
    };

void _mergeLlmUsage(
  JsonMap totalTarget,
  Map<String, JsonMap> byAgentTarget,
  JsonMap stats,
) {
  _mergeUsageBucket(totalTarget, _map(stats['total']));
  for (final entry in _map(stats['by_agent']).entries) {
    final agent = entry.key;
    final bucket = byAgentTarget.putIfAbsent(agent, _emptyUsageBucket);
    _mergeUsageBucket(bucket, _map(entry.value));
  }
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
    'empty_response_turns',
  ]) {
    target[key] = (_intValue(target[key]) ?? 0) + (_intValue(source[key]) ?? 0);
  }
}

JsonMap _sumChatTokenUsage(Iterable<JsonMap> tokenUsageEvents) {
  final result = _emptyUsageBucket();
  for (final event in tokenUsageEvents) {
    result['calls'] = (_intValue(result['calls']) ?? 0) + 1;
    result['prompt_tokens'] = (_intValue(result['prompt_tokens']) ?? 0) +
        (_intValue(event['prompt_tokens']) ?? 0);
    result['completion_tokens'] =
        (_intValue(result['completion_tokens']) ?? 0) +
            (_intValue(event['completion_tokens']) ?? 0);
    result['cached_tokens'] = (_intValue(result['cached_tokens']) ?? 0) +
        (_intValue(event['cached_tokens']) ?? 0);
    result['effective_prompt_tokens'] =
        (_intValue(result['effective_prompt_tokens']) ?? 0) +
            (_intValue(event['effective_prompt_tokens']) ?? 0);
    result['cached_tokens_for_rate'] =
        (_intValue(result['cached_tokens_for_rate']) ?? 0) +
            (_intValue(event['cached_tokens_for_rate']) ?? 0);
    result['total_tokens'] = (_intValue(result['total_tokens']) ?? 0) +
        (_intValue(event['total_tokens']) ?? 0);
  }
  return result;
}

bool _isSchemaValidCard(dynamic card) {
  return card.factId.toString().isNotEmpty &&
      (card.timestamp as int) > 0 &&
      card.status.toString().isNotEmpty &&
      card.uiConfigs.isNotEmpty &&
      card.uiConfigs.every((config) => config.templateId.toString().isNotEmpty);
}

int _duplicateTextCount(Iterable<String> values) {
  final seen = <String>{};
  var duplicates = 0;
  for (final value in values) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) continue;
    if (!seen.add(normalized)) duplicates += 1;
  }
  return duplicates;
}

_ExpectationEvalResult _evaluateTextExpectations({
  required String haystack,
  required List<_TextExpectation> mustContain,
  required List<_TextExpectation> mustNotContain,
  required String mode,
  required String caseId,
  required String operationId,
  required String missingCategory,
  required String forbiddenCategory,
}) {
  final failures = <JsonMap>[];
  var mustHits = 0;
  for (final expectation in mustContain) {
    if (expectation.matches(haystack)) {
      mustHits += 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: missingCategory,
        message: 'Expected text was missing.',
        details: {
          'label': expectation.label,
          'alternatives': expectation.alternatives,
          if (expectation.regexPattern != null)
            'regex': expectation.regexPattern,
        },
      ));
    }
  }

  var forbiddenHits = 0;
  for (final expectation in mustNotContain) {
    if (expectation.matches(haystack)) {
      forbiddenHits += 1;
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: forbiddenCategory,
        message: 'Forbidden text was present.',
        details: {
          'label': expectation.label,
          'alternatives': expectation.alternatives,
          if (expectation.regexPattern != null)
            'regex': expectation.regexPattern,
        },
      ));
    }
  }

  return _ExpectationEvalResult(
    mustHits: mustHits,
    mustTotal: mustContain.length,
    forbiddenHits: forbiddenHits,
    forbiddenTotal: mustNotContain.length,
    failures: failures,
  );
}

Future<_ExpectationEvalResult> _evaluateRelatedFactExpectations({
  required String mode,
  required String caseId,
  required String userId,
  required List<dynamic> expectations,
  required Map<String, String> factIdsByOperation,
}) async {
  final failures = <JsonMap>[];
  var hits = 0;
  var total = 0;

  for (final rawExpectation in expectations) {
    final expectation = _map(rawExpectation);
    final operationId = expectation['operation_id']?.toString() ?? '';
    final factId = factIdsByOperation[operationId] ??
        expectation['fact_id']?.toString() ??
        '';
    if (factId.isEmpty) {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'related_fact_target_missing',
        message: 'Related-fact expectation target could not be resolved.',
        details: expectation,
      ));
      continue;
    }
    final expectedFactIds = <String>{
      ..._strings(expectation['expected_related_fact_ids']),
      for (final op in _strings(expectation['expected_related_operation_ids']))
        if (factIdsByOperation[op] != null) factIdsByOperation[op]!,
    };
    if (expectedFactIds.isEmpty) continue;
    final card = await FileSystemService.instance.readCardFile(userId, factId);
    final relatedIds =
        card?.insight?.relatedFacts.map((related) => related.id).toSet() ??
            const <String>{};

    for (final expectedFactId in expectedFactIds) {
      total += 1;
      if (relatedIds.contains(expectedFactId)) {
        hits += 1;
      } else {
        failures.add(_failure(
          mode: mode,
          caseId: caseId,
          operationId: operationId,
          category: 'related_fact_missing',
          message: 'Expected related fact was not cited by card insight.',
          details: {
            'target_fact_id': factId,
            'expected_related_fact_id': expectedFactId,
            'actual_related_fact_ids': relatedIds.toList(),
          },
        ));
      }
    }
  }

  return _ExpectationEvalResult(
    mustHits: hits,
    mustTotal: total,
    forbiddenHits: 0,
    forbiddenTotal: 0,
    failures: failures,
  );
}

JsonMap _modeSpecificExpected(JsonMap expected, String mode) {
  final byMode = _map(expected['by_mode']);
  final override = _map(byMode[mode]);
  if (override.isEmpty) return expected;
  final base = Map<String, dynamic>.from(expected)..remove('by_mode');
  return {...base, ...override};
}

_RouteEvalResult _evaluateRouteExpectation({
  required String mode,
  required String caseId,
  required String operationId,
  required JsonMap expected,
  required Iterable<dynamic> tasks,
}) {
  final scoped = _modeSpecificExpected(expected, mode);
  final expectedTaskTypes = _strings(scoped['expected_task_types']).toSet();
  final forbiddenTaskTypes = _strings(scoped['forbidden_task_types']).toSet();
  if (expectedTaskTypes.isEmpty && forbiddenTaskTypes.isEmpty) {
    return const _RouteEvalResult();
  }

  final observedTaskTypes = _agentTaskTypesFromTasks(tasks);
  final missing = expectedTaskTypes.difference(observedTaskTypes);
  final forbiddenHits = observedTaskTypes.intersection(forbiddenTaskTypes);
  final failures = <JsonMap>[];
  for (final type in missing) {
    failures.add(_failure(
      mode: mode,
      caseId: caseId,
      operationId: operationId,
      category: 'agent_route_missing',
      message: 'Expected downstream task type was not triggered.',
      details: {
        'expected_task_type': type,
        'observed_task_types': observedTaskTypes.toList()..sort(),
      },
    ));
  }
  for (final type in forbiddenHits) {
    failures.add(_failure(
      mode: mode,
      caseId: caseId,
      operationId: operationId,
      category: 'agent_route_overtrigger',
      message: 'Forbidden downstream task type was triggered.',
      details: {
        'forbidden_task_type': type,
        'observed_task_types': observedTaskTypes.toList()..sort(),
      },
    ));
  }

  return _RouteEvalResult(
    accuracyHits: missing.isEmpty && forbiddenHits.isEmpty ? 1 : 0,
    accuracyTotal: 1,
    missCount: missing.length,
    expectedCount: expectedTaskTypes.length,
    overtriggerCount: forbiddenHits.length,
    observedCount: observedTaskTypes.isEmpty ? 1 : observedTaskTypes.length,
    failures: failures,
  );
}

Set<String> _agentTaskTypesFromTasks(Iterable<dynamic> tasks) {
  final ignored = {
    'fts_index_update',
    'handle_analyze_assets',
  };
  return tasks
      .map((task) => task.type?.toString())
      .whereType<String>()
      .where((type) => !ignored.contains(type))
      .where((type) => type.endsWith('_task'))
      .toSet();
}

_CardMetricEvalResult _evaluateCardMetricExpectations({
  required String mode,
  required String caseId,
  required String operationId,
  required JsonMap expected,
  required dynamic card,
}) {
  final scoped = _modeSpecificExpected(expected, mode);
  if (scoped.isEmpty) return const _CardMetricEvalResult();

  final failures = <JsonMap>[];
  final templateIds = _cardTemplateIds(card);
  final expectedTemplates = _strings(scoped['expected_template_ids']).toSet();
  var templatePrimaryHits = 0;
  var templateAnyHits = 0;
  var templateTotal = 0;
  if (expectedTemplates.isNotEmpty) {
    templateTotal = 1;
    if (templateIds.isNotEmpty &&
        expectedTemplates.contains(templateIds.first)) {
      templatePrimaryHits = 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'card_template_primary_mismatch',
        message: 'Primary card template did not match expected set.',
        details: {
          'expected_template_ids': expectedTemplates.toList()..sort(),
          'actual_template_ids': templateIds,
        },
      ));
    }
    if (templateIds.any(expectedTemplates.contains)) {
      templateAnyHits = 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'card_template_any_mismatch',
        message: 'No card template matched expected set.',
        details: {
          'expected_template_ids': expectedTemplates.toList()..sort(),
          'actual_template_ids': templateIds,
        },
      ));
    }
  }

  final blob = _cardSearchBlob(card);
  final fieldEval = _evaluateTextExpectations(
    haystack: blob,
    mustContain: _textExpectations(
      scoped['field_must_contain'] ?? scoped['must_contain'],
    ),
    mustNotContain: const [],
    mode: mode,
    caseId: caseId,
    operationId: operationId,
    missingCategory: 'card_field_missing',
    forbiddenCategory: 'card_field_forbidden_present',
  );
  final entityEval = _evaluateTextExpectations(
    haystack: blob,
    mustContain: _textExpectations(scoped['expected_entities']),
    mustNotContain: const [],
    mode: mode,
    caseId: caseId,
    operationId: operationId,
    missingCategory: 'card_entity_missing',
    forbiddenCategory: 'card_entity_forbidden_present',
  );
  final hallucinationEval = _evaluateTextExpectations(
    haystack: blob,
    mustContain: const [],
    mustNotContain: _textExpectations(
      scoped['must_not_fields'] ?? scoped['must_not_contain'],
    ),
    mode: mode,
    caseId: caseId,
    operationId: operationId,
    missingCategory: 'card_unexpected_missing',
    forbiddenCategory: 'card_hallucinated_field_present',
  );
  failures.addAll(fieldEval.failures);
  failures.addAll(entityEval.failures);
  failures.addAll(hallucinationEval.failures);

  var timeHits = 0;
  var timeTotal = 0;
  final expectedTime = scoped['expected_time']?.toString();
  final toleranceMinutes = _intValue(scoped['time_tolerance_minutes']) ?? 0;
  if (expectedTime != null && expectedTime.isNotEmpty) {
    timeTotal = 1;
    final expectedDateTime = DateTime.tryParse(expectedTime);
    final actualTimestamp = _intValue(card?.timestamp);
    if (expectedDateTime != null && actualTimestamp != null) {
      final actual = DateTime.fromMillisecondsSinceEpoch(
        actualTimestamp < 100000000000
            ? actualTimestamp * 1000
            : actualTimestamp,
      );
      final diffMinutes = actual.difference(expectedDateTime).inMinutes.abs();
      if (diffMinutes <= toleranceMinutes) {
        timeHits = 1;
      } else {
        failures.add(_failure(
          mode: mode,
          caseId: caseId,
          operationId: operationId,
          category: 'card_time_parse_mismatch',
          message: 'Card timestamp was outside expected tolerance.',
          details: {
            'expected_time': expectedTime,
            'actual_timestamp': actual.toIso8601String(),
            'diff_minutes': diffMinutes,
            'tolerance_minutes': toleranceMinutes,
          },
        ));
      }
    }
  }

  return _CardMetricEvalResult(
    templatePrimaryHits: templatePrimaryHits,
    templateAnyHits: templateAnyHits,
    templateTotal: templateTotal,
    fieldRecallHits: fieldEval.mustHits,
    fieldRecallTotal: fieldEval.mustTotal,
    entityRecallHits: entityEval.mustHits,
    entityRecallTotal: entityEval.mustTotal,
    timeParseHits: timeHits,
    timeParseTotal: timeTotal,
    hallucinatedAbsenceHits:
        hallucinationEval.forbiddenTotal - hallucinationEval.forbiddenHits,
    hallucinatedAbsenceTotal: hallucinationEval.forbiddenTotal,
    failures: failures,
  );
}

List<String> _cardTemplateIds(dynamic card) {
  final raw = card?.uiConfigs;
  if (raw is! Iterable) return const [];
  return raw
      .map((config) => config.templateId?.toString())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

String _cardSearchBlob(dynamic card) {
  if (card == null) return '';
  try {
    return jsonEncode(card.toJson());
  } catch (_) {
    return card.toString();
  }
}

_SuperAgentToolEvalResult _evaluateSuperAgentToolExpectations({
  required String mode,
  required String caseId,
  required String operationId,
  required JsonMap expected,
  required List<JsonMap> events,
}) {
  final scoped = _modeSpecificExpected(expected, mode);
  final calls = events.where((event) => event['type'] == 'tool_call').toList();
  final results =
      events.where((event) => event['type'] == 'tool_result').toList();
  final callNames = calls.map((event) => event['name']?.toString() ?? '');
  final callNameSet = callNames.where((name) => name.isNotEmpty).toSet();
  final failures = <JsonMap>[];

  final expectedTools =
      _strings(scoped['expected_tools'] ?? scoped['tools_must_call']);
  var toolSelectionHits = 0;
  var toolSelectionTotal = 0;
  for (final tool in expectedTools) {
    toolSelectionTotal += 1;
    if (callNameSet.contains(tool)) {
      toolSelectionHits += 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'tool_selection_missing',
        message: 'Expected tool was not called.',
        details: {'expected_tool': tool, 'actual_tools': callNameSet.toList()},
      ));
    }
  }

  final forbiddenTools =
      _strings(scoped['forbidden_tools'] ?? scoped['prohibited_tools']);
  final readOnlyExpected = scoped['read_only'] == true ||
      scoped['readonly'] == true ||
      forbiddenTools.isNotEmpty;
  var readOnlyHits = 0;
  var readOnlyTotal = 0;
  if (readOnlyExpected) {
    readOnlyTotal = 1;
    final violations = calls.where((call) {
      final name = call['name']?.toString() ?? '';
      return forbiddenTools.contains(name) || _isWriteToolName(name);
    }).toList();
    if (violations.isEmpty) {
      readOnlyHits = 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'super_agent_read_only_violation',
        message: 'Read-only Super Agent ask used a write-like tool.',
        details: {'violating_tools': violations.map((e) => e['name']).toList()},
      ));
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
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'tool_args_mismatch',
        message: 'Expected tool arguments were not observed.',
        details: {
          'tool': tool,
          'must_contain': needles,
          'actual_args': matchingCalls
              .map((call) => call['arguments']?.toString() ?? '')
              .toList(),
        },
      ));
    }
  }

  var minimalityHits = 0;
  var minimalityTotal = 0;
  final maxToolCalls = _intValue(scoped['max_tool_calls']);
  if (maxToolCalls != null) {
    minimalityTotal = 1;
    if (calls.length <= maxToolCalls) {
      minimalityHits = 1;
    } else {
      failures.add(_failure(
        mode: mode,
        caseId: caseId,
        operationId: operationId,
        category: 'tool_call_minimality_violation',
        message: 'Tool call count exceeded expected maximum.',
        details: {'actual': calls.length, 'max': maxToolCalls},
      ));
    }
  }

  final expectedSources = _strings(
    scoped['expected_sources'] ?? scoped['retrieval_expected_sources'],
  );
  final rankedSources = _rankedSourcesFromToolResults(results);
  final retrieval = _evaluateRetrievalHits(
    mode: mode,
    caseId: caseId,
    operationId: operationId,
    expectedSources: expectedSources,
    rankedSources: rankedSources,
  );
  failures.addAll(retrieval.failures);

  final failedResults =
      results.where((result) => result['is_error'] == true).toList();
  final seenCalls = <String>{};
  var repeatedCalls = 0;
  for (final call in calls) {
    final key = '${call['name']}|${call['arguments']}';
    if (!seenCalls.add(key)) repeatedCalls += 1;
  }
  final readCalls = calls.where((call) {
    final name = call['name']?.toString() ?? '';
    return _isReadToolName(name);
  }).toList();
  final writeCalls = calls.where((call) {
    final name = call['name']?.toString() ?? '';
    return _isWriteToolName(name);
  }).toList();
  final readErrors = failedResults.where((result) {
    final name = result['name']?.toString() ?? '';
    return _isReadToolName(name);
  }).length;
  final writeErrors = failedResults.where((result) {
    final name = result['name']?.toString() ?? '';
    return _isWriteToolName(name);
  }).length;

  return _SuperAgentToolEvalResult(
    retrievalHitAt1Hits: retrieval.hitAt1Hits,
    retrievalHitAt1Total: retrieval.total,
    retrievalHitAt3Hits: retrieval.hitAt3Hits,
    retrievalHitAt3Total: retrieval.total,
    retrievalHitAt5Hits: retrieval.hitAt5Hits,
    retrievalHitAt5Total: retrieval.total,
    retrievalHitAt10Hits: retrieval.hitAt10Hits,
    retrievalHitAt10Total: retrieval.total,
    readOnlyHits: readOnlyHits,
    readOnlyTotal: readOnlyTotal,
    toolSelectionHits: toolSelectionHits,
    toolSelectionTotal: toolSelectionTotal,
    toolArgsHits: toolArgsHits,
    toolArgsTotal: toolArgsTotal,
    toolCallMinimalityHits: minimalityHits,
    toolCallMinimalityTotal: minimalityTotal,
    toolCallCount: calls.length,
    toolCallFailureCount: failedResults.length,
    toolCallRetryCount: 0,
    repeatedToolCallCount: repeatedCalls,
    readToolCallCount: readCalls.length,
    readToolErrorCount: readErrors,
    writeToolCallCount: writeCalls.length,
    writeToolErrorCount: writeErrors,
    contextPeekCount: readCalls.length,
    contextPeekTaskCount: 1,
    agentToolRoundCount: calls.length,
    agentToolRoundTaskCount: 1,
    failures: failures,
  );
}

_RetrievalHitEval _evaluateRetrievalHits({
  required String mode,
  required String caseId,
  required String operationId,
  required List<String> expectedSources,
  required List<String> rankedSources,
}) {
  if (expectedSources.isEmpty) return const _RetrievalHitEval();
  final expected = expectedSources.toSet();
  bool hitAt(int k) => rankedSources.take(k).any(expected.contains);
  final failures = <JsonMap>[];
  if (!hitAt(10)) {
    failures.add(_failure(
      mode: mode,
      caseId: caseId,
      operationId: operationId,
      category: 'retrieval_hit_missing',
      message: 'No expected retrieval source appeared in top 10.',
      details: {
        'expected_sources': expectedSources,
        'ranked_sources': rankedSources.take(10).toList(),
      },
    ));
  }
  return _RetrievalHitEval(
    total: 1,
    hitAt1Hits: hitAt(1) ? 1 : 0,
    hitAt3Hits: hitAt(3) ? 1 : 0,
    hitAt5Hits: hitAt(5) ? 1 : 0,
    hitAt10Hits: hitAt(10) ? 1 : 0,
    failures: failures,
  );
}

List<String> _rankedSourcesFromToolResults(List<JsonMap> results) {
  final seen = <String>{};
  final ranked = <String>[];
  void addSource(String? source) {
    if (source != null && seen.add(source)) ranked.add(source);
  }

  final memoryBlockPattern = RegExp(
    r'- \[(mem_\d+)\][\s\S]*?(?=\n- \[mem_\d+\]|\z)',
  );
  final sourcePattern = RegExp(r'\d{4}/\d{2}/\d{2}\.md#ts_\d+|mem_\d+');
  for (final result in results) {
    final text = result['result']?.toString() ?? '';
    var parsedMemoryBlocks = false;
    for (final block in memoryBlockPattern.allMatches(text)) {
      parsedMemoryBlocks = true;
      addSource(block.group(1));
      final blockText = block.group(0) ?? '';
      for (final match
          in RegExp(r'\d{4}/\d{2}/\d{2}\.md#ts_\d+').allMatches(blockText)) {
        addSource(match.group(0));
      }
    }
    if (!parsedMemoryBlocks) {
      for (final match in sourcePattern.allMatches(text)) {
        addSource(match.group(0));
      }
      continue;
    }
    for (final match in sourcePattern.allMatches(text)) {
      addSource(match.group(0));
    }
  }
  return ranked;
}

bool _isReadToolName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('read') ||
      normalized.contains('search') ||
      normalized.contains('list') ||
      normalized.contains('get') ||
      normalized.contains('grep') ||
      normalized.contains('find') ||
      normalized.contains('lookup');
}

bool _isWriteToolName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('write') ||
      normalized.contains('save') ||
      normalized.contains('update') ||
      normalized.contains('delete') ||
      normalized.contains('create') ||
      normalized.contains('append') ||
      normalized.contains('replace') ||
      normalized.contains('enqueue') ||
      normalized.contains('mutate');
}

List<JsonMap> _judgeTasksForOperation({
  required String mode,
  required String caseId,
  required String operationId,
  required JsonMap operation,
  required JsonMap output,
}) {
  final expected = _map(operation['expected']);
  final tasks = [
    ..._list(expected['judge_tasks']),
    ..._list(_map(expected['card'])['judge_tasks']),
  ];
  return tasks.map(_map).map((task) {
    return {
      'mode': mode,
      'case_id': caseId,
      'operation_id': operationId,
      'metric': task['metric'],
      'rubric': task['rubric'],
      'input': _sanitizeForLog(operation),
      'output': _sanitizeForLog(output),
    };
  }).toList(growable: false);
}

_TaskErrorFlags _taskErrorFlags(Iterable<dynamic> tasks) {
  var loopDetection = false;
  var maxTurns = false;
  for (final task in tasks) {
    final error = task.error?.toString().toLowerCase() ?? '';
    if (error.contains('loopdetection') || error.contains('loop detection')) {
      loopDetection = true;
    }
    if (error.contains('maximum turns') || error.contains('maxturn')) {
      maxTurns = true;
    }
  }
  return _TaskErrorFlags(loopDetection: loopDetection, maxTurns: maxTurns);
}

JsonMap _usageFieldByAgent(Map<String, JsonMap> usageByAgent, String field) {
  return usageByAgent.map(
    (agent, usage) => MapEntry(agent, _intValue(usage[field]) ?? 0),
  );
}

JsonMap _promptCacheHitRateByAgent(Map<String, JsonMap> usageByAgent) {
  return usageByAgent.map((agent, usage) {
    return MapEntry(
      agent,
      _ratioOrZero(
        _intValue(usage['cached_tokens_for_rate']) ?? 0,
        _intValue(usage['effective_prompt_tokens']) ?? 0,
      ),
    );
  });
}

JsonMap _llmTurnsPerTaskByAgent(
  Map<String, JsonMap> usageByAgent,
  int totalTaskCount,
) {
  return usageByAgent.map((agent, usage) {
    return MapEntry(
      agent,
      _ratioOrZero(_intValue(usage['calls']) ?? 0, totalTaskCount),
    );
  });
}

int _activeTaskPressureFromObservation(JsonMap observation) {
  final counts = _map(observation['task_status_counts']);
  if (counts.isEmpty) return 0;
  return (_intValue(counts['pending']) ?? 0) +
      (_intValue(counts['processing']) ?? 0) +
      (_intValue(counts['retrying']) ?? 0);
}

JsonMap _failure({
  required String mode,
  required String caseId,
  required String operationId,
  required String category,
  required String message,
  JsonMap details = const {},
}) {
  return {
    'mode': mode,
    'case_id': caseId,
    'operation_id': operationId,
    'category': category,
    'message': message,
    if (details.isNotEmpty) 'details': details,
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

const _expectedScenarioFamilies = [
  'life_stream',
  'product_self_test',
  'execution_external_brain',
  'emotion_relationship_review',
  'knowledge_decision_pool',
  'sensitive_domain',
  'parsed_multimodal_context',
  'long_context_fact',
  'long_dialog_followup',
  'failure_degradation',
  'project_status',
  'preference',
  'correction',
  'noise_noop',
  'memory_recall',
  'super_agent_ask',
];

const _expectedJourneyStages = [
  'capture',
  'route',
  'card',
  'memory_write',
  'pkm',
  'recall',
  'projection',
  'ask',
  'judge',
];

const _expectedOperationTypes = [
  'record',
  'memory_recall',
  'para_projection',
  'super_agent_ask',
];

JsonMap _datasetCoverageMetrics(
  List<JsonMap> cases,
  List<AgentPipelineMode> modes,
) {
  final scenarioFamilies = <String>{};
  final journeyStages = <String>{};
  final inputChannels = <String>{};
  final operationTypes = <String>{};
  final agentChains = <String>{};
  var crossDayContinuityCases = 0;
  var correctionCases = 0;
  var noiseCases = 0;
  var followUpQueryCases = 0;
  var relationshipCases = 0;
  var longContextCases = 0;
  var oracleConsistentCases = 0;

  for (final evalCase in cases) {
    final coverage = _map(evalCase['coverage']);
    final caseScenarioFamilies = _list(coverage['scenario_families'])
        .map((item) => item.toString())
        .toList();
    scenarioFamilies.addAll(caseScenarioFamilies);
    journeyStages.addAll(
      _list(coverage['journey_stages']).map((item) => item.toString()),
    );
    inputChannels.addAll(
      _list(coverage['input_channels']).map((item) => item.toString()),
    );

    final operations = _list(evalCase['operations']).map(_map).toList();
    operationTypes.addAll(
      operations
          .map((operation) => operation['type']?.toString())
          .whereType<String>(),
    );

    if (_caseSpansMultipleDays(operations)) crossDayContinuityCases += 1;
    if (caseScenarioFamilies.contains('correction')) correctionCases += 1;
    if (caseScenarioFamilies.contains('noise_noop')) noiseCases += 1;
    if (coverage['relationship_case'] == true ||
        caseScenarioFamilies.contains('emotion_relationship_review')) {
      relationshipCases += 1;
    }
    if (coverage['long_context_case'] == true ||
        caseScenarioFamilies.contains('long_context_fact') ||
        caseScenarioFamilies.contains('long_dialog_followup')) {
      longContextCases += 1;
    }
    if (coverage['dataset_oracle_audited'] == true) {
      oracleConsistentCases += 1;
    }
    if (operations.any((operation) =>
        operation['type'] == 'memory_recall' ||
        operation['type'] == 'super_agent_ask')) {
      followUpQueryCases += 1;
    }
  }

  if (operationTypes.contains('record')) {
    agentChains.add('submit_input_to_card');
    if (modes.contains(AgentPipelineMode.legacyPkm)) {
      agentChains.add('legacy_pkm_agent');
    }
    if (modes.contains(AgentPipelineMode.memoryPrimary)) {
      agentChains.add('memory_primary_write_and_card_insight');
    }
  }
  if (operationTypes.contains('memory_recall')) {
    agentChains.add('memory_primary_recall');
  }
  if (operationTypes.contains('para_projection')) {
    agentChains.add('optional_para_projection');
  }
  if (operationTypes.contains('super_agent_ask')) {
    agentChains.add('super_agent_ask');
  }

  final expectedAgentChains = <String>{
    if (operationTypes.contains('record')) 'submit_input_to_card',
    if (operationTypes.contains('record') &&
        modes.contains(AgentPipelineMode.legacyPkm))
      'legacy_pkm_agent',
    if (operationTypes.contains('record') &&
        modes.contains(AgentPipelineMode.memoryPrimary))
      'memory_primary_write_and_card_insight',
    if (operationTypes.contains('memory_recall')) 'memory_primary_recall',
    if (operationTypes.contains('para_projection')) 'optional_para_projection',
    if (operationTypes.contains('super_agent_ask')) 'super_agent_ask',
  };

  return {
    'scenario_family_coverage': _setCoverageRate(
      scenarioFamilies,
      _expectedScenarioFamilies,
    ),
    'agent_chain_coverage': _setCoverageRate(
      agentChains,
      expectedAgentChains,
    ),
    'journey_stage_coverage': _setCoverageRate(
      journeyStages,
      _expectedJourneyStages,
    ),
    'operation_type_coverage': _setCoverageRate(
      operationTypes,
      _expectedOperationTypes,
    ),
    'cross_day_continuity_coverage': _rate(
      crossDayContinuityCases,
      cases.length,
    ),
    'correction_operation_coverage': _rate(correctionCases, cases.length),
    'noise_resilience_coverage': _rate(noiseCases, cases.length),
    'follow_up_query_coverage': _rate(followUpQueryCases, cases.length),
    'relationship_case_coverage': _rate(relationshipCases, cases.length),
    'long_context_case_coverage': _rate(longContextCases, cases.length),
    'dataset_oracle_consistency': _rate(oracleConsistentCases, cases.length),
    'coverage': {
      'covered_scenario_families': scenarioFamilies.toList()..sort(),
      'expected_scenario_families': _expectedScenarioFamilies,
      'covered_agent_chains': agentChains.toList()..sort(),
      'expected_agent_chains': expectedAgentChains.toList()..sort(),
      'covered_journey_stages': journeyStages.toList()..sort(),
      'expected_journey_stages': _expectedJourneyStages,
      'covered_input_channels': inputChannels.toList()..sort(),
      'covered_operation_types': operationTypes.toList()..sort(),
      'expected_operation_types': _expectedOperationTypes,
      'cross_day_continuity_case_count': crossDayContinuityCases,
      'correction_case_count': correctionCases,
      'noise_resilience_case_count': noiseCases,
      'follow_up_query_case_count': followUpQueryCases,
      'relationship_case_count': relationshipCases,
      'long_context_case_count': longContextCases,
      'dataset_oracle_consistent_case_count': oracleConsistentCases,
    },
  };
}

bool _caseSpansMultipleDays(List<JsonMap> operations) {
  final dates = <String>{};
  for (final operation in operations) {
    final raw = operation['time']?.toString();
    if (raw == null || raw.isEmpty) continue;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) continue;
    dates.add('${parsed.year}-${parsed.month}-${parsed.day}');
  }
  return dates.length > 1;
}

double _setCoverageRate(Set<String> covered, Iterable<String> expected) {
  final expectedSet = expected.toSet();
  if (expectedSet.isEmpty) return 1;
  return _round3(covered.intersection(expectedSet).length / expectedSet.length);
}

JsonMap _compareModes(Map<String, JsonMap> metricsByMode) {
  final legacy = metricsByMode[AgentPipelineMode.legacyPkm.storageValue];
  final memory = metricsByMode[AgentPipelineMode.memoryPrimary.storageValue];
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
    'context_peek_redundancy_rate',
    'first_write_after_read_rate',
    'agent_tool_rounds_per_task',
    'agent_empty_response_rate',
    'loop_detection_absence',
    'max_turns_absence',
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

JsonMap _evaluateGate(
  Map<String, JsonMap> metricsByMode,
  JsonMap comparison,
) {
  final mode = Platform.environment['MEMEX_EVAL_GATE_MODE'] ?? 'candidate';
  final memory = metricsByMode[AgentPipelineMode.memoryPrimary.storageValue];
  if (memory == null) {
    return {
      'mode': mode,
      'status': 'fail',
      'failed_rules': ['memory_primary metrics missing'],
    };
  }

  final maxP95RecordMs = _intFromEnv('MEMEX_EVAL_MAX_P95_RECORD_MS') ??
      (_llmEnabled ? 180000 : 20000);
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
  if (Platform.environment['MEMEX_EVAL_GATE_PROFILE'] == 'pr256_full') {
    rules.addAll([
      _minRule(memory, 'agent_route_accuracy', 0.95),
      _maxRule(memory, 'agent_route_miss_rate', 0.05),
      _maxRule(memory, 'agent_route_overtrigger_rate', 0.05),
      _minRule(memory, 'card_template_primary_accuracy', 0.80),
      _minRule(memory, 'card_template_any_accuracy', 0.90),
      _minRule(memory, 'card_field_recall', 0.95),
      _minRule(memory, 'card_entity_recall', 0.95),
      _minRule(memory, 'card_time_parse_accuracy', 0.95),
      _minRule(memory, 'card_hallucinated_field_absence', 0.95),
      _minRule(memory, 'retrieval_hit_at_10', 0.70),
      _minRule(memory, 'answer_must_include', 0.95),
      _minRule(memory, 'super_agent_read_only_compliance', 0.95),
      _minRule(memory, 'tool_selection_accuracy', 0.95),
      _minRule(memory, 'tool_args_accuracy', 0.90),
      _minRule(memory, 'tool_call_minimality', 0.95),
      _maxRule(memory, 'tool_call_failure_rate', 0.05),
      _maxRule(memory, 'repeated_tool_call_rate', 0.10),
      _maxRule(memory, 'read_tool_error_rate', 0.05),
      _maxRule(memory, 'write_tool_error_rate', 0.05),
      _minRule(memory, 'loop_detection_absence', 1.0),
      _minRule(memory, 'max_turns_absence', 1.0),
      _minRule(memory, 'scenario_family_coverage', 1.0),
      _minRule(memory, 'agent_chain_coverage', 1.0),
      _minRule(memory, 'journey_stage_coverage', 1.0),
      _minRule(memory, 'operation_type_coverage', 1.0),
      _minRule(memory, 'cross_day_continuity_coverage', 1.0),
      _minRule(memory, 'correction_operation_coverage', 1.0),
      _minRule(memory, 'noise_resilience_coverage', 1.0),
      _minRule(memory, 'follow_up_query_coverage', 1.0),
      _minRule(memory, 'relationship_case_coverage', 1.0),
      _minRule(memory, 'long_context_case_coverage', 1.0),
      _minRule(memory, 'dataset_oracle_consistency', 1.0),
    ]);
  }
  final failed = rules.where((rule) => rule['pass'] != true).toList();
  return {
    'mode': mode,
    'status': failed.isEmpty ? 'pass' : 'fail',
    'max_p95_record_ms': maxP95RecordMs,
    'rules': rules,
    'failed_rules': failed.map((rule) => rule['name']).toList(),
  };
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

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = values.toList()..sort();
  final index = ((sorted.length - 1) * percentile).ceil();
  final clampedIndex = index.clamp(0, sorted.length - 1).toInt();
  return sorted[clampedIndex];
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
    ..sort(
      (a, b) =>
          (_intValue(b['elapsed_ms']) ?? 0) - (_intValue(a['elapsed_ms']) ?? 0),
    );
  return records.take(limit).map((obs) {
    final card = _map(obs['card']);
    return {
      'case_id': obs['case_id'],
      'operation_id': obs['operation_id'],
      'elapsed_ms': _intValue(obs['elapsed_ms']) ?? 0,
      'tasks_settled': obs['tasks_settled'],
      'task_status_counts': _map(obs['task_status_counts']),
      'memory_atom_count': obs['memory_atom_count'],
      if (card['title'] != null) 'title': card['title'],
    };
  }).toList(growable: false);
}

String _compactJson(Object? value) => jsonEncode(value ?? const {});

String _escapeTableText(String value) => value.replaceAll('|', r'\|');

String _renderReport({
  required String datasetPath,
  required List<String> modes,
  required int caseOffset,
  required int? caseLimit,
  required JsonMap? llmPreflight,
  required Map<String, JsonMap> metricsByMode,
  required JsonMap comparison,
  required JsonMap gate,
  required List<JsonMap> failures,
}) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Full-Chain Eval Report');
  b.writeln('');
  b.writeln('- Dataset: `$datasetPath`');
  b.writeln('- LLM enabled: `$_llmEnabled`');
  b.writeln('- Modes: `${modes.join(', ')}`');
  b.writeln('- Case offset / limit: `$caseOffset` / `${caseLimit ?? 'all'}`');
  b.writeln('- Iteration: `${_iterationMetadata()['id'] ?? 'unset'}`');
  b.writeln('- Gate status: `${gate['status']}`');
  _writePreflightSection(b, llmPreflight);
  b.writeln('');
  b.writeln('| Metric | ${modes.join(' | ')} |');
  b.writeln('| --- | ${modes.map((_) => '---:').join(' | ')} |');
  for (final metric in [
    'record_count',
    'materialized_card_count',
    'card_materialization_rate',
    'completed_card_count',
    'completed_card_rate',
    'input_to_valid_card_success_rate',
    'completed_with_failure_reason_rate',
    'card_schema_valid_rate',
    'card_source_fact_grounding_rate',
    'cards_with_insight_count',
    'cards_with_insight_rate',
    'memory_expected_hits',
    'memory_expected_total',
    'memory_expected_hit_rate',
    'memory_must_write_recall',
    'memory_must_not_write_precision',
    'memory_source_grounding',
    'memory_duplicate_rate',
    'card_expected_hits',
    'card_expected_total',
    'card_expected_hit_rate',
    'related_fact_hit_rate',
    'memory_recall_query_count',
    'memory_recall_hit_rate',
    'memory_recall_at_10',
    'super_agent_ask_count',
    'super_agent_answer_success_rate',
    'super_agent_answer_hit_rate',
    'super_agent_boundary_precision',
    'super_agent_tokens_per_ask',
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
    'context_peek_redundancy_rate',
    'first_write_after_read_rate',
    'agent_tool_rounds_per_task',
    'agent_empty_response_rate',
    'loop_detection_absence',
    'max_turns_absence',
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
  b.writeln('');
  b.writeln('## Notes');
  b.writeln('');
  b.writeln(
      '- The runner uses real `submitInput` and persistent task settling.');
  b.writeln(
      '- API keys are read from environment variables and redacted from artifacts.');
  b.writeln(
      '- `legacy_pkm` and `memory_primary` run in isolated workspaces; no dual-write compatibility is used.');
  b.writeln(
      '- `failures.jsonl` contains per-case attribution for missing memory, recall, related facts, card state, and task settlement.');
  b.writeln(
      '- `case_debug_index.md` links to per-case JSON logs under `case_logs/<mode>/<case_id>.json` with operation observations, task timeline, final cards, memory atoms, PKM snapshot, and LLM token stats.');
  return b.toString();
}

String _renderPreflightOnlyReport(JsonMap? llmPreflight) {
  final b = StringBuffer();
  b.writeln('# Memory Primary LLM Preflight Report');
  b.writeln('');
  b.writeln('- LLM enabled: `$_llmEnabled`');
  b.writeln('- Preflight only: `true`');
  b.writeln(
      '- API keys are read from environment variables and redacted from artifacts.');
  _writePreflightSection(b, llmPreflight);
  return b.toString();
}

String _renderPreflightFailureReport(JsonMap llmPreflight) {
  final b = StringBuffer();
  b.writeln('# Memory Primary Eval Preflight Failed');
  b.writeln('');
  b.writeln(
      'The full replay was not started because at least one configured LLM subscription failed the connectivity/model check.');
  b.writeln('');
  b.writeln(
      '- Fix the provider/model configuration, or set `MEMEX_EVAL_LLM_PREFLIGHT_WARN_ONLY=1` to run the replay while keeping this failure recorded.');
  b.writeln(
      '- Set `MEMEX_EVAL_SKIP_LLM_PREFLIGHT=1` only when a provider rejects synthetic preflight calls but works in the real agent path.');
  _writePreflightSection(b, llmPreflight);
  return b.toString();
}

void _writePreflightSection(StringBuffer b, JsonMap? llmPreflight) {
  if (llmPreflight == null) return;
  b.writeln('');
  b.writeln('## LLM Preflight');
  b.writeln('');
  b.writeln('- Passed: `${llmPreflight['passed']}`');
  b.writeln('- Skipped: `${llmPreflight['skipped'] ?? false}`');
  b.writeln('- Required: `${llmPreflight['required'] ?? false}`');
  final results = _list(llmPreflight['results']).map(_map).toList();
  if (results.isEmpty) {
    final reason = llmPreflight['reason'];
    if (reason != null) b.writeln('- Reason: `$reason`');
    return;
  }
  b.writeln('');
  b.writeln('| Slot | Type | Model | Base URL | Status | OK | Error |');
  b.writeln('| ---: | --- | --- | --- | ---: | --- | --- |');
  for (final result in results) {
    b.writeln(
      '| ${result['slot'] ?? '-'} | `${result['type'] ?? '-'}` | '
      '`${result['model'] ?? '-'}` | `${result['base_url'] ?? '-'}` | '
      '${result['status_code'] ?? '-'} | ${result['ok'] == true ? 'pass' : 'fail'} | '
      '${_escapeTableText(_truncateString(result['error']?.toString() ?? '-', 240))} |',
    );
  }
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

Future<JsonMap> _writeCaseDebugLog({
  required Directory runDir,
  required String mode,
  required String caseId,
  required String userId,
  required String dataRoot,
  required JsonMap evalCase,
  required Map<String, String> factIdsByOperation,
  required List<JsonMap> observations,
  required List<JsonMap> failures,
}) async {
  final caseLogDir = Directory(p.join(runDir.path, 'case_logs', mode));
  await caseLogDir.create(recursive: true);

  final activeAtoms = await MemoryPrimaryService.instance.listActiveAtoms(
    userId,
  );
  final finalTasks = await LocalTaskExecutor.instance.getTasks(limit: 4000);
  final agentActivityTrace = await _collectAgentActivityTrace();
  final llmStats = await LLMCallRecordService.instance.getAggregatedStatistics(
    userId: userId,
  );

  final log = {
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'mode': mode,
    'case_id': caseId,
    'user_id': userId,
    'data_root': dataRoot,
    'iteration': _iterationMetadata(),
    'case': _sanitizeForLog(evalCase),
    'fact_ids_by_operation': factIdsByOperation,
    'operation_observations': _sanitizeForLog(observations),
    'failures': _sanitizeForLog(failures),
    'failure_category_counts': _failureCategoryCounts(failures),
    'final_tasks': finalTasks.map(_taskSummary).toList(),
    'final_task_status_counts': _taskStatusCounts(finalTasks),
    'agent_activity_trace': agentActivityTrace,
    'final_cards': await _collectCardSummaries(
      userId: userId,
      factIdsByOperation: factIdsByOperation,
    ),
    'final_memory_atoms': activeAtoms.map((atom) => atom.toJson()).toList(),
    'pkm_snapshot': await _collectPkmSnapshot(userId),
    'llm_usage': llmStats,
  };

  await File(p.join(caseLogDir.path, '$caseId.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(log),
    flush: true,
  );
  return log;
}

Future<List<JsonMap>> _collectAgentActivityTrace() async {
  final history = await AgentActivityService.instance.getHistory(limit: 20000);
  return history.reversed.map(_agentActivityMessageSummary).toList();
}

JsonMap _agentActivityMessageSummary(AgentActivityMessageModel message) {
  return {
    'id': message.id,
    'type': message.type.name,
    'title': message.title,
    if (message.content != null) 'content': _sanitizeForLog(message.content),
    if (message.icon != null) 'icon': message.icon,
    'agent_name': message.agentName,
    'agent_id': message.agentId,
    if (message.scene != null) 'scene': message.scene,
    if (message.sceneId != null) 'scene_id': message.sceneId,
    if (message.userId != null) 'user_id': message.userId,
    'timestamp': message.timestamp.toUtc().toIso8601String(),
  };
}

JsonMap _agentActivityTraceMetrics(List<JsonMap> activityTrace) {
  final seenReadKeys = <String, Set<String>>{};
  final readPathsByAgent = <String, Set<String>>{};
  final hasAnyReadByAgent = <String>{};
  var contextPeekTotal = 0;
  var contextPeekRedundantCount = 0;
  var firstWriteTotal = 0;
  var firstWriteAfterReadHits = 0;

  for (final event in activityTrace) {
    if (event['type']?.toString() != 'tool_call_reqeust') continue;

    final parsed = _parseActivityToolCall(event['content']?.toString() ?? '');
    final toolName = parsed.name;
    if (toolName == null || toolName.isEmpty) continue;

    final agentKey = _agentTraceKey(event);
    if (_isReadToolName(toolName)) {
      contextPeekTotal += 1;
      hasAnyReadByAgent.add(agentKey);
      final readKey = '$toolName|${_normalizeTraceArgs(parsed.arguments)}';
      final agentSeenReads =
          seenReadKeys.putIfAbsent(agentKey, () => <String>{});
      if (!agentSeenReads.add(readKey)) {
        contextPeekRedundantCount += 1;
      }
      readPathsByAgent
          .putIfAbsent(agentKey, () => <String>{})
          .addAll(_pathsFromToolArguments(parsed.arguments));
      continue;
    }

    if (!_requiresPriorReadToolName(toolName)) continue;
    firstWriteTotal += 1;
    final writePaths = _pathsFromToolArguments(parsed.arguments);
    final priorReadPaths = readPathsByAgent[agentKey] ?? const <String>{};
    final hasRelatedRead = writePaths.isEmpty
        ? hasAnyReadByAgent.contains(agentKey)
        : writePaths.any((writePath) {
            return priorReadPaths.any(
              (readPath) => _pathsAreRelated(readPath, writePath),
            );
          });
    if (hasRelatedRead) {
      firstWriteAfterReadHits += 1;
    }
  }

  return {
    'context_peek_total': contextPeekTotal,
    'context_peek_redundant_count': contextPeekRedundantCount,
    'context_peek_redundancy_rate': _ratioOrZero(
      contextPeekRedundantCount,
      contextPeekTotal,
    ),
    'first_write_total': firstWriteTotal,
    'first_write_after_read_hits': firstWriteAfterReadHits,
    'first_write_after_read_rate': _rate(
      firstWriteAfterReadHits,
      firstWriteTotal,
    ),
  };
}

({String? name, String arguments}) _parseActivityToolCall(String content) {
  final match = RegExp(r'^\s*##\s+([^\n]+)\n\n([\s\S]*)$').firstMatch(content);
  if (match == null) return (name: null, arguments: '');
  return (
    name: match.group(1)?.trim(),
    arguments: match.group(2)?.trim() ?? '',
  );
}

String _agentTraceKey(JsonMap event) {
  final agentId = event['agent_id']?.toString();
  if (agentId != null && agentId.isNotEmpty) return agentId;
  return event['agent_name']?.toString() ?? 'unknown_agent';
}

String _normalizeTraceArgs(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  try {
    return jsonEncode(_sanitizeForLog(jsonDecode(trimmed)));
  } catch (_) {
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }
}

Set<String> _pathsFromToolArguments(String arguments) {
  if (arguments.trim().isEmpty) return const <String>{};
  try {
    return _collectPathLikeValues(jsonDecode(arguments));
  } catch (_) {
    return RegExp(r'(/[^\s",}]+)')
        .allMatches(arguments)
        .map((match) => _normalizePathForTrace(match.group(1) ?? ''))
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}

Set<String> _collectPathLikeValues(Object? value, {String keyHint = ''}) {
  final paths = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      paths.addAll(
        _collectPathLikeValues(
          entry.value,
          keyHint: entry.key.toString().toLowerCase(),
        ),
      );
    }
    return paths;
  }
  if (value is Iterable) {
    for (final item in value) {
      paths.addAll(_collectPathLikeValues(item, keyHint: keyHint));
    }
    return paths;
  }
  if (value is! String) return paths;

  final lowerKey = keyHint.toLowerCase();
  final looksLikePathKey = lowerKey.contains('path') ||
      lowerKey.contains('file') ||
      lowerKey.contains('target') ||
      lowerKey.contains('source');
  final normalized = _normalizePathForTrace(value);
  if (looksLikePathKey && normalized.isNotEmpty) {
    paths.add(normalized);
  }
  return paths;
}

String _normalizePathForTrace(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return p.normalize(trimmed).replaceAll('\\', '/');
}

bool _pathsAreRelated(String readPath, String writePath) {
  if (readPath == writePath) return true;
  return p.dirname(writePath) == readPath || p.dirname(readPath) == writePath;
}

bool _requiresPriorReadToolName(String name) {
  switch (name.toLowerCase()) {
    case 'write':
    case 'edit':
    case 'move':
    case 'remove':
      return true;
  }
  return false;
}

Future<List<JsonMap>> _collectCardSummaries({
  required String userId,
  required Map<String, String> factIdsByOperation,
}) async {
  final cards = <JsonMap>[];
  for (final entry in factIdsByOperation.entries) {
    final card = await FileSystemService.instance.readCardFile(
      userId,
      entry.value,
    );
    cards.add({
      'operation_id': entry.key,
      'fact_id': entry.value,
      'path': FileSystemService.instance.getCardPath(userId, entry.value),
      if (card == null)
        'missing': true
      else ...{
        'status': card.status,
        'title': card.title,
        'timestamp': card.timestamp,
        'tags': card.tags,
        'ui_config_count': card.uiConfigs.length,
        'insight': card.insight?.toJson(),
        'comments': card.comments.map((comment) => comment.toJson()).toList(),
        'raw': card.toJson(),
      },
    });
  }
  return cards;
}

Future<List<JsonMap>> _collectPkmSnapshot(String userId) async {
  final root = Directory(FileSystemService.instance.getPkmPath(userId));
  if (!await root.exists()) return const [];

  final limit = _intFromEnv('MEMEX_EVAL_CASE_LOG_PKM_FILE_LIMIT') ?? 80;
  final snippetChars =
      _intFromEnv('MEMEX_EVAL_CASE_LOG_PKM_SNIPPET_CHARS') ?? 800;
  final files = <JsonMap>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (files.length >= limit) break;
    if (entity is! File) continue;
    final stat = await entity.stat();
    final relativePath = p.relative(entity.path, from: root.path);
    final entry = <String, dynamic>{
      'path': relativePath,
      'size_bytes': stat.size,
      'modified_at': stat.modified.toIso8601String(),
    };
    final ext = p.extension(entity.path).toLowerCase();
    if (['.md', '.txt', '.yaml', '.yml', '.json'].contains(ext)) {
      try {
        final content = await entity.readAsString();
        entry['snippet'] = _truncateString(content, snippetChars);
      } catch (_) {
        entry['snippet_unavailable'] = true;
      }
    }
    files.add(entry);
  }
  return files;
}

String _renderCaseDebugIndex({
  required List<String> modes,
  required List<JsonMap> observations,
  required List<JsonMap> failures,
}) {
  final b = StringBuffer();
  b.writeln('# Case Debug Index');
  b.writeln('');
  b.writeln('- Generated at: `${DateTime.now().toUtc().toIso8601String()}`');
  b.writeln('- Iteration: `${_iterationMetadata()['id'] ?? 'unset'}`');
  b.writeln('');
  b.writeln(
    '| Mode | Case | Records | Failures | Unsettled ops | Slowest op | Case log |',
  );
  b.writeln('| --- | --- | ---: | ---: | ---: | --- | --- |');

  final keys = <String>{};
  for (final obs in observations) {
    final mode = obs['mode']?.toString();
    final caseId = obs['case_id']?.toString();
    if (mode == null || caseId == null) continue;
    keys.add('$mode\t$caseId');
  }
  final sortedKeys = keys.toList()
    ..sort((a, b) {
      final aParts = a.split('\t');
      final bParts = b.split('\t');
      final modeCompare =
          modes.indexOf(aParts.first).compareTo(modes.indexOf(bParts.first));
      if (modeCompare != 0) return modeCompare;
      return aParts.last.compareTo(bParts.last);
    });

  for (final key in sortedKeys) {
    final parts = key.split('\t');
    final mode = parts.first;
    final caseId = parts.last;
    final caseObservations = observations
        .where((obs) => obs['mode'] == mode && obs['case_id'] == caseId)
        .toList();
    final caseFailures = failures
        .where(
          (failure) => failure['mode'] == mode && failure['case_id'] == caseId,
        )
        .toList();
    final recordCount =
        caseObservations.where((obs) => obs['type'] == 'record').length;
    final unsettledCount = caseObservations
        .where((obs) =>
            (obs['type'] == 'record' || obs['type'] == 'para_projection') &&
            obs['tasks_settled'] != true)
        .length;
    final slowest = caseObservations
        .where((obs) => obs['type'] == 'record')
        .map(_map)
        .toList()
      ..sort(
        (a, b) =>
            (_intValue(b['elapsed_ms']) ?? 0) -
            (_intValue(a['elapsed_ms']) ?? 0),
      );
    final slowestText = slowest.isEmpty
        ? '-'
        : '${slowest.first['operation_id']} (${slowest.first['elapsed_ms']}ms)';
    final logPath = 'case_logs/$mode/$caseId.json';
    b.writeln(
      '| `$mode` | `$caseId` | $recordCount | ${caseFailures.length} | '
      '$unsettledCount | `${_escapeTableText(slowestText)}` | `$logPath` |',
    );
  }
  b.writeln('');
  b.writeln('## How To Use');
  b.writeln('');
  b.writeln(
    'Open the case log for a failing case and inspect `operation_observations`, '
    '`final_tasks`, `final_cards`, `final_memory_atoms`, `pkm_snapshot`, and '
    '`llm_usage` together. When an iteration fixes a case, add the case id, '
    'root cause, code/prompt/schema change, and before/after run ids to '
    '`evals/ITERATION_LOG.md`.',
  );
  return b.toString();
}

JsonMap _iterationMetadata() {
  final id = _firstEnv([
    'MEMEX_EVAL_ITERATION_ID',
    'MEMEX_EVAL_RUN_LABEL',
  ]);
  final note = _firstEnv([
    'MEMEX_EVAL_ITERATION_NOTE',
    'MEMEX_EVAL_FIX_SUMMARY',
  ]);
  final baseline = _firstEnv(['MEMEX_EVAL_BASELINE_RUN']);
  final changedCases = _firstEnv(['MEMEX_EVAL_CHANGED_CASES']);
  return {
    if (id != null) 'id': id,
    if (note != null) 'note': note,
    if (baseline != null) 'baseline_run': baseline,
    if (changedCases != null)
      'changed_cases': changedCases
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
  };
}

Map<String, int> _taskStatusCounts(Iterable<dynamic> tasks) {
  final counts = <String, int>{};
  for (final task in tasks) {
    final status = task.status?.toString() ?? 'unknown';
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

Object? _sanitizeForLog(Object? value, {int maxStringLength = 4000}) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) return _truncateString(value, maxStringLength);
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(
        key.toString(),
        _sanitizeForLog(item, maxStringLength: maxStringLength),
      ),
    );
  }
  if (value is Iterable) {
    return value
        .map((item) => _sanitizeForLog(item, maxStringLength: maxStringLength))
        .toList(growable: false);
  }
  return _truncateString(value.toString(), maxStringLength);
}

String _truncateString(String value, int maxLength) {
  if (maxLength <= 0 || value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...<truncated ${value.length - maxLength} chars>';
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

Future<void> _writeProgress(File file, JsonMap observation) async {
  final progress = {
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'last_observation': observation,
  };
  await file
      .writeAsString(const JsonEncoder.withIndent('  ').convert(progress));
}

String? _firstEnv(List<String> keys) {
  for (final key in keys) {
    final value = Platform.environment[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
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

int? _intFromEnv(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
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

List<_TextExpectation> _textExpectations(Object? value) {
  final result = <_TextExpectation>[];
  for (final item in _list(value)) {
    if (item is String || item is num || item is bool) {
      final text = item.toString().trim();
      if (text.isNotEmpty) {
        result.add(_TextExpectation(label: text, alternatives: [text]));
      }
    } else if (item is List) {
      final alternatives = item
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (alternatives.isNotEmpty) {
        result.add(
          _TextExpectation(
            label: alternatives.first,
            alternatives: alternatives,
          ),
        );
      }
    } else if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      final alternatives = _strings(map['any_of'] ?? map['alternatives']);
      final label = map['label']?.toString().trim();
      final regex = map['regex']?.toString().trim();
      if (regex != null && regex.isNotEmpty) {
        result.add(
          _TextExpectation.regex(
            label: label == null || label.isEmpty ? regex : label,
            pattern: regex,
          ),
        );
        continue;
      }
      if (alternatives.isNotEmpty) {
        result.add(
          _TextExpectation(
            label: label == null || label.isEmpty ? alternatives.first : label,
            alternatives: alternatives,
          ),
        );
      }
    }
  }
  return result;
}

bool _contains(String haystack, String needle) {
  return haystack
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .contains(needle.toLowerCase().replaceAll(RegExp(r'\s+'), ''));
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class _ExpectationEvalResult {
  const _ExpectationEvalResult({
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
}

class _RouteEvalResult {
  const _RouteEvalResult({
    this.accuracyHits = 0,
    this.accuracyTotal = 0,
    this.missCount = 0,
    this.expectedCount = 0,
    this.overtriggerCount = 0,
    this.observedCount = 0,
    this.failures = const [],
  });

  final int accuracyHits;
  final int accuracyTotal;
  final int missCount;
  final int expectedCount;
  final int overtriggerCount;
  final int observedCount;
  final List<JsonMap> failures;
}

class _CardMetricEvalResult {
  const _CardMetricEvalResult({
    this.templatePrimaryHits = 0,
    this.templateAnyHits = 0,
    this.templateTotal = 0,
    this.fieldRecallHits = 0,
    this.fieldRecallTotal = 0,
    this.entityRecallHits = 0,
    this.entityRecallTotal = 0,
    this.timeParseHits = 0,
    this.timeParseTotal = 0,
    this.hallucinatedAbsenceHits = 0,
    this.hallucinatedAbsenceTotal = 0,
    this.failures = const [],
  });

  final int templatePrimaryHits;
  final int templateAnyHits;
  final int templateTotal;
  final int fieldRecallHits;
  final int fieldRecallTotal;
  final int entityRecallHits;
  final int entityRecallTotal;
  final int timeParseHits;
  final int timeParseTotal;
  final int hallucinatedAbsenceHits;
  final int hallucinatedAbsenceTotal;
  final List<JsonMap> failures;
}

class _SuperAgentToolEvalResult {
  const _SuperAgentToolEvalResult({
    this.retrievalHitAt1Hits = 0,
    this.retrievalHitAt1Total = 0,
    this.retrievalHitAt3Hits = 0,
    this.retrievalHitAt3Total = 0,
    this.retrievalHitAt5Hits = 0,
    this.retrievalHitAt5Total = 0,
    this.retrievalHitAt10Hits = 0,
    this.retrievalHitAt10Total = 0,
    this.readOnlyHits = 0,
    this.readOnlyTotal = 0,
    this.toolSelectionHits = 0,
    this.toolSelectionTotal = 0,
    this.toolArgsHits = 0,
    this.toolArgsTotal = 0,
    this.toolCallMinimalityHits = 0,
    this.toolCallMinimalityTotal = 0,
    this.toolCallCount = 0,
    this.toolCallFailureCount = 0,
    this.toolCallRetryCount = 0,
    this.repeatedToolCallCount = 0,
    this.readToolCallCount = 0,
    this.readToolErrorCount = 0,
    this.writeToolCallCount = 0,
    this.writeToolErrorCount = 0,
    this.contextPeekCount = 0,
    this.contextPeekTaskCount = 0,
    this.agentToolRoundCount = 0,
    this.agentToolRoundTaskCount = 0,
    this.failures = const [],
  });

  final int retrievalHitAt1Hits;
  final int retrievalHitAt1Total;
  final int retrievalHitAt3Hits;
  final int retrievalHitAt3Total;
  final int retrievalHitAt5Hits;
  final int retrievalHitAt5Total;
  final int retrievalHitAt10Hits;
  final int retrievalHitAt10Total;
  final int readOnlyHits;
  final int readOnlyTotal;
  final int toolSelectionHits;
  final int toolSelectionTotal;
  final int toolArgsHits;
  final int toolArgsTotal;
  final int toolCallMinimalityHits;
  final int toolCallMinimalityTotal;
  final int toolCallCount;
  final int toolCallFailureCount;
  final int toolCallRetryCount;
  final int repeatedToolCallCount;
  final int readToolCallCount;
  final int readToolErrorCount;
  final int writeToolCallCount;
  final int writeToolErrorCount;
  final int contextPeekCount;
  final int contextPeekTaskCount;
  final int agentToolRoundCount;
  final int agentToolRoundTaskCount;
  final List<JsonMap> failures;
}

class _RetrievalHitEval {
  const _RetrievalHitEval({
    this.total = 0,
    this.hitAt1Hits = 0,
    this.hitAt3Hits = 0,
    this.hitAt5Hits = 0,
    this.hitAt10Hits = 0,
    this.failures = const [],
  });

  final int total;
  final int hitAt1Hits;
  final int hitAt3Hits;
  final int hitAt5Hits;
  final int hitAt10Hits;
  final List<JsonMap> failures;
}

class _TaskErrorFlags {
  const _TaskErrorFlags({
    required this.loopDetection,
    required this.maxTurns,
  });

  final bool loopDetection;
  final bool maxTurns;
}

class _SuperAgentAskResult {
  const _SuperAgentAskResult({
    this.sessionId,
    required this.answer,
    required this.events,
    required this.tokenUsageEvents,
    this.error,
  });

  final String? sessionId;
  final String answer;
  final List<JsonMap> events;
  final List<JsonMap> tokenUsageEvents;
  final String? error;
}

class _EvalLlmConfig {
  const _EvalLlmConfig({
    required this.slot,
    required this.configIndex,
    required this.type,
    required this.model,
    required this.baseUrl,
    required this.apiKey,
    required this.priority,
  });

  final int slot;
  final int configIndex;
  final String type;
  final String model;
  final String baseUrl;
  final String apiKey;
  final int priority;
}

class _HttpJsonResponse {
  const _HttpJsonResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _TextExpectation {
  const _TextExpectation({
    required this.label,
    required this.alternatives,
  }) : regexPattern = null;

  const _TextExpectation.regex({
    required this.label,
    required String pattern,
  })  : alternatives = const [],
        regexPattern = pattern;

  final String label;
  final List<String> alternatives;
  final String? regexPattern;

  bool matches(String haystack) {
    final pattern = regexPattern;
    if (pattern != null) {
      return RegExp(pattern, caseSensitive: false, dotAll: true)
          .hasMatch(haystack);
    }
    return alternatives.any((alternative) => _contains(haystack, alternative));
  }
}

class _TaskWaitResult {
  const _TaskWaitResult({
    required this.tasks,
    required this.newTaskCount,
    required this.settled,
  });

  final List<dynamic> tasks;
  final int newTaskCount;
  final bool settled;

  List<dynamic> get newTasks {
    if (newTaskCount <= 0) return const [];
    return tasks.take(newTaskCount).toList(growable: false);
  }

  Map<String, int> get statusCounts {
    final counts = <String, int>{};
    for (final task in newTasks) {
      final status = task.status?.toString() ?? 'unknown';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  int get failedTaskCount =>
      newTasks.where((task) => task.status?.toString() == 'failed').length;

  List<JsonMap> get activeTaskSummaries => newTasks
      .where(
        (task) =>
            ['pending', 'processing', 'retrying']
                .contains(task.status?.toString()) ||
            task.status?.toString() == 'failed',
      )
      .map(_taskSummary)
      .toList(growable: false);
}

JsonMap _taskSummary(dynamic task) {
  return {
    'id': task.id?.toString(),
    'type': task.type?.toString(),
    'status': task.status?.toString(),
    'biz_id': task.bizId?.toString(),
    'retry_count': task.retryCount,
    'max_retries': task.maxRetries,
    'created_at': task.createdAt,
    'scheduled_at': task.scheduledAt,
    'completed_at': task.completedAt,
    'updated_at': task.updatedAt,
    if (task.error != null) 'error': task.error?.toString(),
    if (task.dependencies != null)
      'dependencies': task.dependencies?.toString(),
    if (task.payload != null) 'payload': _decodeJsonForLog(task.payload),
    if (task.result != null) 'result': _decodeJsonForLog(task.result),
  };
}

Object? _decodeJsonForLog(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  try {
    return _sanitizeForLog(jsonDecode(raw));
  } catch (_) {
    return _truncateString(raw, 4000);
  }
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
