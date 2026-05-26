import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _recordsPerPersona = 100;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/full_chain_journey_medium',
  );
  await outDir.create(recursive: true);

  final cases = [
    for (var i = 0; i < _personas.length; i++) _case(i + 1, _personas[i]),
  ];
  final operationCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['operations'] as List).length,
  );
  final recordCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        (evalCase['operations'] as List)
            .where((operation) =>
                operation is Map && operation['type'] == 'record')
            .length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_full_chain_journey_medium',
    'version': 1,
    'description': '中等规模中文单用户串行 Journey Benchmark，覆盖多周真实使用轨迹。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': recordCount,
    'record_operation_count': recordCount,
    'operation_count': operationCount,
    'records_per_persona': _recordsPerPersona,
    'task_count': taskCount,
    'families': ['full_chain_journey_medium'],
    'notes': [
      '每个 persona 有 $_recordsPerPersona 条中文跨周期 record 操作，另有 wait_memory 和 Super Agent 问答。',
      '输入覆盖工作、生活、临时情绪、临时咨询、长期偏好、冲突更新、日程提醒、证据不足偏好。',
      '数据集可用 fixture adapter 快速验证指标，也可用 serial_full_chain_replay_test.dart 走真实 Memex 链路。',
      '真实 replay 必须保持 maxConcurrency=1，逐条 record 后等待任务 idle。',
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
    'Generated ${cases.length} journey cases, $recordCount records, '
    '$taskCount tasks at ${outDir.path}',
  );
}

JsonMap _case(int n, _PersonaSpec persona) {
  final caseId = 'journey_medium_${_three(n)}';
  final operations = _operations(n, persona);
  final taskPrefix = caseId;
  final askOpId = '${caseId}_ask_001';
  final tasks = <JsonMap>[
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_project_meeting',
      operationId: _recordId(caseId, 4),
      titleContains: [persona.project, persona.primaryPerson],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_family_visit',
      operationId: _recordId(caseId, 20),
      titleContains: ['父母', persona.familyItem],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_weekly_report',
      operationId: _recordId(caseId, 25),
      titleContains: [persona.project, '周报'],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_cost_review',
      operationId: _recordId(caseId, 40),
      titleContains: ['成本', '延迟', '工具调用'],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_failure_review',
      operationId: _recordId(caseId, 60),
      titleContains: [persona.project, '失败模式'],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_roadmap_sync',
      operationId: _recordId(caseId, 75),
      titleContains: [persona.project, '路线图'],
    ),
    _cardTask(
      caseId: caseId,
      taskId: '${taskPrefix}_card_final_review',
      operationId: _recordId(caseId, 95),
      titleContains: [persona.project, '最终复盘'],
    ),
    _memoryTask(
        caseId: caseId, taskId: '${taskPrefix}_memory', persona: persona),
    _superAgentTask(
      caseId: caseId,
      taskId: '${taskPrefix}_super_agent',
      operationId: askOpId,
      persona: persona,
    ),
    _costTask(caseId: caseId, taskId: '${taskPrefix}_cost'),
  ];

  return {
    'case_id': caseId,
    'family': 'full_chain_journey_medium',
    'language': 'zh-CN',
    'persona': {
      'user_id': persona.userId,
      'profile': {
        'occupation': persona.occupation,
        'city': persona.city,
        'habits': persona.habits,
        'preferences': ['偏好中文输出', '结论先行', persona.preference],
      },
    },
    'ground_truth_world': {
      'facts': [
        {
          'id': '${caseId}_fact_meeting_reminder',
          'type': 'preference',
          'content': '用户希望重要会议提前一天提醒。',
        },
        {
          'id': '${caseId}_fact_coffee_latest',
          'type': 'preference',
          'content': '用户旧偏好是不喝咖啡，最新偏好是上午可以喝一杯，下午不喝。',
        },
        {
          'id': '${caseId}_fact_project_owner',
          'type': 'project',
          'content': '${persona.project} 的主要协作人是 ${persona.primaryPerson}。',
        },
      ],
      'events': [
        {
          'id': _recordId(caseId, 4),
          'title': '和 ${persona.primaryPerson} 讨论 ${persona.project}',
          'time': _recordTime(4),
        },
        {
          'id': _recordId(caseId, 20),
          'title': '去父母家带 ${persona.familyItem}',
          'time': _recordTime(20),
        },
      ],
    },
    'operations': [
      ...operations,
      {
        'id': '${caseId}_wait_memory_001',
        'type': 'wait_memory',
        'timeout_seconds': 240,
        'must_include_any': ['重要会议', '咖啡', persona.project],
      },
      {
        'id': askOpId,
        'type': 'ask_super_agent',
        'time': '2026-06-15T10:00:00+08:00',
        'query': '我现在上午能喝咖啡吗？重要会议提醒偏好是什么？${persona.project} 主要找谁对齐？',
        'quick_query': true,
      },
    ],
    'eval_tasks': tasks,
  };
}

