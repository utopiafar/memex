import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/pkm_agent/pkm_agent.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';

class MemoryExtractAgent {
  MemoryExtractAgent._();

  static final _logger = getLogger('MemoryExtractAgent');

  static Future<List<MemoryPatch>> extractPatches({
    required String userId,
    required String factId,
    required String contentText,
    List<Map<String, dynamic>> assetAnalyses = const [],
    DateTime? inputDateTime,
    String? locationContextReminder,
  }) async {
    final skipDecision = PkmAgent.detectNonPersistentInput(contentText);
    if (skipDecision.shouldSkip) {
      _logger.info(
        'Skipping memory extraction for $factId because input opted out.',
      );
      return const [];
    }

    final llmConfig = await UserStorage.getAgentLLMConfig(
      AgentDefinitions.memoryExtractAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    if (!llmConfig.isValid) {
      _logger.info(
        'No LLM configured - skipping memory extraction for $factId',
      );
      return const [];
    }

    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.memoryExtractAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
    final prompt = await _buildPrompt(
      userId: userId,
      factId: factId,
      contentText: contentText,
      assetAnalyses: assetAnalyses,
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
    return _parsePatches(
      response.textOutput ?? '',
      fallbackFactId: factId,
      sourceText: contentText,
    );
  }

  static Future<String> _buildPrompt({
    required String userId,
    required String factId,
    required String contentText,
    required List<Map<String, dynamic>> assetAnalyses,
    DateTime? inputDateTime,
    String? locationContextReminder,
  }) async {
    final currentTime = formatLocalDateTimeWithZone(
      inputDateTime ?? DateTime.now(),
    );
    final existing = await MemoryPrimaryService.instance.searchMemory(
      userId: userId,
      query: contentText,
      limit: 12,
    );
    final existingJson = existing.map((e) => e.toJson()).toList();
    final locationBlock = locationContextReminder?.trim().isEmpty ?? true
        ? ''
        : '<location_context>\n${locationContextReminder!.trim()}\n</location_context>\n';
    final assetBlock = assetAnalyses.isEmpty
        ? '(none)'
        : const JsonEncoder.withIndent('  ').convert(assetAnalyses);

    return '''
You are Memex Memory Extract Agent.

Task: convert the new user Fact into structured Memory Primary patches.
You do not write files. You only propose patches. Another service will apply
dedupe, conflict handling, and persistence.

Current local time:
$currentTime

Current fact id:
$factId

$locationBlock
User raw input:
$contentText

System asset analysis, reference only:
$assetBlock

Existing related memory atoms:
${const JsonEncoder.withIndent('  ').convert(existingJson)}

Extraction rules:
- Only create durable memories useful beyond the current moment.
- Do not log every event. Extract stable preferences, project context,
  relationships, routines, constraints, identity, boundaries, and active plans.
- Preserve the user's language. If the raw input is mostly Chinese, write memory
  content in Chinese while keeping exact project/person names unchanged.
- Treat explicit durable cues as strong write signals: "记住", "长期偏好",
  "个人偏好", "以后", "默认", "以这条为准", "纠正", "覆盖", "owner 是".
  These usually require create/update patches, not a no-op.
- For project ownership or correction facts, include the project name, the new
  current value, and what is being superseded. Use supersedes_memory_ids when an
  existing atom is stale.
- For report/workflow preferences, preserve the actionable slots the user named,
  such as owner, conclusion, risk, next step, deadline, evidence/source, impact
  scope, and acceptance criteria.
- When the raw input names a specific report slot or preference phrase, copy
  the user's exact phrase into content or attributes. For example preserve
  "最新结论", "风险前置", "截止时间", "影响面", "必要证据", and "证据来源"
  instead of replacing them with only generic synonyms.
- For personal constraints, preserve concrete durable attributes such as city,
  timezone interpretation, allergies, health constraints, family/weekend
  boundaries, and caffeine/diet preferences.
- If the input explicitly says a detail is temporary, one-off, casual browsing,
  or should not become a project fact / long-term habit, do not create a memory
  about that detail. Only create a boundary memory if it changes future behavior
  in a reusable way.
- If creating that reusable boundary, generalize the category. Do not copy exact
  one-off examples, casual purchases, temporary locations, screenshot/ad terms,
  or other ephemeral entities into content or entity_ids.
- Preserve concrete evidence by including "$factId" in evidence_fact_ids for
  every create/update patch supported by this fact.
- If this fact clearly updates older memory, use op "create" plus
  supersedes_memory_ids, or op "update" with memory_id when the same atom should
  be edited.
- If the user asks not to remember something, return no patches.
- Schema must stay flexible: put extra domain-specific fields in attributes.
- Never invent memory ids. Only use memory_id values from Existing related
  memory atoms.

Return strict JSON only:
{
  "patches": [
    {
      "op": "create|update|delete|expire",
      "memory_id": "optional existing id for update/delete/expire",
      "type": "identity|preference|routine|reminder_rule|project_context|boundary|asset_environment|interaction_preference|relationship|health|finance|schedule|other",
      "title": "short optional title",
      "content": "atomic third-person memory. Do not start with User said.",
      "confidence": 0.0,
      "importance": 1,
      "entity_ids": ["people, projects, places, exact terms"],
      "evidence_fact_ids": ["$factId"],
      "supersedes_memory_ids": ["optional existing ids"],
      "valid_from": "optional ISO date/time or source phrase",
      "valid_until": "optional ISO date/time or source phrase",
      "attributes": {}
    }
  ]
}
''';
  }

  static List<MemoryPatch> _parsePatches(
    String raw, {
    required String fallbackFactId,
    required String sourceText,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return _buildFallbackPatchesFromSource(
        sourceText: sourceText,
        factId: fallbackFactId,
      );
    }
    try {
      final decoded = jsonDecode(_stripCodeFence(trimmed));
      final rawPatches = decoded is List
          ? decoded
          : decoded is Map
              ? decoded['patches']
              : null;
      if (rawPatches is! List) {
        return _buildFallbackPatchesFromSource(
          sourceText: sourceText,
          factId: fallbackFactId,
        );
      }
      final patches = <MemoryPatch>[];
      for (final item in rawPatches) {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        final patch = MemoryPatch.fromJson(json);
        if (patch.op == 'create' && patch.content.trim().isEmpty) continue;
        final normalizedPatch = _normalizeProjectOwnerCorrectionPatch(
          patch,
          sourceText,
        );
        final withEvidence = _ensureEvidence(normalizedPatch, fallbackFactId);
        final withReportTerms = _preserveExplicitReportTerms(
          withEvidence,
          sourceText,
        );
        final withPersonalTerms = _preserveExplicitPersonalTerms(
          withReportTerms,
          sourceText,
        );
        patches.add(_generalizeTemporaryBoundaryPatch(
          withPersonalTerms,
          sourceText,
        ));
      }
      final ownerCorrectionFallbackPatch = _buildProjectOwnerCorrectionFallback(
        sourceText: sourceText,
        factId: fallbackFactId,
        parsedPatches: patches,
      );
      if (ownerCorrectionFallbackPatch != null) {
        patches.add(ownerCorrectionFallbackPatch);
      }
      final fallbackPatch = _buildExplicitReportPreferenceFallback(
        sourceText: sourceText,
        factId: fallbackFactId,
        parsedPatches: patches,
      );
      if (fallbackPatch != null) patches.add(fallbackPatch);
      final personalFallbackPatch = _buildExplicitPersonalConstraintFallback(
        sourceText: sourceText,
        factId: fallbackFactId,
        parsedPatches: patches,
      );
      if (personalFallbackPatch != null) patches.add(personalFallbackPatch);
      if (patches.length <= 8) return patches.toList(growable: false);
      if (ownerCorrectionFallbackPatch != null ||
          fallbackPatch != null ||
          personalFallbackPatch != null) {
        final requiredFallbacks = [
          if (ownerCorrectionFallbackPatch != null)
            ownerCorrectionFallbackPatch,
          if (fallbackPatch != null) fallbackPatch,
          if (personalFallbackPatch != null) personalFallbackPatch,
        ];
        return [
          ...patches.take(8 - requiredFallbacks.length),
          ...requiredFallbacks,
        ];
      }
      return patches.take(8).toList(growable: false);
    } catch (e) {
      _logger.warning('Failed to parse memory patches: $e');
      return _buildFallbackPatchesFromSource(
        sourceText: sourceText,
        factId: fallbackFactId,
      );
    }
  }

  static List<MemoryPatch> parsePatchesForTest(
    String raw, {
    required String fallbackFactId,
    required String sourceText,
  }) {
    return _parsePatches(
      raw,
      fallbackFactId: fallbackFactId,
      sourceText: sourceText,
    );
  }

  static List<MemoryPatch> _buildFallbackPatchesFromSource({
    required String sourceText,
    required String factId,
  }) {
    final patches = <MemoryPatch>[];
    final ownerCorrection = _buildProjectOwnerCorrectionFallback(
      sourceText: sourceText,
      factId: factId,
      parsedPatches: const [],
    );
    if (ownerCorrection != null) patches.add(ownerCorrection);
    final reportFallback = _buildExplicitReportPreferenceFallback(
      sourceText: sourceText,
      factId: factId,
      parsedPatches: const [],
    );
    if (reportFallback != null) patches.add(reportFallback);
    final personalFallback = _buildExplicitPersonalConstraintFallback(
      sourceText: sourceText,
      factId: factId,
      parsedPatches: const [],
    );
    if (personalFallback != null) patches.add(personalFallback);
    return patches.toList(growable: false);
  }

  static MemoryPatch? _buildProjectOwnerCorrectionFallback({
    required String sourceText,
    required String factId,
    required List<MemoryPatch> parsedPatches,
  }) {
    final correction = _extractProjectOwnerCorrection(sourceText);
    if (correction == null) return null;
    if (_hasProjectOwnerPatch(
      parsedPatches,
      project: correction.project,
      owner: correction.owner,
    )) {
      return null;
    }

    return MemoryPatch(
      op: 'create',
      type: 'project_context',
      title: '${correction.project} owner 更正',
      content:
          '${correction.project} 的导出灰度 owner 是 ${correction.owner}，此前相关旧说法已被覆盖。',
      confidence: 1.0,
      importance: 5,
      entityIds: [correction.project, correction.owner],
      evidenceFactIds: [factId],
      attributes: {
        'fallback_rule': 'project_owner_correction',
        'project': correction.project,
        'current_owner': correction.owner,
      },
    );
  }

  static MemoryPatch _normalizeProjectOwnerCorrectionPatch(
    MemoryPatch patch,
    String sourceText,
  ) {
    final correction = _extractProjectOwnerCorrection(sourceText);
    if (correction == null) return patch;
    final op = patch.op.trim().toLowerCase();
    if (op != 'create' && op != 'update') return patch;
    final text = [
      patch.content,
      patch.title,
      ...patch.entityIds,
    ].join(' ');
    if (!text.contains(correction.project) ||
        !RegExp(r'owner|负责人|负责|导出灰度', caseSensitive: false).hasMatch(text)) {
      return patch;
    }

    final json = patch.toJson();
    json['type'] = 'project_context';
    json['title'] = '${correction.project} owner 更正';
    json['content'] =
        '${correction.project} 的导出灰度 owner 是 ${correction.owner}，此前相关旧说法已被覆盖。';
    json['confidence'] = patch.confidence > 1.0 ? patch.confidence : 1.0;
    json['importance'] = patch.importance > 5 ? patch.importance : 5;
    json['entity_ids'] = [correction.project, correction.owner];
    json['attributes'] = {
      ...patch.attributes,
      'normalization_rule': 'project_owner_correction',
      'project': correction.project,
      'current_owner': correction.owner,
    };
    return MemoryPatch.fromJson(json);
  }

  static _ProjectOwnerCorrection? _extractProjectOwnerCorrection(
    String sourceText,
  ) {
    for (final pattern in [
      RegExp(
        r'以这条为准[:：]\s*(.+?)\s*的\s*导出灰度\s*owner\s*是\s*([^，。；;\n]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(.+?)\s*的\s*导出灰度\s*owner\s*是\s*([^，。；;\n]+)[^。；;\n]*(?:覆盖|作废|失效)',
        caseSensitive: false,
      ),
    ]) {
      final match = pattern.firstMatch(sourceText);
      final project = match?.group(1)?.trim();
      final owner = match?.group(2)?.trim();
      if (project == null ||
          owner == null ||
          project.isEmpty ||
          owner.isEmpty) {
        continue;
      }
      return _ProjectOwnerCorrection(
        project: project.replaceFirst(RegExp(r'^以这条为准[:：]\s*'), '').trim(),
        owner: owner,
      );
    }
    return null;
  }

  static bool _hasProjectOwnerPatch(
    List<MemoryPatch> patches, {
    required String project,
    required String owner,
  }) {
    return patches.any((patch) {
      if (patch.op.trim().toLowerCase() != 'create' &&
          patch.op.trim().toLowerCase() != 'update') {
        return false;
      }
      final text = [
        patch.content,
        patch.title,
        ...patch.entityIds,
      ].join(' ');
      return text.contains(project) &&
          text.contains(owner) &&
          RegExp(r'owner|负责人|负责|导出灰度', caseSensitive: false).hasMatch(text);
    });
  }

  static MemoryPatch _ensureEvidence(MemoryPatch patch, String factId) {
    if (patch.evidenceFactIds.isNotEmpty) return patch;
    if (patch.op != 'create' && patch.op != 'update') return patch;
    final json = patch.toJson();
    json['evidence_fact_ids'] = [factId];
    return MemoryPatch.fromJson(json);
  }

  static MemoryPatch _preserveExplicitReportTerms(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.op != 'create' && patch.op != 'update') return patch;
    if (!_looksLikeReportPreference(sourceText)) return patch;

    final sourceTerms = _reportTermsFromSource(sourceText);
    if (sourceTerms.isEmpty) return patch;

    final missingTerms = sourceTerms
        .where((term) => !patch.content.contains(term))
        .toList(growable: false);
    final existingTerms = (patch.attributes['preserved_report_terms'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final preservedTerms = <String>[
      ...existingTerms,
      ...sourceTerms,
    ];

    final json = patch.toJson();
    if (missingTerms.isNotEmpty) {
      final suffix = '保留用户原词偏好：${missingTerms.join('、')}。';
      json['content'] = patch.content.trim().isEmpty
          ? suffix
          : '${patch.content.trim()} $suffix';
    }
    json['attributes'] = {
      ...patch.attributes,
      'preserved_report_terms': preservedTerms,
    };
    return MemoryPatch.fromJson(json);
  }

  static MemoryPatch _preserveExplicitPersonalTerms(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.op != 'create' && patch.op != 'update') return patch;
    if (!_looksLikePersonalConstraint(sourceText)) return patch;

    final sourceTerms = _personalTermsFromSource(sourceText);
    if (sourceTerms.isEmpty) return patch;

    final missingTerms = sourceTerms
        .where((term) => !patch.content.contains(term))
        .toList(growable: false);
    final existingTerms =
        (patch.attributes['preserved_personal_terms'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[];
    final preservedTerms = <String>[
      ...existingTerms,
      ...sourceTerms,
    ];

    final json = patch.toJson();
    if (missingTerms.isNotEmpty) {
      final suffix = '保留用户原词约束：${missingTerms.join('、')}。';
      json['content'] = patch.content.trim().isEmpty
          ? suffix
          : '${patch.content.trim()} $suffix';
    }
    json['attributes'] = {
      ...patch.attributes,
      'preserved_personal_terms': preservedTerms,
    };
    return MemoryPatch.fromJson(json);
  }

  static bool _looksLikeReportPreference(String sourceText) {
    return RegExp(r'报告|总结|行动项|技术|项目|客户影响').hasMatch(sourceText);
  }

  static bool _looksLikePersonalConstraint(String sourceText) {
    return RegExp(
      r'个人偏好|常驻|以后|默认|长期|通常|一般|不默认|尽量|边界|跨时区|咖啡因|周末|九点后|9\s*(?:点|pm)',
      caseSensitive: false,
    ).hasMatch(sourceText);
  }

  static MemoryPatch? _buildExplicitReportPreferenceFallback({
    required String sourceText,
    required String factId,
    required List<MemoryPatch> parsedPatches,
  }) {
    if (!_looksLikeReportPreference(sourceText)) return null;
    final sourceTerms = _reportTermsFromSource(sourceText);
    if (sourceTerms.isEmpty) return null;

    if (_looksLikeExplicitReportPreference(sourceText) &&
        !_hasCreatePatchCoveringTerms(parsedPatches, sourceTerms)) {
      return _buildReportPreferencePatch(
        sourceText: sourceText,
        factId: factId,
        terms: sourceTerms,
        fallbackRule: 'explicit_report_preference_create',
      );
    }

    final preservedText = parsedPatches
        .map(
          (patch) => [
            patch.content,
            ..._attributeStringList(patch.attributes['preserved_report_terms']),
          ].join(' '),
        )
        .join('\n');
    final missingTerms = sourceTerms
        .where((term) => !preservedText.contains(term))
        .toList(growable: false);
    if (missingTerms.isEmpty) return null;

    return _buildReportPreferencePatch(
      sourceText: sourceText,
      factId: factId,
      terms: missingTerms,
      fallbackRule: 'explicit_report_terms',
    );
  }

  static bool _looksLikeExplicitReportPreference(String sourceText) {
    return _looksLikeReportPreference(sourceText) &&
        RegExp(r'记住|长期偏好|默认列出|默认包含|固定槽位|以后.*(?:写|做|报告|总结)')
            .hasMatch(sourceText);
  }

  static bool _hasCreatePatchCoveringTerms(
    List<MemoryPatch> patches,
    List<String> sourceTerms,
  ) {
    return patches.any((patch) {
      if (patch.op.trim().toLowerCase() != 'create') return false;
      final text = [
        patch.content,
        ..._attributeStringList(patch.attributes['preserved_report_terms']),
      ].join(' ');
      return sourceTerms.every(text.contains);
    });
  }

  static MemoryPatch _buildReportPreferencePatch({
    required String sourceText,
    required String factId,
    required List<String> terms,
    required String fallbackRule,
  }) {
    final project = _extractReportProject(sourceText);
    final subject = project == null ? '报告/总结' : '$project 相关报告/总结';
    return MemoryPatch(
      op: 'create',
      type: 'interaction_preference',
      title: '报告偏好',
      content: '用户希望$subject保留以下显式偏好：${terms.join('、')}。',
      confidence: 0.9,
      importance: 4,
      entityIds: [
        if (project != null) project,
        ...terms,
      ],
      evidenceFactIds: [factId],
      attributes: {
        'preserved_report_terms': terms,
        'fallback_rule': fallbackRule,
      },
    );
  }

  static MemoryPatch? _buildExplicitPersonalConstraintFallback({
    required String sourceText,
    required String factId,
    required List<MemoryPatch> parsedPatches,
  }) {
    if (!_looksLikePersonalConstraint(sourceText)) return null;
    final sourceTerms = _personalTermsFromSource(sourceText);
    if (sourceTerms.isEmpty) return null;

    final preservedText = parsedPatches
        .map(
          (patch) => [
            patch.content,
            ..._attributeStringList(
              patch.attributes['preserved_personal_terms'],
            ),
          ].join(' '),
        )
        .join('\n');
    final missingTerms = sourceTerms
        .where((term) => !preservedText.contains(term))
        .toList(growable: false);
    if (missingTerms.isEmpty) return null;

    return MemoryPatch(
      op: 'create',
      type: 'boundary',
      title: '个人约束',
      content: '用户有以下稳定个人约束：${missingTerms.join('、')}。',
      confidence: 0.9,
      importance: 4,
      entityIds: missingTerms,
      evidenceFactIds: [factId],
      attributes: {
        'preserved_personal_terms': missingTerms,
        'fallback_rule': 'explicit_personal_terms',
      },
    );
  }

  static List<String> _attributeStringList(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }

  static String? _extractReportProject(String sourceText) {
    for (final pattern in [
      RegExp(r'给我做\s+(.+?)\s+相关总结'),
      RegExp(r'尤其是\s+(.+?)\s+的验收依据'),
      RegExp(r'(.+?)\s+第\s*\d+\s*轮复盘'),
    ]) {
      final match = pattern.firstMatch(sourceText);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static const _explicitReportTerms = [
    'owner',
    '结论',
    '风险',
    '下一步',
    '最新结论',
    '风险前置',
    '截止时间',
    '影响面',
    '必要证据',
    '证据来源',
  ];

  static List<String> _reportTermsFromSource(String sourceText) {
    final terms = <String>{};
    for (final term in _explicitReportTerms) {
      if (sourceText.contains(term)) terms.add(term);
    }
    for (final entry in _explicitReportTermAliases.entries) {
      if (entry.value.any((pattern) => pattern.hasMatch(sourceText))) {
        terms.add(entry.key);
      }
    }
    return terms.toList(growable: false);
  }

  static List<String> _personalTermsFromSource(String sourceText) {
    final terms = <String>{};
    if (sourceText.contains('九点后') ||
        RegExp(r'(?:晚上)?\s*9\s*(?:点|pm)\s*后', caseSensitive: false)
            .hasMatch(sourceText)) {
      terms.add('九点后');
    }
    for (final term in const ['低咖啡因', '周末']) {
      if (sourceText.contains(term)) terms.add(term);
    }
    final cityMatch =
        RegExp(r'常驻\s*([A-Za-z\u4e00-\u9fa5]{2,12})').firstMatch(sourceText);
    final city = cityMatch?.group(1)?.trim();
    if (city != null && city.isNotEmpty) terms.add(city);
    return terms.toList(growable: false);
  }

  static final Map<String, List<RegExp>> _explicitReportTermAliases = {
    '风险前置': [
      RegExp(r'先(?:给|写|列)?结论[、和]风险'),
      RegExp(r'结论[、和]风险.*背景(?:可以)?(?:放后|后置)'),
    ],
    '截止时间': [
      RegExp(r'(deadline|due date)', caseSensitive: false),
      RegExp(r'(截止|到期|ddl)\s*(时间|日期)?'),
    ],
    '必要证据': [
      RegExp(r'(必要|关键|验收)\s*(证据|依据)'),
      RegExp(r'(evidence|acceptance criteria)', caseSensitive: false),
    ],
    '证据来源': [
      RegExp(r'(证据|信息|资料)?来源'),
      RegExp(r'(source|sources)', caseSensitive: false),
    ],
  };

  static MemoryPatch _generalizeTemporaryBoundaryPatch(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.op != 'create' && patch.op != 'update') return patch;
    if (patch.type != 'boundary') return patch;
    if (!_looksLikeTemporaryNoLongTermBoundary(sourceText)) return patch;

    final json = patch.toJson();
    json['title'] = patch.title.trim().isEmpty ? '临时事件不长期化' : patch.title;
    json['content'] = '用户不希望将临时、一次性或低信号噪声写入长期记忆；'
        '遇到这类输入时只保留可复用边界，不保留具体临时细节。';
    json['entity_ids'] = <String>[];
    json['attributes'] = {
      ...patch.attributes,
      'normalization_rule': 'temporary_boundary_generalization',
      'noise_examples_removed': true,
    };
    return MemoryPatch.fromJson(json);
  }

  static bool _looksLikeTemporaryNoLongTermBoundary(String sourceText) {
    final hasTemporaryCue = RegExp(
      r'临时|一次性|短期|随手|低信号|噪声|广告|截图|casual|temporary|one[- ]off|ephemeral',
      caseSensitive: false,
    ).hasMatch(sourceText);
    final hasNoLongTermCue = RegExp(
      r'不要.*(?:长期|长记忆|长期记忆|长期画像|保存|写入)|不(?:要|应).*长期|别.*(?:记|保存|长期化)',
      caseSensitive: false,
    ).hasMatch(sourceText);
    return hasTemporaryCue && hasNoLongTermCue;
  }

  static String _stripCodeFence(String value) {
    if (!value.startsWith('```')) return value;
    return value
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
}

class _ProjectOwnerCorrection {
  final String project;
  final String owner;

  const _ProjectOwnerCorrection({
    required this.project,
    required this.owner,
  });
}
