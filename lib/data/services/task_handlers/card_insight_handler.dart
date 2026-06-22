import 'dart:convert';

import 'package:memex/agent/agent_utils.dart';
import 'package:memex/agent/card_insight_agent/card_insight_agent.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/related_facts_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';

final _logger = getLogger('CardInsightHandler');

Future<CardInsightDraft> processWithCardInsightAgent({
  required String userId,
  required String factId,
  required String contentText,
  List<Map<String, dynamic>>? assetAnalyses,
  DateTime? inputDateTime,
  String? locationContextReminder,
}) async {
  final fileSystem = FileSystemService.instance;
  final card = await fileSystem.readCardFile(userId, factId);
  final cardForDraft = _cardWithoutInsight(card);
  final assetInfo = formatAssetAnalysis(assetAnalyses);
  final retrievalText =
      assetInfo.isEmpty ? contentText : '$contentText\n\n$assetInfo';

  final relatedFacts = await RelatedFactsService.instance.findRelatedFacts(
    userId: userId,
    factId: factId,
    contentText: retrievalText,
  );

  final draft = await CardInsightAgent.generate(
    userId: userId,
    factId: factId,
    contentText: retrievalText,
    card: cardForDraft,
    relatedFacts: relatedFacts,
    inputDateTime: inputDateTime,
    locationContextReminder: locationContextReminder,
  );

  await fileSystem.updateCardFile(
    userId,
    factId,
    (card) => card.copyWith(
      insight: CardInsight(
        text: draft.text,
        summary: draft.summary,
        relatedFacts: draft.relatedFactIds
            .where(CardInsightAgent.isTimelineFactId)
            .map((id) => RelatedFact(id: id))
            .toList(growable: false),
      ),
    ),
    createIfNotExists: true,
  );

  EventBusService.instance.emitEvent(CardDetailUpdatedMessage(cardId: factId));
  return draft;
}

Future<void> handleCardInsightImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info('Starting Card Insight task for user: $userId');

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

    final draft = await processWithCardInsightAgent(
      userId: userId,
      factId: factId,
      contentText: combinedText,
      assetAnalyses: assetAnalyses,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
    );

    await LocalTaskExecutor.instance.updateTaskResult(
      context.taskId,
      jsonEncode({'card_insight_draft': draft.toJson()}),
    );

    _logger.info('Card Insight task completed for $factId');
  } catch (e, stack) {
    _logger.severe('Error in Card Insight task: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}

CardData? _cardWithoutInsight(CardData? card) {
  if (card == null) return null;
  final json = card.toJson()..remove('insight');
  return CardData.fromJson(json);
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