JsonMap _cardTask({
  required String caseId,
  required String taskId,
  required String operationId,
  required List<String> titleContains,
}) =>
    {
      'task_id': taskId,
      'type': 'card_extraction',
      'expected': {
        'operation_id': operationId,
        'status': 'completed',
        'title_contains': titleContains,
        'must_not_fields': ['weather', 'price'],
      },
      'fixture_observed': {
        'card': {
          'card_type': 'classic_card',
          'title': titleContains.join(' '),
          'status': 'completed',
          'fields': {'source_id': operationId},
        },
        'trace_events': [
          _taskTrace('card_agent_task'),
          _toolTrace('save_timeline_card')
        ],
        'llm_calls': [_llmCall('card_agent', 1800, 380)],
      },
    };

JsonMap _memoryTask({
  required String caseId,
  required String taskId,
  required _PersonaSpec persona,
}) =>
    {
      'task_id': taskId,
      'type': 'memory_write',
      'expected': {
        'must_write': [
          {
            'id': '${caseId}_mem_meeting_reminder',
            'must_include': ['重要会议', '提前一天'],
          },
          {
            'id': '${caseId}_mem_coffee_latest',
            'must_include': ['上午', '咖啡'],
          },
          {
            'id': '${caseId}_mem_project_owner',
            'must_include': [persona.project, persona.primaryPerson],
          },
          {
            'id': '${caseId}_mem_no_guessing',
            'must_include': ['没有记录', '不确定'],
          },
        ],
        'must_not_write': [
          {
            'id': '${caseId}_temp_mood',
            'must_include': ['今天有点烦'],
          },
          {
            'id': '${caseId}_temp_consult',
            'must_include': ['临时咨询'],
          },
          {
            'id': '${caseId}_temp_sleep',
            'must_include': ['今晚想早点睡'],
          },
        ],
        'conflicts': [
          {
            'latest_should_include': ['上午', '咖啡'],
            'superseded_should_not_be_active': ['早上', '不要', '咖啡'],
          }
        ],
        'evaluate_write_precision': false,
        'max_duplicate_rate': 0.25,
      },
      'fixture_observed': {
        'memory_entries': [
          {
            'id': '${caseId}_mem_meeting_reminder',
            'content': '用户希望重要会议提前一天提醒。',
            'status': 'active',
          },
          {
            'id': '${caseId}_mem_coffee_old',
            'content': '用户早上不要喝咖啡。',
            'status': 'superseded',
          },
          {
            'id': '${caseId}_mem_coffee_latest',
            'content': '用户最新偏好是上午可以喝咖啡，下午不喝。',
            'status': 'active',
          },
          {
            'id': '${caseId}_mem_project_owner',
            'content': '${persona.project} 主要找 ${persona.primaryPerson} 对齐。',
            'status': 'active',
          },
          {
            'id': '${caseId}_mem_no_guessing',
            'content': '没有记录时回答不确定，不要猜。',
            'status': 'active',
          },
        ],
        'trace_events': [_taskTrace('memory_sync_task')],
        'llm_calls': [_llmCall('memory_agent', 2600, 420)],
      },
    };

