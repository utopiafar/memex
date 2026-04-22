import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/agent_cache_helper.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/agent/skills/manage_todo_schedule/todo_schedule_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/agent/todo_schedule_agent/prompts.dart';
import 'package:memex/data/services/file_system_service.dart';

class TodoScheduleAgent {
  static final Logger _logger = Logger('TodoScheduleAgent');

  static Future<StatefulAgent> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String factId,
  }) async {
    final fileService = FileSystemService.instance;
    final factIdSafe = fileService.makeFactIdSafe(factId);
    final sessionId = "todo_schedule_${userId}_$factIdSafe";

    // Load or create agent state
    final state = await loadOrCreateAgentState(sessionId, {
      'userId': userId,
      'factId': factId,
      'scene': 'todo_schedule',
      'sceneId': factId,
    });

    final controller = AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    // Memory context (read-only for this agent)
    final memoryManagement = await MemoryManagement.createDefault(
      userId: userId,
      sourceAgent: 'todo_schedule_agent',
    );
    final memoryPrompt = await memoryManagement.buildMemoryPrompt();
    state.systemReminders["user_memory"] = memoryPrompt;

    final agent = StatefulAgent(
      name: 'todo_schedule_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      planMode: PlanMode.none,
      compressor: LLMBasedContextCompressor(
        client: client,
        modelConfig: modelConfig,
        totalTokenThreshold: 64000,
        keepRecentMessageSize: 10,
      ),
      tools: [],
      skills: [
        TodoScheduleSkill(forceActivate: true),
      ],
      systemPrompts: [buildTodoSchedulePrompt()],
      disableSubAgents: true,
      controller: controller,
      withGeneralPrinciples: true,
      autoSaveStateFunc: (state) async {
        await saveAgentState(state);
      },
      systemCallback: createSystemCallback(userId),
    );

    _logger.info(
        'TodoScheduleAgent created, userId: $userId, sessionId: $sessionId');
    return agent;
  }

  /// Run the agent with user content.
  static Future<void> runWithContent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String factId,
    required String userContent,
  }) async {
    // Ensure cached responseId for continuity
    final cachedResponseId = await AgentCacheHelper.ensureValidCachedResponseId(
      agentType: 'todo_schedule',
      client: client,
      modelConfig: modelConfig,
      agentFactory: ({
        required LLMClient client,
        required ModelConfig modelConfig,
      }) async {
        return _createAgent(
          client: client,
          modelConfig: modelConfig,
          userId: 'mocked_user_id',
          factId:
              'mocked_fact_id_${DateTime.now().millisecondsSinceEpoch}',
        );
      },
    );

    // Prepare modelConfig with previous_response_id
    final extra = Map<String, dynamic>.from(modelConfig.extra ?? {});
    if (cachedResponseId != null) {
      extra['previous_response_id'] = cachedResponseId;
    }
    final finalModelConfig = ModelConfig(
      model: modelConfig.model,
      extra: extra,
      temperature: modelConfig.temperature,
      maxTokens: modelConfig.maxTokens,
      topP: modelConfig.topP,
      topK: modelConfig.topK,
      generationConfig: modelConfig.generationConfig,
    );

    final agent = await _createAgent(
      client: client,
      modelConfig: finalModelConfig,
      userId: userId,
      factId: factId,
    );

    final input = [
      UserMessage([
        TextPart(userContent),
      ])
    ];

    _logger.info(
        'TodoScheduleAgent running, userId: $userId, factId: $factId');
    await agent.run(input, useStream: false);

    // Log execution event
    try {
      await FileSystemService.instance.eventLogService.logEvent(
        userId: userId,
        eventType: 'agent_execution',
        description: 'TodoSchedule Agent completed',
        metadata: {
          'agent_name': 'todo_schedule_agent',
          'session_id': agent.state.sessionId,
          'fact_id': factId,
        },
      );
    } catch (_) {
      // Event logging failure should not break agent execution
    }
  }
}
