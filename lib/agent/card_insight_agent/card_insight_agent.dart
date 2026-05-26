import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/data/services/related_facts_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

class CardInsightDraft {
  final String text;
  final String summary;
  final List<String> relatedFactIds;
  final bool fallback;

  const CardInsightDraft({
    required this.text,
    required this.summary,
    required this.relatedFactIds,
    this.fallback = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'summary': summary,
      'related_fact_ids': relatedFactIds,
      'fallback': fallback,
    };
  }
}

class CardInsightAgent {
  CardInsightAgent._();

  static final Logger _logger = getLogger('CardInsightAgent');

  static Future<CardInsightDraft> generate({
    required String userId,
    required String factId,
    required String contentText,
    required CardData? card,
    required List<RelatedFactCandidate> relatedFacts,
    DateTime? inputDateTime,
    String? locationContextReminder,
  }) async {
    try {
      final llmConfig = await UserStorage.getAgentLLMConfig(
        AgentDefinitions.cardInsightAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      if (!llmConfig.isValid) {
        return _fallback(contentText, relatedFacts);
      }

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.cardInsightAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final prompt = await _buildPrompt(
        userId: userId,
        factId: factId,
        contentText: contentText,
        card: card,
        relatedFacts: relatedFacts,
        inputDateTime: inputDateTime,
        locationContextReminder: locationContextReminder,
      );
      final response = await resources.client.generate(
        [
          UserMessage([TextPart(prompt)]),
        ],
        modelConfig: resources.modelConfig,
        jsonOutput: true,
      );
      final draft = _parseDraft(
        response.textOutput ?? '',
        allowedRelatedFactIds: relatedFacts.map((e) => e.factId).toSet(),
      );
      if (draft != null) return draft;
      return _fallback(contentText, relatedFacts);
    } catch (e, stack) {
      _logger.warning(
        'Card insight generation fell back for $factId: $e',
        e,
        stack,
      );
      return _fallback(contentText, relatedFacts);
    }
  }

  static Future<String> _buildPrompt({
    required String userId,
    required String factId,
    required String contentText,
    required CardData? card,
    required List<RelatedFactCandidate> relatedFacts,
    DateTime? inputDateTime,
    String? locationContextReminder,
  }) async {
    var userMemory = '';
    try {
      final memoryManagement = await MemoryManagement.createDefault(
        userId: userId,
        sourceAgent: 'card_insight_agent',
      );
      userMemory = await memoryManagement.buildMemoryPrompt();
    } catch (e) {
      _logger.fine('User memory unavailable for card insight prompt: $e');
    }

    final cardJson = card?.toJson() ?? const <String, dynamic>{};
    final relatedJson = relatedFacts.map((e) => e.toJson()).toList();
    final currentTime = formatLocalDateTimeWithZone(
      inputDateTime ?? DateTime.now(),
    );
    final locationBlock = locationContextReminder?.trim().isEmpty ?? true
        ? ''
        : '<location_context>\n${locationContextReminder!.trim()}\n</location_context>\n';

    return '''
You generate timeline-card insight metadata for Memex.

The input has already been saved as raw Fact and Timeline Card data. Do not organize or update PARA/PKM files. Use the user memory and related Fact candidates only as context.

Current local time:
$currentTime

Fact id:
$factId

$locationBlock
User memory:
${userMemory.isEmpty ? '(empty)' : userMemory}

Current raw input:
$contentText

Current card JSON:
${const JsonEncoder.withIndent('  ').convert(cardJson)}

Hybrid retrieval candidates:
${const JsonEncoder.withIndent('  ').convert(relatedJson)}

Return strict JSON only:
{
  "insight_text": "A concise explanation of why this record matters and how it connects to durable context. Use the user's language.",
  "summary_text": "One short sentence for quick scanning.",
  "related_fact_ids": ["Only fact_id values from Hybrid retrieval candidates that are genuinely related"]
}
''';
  }

  static CardInsightDraft? _parseDraft(
    String raw, {
    required Set<String> allowedRelatedFactIds,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final jsonText = _stripCodeFence(trimmed);
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final text = decoded['insight_text']?.toString().trim() ?? '';
      final summary = decoded['summary_text']?.toString().trim() ?? '';
      final related = <String>[];
      final rawRelated = decoded['related_fact_ids'];
      if (rawRelated is List) {
        for (final item in rawRelated) {
          final id = item.toString();
          if (allowedRelatedFactIds.contains(id)) related.add(id);
        }
      }
      if (text.isEmpty && summary.isEmpty) return null;
      return CardInsightDraft(
        text: text.isEmpty ? summary : text,
        summary: summary.isEmpty ? text : summary,
        relatedFactIds: related,
      );
    } catch (_) {
      return null;
    }
  }

  static CardInsightDraft _fallback(
    String contentText,
    List<RelatedFactCandidate> relatedFacts,
  ) {
    final compact = contentText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final summary =
        compact.length > 120 ? '${compact.substring(0, 120)}...' : compact;
    final relatedIds = relatedFacts.take(3).map((e) => e.factId).toList();
    return CardInsightDraft(
      text: relatedIds.isEmpty
          ? summary
          : '$summary\n\nRelated context: ${relatedIds.join(', ')}',
      summary: summary,
      relatedFactIds: relatedIds,
      fallback: true,
    );
  }

  static String _stripCodeFence(String value) {
    if (!value.startsWith('```')) return value;
    return value
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
}
