import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
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
  final double memoryEvidenceScore;
  final double anchorScore;
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
    this.memoryEvidenceScore = 0,
    this.anchorScore = 0,
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
        'memory_evidence': memoryEvidenceScore,
        'anchor': anchorScore,
        'total': totalScore,
      },
      if (matchedHints.isNotEmpty) 'matched_hints': matchedHints,
    };
  }
}

class _RelatedFactScratch {
  final String factId;
  final String title;
  final String searchable;
  final QueryMatch match;
  final double lexicalScore;
  final double recencyScore;
  final double entityScore;
  final double memoryEvidenceScore;
  final double anchorScore;
  final List<String> matchedHints;

  const _RelatedFactScratch({
    required this.factId,
    required this.title,
    required this.searchable,
    required this.match,
    required this.lexicalScore,
    required this.recencyScore,
    required this.entityScore,
    required this.memoryEvidenceScore,
    required this.anchorScore,
    required this.matchedHints,
  });
}

class RelatedFactsService {
  RelatedFactsService._();

  static final RelatedFactsService instance = RelatedFactsService._();

  final _logger = getLogger('RelatedFactsService');

  Future<List<RelatedFactCandidate>> findRelatedFacts({
    required String userId,
    required String factId,
    required String contentText,
    int limit = 8,
    int candidateLimit = 80,
  }) async {
    final query = contentText.trim();
    if (query.isEmpty) return const [];

    final fs = FileSystemService.instance;
    final queryHints = _extractQueryHints(query);
    final memoryEvidenceIds = await _collectMemoryEvidenceIds(
      userId: userId,
      currentFactId: factId,
      query: query,
    );
    final correctionAnchorFactIds = await _collectCorrectionAnchorFactIds(
      userId: userId,
      currentFactId: factId,
      query: query,
      queryHints: queryHints,
      limit: 3,
    );
    final genericAnchorFactIds = await _collectAnchorFactIds(
      userId: userId,
      currentFactId: factId,
      queryHints: queryHints,
      limit: 3,
    );
    final anchorFactIds = _dedupeIds([
      ...correctionAnchorFactIds,
      ...genericAnchorFactIds,
    ]);
    final candidateIds = await _collectCandidateIds(
      userId: userId,
      currentFactId: factId,
      query: query,
      candidateLimit: candidateLimit,
      priorityFactIds: [
        ...anchorFactIds,
        ...memoryEvidenceIds,
      ],
    );
    if (candidateIds.isEmpty) return const [];

    final scratchCandidates = <_RelatedFactScratch>[];
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
      final memoryEvidenceScore =
          memoryEvidenceIds.contains(candidateFactId) ? 1.0 : 0.0;
      final anchorScore = anchorFactIds.contains(candidateFactId) ? 1.0 : 0.0;
      final recencyScore = 1.0 - (index / math.max(1, candidateIds.length));

      scratchCandidates.add(
        _RelatedFactScratch(
          factId: candidateFactId,
          title: _titleFor(card, factInfo?.content, candidateFactId),
          searchable: searchable,
          match: match,
          lexicalScore: lexicalScore,
          recencyScore: recencyScore,
          entityScore: entityScore,
          memoryEvidenceScore: memoryEvidenceScore,
          anchorScore: anchorScore,
          matchedHints: matchedHints,
        ),
      );
    }

    final embeddingConfig = await UserStorage.getEmbeddingConfig();
    List<double>? queryEmbedding;
    var candidateEmbeddings = <List<double>?>[];
    if (embeddingConfig.isUsable && scratchCandidates.isNotEmpty) {
      final embeddings = await EmbeddingService.instance.embedTexts(
        [
          query,
          for (final candidate in scratchCandidates)
            _clipForEmbedding(candidate.searchable),
        ],
        config: embeddingConfig,
      );
      if (embeddings.length == scratchCandidates.length + 1) {
        queryEmbedding = embeddings.first;
        candidateEmbeddings = embeddings.skip(1).toList(growable: false);
      }
    }

