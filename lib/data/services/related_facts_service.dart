import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/search/query_matcher.dart';
import 'package:memex/data/services/search_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class RelatedFactCandidate {
  final String factId;
  final String title;
  final String snippet;
  final String source;
  final double lexicalScore;
  final double vectorScore;
  final double recencyScore;
  final double entityScore;
  final double totalScore;
  final List<String> matchedHints;

  const RelatedFactCandidate({
    required this.factId,
    required this.title,
    required this.snippet,
    required this.source,
    required this.lexicalScore,
    required this.vectorScore,
    required this.recencyScore,
    required this.entityScore,
    required this.totalScore,
    this.matchedHints = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'fact_id': factId,
      'title': title,
      'snippet': snippet,
      'source': source,
      'scores': {
        'lexical': lexicalScore,
        'vector': vectorScore,
        'recency': recencyScore,
        'entity': entityScore,
        'total': totalScore,
      },
      if (matchedHints.isNotEmpty) 'matched_hints': matchedHints,
    };
  }
}

class RelatedFactsService {
  RelatedFactsService._();

  static final RelatedFactsService instance = RelatedFactsService._();

  final Logger _logger = getLogger('RelatedFactsService');

  Future<List<RelatedFactCandidate>> findRelatedFacts({
    required String userId,
    required String factId,
    required String contentText,
    int limit = 6,
    int candidateLimit = 80,
  }) async {
    final query = contentText.trim();
    if (query.isEmpty) return const [];

    final fs = FileSystemService.instance;
    final queryHints = _extractQueryHints(query);
    final candidateIds = await _collectCandidateIds(
      userId: userId,
      currentFactId: factId,
      query: query,
      candidateLimit: candidateLimit,
    );
    if (candidateIds.isEmpty) return const [];

    final embeddingConfig = await UserStorage.getEmbeddingConfig();
    final queryEmbedding = embeddingConfig.isUsable
        ? await EmbeddingService.instance.embedText(
            query,
            config: embeddingConfig,
          )
        : null;

    final candidates = <RelatedFactCandidate>[];
    for (var index = 0; index < candidateIds.length; index++) {
      final candidateFactId = candidateIds[index];
      final factInfo = await fs.extractFactContentFromFile(
        userId,
        candidateFactId,
      );
      final card = await fs.readCardFile(userId, candidateFactId);
      if (factInfo == null && card == null) continue;
      if (card?.deleted == true) continue;

      final searchable = _buildSearchableText(
        factContent: factInfo?.content,
        card: card,
      );
      final match = await QueryMatcher.match(query, searchable);
      final lexicalScore = math.min(1.0, match.score / 12.0);
      final matchedHints = queryHints
          .where((hint) => _containsNormalized(searchable, hint))
          .toList(growable: false);
      final entityScore = queryHints.isEmpty
          ? 0.0
          : matchedHints.length / math.max(1, queryHints.length);

      var vectorScore = 0.0;
      if (queryEmbedding != null && embeddingConfig.isUsable) {
        final candidateEmbedding = await EmbeddingService.instance.embedText(
          searchable.length > 3000 ? searchable.substring(0, 3000) : searchable,
          config: embeddingConfig,
        );
        final similarity = EmbeddingService.instance.cosineSimilarity(
          queryEmbedding,
          candidateEmbedding,
        );
        vectorScore =
            similarity == null ? 0.0 : similarity.clamp(0.0, 1.0).toDouble();
      }

      final recencyScore = 1.0 - (index / math.max(1, candidateIds.length));
      final totalScore = lexicalScore * 0.55 +
          vectorScore * 0.30 +
          entityScore * 0.15 +
          recencyScore * 0.08 +
          (_isFtsCandidate(candidateFactId, candidateIds) ? 0.05 : 0.0);

      if (lexicalScore <= 0 && vectorScore < 0.2 && entityScore <= 0) {
        continue;
      }

      candidates.add(
        RelatedFactCandidate(
          factId: candidateFactId,
          title: _titleFor(card, factInfo?.content, candidateFactId),
          snippet: QueryMatcher.snippet(
            content: searchable,
            matchIndexes: match.indexes,
            maxChars: 420,
            contextRadius: 160,
          ),
          source: vectorScore >= lexicalScore ? 'hybrid_vector' : 'hybrid_text',
          lexicalScore: lexicalScore,
          vectorScore: vectorScore,
          recencyScore: recencyScore,
          entityScore: entityScore,
          totalScore: totalScore,
          matchedHints: matchedHints,
        ),
      );
    }

    candidates.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return candidates.take(limit).toList(growable: false);
  }

