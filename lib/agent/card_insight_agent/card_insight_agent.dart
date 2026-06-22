import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/memory_primary_service.dart';
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
  final List<String> relatedMemoryIds;
  final bool fallback;

  const CardInsightDraft({
    required this.text,
    required this.summary,
    required this.relatedFactIds,
    this.relatedMemoryIds = const [],
    this.fallback = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'summary': summary,
      'related_fact_ids': relatedFactIds,
      'related_memory_ids': relatedMemoryIds,
      'fallback': fallback,
    };
  }
}

class CardInsightAgent {
  CardInsightAgent._();

  static final _logger = getLogger('CardInsightAgent');

  static Future<CardInsightDraft> generate({
    required String userId,
    required String factId,
    required String contentText,
    required CardData? card,
    required List<RelatedFactCandidate> relatedFacts,
    DateTime? inputDateTime,
    String? locationContextReminder,
  }) async {
    if (!_llmInsightEnabled) {
      return _fallback(contentText, relatedFacts);
    }

    return _generate(
      userId: userId,
      factId: factId,
      contentText: contentText,
      card: card,
      relatedFacts: relatedFacts,
      inputDateTime: inputDateTime,
      locationContextReminder: locationContextReminder,
    ).timeout(
      _overallGenerationTimeout,
      onTimeout: () {
        _logger.warning(
          'Card insight generation timed out for $factId; using fallback.',
        );
        return _fallback(contentText, relatedFacts);
      },
    );
  }

