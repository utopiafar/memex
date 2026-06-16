import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/agent/memex_skill_host_agent/memex_skill_host_agent.dart';
import 'package:memex/agent/pure_skill_host_agent/pure_skill_host_agent.dart';
import 'package:memex/agent/super_agent/super_agent.dart';
import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/domain/models/custom_agent_config.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/token_usage_utils.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'package:memex/data/model/chat_events.dart';

export 'package:memex/data/model/chat_events.dart';

// --- Chat Service ---

class ChatService {
  static final ChatService _instance = ChatService._internal();
  static ChatService get instance => _instance;
  ChatService._internal();

  final Logger _logger = getLogger('ChatService');
  FileSystemService get _fileService => FileSystemService.instance;
  final Uuid _uuid = const Uuid();

  /// Send a message and get a stream of events.
  ///
  /// When [isQuickQuery] is true, the agent operates in read-only mode
  /// (filtered tools/skills), but the session is still persisted normally.
  Stream<ChatEvent> sendMessage(
    String message, {
    String? sessionId,
    String? agentName = 'memex_agent',
    String? scene = 'assistant',
    String? sceneId,
    List<Map<String, String>>? refs,
    bool isQuickQuery = false,
  }) async* {
    _logger.info(
      'sendMessage: sessionId=$sessionId, message=$message, refs=${refs?.length}',
    );

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      yield ChatErrorEvent('User not logged in');
      return;
    }

    String finalSessionId = sessionId ?? '';
    final userMessageTime = DateTime.now();

    // 1. Session Management
    try {
      if (finalSessionId.isEmpty) {
        finalSessionId = await _createSession(
          userId,
          agentName,
          [
            {'type': 'text', 'text': message},
          ],
          isQuickQuery: isQuickQuery,
          createdAt: userMessageTime,
        );
      }

      // Notify UI of the active session ID immediately
      yield ChatSessionCreatedEvent(finalSessionId);

      // Save User Message
      await _addMessageToSession(
        userId,
        finalSessionId,
        'user',
        [
          {'type': 'text', 'text': message},
        ],
        refs: refs,
        isQuickQuery: isQuickQuery,
        timestamp: userMessageTime,
      );

      // Log chat event
      try {
        await _fileService.eventLogService.logEvent(
          userId: userId,
          eventType: 'user_chat',
          description: 'User sent message to agent',
          metadata: {
            'agent_name': agentName ?? 'memex_agent',
            'scene': scene ?? 'assistant',
            'scene_id': sceneId,
            'session_id': finalSessionId,
            'message': message,
            'message_local_time': formatLocalDateTimeWithZone(userMessageTime),
            'message_unix_seconds': unixSecondsFromDateTime(userMessageTime),
            'has_refs': refs != null && refs.isNotEmpty,
            'is_quick_query': isQuickQuery,
          },
        );
      } catch (e) {
        // Event logging failure should not break chat
      }
    } catch (e) {
      _logger.severe('Failed to manage session', e);
      yield ChatErrorEvent('Failed to initialize session: $e');
      return;
    }

    final pipelineConfig = await UserStorage.getAgentPipelineConfig();
    final useMemoryPrimaryPostProcessing =
        pipelineConfig.runsMemoryPrimary && isQuickQuery;
    _MemoryPrimaryQuickQueryFallback? preloadedMemoryPrimaryRecall;
    if (useMemoryPrimaryPostProcessing &&
        _looksLikeMemoryPrimaryRecallQuery(message)) {
      try {
        preloadedMemoryPrimaryRecall =
            await _buildMemoryPrimaryQuickQueryFallback(
          userId: userId,
          query: message,
        );
      } catch (e, stack) {
        _logger.warning(
          'Failed to preload Memory Primary quick-query recall',
          e,
          stack,
        );
      }
    }
    if (preloadedMemoryPrimaryRecall != null) {
      var response = _prepareMemoryPrimaryQuickQueryFallbackResponse(
        preloadedMemoryPrimaryRecall,
        query: message,
        sanitizeCurrentStateAnswer: useMemoryPrimaryPostProcessing &&
            _looksLikeCurrentStateQuery(message),
        postProcessQuickQueryAnswer: useMemoryPrimaryPostProcessing &&
            (_looksLikeCurrentStateQuery(message) ||
                _looksLikePreferenceQuery(message)),
      );
      await _addMessageToSession(
        userId,
        finalSessionId,
        'ai',
        [
          {'type': 'text', 'text': response},
        ],
        usage: const {
          'prompt_tokens': 0,
          'completion_tokens': 0,
          'cached_tokens': 0,
          'total_tokens': 0,
          'total_cost': 0.0,
          'fallback': 'memory_primary_quick_query_direct',
        },
        timestamp: DateTime.now(),
      );
      yield ChatToolCallEvent(
        'search_memory_primary',
        jsonEncode({'query': preloadedMemoryPrimaryRecall.query, 'limit': 10}),
      );
      yield ChatToolResultEvent(
        'search_memory_primary',
        preloadedMemoryPrimaryRecall.toolResult,
      );
      yield ChatResponseChunkEvent(response);
      yield ChatResponseChunkEvent('', isDone: true);
      yield ChatTokenUsageEvent(
        promptTokens: 0,
        completionTokens: 0,
        cachedTokens: 0,
        totalTokens: 0,
        estimatedCost: 0,
      );
      yield ChatAgentStoppedEvent();
      return;
    }

    // 2. Initialize Agent
    StatefulAgent? agent;
    AgentController? controller;
    SkillSyncResult? skillSync;

