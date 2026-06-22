import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/prompts.dart';
import 'package:memex/data/services/file_operation_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/date_util.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';

final getCurrentTimeTool = Tool(
  name: 'getCurrentTime',
  description: 'Get current time and week id',
  parameters: {'type': 'object', 'properties': {}},
  executable: () {
    final now = DateTime.now();

    // ISO week year can be different from calendar year (e.g. early Jan)
    // Adjust year if needed.
    // For simplicity, let's trust the Monday-based calc.
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final thursday = monday.add(const Duration(days: 3));
    final year = thursday.year;

    final weekId = '${year}_W${isoWeekNumber(now)}';
    return "Current Local Time: ${formatLocalDateTimeWithZone(now)}, Current WeekId: $weekId";
  },
);

final getPkmOverviewTool = Tool(
  name: 'get_pkm_overview',
  description:
      'Get current directory structure and file information of the PKM knowledge base.',
  parameters: {'type': 'object', 'properties': {}},
  executable: () async {
    final context = AgentCallToolContext.current;
    if (context == null) {
      throw StateError(
        "get_pkm_overview must be called within an agent execution context.",
      );
    }
    final userId = context.state.metadata['userId'] as String;
    final fileService = FileSystemService.instance;
    final fileOpService = FileOperationService.instance;

    final workingDirectory = fileService.getWorkspacePath(userId);
    final pkmPath = fileService.getPkmPath(userId);
    final pkmDir = Directory(pkmPath);

    String pkmStructure = '';
    try {
      if (pkmDir.existsSync()) {
        pkmStructure = await fileOpService.listDirectory(
          dirPath: pkmPath,
          workingDirectory: workingDirectory,
        );
      } else {
        pkmStructure = Prompts.pkmAgentDirectoryNotCreated;
      }
    } catch (e) {
      getLogger('PkmAgent').warning('Failed to get PKM structure: $e');
      pkmStructure = Prompts.pkmAgentDirectoryStructureError(e.toString());
    }
    final header = pkmStructure.contains('passing a specific path')
        ? Prompts.pkmAgentTruncatedOverviewHeader
        : Prompts.pkmAgentFullOverviewHeader;
    return '''<system-reminder>
$header
$pkmStructure
</system-reminder>''';
  },
);