  static Future<CardInsightDraft> _generate({
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
      ).timeout(_llmGenerationTimeout);
      final draft = _parseDraft(
        response.textOutput ?? '',
        allowedRelatedFactIds:
            relatedFacts.map((e) => e.factId).where(isTimelineFactId).toSet(),
      );
      if (draft != null) {
        return _withBackfilledRelatedFacts(draft, relatedFacts);
      }
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
    final memoryContext = await MemoryPrimaryService.instance
        .buildRecallPromptBlock(userId: userId, query: contentText, limit: 8);
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

The input has already been saved as a raw Fact and Timeline Card. Do not
organize or update PARA/PKM files. Use Memory Primary and related Fact
candidates only as cited context.

Current local time:
$currentTime

Fact id:
$factId

$locationBlock
Memory Primary recall:
${memoryContext.isEmpty ? '(empty)' : memoryContext}

Current raw input:
$contentText

Current card JSON:
${const JsonEncoder.withIndent('  ').convert(cardJson)}

Related Fact candidates:
${const JsonEncoder.withIndent('  ').convert(relatedJson)}

Rules:
- Insight should explain why this record matters in context.
- Only cite related_fact_ids that appear in Related Fact candidates.
- Do not invent facts beyond current input, memory recall, or related facts.
- Keep the user's language.

Return strict JSON only:
{
  "insight_text": "concise explanation for the detail page",
  "summary_text": "one short sentence for quick scanning",
  "related_fact_ids": ["candidate fact_id values only"],
  "related_memory_ids": ["memory ids from Memory Primary recall if directly used"]
}
''';
  }

  static CardInsightDraft? _parseDraft(
    String raw, {
    required Set<String> allowedRelatedFactIds,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(_stripCodeFence(trimmed));
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
      final relatedMemory = <String>[];
      final rawRelatedMemory = decoded['related_memory_ids'];
      if (rawRelatedMemory is List) {
        for (final item in rawRelatedMemory) {
          final id = item.toString().trim();
          if (_isMemoryId(id)) relatedMemory.add(id);
        }
      }
      if (text.isEmpty && summary.isEmpty) return null;
      return CardInsightDraft(
        text: text.isEmpty ? summary : text,
        summary: summary.isEmpty ? text : summary,
        relatedFactIds: related,
        relatedMemoryIds: relatedMemory,
      );
    } catch (_) {
      return null;
    }
  }

  static CardInsightDraft _fallback(
    String contentText,
    List<RelatedFactCandidate> relatedFacts,
  ) {
    final compact = _compactContent(contentText);
    final focus = _clipAtBoundary(compact, 72);
    final labels = _insightLabels(compact);
    final summary = _fallbackSummary(focus, labels);
    final insightLead = _fallbackInsightLead(
      content: compact,
      labels: labels,
    );
    final synthesis = _fallbackSynthesis(labels, compact);
    final relatedIds = <String>[];
    final relatedMemoryIds = <String>[];
    for (final candidate in relatedFacts) {
      final id = candidate.factId;
      if (isTimelineFactId(id)) {
        if (relatedIds.length < _maxRelatedFactIds) relatedIds.add(id);
      } else if (_isMemoryId(id)) {
        if (relatedMemoryIds.length < _maxRelatedMemoryIds) {
          relatedMemoryIds.add(id);
        }
      }
    }
    final relatedLine = _relatedContextLine(relatedFacts);
    final body = [
      insightLead,
      synthesis,
      if (relatedLine != null) relatedLine,
    ].join('\n\n');

    return CardInsightDraft(
      text: body,
      summary: summary,
      relatedFactIds: relatedIds,
      relatedMemoryIds: relatedMemoryIds,
      fallback: true,
    );
  }

  static CardInsightDraft _withBackfilledRelatedFacts(
    CardInsightDraft draft,
    List<RelatedFactCandidate> candidates,
  ) {
    final seen = <String>{};
    final seenMemory = <String>{};
    final relatedIds = <String>[];
    final relatedMemoryIds = <String>[];

    void addRelatedFact(String id) {
      if (!isTimelineFactId(id)) return;
      if (relatedIds.length >= _maxRelatedFactIds) return;
      if (seen.add(id)) relatedIds.add(id);
    }

    void addRelatedMemory(String id) {
      if (!_isMemoryId(id)) return;
      if (relatedMemoryIds.length >= _maxRelatedMemoryIds) return;
      if (seenMemory.add(id)) relatedMemoryIds.add(id);
    }

    for (final id in draft.relatedMemoryIds) {
      addRelatedMemory(id);
    }

    final supportiveCandidates =
        candidates.where(_isSupportiveCandidate).toList(growable: false);

    for (final candidate in supportiveCandidates) {
      addRelatedFact(candidate.factId);
      addRelatedMemory(candidate.factId);
      if (relatedIds.length >= _maxRelatedFactIds &&
          relatedMemoryIds.length >= _maxRelatedMemoryIds) {
        break;
      }
    }

    for (final id in draft.relatedFactIds) {
      addRelatedFact(id);
    }

    if (relatedIds.isEmpty) {
      for (final candidate in candidates.take(3)) {
        addRelatedFact(candidate.factId);
      }
    }

    return CardInsightDraft(
      text: draft.text,
      summary: draft.summary,
      relatedFactIds: relatedIds,
      relatedMemoryIds: relatedMemoryIds,
      fallback: draft.fallback,
    );
  }

  static bool _isSupportiveCandidate(RelatedFactCandidate candidate) {
    if (candidate.memoryEvidenceScore > 0) return true;
    if (candidate.anchorScore > 0) return true;
    if (candidate.matchedHints.length >= 2) return true;
    return candidate.totalScore >= 0.48;
  }

  static String _compactContent(String contentText) {
    return contentText
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]\([^\)]*\)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<_InsightLabel> _insightLabels(String content) {
    final labels = <_InsightLabel>[];
    void addIf(_InsightLabel label, Pattern pattern) {
      if (content.contains(pattern)) labels.add(label);
    }

    addIf(_InsightLabel.correction, RegExp(r'更正|以这条为准|覆盖|当前 owner'));
    addIf(_InsightLabel.relationship, RegExp(r'关系|付款|发票|合同'));
    addIf(_InsightLabel.preference, RegExp(r'报告偏好|长期协作偏好|个人长期偏好|偏好'));
    addIf(_InsightLabel.sensitive, RegExp(r'高敏|财务压力|投资建议|税务结论'));
    addIf(_InsightLabel.parsedText, RegExp(r'OCR|截图|已解析'));
    addIf(_InsightLabel.longContext, RegExp(r'长上下文|很久以后|优先用当前'));
    addIf(_InsightLabel.noAction, RegExp(r'不要创建提醒|不要创建|不是行动|只记录'));
    addIf(_InsightLabel.noise, RegExp(r'临时噪声|低信号噪声|不要长期化|广告词'));
    addIf(_InsightLabel.projectStatus,
        RegExp(r'Project|项目|灰度|验收|回滚|失败恢复|验证|owner|风险'));

    return labels.isEmpty ? const [_InsightLabel.general] : labels;
  }

  static String _fallbackSummary(String focus, List<_InsightLabel> labels) {
    final lead = focus.isEmpty ? '这条记录' : _stripTrailingPunctuation(focus);
    if (labels.contains(_InsightLabel.noise)) {
      return '$lead：低信号临时记录，后续应避免长期化。';
    }
    if (labels.contains(_InsightLabel.sensitive)) {
      return '$lead：保留事实和情绪边界，避免给确定性建议。';
    }
    if (labels.contains(_InsightLabel.noAction)) {
      return '$lead：只作为反思保存，不应自动创建提醒或行动。';
    }
    if (labels.contains(_InsightLabel.parsedText)) {
      return '$lead：这是已解析文本证据，后续直接使用给定文本。';
    }
    if (labels.contains(_InsightLabel.preference)) {
      return '$lead：这是可复用偏好，后续输出应按该格式组织。';
    }
    if (labels.contains(_InsightLabel.correction)) {
      return '$lead：这是当前口径更新，后续召回应优先采用本条。';
    }
    if (labels.contains(_InsightLabel.longContext)) {
      return '$lead：这是长周期召回锚点，后续应优先使用当前口径。';
    }
    if (labels.contains(_InsightLabel.relationship)) {
      return '$lead：这是职责或关系边界信息，后续问答需区分当前角色。';
    }
    if (labels.contains(_InsightLabel.projectStatus)) {
      return '$lead：这是项目状态信号，后续关注 owner、风险和下一步。';
    }
    return '$lead：这是后续召回可用的事实锚点。';
  }

  static String _stripTrailingPunctuation(String value) {
    final stripped = value.replaceFirst(RegExp(r'[。！？!?；;，,：:\s]+$'), '');
    return stripped.isEmpty ? value.trim() : stripped;
  }

  static String _fallbackInsightLead({
    required String content,
    required List<_InsightLabel> labels,
  }) {
    if (labels.contains(_InsightLabel.noise)) {
      return '价值：这是低信号、临时性的时间线记录；后续使用时应避免把它变成稳定偏好、项目事实或推荐依据。';
    }
    if (labels.contains(_InsightLabel.sensitive)) {
      return '价值：这是敏感领域的处理边界声明；后续只能用于事实回顾和情绪复盘，不应扩展为投资、税务、医疗或法律判断。';
    }
    if (labels.contains(_InsightLabel.noAction)) {
      return '价值：用户明确限定为记录而非任务；这条把“以后应该”类表达降级为复盘信号，后续只能用于理解习惯改进，不应自动创建提醒、日程或行动项。';
    }
    if (labels.contains(_InsightLabel.parsedText) &&
        labels.contains(_InsightLabel.projectStatus)) {
      return '价值：这条已解析文本可作为项目风险清单证据；下一步应把它归入对应项目的灰度风险追踪，围绕负责人、验收标准和风险关闭状态继续推进，而不是重新评估截图或 OCR 本身。';
    }
    if (labels.contains(_InsightLabel.parsedText)) {
      return '价值：这条记录提供的是已解析文本证据；后续应直接使用给定文本，并避免重新判断原始 OCR。';
    }
    if (labels.contains(_InsightLabel.preference)) {
      if (_hasSchedulingPreference(content)) {
        return '价值：这是可执行的日程协作偏好；下一次排期或回答时间安排问题时，应先检查地点、固定时段和不安排事项，遇到冲突时优先保护用户明确保留的时间块。';
      }
      if (_hasReportFormatPreference(content)) {
        if (_isRepeatedConfirmation(content)) {
          return '价值：这是对既有输出格式偏好的重复确认，不是新的项目状态；后续遇到同类项目回答时，应把这条作为稳定结构约束来覆盖临时表达差异。';
        }
        return '价值：这是可执行的输出格式偏好；下一次回答相关项目问题时，应按用户指定的栏目顺序组织结论、风险、下一步、Owner 和证据来源。';
      }
      return '价值：这是可执行的协作偏好；下一次处理同类上下文时，应先检查用户明确声明的格式、边界和不希望发生的事项。';
    }
    if (labels.contains(_InsightLabel.correction)) {
      return '价值：这是当前口径更新；后续召回和回答应优先采用本条，把旧说法降级为历史背景。';
    }
    if (labels.contains(_InsightLabel.longContext)) {
      return '价值：这是长周期召回锚点；很久以后回答相关问题时，应优先使用当前 owner 或当前口径。';
    }
    if (labels.contains(_InsightLabel.relationship)) {
      return '价值：它明确了职责路由的负向排除和正向联系人；后续询问付款、发票或合同时，应先排除不负责的人，再指向当前可处理的联系人。';
    }
    if (labels.contains(_InsightLabel.projectStatus)) {
      if (_hasFailureRecoveryAlignment(content)) {
        return '价值：它把失败恢复与回滚演练口径连成跨项目一致性约束；后续复盘时应一起校验这两个风险/恢复项，并保留证据来源。';
      }
      if (RegExp(r'启动|早期记录|灰度准备').hasMatch(content)) {
        return '价值：这是项目推进的基线记录；下一步应确认负责人、验收标准和主要风险项，后续更正时可用来区分历史口径与当前口径。';
      }
      if (RegExp(r'第\s*\d+\s*次验证|第\s*\d+\s*轮|继续由她负责|仍负责|owner')
          .hasMatch(content)) {
        return '价值：这是责任连续性和验收进度信号；下一步应跟进对应验收项、风险项或上线前置项是否已经推进或关闭。';
      }
      return '价值：这是项目状态信号；下一步应围绕记录中的 owner、风险项、验收项或上线前置项继续跟进。';
    }
    return '价值：它为后续回看提供当前事实锚点；需要判断历史变化时，应与相关记录一起使用。';
  }

  static String _fallbackSynthesis(List<_InsightLabel> labels, String content) {
    if (labels.contains(_InsightLabel.noise)) {
      return '意义：这类内容适合保留在时间线中帮助回看当天状态，但不应被提升为稳定偏好、项目事实或推荐依据。';
    }
    if (labels.contains(_InsightLabel.sensitive)) {
      return '意义：这是敏感领域的安全使用规则：后续只能归纳事实、情绪和不确定性；一旦问题转向决策、收益或税务方案，应保持边界并提醒需要专业判断。';
    }
    if (labels.contains(_InsightLabel.noAction)) {
      return '意义：它把反思内容和执行授权分开保存；除非用户之后明确提出新请求，否则系统只能在回顾时引用这条边界，而不能把它升级成待办。';
    }
    if (labels.contains(_InsightLabel.parsedText) &&
        labels.contains(_InsightLabel.projectStatus)) {
      return '意义：它不是图片质量判断，而是项目风险证据入口；后续检索到该项目灰度、回滚或验收问题时，应把这条作为风险清单来源之一。';
    }
    if (labels.contains(_InsightLabel.parsedText)) {
      return '意义：已给定的解析文本可作为证据参与记忆和检索，但不需要重新判断截图或 OCR 本身。';
    }
    if (labels.contains(_InsightLabel.preference)) {
      if (_hasSchedulingPreference(content)) {
        return '意义：它把日程偏好转成可检查的执行规则，后续应在排会和协作安排前主动核对，避免把已声明的时间边界当成普通可用时段。';
      }
      if (_hasReportFormatPreference(content)) {
        if (_isRepeatedConfirmation(content)) {
          return '意义：重复确认会提高该偏好的优先级和置信度；当历史卡片、记忆或回答模板出现不同顺序时，应优先采用这条确认后的栏目顺序。';
        }
        return '意义：它把回答偏好转成可复用的结构约束，后续检索到这些项目时应先给最新结论，再补风险、下一步、Owner 和证据。';
      }
      return '意义：它把偏好转成可检查的执行规则，后续应在同类协作或问答场景中主动核对，而不是把偏好当成普通背景信息。';
    }
    if (labels.contains(_InsightLabel.correction)) {
      return '意义：它覆盖或修正了旧说法，后续回答应把旧信息视为历史背景，并把本条作为当前事实。';
    }
    if (labels.contains(_InsightLabel.longContext)) {
      return '意义：这是长周期召回锚点，未来跨时间提问时应优先使用当前 owner 或当前口径，而不是早期记录。';
    }
    if (labels.contains(_InsightLabel.relationship)) {
      return '意义：这类记录适合沉淀为联系人路由规则，后续关于付款、发票或合同的问题应优先使用当前联系人，并把排除项作为防误答边界。';
    }
    if (labels.contains(_InsightLabel.projectStatus)) {
      return '意义：它把项目进展与负责人、验收风险或恢复口径连接起来，后续跟进时可用来判断当前状态和下一步关注点。';
    }
    return '意义：它为后续回看提供当前事实点，必要时应与相关记录一起判断历史变化和当前状态。';
  }

  static bool _hasFailureRecoveryAlignment(String content) {
    return RegExp(r'失败恢复').hasMatch(content) &&
        RegExp(r'回滚演练').hasMatch(content);
  }

  static bool _hasSchedulingPreference(String content) {
    return RegExp(r'常驻|周三|深度工作|不安排评审|排期|排会|固定时段').hasMatch(content);
  }

  static bool _hasReportFormatPreference(String content) {
    return RegExp(r'报告偏好|回答格式|回答要|字段|栏目|证据来源|最新结论|Owner', caseSensitive: false)
        .hasMatch(content);
  }

  static bool _isRepeatedConfirmation(String content) {
    return RegExp(r'重复确认|再次确认|重申|确认一遍').hasMatch(content);
  }

  static String? _relatedContextLine(List<RelatedFactCandidate> relatedFacts) {
    final count = relatedFacts
        .where((e) => isTimelineFactId(e.factId))
        .take(_maxRelatedFactIds)
        .length;
    if (count == 0) return null;
    return '相关上下文：已关联 $count 条候选记录，用于校验历史说法、当前口径和边界；具体证据保留在结构化 related_facts 中。';
  }

  static String _clipAtBoundary(String value, int maxLength) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLength) return compact;
    final clipped = compact.substring(0, maxLength);
    final boundary = [
      clipped.lastIndexOf('。'),
      clipped.lastIndexOf('；'),
      clipped.lastIndexOf(';'),
      clipped.lastIndexOf('，'),
      clipped.lastIndexOf(','),
      clipped.lastIndexOf(' '),
    ].where((index) => index >= 24).fold<int>(
          -1,
          (best, index) => index > best ? index : best,
        );
    final text = boundary > 0 ? clipped.substring(0, boundary) : clipped;
    return '${text.trim()}...';
  }

  static const _maxRelatedFactIds = 8;
  static const _maxRelatedMemoryIds = 8;
  static const _overallGenerationTimeout = Duration(seconds: 75);
  static const _llmGenerationTimeout = Duration(seconds: 45);

  static final RegExp _timelineFactIdPattern = RegExp(
    r'^\d{4}/\d{2}/\d{2}\.md#ts_\d+$',
  );
  static final RegExp _memoryIdPattern = RegExp(r'^mem_\d+$');

  static bool isTimelineFactId(String id) {
    return _timelineFactIdPattern.hasMatch(id.trim());
  }

  static bool _isMemoryId(String id) {
    return _memoryIdPattern.hasMatch(id.trim());
  }

  static bool get _llmInsightEnabled {
    final value = Platform.environment['MEMEX_CARD_INSIGHT_ENABLE_LLM']
        ?.trim()
        .toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  static String _stripCodeFence(String value) {
    if (!value.startsWith('```')) return value;
    return value
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
}

enum _InsightLabel {
  correction,
  relationship,
  preference,
  sensitive,
  parsedText,
  longContext,
  noAction,
  noise,
  projectStatus,
  general,
}