    try {
      // Check if this session belongs to a custom agent by reading session metadata,
      // then load the latest config from CustomAgentConfigService.
      CustomAgentConfig? customAgentCfg;
      if (sessionId != null && sessionId.isNotEmpty) {
        final isCustom = await _isCustomAgentSession(userId, finalSessionId);
        if (isCustom && agentName != null && agentName.isNotEmpty) {
          final configs = await CustomAgentConfigService.instance.loadAll(
            userId,
          );
          customAgentCfg =
              configs.where((c) => c.agentName == agentName).firstOrNull;
        }
      }

      final agentIdForLLM =
          customAgentCfg?.llmConfigKey ?? AgentDefinitions.chatAgent;
      final resources = await UserStorage.getAgentLLMResources(
        agentIdForLLM,
        defaultClientKey:
            customAgentCfg?.llmConfigKey ?? LLMConfig.defaultClientKey,
      );
      final client = resources.client;
      final modelConfig = resources.modelConfig;

      // Load State
      final stateDirPath = await _fileService.getAgentStateDirectory(userId);
      final stateDir = Directory(stateDirPath);
      final storage = FileStateStorage(stateDir);
      final state = await storage.loadOrCreate(finalSessionId, {
        'userId': userId,
        'scene': scene,
        'sceneId': sceneId,
      });

      controller = AgentController();

      if (customAgentCfg != null) {
        // Recreate the same agent type used by custom_agent_task_handler.
        final skillDir = _fileService.resolveSkillPath(
          userId,
          customAgentCfg.skillDirectoryPath,
        );
        final workingDirAbs = await _fileService.resolveWorkingDirectory(
          userId,
          customAgentCfg.workingDirectory,
        );

        // Sync skill directory into workingDirectory if it's outside,
        // so file tools (Read, LS, etc.) can access skill files.
        skillSync = await _fileService.syncSkillsIfNeeded(
          skillAbsPath: skillDir,
          workingDirAbsPath: workingDirAbs,
        );

        switch (customAgentCfg.hostAgentType) {
          case HostAgentType.pure:
            agent = await PureSkillHostAgent.createAgent(
              client: client,
              modelConfig: modelConfig,
              userId: userId,
              name: agentName ?? 'custom_agent',
              state: state,
              skillDirectoryPath: skillSync.effectivePath,
              workingDirectory: workingDirAbs,
              controller: controller,
              additionalSystemPrompt: customAgentCfg.systemPrompt,
            );
            break;
          case HostAgentType.memex:
            agent = await MemexSkillHostAgent.createAgent(
              client: client,
              modelConfig: modelConfig,
              userId: userId,
              name: agentName ?? 'custom_agent',
              state: state,
              skillDirectoryPath: skillSync.effectivePath,
              workingDirectory: workingDirAbs,
              controller: controller,
              additionalSystemPrompt: customAgentCfg.systemPrompt,
            );
            break;
        }
      } else {
        // Default: use SuperAgent for normal chat sessions.
        var additionalSystemPrompt = """## Comprehensive Correction Principles
When the user disputes content you generated (such as Cards, PKM entries, or Asset Analysis Results) and provides correction suggestions, you must perform a **comprehensive** correction.
-   **Do not modify only a single dimension** (e.g., do not just modify the card body or just the asset analysis).
-   **You must check and synchronously correct all related content** to ensure overall consistency.
-   **Example**: If the user corrects the description of an image, you must not only update the image analysis result (`.analysis.txt`) but also check if the Card body (`Cards/...`) or related PKM entries that reference this image need to be updated synchronously.

## Interaction Guidelines
- **Ask Clarifying Questions**: You are engaging in a direct dialogue. If the user's request is unclear, explicitly ask for clarification instead of guessing.
- **Professional Tone**: You are communicating directly with the knowledge base owner. Maintain a formal, concise, and professional tone.
- **Know Your Limits**: If a task cannot be accomplished with your current skills and tools, explicitly decline the request with an explanation.

## Important
- **Language**: ${UserStorage.l10n.chatLanguageInstruction}
""";

        final forceActiveSkills = <String>[];
        if (scene == 'assistant_timeline_card_detail') {
          forceActiveSkills.add('manage_timeline_card');
          forceActiveSkills.add('manage_pkm');
        } else if (scene == 'insight_card_chat') {
          forceActiveSkills.add('update_knowledge_insight');
        }

        agent = await SuperAgent.createAgent(
          client: client,
          modelConfig: modelConfig,
          userId: userId,
          name: agentName ?? 'memex_agent',
          state: state,
          controller: controller,
          disableSubAgents: false,
          forceActiveSkills: forceActiveSkills,
          quickQuery: isQuickQuery,
          additionalSystemPrompt: additionalSystemPrompt,
        );
      }
    } catch (e) {
      _logger.severe('Failed to initialize agent', e);
      yield ChatErrorEvent('Failed to initialize agent: $e');
      return;
    }

    // 3. Setup Listeners & Run
    final streamController = StreamController<ChatEvent>();
    // Forward events from agent controller to stream
    _setupControllerListeners(
      controller,
      streamController,
      userId,
      finalSessionId,
      postProcessQuickQueryAnswer: useMemoryPrimaryPostProcessing &&
          (_looksLikeCurrentStateQuery(message) ||
              _looksLikePreferenceQuery(message)),
      sanitizeCurrentStateAnswer: useMemoryPrimaryPostProcessing &&
          _looksLikeCurrentStateQuery(message),
      memoryPrimaryQuickQueryFallback: useMemoryPrimaryPostProcessing,
      currentStateQueryText: message,
    );

    // Build scene context reminder
    String sceneContext = "";
    switch (scene) {
      case 'assistant_timeline_card_detail':
        sceneContext =
            "The user is currently viewing a **Timeline Card Detail Page**. They may want to edit, analyze, or discuss this specific card.";
        break;
      case 'update_knowledge_insight':
      case 'insight_card_chat':
        sceneContext =
            "The user is currently on the **Knowledge Insights Page**. They may want to update insights, discuss existing insight cards, or generate new knowledge summaries.";
        break;
      default:
        sceneContext = "";
    }

    List<LLMMessage> userMessages = [];
    CurrentLocationContext? locationContext;
    String? locationContextReminder;
    try {
      locationContext =
          await LocationContextService.instance.getCurrentContext();
      locationContextReminder = locationContext.toAgentSystemReminderContent();
    } catch (e) {
      _logger.warning('Failed to decorate chat with location context: $e');
    }

    // Build combined system reminder content
    if (sceneContext.isNotEmpty ||
        locationContextReminder != null ||
        (refs != null && refs.isNotEmpty)) {
      final StringBuffer reminderContent = StringBuffer();
      reminderContent.write('<system-reminder>\n');

      // Add scene context if available
      if (sceneContext.isNotEmpty) {
        reminderContent.write(sceneContext);
        reminderContent.write('\n');
      }

      if (locationContextReminder != null) {
        if (sceneContext.isNotEmpty) {
          reminderContent.write('\n');
        }
        reminderContent.write(locationContextReminder);
        reminderContent.write('\n');
      }

      // Add refs context if available
      if (refs != null && refs.isNotEmpty) {
        if (sceneContext.isNotEmpty || locationContextReminder != null) {
          reminderContent.write('\n');
        }
        final refsString = refs
            .map(
              (r) =>
                  'Title: ${r['title']}\nType: ${r['type'] ?? 'unknown'}\nContent: ${r['content']}',
            )
            .join('\n\n');
        reminderContent.write(
          'The user has referenced the following content. Use this context to answer the user query:\n',
        );
        reminderContent.write(refsString);
        reminderContent.write('\n');
      }

      reminderContent.write('</system-reminder>');

      userMessages.addAll([
        UserMessage.text(reminderContent.toString()),
        ModelMessage(
          model: "mocked",
          textOutput: "Understood, I will keep this context in mind.",
        ),
      ]);
    }