    final candidates = <RelatedFactCandidate>[];
    for (var index = 0; index < scratchCandidates.length; index++) {
      final scratch = scratchCandidates[index];
      var vectorScore = 0.0;
      if (queryEmbedding != null && index < candidateEmbeddings.length) {
        final similarity = EmbeddingService.instance.cosineSimilarity(
          queryEmbedding,
          candidateEmbeddings[index],
        );
        vectorScore =
            similarity == null ? 0.0 : similarity.clamp(0.0, 1.0).toDouble();
      }

      final totalScore = scratch.lexicalScore * 0.45 +
          vectorScore * 0.25 +
          scratch.entityScore * 0.15 +
          scratch.memoryEvidenceScore * 0.30 +
          scratch.anchorScore * 0.35 +
          scratch.recencyScore * 0.05 +
          (_isFtsCandidate(scratch.factId, candidateIds) ? 0.05 : 0.0);

      if (scratch.lexicalScore <= 0 &&
          vectorScore < 0.2 &&
          scratch.entityScore <= 0 &&
          scratch.memoryEvidenceScore <= 0 &&
          scratch.anchorScore <= 0) {
        continue;
      }

      candidates.add(
        RelatedFactCandidate(
          factId: scratch.factId,
          title: scratch.title,
          snippet: QueryMatcher.snippet(
            content: scratch.searchable,
            matchIndexes: scratch.match.indexes,
            maxChars: 420,
            contextRadius: 160,
          ),
          source: scratch.memoryEvidenceScore > 0
              ? 'memory_evidence'
              : scratch.anchorScore > 0
                  ? 'project_anchor'
                  : vectorScore >= scratch.lexicalScore
                      ? 'hybrid_vector'
                      : 'hybrid_text',
          lexicalScore: scratch.lexicalScore,
          vectorScore: vectorScore,
          recencyScore: scratch.recencyScore,
          entityScore: scratch.entityScore,
          memoryEvidenceScore: scratch.memoryEvidenceScore,
          anchorScore: scratch.anchorScore,
          totalScore: totalScore,
          matchedHints: scratch.matchedHints,
        ),
      );
    }

