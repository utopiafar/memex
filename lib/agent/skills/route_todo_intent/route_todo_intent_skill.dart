import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('RouteTodoIntentSkill');

/// Skill for classifying todo/schedule intent from user input.
/// The agent MUST call this tool to report its classification.
class RouteTodoIntentSkill extends Skill {
  RouteTodoIntentSkill()
      : super(
          name: 'route_todo_intent',
          description:
              'Classifies whether user input contains todo or schedule intent. '
              'Must be called for every input to determine routing.',
          systemPrompt: '',
          tools: _buildTools(),
        );

  static List<Tool> _buildTools() {
    return [
      Tool(
        name: 'classify_todo_intent',
        description:
            'Classify the user input as add/complete/cancel/none. '
            'Call this exactly once per input.',
        parameters: {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['add', 'complete', 'cancel', 'none'],
              'description':
                  'The detected action type: add=new todo/schedule, complete=finish existing, cancel=cancel existing, none=no intent',
            },
            'items': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'title': {
                    'type': 'string',
                    'description': 'Title of the referenced item',
                  },
                  'type': {
                    'type': 'string',
                    'enum': ['todo', 'schedule'],
                    'description': 'Item type (only for add action)',
                  },
                },
              },
              'description': 'Extracted items (empty for none)',
            },
          },
          'required': ['action', 'items'],
        },
        executable: (
          String action,
          List? items,
        ) async {
          final context = AgentCallToolContext.current;

          // Store the routing result in agent state metadata for the handler to read
          final result = {
            'action': action,
            'items': items ?? [],
          };

          if (context != null) {
            context.state.metadata['routing_result'] = jsonEncode(result);
          }

          _logger.info('Routing classification: action=$action, items=${items?.length ?? 0}');

          return AgentToolResult(
            content: TextPart('Classification recorded: $action'),
          );
        },
      ),
    ];
  }
}
