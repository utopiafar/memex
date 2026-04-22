import 'package:logging/logging.dart';
import 'package:memex/agent/todo_routing_agent/todo_routing_agent.dart';
import 'package:memex/agent/todo_schedule_agent/todo_schedule_agent.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/todo_schedule_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final Logger _logger = getLogger('TodoScheduleHandler');

/// Task handler for todo_schedule_agent_task.
Future<void> handleTodoScheduleAgentImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext taskContext,
) async {
  _logger.info(
      'Handling TodoSchedule task for user: $userId, payload keys: ${payload.keys.toList()}');

  final factId = payload['fact_id'] as String?;
  final combinedText = payload['combined_text'] as String?;

  if (factId == null || combinedText == null) {
    _logger.info(
        'TodoSchedule: skipping (factId=$factId, hasText=${combinedText != null})');
    return;
  }

  // Check if LLM is configured
  final llmConfig = await UserStorage.getAgentLLMConfig(
    AgentDefinitions.todoScheduleAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );
  if (!llmConfig.isValid) {
    _logger.info('No LLM configured for TodoScheduleAgent — skipping');
    return;
  }

  // Get LLM resources
  final resources = await UserStorage.getAgentLLMResources(
    AgentDefinitions.todoScheduleAgent,
    defaultClientKey: LLMConfig.defaultClientKey,
  );

  // Step 1: Run routing Agent to detect intent
  final intent = await TodoRoutingAgent.runRouting(
    client: resources.client,
    modelConfig: resources.modelConfig,
    userId: userId,
    userContent: combinedText,
  );

  if (intent == null) {
    _logger.info('TodoSchedule: routing agent returned no result — skipping');
    return;
  }

  final action = intent['action'] as String?;
  if (action == null || action == 'none') {
    _logger.info('TodoSchedule: action=$action — skipping');
    return;
  }

  _logger.info('TodoSchedule: detected action=$action');

  // Step 2: For complete/cancel — operate directly via Service (no Agent needed)
  if (action == 'complete' || action == 'cancel') {
    await _handleStatusChange(userId, intent, action);
    EventBusService.instance.emitEvent(TodoItemsUpdatedMessage());
    return;
  }

  // Step 3: For add — run full Agent to extract structured fields
  _logger.info('TodoSchedule: running full Agent for fact $factId');
  await TodoScheduleAgent.runWithContent(
    client: resources.client,
    modelConfig: resources.modelConfig,
    userId: userId,
    factId: factId,
    userContent: combinedText,
  );

  _logger.info('TodoSchedule Agent task completed for $factId');
  EventBusService.instance.emitEvent(TodoItemsUpdatedMessage());
}

/// Handle complete/cancel actions directly via TodoScheduleService.
Future<void> _handleStatusChange(
  String userId,
  Map<String, dynamic> intent,
  String action,
) async {
  final items = intent['items'] as List<dynamic>?;
  if (items == null || items.isEmpty) return;

  final service = TodoScheduleService.instance;
  final pendingTodos = await service.getPendingTodos(userId);

  for (final item in items) {
    final title = item['title'] as String?;
    if (title == null) continue;

    final match = _findBestMatch(pendingTodos, title);
    if (match == null) {
      _logger.info('TodoSchedule: no matching todo for "$title"');
      continue;
    }

    if (action == 'complete') {
      await service.completeItem(match.id);
      _logger.info('TodoSchedule: completed "${match.title}" (${match.id})');
    } else {
      await service.cancelItem(match.id);
      _logger.info('TodoSchedule: cancelled "${match.title}" (${match.id})');
    }
  }
}

/// Find best matching todo by title similarity.
TodoScheduleItem? _findBestMatch(List<TodoScheduleItem> items, String title) {
  final lowerTitle = title.toLowerCase();
  // Exact match first
  for (final item in items) {
    if (item.title.toLowerCase() == lowerTitle) return item;
  }
  // Contains match
  for (final item in items) {
    if (item.title.toLowerCase().contains(lowerTitle) ||
        lowerTitle.contains(item.title.toLowerCase())) {
      return item;
    }
  }
  return null;
}

/// Failure handler for todo_schedule_agent_task.
Future<void> handleTodoScheduleFailureImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
  Object error,
  StackTrace? stackTrace,
) async {
  _logger.severe(
    'TodoSchedule task failed for user: $userId, error: $error',
    error,
    stackTrace,
  );
}
