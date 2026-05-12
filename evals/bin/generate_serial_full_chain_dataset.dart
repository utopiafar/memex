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
    'record_operation_count': (cases.first['operations'] as List)
        .where((operation) => operation is Map && operation['type'] == 'record')
        .length,
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
          '上午咖啡',
        ],
      },
      'operations': [
        ..._recordOperations(),
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
            'max_total_tokens': 2500000,
            'max_tokens_per_input': 70000,
            'max_latency_ms': 7200000,
            'max_tool_calls': 2500,
            'max_retry_rate': 0,
            'max_failed_task_rate': 0,
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
                'must_include': ['上午', '咖啡'],
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
                'latest_should_include': ['上午', '咖啡'],
                'superseded_should_not_be_active': ['早上', '不要', '咖啡'],
              }
            ],
            'evaluate_write_precision': false,
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

List<JsonMap> _recordOperations() {
  final records = [
    (
      '以后重要会议尽量提前一天提醒我，别临近了才说。',
      ['重要会议'],
    ),
    ('我不喝咖啡，早上也不要。', ['咖啡']),
    (
      '今天有点烦，主要是临时会太多，这只是今天，不要当成长期偏好。',
      ['今天'],
    ),
    ('周五下午三点和 Jason 讨论会员召回预算，帮我记一下。', ['Jason', '预算']),
    ('我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。', ['咖啡']),
    ('今天早上先看版本风险，导出功能的验收标准还要补齐。', ['版本风险']),
    ('中午和 Alex 简单聊了下导出入口，先不要定最终方案。', ['Alex']),
    ('晚上散步想到一个点：空状态应该给下一步动作，不只是文案。', ['空状态']),
    ('明天下午四点和设计看灰度发布页，提醒我带截图。', ['灰度发布']),
    ('这周杭州可能下雨，线下会议通勤多留二十分钟。', ['通勤']),
    ('今天只是想喝奶茶，不是长期饮食偏好。', ['奶茶']),
    ('需求复盘里记一下，客服最常问导出失败后的重试。', ['导出失败']),
    ('周三下午通常适合需求评审，上午尽量别排会。', ['需求评审']),
    ('如果会议涉及权限，提醒我找安全同事一起看。', ['权限']),
    ('今晚九点以后不要提醒我看工作文档，除非是发布事故。', ['提醒']),
    ('把老版本兼容风险放到发布清单里，owner 先写 Alex。', ['老版本兼容']),
    ('今天有点困，下午会如果不重要就先跳过，这只是今天。', ['有点困']),
    ('下周一上午十点和 QA 对回归用例。', ['QA', '回归用例']),
    ('导出项目的决策记录要保留来源，不要只写结论。', ['决策记录']),
    ('临时查一下竞品价格页的信息架构，明天再整理。', ['竞品']),
    ('周末可能去看展，这个不用放工作日程。', ['看展']),
    ('如果我问那个风险，通常指最近的发布风险。', ['发布风险']),
    ('发布当天不要安排太多一对一，容易被打断。', ['发布当天']),
    ('记一下，用户反馈里“找不到入口”归到可发现性问题。', ['可发现性']),
    ('今天晚上想早点睡，不要写成长期作息。', ['早点睡']),
    ('PRD 里验收标准要按用户路径写，不要按模块堆。', ['验收标准']),
    ('下次重要评审前一天提醒我准备用户路径截图。', ['评审']),
    ('如果 Alex 提到导出性能，先问清楚数据量级。', ['导出性能']),
    ('这周五之前把灰度监控指标补齐。', ['灰度监控']),
    ('晚上临时想查 Flutter 路由方案，不用进长期记忆。', ['Flutter']),
    ('发布复盘模板保留背景、决策、风险、下一步。', ['发布复盘']),
    ('如果没有记录，回答我时直接说不确定，别猜。', ['不确定']),
    ('导出项目里 Alex 是主要 owner，这个可以长期记。', ['Alex', 'owner']),
    ('明天早上九点半提醒我看异常指标。', ['异常指标']),
    ('今天情绪一般，别写成长期状态。', ['情绪']),
    ('月底复盘要把成本、延迟和工具调用次数列出来。', ['成本', '延迟']),
  ];

  return [
    for (var i = 0; i < records.length; i++)
      {
        'id': 'op_record_${(i + 1).toString().padLeft(3, '0')}',
        'type': 'record',
        'time': _recordTime(i),
        'content': records[i].$1,
        'expected_title_contains': records[i].$2,
      }
  ];
}

String _recordTime(int index) {
  final day = 1 + index ~/ 3;
  final hour = [9, 15, 21][index % 3];
  return '2026-05-${day.toString().padLeft(2, '0')}T'
      '${hour.toString().padLeft(2, '0')}:'
      '${(index * 5 % 60).toString().padLeft(2, '0')}:00+08:00';
}