JsonMap _superAgentTask({
  required String caseId,
  required String taskId,
  required String operationId,
  required _PersonaSpec persona,
}) =>
    {
      'task_id': taskId,
      'type': 'super_agent_qa',
      'query': '我现在上午能喝咖啡吗？重要会议提醒偏好是什么？${persona.project} 主要找谁对齐？',
      'expected': {
        'operation_id': operationId,
        'must_include': ['上午', '咖啡', '重要会议', '提前一天', persona.primaryPerson],
        'must_not_include': ['完全不喝咖啡', '不知道'],
        'allowed_uncertainty': false,
        'read_only': true,
        'prohibited_tool_calls': [
          'update_memory',
          'delete_memory',
          'save_timeline_card'
        ],
        'personalization_must_include': [persona.project],
      },
      'fixture_observed': {
        'answer':
            '可以，按最新记录你上午可以喝一杯咖啡，下午还是别喝。重要会议偏好是提前一天提醒；${persona.project} 主要找 ${persona.primaryPerson} 对齐。',
        'retrieved_sources': [
          '${caseId}_mem_coffee_latest',
          '${caseId}_mem_meeting_reminder',
          '${caseId}_mem_project_owner',
        ],
        'cited_sources': [
          '${caseId}_mem_coffee_latest',
          '${caseId}_mem_meeting_reminder',
          '${caseId}_mem_project_owner',
        ],
        'tool_calls': [
          {
            'name': 'search_memory',
            'args': {'query': '咖啡 重要会议 ${persona.project}'},
          }
        ],
        'trace_events': [_toolTrace('search_memory')],
        'llm_calls': [_llmCall('memex_agent', 3200, 500)],
      },
    };

JsonMap _costTask({required String caseId, required String taskId}) => {
      'task_id': taskId,
      'type': 'cost_trace',
      'expected': {
        'max_total_tokens': 1600000,
        'max_tokens_per_input': 80000,
        'max_latency_ms': 9000000,
        'max_tool_calls': 5000,
        'max_retry_rate': 0.05,
        'max_failed_task_rate': 0,
        'require_all_tasks_completed': true,
        'must_include': ['Facts', 'Cards', 'Super Agent'],
      },
      'fixture_observed': {
        'answer': 'Journey 已写入 Facts、Cards，并完成 Super Agent 问答。',
        'trace_events': [
          for (var i = 0; i < _recordsPerPersona * 4; i++)
            {
              'event_type': 'task',
              'task_id': '${caseId}_task_$i',
              'task_type': i.isEven ? 'card_agent_task' : 'memory_sync_task',
              'status': 'completed',
              'latency_ms': 1400 + i * 7,
            },
          for (var i = 0; i < _recordsPerPersona * 2; i++)
            _toolTrace(i.isEven ? 'save_card' : 'search_memory'),
        ],
        'active_tasks': const [],
        'failed_tasks': const [],
        'task_status_counts': {'completed': _recordsPerPersona * 4},
        'tasks_settled': true,
        'llm_calls': [
          for (var i = 0; i < _recordsPerPersona * 3; i++)
            _llmCall('journey_agent', 1600 + i, 360),
        ],
        'case_elapsed_ms': _recordsPerPersona * 12000,
        'suite_elapsed_ms': _recordsPerPersona * 12000 * _personas.length,
        'input_count': _recordsPerPersona,
        'task_count': _recordsPerPersona * 4,
      },
    };

List<JsonMap> _operations(int n, _PersonaSpec persona) => [
      for (var i = 1; i <= _recordsPerPersona; i++)
        {
          'id': _recordId('journey_medium_${_three(n)}', i),
          'type': 'record',
          'time': _recordTime(i),
          'content': _recordContent(index: i, persona: persona),
          'expected_title_contains': _titleNeedles(index: i, persona: persona),
        }
    ];

