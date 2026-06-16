import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class MemoryAtomStatus {
  static const String active = 'active';
  static const String superseded = 'superseded';
  static const String deleted = 'deleted';
  static const String expired = 'expired';
  static const String conflict = 'conflict';

  static const Set<String> values = {
    active,
    superseded,
    deleted,
    expired,
    conflict,
  };
}

class MemoryAtom {
  final String id;
  final String type;
  final String title;
  final String content;
  final String status;
  final double confidence;
  final int importance;
  final List<String> entityIds;
  final List<String> evidenceFactIds;
  final String? validFrom;
  final String? validUntil;
  final String createdAt;
  final String updatedAt;
  final String sourceAgent;
  final String schemaVersion;
  final Map<String, dynamic> attributes;

  const MemoryAtom({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.status,
    required this.confidence,
    required this.importance,
    required this.entityIds,
    required this.evidenceFactIds,
    required this.validFrom,
    required this.validUntil,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceAgent,
    required this.schemaVersion,
    required this.attributes,
  });

  bool get isActive => status == MemoryAtomStatus.active;

  String get searchableText {
    return [
      type,
      title,
      content,
      entityIds.join(' '),
      attributes.values.join(' '),
    ].where((part) => part.trim().isNotEmpty).join('\n');
  }

  factory MemoryAtom.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toIso8601String();
    return MemoryAtom(
      id: json['id']?.toString() ?? json['memory_id']?.toString() ?? '',
      type: _stringOrDefault(json['type'] ?? json['kind'], 'other'),
      title: _stringOrDefault(json['title'], ''),
      content: _stringOrDefault(json['content'], ''),
      status: _normalizeStatus(json['status']?.toString()),
      confidence: _doubleOrDefault(json['confidence'], 0.7),
      importance: _intOrDefault(json['importance'], 3),
      entityIds: _stringList(json['entity_ids'] ?? json['entities']),
      evidenceFactIds: _stringList(
        json['evidence_fact_ids'] ?? json['source_fact_ids'],
      ),
      validFrom: _optionalString(json['valid_from']),
      validUntil: _optionalString(json['valid_until']),
      createdAt: _stringOrDefault(json['created_at'], now),
      updatedAt: _stringOrDefault(json['updated_at'], now),
      sourceAgent: _stringOrDefault(json['source_agent'], 'unknown'),
      schemaVersion: _stringOrDefault(json['schema_version'], 'memory_atom.v1'),
      attributes: Map<String, dynamic>.from(
        json['attributes'] as Map? ?? json['attributes_json'] as Map? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'content': content,
      'status': status,
      'confidence': confidence,
      'importance': importance,
      'entity_ids': entityIds,
      'evidence_fact_ids': evidenceFactIds,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'source_agent': sourceAgent,
      'schema_version': schemaVersion,
      'attributes': attributes,
    };
  }

  MemoryAtom copyWith({
    String? id,
    String? type,
    String? title,
    String? content,
    String? status,
    double? confidence,
    int? importance,
    List<String>? entityIds,
    List<String>? evidenceFactIds,
    String? validFrom,
    String? validUntil,
    String? createdAt,
    String? updatedAt,
    String? sourceAgent,
    String? schemaVersion,
    Map<String, dynamic>? attributes,
  }) {
    return MemoryAtom(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      importance: importance ?? this.importance,
      entityIds: entityIds ?? this.entityIds,
      evidenceFactIds: evidenceFactIds ?? this.evidenceFactIds,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceAgent: sourceAgent ?? this.sourceAgent,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      attributes: attributes ?? this.attributes,
    );
  }

  static String _normalizeStatus(String? value) {
    final normalized = value?.trim();
    if (normalized != null && MemoryAtomStatus.values.contains(normalized)) {
      return normalized;
    }
    return MemoryAtomStatus.active;
  }

