import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/full_chain_serial_smoke',
  );
  await outDir.create(recursive: true);

  final cases = [_case()];
  final manifest = {
    'dataset_id': 'memex_full_chain_serial_smoke',
    'version': 1,
    'description': '中文小样本串行全链路 replay 数据集，按真实单用户操作脚本执行。',
    'created_at': '2026-05-12',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'case_count': cases.length,
    'persona_count': cases.length,
    'operation_count': (cases.first['operations'] as List).length,
    'families': ['full_chain_serial_replay'],
    'notes': [
      '执行器应以 maxConcurrency=1 串行处理后台任务。',
      '每条 record 操作后等待 task idle，再进入下一步。',
      '使用 submitInput(createdAt) 进行低侵入时间仿真。',
      'Super Agent 问答使用 router.sendMessage 的真实 chat stream。',
    ],
  };

  await File('${outDir.path}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File('${outDir.path}/cases.jsonl').writeAsString(
    '${cases.map(jsonEncode).join('\n')}\n',
    flush: true,
  );

  stdout.writeln(
    'Generated ${cases.length} serial full-chain case at ${outDir.path}',
  );
}

JsonMap _case() => {
      'case_id': 'full_chain_serial_001',
      'family': 'full_chain_serial_replay',
      'language': 'zh-CN',
      'persona': {
        'user_id': 'eval_serial_u_001',
        'profile': {
          'occupation': '产品经理',
          'city': '杭州',
          'preferences': ['偏好中文输出', '结论先行'],
        },
      },
      'ground_truth_world': {
        'facts': [
          {
            'id': 'op_record_001',
            'content': '用户希望重要会议提前一天提醒。',
          },
          {
            'id': 'op_record_002',
            'content': '用户旧偏好是不喝咖啡。',
          },
          {
            'id': 'op_record_003',
            'content': '用户今天有点烦，但明确不要写成长记忆。',
          },
          {
            'id': 'op_record_004',
            'content': '用户周五下午三点和 Jason 讨论会员召回预算。',
          },
          {
            'id': 'op_record_005',
            'content': '用户最新偏好是上午可以喝一杯咖啡，下午不喝。',
          },
        ],
        'expected_latest_memory': [
          '重要会议提前一天提醒',
          '上午可以喝一杯咖啡',
        ],
      },
      'operations': [
        {
          'id': 'op_record_001',
          'type': 'record',
          'time': '2026-05-01T09:00:00+08:00',
          'content': '以后重要会议尽量提前一天提醒我，别临近了才说。',
          'expected_title_contains': ['重要会议'],
        },
        {
          'id': 'op_record_002',
          'type': 'record',
          'time': '2026-05-03T09:30:00+08:00',
          'content': '我不喝咖啡，早上也不要。',
          'expected_title_contains': ['咖啡'],
        },
        {
          'id': 'op_record_003',
          'type': 'record',
          'time': '2026-05-05T21:00:00+08:00',
          'content': '今天有点烦，主要是临时会太多，这只是今天，不要当成长期偏好。',
          'expected_title_contains': ['今天'],
        },
        {
          'id': 'op_record_004',
          'type': 'record',
          'time': '2026-05-08T15:00:00+08:00',
          'content': '周五下午三点和 Jason 讨论会员召回预算，帮我记一下。',
          'expected_title_contains': ['Jason', '预算'],
        },
        {
          'id': 'op_record_005',
          'type': 'record',
          'time': '2026-05-12T09:00:00+08:00',
          'content': '我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。',
          'expected_title_contains': ['咖啡'],
        },
        {
          'id': 'op_wait_memory_001',
          'type': 'wait_memory',
          'timeout_seconds': 180,
          'must_include_any': ['重要会议', '咖啡'],
        },
        {
          'id': 'op_ask_001',
          'type': 'ask_super_agent',
          'time': '2026-05-12T10:00:00+08:00',
          'query': '我现在早上能喝咖啡吗？重要会议提醒偏好是什么？',
          'quick_query': true,
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'full_chain_serial_001_cost',
          'type': 'cost_trace',
          'expected': {
            'max_total_tokens': 600000,
            'max_latency_ms': 900000,
            'max_tool_calls': 300,
            'require_all_tasks_completed': true,
            'must_include': ['Facts', 'Cards', 'Super Agent'],
          },
        },
        {
          'task_id': 'full_chain_serial_001_memory',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_meeting_reminder',
                'must_include': ['重要会议', '提前一天'],
              },
              {
                'id': 'mem_coffee_latest',
                'must_include': ['上午', '可以喝', '咖啡'],
              },
            ],
            'must_not_write': [
              {
                'id': 'mem_temporary_mood',
                'must_include': ['今天有点烦'],
              }
            ],
            'conflicts': [
              {
                'latest_should_include': ['上午', '可以喝', '咖啡'],
                'superseded_should_not_be_active': ['早上', '不要', '咖啡'],
              }
            ],
          },
        },
        {
          'task_id': 'full_chain_serial_001_super_agent',
          'type': 'super_agent_qa',
          'query': '我现在早上能喝咖啡吗？重要会议提醒偏好是什么？',
          'expected': {
            'must_include': ['咖啡', '重要会议', '提前'],
            'must_not_include': ['完全不喝咖啡'],
            'allowed_uncertainty': false,
            'read_only': true,
            'prohibited_tool_calls': ['update_memory', 'delete_memory'],
          },
        },
      ],
    };