String _recordContent({required int index, required _PersonaSpec persona}) {
  switch (index) {
    case 1:
      return '以后像${persona.project}评审这种重要会议，尽量提前一天提醒我，别临近了才说。';
    case 2:
      return '先记一下，我最近不喝咖啡，早上也不要，免得影响状态。';
    case 3:
      return '今天有点烦，主要是${persona.city}这边临时会太多，这只是今天，不要当成长期偏好。';
    case 4:
      return '下周二上午十点和${persona.primaryPerson}讨论${persona.project}的灰度计划，帮我记一下。';
    case 5:
      return '我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝，尤其是开会多的时候。';
    case 10:
      return '${persona.project} 主要找 ${persona.primaryPerson} 对齐，这个可以长期记。';
    case 15:
      return '如果没有记录，回答我时直接说不确定，别猜。';
    case 20:
      return '这周六上午提醒我去父母家，顺便带${persona.familyItem}。';
    case 25:
      return '周五下班前提醒我把${persona.project} 周报发给 ${persona.secondaryPerson}，重点写风险和 owner。';
    case 30:
      return '下次看数据时提醒我把异常值单独标出来，别混在整体均值里。';
    case 35:
      return '这两天只是想吃清淡一点，别记成长期饮食偏好。';
    case 40:
      return '月底复盘要把成本、延迟和工具调用次数列出来。';
    case 60:
      return '6月10日下午三点和${persona.secondaryPerson}复盘${persona.project}的失败模式，提醒我带指标截图。';
    case 75:
      return '月底和${persona.primaryPerson}确认${persona.project}路线图，先看风险 owner 和回滚预案。';
    case 95:
      return '6月底做${persona.project}最终复盘，提醒我把结论、来源、成本和下一步分开写。';
  }
  final detail = _details[index % _details.length];
  final habit = persona.habits[index % persona.habits.length];
  final metric = _metrics[index % _metrics.length];
  final lifeItem = _lifeItems[index % _lifeItems.length];
  final consultTopic = _consultTopics[index % _consultTopics.length];
  final templates = [
    '今天早上先看${persona.project}的$detail，验收标准还要补齐。',
    '中午和${persona.secondaryPerson}简单聊了下$detail，先不要定最终方案。',
    '晚上散步想到一个点：$detail 不能只给文案，最好给下一步动作。',
    '明天下午四点和设计看${persona.project}的$detail，提醒我带截图。',
    '${persona.city}这周通勤不稳定，和$habit 相关的安排最好多留二十分钟。',
    '今天只是想试试$lifeItem，不是长期生活偏好。',
    '临时咨询一下，$consultTopic 这件事明天再整理，不用写成长记忆。',
    '$habit 这件事尽量别和${persona.project}的深度工作冲突。',
    '如果会议涉及$detail，提醒我找对应同事一起看，不要我一个人拍板。',
    '今晚想早点睡，主要是今天事情太碎，不要写成长期作息。',
    '${persona.project}复盘模板保留背景、决策、风险、下一步，特别标出$metric。',
    '今天情绪一般，和$detail卡住有关，别写成长期状态。',
  ];
  return templates[(index - 6) % templates.length];
}

List<String> _titleNeedles(
    {required int index, required _PersonaSpec persona}) {
  switch (index) {
    case 4:
      return [persona.project, persona.primaryPerson];
    case 20:
      return ['父母', persona.familyItem];
    case 25:
      return [persona.project, '周报'];
    case 40:
      return ['成本', '延迟', '工具调用'];
    case 60:
      return [persona.project, '失败模式'];
    case 75:
      return [persona.project, '路线图'];
    case 95:
      return [persona.project, '最终复盘'];
    default:
      return [];
  }
}

String _recordId(String caseId, int index) =>
    '${caseId}_record_${index.toString().padLeft(3, '0')}';

String _recordTime(int index) {
  final day = DateTime.utc(2026, 5, 1).add(Duration(days: index));
  final hour = [9, 15, 21][index % 3];
  return '2026-${_two(day.month)}-${_two(day.day)}T${_two(hour)}:'
      '${_two((index * 7) % 60)}:00+08:00';
}

JsonMap _taskTrace(String type) => {
      'event_type': 'task',
      'task_id': '${type}_${DateTime.utc(2026).microsecondsSinceEpoch}',
      'task_type': type,
      'status': 'completed',
      'latency_ms': 1200,
    };

