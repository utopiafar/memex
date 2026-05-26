import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:path/path.dart' as path;

void main() {
  const userId = 'memory_source_user';
  late Directory tempRoot;
  late MemoryManagement memory;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('memex_memory_source_');
    await FileSystemService.init(tempRoot.path);
    memory = MemoryManagement(
      userId: userId,
      sourceAgent: 'test_agent',
      client: _UnusedClient(),
      modelConfig: ModelConfig(model: 'test-model'),
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('stores source fact ids on appended memory atoms', () async {
    await FileSystemService.instance.appendToDailyFactFile(
      userId,
      DateTime(2026, 5, 5),
      '## <id:ts_1> 09:00:00 "{}"\n\n妈妈晚间用药时间是晚上 9 点。\n',
    );

    await memory.appendMemories(
      ['妈妈晚间用药时间是晚上 9 点。'],
      sourceFactIds: const ['2026/05/05.md#ts_1'],
    );

    final memoryJson = await _readMemoryJson(userId);
    final buffer = memoryJson['recent_buffer'] as List;
    expect(buffer, hasLength(1));
    expect(buffer.single['content'], '妈妈晚间用药时间是晚上 9 点。');
    expect(buffer.single['source_fact_ids'], ['2026/05/05.md#ts_1']);

    final prompt = await memory.buildMemoryPrompt();
    expect(prompt, contains('妈妈晚间用药时间是晚上 9 点。'));
    expect(prompt, contains('sources: 2026/05/05.md#ts_1'));
    expect(prompt, contains('source[2026/05/05.md#ts_1]'));
  });

  test('parses object-style tool memory atoms with retrieval hints', () async {
    await memory.appendMemoryAtoms([
      MemoryAtomDraft.fromToolInput({
        'content': '用户偏好更少的澄清打断。',
        'kind': 'interaction_preference',
        'entities': ['澄清打断'],
        'source_fact_ids': ['2026/05/06.md#ts_2', '2026/05/06.md#ts_2'],
        'confidence': 0.8,
        'scope': 'AI interaction',
      }),
      MemoryAtomDraft.fromToolInput('兼容旧字符串格式。'),
    ]);

    final memoryJson = await _readMemoryJson(userId);
    final buffer = memoryJson['recent_buffer'] as List;
    expect(buffer, hasLength(2));
    expect(buffer.first['kind'], 'interaction_preference');
    expect(buffer.first['entities'], ['澄清打断']);
    expect(buffer.first['source_fact_ids'], ['2026/05/06.md#ts_2']);
    expect(buffer.first['confidence'], 0.8);
    expect(buffer.first['scope'], 'AI interaction');
    expect(buffer.last.containsKey('source_fact_ids'), isFalse);
  });

  test('marks older memory atoms as superseded by semantic decision', () async {
    await memory.appendMemoryAtoms([
      MemoryAtomDraft.fromToolInput({
        'content': '妈妈晚间用药提醒时间是晚上 8 点。',
        'source_fact_ids': ['2026/04/20.md#ts_1'],
      }),
    ]);

    await memory.appendMemoryAtoms([
      MemoryAtomDraft.fromToolInput({
        'content': '妈妈晚间用药提醒时间更新为晚上 9 点半。',
        'source_fact_ids': ['2026/05/07.md#ts_1'],
        'supersedes_memory_ids': ['mem_101'],
      }),
    ]);

    final memoryJson = await _readMemoryJson(userId);
    final buffer = memoryJson['recent_buffer'] as List;
    expect(buffer, hasLength(2));
    expect(buffer.first['status'], 'superseded');
    expect(buffer.first['superseded_by_memory_id'], 'mem_102');
    expect(buffer.last['supersedes_memory_ids'], ['mem_101']);

    final prompt = await memory.buildMemoryPrompt();
    expect(prompt, contains('[mem_102]'));
    expect(prompt, contains('晚上 9 点半'));
    expect(prompt, isNot(contains('晚上 8 点')));
  });

  test('preserves retrieval hints when recent atoms are archived', () async {
    final archivingMemory = MemoryManagement(
      userId: userId,
      sourceAgent: 'test_agent',
      client: _StaticClient('## Profile\n- 发布提醒偏好提前一天。'),
      modelConfig: ModelConfig(model: 'test-model'),
      recentBufferThreshold: 0,
    );

    final result = await archivingMemory.appendMemoryAtoms([
      MemoryAtomDraft.fromToolInput({
        'content': '导出灰度发布提醒需要提前一天。',
        'kind': 'reminder_rule',
        'entities': ['导出灰度', '提前一天'],
        'source_fact_ids': ['2026/05/08.md#ts_1'],
        'confidence': 0.9,
      }),
    ]);
    expect(result, contains('consolidated'));

    final memoryJson = await _readMemoryJson(userId);
    expect(memoryJson['recent_buffer'], isEmpty);
    final archivedAtoms = memoryJson['archived_atoms'] as List;
    expect(archivedAtoms, hasLength(1));
    expect(archivedAtoms.single['kind'], 'reminder_rule');
    expect(archivedAtoms.single['entities'], ['导出灰度', '提前一天']);
    expect(archivedAtoms.single['source_fact_ids'], ['2026/05/08.md#ts_1']);

    final prompt = await archivingMemory.buildMemoryPrompt();
    expect(prompt, contains('Archived Memory Atoms'));
    expect(prompt, contains('kind=reminder_rule'));
    expect(prompt, contains('sources: 2026/05/08.md#ts_1'));
  });
}

Future<Map<String, dynamic>> _readMemoryJson(String userId) async {
  final fs = FileSystemService.instance;
  final memoryPath =
      path.join(fs.getSystemPath(userId), 'memory', 'memory.json');
  return jsonDecode(await File(memoryPath).readAsString())
      as Map<String, dynamic>;
}

class _UnusedClient extends LLMClient {
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    throw UnsupportedError('LLM is not used by this test.');
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
    throw UnsupportedError('LLM is not used by this test.');
  }
}

class _StaticClient extends LLMClient {
  _StaticClient(this.output);

  final String output;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    return ModelMessage(textOutput: output, model: modelConfig.model);
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
    throw UnsupportedError('Streaming is not used by this test.');
  }
}
