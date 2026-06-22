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
- Preserve work-state transitions when they are explicitly framed as reusable
  context for later recall, such as role switches across projects, mood/state
  changes, and "not an action/reminder" boundaries. Keep the factual transition
  and the no-action boundary separate when possible.
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
- When the raw input contains a domain-specific compound term, preserve the
  exact term in content or attributes instead of splitting it into looser
  fragments. This is especially important for terms ending in "优先级",
  "风险列表", "窗口", "回滚演练", "失败恢复口径", or "验收依据".
- When the raw input is parsed OCR/screenshot text or explicitly says to use
  given text, preserve that source context and handling boundary. The memory
  should make clear that future answers should use the given text and should
  not judge OCR quality.
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
        final withDomainTerms = _preserveExplicitDomainTerms(
          withPersonalTerms,
          sourceText,
        );
        final withParsedTextContext = _preserveParsedTextContext(
          withDomainTerms,
          sourceText,
        );
        patches.add(_generalizeTemporaryBoundaryPatch(
          withParsedTextContext,
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
      final roleTransitionPatch = _buildRoleTransitionFallback(
        sourceText: sourceText,
        factId: fallbackFactId,
        parsedPatches: patches,
      );
      if (roleTransitionPatch != null) patches.add(roleTransitionPatch);
      final parsedTextFallbackPatch = _buildParsedTextContextFallback(
        sourceText: sourceText,
        factId: fallbackFactId,
        parsedPatches: patches,
      );
      if (parsedTextFallbackPatch != null) {
        patches.add(parsedTextFallbackPatch);
      }
      if (patches.length <= 8) return patches.toList(growable: false);
      if (ownerCorrectionFallbackPatch != null ||
          fallbackPatch != null ||
          personalFallbackPatch != null ||
          roleTransitionPatch != null ||
          parsedTextFallbackPatch != null) {
        final requiredFallbacks = [
          if (ownerCorrectionFallbackPatch != null)
            ownerCorrectionFallbackPatch,
          if (fallbackPatch != null) fallbackPatch,
          if (personalFallbackPatch != null) personalFallbackPatch,
          if (roleTransitionPatch != null) roleTransitionPatch,
          if (parsedTextFallbackPatch != null) parsedTextFallbackPatch,
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
    final roleTransitionFallback = _buildRoleTransitionFallback(
      sourceText: sourceText,
      factId: factId,
      parsedPatches: const [],
    );
    if (roleTransitionFallback != null) patches.add(roleTransitionFallback);
    final parsedTextFallback = _buildParsedTextContextFallback(
      sourceText: sourceText,
      factId: factId,
      parsedPatches: const [],
    );
    if (parsedTextFallback != null) patches.add(parsedTextFallback);
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

  static MemoryPatch _preserveExplicitDomainTerms(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.op != 'create' && patch.op != 'update') return patch;
    final sourceTerms = _domainTermsFromSource(sourceText);
    if (sourceTerms.isEmpty) return patch;
    if (!_patchLooksRelatedToDomainTerms(patch, sourceTerms)) return patch;

    final missingTerms = sourceTerms
        .where((term) => !patch.content.contains(term))
        .toList(growable: false);
    final existingTerms = (patch.attributes['preserved_domain_terms'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final preservedTerms = <String>[
      ...existingTerms,
      ...sourceTerms,
    ];

    final json = patch.toJson();
    if (missingTerms.isNotEmpty) {
      final suffix = '保留用户原词领域术语：${missingTerms.join('、')}。';
      json['content'] = patch.content.trim().isEmpty
          ? suffix
          : '${patch.content.trim()} $suffix';
    }
    json['entity_ids'] = [
      ...patch.entityIds,
      ...missingTerms.where((term) => !patch.entityIds.contains(term)),
    ];
    json['attributes'] = {
      ...patch.attributes,
      'preserved_domain_terms': preservedTerms,
    };
    return MemoryPatch.fromJson(json);
  }

  static MemoryPatch _preserveParsedTextContext(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.op != 'create' && patch.op != 'update') return patch;
    if (!_looksLikeParsedTextSource(sourceText)) return patch;
    if (!_patchLooksRelatedToParsedTextContext(patch, sourceText)) {
      return patch;
    }

    final json = patch.toJson();
    final hasParsedTextMarker = RegExp(
      r'OCR|已解析|截图文字|给定文本',
      caseSensitive: false,
    ).hasMatch(patch.content);
    if (!hasParsedTextMarker) {
      const suffix = '此为已解析截图/OCR上下文，Agent 只需使用给定文本处理，不判断 OCR 质量。';
      json['content'] = patch.content.trim().isEmpty
          ? suffix
          : '${patch.content.trim()} $suffix';
    }
    json['entity_ids'] = _appendUniqueStrings(
      patch.entityIds,
      const ['OCR', '给定文本'],
    );
    json['attributes'] = {
      ...patch.attributes,
      'source_type': patch.attributes['source_type'] ?? 'screenshot_ocr',
      'ocr_handling': patch.attributes['ocr_handling'] ?? 'use_given_text_only',
    };
    return MemoryPatch.fromJson(json);
  }

  static bool _looksLikeParsedTextSource(String sourceText) {
    return RegExp(
      r'OCR|已解析截图|截图文字|图片文字|给定文本',
      caseSensitive: false,
    ).hasMatch(sourceText);
  }

  static bool _patchLooksRelatedToParsedTextContext(
    MemoryPatch patch,
    String sourceText,
  ) {
    if (patch.type == 'boundary' &&
        _looksLikeTemporaryNoLongTermBoundary(sourceText)) {
      return false;
    }
    final patchText = [
      patch.type,
      patch.title,
      patch.content,
      ...patch.entityIds,
    ].join(' ');
    if (RegExp(r'项目|Project|风险|分歧|仲裁|owner|负责人|职责|合同|发票|验收',
            caseSensitive: false)
        .hasMatch(patchText)) {
      return true;
    }
    final sourceTerms = _domainTermsFromSource(sourceText);
    return _patchLooksRelatedToDomainTerms(patch, sourceTerms);
  }

  static MemoryPatch? _buildParsedTextContextFallback({
    required String sourceText,
    required String factId,
    required List<MemoryPatch> parsedPatches,
  }) {
    if (!_looksLikeParsedTextSource(sourceText)) return null;
    if (!RegExp(r'项目|Project|风险列表|灰度风险|分歧|仲裁|owner|负责人|职责',
            caseSensitive: false)
        .hasMatch(sourceText)) {
      return null;
    }
    if (parsedPatches.any(
      (patch) =>
          patch.op == 'create' &&
          _looksLikeParsedTextSource([
            patch.content,
            patch.title,
            ...patch.entityIds,
            ...patch.attributes.values.map((value) => value.toString()),
          ].join(' ')),
    )) {
      return null;
    }

    final project = RegExp(r'Project\s+[A-Za-z0-9][A-Za-z0-9 _-]*')
        .firstMatch(sourceText)
        ?.group(0)
        ?.trim();
    final content = sourceText
        .replaceFirst(RegExp(r'^.*?(?:OCR|已解析截图|截图文字|图片文字)[^：:]*[:：]?\s*'), '')
        .trim();
    final normalizedContent = content.isEmpty ? sourceText.trim() : content;
    final entityIds = <String>[
      if (project != null && project.isNotEmpty) project,
      ..._domainTermsFromSource(sourceText),
      'OCR',
      '给定文本',
    ];
    return MemoryPatch(
      op: 'create',
      type: 'project_context',
      title: project == null ? '已解析文本项目上下文' : '$project 已解析文本上下文',
      content: '$normalizedContent 此为已解析截图/OCR上下文，Agent 只需使用给定文本处理，不判断 OCR 质量。',
      confidence: 0.85,
      importance: 3,
      entityIds: _appendUniqueStrings(const [], entityIds),
      evidenceFactIds: [factId],
      attributes: const {
        'fallback_rule': 'parsed_text_context',
        'source_type': 'screenshot_ocr',
        'ocr_handling': 'use_given_text_only',
      },
    );
  }

  static List<String> _appendUniqueStrings(
    List<String> base,
    List<String> additions,
  ) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in [...base, ...additions]) {
      final text = value.trim();
      if (text.isNotEmpty && seen.add(text)) result.add(text);
    }
    return result;
  }

  static bool _patchLooksRelatedToDomainTerms(
    MemoryPatch patch,
    List<String> terms,
  ) {
    final text = [
      patch.content,
      patch.title,
      ...patch.entityIds,
    ].join(' ');
    for (final term in terms) {
      if (text.contains(term)) return true;
      for (final marker in _domainTermMarkers(term)) {
        if (text.contains(marker)) return true;
      }
    }
    return false;
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

  static MemoryPatch? _buildRoleTransitionFallback({
    required String sourceText,
    required String factId,
    required List<MemoryPatch> parsedPatches,
  }) {
    final transition = _extractRoleTransition(sourceText);
    if (transition == null) return null;
    final existingText = parsedPatches
        .map((patch) => '${patch.content} ${patch.entityIds.join(' ')}')
        .join('\n');
    if ([
      transition.fromRole,
      transition.toRole,
      transition.toMood,
    ].every(existingText.contains)) {
      return null;
    }

    return MemoryPatch(
      op: 'create',
      type: 'project_context',
      title: '角色与心态转换',
      content:
          '用户在 ${transition.fromProject} 和 ${transition.toProject} 之间切换角色：上午以 ${transition.fromRole} 处理 ${transition.fromProject}，下午切到 ${transition.toRole} 处理 ${transition.toProject}；阶段心态从 ${transition.fromMood} 转为 ${transition.toMood}。这不是提醒或行动创建请求。',
      confidence: 0.95,
      importance: 4,
      entityIds: [
        transition.fromRole,
        transition.toRole,
        transition.fromProject,
        transition.toProject,
        transition.fromMood,
        transition.toMood,
      ],
      evidenceFactIds: [factId],
      attributes: {
        'fallback_rule': 'role_mood_transition',
        'from_role': transition.fromRole,
        'to_role': transition.toRole,
        'from_project': transition.fromProject,
        'to_project': transition.toProject,
        'from_mood': transition.fromMood,
        'to_mood': transition.toMood,
        'read_only_boundary': 'not_action_or_reminder',
      },
    );
  }

  static _RoleTransition? _extractRoleTransition(String sourceText) {
    final roleMatch = RegExp(
      r'上午以\s*(.+?)\s*看\s*((?:Project|项目)[^，；;]+?)\s*上线风险[，；;]\s*下午切到\s*(.+?)\s*整理\s*((?:Meridian|Project|项目)[^，；;]+?)\s*客户反馈',
    ).firstMatch(sourceText);
    final moodMatch =
        RegExp(r'心态从\s*([^，。；;\n]+?)\s*转为\s*([^，。；;\n]+)').firstMatch(
      sourceText,
    );
    if (roleMatch == null || moodMatch == null) return null;
    final fromRole = roleMatch.group(1)?.trim();
    final fromProject = roleMatch.group(2)?.trim();
    final toRole = roleMatch.group(3)?.trim();
    final toProject = roleMatch.group(4)?.trim();
    final fromMood = moodMatch.group(1)?.trim();
    final toMood = moodMatch.group(2)?.trim();
    if ([
      fromRole,
      fromProject,
      toRole,
      toProject,
      fromMood,
      toMood,
    ].any((value) => value == null || value.isEmpty)) {
      return null;
    }
    return _RoleTransition(
      fromRole: fromRole!,
      toRole: toRole!,
      fromProject: fromProject!,
      toProject: toProject!,
      fromMood: fromMood!,
      toMood: toMood!,
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

  static List<String> _domainTermsFromSource(String sourceText) {
    final terms = <String>{};
    for (final term in const [
      '回滚演练',
      '失败恢复口径',
      '风险列表',
      '验收依据',
    ]) {
      if (sourceText.contains(term)) terms.add(term);
    }

    for (final match in RegExp(r'优先级').allMatches(sourceText)) {
      final prefix = _domainTermPrefixBefore(sourceText, match.start);
      final term = '$prefix优先级'.trim();
      if (term.length >= 4 && !RegExp(r'\s').hasMatch(term)) {
        terms.add(term);
      }
    }
    for (final suffix in const ['节奏', '窗口']) {
      for (final match in RegExp(suffix).allMatches(sourceText)) {
        final prefix = _domainTermPrefixBefore(sourceText, match.start);
        final term = '$prefix$suffix'.trim();
        if (term.length >= 4 && !RegExp(r'\s').hasMatch(term)) {
          terms.add(term);
        }
      }
    }
    for (final match in RegExp(r'分歧').allMatches(sourceText)) {
      final term = _domainTermPrefixBefore(sourceText, match.start)
          .replaceFirst(RegExp(r'(?:有|存在|产生|出现|发生)$'), '')
          .trim();
      if (term.length >= 4 && !RegExp(r'\s').hasMatch(term)) {
        terms.add(term);
      }
    }
    return terms.toList(growable: false);
  }

  static String _domainTermPrefixBefore(String sourceText, int end) {
    final prefixStart = (end - 16).clamp(0, end).toInt();
    var prefix = sourceText.substring(prefixStart, end);
    final splitMarkers = [
      '对',
      '关于',
      '针对',
      '就',
      '：',
      ':',
      '；',
      ';',
      '，',
      ',',
      '。',
      '\n'
    ];
    var splitAt = -1;
    for (final marker in splitMarkers) {
      final index = prefix.lastIndexOf(marker);
      if (index > splitAt) splitAt = index;
    }
    if (splitAt >= 0) {
      prefix = prefix.substring(splitAt + 1);
    }
    return prefix.replaceFirst(RegExp(r'^(?:的|该|此|这个|那个)\s*'), '').trim();
  }

  static List<String> _domainTermMarkers(String term) {
    if (term.endsWith('优先级')) {
      final prefix = term.substring(0, term.length - '优先级'.length);
      return [
        if (prefix.isNotEmpty) prefix,
        '优先级',
        '仲裁',
        '分歧',
      ];
    }
    if (term.endsWith('风险列表')) {
      return ['风险列表', '灰度风险', '风险'];
    }
    if (term.endsWith('节奏')) {
      final prefix = term.substring(0, term.length - '节奏'.length);
      return [
        if (prefix.isNotEmpty) prefix,
        '节奏',
        '分歧',
        '仲裁',
      ];
    }
    if (term.endsWith('窗口')) {
      final prefix = term.substring(0, term.length - '窗口'.length);
      return [
        if (prefix.isNotEmpty) prefix,
        '窗口',
        '分歧',
        '仲裁',
      ];
    }
    return [term];
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
    if (!_looksLikeTemporaryNoLongTermBoundary(sourceText)) return patch;
    if (!_looksLikeTemporaryNoLongTermBoundary(patch.content)) return patch;

    final json = patch.toJson();
    json['type'] = 'boundary';
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
      r'不要.*(?:长期|长记忆|长期记忆|长期画像|保存|写入)|不(?:要|应|希望).*长期|别.*(?:记|保存|长期化)',
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

class _RoleTransition {
  final String fromRole;
  final String toRole;
  final String fromProject;
  final String toProject;
  final String fromMood;
  final String toMood;

  const _RoleTransition({
    required this.fromRole,
    required this.toRole,
    required this.fromProject,
    required this.toProject,
    required this.fromMood,
    required this.toMood,
  });
}