JsonMap _toolTrace(String name) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': 300,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 1200,
    };

String _two(int n) => n.toString().padLeft(2, '0');
String _three(int n) => n.toString().padLeft(3, '0');

class _PersonaSpec {
  const _PersonaSpec({
    required this.userId,
    required this.occupation,
    required this.city,
    required this.project,
    required this.primaryPerson,
    required this.secondaryPerson,
    required this.familyItem,
    required this.preference,
    required this.habits,
  });

  final String userId;
  final String occupation;
  final String city;
  final String project;
  final String primaryPerson;
  final String secondaryPerson;
  final String familyItem;
  final String preference;
  final List<String> habits;
}

const _personas = [
  _PersonaSpec(
    userId: 'journey_u_001',
    occupation: '产品经理',
    city: '杭州',
    project: '导出项目',
    primaryPerson: 'Alex',
    secondaryPerson: 'Leo',
    familyItem: '体检报告复印件',
    preference: '重要事项要列来源',
    habits: ['周三下午需求评审', '晚上复盘当天工作'],
  ),
  _PersonaSpec(
    userId: 'journey_u_002',
    occupation: '跨境电商运营',
    city: '深圳',
    project: '北美站增长',
    primaryPerson: 'Jason',
    secondaryPerson: 'Mina',
    familyItem: '保温杯和降压药',
    preference: '投流复盘先看异常',
    habits: ['周三晚上健身', '周末看望父母'],
  ),
  _PersonaSpec(
    userId: 'journey_u_003',
    occupation: '数据分析师',
    city: '上海',
    project: 'Memex eval',
    primaryPerson: 'Grace',
    secondaryPerson: '小陈',
    familyItem: '书和眼药水',
    preference: '指标解释要保留英文 metric id',
    habits: ['上午深度分析', '周四 dashboard review'],
  ),
  _PersonaSpec(
    userId: 'journey_u_004',
    occupation: '律师',
    city: '广州',
    project: '法务合同库',
    primaryPerson: 'Annie',
    secondaryPerson: '老王',
    familyItem: '医保卡',
    preference: '重要结论要列来源',
    habits: ['下午审合同', '周末陪家人'],
  ),
  _PersonaSpec(
    userId: 'journey_u_005',
    occupation: '财务主管',
    city: '成都',
    project: '预算月结',
    primaryPerson: 'Mina',
    secondaryPerson: 'Ada',
    familyItem: '血压计',
    preference: '数字先给口径',
    habits: ['月底结账', '早上核对付款'],
  ),
  _PersonaSpec(
    userId: 'journey_u_006',
    occupation: '内容运营',
    city: '苏州',
    project: '小红书活动',
    primaryPerson: 'Grace',
    secondaryPerson: 'Jason',
    familyItem: '水果',
    preference: '复盘保留素材来源',
    habits: ['晚上看评论', '周五整理选题'],
  ),
];

const _details = [
  '入口文案',
  '权限边界',
  '回滚预案',
  '客服话术',
  '异常监控',
  '预算余量',
  '数据口径',
  '跨端兼容',
  '素材反馈',
  '用户路径',
  '风险 owner',
  '灰度节奏',
  '查询 SQL',
  '指标解释',
  '会议纪要',
  '来源标注',
];

const _metrics = [
  '失败率',
  '重试率',
  'P95 延迟',
  'token 成本',
  '工具调用次数',
  'MRR',
  'hit@3',
  '用户反馈',
];

const _lifeItems = [
  '无糖酸奶',
  '晚饭后散步',
  '早睡半小时',
  '周末看展',
  '下班后听播客',
  '午休十分钟',
  '低糖咖啡',
  '整理书桌',
];

const _consultTopics = [
  '客户催回复怎么措辞',
  '会议纪要怎么压缩',
  '低成本做用户访谈',
  '写周报怎么先给结论',
  '复盘里怎么区分事实和推测',
  '临时失眠怎么温和处理',
  '需求变更怎么记录 decision',
  '数据异常怎么先排查口径',
];