    candidates.sort((a, b) {
      final aAnchorRank = anchorFactIds.indexOf(a.factId);
      final bAnchorRank = anchorFactIds.indexOf(b.factId);
      if (aAnchorRank >= 0 || bAnchorRank >= 0) {
        if (aAnchorRank < 0) return 1;
        if (bAnchorRank < 0) return -1;
        return aAnchorRank.compareTo(bAnchorRank);
      }
      return b.totalScore.compareTo(a.totalScore);
    });
    return candidates.take(limit).toList(growable: false);
  }

  List<String> _extractQueryHints(String query) {
    final hints = <String>{};

    for (final match in RegExp(
      r'[A-Za-z][A-Za-z0-9_-]{1,40}',
    ).allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final match in RegExp(
      r'[A-Za-z][A-Za-z0-9_-]{1,40}\s*[\u4e00-\u9fa5]{1,12}',
    ).allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final match in RegExp(
      r'[\u4e00-\u9fa5A-Za-z0-9_-]{2,24}(?:项目|改版|增长|灰度|计划|负责人|来源|边界|偏好|提醒|用药|账单|合同|实验|复盘|上线|发布|评审|资料|材料|任务|迁移|看板|协作|系统|预测|洞察库)',
    ).allMatches(query)) {
      hints.add(match.group(0)!);
    }

    for (final pattern in [
      RegExp(
        r'([A-Za-z][A-Za-z0-9_-]{1,40}\s*[\u4e00-\u9fa5]{1,12}|[\u4e00-\u9fa5A-Za-z0-9_-]{2,24})\s*的(?:客服|导出|验收|灰度|复盘)',
      ),
      RegExp(
        r'给我做\s*([A-Za-z][A-Za-z0-9_-]{1,40}\s*[\u4e00-\u9fa5]{1,12}|[\u4e00-\u9fa5A-Za-z0-9_-]{2,24})\s*相关总结',
      ),
    ]) {
      for (final match in pattern.allMatches(query)) {
        final value = match.group(1)?.trim();
        if (value != null && value.isNotEmpty) hints.add(value);
      }
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
    required List<String> priorityFactIds,
  }) async {
    final seen = <String>{currentFactId};
    final ids = <String>[];

    for (final id in priorityFactIds) {
      if (ids.length >= candidateLimit) break;
      if (seen.add(id)) ids.add(id);
    }

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

    final allFacts = [
      ...await FileSystemService.instance.listAllFacts(userId),
    ]..sort();
    for (final id in allFacts.reversed) {
      if (ids.length >= candidateLimit) break;
      if (seen.add(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  Future<List<String>> _collectCorrectionAnchorFactIds({
    required String userId,
    required String currentFactId,
    required String query,
    required List<String> queryHints,
    required int limit,
  }) async {
    if (!_looksLikeCorrection(query)) return const [];
    final oldSubjects = _extractCorrectedSubjects(query);
    if (oldSubjects.isEmpty) return const [];
    final projectHints =
        queryHints.where(_isStrongAnchorHint).toList(growable: false);

    final ids = <String>[];
    final allFacts = [
      ...await FileSystemService.instance.listAllFacts(userId),
    ]..sort();
    for (final id in allFacts) {
      if (ids.length >= limit) break;
      if (id == currentFactId) continue;

      final factInfo = await FileSystemService.instance
          .extractFactContentFromFile(userId, id);
      final card = await FileSystemService.instance.readCardFile(userId, id);
      if (factInfo == null && card == null) continue;
      if (card?.deleted == true) continue;

      final searchable = _buildSearchableText(
        factContent: factInfo?.content,
        card: card,
      );
      final hasOldSubject = oldSubjects.any(
        (subject) => _containsNormalized(searchable, subject),
      );
      if (!hasOldSubject) continue;

      final hasProjectHint = projectHints.isEmpty ||
          projectHints.any((hint) => _containsNormalized(searchable, hint));
      final hasOwnershipLanguage = RegExp(
        r'(负责|负责人|owner|验收口径|分工)',
        caseSensitive: false,
      ).hasMatch(searchable);
      if (hasProjectHint && hasOwnershipLanguage) ids.add(id);
    }
    return ids;
  }

  Future<List<String>> _collectMemoryEvidenceIds({
    required String userId,
    required String currentFactId,
    required String query,
  }) async {
    try {
      final recalls = await MemoryPrimaryService.instance.searchMemory(
        userId: userId,
        query: query,
        limit: 10,
      );
      final seen = <String>{currentFactId};
      final ids = <String>[];
      for (final recall in recalls) {
        for (final id in recall.atom.evidenceFactIds) {
          if (seen.add(id)) ids.add(id);
        }
      }
      return ids;
    } catch (e) {
      _logger.fine('Memory evidence candidate collection skipped: $e');
      return const [];
    }
  }

  Future<List<String>> _collectAnchorFactIds({
    required String userId,
    required String currentFactId,
    required List<String> queryHints,
    required int limit,
  }) async {
    final significantHints = queryHints
        .where(
          (hint) => !RegExp(
            r'^(FAQ|owner)$',
            caseSensitive: false,
          ).hasMatch(hint),
        )
        .toList(growable: false);
    if (significantHints.isEmpty) return const [];
    if (significantHints.length == 1 &&
        !_isStrongAnchorHint(significantHints.single)) {
      return const [];
    }
    final strongAnchorHints =
        significantHints.where(_isStrongAnchorHint).toList(growable: false);
    final minMatchedHints = significantHints.length >= 2 ? 2 : 1;

    final ids = <String>[];
    final allFacts = [
      ...await FileSystemService.instance.listAllFacts(userId),
    ]..sort();
    for (final id in allFacts) {
      if (ids.length >= limit) break;
      if (id == currentFactId) continue;

      final factInfo = await FileSystemService.instance
          .extractFactContentFromFile(userId, id);
      final card = await FileSystemService.instance.readCardFile(userId, id);
      if (factInfo == null && card == null) continue;
      if (card?.deleted == true) continue;

      final searchable = _buildSearchableText(
        factContent: factInfo?.content,
        card: card,
      );
      final matched = significantHints
          .where((hint) => _containsNormalized(searchable, hint))
          .length;
      final strongMatched = strongAnchorHints
          .where((hint) => _containsNormalized(searchable, hint))
          .isNotEmpty;
      if (strongMatched || matched >= minMatchedHints) ids.add(id);
    }
    return ids;
  }

  bool _isStrongAnchorHint(String hint) {
    final compact = hint.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 4) return false;
    if (RegExp(
      r'(项目|改版|增长|灰度|计划|实验|复盘|上线|发布|评审|任务|迁移|看板|协作|系统|预测|洞察库)$',
    ).hasMatch(compact)) {
      return true;
    }
    return RegExp(r'[A-Za-z]').hasMatch(compact) &&
        RegExp(r'[\u4e00-\u9fa5]').hasMatch(compact);
  }

  bool _looksLikeCorrection(String query) {
    return RegExp(
      r'(以这条为准|覆盖|作废|更正|纠正|改成|不是|之前关于)',
    ).hasMatch(query);
  }

  List<String> _extractCorrectedSubjects(String query) {
    final subjects = <String>{};
    final patterns = [
      RegExp(
        r'之前关于\s*([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})\s*负责',
        caseSensitive: false,
      ),
      RegExp(
        r'([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})\s*负责的说法',
        caseSensitive: false,
      ),
      RegExp(
        r'不是\s*([A-Za-z][A-Za-z0-9_-]{1,40}|[\u4e00-\u9fa5]{2,8})',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(query)) {
        final value = match.group(1)?.trim();
        if (value != null && value.isNotEmpty) subjects.add(value);
      }
    }
    return subjects.toList(growable: false);
  }

  List<String> _dedupeIds(Iterable<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (seen.add(id)) id,
    ];
  }

  bool _isFtsCandidate(String factId, List<String> candidateIds) {
    final firstHalf = math.max(1, candidateIds.length ~/ 2);
    return candidateIds.take(firstHalf).contains(factId);
  }

  String _clipForEmbedding(String text) {
    return text.length > 3000 ? text.substring(0, 3000) : text;
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