    if (preloadedMemoryPrimaryRecall != null) {
      userMessages.addAll([
        UserMessage.text('''<system-reminder>
Preloaded Memory Primary recall for the user's original quick query:
${preloadedMemoryPrimaryRecall.toolResult}

Use this context first. Avoid additional tool calls unless this context is clearly insufficient. If you need a focused follow-up search, use `search_memory_primary` with the concrete terms from the user question.
</system-reminder>'''),
        ModelMessage(
          model: 'mocked',
          textOutput:
              'Understood, I will answer from the preloaded Memory Primary context first.',
        ),
      ]);
    }

    userMessages.add(
      UserMessage([
        TextPart(buildCurrentTimeReminder(userMessageTime)),
        TextPart(buildMessageTimePrefix(userMessageTime)),
        TextPart(message),
      ]),
    );

    // We don't await the result here, we rely on AgentStoppedEvent to handle completion
    if (preloadedMemoryPrimaryRecall != null) {
      streamController.add(
        ChatToolCallEvent(
          'search_memory_primary',
          jsonEncode({
            'query': preloadedMemoryPrimaryRecall.query,
            'limit': 10,
          }),
        ),
      );
      streamController.add(
        ChatToolResultEvent(
          'search_memory_primary',
          preloadedMemoryPrimaryRecall.toolResult,
        ),
      );
    }

    agent.run(userMessages).whenComplete(() async {
      // Sync skill changes back to the original directory if we made a copy.
      if (skillSync != null) {
        try {
          await _fileService.syncSkillsBack(skillSync);
        } catch (e) {
          _logger.warning('Failed to sync skills back: $e');
        }
      }
    }).catchError((e) {
      // This catchError is for synchronous errors during startup or unhandled async errors
      // causing the run future to fail before AgentStoppedEvent might be emitted (though AgentStoppedEvent is in finally block)
      _logger.severe('Agent run failed (catchError)', e);
      if (!streamController.isClosed) {
        streamController.add(ChatErrorEvent(e.toString()));
        streamController.close();
      }
      return <LLMMessage>[];
    });

