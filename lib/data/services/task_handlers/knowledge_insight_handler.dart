import 'dart:async';
import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/agent/insight_agent/knowledge_insight_agent.dart';
import 'package:memex/data/services/event_bus_service.dart';

final Logger _logger = getLogger('LocalTaskHandlers');

/// Handler for Knowledge Insight Update
Future<void> handleKnowledgeInsight(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info(
    'Executing handleKnowledgeInsight for task ${context.taskId}, bizId: ${context.bizId}',
  );

  try {
    try {
      await KnowledgeInsightAgent.updateKnowledgeInsight(
        userId: userId,
        runId: context.taskId,
      );
    } on AgentException catch (e) {
      if (e.code != AgentExceptionCode.loopDetection) {
        rethrow;
      }

      _logger.warning(
        'Knowledge insight task ${context.taskId} skipped after recoverable agent loop: ${e.message}',
      );
      await LocalTaskExecutor.instance.updateTaskResult(
        context.taskId,
        jsonEncode({
          'status': 'skipped',
          'reason': 'recoverable_agent_loop',
          'error': e.toString(),
        }),
      );
    }
  } finally {
    // Always notify UI that the refresh operation is done (success or failure).
    // On failure, handleGenericAgentFailure also emits ErrorNotificationMessage
    // for the error toast, but we need NewInsightMessage to stop the loading state.
    EventBusService.instance.emitEvent(
      NewInsightMessage(insightId: context.bizId ?? context.taskId, html: ''),
    );
  }
}
