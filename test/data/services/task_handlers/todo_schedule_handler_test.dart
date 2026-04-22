import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/route_todo_intent/route_todo_intent_skill.dart';

/// Run a function inside a Zone with AgentCallToolContext set.
T _withToolContext<T>(AgentState state, T Function() fn) {
  final context = AgentCallToolContext(
    state: state,
    agent: _FakeAgent(),
    batchCallId: 'test_batch',
  );
  return runZoned(
    fn,
    zoneValues: {AgentCallToolContext.ZoneKey: context},
  );
}

class _FakeAgent extends StatefulAgent {
  _FakeAgent()
      : super(
          name: 'fake_agent',
          client: _FakeLLMClient(),
          modelConfig: ModelConfig(model: 'test'),
          state: AgentState(sessionId: 'fake'),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeLLMClient extends LLMClient {
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    return ModelMessage(model: 'test');
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final controller = StreamController<StreamingMessage>();
    controller.close();
    return controller.stream;
  }
}

void main() {
  group('classify_todo_intent tool', () {
    late AgentState state;
    late RouteTodoIntentSkill skill;
    late Tool tool;

    setUp(() {
      state = AgentState(sessionId: 'test_session', metadata: {});
      skill = RouteTodoIntentSkill();
      tool = skill.tools!.first;
    });

    test('stores add action in metadata', () async {
      _withToolContext(state, () {
        return (tool.executable as Function)('add', [
          {'title': '吃饭', 'type': 'todo'}
        ]);
      });

      final stored = state.metadata['routing_result'] as String;
      final parsed = jsonDecode(stored) as Map<String, dynamic>;
      expect(parsed['action'], 'add');
      expect((parsed['items'] as List).length, 1);
    });

    test('stores complete action in metadata', () async {
      _withToolContext(state, () {
        return (tool.executable as Function)('complete', [
          {'title': '吃饭'}
        ]);
      });

      final stored = state.metadata['routing_result'] as String;
      final parsed = jsonDecode(stored) as Map<String, dynamic>;
      expect(parsed['action'], 'complete');
    });

    test('stores cancel action in metadata', () async {
      _withToolContext(state, () {
        return (tool.executable as Function)('cancel', [
          {'title': '会议'}
        ]);
      });

      final stored = state.metadata['routing_result'] as String;
      final parsed = jsonDecode(stored) as Map<String, dynamic>;
      expect(parsed['action'], 'cancel');
    });

    test('stores none action with empty items', () async {
      _withToolContext(state, () {
        return (tool.executable as Function)('none', []);
      });

      final stored = state.metadata['routing_result'] as String;
      final parsed = jsonDecode(stored) as Map<String, dynamic>;
      expect(parsed['action'], 'none');
      expect((parsed['items'] as List).length, 0);
    });

    test('handles null items gracefully', () async {
      _withToolContext(state, () {
        return (tool.executable as Function)('none', null);
      });

      final stored = state.metadata['routing_result'] as String;
      final parsed = jsonDecode(stored) as Map<String, dynamic>;
      expect(parsed['action'], 'none');
      expect(parsed['items'], []);
    });

    test('no metadata stored without AgentCallToolContext', () async {
      // Running without zone context should not crash
      await (tool.executable as Function)('none', []);

      // metadata won't be set (no zone context)
      expect(state.metadata.containsKey('routing_result'), isFalse);
    });
  });
}
