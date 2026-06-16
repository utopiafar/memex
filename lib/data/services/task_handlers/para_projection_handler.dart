import 'dart:convert';

import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/para_projection_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('ParaProjectionHandler');

Future<void> handleParaProjectionImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info('Starting PARA projection task for user: $userId');

  try {
    final dryRun = payload['dry_run'] as bool? ?? false;
    final result = await ParaProjectionService.instance
        .projectMemoryPrimaryToPara(userId: userId, dryRun: dryRun);
    await LocalTaskExecutor.instance.updateTaskResult(
      context.taskId,
      jsonEncode({'para_projection': result.toJson()}),
    );
    _logger.info('PARA projection task completed for user: $userId');
  } catch (e, stack) {
    _logger.severe('Error in PARA projection task: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}