  List<String> _extractQueryHints(String query) {
    final hints = <String>{};

    for (final match
        in RegExp(r'[A-Za-z][A-Za-z0-9_-]{1,40}').allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final match in RegExp(
      r'[\u4e00-\u9fa5A-Za-z0-9_-]{2,24}(?:项目|改版|增长|灰度|计划|负责人|来源|边界|偏好|提醒|用药|账单|合同|实验|复盘|上线|发布|评审|资料|材料|任务)',
    ).allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final match in RegExp(r'[\u4e00-\u9fa5]{1,4}老师').allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final pattern in [
      RegExp(r'找\s*([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})'),
      RegExp(r'和\s*([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})\s*对齐'),
      RegExp(r'([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})\s*补来源'),
      RegExp(r'([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})\s*确认来源'),
    ]) {
      for (final match in pattern.allMatches(query)) {
        final value = match.group(1)?.trim();
        if (value != null && value.isNotEmpty) hints.add(value);
      }
    }

    return hints
        .where((hint) => hint.length >= 2)
        .take(12)
        .toList(growable: false);
  }

  Future<List<String>> _collectCandidateIds({
    required String userId,
    required String currentFactId,
    required String query,
    required int candidateLimit,
  }) async {
    final seen = <String>{currentFactId};
    final ids = <String>[];

    try {
      final ftsResults = await SearchService.instance.searchCards(
        query,
        limit: candidateLimit ~/ 2,
      );
      for (final result in ftsResults) {
        final id = result['fact_id']?.toString();
        if (id != null && seen.add(id)) {
          ids.add(id);
        }
      }
    } catch (e) {
      _logger.fine('FTS card candidate collection skipped: $e');
    }

    final allFacts = await FileSystemService.instance.listAllFacts(userId);
    for (final id in allFacts.reversed) {
      if (ids.length >= candidateLimit) break;
      if (seen.add(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  bool _isFtsCandidate(String factId, List<String> candidateIds) {
    final firstHalf = math.max(1, candidateIds.length ~/ 2);
    return candidateIds.take(firstHalf).contains(factId);
  }

  String _buildSearchableText({
    required String? factContent,
    required CardData? card,
  }) {
    final parts = <String>[
      if (card?.title != null) card!.title!,
      if (card != null) card.tags.join(' '),
      if (factContent != null) factContent,
      if (card?.insight?.summary != null) card!.insight!.summary!,
      if (card?.insight?.text != null) card!.insight!.text!,
      if (card != null) _uiConfigText(card.uiConfigs),
    ].where((part) => part.trim().isNotEmpty).toList();
    return parts.join('\n');
  }

  String _uiConfigText(List<UiConfig> uiConfigs) {
    final values = <String>[];
    for (final config in uiConfigs) {
      for (final value in config.data.values) {
        if (value != null) values.add(value.toString());
      }
    }
    return values.join('\n');
  }

  String _titleFor(CardData? card, String? content, String fallback) {
    final title = card?.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final contentTitle = content?.trim().split('\n').firstOrNull?.trim();
    if (contentTitle != null && contentTitle.isNotEmpty) {
      return contentTitle.length > 60
          ? '${contentTitle.substring(0, 60)}...'
          : contentTitle;
    }
    return fallback;
  }

  bool _containsNormalized(String haystack, String needle) {
    return haystack
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .contains(needle.toLowerCase().replaceAll(RegExp(r'\s+'), ''));
  }
}
