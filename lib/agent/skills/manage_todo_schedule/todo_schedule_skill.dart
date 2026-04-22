import 'dart:convert';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/todo_schedule_service.dart';

final Logger _logger = Logger('TodoScheduleSkill');

/// Skill for managing todo and schedule items in the Agenda view.
class TodoScheduleSkill extends Skill {
  TodoScheduleSkill({super.forceActivate})
      : super(
          name: 'manage_todo_schedule',
          description:
              'Extracts actionable todos and schedules from user input. '
              'Creates new items, completes existing ones, or cancels them. '
              'Use when user mentions tasks, plans, appointments, or indicates completion of previous tasks.',
          systemPrompt: '',
          tools: _buildTools(),
        );

  static List<Tool> _buildTools() {
    return [
      // Tool 1: Get existing todos for context
      Tool(
        name: 'get_existing_todos',
        description:
            'Get all pending (uncompleted) todos for the current user. '
            'Use this BEFORE creating new todos to avoid duplicates, and to find matching todos when the user says they completed something.',
        parameters: {
          'type': 'object',
          'properties': {},
        },
        executable: () async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          if (userId == null) {
            return AgentToolResult(
              content: TextPart('Error: userId not found in agent context'),
            );
          }

          final service = TodoScheduleService.instance;
          final items = await service.getPendingTodos(userId);

          if (items.isEmpty) {
            return AgentToolResult(
              content: TextPart('No pending todos found.'),
            );
          }

          final result = items
              .map((item) => {
                    'id': item.id,
                    'title': item.title,
                    'type': item.type,
                    'priority': item.priority,
                    'due_date': item.dueDate,
                    'tags': item.tags,
                  })
              .toList();

          return AgentToolResult(
            content: TextPart(
              'Existing pending todos:\n${jsonEncode(result)}',
            ),
          );
        },
      ),

      // Tool 2: Create a new todo
      Tool(
        name: 'create_todo',
        description: 'Create a new todo item. Use when user expresses intention to do something.',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Short, actionable description of the todo',
            },
            'priority': {
              'type': 'integer',
              'description': '0=normal (default), 1=important',
            },
            'due_date': {
              'type': 'string',
              'description':
                  'Due date in YYYY-MM-DD format. Null if no specific deadline.',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Category tags (e.g. "work", "personal")',
            },
          },
          'required': ['title'],
        },
        executable: (
          String title,
          int? priority,
          String? due_date,
          List? tags,
        ) async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          final factId = context?.state.metadata['factId'] as String?;
          if (userId == null) {
            return AgentToolResult(
              content: TextPart('Error: userId not found'),
            );
          }

          final service = TodoScheduleService.instance;
          DateTime? dueDate;
          if (due_date != null) {
            try {
              dueDate = DateTime.parse(due_date);
            } catch (_) {
              _logger.warning('Failed to parse due_date: $due_date');
            }
          }

          final item = await service.createTodo(
            userId: userId,
            title: title,
            sourceFactId: factId ?? '',
            priority: priority ?? 0,
            dueDate: dueDate,
            tags: tags?.cast<String>(),
          );

          _logger.info('Created todo: ${item.title} (id=${item.id})');
          return AgentToolResult(
            content: TextPart('Created todo: "${item.title}" (id: ${item.id})'),
          );
        },
      ),

      // Tool 3: Create a new schedule
      Tool(
        name: 'create_schedule',
        description:
            'Create a new schedule/event item. Use when user mentions an appointment, meeting, or timed event.',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Short description of the event',
            },
            'start_time': {
              'type': 'string',
              'description':
                  'Event start time in YYYY-MM-DD HH:MM format (24h)',
            },
            'end_time': {
              'type': 'string',
              'description': 'Event end time in YYYY-MM-DD HH:MM format (optional)',
            },
            'priority': {
              'type': 'integer',
              'description': '0=normal (default), 1=important',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Category tags',
            },
          },
          'required': ['title', 'start_time'],
        },
        executable: (
          String title,
          String start_time,
          String? end_time,
          int? priority,
          List? tags,
        ) async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          final factId = context?.state.metadata['factId'] as String?;
          if (userId == null) {
            return AgentToolResult(
              content: TextPart('Error: userId not found'),
            );
          }

          final service = TodoScheduleService.instance;

          DateTime? startTime;
          DateTime? endTime;
          try {
            startTime = DateTime.parse(start_time);
          } catch (_) {
            return AgentToolResult(
              content: TextPart('Error: invalid start_time format: $start_time'),
            );
          }
          if (end_time != null) {
            try {
              endTime = DateTime.parse(end_time);
            } catch (_) {
              _logger.warning('Failed to parse end_time: $end_time');
            }
          }

          final item = await service.createSchedule(
            userId: userId,
            title: title,
            sourceFactId: factId ?? '',
            scheduleStart: startTime,
            scheduleEnd: endTime,
            priority: priority ?? 0,
            tags: tags?.cast<String>(),
          );

          _logger.info('Created schedule: ${item.title} (id=${item.id})');
          return AgentToolResult(
            content:
                TextPart('Created schedule: "${item.title}" (id: ${item.id})'),
          );
        },
      ),

      // Tool 4: Complete a todo
      Tool(
        name: 'complete_todo',
        description:
            'Mark an existing todo as completed. Use when user says they finished something. '
            'Provide either the exact todo_id (from get_existing_todos) or a title to fuzzy-match.',
        parameters: {
          'type': 'object',
          'properties': {
            'todo_id': {
              'type': 'string',
              'description': 'Exact todo ID from get_existing_todos',
            },
            'title': {
              'type': 'string',
              'description':
                  'Title to match against existing todos (used if todo_id not provided)',
            },
          },
        },
        executable: (
          String? todo_id,
          String? title,
        ) async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          if (userId == null) {
            return AgentToolResult(
              content: TextPart('Error: userId not found'),
            );
          }

          final service = TodoScheduleService.instance;

          if (todo_id != null && todo_id.isNotEmpty) {
            // Direct ID match
            await service.completeItem(todo_id);
            return AgentToolResult(
              content: TextPart('Completed todo: $todo_id'),
            );
          }

          if (title != null && title.isNotEmpty) {
            // Fuzzy match by title
            final pending = await service.getPendingTodos(userId);
            final matched = _fuzzyMatch(pending, title);
            if (matched != null) {
              await service.completeItem(matched.id);
              return AgentToolResult(
                content: TextPart(
                  'Completed todo: "${matched.title}" (id: ${matched.id})',
                ),
              );
            }
            return AgentToolResult(
              content: TextPart(
                'No matching todo found for "$title". Available todos: ${pending.map((t) => t.title).join(", ")}',
              ),
            );
          }

          return AgentToolResult(
            content: TextPart(
              'Error: provide either todo_id or title to identify the todo to complete.',
            ),
          );
        },
      ),

      // Tool 5: Cancel a todo
      Tool(
        name: 'cancel_todo',
        description:
            'Mark an existing todo as cancelled. Use when user says they no longer plan to do something.',
        parameters: {
          'type': 'object',
          'properties': {
            'todo_id': {
              'type': 'string',
              'description': 'Exact todo ID from get_existing_todos',
            },
            'title': {
              'type': 'string',
              'description':
                  'Title to match against existing todos (used if todo_id not provided)',
            },
          },
        },
        executable: (
          String? todo_id,
          String? title,
        ) async {
          final context = AgentCallToolContext.current;
          final userId = context?.state.metadata['userId'] as String?;
          if (userId == null) {
            return AgentToolResult(
              content: TextPart('Error: userId not found'),
            );
          }

          final service = TodoScheduleService.instance;

          if (todo_id != null && todo_id.isNotEmpty) {
            await service.cancelItem(todo_id);
            return AgentToolResult(
              content: TextPart('Cancelled todo: $todo_id'),
            );
          }

          if (title != null && title.isNotEmpty) {
            final pending = await service.getPendingTodos(userId);
            final matched = _fuzzyMatch(pending, title);
            if (matched != null) {
              await service.cancelItem(matched.id);
              return AgentToolResult(
                content: TextPart(
                  'Cancelled todo: "${matched.title}" (id: ${matched.id})',
                ),
              );
            }
            return AgentToolResult(
              content: TextPart('No matching todo found for "$title".'),
            );
          }

          return AgentToolResult(
            content: TextPart(
              'Error: provide either todo_id or title to identify the todo to cancel.',
            ),
          );
        },
      ),
    ];
  }

  /// Simple fuzzy match: check if any pending todo title contains
  /// all words from the query, or vice versa.
  static dynamic _fuzzyMatch(List pending, String query) {
    final queryLower = query.toLowerCase();
    final queryWords = queryLower
        .split(RegExp(r'[\s,，、]+'))
        .where((w) => w.length > 1)
        .toList();

    dynamic bestMatch;
    int bestScore = 0;

    for (final item in pending) {
      final title = (item.title as String).toLowerCase();

      // Exact match
      if (title == queryLower) {
        return item;
      }

      // Substring match
      if (title.contains(queryLower) || queryLower.contains(title)) {
        return item;
      }

      // Word overlap score
      int score = 0;
      for (final word in queryWords) {
        if (title.contains(word)) {
          score++;
        }
      }
      if (score > bestScore && score > 0) {
        bestScore = score;
        bestMatch = item;
      }
    }

    // Only return match if at least half the words matched
    if (bestScore >= (queryWords.length / 2).ceil()) {
      return bestMatch;
    }
    return null;
  }
}