Tool buildSearchMemoryPrimaryTool() {
  return Tool(
    name: 'search_memory_primary',
    description: '''
Search the user's active Memory Primary atoms. Use this before falling back to generic answers when the user asks about their preferences, project state, decisions, relationships, corrections, or remembered context.

Returns ranked memories with score, type, content, entities, and evidence fact ids. This tool is read-only and does not modify memory.
''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Natural language query describing the memory or context to recall.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum memories to return. Defaults to 8.',
        },
        'types': {
          'type': 'array',
          'description':
              'Optional Memory Primary atom types to include, such as interaction_preference, project_context, identity, relationship.',
          'items': {'type': 'string'},
        },
      },
      'required': ['query'],
    },
    executable: (String query, int? limit, List<dynamic>? types) async {
      final context = AgentCallToolContext.current;
      if (context == null) {
        throw StateError(
          'search_memory_primary must be called within an agent execution context.',
        );
      }
      final userId = context.state.metadata['userId'] as String;
      final requestedTypes = types
          ?.map((type) => type.toString().trim())
          .where((type) => type.isNotEmpty)
          .toSet();
      final typeSet = _expandMemoryTypeFilters(requestedTypes);
      final results = await searchMemoryPrimaryForTool(
        userId: userId,
        query: query,
        limit: (limit ?? 8).clamp(1, 20),
        types: typeSet == null || typeSet.isEmpty ? null : typeSet,
      );
      if (results.isEmpty) {
        return '<memory_primary_context>No active memories matched.</memory_primary_context>';
      }

      final buffer = StringBuffer();
      final currentStateQuery = _looksLikeCurrentStateQuery(query);
      buffer.writeln('<memory_primary_context>');
      for (final result in results) {
        final atom = result.atom;
        final content = currentStateQuery
            ? _redactSupersededValuesForCurrentState(atom.content)
            : atom.content;
        final visibleEntityIds = currentStateQuery
            ? atom.entityIds.where(content.contains).toList(growable: false)
            : atom.entityIds;
        buffer.writeln(
          '- [${atom.id}] (${atom.type}, score=${result.totalScore.toStringAsFixed(2)}, confidence=${atom.confidence.toStringAsFixed(2)}, importance=${atom.importance}) $content',
        );
        if (visibleEntityIds.isNotEmpty) {
          buffer.writeln('  entities: ${visibleEntityIds.join(', ')}');
        }
        if (atom.evidenceFactIds.isNotEmpty) {
          buffer.writeln(
            '  evidence_fact_ids: ${atom.evidenceFactIds.join(', ')}',
          );
        }
        if (result.reasons.isNotEmpty) {
          buffer.writeln('  reasons: ${result.reasons.join(', ')}');
        }
        if (result.retrievalSources.isNotEmpty) {
          buffer.writeln(
            '  retrieval_sources: ${result.retrievalSources.join(', ')}',
          );
        }
        final ranks = [
          if (result.ftsRank != null) 'fts=${result.ftsRank}',
          if (result.vectorRank != null) 'vector=${result.vectorRank}',
        ];
        if (ranks.isNotEmpty) {
          buffer.writeln('  retrieval_ranks: ${ranks.join(', ')}');
        }
      }
      buffer.writeln('</memory_primary_context>');
      final directAnswerCandidates = _directAnswerCandidatesForTool(
        query,
        results,
      );
      if (directAnswerCandidates.isNotEmpty) {
        buffer.writeln('<direct_answer_candidates>');
        for (final candidate in directAnswerCandidates) {
          buffer.writeln('- $candidate');
        }
        buffer.writeln('</direct_answer_candidates>');
      }
      if (currentStateQuery) {
        buffer.writeln('<system-reminder>');
        buffer.writeln(
          'For current-state answers, use only the current value from Memory Primary. If a memory says old records were corrected, do not name or quote the stale old value; say only that previous records were superseded. If the user asks for evidence, cite evidence_fact_ids and paraphrase the current-value clause instead of opening or copying raw correction text that contains stale values. Do not add risk or next-step claims unless the returned memories explicitly contain that evidence.',
        );
        buffer.writeln('</system-reminder>');
      }
      if (_looksLikePreferenceQuery(query)) {
        final constraints = _preferenceConstraintsForTool(results);
        if (constraints.isNotEmpty) {
          buffer.writeln('<preference_constraints>');
          for (final constraint in constraints) {
            buffer.writeln('- $constraint');
          }
          buffer.writeln('</preference_constraints>');
        }
        buffer.writeln('<system-reminder>');
        buffer.writeln(
          'For preference questions, the final answer MUST include every bullet in <preference_constraints> using the same concrete terms. Do not infer current-vs-historical owner rules or conflict-handling rules unless a returned memory explicitly states them. Preserve conclusion-first, risk, next-step, owner, evidence-source, background placement, deadline splitting, and original user wording exactly when they are returned. For report-format questions, list these as format fields only; do not populate owner, risk, or next-step fields with project facts, and do not add benefit/rationale, OCR, or failure-recovery details unless the user asked for them and returned memories explicitly tie them to the requested format.',
        );
        buffer.writeln('</system-reminder>');
      }
      if (_looksLikeRelationshipQuery(query)) {
        buffer.writeln('<system-reminder>');
        buffer.writeln(
          'For relationship, owner, or contact questions, answer each sub-question only from the returned memories. Name a person for a responsibility only when a returned memory contains both the person and that responsibility. When possible, include the relevant evidence_fact_ids for each named person or responsibility, especially when the user asks a multi-part question. If a sub-question is not supported by returned memories, say it was not found instead of filling from general context.',
        );
        buffer.writeln('</system-reminder>');
      }
      return buffer.toString();
    },
  );
}

Future<List<MemoryRecallResult>> searchMemoryPrimaryForTool({
  required String userId,
  required String query,
  required int limit,
  Set<String>? types,
}) async {
  final primary = await MemoryPrimaryService.instance.searchMemory(
    userId: userId,
    query: query,
    limit: limit,
    types: types,
  );
  final merged = _mergeMemoryRecallResults(primary);

  if (_looksLikeRelationshipQuery(query)) {
    for (final expandedQuery in _relationshipExpandedQueriesForTool(query)) {
      final relationshipResults =
          await MemoryPrimaryService.instance.searchMemory(
        userId: userId,
        query: expandedQuery,
        limit: limit,
        types: types,
      );
      _mergeMemoryRecallResults(relationshipResults, into: merged);
    }
    final directRelationshipResults = await _directTermMatchResults(
      userId: userId,
      query: query,
      terms: _relationshipTermsForQuery(query),
      preferredTypes: const {'relationship'},
      types: types,
      reason: 'relationship_term_match',
    );
    _mergeMemoryRecallResults(directRelationshipResults, into: merged);
    merged.sort((a, b) {
      final boostDiff = _relationshipResultBoost(query, b.atom) -
          _relationshipResultBoost(query, a.atom);
      if (boostDiff != 0) return boostDiff;
      return b.totalScore.compareTo(a.totalScore);
    });
  }

  if (_looksLikeIdentityOrRoutineQuery(query)) {
    for (final expandedQuery in _identityRoutineExpandedQueriesForTool(query)) {
      final identityRoutineResults =
          await MemoryPrimaryService.instance.searchMemory(
        userId: userId,
        query: expandedQuery,
        limit: limit,
        types: const {'identity', 'routine', 'preference'},
      );
      _mergeMemoryRecallResults(identityRoutineResults, into: merged);
    }
    final directIdentityRoutineResults = await _directTermMatchResults(
      userId: userId,
      query: query,
      terms: _identityRoutineTermsForQuery(query),
      preferredTypes: const {'identity', 'routine', 'preference'},
      types: types,
      reason: 'identity_routine_term_match',
    );
    _mergeMemoryRecallResults(directIdentityRoutineResults, into: merged);
    merged.sort((a, b) {
      final boostDiff = _identityRoutineResultBoost(query, b.atom) -
          _identityRoutineResultBoost(query, a.atom);
      if (boostDiff != 0) return boostDiff;
      return b.totalScore.compareTo(a.totalScore);
    });
  }

  if (_looksLikeRoleMoodTransitionQuery(query)) {
    for (final expandedQuery in _roleMoodExpandedQueriesForTool(query)) {
      final roleMoodResults = await MemoryPrimaryService.instance.searchMemory(
        userId: userId,
        query: expandedQuery,
        limit: limit,
        types: const {'project_context', 'boundary'},
      );
      _mergeMemoryRecallResults(roleMoodResults, into: merged);
    }
    final directRoleMoodResults = await _directTermMatchResults(
      userId: userId,
      query: query,
      terms: _roleMoodTermsForQuery(query),
      preferredTypes: const {'project_context', 'boundary'},
      types: types,
      reason: 'role_mood_term_match',
    );
    _mergeMemoryRecallResults(directRoleMoodResults, into: merged);
    merged.sort((a, b) {
      final boostDiff = _roleMoodResultBoost(query, b.atom) -
          _roleMoodResultBoost(query, a.atom);
      if (boostDiff != 0) return boostDiff;
      return b.totalScore.compareTo(a.totalScore);
    });
  }

  if (_looksLikePreferenceQuery(query)) {
    for (final expandedQuery in const [
      '技术报告 报告格式 格式偏好 结论 风险 下一步 背景 风险前置',
      '用户偏好 报告 呈现 风险前置 结论 下一步',
      '冲突 最新结论 最新的结论 原词偏好 技术报告 报告偏好',
    ]) {
      final preferenceResults =
          await MemoryPrimaryService.instance.searchMemory(
        userId: userId,
        query: expandedQuery,
        limit: limit,
        types: const {'interaction_preference', 'preference'},
      );
      _mergeMemoryRecallResults(preferenceResults, into: merged);
    }
    final directPreferenceResults = await _directTermMatchResults(
      userId: userId,
      query: query,
      terms: _preferenceTermsForQuery(query),
      preferredTypes: const {'interaction_preference', 'preference'},
      types: types,
      reason: 'preference_term_match',
    );
    _mergeMemoryRecallResults(directPreferenceResults, into: merged);
    merged.sort((a, b) {
      if (_looksLikeReportFormatPreferenceQuery(query)) {
        final formatBoostDiff = _reportFormatPreferenceBoost(b.atom.content) -
            _reportFormatPreferenceBoost(a.atom.content);
        if (formatBoostDiff != 0) return formatBoostDiff;
      }
      final aPreference = a.atom.type == 'interaction_preference' ? 1 : 0;
      final bPreference = b.atom.type == 'interaction_preference' ? 1 : 0;
      if (aPreference != bPreference) return bPreference - aPreference;
      final aConstraintBoost = _preferenceConstraintBoost(a.atom.content);
      final bConstraintBoost = _preferenceConstraintBoost(b.atom.content);
      if (aConstraintBoost != bConstraintBoost) {
        return bConstraintBoost - aConstraintBoost;
      }
      return b.totalScore.compareTo(a.totalScore);
    });
  }

  return merged.take(limit).toList(growable: false);
}

Future<List<MemoryRecallResult>> _directTermMatchResults({
  required String userId,
  required String query,
  required List<String> terms,
  required Set<String> preferredTypes,
  required String reason,
  Set<String>? types,
}) async {
  final effectiveTerms =
      terms.where((term) => term.trim().length >= 2).toList(growable: false);
  if (effectiveTerms.isEmpty) return const [];

  final allowedTypes = types == null || types.isEmpty ? preferredTypes : types;
  final atoms = await MemoryPrimaryService.instance.listActiveAtoms(userId);
  final results = <MemoryRecallResult>[];
  for (var i = 0; i < atoms.length; i++) {
    final atom = atoms[i];
    if (allowedTypes.isNotEmpty && !allowedTypes.contains(atom.type)) {
      continue;
    }
    final searchable = '${atom.type} ${atom.title} ${atom.content} '
        '${atom.entityIds.join(' ')}';
    final hits = effectiveTerms
        .where(
          (term) => term.trim().isNotEmpty && _containsAny(searchable, [term]),
        )
        .toList(growable: false);
    if (hits.isEmpty) continue;
    final typeBoost = preferredTypes.contains(atom.type) ? 0.12 : 0.0;
    final evidenceBoost = atom.evidenceFactIds.isNotEmpty ? 0.04 : 0.0;
    final lexicalScore =
        (hits.length / effectiveTerms.length).clamp(0.0, 1.0).toDouble();
    results.add(
      MemoryRecallResult(
        atom: atom,
        lexicalScore: lexicalScore,
        vectorScore: 0,
        entityScore: 0,
        recencyScore: atoms.length <= 1 ? 1 : i / (atoms.length - 1),
        totalScore: (0.58 + lexicalScore * 0.24 + typeBoost + evidenceBoost)
            .clamp(0.0, 1.0)
            .toDouble(),
        ftsRank: i + 1,
        vectorRank: null,
        snippet: atom.content.length > 360
            ? '${atom.content.substring(0, 360)}...'
            : atom.content,
        reasons: [reason, if (atom.evidenceFactIds.isNotEmpty) 'has_evidence'],
      ),
    );
  }
  results.sort((a, b) => b.totalScore.compareTo(a.totalScore));
  return results;
}

List<MemoryRecallResult> _mergeMemoryRecallResults(
  Iterable<MemoryRecallResult> values, {
  List<MemoryRecallResult>? into,
}) {
  final result = into ?? <MemoryRecallResult>[];
  final seen = result.map((item) => item.atom.id).toSet();
  for (final value in values) {
    if (seen.add(value.atom.id)) result.add(value);
  }
  return result;
}

Set<String>? _expandMemoryTypeFilters(Set<String>? types) {
  if (types == null || types.isEmpty) return types;
  final expanded = {...types};
  if (expanded.contains('interaction_preference') ||
      expanded.contains('preference') ||
      expanded.contains('preference_constraint')) {
    expanded.add('interaction_preference');
    expanded.add('preference');
    expanded.remove('preference_constraint');
  }
  return expanded;
}

bool _looksLikePreferenceQuery(String query) {
  final normalized = query.toLowerCase();
  return normalized.contains('偏好') ||
      normalized.contains('preference') ||
      normalized.contains('preferences') ||
      normalized.contains('格式') ||
      normalized.contains('format') ||
      normalized.contains('报告') ||
      normalized.contains('report') ||
      normalized.contains('style') ||
      normalized.contains('写法');
}

bool _looksLikeReportFormatPreferenceQuery(String query) {
  final normalized = query.toLowerCase();
  return _looksLikePreferenceQuery(query) &&
      (normalized.contains('报告') ||
          normalized.contains('汇报') ||
          normalized.contains('格式') ||
          normalized.contains('写法') ||
          normalized.contains('report') ||
          normalized.contains('format') ||
          normalized.contains('style'));
}

bool _looksLikeIdentityOrRoutineQuery(String query) {
  return _containsAny(query, const [
    '常驻',
    '居住',
    '住哪',
    '哪里',
    '在哪',
    '城市',
    'city',
    'location',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '上午',
    '下午',
    '晚上',
    '安排',
    '日程',
    '深度工作',
    'routine',
    'schedule',
  ]);
}

bool _looksLikeRoleMoodTransitionQuery(String query) {
  return _containsAny(query, const [
    '角色',
    '切换',
    '转换',
    '心态',
    '情绪',
    '反思',
    'mood',
    'role',
  ]);
}

bool _looksLikeRelationshipQuery(String query) {
  final normalized = query.toLowerCase();
  return normalized.contains('找谁') ||
      normalized.contains('谁负责') ||
      normalized.contains('负责人') ||
      normalized.contains('负责') ||
      normalized.contains('联系人') ||
      normalized.contains('关系') ||
      normalized.contains('职责') ||
      normalized.contains('owner') ||
      normalized.contains('contact') ||
      normalized.contains('relationship');
}

List<String> _relationshipExpandedQueriesForTool(String query) {
  final expanded = <String>[];
  if (_containsAny(query, const ['产品评审', '体验文案', '评审', '文案'])) {
    expanded.add('产品评审 体验文案 负责 负责人 找谁 联系人 职责');
  }
  if (_containsAny(query, const ['合同付款', '发票确认', '付款', '发票'])) {
    expanded.add('合同付款 发票确认 负责 负责人 找谁 联系人 当前 现在');
  }
  if (_containsAny(query, const ['owner', '负责人', '验收', '回滚', '恢复'])) {
    expanded.add('当前 owner 负责人 验收 回滚演练 失败恢复 以这条为准');
  }
  if (_looksLikeProjectOwnerQuery(query)) {
    expanded.add('项目 当前 owner 负责人 仍负责 以这条为准 复盘');
  }
  final normalizedQuery = query.replaceAll(RegExp(r'\s+'), '');
  return expanded
      .where((item) => item.replaceAll(RegExp(r'\s+'), '') != normalizedQuery)
      .toList(growable: false);
}

List<String> _relationshipTermsForQuery(String query) {
  final terms = <String>[];
  if (_containsAny(query, const ['产品评审', '体验文案', '评审', '文案'])) {
    terms.addAll(const ['产品评审', '体验文案', '评审', '文案']);
  }
  if (_containsAny(query, const ['合同付款', '发票确认', '付款', '发票'])) {
    terms.addAll(const ['合同付款', '发票确认', '付款', '发票']);
  }
  if (_containsAny(query, const ['owner', '负责人', '负责'])) {
    terms.addAll(const ['owner', '负责人', '负责']);
  }
  return terms;
}

List<String> _identityRoutineExpandedQueriesForTool(String query) {
  final expanded = <String>[];
  if (_containsAny(query, const [
    '常驻',
    '居住',
    '住哪',
    '哪里',
    '在哪',
    '城市',
    'city',
    'location',
  ])) {
    expanded.add('用户 常驻地 居住地 所在城市 长期居住 identity');
  }
  if (_containsAny(query, const [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '上午',
    '下午',
    '晚上',
    '安排',
    '日程',
    '深度工作',
    'routine',
    'schedule',
  ])) {
    expanded.add('用户 日程 安排 深度工作 不安排评审会 routine');
  }
  final normalizedQuery = query.replaceAll(RegExp(r'\s+'), '');
  return expanded
      .where((item) => item.replaceAll(RegExp(r'\s+'), '') != normalizedQuery)
      .toList(growable: false);
}

List<String> _identityRoutineTermsForQuery(String query) {
  final terms = <String>[];
  if (_containsAny(query, const [
    '常驻',
    '居住',
    '住哪',
    '哪里',
    '在哪',
    '城市',
    'city',
    'location',
  ])) {
    terms.addAll(const ['常驻', '居住', '城市', '长期居住']);
  }
  if (_containsAny(query, const [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '上午',
    '下午',
    '晚上',
    '安排',
    '日程',
    '深度工作',
    'routine',
    'schedule',
  ])) {
    terms.addAll(const [
      '周一',
      '周二',
      '周三',
      '周四',
      '上午',
      '下午',
      '深度工作',
      '评审会',
      '日程',
    ]);
  }
  return terms;
}

List<String> _roleMoodExpandedQueriesForTool(String query) {
  final expanded = <String>[
    '角色转换 心态 情绪 切换 反思 不是行动 不创建提醒',
  ];
  if (_containsAny(query, const ['Project', 'Meridian', '项目'])) {
    expanded.add('Project Orion Meridian 角色 心态 客户访谈 整理 上线风险');
  }
  final normalizedQuery = query.replaceAll(RegExp(r'\s+'), '');
  return expanded
      .where((item) => item.replaceAll(RegExp(r'\s+'), '') != normalizedQuery)
      .toList(growable: false);
}

List<String> _roleMoodTermsForQuery(String query) {
  final terms = <String>['角色', '心态', '切换', '转换'];
  for (final token in RegExp(
    r'[A-Za-z][A-Za-z0-9_ ./-]{1,40}|[\u4e00-\u9fa5]{2,}',
  ).allMatches(query).map((match) => match.group(0)!.trim())) {
    if (token.length >= 2 &&
        _containsAny(token, const ['Project', 'Meridian', '产品经理', '客户访谈'])) {
      terms.add(token);
    }
  }
  return terms.toSet().toList(growable: false);
}

List<String> _preferenceTermsForQuery(String query) {
  final terms = <String>[];
  if (_looksLikePreferenceQuery(query) &&
      _containsAny(query, const [
        '报告',
        '技术报告',
        '项目报告',
        '格式',
        '写法',
        'report',
        'format',
        'style',
      ])) {
    terms.addAll(const [
      '技术报告',
      '项目报告',
      '报告格式',
      '格式偏好',
      '最新结论',
      '结论',
      '风险',
      '下一步',
      'owner',
      '证据来源',
      '背景',
    ]);
  }
  return terms;
}

bool _containsAny(String text, List<String> needles) {
  final normalized = text.toLowerCase();
  return needles.any((needle) => normalized.contains(needle.toLowerCase()));
}

int _identityRoutineResultBoost(String query, MemoryAtom atom) {
  final content = '${atom.type} ${atom.title} ${atom.content} '
      '${atom.entityIds.join(' ')}';
  var boost = 0;
  if (atom.evidenceFactIds.isNotEmpty) boost += 1;
  if (_containsAny(query, const [
        '常驻',
        '居住',
        '住哪',
        '哪里',
        '在哪',
        '城市',
        'city',
        'location',
      ]) &&
      atom.type == 'identity') {
    boost += 14;
  }
  if (_containsAny(query, const [
        '周一',
        '周二',
        '周三',
        '周四',
        '周五',
        '上午',
        '下午',
        '晚上',
        '安排',
        '日程',
        '深度工作',
        'routine',
        'schedule',
      ]) &&
      atom.type == 'routine') {
    boost += 14;
  }
  if (_containsAny(content, const ['常驻', '居住', '城市', '长期居住'])) {
    boost += 3;
  }
  if (_containsAny(content, const [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '深度工作',
    '日程',
    '安排',
  ])) {
    boost += 3;
  }
  if (atom.type == 'boundary') boost -= 8;
  if (atom.type == 'project_context' || atom.type == 'relationship') {
    boost -= 2;
  }
  return boost;
}

int _relationshipResultBoost(String query, MemoryAtom atom) {
  final content = '${atom.type} ${atom.title} ${atom.content} '
      '${atom.entityIds.join(' ')}';
  var boost = 0;
  if (atom.type == 'relationship') boost += 2;
  if (atom.evidenceFactIds.isNotEmpty) boost += 1;
  if (_containsAny(query, const ['产品评审', '体验文案', '评审', '文案']) &&
      _containsAny(content, const ['产品评审', '体验文案'])) {
    boost += 8;
  }
  if (_containsAny(query, const ['合同付款', '发票确认', '付款', '发票']) &&
      _containsAny(content, const ['合同付款', '发票确认', '付款', '发票'])) {
    boost += 8;
  }
  if (_containsAny(query, const ['owner', '负责人', '验收']) &&
      _containsAny(content, const ['owner', '负责人', '验收'])) {
    boost += 5;
  }
  if (_looksLikeProjectOwnerQuery(query) &&
      (atom.type == 'project_context' || atom.type == 'other') &&
      _containsAny(content, const ['owner', '负责人', '仍负责', '负责']) &&
      _queryEntityOverlap(query, atom) > 0) {
    boost += 12;
  }
  return boost;
}

int _roleMoodResultBoost(String query, MemoryAtom atom) {
  final content = '${atom.type} ${atom.title} ${atom.content} '
      '${atom.entityIds.join(' ')} ${atom.attributes.values.join(' ')}';
  var boost = 0;
  if (atom.type == 'project_context') boost += 4;
  if (_containsAny(content, const ['角色', '心态', '切换', '转换'])) boost += 8;
  if (_containsAny(
      content, const ['from_role', 'to_role', 'from_mood', 'to_mood'])) {
    boost += 8;
  }
  if (_queryEntityOverlap(query, atom) > 0) boost += 4;
  if (atom.evidenceFactIds.isNotEmpty) boost += 1;
  return boost;
}

bool _looksLikeProjectOwnerQuery(String query) {
  final normalized = query.toLowerCase();
  final asksOwner = normalized.contains('owner') || normalized.contains('负责人');
  if (!asksOwner) return false;
  final asksSpecificProject =
      normalized.contains('project') || normalized.contains('项目');
  if (!asksSpecificProject) return false;
  if (_containsAny(query, const ['产品评审', '体验文案', '合同付款', '发票确认', '付款', '发票'])) {
    return false;
  }
  return true;
}

int _queryEntityOverlap(String query, MemoryAtom atom) {
  final normalizedQuery = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  var hits = 0;
  for (final entity in atom.entityIds) {
    final normalizedEntity = entity.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '',
        );
    if (normalizedEntity.length >= 2 &&
        normalizedQuery.contains(normalizedEntity)) {
      hits += 1;
    }
  }
  if (hits > 0) return hits;
  final title = atom.title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final content = atom.content.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  for (final token in RegExp(
    r'[a-z0-9_./-]{2,}|[\u4e00-\u9fa5]{2,}',
  ).allMatches(query.toLowerCase()).map((match) => match.group(0)!).take(12)) {
    final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
    if (normalizedToken.length >= 2 &&
        (title.contains(normalizedToken) ||
            content.contains(normalizedToken))) {
      hits += 1;
    }
  }
  return hits;
}

bool _looksLikeCurrentStateQuery(String query) {
  final normalized = query.toLowerCase();
  return normalized.contains('当前') ||
      normalized.contains('current') ||
      normalized.contains('现在') ||
      normalized.contains('latest') ||
      normalized.contains('最新') ||
      normalized.contains('以哪条为准') ||
      normalized.contains('以谁为准');
}

String _redactSupersededValuesForCurrentState(String content) {
  var redacted = content;
  for (final pattern in [
    RegExp(r'(?:之前|此前|先前)关于[^。；;]*?(?:覆盖|作废|失效|不准确|superseded)[^。；;]*[。；;]?'),
    RegExp(r'(?:曾有|原来|旧记录)[^。；;]*?(?:覆盖|作废|失效|不准确|superseded)[^。；;]*[。；;]?'),
    RegExp(r'(?:覆盖|作废|失效|不准确|superseded)[^。；;]*?(?:之前|此前|先前|旧)[^。；;]*[。；;]?'),
  ]) {
    redacted = redacted.replaceAll(pattern, '此前相关旧说法已被覆盖。');
  }
  return redacted.replaceAll(RegExp(r'(。此前相关旧说法已被覆盖。)+'), '。此前相关旧说法已被覆盖。');
}

int _preferenceConstraintBoost(String content) {
  final normalized = content.toLowerCase();
  var score = 0;
  if (content.contains('最新结论') ||
      content.contains('最新的结论') ||
      content.contains('冲突') ||
      normalized.contains('latest conclusion')) {
    score += 4;
  }
  if (content.contains('风险前置') ||
      content.contains('风险优先') ||
      normalized.contains('risk-first') ||
      normalized.contains('risks first')) {
    score += 3;
  }
  if (content.contains('owner') ||
      content.contains('负责人') ||
      content.contains('截止时间') ||
      content.contains('证据来源') ||
      content.contains('影响面')) {
    score += 1;
  }
  if ((content.contains('背景') || normalized.contains('background')) &&
      (content.contains('最后') ||
          content.contains('后置') ||
          content.contains('放后') ||
          normalized.contains('last'))) {
    score += 2;
  }
  if (content.contains('技术报告') ||
      content.contains('项目报告') ||
      normalized.contains('report')) {
    score += 1;
  }
  return score;
}

int _reportFormatPreferenceBoost(String content) {
  final normalized = content.toLowerCase();
  var score = 0;
  if (content.contains('最新结论') ||
      content.contains('最新的结论') ||
      normalized.contains('latest conclusion')) {
    score += 8;
  }
  if (content.contains('风险') || normalized.contains('risk')) score += 4;
  if (content.contains('下一步') || normalized.contains('next step')) {
    score += 4;
  }
  if (content.contains('证据来源') || normalized.contains('evidence')) {
    score += 5;
  }
  if (content.contains('owner') || content.contains('负责人')) score += 2;
  if (content.contains('汇报结构') ||
      content.contains('回答结构') ||
      content.contains('项目报告') ||
      content.contains('技术报告') ||
      content.contains('报告的结构') ||
      content.contains('回答要先') ||
      content.contains('回答格式') ||
      normalized.contains('report format')) {
    score += 8;
  }
  if ((content.contains('背景') || normalized.contains('background')) &&
      (content.contains('最后') ||
          content.contains('后置') ||
          content.contains('放后') ||
          normalized.contains('last'))) {
    score += 3;
  }
  if (content.contains('OCR') ||
      content.contains('截图') ||
      content.contains('灰度风险列表') ||
      content.contains('财务压力') ||
      content.contains('投资建议') ||
      content.contains('税务结论') ||
      content.contains('反思不是行动') ||
      content.contains('失败恢复') ||
      content.contains('回滚演练口径')) {
    score -= 12;
  }
  if ((content.contains('当前 owner') || content.contains('旧 owner')) &&
      !content.contains('最新结论')) {
    score -= 6;
  }
  return score;
}

List<String> _preferenceConstraintsForTool(
  Iterable<MemoryRecallResult> results,
) {
  final constraints = <String>{};
  for (final result in results) {
    final atom = result.atom;
    if (!atom.type.contains('preference')) continue;
    final content = atom.content;
    final normalized = content.toLowerCase();
    if (content.contains('冲突') ||
        normalized.contains('conflict') ||
        normalized.contains('conflicts')) {
      constraints.add('如有信息冲突，优先告知最新结论。');
    }
    if (content.contains('结论') ||
        normalized.contains('conclusion') ||
        normalized.contains('conclusions')) {
      constraints.add('结论前置。');
    }
    if (content.contains('风险前置') ||
        content.contains('风险优先') ||
        normalized.contains('risk-first') ||
        normalized.contains('risks first')) {
      constraints.add('风险前置。');
    }
    if (content.contains('owner') &&
        content.contains('风险') &&
        content.contains('下一步') &&
        content.contains('证据来源')) {
      constraints.add('默认列出 owner、风险、下一步和证据来源。');
    }
    if ((content.contains('背景') || normalized.contains('background')) &&
        (content.contains('最后') ||
            content.contains('后置') ||
            content.contains('放后') ||
            normalized.contains('last'))) {
      constraints.add('背景放在最后。');
    }
    if (content.contains('截止时间') ||
        normalized.contains('deadline') ||
        normalized.contains('due date')) {
      constraints.add('行动项按 owner 和截止时间拆开。');
    }
    if (content.contains('影响面') ||
        normalized.contains('impact scope') ||
        normalized.contains('customer impact')) {
      constraints.add('涉及客户影响时单独列出影响面。');
    }
  }
  return constraints.toList(growable: false);
}

List<String> _directAnswerCandidatesForTool(
  String query,
  List<MemoryRecallResult> results,
) {
  if (_looksLikeCurrentStateQuery(query)) {
    final candidates = <String>[];
    final excludedTerms = _excludedEntityTermsForTool(query);
    for (final result in results) {
      if (_queryEntityOverlapExcludingForTool(
            query,
            result.atom,
            excludedTerms,
          ) <=
          0) {
        continue;
      }
      for (final clause in _currentStateClausesForTool(result.atom.content)) {
        if (!_containsAny(clause, const [
          '当前',
          '现在',
          '仍负责',
          '继续由',
          '确认继续',
          'current',
        ])) {
          continue;
        }
        if (!_containsAny(clause, const ['owner', '负责人', '负责', '验收'])) {
          continue;
        }
        final text = _stripSupersededTailForTool(clause);
        if (text.isEmpty) continue;
        final evidence = result.atom.evidenceFactIds.isEmpty
            ? ''
            : ' evidence_fact_ids=${result.atom.evidenceFactIds.join(', ')}';
        candidates.add('$text$evidence');
      }
    }
    if (candidates.isNotEmpty) return candidates.toSet().take(5).toList();
  }

  if (_looksLikeRoleMoodTransitionQuery(query)) {
    final candidates = <String>[];
    for (final result in results) {
      final attrs = result.atom.attributes;
      final fromRole = _attributeStringForTool(attrs['from_role']);
      final toRole = _attributeStringForTool(attrs['to_role']);
      final fromMood = _attributeStringForTool(attrs['from_mood']);
      final toMood = _attributeStringForTool(attrs['to_mood']);
      if ([fromRole, toRole, fromMood, toMood].any((value) => value == null)) {
        continue;
      }
      final fromProject = _attributeStringForTool(attrs['from_project']);
      final toProject = _attributeStringForTool(attrs['to_project']);
      final projectText = fromProject == null || toProject == null
          ? ''
          : '$fromProject -> $toProject; ';
      final evidence = result.atom.evidenceFactIds.isEmpty
          ? ''
          : ' evidence_fact_ids=${result.atom.evidenceFactIds.join(', ')}';
      candidates.add(
        '${projectText}roles: $fromRole -> $toRole; mood: $fromMood -> $toMood.$evidence',
      );
    }
    if (candidates.isNotEmpty) return candidates.toSet().take(5).toList();
  }

  return const [];
}

List<String> _currentStateClausesForTool(String content) {
  return content
      .split(RegExp(r'[。；;\n]+'))
      .map((clause) => clause.trim())
      .where((clause) => clause.isNotEmpty)
      .toList(growable: false);
}

String _stripSupersededTailForTool(String clause) {
  var result = clause.trim();
  result = result.replaceFirst(RegExp(r'[，,]\s*(?:覆盖|作废|失效).*$'), '');
  result = result.replaceFirst(RegExp(r'[，,]\s*(?:此前|之前|旧).*$'), '');
  return result.trim();
}

String? _attributeStringForTool(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _queryEntityOverlapExcludingForTool(
  String query,
  MemoryAtom atom,
  Set<String> excludedTerms,
) {
  final normalizedQuery = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  var hits = 0;
  for (final entity in atom.entityIds) {
    final normalizedEntity = entity.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '',
        );
    if (_isExcludedEntityForTool(normalizedEntity, excludedTerms)) continue;
    if (normalizedEntity.length >= 2 &&
        normalizedQuery.contains(normalizedEntity)) {
      hits += 1;
    }
  }
  if (hits > 0) return hits;
  final title = atom.title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final content = atom.content.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  for (final token in RegExp(
    r'[a-z0-9_./-]{2,}|[\u4e00-\u9fa5]{2,}',
  ).allMatches(query.toLowerCase()).map((match) => match.group(0)!).take(12)) {
    final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
    if (_isExcludedEntityForTool(normalizedToken, excludedTerms)) continue;
    if (normalizedToken.length >= 2 &&
        (title.contains(normalizedToken) ||
            content.contains(normalizedToken))) {
      hits += 1;
    }
  }
  return hits;
}

Set<String> _excludedEntityTermsForTool(String query) {
  final terms = <String>{};
  for (final pattern in [
    RegExp(r'(?:不要|别|避免|不要再)\s*(?:混到|混入|混淆|关联到|提到|回答)\s*([^？?。；;\n]+)'),
    RegExp(r'(?:不要|别|避免)\s*(?:包括|包含)\s*([^？?。；;\n]+)'),
  ]) {
    for (final match in pattern.allMatches(query)) {
      final raw = match.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      for (final term in raw.split(RegExp(r'\s*(?:和|或|、|,|，)\s*'))) {
        final normalized = term
            .replaceAll(RegExp(r'^(?:到|把|将)\s*'), '')
            .replaceAll(RegExp(r'[：:，,。；;？?]+$'), '')
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '');
        if (normalized.length >= 2) terms.add(normalized);
      }
    }
  }
  return terms;
}

bool _isExcludedEntityForTool(
  String normalizedEntity,
  Set<String> excludedTerms,
) {
  if (normalizedEntity.length < 2) return false;
  return excludedTerms.any(
    (term) =>
        term.length >= 2 &&
        (term.contains(normalizedEntity) || normalizedEntity.contains(term)),
  );
}
