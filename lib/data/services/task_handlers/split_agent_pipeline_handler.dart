import 'package:logging/logging.dart';
import 'package:memex/agent/agent_utils.dart';
import 'package:memex/agent/card_insight_agent/card_insight_agent.dart';
import 'package:memex/agent/pkm_agent/pkm_agent.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/memory_sync_service.dart';
import 'package:memex/data/services/related_facts_service.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

final Logger _logger = getLogger('SplitAgentPipelineHandler');

Future<void> processWithSplitAgentPipeline({
  required String userId,
  required String factId,
  required String contentText,
  List<Map<String, dynamic>>? assetAnalyses,
  DateTime? inputDateTime,
  String? locationContextReminder,
  required bool writePrimary,
}) async {
  final skipDecision = PkmAgent.detectNonPersistentInput(contentText);
  if (skipDecision.shouldSkip) {
    _logger.info(
      'Skipping split pipeline for $factId because input is non-persistent: ${skipDecision.toJson()}',
    );
    return;
  }

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

  if (writePrimary) {
    await fileSystem.updateCardFile(
      userId,
      factId,
      (card) => card.copyWith(
        insight: CardInsight(
          text: draft.text,
          summary: draft.summary,
          relatedFacts: draft.relatedFactIds
              .map((id) => RelatedFact(id: id))
              .toList(growable: false),
        ),
      ),
      createIfNotExists: true,
    );
    EventBusService.instance.emitEvent(
      CardDetailUpdatedMessage(cardId: factId),
    );
    await MemorySyncService.instance.enqueueFact(userId, factId);
  }

  await fileSystem.writeSplitAgentShadowResult(userId, factId, {
    'fact_id': factId,
    'mode': writePrimary ? 'split_primary' : 'split_shadow',
    'write_primary': writePrimary,
    'created_at': DateTime.now().toIso8601String(),
    'input_datetime': inputDateTime?.toIso8601String(),
    'memory_atom_source_fact_ids_expected': [factId],
    'legacy_card_insight': _cardInsightToJson(card?.insight),
    'related_facts': relatedFacts.map((e) => e.toJson()).toList(),
    'draft': draft.toJson(),
    'comparison': _buildComparison(
      legacyInsight: card?.insight,
      draft: draft,
      candidates: relatedFacts,
    ),
  });
}

CardData? _cardWithoutInsight(CardData? card) {
  if (card == null) return null;
  final json = card.toJson()..remove('insight');
  return CardData.fromJson(json);
}

Map<String, dynamic>? _cardInsightToJson(CardInsight? insight) {
  if (insight == null) return null;
  return insight.toJson();
}

Map<String, dynamic> _buildComparison({
  required CardInsight? legacyInsight,
  required CardInsightDraft draft,
  required List<RelatedFactCandidate> candidates,
}) {
  final legacyRelated =
      legacyInsight?.relatedFacts.map((fact) => fact.id).toSet() ?? <String>{};
  final splitRelated = draft.relatedFactIds.toSet();
  final candidateIds = candidates.map((fact) => fact.factId).toSet();
  final overlap = legacyRelated.intersection(splitRelated);
  final avgEntityScore = candidates.isEmpty
      ? 0.0
      : candidates.map((fact) => fact.entityScore).reduce((a, b) => a + b) /
          candidates.length;
  return {
    'legacy_insight_present': legacyInsight != null &&
        ((legacyInsight.text?.trim().isNotEmpty ?? false) ||
            (legacyInsight.summary?.trim().isNotEmpty ?? false) ||
            legacyRelated.isNotEmpty),
    'split_insight_present':
        draft.text.trim().isNotEmpty || draft.summary.trim().isNotEmpty,
    'legacy_related_count': legacyRelated.length,
    'split_related_count': splitRelated.length,
    'candidate_count': candidateIds.length,
    'candidate_avg_entity_score': avgEntityScore,
    'related_overlap_count': overlap.length,
    'split_related_ids_from_candidates':
        splitRelated.every(candidateIds.contains),
    'fallback_used': draft.fallback,
  };
}

Future<void> handleSplitAgentPipelineImpl(
  String userId,
  Map<String, dynamic> payload,
  TaskContext context,
) async {
  _logger.info('Starting split agent pipeline task for user: $userId');

  try {
    final config = await UserStorage.getAgentPipelineConfig();
    if (!config.runsSplitPipeline) {
      _logger.info('Split pipeline disabled; no-op task completes.');
      return;
    }

    final factId = payload['fact_id'] as String;
    final combinedText = payload['combined_text'] as String;
    final locationContextReminder =
        payload['location_context_reminder'] as String?;
    final inputDateTime = dateTimeFromUnixSeconds(payload['created_at_ts']);

    List<Map<String, dynamic>>? assetAnalyses;
    if (context.bizId != null) {
      try {
        final analysisResult =
            await LocalTaskExecutor.instance.getTaskResultByBizId(
          userId,
          'handle_analyze_assets',
          context.bizId!,
        );

        if (analysisResult != null &&
            analysisResult.containsKey('asset_analyses')) {
          assetAnalyses = (analysisResult['asset_analyses'] as List)
              .cast<Map<String, dynamic>>();
        }
      } catch (e) {
        _logger.warning('Failed to retrieve asset analyses: $e');
      }
    }

    await processWithSplitAgentPipeline(
      userId: userId,
      factId: factId,
      contentText: combinedText,
      assetAnalyses: assetAnalyses,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
      writePrimary: config.splitWritesPrimary,
    );

    _logger.info('Split agent pipeline task completed for $factId');
  } catch (e, stack) {
    _logger.severe('Error in split agent pipeline task: $e', e, stack);
    rethrowIfNonRetryable(e);
  }
}