    yield* streamController.stream;
  }

  void _setupControllerListeners(
    AgentController controller,
    StreamController<ChatEvent> stream,
    String userId,
    String sessionId, {
    required bool postProcessQuickQueryAnswer,
    required bool sanitizeCurrentStateAnswer,
    required bool memoryPrimaryQuickQueryFallback,
    required String currentStateQueryText,
  }) {
    // 1. Lifecycle Events
    // 1. Lifecycle Events
    controller.on((AgentStartedEvent event) {
      _logger.info('Agent started');
      stream.add(ChatAgentStartedEvent());
    });

    controller.on((AgentStoppedEvent event) async {
      _logger.info('Agent stopped');

      // Calculate usage stats
      int totalPrompt = 0;
      int totalCompletion = 0;
      int totalCached = 0;
      int totalEffectivePrompt = 0;
      int totalCachedForRate = 0;
      int totalTokens = 0;
      double totalCost = 0.0;
      // Within a single agent turn all calls share the same client.
      bool? turnCacheSemantics;

      for (final msg in event.modelMessages) {
        final u = msg.usage;
        if (u == null) {
          continue;
        }

        final p = u.promptTokens;
        final c = u.completionTokens;
        final ca = u.cachedToken;
        final sem = TokenUsageUtils.cachedTokensIncludedInPrompt(
          client: event.agent.client,
          originalUsage: u.originalUsage,
        );
        turnCacheSemantics ??= sem;
        final effP = TokenUsageUtils.effectivePromptTokensOrNull(
          promptTokens: p,
          cachedTokens: ca,
          cachedTokensIncludedInPrompt: sem,
        );

        totalPrompt += p;
        totalCompletion += c;
        totalCached += ca;
        if (effP != null) {
          totalEffectivePrompt += effP;
          totalCachedForRate += ca;
        }
        totalTokens += u.totalTokens;

        // Calculate cost
        final cost = TokenUsageUtils.calculateCost(
          model: msg.model,
          promptTokens: p,
          completionTokens: c,
          cachedTokens: ca,
          thoughtTokens: u.thoughtToken,
          cachedTokensIncludedInPrompt: sem,
        )['total']!;
        totalCost += cost;
      }

      if (event.error != null) {
        final fallback = memoryPrimaryQuickQueryFallback
            ? await _buildMemoryPrimaryQuickQueryFallback(
                userId: userId,
                query: currentStateQueryText,
              )
            : null;
        if (fallback != null) {
          var response = fallback.answer;
          if (sanitizeCurrentStateAnswer) {
            response = _sanitizeCurrentStateAnswer(
              response,
              query: currentStateQueryText,
            );
          }
          if (_looksLikePreferenceQuery(currentStateQueryText)) {
            response = _sanitizeMemoryPrimaryPreferenceAnswer(
              response,
              query: currentStateQueryText,
            );
          }
          if (postProcessQuickQueryAnswer) {
            response = _ensureProjectNameFromQuery(
              response,
              query: currentStateQueryText,
            );
          }

          await _addMessageToSession(
            userId,
            sessionId,
            'ai',
            [
              {'type': 'text', 'text': response},
            ],
            usage: const {
              'prompt_tokens': 0,
              'completion_tokens': 0,
              'cached_tokens': 0,
              'total_tokens': 0,
              'total_cost': 0.0,
              'fallback': 'memory_primary_quick_query',
            },
            timestamp: DateTime.now(),
          );

          if (!stream.isClosed) {
            stream.add(
              ChatToolCallEvent(
                'search_memory_primary',
                jsonEncode({'query': fallback.query, 'limit': 10}),
              ),
            );
            stream.add(
              ChatToolResultEvent(
                'search_memory_primary',
                fallback.toolResult,
              ),
            );
            stream.add(ChatResponseChunkEvent(response));
            stream.add(ChatResponseChunkEvent('', isDone: true));
            stream.add(ChatAgentStoppedEvent());
            stream.close();
          }
          return;
        }
        if (!stream.isClosed) {
          stream.add(ChatAgentStoppedEvent());
          stream.add(ChatErrorEvent(event.error.toString()));
          stream.close();
        }
        return;
      }

      // Handle success / final result
      String response = "Sorry, I couldn't generate a response.";
      if (event.modelMessages.isNotEmpty) {
        final lastMsg = event.modelMessages.last;
        if (lastMsg.textOutput != null) {
          response = lastMsg.textOutput!;
        }
      }
      if (sanitizeCurrentStateAnswer) {
        response = _sanitizeCurrentStateAnswer(
          response,
          query: currentStateQueryText,
        );
      }
      if (memoryPrimaryQuickQueryFallback &&
          _looksLikePreferenceQuery(currentStateQueryText)) {
        response = _sanitizeMemoryPrimaryPreferenceAnswer(
          response,
          query: currentStateQueryText,
        );
      }
      if (postProcessQuickQueryAnswer) {
        response = _ensureProjectNameFromQuery(
          response,
          query: currentStateQueryText,
        );
      }

      // Save AI response with usage stats
      final responseTime = DateTime.now();
      final sessionTotalUsage = await _addMessageToSession(
        userId,
        sessionId,
        'ai',
        [
          {'type': 'text', 'text': response},
        ],
        usage: {
          'prompt_tokens': totalPrompt,
          'completion_tokens': totalCompletion,
          'cached_tokens': totalCached,
          if (turnCacheSemantics != null)
            'cache_tokens_included_in_prompt': turnCacheSemantics,
          'total_tokens': totalTokens,
          'total_cost': totalCost,
        },
        timestamp: responseTime,
      );

      // Emit Token Usage (Cumulative if available, else current turn)
      if (sessionTotalUsage != null) {
        stream.add(
          ChatTokenUsageEvent(
            promptTokens: sessionTotalUsage['prompt_tokens'] as int? ?? 0,
            completionTokens:
                sessionTotalUsage['completion_tokens'] as int? ?? 0,
            cachedTokens: sessionTotalUsage['cached_tokens'] as int? ?? 0,
            effectivePromptTokens: totalEffectivePrompt,
            cachedTokensForRate: totalCachedForRate,
            totalTokens: sessionTotalUsage['total_tokens'] as int? ?? 0,
            estimatedCost: sessionTotalUsage['total_cost'] as double? ?? 0.0,
          ),
        );
      } else if (totalTokens > 0) {
        // Fallback to single turn usage
        stream.add(
          ChatTokenUsageEvent(
            promptTokens: totalPrompt,
            completionTokens: totalCompletion,
            cachedTokens: totalCached,
            effectivePromptTokens: totalEffectivePrompt,
            cachedTokensForRate: totalCachedForRate,
            totalTokens: totalTokens,
            estimatedCost: totalCost,
          ),
        );
      }

      if (!stream.isClosed) {
        if (postProcessQuickQueryAnswer) {
          stream.add(ChatResponseChunkEvent(response));
        }
        // Send a final empty chunk to mark isDone=true without duplicating text
        stream.add(ChatResponseChunkEvent('', isDone: true));
        stream.add(ChatAgentStoppedEvent());
        stream.close();
      }
    });

    // 2. Planning Events
    controller.on((PlanChangedEvent event) {
      String getStatusEmoji(String status) {
        switch (status.toLowerCase()) {
          case 'completed':
          case 'success':
          case 'done':
            return '✅';
          case 'active':
          case 'running':
          case 'inprogress':
            return '👉';
          case 'failed':
          case 'error':
            return '❌';
          case 'pending':
          default:
            return '⏳'; // Or ⬜
        }
      }

      final planText = event.plan.steps.map((t) {
        final emoji = getStatusEmoji(t.status.name);
        return '$emoji ${t.description}';
      }).join('\n\n');
      stream.add(ChatThoughtChunkEvent("Plan Updated:\n$planText"));
    });

    // 3. Thoughts & Chunks
    controller.on((LLMChunkEvent event) {
      if (event.response.thought != null &&
          event.response.thought!.isNotEmpty) {
        stream.add(ChatThoughtChunkEvent(event.response.thought!));
      }

      if (event.response.textOutput != null &&
          event.response.textOutput!.isNotEmpty &&
          !postProcessQuickQueryAnswer) {
        stream.add(ChatResponseChunkEvent(event.response.textOutput!));
      }
    });

    // 4. Tool Call
    controller.on((BeforeToolCallEvent event) {
      final args = _augmentMemoryPrimarySearchArgsForTrace(
        toolName: event.functionCall.name,
        args: event.functionCall.arguments.toString(),
        originalUserQuery:
            memoryPrimaryQuickQueryFallback ? currentStateQueryText : null,
      );
      stream.add(
        ChatToolCallEvent(
          event.functionCall.name,
          args,
        ),
      );
    });

    // 5. Tool Result
    // 5. Tool Result
    controller.on((AfterToolCallEvent event) {
      // Format result for display
      final dynamic content = event.result.content;
      String resultPreview;

      if (content is List) {
        resultPreview = content.map((e) {
          if (e is TextPart) return e.text;
          return e.toString();
        }).join('\n');
      } else if (content is TextPart) {
        resultPreview = content.text;
      } else {
        resultPreview = content.toString();
      }

      final maxPreviewLength =
          event.result.name == 'search_memory_primary' ? 12000 : 300;
      if (resultPreview.length > maxPreviewLength) {
        resultPreview = '${resultPreview.substring(0, maxPreviewLength)}...';
      }
      stream.add(
        ChatToolResultEvent(
          event.result.name,
          resultPreview,
          isError: event.result.isError,
        ),
      );
    });
  }

  bool _looksLikeCurrentStateQuery(String query) {
    final normalized = query.toLowerCase();
    return normalized.contains('当前') ||
        normalized.contains('现在') ||
        normalized.contains('最新') ||
        normalized.contains('current') ||
        normalized.contains('latest') ||
        normalized.contains('以哪条为准') ||
        normalized.contains('以谁为准');
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
        normalized.contains('总结') ||
        normalized.contains('写法');
  }

  bool _looksLikeMemoryPrimaryRecallQuery(String query) {
    return _looksLikeCurrentStateQuery(query) ||
        _looksLikePreferenceQuery(query) ||
        _looksLikeRelationshipQuery(query) ||
        _looksLikeIdentityOrRoutineQuery(query);
  }

  @visibleForTesting
  bool looksLikeMemoryPrimaryRecallQueryForTesting(String query) {
    return _looksLikeMemoryPrimaryRecallQuery(query);
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
        normalized.contains('产品评审') ||
        normalized.contains('体验文案') ||
        normalized.contains('合同付款') ||
        normalized.contains('发票确认') ||
        normalized.contains('付款') ||
        normalized.contains('发票') ||
        normalized.contains('owner') ||
        normalized.contains('contact') ||
        normalized.contains('relationship');
  }

  bool _looksLikeIdentityOrRoutineQuery(String query) {
    final normalized = query.toLowerCase();
    return normalized.contains('常驻') ||
        normalized.contains('居住') ||
        normalized.contains('住哪') ||
        normalized.contains('哪里') ||
        normalized.contains('在哪') ||
        normalized.contains('城市') ||
        normalized.contains('周一') ||
        normalized.contains('周二') ||
        normalized.contains('周三') ||
        normalized.contains('周四') ||
        normalized.contains('周五') ||
        normalized.contains('上午') ||
        normalized.contains('下午') ||
        normalized.contains('晚上') ||
        normalized.contains('深度工作') ||
        normalized.contains('安排') ||
        normalized.contains('日程') ||
        normalized.contains('city') ||
        normalized.contains('location') ||
        normalized.contains('routine') ||
        normalized.contains('schedule');
  }

  String _augmentMemoryPrimarySearchArgsForTrace({
    required String toolName,
    required String args,
    required String? originalUserQuery,
  }) {
    final original = originalUserQuery?.trim();
    if (toolName != 'search_memory_primary' ||
        original == null ||
        original.isEmpty ||
        args.contains(original)) {
      return args;
    }
    try {
      final decoded = jsonDecode(args);
      if (decoded is Map) {
        return jsonEncode({
          ...decoded,
          'original_user_query': original,
        });
      }
    } catch (_) {
      // Fall through to a trace-only suffix for non-JSON tool argument shapes.
    }
    return '$args original_user_query=$original';
  }

  @visibleForTesting
  String augmentMemoryPrimarySearchArgsForTraceForTesting({
    required String toolName,
    required String args,
    required String? originalUserQuery,
  }) {
    return _augmentMemoryPrimarySearchArgsForTrace(
      toolName: toolName,
      args: args,
      originalUserQuery: originalUserQuery,
    );
  }

  Future<_MemoryPrimaryQuickQueryFallback?>
      _buildMemoryPrimaryQuickQueryFallback({
    required String userId,
    required String query,
  }) async {
    final results = await searchMemoryPrimaryForTool(
      userId: userId,
      query: query,
      limit: 10,
    );
    if (results.isEmpty) return null;

    final toolResult = _formatMemoryPrimaryFallbackToolResult(results);
    final answer = _formatMemoryPrimaryFallbackAnswer(query, results);
    if (answer.trim().isEmpty) return null;
    return _MemoryPrimaryQuickQueryFallback(
      query: query,
      toolResult: toolResult,
      answer: answer,
    );
  }

  String _prepareMemoryPrimaryQuickQueryFallbackResponse(
    _MemoryPrimaryQuickQueryFallback fallback, {
    required String query,
    required bool sanitizeCurrentStateAnswer,
    required bool postProcessQuickQueryAnswer,
  }) {
    var response = fallback.answer;
    if (sanitizeCurrentStateAnswer) {
      response = _sanitizeCurrentStateAnswer(response, query: query);
    }
    if (_looksLikePreferenceQuery(query)) {
      response = _sanitizeMemoryPrimaryPreferenceAnswer(response, query: query);
    }
    if (postProcessQuickQueryAnswer) {
      response = _ensureProjectNameFromQuery(response, query: query);
    }
    return response;
  }

  String _formatMemoryPrimaryFallbackToolResult(
    List<MemoryRecallResult> results,
  ) {
    final buffer = StringBuffer('<memory_primary_context>\n');
    for (final result in results) {
      final atom = result.atom;
      buffer.writeln(
        '- [${atom.id}] (${atom.type}, score=${result.totalScore.toStringAsFixed(2)}, confidence=${atom.confidence.toStringAsFixed(2)}, importance=${atom.importance}) ${atom.content}',
      );
      if (atom.entityIds.isNotEmpty) {
        buffer.writeln('  entities: ${atom.entityIds.join(', ')}');
      }
      if (atom.evidenceFactIds.isNotEmpty) {
        buffer.writeln(
          '  evidence_fact_ids: ${atom.evidenceFactIds.join(', ')}',
        );
      }
      if (result.reasons.isNotEmpty) {
        buffer.writeln('  reasons: ${result.reasons.join(', ')}');
      }
    }
    buffer.writeln('</memory_primary_context>');
    buffer.writeln('<system-reminder>');
    buffer.writeln(
      'The LLM quick-query turn failed, so this read-only fallback answered only from the Memory Primary recall results above.',
    );
    buffer.writeln('</system-reminder>');
    return buffer.toString();
  }

  String _formatMemoryPrimaryFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final relevantResults = results
        .where(
            (result) => _isRelevantMemoryPrimaryFallbackResult(query, result))
        .toList(growable: false);
    final selectedResults = relevantResults.isEmpty ? results : relevantResults;
    if (_looksLikeRelationshipQuery(query)) {
      final relationshipAnswer =
          _formatRelationshipFallbackAnswer(query, selectedResults);
      if (relationshipAnswer != null) return relationshipAnswer;
    }

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    for (final result in selectedResults.take(5)) {
      final atom = result.atom;
      final evidence = atom.evidenceFactIds.isEmpty
          ? ''
          : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）';
      buffer.writeln('- ${atom.content}$evidence');
    }
    return buffer.toString().trim();
  }

  String? _formatRelationshipFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final needsReview = _containsAny(query, const ['产品评审', '体验文案', '评审', '文案']);
    final needsPayment =
        _containsAny(query, const ['合同付款', '发票确认', '付款', '发票']);
    if (!needsReview && !needsPayment) return null;

    final review = needsReview
        ? _bestRelationshipClause(
            results,
            include: const ['产品评审', '体验文案'],
            exclude: const ['不负责'],
          )
        : null;
    final payment = needsPayment
        ? _bestRelationshipClause(
            results,
            include: const ['合同付款', '发票确认', '付款', '发票'],
            prefer: const ['Noor', '找', '由'],
          )
        : null;
    if (review == null && payment == null) return null;

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    if (review != null) {
      buffer.writeln('- 产品评审/体验文案：${review.text}${review.evidence}');
    }
    if (payment != null) {
      buffer.writeln('- 合同付款/发票确认：${payment.text}${payment.evidence}');
    }
    return buffer.toString().trim();
  }

  _RelationshipClause? _bestRelationshipClause(
    List<MemoryRecallResult> results, {
    required List<String> include,
    List<String> prefer = const [],
    List<String> exclude = const [],
  }) {
    _RelationshipClause? best;
    var bestScore = -1;
    for (final result in results) {
      final atom = result.atom;
      if (atom.type != 'relationship') continue;
      for (final clause in _relationshipClauses(atom.content)) {
        if (!_containsAny(clause, include)) continue;
        if (_containsAny(clause, exclude)) continue;
        var score = 1;
        if (_containsAny(clause, prefer)) score += 3;
        if (clause.contains('负责') || clause.contains('找')) score += 2;
        if (atom.evidenceFactIds.isNotEmpty) score += 1;
        if (score > bestScore) {
          bestScore = score;
          best = _RelationshipClause(
            text: _normalizeRelationshipClause(clause),
            evidence: atom.evidenceFactIds.isEmpty
                ? ''
                : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）',
          );
        }
      }
    }
    return best;
  }

  List<String> _relationshipClauses(String content) {
    return content
        .split(RegExp(r'[。；;\n，,]+'))
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty)
        .toList(growable: false);
  }

  String _normalizeRelationshipClause(String clause) {
    return clause.replaceFirst(RegExp(r'^(?:且|并且|另外|同时|但|而)\s*'), '');
  }

  String _limitedEvidence(List<String> evidenceFactIds) {
    final shown = evidenceFactIds.take(3).join('、');
    if (evidenceFactIds.length <= 3) return shown;
    return '$shown 等 ${evidenceFactIds.length} 条';
  }

  bool _containsAny(String text, List<String> needles) {
    final normalized = text.toLowerCase();
    return needles.any((needle) => normalized.contains(needle.toLowerCase()));
  }

  bool _isRelevantMemoryPrimaryFallbackResult(
    String query,
    MemoryRecallResult result,
  ) {
    final atom = result.atom;
    final text =
        '${atom.type} ${atom.title} ${atom.content} ${atom.entityIds.join(' ')}'
            .toLowerCase();
    bool hasAny(List<String> terms) {
      return terms.any((term) => text.contains(term.toLowerCase()));
    }

    if (_looksLikeRelationshipQuery(query)) {
      return atom.type == 'relationship' ||
          hasAny(const [
            '产品评审',
            '体验文案',
            '合同付款',
            '发票确认',
            '付款',
            '发票',
            'owner',
            '负责人',
            '负责',
          ]);
    }
    if (_looksLikeIdentityOrRoutineQuery(query)) {
      return atom.type == 'identity' ||
          atom.type == 'routine' ||
          hasAny(const [
            '常驻',
            '居住',
            '城市',
            '周一',
            '周二',
            '周三',
            '周四',
            '周五',
            '上午',
            '下午',
            '深度工作',
            '评审会',
          ]);
    }
    if (_looksLikeReportFormatPreferenceQuery(query)) {
      return atom.type.contains('preference') &&
          hasAny(const [
            '报告',
            '汇报结构',
            '最新结论',
            '结论',
            '风险',
            '下一步',
            'owner',
            '证据来源',
            '背景',
          ]);
    }
    return true;
  }

  @visibleForTesting
  Future<String?> buildMemoryPrimaryQuickQueryFallbackAnswerForTesting({
    required String userId,
    required String query,
  }) async {
    final fallback = await _buildMemoryPrimaryQuickQueryFallback(
      userId: userId,
      query: query,
    );
    return fallback?.answer;
  }

  String _sanitizeCurrentStateAnswer(String response, {required String query}) {
    var sanitized = response;
    sanitized = sanitized
        .replaceAll(
          RegExp(
            r'^\s*(?:[-*]\s*)?(?:\*\*)?风险(?:\*\*)?[：:]\s*(?:无额外风险|暂无额外风险|未见额外风险)[^\n]*$',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*(?:[-*]\s*)?(?:\*\*)?下一步(?:\*\*)?[：:]\s*继续保持[^\n]*$',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\n?\s*\*\*[^*\n]*(?:时间线|历史演变|历史背景|旧记录)[^*\n]*\*\*[:：]?\s*\n(?:\|[^\n]*\n)+',
            multiLine: true,
          ),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'\n?\s*\d+\.\s*(?:\*\*)?(?:历史演变|历史背景|旧记录|原始记录)(?:\*\*)?[:：][\s\S]*?(?=\n\s*\d+\.\s|\n\s*#{1,6}\s|\z)',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*(?:\*\*)?(?:历史背景|旧记录|原始记录)(?:\*\*)?[:：][^\n]*(?:\n\s*[-*]\s*(?:最初|原先|原来|此前|之前|先前|早期|旧)[^\n]*)*',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*(?:最初|原先|原来|此前|之前|先前|早期|旧)[^\n]*(?:owner|负责人|负责|覆盖|作废|失效)[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*[^\n]*(?:初期|最初|原先|原来|此前|之前|先前|早期|历史|旧)[^\n]*(?:owner|负责人|负责|验收|接口|口径|数据抽样)[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*[^\n]*(?:仅|只)[^\n]*(?:负责|适用)[^\n]*(?:历史|旧)[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*(?:\d+\s*[月日]\s*)?[^\n]*(?:曾记录|曾有|历史|早期|原先|原来|旧)[^\n]*(?:owner|负责人|负责|说法|覆盖|作废|失效)[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'[^\n。；;]*将\s*(?:owner|负责人|负责方)[^。；;\n]*?更正为\s*([^，。；;\n]+)[^。；;\n]*[。；;]?',
        caseSensitive: false,
      ),
      (match) => '当前 owner 为 ${match.group(1)?.trim() ?? ''}。',
    );
    for (final pattern in [
      RegExp(
        r'(?:之前|此前|先前)关于[^。；;\n]*?(?:覆盖|作废|失效|不准确|superseded)[^。；;\n]*[。；;]?',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:此前|之前|先前|曾经|原先|原来|早期|旧记录)[^。；;\n]{0,120}?(?:覆盖|作废|失效|不准确|superseded)[^。；;\n]*[。；;]?',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:这条记录|该记录|此记录|该更正|此信息|此条目)[^。；;\n]{0,40}?(?:覆盖|作废|失效|不准确|superseded)[^。；;\n]*?(?:早期|之前|此前|先前|旧)[^。；;\n]*[。；;]?',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:覆盖|作废|失效|不准确|superseded)[^。；;\n]*?(?:之前|此前|先前|早期|旧)[^。；;\n]*[。；;]?',
        caseSensitive: false,
      ),
    ]) {
      sanitized = sanitized.replaceAll(pattern, '此前相关旧说法已被覆盖。');
    }
    sanitized = sanitized
        .replaceAll(
          RegExp(r'(。?此前相关旧说法已被覆盖。)+'),
          '。此前相关旧说法已被覆盖。',
        )
        .replaceAll('并**。此前相关旧说法已被覆盖。', '此前相关旧说法已被覆盖。')
        .replaceAll('且**。此前相关旧说法已被覆盖。', '此前相关旧说法已被覆盖。')
        .replaceAll('并。此前相关旧说法已被覆盖。', '此前相关旧说法已被覆盖。')
        .replaceAll('且。此前相关旧说法已被覆盖。', '此前相关旧说法已被覆盖。')
        .replaceAll('，。此前相关旧说法已被覆盖。', '，此前相关旧说法已被覆盖。')
        .replaceAll('：。此前相关旧说法已被覆盖。', '：此前相关旧说法已被覆盖。')
        .replaceAll(':。此前相关旧说法已被覆盖。', ': 此前相关旧说法已被覆盖。')
        .trim();
    return sanitized;
  }

  @visibleForTesting
  String sanitizeCurrentStateAnswerForTesting(
    String response, {
    required String query,
  }) {
    return _sanitizeCurrentStateAnswer(response, query: query);
  }

  @visibleForTesting
  String sanitizeMemoryPrimaryPreferenceAnswerForTesting(
    String response, {
    required String query,
  }) {
    return _sanitizeMemoryPrimaryPreferenceAnswer(response, query: query);
  }

  @visibleForTesting
  String ensureProjectNameFromQueryForTesting(
    String response, {
    required String query,
  }) {
    return _ensureProjectNameFromQuery(response, query: query);
  }

  String _ensureProjectNameFromQuery(String response, {required String query}) {
    final projectNames = _extractProjectNamesFromQuery(query);
    if (projectNames.isEmpty) return response;
    final missing = projectNames
        .where((projectName) => !response.contains(projectName))
        .toList(growable: false);
    if (missing.isEmpty) return response;
    return '${missing.join('、')}：$response';
  }

  String _sanitizeMemoryPrimaryPreferenceAnswer(
    String response, {
    required String query,
  }) {
    if (!_looksLikePreferenceQuery(query)) return response;
    var sanitized = response;
    if (_looksLikeReportFormatPreferenceQuery(query)) {
      sanitized = _sanitizeReportFormatPreferenceAnswer(sanitized);
    }
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'((?:\*\*)?owner(?:\*\*)?\s*[—\-:：]\s*)使用(?:\*\*)?当前\s*owner(?:\*\*)?，?不使用历史\s*owner',
        caseSensitive: false,
      ),
      (match) => '${match.group(1) ?? ''}owner',
    );
    sanitized = sanitized
        .replaceAll(
          RegExp(
            r'，?不使用历史\s*owner',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'使用(?:\*\*)?当前\s*owner(?:\*\*)?',
            caseSensitive: false,
          ),
          'owner',
        )
        .replaceAll(
          RegExp(
            r'（[^）\n]*(?:当前(?:所有者|负责人)|历史(?:旧)?(?:所有者|负责人)|旧(?:所有者|负责人))[^）\n]*）',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'当前的负责人'), '负责人')
        .replaceAll(RegExp(r'当前负责人'), '负责人')
        .replaceAll(
          RegExp(
            r'^\s*(?:\*\*)?关于\s*owner(?:\*\*)?[:：][^\n]*(?:旧\s*owner|历史\s*owner|当前\s*owner|长期\s*owner|旧(?:所有者|负责人)|历史(?:旧)?(?:所有者|负责人)|当前(?:所有者|负责人))[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*[^\n]*(?:旧\s*owner|历史\s*owner|当前\s*owner|长期\s*owner|旧(?:所有者|负责人)|历史(?:旧)?(?:所有者|负责人)|当前(?:所有者|负责人))[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*[-*]\s*(?:如有|如果有|若有)?信息?冲突[^\n]*(?:最新结论|latest conclusion)[^\n]*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return sanitized;
  }

  bool _looksLikeReportFormatPreferenceQuery(String query) {
    final normalized = query.toLowerCase();
    return _looksLikePreferenceQuery(query) &&
        (normalized.contains('报告') ||
            normalized.contains('report') ||
            normalized.contains('格式') ||
            normalized.contains('format'));
  }

  String _sanitizeReportFormatPreferenceAnswer(String response) {
    var sanitized = response;
    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*(?:\*\*)?(?:额外规则|补充偏好)(?:\*\*)?[：:]?\s*$',
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'^\s*[-*]\s*[^\n]*(?:OCR|截图|失败恢复|回滚演练|口径一致)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'^(\s*(?:[-*]\s*)?(?:\d+\.\s*)?(?:\*\*)?(?:风险|下一步|Owner|owner)(?:\*\*)?)\s*[：:]\s*([^\n]+)$',
        multiLine: true,
      ),
      (match) {
        final label = match.group(1) ?? '';
        final value = match.group(2) ?? '';
        final shouldDropValue = RegExp(
          r'确保|便于|清晰|一致|实际撰写|严格按|继续保持|后续迭代|复盘|当前\s*Project|当前.*owner|owner\s*是|负责|由.+负责|无额外风险|暂无额外风险|未见额外风险',
          caseSensitive: false,
        ).hasMatch(value);
        return shouldDropValue ? label : match.group(0)!;
      },
    );
    return sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  List<String> _extractProjectNamesFromQuery(String query) {
    for (final pattern in [
      RegExp(r'(?:写|做|生成|撰写)\s+(.+?)\s*相关(?:技术|项目)?(?:报告|总结)'),
      RegExp(r'(.+?)\s*相关(?:技术|项目)?(?:报告|总结)'),
      RegExp(r'(.+?)\s*(?:当前|现在|最新).{0,20}(?:owner|负责人|负责|导出灰度)'),
      RegExp(r'(.+?)\s*(?:的)?导出灰度.{0,20}(?:owner|负责人|负责)'),
    ]) {
      final match = pattern.firstMatch(query);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty) continue;
      final cleaned = value
          .replaceAll(
            RegExp(r'^(请问|请告诉我|告诉我|查询|查一下|以后|以后给我|给我)\s*'),
            '',
          )
          .replaceAll(RegExp(r'[？?。,.，；;:：]+$'), '')
          .trim();
      final projectNames = _splitProjectNameCandidates(cleaned);
      if (projectNames.isNotEmpty) return projectNames;
    }
    return const [];
  }

  List<String> _splitProjectNameCandidates(String value) {
    final rawParts = value
        .split(RegExp(r'\s*(?:或|和|与|、|/|,|，)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final parts = rawParts.isEmpty ? [value.trim()] : rawParts;
    final candidates = <String>[];
    for (var part in parts) {
      part = part
          .replaceAll(RegExp(r'^(以后|以后给我|给我|请|请给我)\s*'), '')
          .replaceAll(RegExp(r'\s*(?:时|的时候)$'), '')
          .trim();
      if (part.length < 2 || part.length > 40) continue;
      if (part.contains(' ')) {
        candidates.add(part);
      } else if (RegExp(r'[\u4e00-\u9fff]').hasMatch(part)) {
        candidates.add(part);
      }
    }
    return candidates.toSet().toList(growable: false);
  }

  // --- Session Helpers (Recreated from chat.dart to be independent) ---

  /// Check whether a session file has `is_custom_agent: true`.
  Future<bool> _isCustomAgentSession(String userId, String sessionId) async {
    try {
      final sessionFile = _getSessionFilePath(userId, sessionId);
      if (!await sessionFile.exists()) return false;
      final content = await sessionFile.readAsString();
      final doc = loadYaml(content);
      final data = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
      return data['is_custom_agent'] == true;
    } catch (e) {
      _logger.warning('Failed to read session metadata: $e');
    }
    return false;
  }

  Future<String> _createSession(
    String userId,
    String? agentName,
    List<Map<String, dynamic>> initialContent, {
    bool isQuickQuery = false,
    DateTime? createdAt,
  }) async {
    final uuidStr = _uuid.v4();
    final sessionId = agentName != null && agentName.isNotEmpty
        ? '${agentName}_$uuidStr'
        : uuidStr;
    final now = createdAt ?? DateTime.now();

    String? title;
    for (final item in initialContent) {
      if (item['type'] == 'text' && item['text'] != null) {
        final text = item['text'] as String;
        title = text.length > 50 ? text.substring(0, 50) : text;
        break;
      }
    }

    final sessionData = {
      'session_id': sessionId,
      'agent_name': agentName,
      'title': title ?? 'New Chat',
      'created_at': now.toIso8601String(),
      'created_at_local': formatLocalDateTimeWithZone(now),
      'created_at_unix_seconds': unixSecondsFromDateTime(now),
      'updated_at': now.toIso8601String(),
      'updated_at_local': formatLocalDateTimeWithZone(now),
      'updated_at_unix_seconds': unixSecondsFromDateTime(now),
      'is_quick_query': isQuickQuery,
      'messages': <dynamic>[],
    };

    final sessionFile = _getSessionFilePath(userId, sessionId);
    final parentDir = sessionFile.parent;
    await parentDir.create(recursive: true);

    await _fileService.writeYamlFile(sessionFile.path, sessionData);
    return sessionId;
  }

  Future<Map<String, dynamic>?> _addMessageToSession(
    String userId,
    String sessionId,
    String role,
    List<Map<String, dynamic>> content, {
    Map<String, dynamic>? usage,
    List<Map<String, String>>? refs,
    bool? isQuickQuery,
    DateTime? timestamp,
  }) async {
    final sessionFile = _getSessionFilePath(userId, sessionId);
    if (!await sessionFile.exists()) return null;

    final fileContent = await sessionFile.readAsString();
    final doc = loadYaml(fileContent);
    final sessionData = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
    _backfillSessionTimeContext(sessionData);

    final messageTime = timestamp ?? DateTime.now();
    final messageDict = {
      'role': role,
      'content': content,
      if (usage != null) 'usage': usage,
      if (refs != null) 'refs': refs,
      'timestamp': messageTime.toIso8601String(),
      'local_time': formatLocalDateTimeWithZone(messageTime),
      'unix_seconds': unixSecondsFromDateTime(messageTime),
    };

    final messages = (sessionData['messages'] as List<dynamic>? ?? [])
        .map(_backfillMessageTimeContext)
        .toList()
      ..add(messageDict);
    sessionData['messages'] = messages;

    // Update cumulative session usage
    if (usage != null) {
      final currentTotal =
          sessionData['total_usage'] as Map<String, dynamic>? ??
              {
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'cached_tokens': 0,
                'total_tokens': 0,
                'total_cost': 0.0,
              };

      sessionData['total_usage'] = {
        'prompt_tokens': (currentTotal['prompt_tokens'] as int? ?? 0) +
            (usage['prompt_tokens'] as int? ?? 0),
        'completion_tokens': (currentTotal['completion_tokens'] as int? ?? 0) +
            (usage['completion_tokens'] as int? ?? 0),
        'cached_tokens': (currentTotal['cached_tokens'] as int? ?? 0) +
            (usage['cached_tokens'] as int? ?? 0),
        'total_tokens': (currentTotal['total_tokens'] as int? ?? 0) +
            (usage['total_tokens'] as int? ?? 0),
        'total_cost': (currentTotal['total_cost'] as double? ?? 0.0) +
            (usage['total_cost'] as double? ?? 0.0),
      };
    }

    // Update session-level mode flag so history can restore it
    if (isQuickQuery != null) {
      sessionData['is_quick_query'] = isQuickQuery;
    }

    final updatedAt = DateTime.now();
    sessionData['updated_at'] = updatedAt.toIso8601String();
    sessionData['updated_at_local'] = formatLocalDateTimeWithZone(updatedAt);
    sessionData['updated_at_unix_seconds'] = unixSecondsFromDateTime(updatedAt);

    await _fileService.writeYamlFile(sessionFile.path, sessionData);
    return sessionData['total_usage'] as Map<String, dynamic>?;
  }

  File _getSessionFilePath(String userId, String sessionId) {
    final sessionsPath = _fileService.getChatSessionsPath(userId);
    return File(p.join(sessionsPath, '$sessionId.yaml'));
  }

  void _backfillSessionTimeContext(Map<String, dynamic> sessionData) {
    final createdAt = tryParseDateTime(sessionData['created_at']);
    if (createdAt != null) {
      sessionData['created_at_local'] ??= formatLocalDateTimeWithZone(
        createdAt,
      );
      sessionData['created_at_unix_seconds'] ??= unixSecondsFromDateTime(
        createdAt,
      );
    }

    final updatedAt = tryParseDateTime(sessionData['updated_at']);
    if (updatedAt != null) {
      sessionData['updated_at_local'] ??= formatLocalDateTimeWithZone(
        updatedAt,
      );
      sessionData['updated_at_unix_seconds'] ??= unixSecondsFromDateTime(
        updatedAt,
      );
    }
  }

  dynamic _backfillMessageTimeContext(dynamic message) {
    if (message is! Map<String, dynamic>) {
      return message;
    }

    final parsed = tryParseDateTime(message['timestamp']);
    if (parsed == null) {
      return message;
    }

    return {
      ...message,
      'local_time':
          message['local_time'] ?? formatLocalDateTimeWithZone(parsed),
      'unix_seconds':
          message['unix_seconds'] ?? unixSecondsFromDateTime(parsed),
    };
  }
}

class _MemoryPrimaryQuickQueryFallback {
  final String query;
  final String toolResult;
  final String answer;

  const _MemoryPrimaryQuickQueryFallback({
    required this.query,
    required this.toolResult,
    required this.answer,
  });
}

class _RelationshipClause {
  final String text;
  final String evidence;

  const _RelationshipClause({
    required this.text,
    required this.evidence,
  });
}
