import 'dart:convert';

import 'package:memex/agent/memory_extract_agent/memory_extract_agent.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';

final _logger = getLogger('MemoryPrimaryHandler');

Future<List<MemoryAtom>> processWithMemoryPrimary({
  required String userId,
  required String factId,
  required String contentText,
  List<Map<String, dynamic>>? assetAnalyses,
  DateTime? inputDateTime,
  String? locationContextReminder,
}) async {
  final patches = await MemoryExtractAgent.extractPatches(
    userId: userId,
    factId: factId,
    contentText: contentText,
    assetAnalyses: assetAnalyses ?? const [],
    inputDateTime: inputDateTime,
    locationContextReminder: locationContextReminder,
  );
  if (patches.isEmpty) return const [];

  return MemoryPrimaryService.instance.applyPatches(
    userId: userId,
    patches: patches,
    sourceAgent: 'memory_extract_agent',
  );
}

Future<void> handleMemoryPrimaryImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info('Starting Memory Primary task for user: $userId');

  try {
    final factId = payload['fact_id'] as String;
    final combinedText = payload['combined_text'] as String;
    final locationContextReminder =
        payload['location_context_reminder'] as String?;
    final inputDateTime = dateTimeFromUnixSeconds(payload['created_at_ts']);

    final assetAnalyses = await _assetAnalysesFromPriorTask(
      userId: userId,
      combinedText: combinedText,
      context: context,
    );

    final changed = await processWithMemoryPrimary(
      userId: userId,
      factId: factId,
      contentText: combinedText,
      assetAnalyses: assetAnalyses,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
    );

    await LocalTaskExecutor.instance.updateTaskResult(
      context.taskId,
      jsonEncode({
        'changed_memory_ids': changed.map((atom) => atom.id).toList(),
        'changed_memory_atoms': changed.map((atom) => atom.toJson()).toList(),
      }),
    );

    _logger.info('Memory Primary task completed for $factId');
  } catch (e, stack) {
    _logger.severe('Error in Memory Primary task: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}

Future<Map<String, dynamic>> rebuildMemoryPrimaryFromFacts({
  required String userId,
  int? limit,
}) async {
  await MemoryPrimaryService.instance.resetMemoryPrimaryData(userId);

  final fs = FileSystemService.instance;
  final factIds = await fs.listAllFacts(userId);
  final ordered = limit == null ? factIds : factIds.take(limit).toList();
  var processed = 0;
  var changedCount = 0;
  final failed = <String>[];

  for (final factId in ordered) {
    try {
      final fact = await fs.extractFactContentFromFile(userId, factId);
      if (fact == null) continue;
      final changed = await processWithMemoryPrimary(
        userId: userId,
        factId: factId,
        contentText: fact.content,
        assetAnalyses: fact.assetAnalyses,
        inputDateTime: fact.datetime,
      );
      processed += 1;
      changedCount += changed.length;
    } catch (e) {
      failed.add(factId);
      _logger.warning('Memory Primary rebuild failed for $factId: $e');
    }
  }

  return {
    'processed_fact_count': processed,
    'changed_memory_count': changedCount,
    'failed_fact_ids': failed,
  };
}

Future<List<Map<String, dynamic>>?> _assetAnalysesFromPriorTask({
  required String userId,
  required String combinedText,
  required TaskContext context,
}) async {
  if (context.bizId == null) return null;
  await failIfAssetAnalysisFailed(
    bizId: context.bizId,
    combinedText: combinedText,
  );
  final analysisResult = await LocalTaskExecutor.instance.getTaskResultByBizId(
    userId,
    'handle_analyze_assets',
    context.bizId!,
  );

  if (analysisResult != null && analysisResult.containsKey('asset_analyses')) {
    return (analysisResult['asset_analyses'] as List)
        .cast<Map<String, dynamic>>();
  }
  return null;
}