  static String _stringOrDefault(dynamic value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String? _optionalString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _doubleOrDefault(dynamic value, double fallback) {
    if (value is num) return value.toDouble().clamp(0.0, 1.0).toDouble();
    return double.tryParse(value?.toString() ?? '')?.clamp(0.0, 1.0) ??
        fallback;
  }

  static int _intOrDefault(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }
}

class MemoryPatch {
  final String op;
  final String? memoryId;
  final String type;
  final String title;
  final String content;
  final String status;
  final double confidence;
  final int importance;
  final List<String> entityIds;
  final List<String> evidenceFactIds;
  final List<String> supersedesMemoryIds;
  final String? validFrom;
  final String? validUntil;
  final Map<String, dynamic> attributes;

  const MemoryPatch({
    required this.op,
    this.memoryId,
    this.type = 'other',
    this.title = '',
    this.content = '',
    this.status = MemoryAtomStatus.active,
    this.confidence = 0.7,
    this.importance = 3,
    this.entityIds = const [],
    this.evidenceFactIds = const [],
    this.supersedesMemoryIds = const [],
    this.validFrom,
    this.validUntil,
    this.attributes = const {},
  });

  factory MemoryPatch.fromJson(Map<String, dynamic> json) {
    return MemoryPatch(
      op: _clean(json['op']) ?? _clean(json['operation']) ?? 'create',
      memoryId: _clean(json['memory_id'] ?? json['id']),
      type: _clean(json['type'] ?? json['kind']) ?? 'other',
      title: _clean(json['title']) ?? '',
      content: _clean(json['content'] ?? json['memory'] ?? json['text']) ?? '',
      status: MemoryAtomStatus.values.contains(_clean(json['status']))
          ? _clean(json['status'])!
          : MemoryAtomStatus.active,
      confidence: _double(json['confidence'], 0.7),
      importance: _int(json['importance'], 3),
      entityIds: _stringList(json['entity_ids'] ?? json['entities']),
      evidenceFactIds: _stringList(
        json['evidence_fact_ids'] ?? json['source_fact_ids'],
      ),
      supersedesMemoryIds: _stringList(
        json['supersedes_memory_ids'] ?? json['supersedes'],
      ),
      validFrom: _clean(json['valid_from']),
      validUntil: _clean(json['valid_until']),
      attributes: Map<String, dynamic>.from(
        json['attributes'] as Map? ?? json['attributes_json'] as Map? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'op': op,
      if (memoryId != null) 'memory_id': memoryId,
      'type': type,
      'title': title,
      'content': content,
      'status': status,
      'confidence': confidence,
      'importance': importance,
      'entity_ids': entityIds,
      'evidence_fact_ids': evidenceFactIds,
      'supersedes_memory_ids': supersedesMemoryIds,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
      'attributes': attributes,
    };
  }

  static String? _clean(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _double(dynamic value, double fallback) {
    if (value is num) return value.toDouble().clamp(0.0, 1.0).toDouble();
    return double.tryParse(value?.toString() ?? '')?.clamp(0.0, 1.0) ??
        fallback;
  }

  static int _int(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }
}

class MemoryRecallResult {
  final MemoryAtom atom;
  final double lexicalScore;
  final double vectorScore;
  final double entityScore;
  final double recencyScore;
  final double totalScore;
  final String snippet;
  final List<String> reasons;

  const MemoryRecallResult({
    required this.atom,
    required this.lexicalScore,
    required this.vectorScore,
    required this.entityScore,
    required this.recencyScore,
    required this.totalScore,
    required this.snippet,
    required this.reasons,
  });

  Map<String, dynamic> toJson() {
    return {
      'memory_id': atom.id,
      'type': atom.type,
      'title': atom.title,
      'content': atom.content,
      'status': atom.status,
      'evidence_fact_ids': atom.evidenceFactIds,
      'snippet': snippet,
      'reasons': reasons,
      'scores': {
        'lexical': lexicalScore,
        'vector': vectorScore,
        'entity': entityScore,
        'recency': recencyScore,
        'total': totalScore,
      },
    };
  }
}

class MemoryPrimaryService {
  MemoryPrimaryService._();

  static final MemoryPrimaryService instance = MemoryPrimaryService._();

  final _logger = getLogger('MemoryPrimaryService');
  final Map<String, Future<void>> _locks = {};

  Future<List<MemoryAtom>> listAtoms(String userId) async {
    final store = await _loadStore(userId);
    return _atomsFromStore(store);
  }

  Future<List<MemoryAtom>> listActiveAtoms(String userId) async {
    final atoms = await listAtoms(userId);
    return atoms.where((atom) => atom.isActive).toList(growable: false);
  }

  Future<List<MemoryAtom>> applyPatches({
    required String userId,
    required List<MemoryPatch> patches,
    required String sourceAgent,
  }) async {
    if (patches.isEmpty) return const [];
    return _withUserLock(userId, () async {
      final store = await _loadStore(userId);
      final atoms = _atomsFromStore(store);
      final changed = <MemoryAtom>[];

      var nextId = (store['next_memory_id'] as num?)?.toInt() ?? 101;
      final now = DateTime.now().toIso8601String();

      for (final patch in patches) {
        final op = patch.op.trim().toLowerCase();
        final inheritedAttributes = _preservedAttributesFromSuperseded(
          atoms,
          patch.supersedesMemoryIds,
        );
        final patchAttributes = _mergeAttributes(
          inheritedAttributes,
          patch.attributes,
        );
        if (op == 'delete') {
          final index = _findAtomIndex(atoms, patch.memoryId);
          if (index < 0) continue;
          final updated = atoms[index].copyWith(
            status: MemoryAtomStatus.deleted,
            updatedAt: now,
            sourceAgent: sourceAgent,
          );
          atoms[index] = updated;
          changed.add(updated);
          continue;
        }

        if (op == 'expire') {
          final index = _findAtomIndex(atoms, patch.memoryId);
          if (index < 0) continue;
          final updated = atoms[index].copyWith(
            status: MemoryAtomStatus.expired,
            validUntil: patch.validUntil ?? now,
            updatedAt: now,
            sourceAgent: sourceAgent,
          );
          atoms[index] = updated;
          changed.add(updated);
          continue;
        }

        for (final supersededId in patch.supersedesMemoryIds) {
          final index = _findAtomIndex(atoms, supersededId);
          if (index < 0) continue;
          atoms[index] = atoms[index].copyWith(
            status: MemoryAtomStatus.superseded,
            updatedAt: now,
            attributes: {
              ...atoms[index].attributes,
              'superseded_by_candidate_content': patch.content,
            },
          );
          changed.add(atoms[index]);
        }

        if (op == 'update') {
          final index = _findAtomIndex(atoms, patch.memoryId);
          if (index < 0) continue;
          final current = atoms[index];
          final attributes = _mergeAttributes(
            current.attributes,
            patchAttributes,
          );
          final rawContent = patch.content.isEmpty
              ? current.content
              : _preserveRelationshipResponsibilities(
                  current: current,
                  patch: patch,
                  nextContent: patch.content,
                );
          final content = _appendPreservedTerms(rawContent, attributes);
          final updated = current.copyWith(
            type: patch.type,
            title: patch.title.isEmpty ? current.title : patch.title,
            content: content,
            status: patch.status,
            confidence: patch.confidence,
            importance: patch.importance,
            entityIds: _mergeStrings(current.entityIds, patch.entityIds),
            evidenceFactIds: _mergeStrings(
              current.evidenceFactIds,
              patch.evidenceFactIds,
            ),
            validFrom: patch.validFrom,
            validUntil: patch.validUntil,
            updatedAt: now,
            sourceAgent: sourceAgent,
            attributes: attributes,
          );
          atoms[index] = updated;
          changed.add(updated);
          continue;
        }

        final patchContent = _preserveSupersededRelationshipResponsibilities(
          atoms: atoms,
          patch: patch,
          nextContent: patch.content,
        );
        if (patchContent.trim().isEmpty) continue;
        final duplicateIndex = _findDuplicateActiveAtom(atoms, patchContent);
        if (duplicateIndex >= 0) {
          final current = atoms[duplicateIndex];
          final attributes = _mergeAttributes(
            current.attributes,
            patchAttributes,
          );
          final rawContent = _preserveRelationshipResponsibilities(
            current: current,
            patch: patch,
            nextContent: patchContent,
          );
          final content = _appendPreservedTerms(rawContent, attributes);
          final updated = current.copyWith(
            content: content,
            entityIds: _mergeStrings(current.entityIds, patch.entityIds),
            evidenceFactIds: _mergeStrings(
              current.evidenceFactIds,
              patch.evidenceFactIds,
            ),
            confidence: math.max(current.confidence, patch.confidence),
            importance: math.max(current.importance, patch.importance),
            updatedAt: now,
            sourceAgent: sourceAgent,
            attributes: attributes,
          );
          atoms[duplicateIndex] = updated;
          changed.add(updated);
          continue;
        }

        final relatedRelationshipIndex =
            _findRelatedActiveRelationshipAtom(atoms, patch);
        if (relatedRelationshipIndex >= 0) {
          final current = atoms[relatedRelationshipIndex];
          final attributes = _mergeAttributes(
            current.attributes,
            patchAttributes,
          );
          final rawContent = _preserveRelationshipResponsibilities(
            current: current,
            patch: patch,
            nextContent: patchContent,
          );
          final content = _appendPreservedTerms(rawContent, attributes);
          final updated = current.copyWith(
            type: patch.type,
            title: patch.title.isEmpty ? current.title : patch.title,
            content: content,
            entityIds: _mergeStrings(current.entityIds, patch.entityIds),
            evidenceFactIds: _mergeStrings(
              current.evidenceFactIds,
              patch.evidenceFactIds,
            ),
            confidence: math.max(current.confidence, patch.confidence),
            importance: math.max(current.importance, patch.importance),
            validFrom: patch.validFrom ?? current.validFrom,
            validUntil: patch.validUntil ?? current.validUntil,
            updatedAt: now,
            sourceAgent: sourceAgent,
            attributes: attributes,
          );
          atoms[relatedRelationshipIndex] = updated;
          changed.add(updated);
          continue;
        }

        final explicitId = patch.memoryId?.trim();
        final id = explicitId == null || explicitId.isEmpty
            ? 'mem_$nextId'
            : explicitId;
        nextId = math.max(
            nextId + (explicitId == null || explicitId.isEmpty ? 1 : 0),
            _nextIdAfter(id));
        final atom = MemoryAtom(
          id: id,
          type: patch.type,
          title: patch.title,
          content: _appendPreservedTerms(
            patchContent.trim(),
            patchAttributes,
          ),
          status: patch.status,
          confidence: patch.confidence,
          importance: patch.importance,
          entityIds: patch.entityIds,
          evidenceFactIds: patch.evidenceFactIds,
          validFrom: patch.validFrom,
          validUntil: patch.validUntil,
          createdAt: now,
          updatedAt: now,
          sourceAgent: sourceAgent,
          schemaVersion: 'memory_atom.v1',
          attributes: patchAttributes,
        );
        atoms.add(atom);
        changed.add(atom);
      }

      store['next_memory_id'] = nextId;
      store['atoms'] = atoms.map((atom) => atom.toJson()).toList();
      store['schema_version'] = 1;
      store['updated_at'] = now;
      await _writeStore(userId, store);
      await _appendChangeLog(userId, {
        'created_at': now,
        'source_agent': sourceAgent,
        'patches': patches.map((patch) => patch.toJson()).toList(),
        'changed_memory_ids': changed.map((atom) => atom.id).toList(),
      });
      return changed;
    });
  }

  Future<List<MemoryRecallResult>> searchMemory({
    required String userId,
    required String query,
    int limit = 8,
    Set<String>? types,
    Set<String>? excludeMemoryIds,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final atoms = (await listActiveAtoms(userId)).where((atom) {
      if (types != null && types.isNotEmpty && !types.contains(atom.type)) {
        return false;
      }
      if (excludeMemoryIds != null && excludeMemoryIds.contains(atom.id)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    if (atoms.isEmpty) return const [];

    final embeddingConfig = await UserStorage.getEmbeddingConfig();
    List<double>? queryEmbedding;
    var atomEmbeddings = <List<double>?>[];
    if (embeddingConfig.isUsable) {
      final embeddings = await EmbeddingService.instance.embedTexts(
        [
          trimmed,
          for (final atom in atoms) _clipForEmbedding(atom.searchableText),
        ],
        config: embeddingConfig,
      );
      if (embeddings.length == atoms.length + 1) {
        queryEmbedding = embeddings.first;
        atomEmbeddings = embeddings.skip(1).toList(growable: false);
      }
    }

    final queryTokens = _tokens(trimmed);
    final results = <MemoryRecallResult>[];
    for (var i = 0; i < atoms.length; i++) {
      final atom = atoms[i];
      final searchable = atom.searchableText;
      final lexicalScore = _lexicalScore(queryTokens, searchable);
      final entityScore = _entityScore(trimmed, atom.entityIds);
      var vectorScore = 0.0;
      if (queryEmbedding != null && i < atomEmbeddings.length) {
        vectorScore = EmbeddingService.instance
                .cosineSimilarity(queryEmbedding, atomEmbeddings[i])
                ?.clamp(0.0, 1.0)
                .toDouble() ??
            0.0;
      }
      final recencyScore = atoms.length <= 1 ? 1.0 : i / (atoms.length - 1);
      final importanceScore = atom.importance.clamp(1, 5) / 5.0;
      final totalScore = lexicalScore * 0.40 +
          vectorScore * 0.30 +
          entityScore * 0.15 +
          recencyScore * 0.08 +
          importanceScore * 0.07;

      if (lexicalScore == 0 && entityScore == 0 && vectorScore < 0.18) {
        continue;
      }

      results.add(
        MemoryRecallResult(
          atom: atom,
          lexicalScore: lexicalScore,
          vectorScore: vectorScore,
          entityScore: entityScore,
          recencyScore: recencyScore,
          totalScore: totalScore,
          snippet: _snippet(atom.content, queryTokens),
          reasons: [
            if (lexicalScore > 0) 'lexical_match',
            if (entityScore > 0) 'entity_match',
            if (vectorScore >= 0.18) 'embedding_rerank',
            if (atom.evidenceFactIds.isNotEmpty) 'has_evidence',
          ],
        ),
      );
    }

    results.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return results.take(limit).toList(growable: false);
  }

  Future<List<MemoryAtom>> findConflicts({
    required String userId,
    required MemoryPatch patch,
    int limit = 5,
  }) async {
    if (patch.content.trim().isEmpty) return const [];
    final atoms = await listActiveAtoms(userId);
    final patchEntities = patch.entityIds.map(_normalize).toSet();
    final matches = <MemoryAtom>[];
    for (final atom in atoms) {
      if (atom.type != patch.type) continue;
      final atomEntities = atom.entityIds.map(_normalize).toSet();
      if (patchEntities.isEmpty || atomEntities.isEmpty) continue;
      if (patchEntities.intersection(atomEntities).isEmpty) continue;
      if (_normalize(atom.content) == _normalize(patch.content)) continue;
      matches.add(atom);
    }
    return matches.take(limit).toList(growable: false);
  }

  Future<String> buildRecallPromptBlock({
    required String userId,
    required String query,
    int limit = 8,
  }) async {
    final recalls = await searchMemory(
      userId: userId,
      query: query,
      limit: limit,
    );
    if (recalls.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('<memory_primary_context>');
    for (final recall in recalls) {
      final atom = recall.atom;
      sb.writeln(
        '- [${atom.id}] (${atom.type}, score=${recall.totalScore.toStringAsFixed(2)}) ${atom.content}',
      );
      if (atom.evidenceFactIds.isNotEmpty) {
        sb.writeln('  evidence_fact_ids: ${atom.evidenceFactIds.join(', ')}');
      }
    }
    sb.writeln('</memory_primary_context>');
    return sb.toString();
  }

  Future<void> resetMemoryPrimaryData(String userId) async {
    await _withUserLock(userId, () async {
      final dir = Directory(
        FileSystemService.instance.getMemoryPrimaryPath(userId),
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
  }

  Future<T> _withUserLock<T>(
    String userId,
    Future<T> Function() operation,
  ) async {
    final key = FileSystemService.instance.getMemoryPrimaryPath(userId);
    while (_locks.containsKey(key)) {
      await _locks[key]!;
    }
    final completer = Completer<void>();
    _locks[key] = completer.future;
    try {
      return await operation();
    } finally {
      completer.complete();
      _locks.remove(key);
    }
  }

  Future<Map<String, dynamic>> _loadStore(String userId) async {
    final path = FileSystemService.instance.getMemoryAtomsPath(userId);
    final file = File(path);
    if (!await file.exists()) {
      return {
        'schema_version': 1,
        'next_memory_id': 101,
        'atoms': <Map<String, dynamic>>[],
      };
    }
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('Failed to load memory store for $userId: $e');
      return {
        'schema_version': 1,
        'next_memory_id': 101,
        'atoms': <Map<String, dynamic>>[],
      };
    }
  }

  Future<void> _writeStore(String userId, Map<String, dynamic> store) async {
    final path = FileSystemService.instance.getMemoryAtomsPath(userId);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(store));
  }

  Future<void> _appendChangeLog(
    String userId,
    Map<String, dynamic> entry,
  ) async {
    final path = FileSystemService.instance.getMemoryChangeLogPath(userId);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  List<MemoryAtom> _atomsFromStore(Map<String, dynamic> store) {
    final raw = store['atoms'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => MemoryAtom.fromJson(Map<String, dynamic>.from(item)))
        .where((atom) => atom.id.isNotEmpty && atom.content.isNotEmpty)
        .toList();
  }

  int _findAtomIndex(List<MemoryAtom> atoms, String? memoryId) {
    if (memoryId == null || memoryId.trim().isEmpty) return -1;
    return atoms.indexWhere((atom) => atom.id == memoryId);
  }

  int _findDuplicateActiveAtom(List<MemoryAtom> atoms, String content) {
    final normalized = _normalizeDuplicateContent(content);
    return atoms.indexWhere(
      (atom) =>
          atom.isActive &&
          _normalizeDuplicateContent(atom.content) == normalized,
    );
  }

  String _normalizeDuplicateContent(String content) {
    final withoutPreservedTerms = content
        .replaceAll(RegExp(r'\s*保留用户原词偏好：[^。]*。'), ' ')
        .replaceAll(RegExp(r'\s*保留用户原词约束：[^。]*。'), ' ')
        .trim();
    return _normalize(withoutPreservedTerms);
  }

  List<String> _mergeStrings(List<String> a, List<String> b) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in [...a, ...b]) {
      final text = value.trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }

  Map<String, dynamic> _mergeAttributes(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final merged = {...a, ...b};
    final preservedTerms = _mergeStrings(
      _attributeStringList(a['preserved_report_terms']),
      _attributeStringList(b['preserved_report_terms']),
    );
    if (preservedTerms.isNotEmpty) {
      merged['preserved_report_terms'] = preservedTerms;
    }
    final preservedPersonalTerms = _mergeStrings(
      _attributeStringList(a['preserved_personal_terms']),
      _attributeStringList(b['preserved_personal_terms']),
    );
    if (preservedPersonalTerms.isNotEmpty) {
      merged['preserved_personal_terms'] = preservedPersonalTerms;
    }
    return merged;
  }

  Map<String, dynamic> _preservedAttributesFromSuperseded(
    List<MemoryAtom> atoms,
    List<String> supersededIds,
  ) {
    final preservedTerms = <String>[];
    final preservedPersonalTerms = <String>[];
    for (final id in supersededIds) {
      final index = _findAtomIndex(atoms, id);
      if (index < 0) continue;
      preservedTerms.addAll(
        _attributeStringList(
          atoms[index].attributes['preserved_report_terms'],
        ),
      );
      preservedPersonalTerms.addAll(
        _attributeStringList(
          atoms[index].attributes['preserved_personal_terms'],
        ),
      );
    }
    final mergedTerms = _mergeStrings(const [], preservedTerms);
    final mergedPersonalTerms = _mergeStrings(const [], preservedPersonalTerms);
    if (mergedTerms.isEmpty && mergedPersonalTerms.isEmpty) return const {};
    return {
      if (mergedTerms.isNotEmpty) 'preserved_report_terms': mergedTerms,
      if (mergedPersonalTerms.isNotEmpty)
        'preserved_personal_terms': mergedPersonalTerms,
    };
  }

  String _appendPreservedTerms(
    String content,
    Map<String, dynamic> attributes,
  ) {
    var result = content;
    final preservedTerms =
        _attributeStringList(attributes['preserved_report_terms']);
    result = _appendMissingTerms(
      result,
      preservedTerms,
      '保留用户原词偏好',
    );
    final preservedPersonalTerms =
        _attributeStringList(attributes['preserved_personal_terms']);
    result = _appendMissingTerms(
      result,
      preservedPersonalTerms,
      '保留用户原词约束',
    );
    return result;
  }

  String _preserveRelationshipResponsibilities({
    required MemoryAtom current,
    required MemoryPatch patch,
    required String nextContent,
  }) {
    if (!_isRelationshipLikeMemory(current.type, current.content) &&
        !_isRelationshipLikeMemory(patch.type, patch.content)) {
      return nextContent;
    }
    var result = nextContent.trim();
    if (result.isEmpty) return result;

    for (final clause in _relationshipResponsibilityClauses(current.content)) {
      if (result.contains(clause)) continue;
      final responsibility = _responsibilityObject(clause);
      if (responsibility != null && result.contains(responsibility)) continue;
      result = '$clause；$result';
    }
    return result;
  }

  String _preserveSupersededRelationshipResponsibilities({
    required List<MemoryAtom> atoms,
    required MemoryPatch patch,
    required String nextContent,
  }) {
    var result = nextContent;
    for (final supersededId in patch.supersedesMemoryIds) {
      final index = _findAtomIndex(atoms, supersededId);
      if (index < 0) continue;
      result = _preserveRelationshipResponsibilities(
        current: atoms[index],
        patch: patch,
        nextContent: result,
      );
    }
    return result;
  }

  int _findRelatedActiveRelationshipAtom(
    List<MemoryAtom> atoms,
    MemoryPatch patch,
  ) {
    if (!_isRelationshipLikeMemory(patch.type, patch.content)) return -1;
    final patchKeys = _relationshipSpecificKeys(
      patch.entityIds,
      patch.content,
    );
    if (patchKeys.isEmpty) return -1;
    for (var i = 0; i < atoms.length; i++) {
      final atom = atoms[i];
      if (!atom.isActive ||
          !_isRelationshipLikeMemory(atom.type, atom.content)) {
        continue;
      }
      final atomKeys = _relationshipSpecificKeys(
        atom.entityIds,
        '${atom.title} ${atom.content}',
      );
      if (atomKeys.intersection(patchKeys).isNotEmpty) {
        return i;
      }
    }
    return -1;
  }

  bool _isRelationshipLikeMemory(String type, String content) {
    if (type == 'relationship') return true;
    return RegExp(r'负责|职责|联系人|合同付款|发票确认|产品评审|体验文案').hasMatch(content);
  }

  int _nextIdAfter(String memoryId) {
    final match = RegExp(r'^mem_(\d+)$').firstMatch(memoryId);
    final numeric = int.tryParse(match?.group(1) ?? '');
    if (numeric == null) return 0;
    return numeric + 1;
  }

  Set<String> _relationshipSpecificKeys(
    List<String> entityIds,
    String content,
  ) {
    final keys = <String>{};
    for (final entity in entityIds) {
      final normalized = _normalizeRelationshipKey(entity);
      if (normalized != null) keys.add(normalized);
    }
    for (final match
        in RegExp(r'\b[A-Z][A-Za-z]{2,}[A-Z]\b').allMatches(content)) {
      final normalized = _normalizeRelationshipKey(match.group(0)!);
      if (normalized != null) keys.add(normalized);
    }
    return keys;
  }

  String? _normalizeRelationshipKey(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.length < 2) return null;
    const generic = {
      '关系',
      '职责',
      '负责',
      '负责人',
      '联系人',
      '合同',
      '合同付款',
      '付款',
      '发票',
      '发票确认',
      '产品评审',
      '体验文案',
      'owner',
      'project',
      'orion',
      'meridian',
    };
    if (generic.contains(normalized)) return null;
    if (normalized.contains('project') ||
        normalized.contains('orion') ||
        normalized.contains('meridian') ||
        normalized.contains('导出')) {
      return null;
    }
    return normalized;
  }

  List<String> _relationshipResponsibilityClauses(String content) {
    return content
        .split(RegExp(r'[。；;\n，,]+'))
        .map((clause) => clause.trim())
        .where((clause) {
      if (clause.isEmpty) return false;
      if (!clause.contains('负责') && !clause.contains('职责')) return false;
      if (RegExp(r'不负责|以前|旧|历史|曾经|此前|之前|只适用|仅适用').hasMatch(clause)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  String? _responsibilityObject(String clause) {
    final match =
        RegExp(r'(?:负责|职责(?:是|为|包括)?|负责范围(?:是|为)?)\s*(.+)$').firstMatch(clause);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String _appendMissingTerms(
    String content,
    List<String> preservedTerms,
    String label,
  ) {
    final missingTerms = preservedTerms
        .where((term) => term.isNotEmpty && !content.contains(term))
        .toList(growable: false);
    if (missingTerms.isEmpty) return content;
    final trimmed = content.trim();
    final suffix = '$label：${missingTerms.join('、')}。';
    return trimmed.isEmpty ? suffix : '$trimmed $suffix';
  }

  List<String> _attributeStringList(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }

  List<String> _tokens(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>{};
    for (final match in RegExp(r'[a-z0-9_./-]{2,}').allMatches(lower)) {
      tokens.add(match.group(0)!);
    }
    for (final match in RegExp(r'[\u4e00-\u9fa5]+').allMatches(text)) {
      _addCjkTokens(tokens, match.group(0)!);
    }
    return tokens.take(32).toList(growable: false);
  }

  void _addCjkTokens(Set<String> tokens, String text) {
    if (text.length < 2) return;
    if (text.length <= 8) tokens.add(text);
    for (final size in const [2, 3, 4]) {
      if (text.length < size) continue;
      for (var i = 0; i <= text.length - size; i++) {
        tokens.add(text.substring(i, i + size));
      }
    }
  }

  double _lexicalScore(List<String> queryTokens, String searchable) {
    if (queryTokens.isEmpty) return 0;
    final normalizedSearchable = _normalize(searchable);
    var hits = 0;
    for (final token in queryTokens) {
      if (normalizedSearchable.contains(_normalize(token))) hits += 1;
    }
    return (hits / queryTokens.length).clamp(0.0, 1.0).toDouble();
  }

  double _entityScore(String query, List<String> entityIds) {
    if (entityIds.isEmpty) return 0;
    final normalizedQuery = _normalize(query);
    var hits = 0;
    for (final entity in entityIds) {
      if (normalizedQuery.contains(_normalize(entity))) hits += 1;
    }
    return (hits / entityIds.length).clamp(0.0, 1.0).toDouble();
  }

  String _snippet(String content, List<String> queryTokens) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 360) return compact;
    for (final token in queryTokens) {
      final index = _normalize(compact).indexOf(_normalize(token));
      if (index >= 0) {
        final start = math.max(0, index - 140);
        final end = math.min(compact.length, index + 220);
        return '${start > 0 ? '...' : ''}${compact.substring(start, end)}${end < compact.length ? '...' : ''}';
      }
    }
    return '${compact.substring(0, 360)}...';
  }

  String _clipForEmbedding(String text) {
    return text.length > 3000 ? text.substring(0, 3000) : text;
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }
}
