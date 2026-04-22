import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/skills/route_todo_intent/route_todo_intent_skill.dart';
import 'package:memex/agent/todo_routing_agent/prompts.dart';

class TodoRoutingAgent {
  static final Logger _logger = Logger('TodoRoutingAgent');

  /// Create a lightweight routing agent.
  /// No state persistence, no memory, no response caching — just classify and return.
  static Future<StatefulAgent> _createAgent({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
  }) async {
    final sessionId =
        'todo_routing_${userId}_${DateTime.now().millisecondsSinceEpoch}';
    final state = AgentState(
      sessionId: sessionId,
      metadata: {
        'userId': userId,
        'scene': 'todo_routing',
        'sceneId': sessionId,
      },
    );

    final controller = AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    final agent = StatefulAgent(
      name: 'todo_routing_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      planMode: PlanMode.none,
      tools: [],
      skills: [
        RouteTodoIntentSkill(),
      ],
      systemPrompts: [todoRoutingAgentSystemPrompt],
      disableSubAgents: true,
      controller: controller,
      withGeneralPrinciples: false,
      autoSaveStateFunc: null,
    );

    _logger.info('TodoRoutingAgent created, userId: $userId');
    return agent;
  }

  /// Run the routing agent and return the classification result.
  /// Returns null if classification fails.
  static Future<Map<String, dynamic>?> runRouting({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String userContent,
  }) async {
    final agent = await _createAgent(
      client: client,
      modelConfig: modelConfig,
      userId: userId,
    );

    final input = [
      UserMessage([TextPart(userContent)]),
    ];

    _logger.info(
        'TodoRoutingAgent running for input: "${userContent.length > 50 ? '${userContent.substring(0, 50)}...' : userContent}"');

    try {
      await agent.run(input, useStream: false);
    } catch (e) {
      _logger.warning('TodoRoutingAgent execution failed: $e');
      return null;
    }

    // Read routing result from agent state metadata
    final resultJson = agent.state.metadata['routing_result'] as String?;
    if (resultJson == null) {
      _logger.info('TodoRoutingAgent: no routing result in metadata');
      return null;
    }

    try {
      var jsonStr = resultJson.trim();
      if (jsonStr.startsWith('```')) {
        final lines = jsonStr.split('\n');
        if (lines.length >= 3) {
          jsonStr = lines.sublist(1, lines.length - 1).join('\n');
        }
      }
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      _logger.info('TodoRoutingAgent result: action=${result['action']}');
      return result;
    } catch (e) {
      _logger.warning(
          'TodoRoutingAgent: failed to parse routing result: $e');
      return null;
    }
  }
}
