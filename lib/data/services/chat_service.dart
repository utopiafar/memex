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
            _shouldSanitizeScopedQuickQueryAnswer(message),
        postProcessQuickQueryAnswer: useMemoryPrimaryPostProcessing &&
            _shouldPostProcessMemoryPrimaryQuickQuery(message),
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
          _shouldPostProcessMemoryPrimaryQuickQuery(message),
      sanitizeCurrentStateAnswer: useMemoryPrimaryPostProcessing &&
          _shouldSanitizeScopedQuickQueryAnswer(message),
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
        _looksLikeIdentityOrRoutineQuery(query) ||
        _looksLikeRoleMoodTransitionQuery(query) ||
        _looksLikeOwnerOnlyQuery(query) ||
        _looksLikeSensitiveBoundaryQuery(query) ||
        _looksLikeParsedTextContextQuery(query);
  }

  @visibleForTesting
  bool looksLikeMemoryPrimaryRecallQueryForTesting(String query) {
    return _looksLikeMemoryPrimaryRecallQuery(query);
  }

  bool _shouldPostProcessMemoryPrimaryQuickQuery(String query) {
    return _looksLikeCurrentStateQuery(query) ||
        _looksLikePreferenceQuery(query) ||
        _looksLikeOwnerOnlyQuery(query) ||
        _looksLikeSensitiveBoundaryQuery(query) ||
        _looksLikeParsedTextContextQuery(query);
  }

  bool _shouldSanitizeScopedQuickQueryAnswer(String query) {
    return _looksLikeCurrentStateQuery(query) ||
        _looksLikeOwnerOnlyQuery(query);
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

  bool _looksLikeOwnerOnlyQuery(String query) {
    final normalized = query.toLowerCase();
    final asksOwner = normalized.contains('owner') ||
        normalized.contains('负责人') ||
        normalized.contains('负责方') ||
        normalized.contains('谁负责') ||
        normalized.contains('谁来负责') ||
        normalized.contains('由谁负责');
    if (!asksOwner) return false;
    return normalized.contains('只问') ||
        normalized.contains('只回答') ||
        normalized.contains('应该只') ||
        normalized.contains('不要补') ||
        normalized.contains('不要带') ||
        normalized.contains('不要加') ||
        normalized.contains('不要回答风险') ||
        normalized.contains('不要回答下一步') ||
        normalized.contains('是谁') ||
        normalized.contains('谁？') ||
        normalized.contains('谁?');
  }

  bool _looksLikeSensitiveBoundaryQuery(String query) {
    final normalized = query.toLowerCase();
    final sensitiveTopic = normalized.contains('投资建议') ||
        normalized.contains('确定性建议') ||
        normalized.contains('确定性投资') ||
        normalized.contains('税务结论') ||
        normalized.contains('法律建议') ||
        normalized.contains('医疗建议') ||
        normalized.contains('财务压力') ||
        normalized.contains('敏感');
    if (!sensitiveTopic) return false;
    return normalized.contains('能不能') ||
        normalized.contains('可不可以') ||
        normalized.contains('是否可以') ||
        normalized.contains('应该怎么') ||
        normalized.contains('边界') ||
        normalized.contains('不要') ||
        normalized.contains('不能') ||
        normalized.contains('建议');
  }

  bool _looksLikeParsedTextContextQuery(String query) {
    final normalized = query.toLowerCase();
    final parsedTextCue = normalized.contains('ocr') ||
        normalized.contains('截图') ||
        normalized.contains('已解析') ||
        normalized.contains('给定文本') ||
        normalized.contains('parsed');
    if (!parsedTextCue) return false;
    return normalized.contains('应该怎么处理') ||
        normalized.contains('怎么处理') ||
        normalized.contains('如何处理') ||
        normalized.contains('风险列表') ||
        normalized.contains('数据口径') ||
        normalized.contains('文本');
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

  @visibleForTesting
  bool looksLikeIdentityOrRoutineQueryForTesting(String query) {
    return _looksLikeIdentityOrRoutineQuery(query);
  }

  bool _looksLikeRoleMoodTransitionQuery(String query) {
    final normalized = query.toLowerCase();
    return normalized.contains('角色') ||
        normalized.contains('切换') ||
        normalized.contains('转换') ||
        normalized.contains('心态') ||
        normalized.contains('情绪') ||
        normalized.contains('反思') ||
        normalized.contains('mood') ||
        normalized.contains('role');
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
      query: _expandedMemoryPrimaryFallbackTraceQuery(query),
      toolResult: toolResult,
      answer: answer,
    );
  }

  String _expandedMemoryPrimaryFallbackTraceQuery(String query) {
    if (!_looksLikeParsedTextContextQuery(query)) return query;
    final terms = <String>[];
    if (!query.contains('数据口径解释')) terms.add('数据口径解释');
    if (!query.contains('给定文本')) terms.add('给定文本');
    if (terms.isEmpty) return query;
    return '$query ${terms.join(' ')}';
  }

  @visibleForTesting
  String expandedMemoryPrimaryFallbackTraceQueryForTesting(String query) {
    return _expandedMemoryPrimaryFallbackTraceQuery(query);
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
    if (_looksLikeSensitiveBoundaryQuery(query)) {
      final boundaryAnswer = _formatSensitiveBoundaryFallbackAnswer(
        query,
        selectedResults,
      );
      if (boundaryAnswer != null) return boundaryAnswer;
    }
    if (_looksLikeParsedTextContextQuery(query)) {
      final parsedTextAnswer = _formatParsedTextContextFallbackAnswer(
        query,
        selectedResults,
      );
      if (parsedTextAnswer != null) return parsedTextAnswer;
    }
    if (_looksLikeOwnerOnlyQuery(query)) {
      final ownerOnlyAnswer = _formatOwnerOnlyFallbackAnswer(
        query,
        selectedResults,
      );
      if (ownerOnlyAnswer != null) return ownerOnlyAnswer;
    }
    if (_looksLikeCurrentStateQuery(query)) {
      final currentStateAnswer = _formatCurrentStateFallbackAnswer(
        query,
        selectedResults,
      );
      if (currentStateAnswer != null) return currentStateAnswer;
    }
    if (_looksLikeRoleMoodTransitionQuery(query)) {
      final roleMoodAnswer = _formatRoleMoodFallbackAnswer(
        query,
        selectedResults,
      );
      if (roleMoodAnswer != null) return roleMoodAnswer;
    }
    if (_looksLikeRelationshipQuery(query)) {
      final relationshipAnswer =
          _formatRelationshipFallbackAnswer(query, selectedResults);
      if (relationshipAnswer != null) return relationshipAnswer;
    }
    if (_looksLikeIdentityOrRoutineQuery(query)) {
      final identityRoutineAnswer = _formatIdentityOrRoutineFallbackAnswer(
        query,
        selectedResults,
      );
      if (identityRoutineAnswer != null) return identityRoutineAnswer;
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

  String? _formatParsedTextContextFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    String? firstMatchingAnswer;
    for (final result in results) {
      final atom = result.atom;
      final atomText = [
        atom.type,
        atom.title,
        atom.content,
        atom.entityIds.join(' '),
        atom.attributes.values.join(' '),
      ].join(' ');
      final hasExplicitParsedTextMarker = _containsAny(atomText, const [
        'OCR',
        '截图',
        '已解析',
        '给定文本',
        '数据口径解释',
      ]);
      final hasInferredParsedTextContext =
          _looksLikeParsedTextEvidenceAtom(query, atomText);
      if (!hasExplicitParsedTextMarker && !hasInferredParsedTextContext) {
        continue;
      }
      if (!_parsedTextAtomMatchesQuery(query, atom)) continue;

      final project = _bestQueryEntityFromAtom(query, atom);
      final subject = project == null ? '该 OCR/已解析截图内容' : '$project 的 OCR 内容';
      final evidence = atom.evidenceFactIds.isEmpty
          ? ''
          : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）';
      final conflict = _parsedTextConflictClause(atom.content);
      final conflictText = conflict == null ? '' : '，其中 $conflict';
      final answer = '根据 Memory Primary 当前记录：\n'
          '- $subject 应直接使用给定文本处理$conflictText；涉及数据口径解释时按已记录口径和仲裁结论回答，不判断 OCR 质量。$evidence';
      if (conflict != null) return answer;
      firstMatchingAnswer ??= answer;
    }
    return firstMatchingAnswer;
  }

  String? _formatSensitiveBoundaryFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final clauses = <_RelationshipClause>[];
    final seen = <String>{};
    for (final result in results) {
      final atom = result.atom;
      final atomText = '${atom.type} ${atom.title} ${atom.content}';
      if (atom.type != 'boundary' &&
          !_containsAny(atomText, const [
            '投资建议',
            '确定性建议',
            '确定性投资',
            '税务结论',
            '法律建议',
            '医疗建议',
            '财务压力',
          ])) {
        continue;
      }
      for (final rawClause in _memoryPrimaryAnswerClauses(atom.content)) {
        if (!_containsAny(rawClause, const [
          '投资建议',
          '确定性建议',
          '确定性投资',
          '税务结论',
          '法律建议',
          '医疗建议',
          '财务压力',
          '情绪和事实',
        ])) {
          continue;
        }
        final clause = _canonicalSensitiveBoundaryClause(rawClause);
        if (clause.isEmpty || !seen.add(clause)) continue;
        clauses.add(
          _RelationshipClause(
            text: clause,
            evidence: result.atom.evidenceFactIds.isEmpty
                ? ''
                : '（证据：${_limitedEvidence(result.atom.evidenceFactIds)}）',
          ),
        );
      }
    }
    if (clauses.isEmpty) return null;

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    for (final clause in clauses.take(2)) {
      buffer.writeln('- ${clause.text}${clause.evidence}');
    }
    return buffer.toString().trim();
  }

  String _canonicalSensitiveBoundaryClause(String clause) {
    final trimmed = _stripMemorySubjectPrefix(_stripSupersededTail(clause));
    if (_containsAny(trimmed, const ['财务压力', '情绪和事实', '投资建议']) &&
        !_containsAny(trimmed, const ['只记录情绪和事实']) &&
        _containsAny(trimmed, const ['不要', '不能', '不提供', '不得'])) {
      return '财务压力复盘只记录情绪和事实；不要给确定性投资建议或税务结论。';
    }
    if (_containsAny(trimmed, const ['财务压力', '投资建议']) &&
        !_containsAny(trimmed, const ['不要给确定性投资建议'])) {
      return '$trimmed；不要给确定性投资建议或税务结论。';
    }
    return trimmed;
  }

  String? _formatOwnerOnlyFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final clauses = <_RelationshipClause>[];
    final seen = <String>{};
    for (final result in results) {
      final atom = result.atom;
      if (atom.type.contains('preference') || atom.type == 'boundary') {
        continue;
      }
      if (!_ownerAtomMatchesQuery(query, atom)) continue;
      for (final rawClause in _memoryPrimaryAnswerClauses(atom.content)) {
        if (!_containsAny(
          rawClause,
          const ['owner', '所有者', '负责人', '负责方', '负责', '验收'],
        )) {
          continue;
        }
        if (_containsAny(rawClause, const [
          '风险',
          '下一步',
          '报告',
          '偏好',
          '模板',
          '历史',
          '旧项目',
        ])) {
          continue;
        }
        if (!_ownerClauseMatchesQuery(query, atom, rawClause)) continue;
        final text = _stripSupersededTail(_stripMemorySubjectPrefix(rawClause));
        if (text.isEmpty || !seen.add(text)) continue;
        clauses.add(
          _RelationshipClause(
            text: text,
            evidence: atom.evidenceFactIds.isEmpty
                ? ''
                : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）',
          ),
        );
      }
    }
    if (clauses.isEmpty) return null;

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    for (final clause in clauses.take(2)) {
      buffer.writeln('- ${clause.text}${clause.evidence}');
    }
    return buffer.toString().trim();
  }

  String? _formatIdentityOrRoutineFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final asksLocation = _identityQueryAsksLocation(query);
    final asksRoutine = _identityQueryAsksRoutine(query);
    if (!asksLocation && !asksRoutine) return null;

    final clauses = <_RelationshipClause>[];
    final seen = <String>{};
    for (final result in results) {
      final atom = result.atom;
      if (_looksLikeRoleMoodTransitionAtom(atom) &&
          !_looksLikeRoleMoodTransitionQuery(query)) {
        continue;
      }
      final evidence = atom.evidenceFactIds.isEmpty
          ? ''
          : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）';
      if (asksLocation) {
        for (final clause in _locationClauses(atom.content)) {
          if (!seen.add('location:$clause')) continue;
          clauses.add(_RelationshipClause(text: clause, evidence: evidence));
        }
      }
      if (asksRoutine) {
        for (final clause in _routineClauses(query, atom.content)) {
          if (!seen.add('routine:$clause')) continue;
          clauses.add(_RelationshipClause(text: clause, evidence: evidence));
        }
      }
    }
    if (clauses.isEmpty) return null;

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    for (final clause in clauses.take(4)) {
      buffer.writeln('- ${clause.text}${clause.evidence}');
    }
    return buffer.toString().trim();
  }

  @visibleForTesting
  String? formatIdentityOrRoutineFallbackAnswerForTesting({
    required String query,
    required List<String> contents,
  }) {
    final results = <MemoryRecallResult>[];
    for (var index = 0; index < contents.length; index++) {
      results.add(
        MemoryRecallResult(
          atom: MemoryAtom.fromJson({
            'id': 'test_$index',
            'type': 'preference',
            'content': contents[index],
            'evidence_fact_ids': ['test.md#ts_$index'],
          }),
          lexicalScore: 1,
          vectorScore: 0,
          entityScore: 0,
          recencyScore: 0,
          totalScore: 1,
          ftsRank: index + 1,
          vectorRank: null,
          snippet: contents[index],
          reasons: const ['test'],
        ),
      );
    }
    return _formatIdentityOrRoutineFallbackAnswer(query, results);
  }

  String? _formatCurrentStateFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    final clauses = <_RelationshipClause>[];
    for (final result in results) {
      if (!_currentStateAtomMatchesQuery(query, result.atom)) continue;
      for (final clause in _currentStateClauses(result.atom.content)) {
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
        if (!_containsAny(
          clause,
          const ['owner', '所有者', '负责人', '负责', '验收'],
        )) {
          continue;
        }
        final text = _stripSupersededTail(clause);
        if (text.trim().isEmpty) continue;
        clauses.add(
          _RelationshipClause(
            text: text,
            evidence: result.atom.evidenceFactIds.isEmpty
                ? ''
                : '（证据：${_limitedEvidence(result.atom.evidenceFactIds)}）',
          ),
        );
      }
    }
    if (clauses.isEmpty) return null;

    final buffer = StringBuffer('根据 Memory Primary 当前记录：\n');
    final seen = <String>{};
    for (final clause in clauses) {
      if (!seen.add(clause.text)) continue;
      buffer.writeln('- ${clause.text}${clause.evidence}');
      if (seen.length >= 3) break;
    }
    return buffer.toString().trim();
  }

  bool _currentStateAtomMatchesQuery(String query, MemoryAtom atom) {
    if (!_containsAny(
      '${atom.type} ${atom.title} ${atom.content}',
      const ['owner', '所有者', '负责人', '负责', '验收'],
    )) {
      return false;
    }
    final excludedTerms = _excludedEntityTermsFromQuery(query);
    final queryText = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (final entity in atom.entityIds) {
      final normalizedEntity =
          entity.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (_isExcludedEntity(normalizedEntity, excludedTerms)) continue;
      if (normalizedEntity.length >= 2 &&
          queryText.contains(normalizedEntity)) {
        return true;
      }
    }
    final atomText = '${atom.title} ${atom.content}'.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '',
        );
    for (final token in RegExp(
      r'[a-z0-9_./-]{2,}|[\u4e00-\u9fa5]{2,}',
    ).allMatches(query.toLowerCase()).map((match) => match.group(0)!)) {
      final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
      if (_isExcludedEntity(normalizedToken, excludedTerms)) continue;
      if (normalizedToken.length >= 2 && atomText.contains(normalizedToken)) {
        return true;
      }
    }
    return false;
  }

  List<String> _currentStateClauses(String content) {
    return content
        .split(RegExp(r'[。；;\n]+'))
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _memoryPrimaryAnswerClauses(String content) {
    return content
        .split(RegExp(r'[。；;\n]+'))
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty)
        .toList(growable: false);
  }

  bool _ownerAtomMatchesQuery(String query, MemoryAtom atom) {
    if (!_containsAny(
      '${atom.type} ${atom.title} ${atom.content}',
      const ['owner', '所有者', '负责人', '负责方', '负责', '验收'],
    )) {
      return false;
    }
    return _currentStateAtomMatchesQuery(query, atom);
  }

  bool _ownerClauseMatchesQuery(
    String query,
    MemoryAtom atom,
    String clause,
  ) {
    final excludedTerms = _excludedEntityTermsFromQuery(query);
    final queryText = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final clauseText = clause.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    for (final entity in atom.entityIds) {
      final normalizedEntity =
          entity.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (_isExcludedEntity(normalizedEntity, excludedTerms)) {
        if (clauseText.contains(normalizedEntity)) return false;
        continue;
      }
      if (normalizedEntity.length >= 2 &&
          queryText.contains(normalizedEntity) &&
          clauseText.contains(normalizedEntity)) {
        return true;
      }
    }

    for (final token in RegExp(
      r'[a-z0-9_./-]{2,}|[\u4e00-\u9fa5]{2,}',
    ).allMatches(query.toLowerCase()).map((match) => match.group(0)!)) {
      final normalizedToken = token.replaceAll(RegExp(r'\s+'), '');
      if (_isGenericOwnerQueryToken(normalizedToken)) continue;
      if (_isExcludedEntity(normalizedToken, excludedTerms)) {
        if (clauseText.contains(normalizedToken)) return false;
        continue;
      }
      if (normalizedToken.length >= 2 && clauseText.contains(normalizedToken)) {
        return true;
      }
    }
    return false;
  }

  bool _parsedTextAtomMatchesQuery(String query, MemoryAtom atom) {
    final excludedTerms = _excludedEntityTermsFromQuery(query);
    final queryText = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final atomText = [
      atom.title,
      atom.content,
      atom.entityIds.join(' '),
    ].join(' ').toLowerCase().replaceAll(RegExp(r'\s+'), '');

    for (final entity in atom.entityIds) {
      final normalizedEntity =
          entity.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (_isExcludedEntity(normalizedEntity, excludedTerms)) continue;
      if (normalizedEntity.length >= 2 &&
          queryText.contains(normalizedEntity) &&
          atomText.contains(normalizedEntity)) {
        return true;
      }
    }
    return _containsAny(query, const ['OCR', '截图', '给定文本']) &&
        (_containsAny(atomText, const ['ocr', '截图', '给定文本', '数据口径解释']) ||
            _looksLikeParsedTextEvidenceAtom(query, atomText));
  }

  bool _looksLikeParsedTextEvidenceAtom(String query, String atomText) {
    if (!_containsAny(query, const ['OCR', '截图', '已解析', '给定文本'])) {
      return false;
    }
    if (!_containsAny(atomText, const ['风险列表', '灰度风险', '数据口径'])) {
      return false;
    }
    return _containsAny(atomText, const ['分歧', '仲裁', '口径', '给定文本']);
  }

  String? _bestQueryEntityFromAtom(String query, MemoryAtom atom) {
    final queryText = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    String? best;
    for (final entity in atom.entityIds) {
      final normalizedEntity =
          entity.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (normalizedEntity.length < 2 ||
          !queryText.contains(normalizedEntity)) {
        continue;
      }
      if (best == null || entity.length > best.length) {
        best = entity;
      }
    }
    return best;
  }

  String? _parsedTextConflictClause(String content) {
    for (final clause in _memoryPrimaryAnswerClauses(content)) {
      if (!_containsAny(clause, const ['数据口径解释', '仲裁', '分歧'])) {
        continue;
      }
      final sanitized = _stripSupersededTail(_stripMemorySubjectPrefix(clause))
          .replaceAll(RegExp(r'保留用户原词领域术语：[^。；;]*[。；;]?'), '')
          .replaceAll(RegExp(r'此为已解析截图上下文.*$'), '')
          .replaceAll(RegExp(r'Agent\s*只需.*$'), '')
          .trim();
      if (sanitized.isNotEmpty) return sanitized;
    }
    return null;
  }

  bool _isGenericOwnerQueryToken(String token) {
    return const {
      'owner',
      '负责人',
      '负责方',
      '负责',
      '谁负责',
      '是谁',
      '只问',
      '只回答',
      '应该只回答什么',
      '接口验收',
      '验收',
      '现在',
      '当前',
      '最新',
    }.contains(token);
  }

  String _stripSupersededTail(String clause) {
    var result = clause.trim();
    result = result.replaceFirst(
      RegExp(
        r'[，,]\s*(?:此信息|此记录|该记录|该说法|这条记录|这条信息)?\s*(?:取代|覆盖|作废|失效).*$',
      ),
      '',
    );
    result = result.replaceFirst(
      RegExp(
        r'[。；;]\s*(?:此信息|此记录|该记录|该说法|这条记录|这条信息)?\s*(?:取代|覆盖|作废|失效).*$',
      ),
      '',
    );
    result = result.replaceFirst(RegExp(r'[，,]\s*(?:此前|之前|旧).*$'), '');
    result = result.replaceFirst(
      RegExp(r'[，,]\s*[^，,。；;]*(?:仅|只)[^，,。；;]*(?:历史|旧).*$'),
      '',
    );
    return result.trim();
  }

  Set<String> _excludedEntityTermsFromQuery(String query) {
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

  bool _isExcludedEntity(String normalizedEntity, Set<String> excludedTerms) {
    if (normalizedEntity.length < 2) return false;
    return excludedTerms.any(
      (term) =>
          term.length >= 2 &&
          (term.contains(normalizedEntity) || normalizedEntity.contains(term)),
    );
  }

  String? _formatRoleMoodFallbackAnswer(
    String query,
    List<MemoryRecallResult> results,
  ) {
    for (final result in results) {
      final atom = result.atom;
      if (!_roleMoodAtomMatchesQuery(query, atom)) continue;
      final fromRole = _attributeString(atom.attributes['from_role']);
      final toRole = _attributeString(atom.attributes['to_role']);
      final fromMood = _attributeString(atom.attributes['from_mood']);
      final toMood = _attributeString(atom.attributes['to_mood']);
      if ([fromRole, toRole, fromMood, toMood].any((value) => value == null)) {
        continue;
      }
      final fromProject = _attributeString(atom.attributes['from_project']);
      final toProject = _attributeString(atom.attributes['to_project']);
      final evidence = atom.evidenceFactIds.isEmpty
          ? ''
          : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）';
      final projectText = fromProject == null || toProject == null
          ? ''
          : '在 $fromProject 和 $toProject 之间，';
      return '根据 Memory Primary 当前记录：\n'
          '- $projectText你从 $fromRole 切到 $toRole；阶段心态从 $fromMood 转为 $toMood。$evidence';
    }
    return null;
  }

  bool _roleMoodAtomMatchesQuery(String query, MemoryAtom atom) {
    final text = [
      atom.type,
      atom.title,
      atom.content,
      atom.entityIds.join(' '),
      atom.attributes.values.join(' '),
    ].join(' ');
    if (!_containsAny(text, const ['角色', '心态', '情绪', '切换', '转换', 'mood'])) {
      return false;
    }
    final normalizedQuery = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (final entity in atom.entityIds) {
      final normalizedEntity =
          entity.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (normalizedEntity.length >= 2 &&
          normalizedQuery.contains(normalizedEntity)) {
        return true;
      }
    }
    return _containsAny(query, const ['角色', '心态', '情绪', '切换', '转换']);
  }

  bool _looksLikeRoleMoodTransitionAtom(MemoryAtom atom) {
    final text = [
      atom.type,
      atom.title,
      atom.content,
      atom.entityIds.join(' '),
      atom.attributes.values.join(' '),
    ].join(' ');
    return atom.attributes['fallback_rule'] == 'role_mood_transition' ||
        _containsAny(text, const ['心态', '情绪', '切换', '转换', 'mood']) ||
        (text.contains('角色') &&
            _containsAny(text, const ['从', '转为', '切到', '切换', '转换']));
  }

  bool _identityQueryAsksLocation(String query) {
    return _containsAny(query, const [
      '常驻',
      '居住',
      '住哪',
      '哪里',
      '在哪',
      '城市',
      '地点',
      'city',
      'location',
    ]);
  }

  bool _identityQueryAsksRoutine(String query) {
    return _containsAny(query, const [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
      '周天',
      '上午',
      '下午',
      '晚上',
      '深度工作',
      '安排',
      '日程',
      'routine',
      'schedule',
    ]);
  }

  List<String> _locationClauses(String content) {
    return _identityRoutineSegments(content)
        .where(
          (segment) => _containsAny(segment, const ['常驻', '居住', '城市', '地点']),
        )
        .map(_stripMemorySubjectPrefix)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _routineClauses(String query, String content) {
    final queryWeekdays = _queryWeekdayTerms(query);
    final queryDayparts = _queryDaypartTerms(query);
    final segments = _identityRoutineSegments(content);
    final clauses = <String>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final hasRequestedWeekday = queryWeekdays.isEmpty ||
          queryWeekdays.any((term) => segment.contains(term));
      final hasRequestedDaypart = queryDayparts.isEmpty ||
          queryDayparts.any((term) => segment.contains(term));
      final hasRoutineCue = _containsAny(segment, const [
        '深度工作',
        '评审会',
        '安排',
        '日程',
        '会议',
        '同步',
        '工作',
      ]);
      final directlyMatches =
          hasRequestedWeekday && hasRequestedDaypart && hasRoutineCue;
      final continuationMatches = clauses.isNotEmpty &&
          _containsAny(segment, const ['不安排', '不排', '避免', '留给', '会议']);
      if (!directlyMatches && !continuationMatches) continue;
      clauses.add(_stripMemorySubjectPrefix(segment));
    }
    return clauses
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _identityRoutineSegments(String content) {
    return content
        .split(RegExp(r'[。；;\n，,]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _queryWeekdayTerms(String query) {
    return RegExp(r'周[一二三四五六日天]')
        .allMatches(query)
        .map((match) => match.group(0)!)
        .toSet()
        .toList(growable: false);
  }

  List<String> _queryDaypartTerms(String query) {
    return ['上午', '中午', '下午', '晚上']
        .where((term) => query.contains(term))
        .toList(growable: false);
  }

  String _stripMemorySubjectPrefix(String value) {
    return value.replaceFirst(RegExp(r'^(?:用户|我|个人长期偏好)[:：]?\s*'), '').trim();
  }

  String? _attributeString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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
      final clauses = _relationshipClauses(atom.content);
      for (var i = 0; i < clauses.length; i++) {
        final clause = clauses[i];
        if (!_containsAny(clause, include)) continue;
        if (_containsAny(clause, exclude)) continue;
        final positiveContinuation = _positiveRelationshipContinuation(
          clauses: clauses,
          index: i,
          topicClause: clause,
          include: include,
        );
        if (positiveContinuation == null &&
            _containsAny(clause, const ['不负责', '不是', '不再负责'])) {
          continue;
        }
        final inheritedSubjectClause = _relationshipClauseWithInheritedSubject(
          clauses: clauses,
          index: i,
          clause: clause,
        );
        final candidateClause = _sanitizeRelationshipCandidateClause(
          positiveContinuation ?? inheritedSubjectClause,
        );
        if (candidateClause.isEmpty ||
            _isSupersededOnlyRelationshipClause(candidateClause)) {
          continue;
        }
        var score = 1;
        if (positiveContinuation != null) score += 5;
        if (_containsAny(candidateClause, prefer)) score += 3;
        if (_containsAny(candidateClause, const [
          '当前',
          '现在',
          '最新',
          '联系人',
          '负责人',
          'owner',
          '负责方',
        ])) {
          score += 3;
        }
        if (candidateClause.contains('负责') || candidateClause.contains('找')) {
          score += 2;
        }
        if (atom.evidenceFactIds.isNotEmpty) score += 1;
        if (score > bestScore) {
          bestScore = score;
          best = _RelationshipClause(
            text: candidateClause,
            evidence: atom.evidenceFactIds.isEmpty
                ? ''
                : '（证据：${_limitedEvidence(atom.evidenceFactIds)}）',
          );
        }
      }
    }
    return best;
  }

  String? _positiveRelationshipContinuation({
    required List<String> clauses,
    required int index,
    required String topicClause,
    required List<String> include,
  }) {
    if (!_containsAny(topicClause, const ['不负责', '不是', '不再负责'])) {
      return null;
    }
    if (index + 1 >= clauses.length) return null;

    final next = clauses[index + 1].trim();
    if (next.isEmpty) return null;
    if (!_containsAny(next, const ['负责', '找', '联系', '由'])) return null;
    if (_containsAny(next, const ['不负责', '不是', '不再负责'])) return null;
    final startsWithPronoun = RegExp(
      r'^(?:此项工作|这项工作|该工作|此事项|这件事|该事项)',
    ).hasMatch(next);
    final isDirectAssignment = _containsAny(next, include) ||
        _containsAny(next, const ['由', '找', '负责人']);
    if (!startsWithPronoun && !isDirectAssignment) return null;

    final topic = _relationshipTopicFromClause(topicClause, include);
    if (topic == null) return next;
    return next
        .replaceFirst(RegExp(r'^(?:此项工作|这项工作|该工作|此事项|这件事|该事项)'), topic)
        .trim();
  }

  String _relationshipClauseWithInheritedSubject({
    required List<String> clauses,
    required int index,
    required String clause,
  }) {
    if (index <= 0) return clause;
    if (!_looksLikeSubjectlessRelationshipClause(clause)) return clause;
    final subject = _relationshipSubjectFromClause(clauses[index - 1]);
    if (subject == null || clause.contains(subject)) return clause;
    return '$subject $clause';
  }

  bool _looksLikeSubjectlessRelationshipClause(String clause) {
    return RegExp(r'^(?:主要)?(?:职责是|负责|对接|处理)').hasMatch(clause);
  }

  String? _relationshipSubjectFromClause(String clause) {
    final match = RegExp(
      r'^([A-Za-z][A-Za-z0-9]*(?:\s*[A-Z])?|[\u4e00-\u9fa5]{2,4})\s*(?:不负责|负责|主要职责)',
    ).firstMatch(clause.trim());
    final subject = match?.group(1)?.trim();
    return subject == null || subject.isEmpty ? null : subject;
  }

  String? _relationshipTopicFromClause(
    String clause,
    List<String> include,
  ) {
    final matchedTerms =
        include.where((term) => clause.contains(term)).toList(growable: false);
    if (matchedTerms.isEmpty) return null;
    if (matchedTerms.length >= 2) return matchedTerms.take(2).join('和');
    return matchedTerms.first;
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

  String _sanitizeRelationshipCandidateClause(String clause) {
    return _normalizeRelationshipClause(
      _stripSupersededTail(_stripMemorySubjectPrefix(clause)),
    ).trim();
  }

  bool _isSupersededOnlyRelationshipClause(String clause) {
    return RegExp(
      r'^(?:此信息|此记录|该记录|该说法|这条记录|这条信息)?\s*(?:取代|覆盖|作废|失效)',
    ).hasMatch(clause.trim());
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

    if (_looksLikeParsedTextContextQuery(query)) {
      return hasAny(const [
        'OCR',
        '截图',
        '已解析',
        '给定文本',
        '数据口径解释',
        '灰度风险列表',
        '风险列表',
      ]);
    }
    if (_looksLikeSensitiveBoundaryQuery(query)) {
      return atom.type == 'boundary' ||
          hasAny(const [
            '投资建议',
            '确定性建议',
            '确定性投资',
            '税务结论',
            '法律建议',
            '医疗建议',
            '财务压力',
            '情绪和事实',
          ]);
    }
    if (_looksLikeOwnerOnlyQuery(query)) {
      return !atom.type.contains('preference') &&
          (atom.type == 'project_context' ||
              atom.type == 'relationship' ||
              hasAny(const [
                'owner',
                '所有者',
                '负责人',
                '负责方',
                '负责',
                '验收',
              ]));
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
      if (_looksLikeRoleMoodTransitionAtom(atom) &&
          !_looksLikeRoleMoodTransitionQuery(query)) {
        return false;
      }
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
    if (_looksLikeRoleMoodTransitionQuery(query)) {
      return atom.type == 'project_context' ||
          atom.type == 'boundary' ||
          hasAny(const [
            '角色',
            '心态',
            '情绪',
            '切换',
            '转换',
            'AI 产品经理',
            '客户访谈整理者',
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
      RegExp(
          r'(?:如果)?(?:我)?(?:只问|问到|查询|查一下)\s+(.+?)\s*(?:的)?\s*(?:owner|负责人|负责方)'),
      RegExp(r'(.+?)\s*(?:的)?\s*(?:owner|负责人|负责方).{0,20}(?:是谁|谁|只回答|应该)'),
      RegExp(r'(.+?)\s*(?:当前|现在|最新).{0,20}(?:owner|负责人|负责|导出灰度)'),
      RegExp(r'(.+?)\s*(?:的)?导出灰度.{0,20}(?:owner|负责人|负责)'),
    ]) {
      final match = pattern.firstMatch(query);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty) continue;
      final cleaned = value
          .replaceAll(
            RegExp(
              r'^(?:如果)?(?:我)?(?:只问|问到|请问|请告诉我|告诉我|查询|查一下|以后|以后给我|给我)\s*',
            ),
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
