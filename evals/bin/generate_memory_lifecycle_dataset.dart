import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _inputsPerPersona = 48;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/memory_lifecycle',
  );
  await outDir.create(recursive: true);

  final cases = [
    for (var i = 0; i < _personas.length; i++) _case(i + 1, _personas[i]),
  ];
  final inputCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['input_stream'] as List).length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_memory_lifecycle',
    'version': 1,
    'description':
        '中文 Memory Lifecycle Benchmark，评估长期事实、临时状态、重复表达、冲突更新、撤销和过期记忆。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'inputs_per_persona': _inputsPerPersona,
    'task_count': taskCount,
    'tasks_per_persona': 5,
    'families': ['memory_lifecycle'],
    'notes': [
      '每个 persona 有 $_inputsPerPersona 条中文输入，按生命周期阶段组织。',
      '覆盖 must-write recall、write precision、conflict handling、duplicate rate、temporal validity、source grounding 和 sensitive overwrite absence。',
      'fixture_observed 是理想 memory 状态，用于验证 grader 与报告口径；后续可接真实 memory replay 产物。',
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
    'Generated ${cases.length} memory lifecycle cases, $inputCount inputs, '
    '$taskCount tasks at ${outDir.path}',
  );
}

JsonMap _case(int n, _MemoryPersona persona) {
  final caseId = 'memory_lifecycle_${_three(n)}';
  final entries = _memoryEntries(caseId, persona);
  return {
    'case_id': caseId,
    'family': 'memory_lifecycle',
    'language': 'zh-CN',
    'persona': {
      'user_id': persona.userId,
      'profile': {
        'occupation': persona.occupation,
        'city': persona.city,
        'habits': persona.habits,
        'preferences': ['中文输出', persona.preference],
      },
    },
    'ground_truth_world': {
      'facts': [
        {
          'id': '${caseId}_fact_reminder',
          'type': 'preference',
          'content': '用户希望重要会议提前一天提醒。',
          'valid_from': '2026-05-01',
        },
        {
          'id': '${caseId}_fact_diet',
          'type': 'preference',
          'content': persona.dietMemory,
          'valid_from': '2026-05-02',
        },
        {
          'id': '${caseId}_fact_coffee_new',
          'type': 'preference',
          'content': '用户最新咖啡偏好是上午可以喝一杯，下午不喝。',
          'valid_from': '2026-05-12',
        },
        {
          'id': '${caseId}_fact_habit_pause',
          'type': 'temporal_preference',
          'content': '${persona.pauseHabit} 只在 2026-05 暂停，2026-06 起恢复观察。',
          'valid_from': '2026-05-18',
          'valid_until': '2026-05-31',
        },
      ],
    },
    'input_stream': _inputs(caseId: caseId, persona: persona),
    'eval_tasks': [
      _memoryTask(
        caseId: caseId,
        taskId: '${caseId}_initial_write',
        expected: {
          'must_write': [
            {
              'id': '${caseId}_mem_reminder',
              'must_include': ['重要会议', '提前一天'],
              'source_ids': ['${caseId}_input_01'],
              'valid_from': '2026-05-01',
            },
            {
              'id': '${caseId}_mem_diet',
              'must_include': persona.dietNeedles,
              'source_ids': ['${caseId}_input_02'],
            },
          ],
          'must_not_write': [
            {
              'id': '${caseId}_temp_mood',
              'must_include': ['今天', persona.temporaryMood],
            }
          ],
          'max_duplicate_rate': 0.2,
        },
        entries: _entriesById(
          entries,
          ['${caseId}_mem_reminder', '${caseId}_mem_diet'],
        ),
      ),
      _memoryTask(
        caseId: caseId,
        taskId: '${caseId}_conflict_update',
        expected: {
          'must_write': [
            {
              'id': '${caseId}_mem_coffee_latest',
              'must_include': ['上午', '咖啡'],
              'source_ids': ['${caseId}_input_12'],
              'valid_from': '2026-05-12',
            }
          ],
          'conflicts': [
            {
              'latest_should_include': ['上午', '咖啡'],
              'superseded_should_not_be_active': ['完全不喝咖啡'],
            }
          ],
          'evaluate_write_precision': false,
        },
        entries: _entriesById(
          entries,
          ['${caseId}_mem_coffee_old', '${caseId}_mem_coffee_latest'],
        ),
      ),
      _memoryTask(
        caseId: caseId,
        taskId: '${caseId}_temporal_scope',
        expected: {
          'must_write': [
            {
              'id': '${caseId}_mem_pause',
              'must_include': [persona.pauseHabit, '暂停'],
              'source_ids': ['${caseId}_input_18'],
              'valid_from': '2026-05-18',
              'valid_until': '2026-05-31',
            }
          ],
          'must_not_write': [
            {
              'id': '${caseId}_one_day_food',
              'must_include': ['今天只是想吃'],
            }
          ],
          'evaluate_write_precision': false,
        },
        entries: _entriesById(entries, ['${caseId}_mem_pause']),
      ),
      _memoryTask(
        caseId: caseId,
        taskId: '${caseId}_sensitive_boundary',
        expected: {
          'must_write': [
            {
              'id': '${caseId}_mem_no_guessing',
              'must_include': ['没有记录', '不确定'],
              'source_ids': ['${caseId}_input_24'],
            }
          ],
          'sensitive_must_not_write': [
            {
              'id': '${caseId}_sensitive_health',
              'must_include': ['血压', '医生'],
            },
            {
              'id': '${caseId}_private_family',
              'must_include': ['家庭争执'],
            }
          ],
          'evaluate_write_precision': false,
        },
        entries: _entriesById(entries, ['${caseId}_mem_no_guessing']),
      ),
      _superAgentTask(caseId: caseId, persona: persona),
    ],
  };
}

List<JsonMap> _entriesById(List<JsonMap> entries, List<String> ids) =>
    entries.where((entry) => ids.contains(entry['id'])).toList();

JsonMap _memoryTask({
  required String caseId,
  required String taskId,
  required JsonMap expected,
  required List<JsonMap> entries,
}) =>
    {
      'task_id': taskId,
      'type': 'memory_write',
      'expected': expected,
      'fixture_observed': {
        'memory_entries': entries,
        'trace_events': [_taskTrace('memory_sync_task')],
        'llm_calls': [_llmCall('memory_agent', 2200, 420)],
      },
    };

JsonMap _superAgentTask({
  required String caseId,
  required _MemoryPersona persona,
}) =>
    {
      'task_id': '${caseId}_super_agent_latest_memory',
      'type': 'super_agent_qa',
      'query': '我现在咖啡怎么喝？重要会议提醒偏好是什么？${persona.pauseHabit}这个月还继续吗？',
      'expected': {
        'must_include': ['上午', '咖啡', '重要会议', '提前一天', persona.pauseHabit, '暂停'],
        'must_not_include': ['完全不喝咖啡', '每天都暂停'],
        'read_only': true,
        'prohibited_tool_calls': [
          'update_memory',
          'delete_memory',
          'save_memory'
        ],
        'personalization_must_include': [persona.pauseHabit],
      },
      'fixture_observed': {
        'answer':
            '最新记录是上午可以喝一杯咖啡，下午不喝。重要会议需要提前一天提醒；${persona.pauseHabit}在 2026-05 暂停，6 月起恢复观察。',
        'retrieved_sources': [
          '${caseId}_mem_coffee_latest',
          '${caseId}_mem_reminder',
          '${caseId}_mem_pause',
        ],
        'cited_sources': [
          '${caseId}_mem_coffee_latest',
          '${caseId}_mem_reminder',
          '${caseId}_mem_pause',
        ],
        'tool_calls': [
          {
            'name': 'search_memory',
            'args': {'query': '咖啡 重要会议 ${persona.pauseHabit}'},
          }
        ],
        'trace_events': [_toolTrace('search_memory')],
        'llm_calls': [_llmCall('memex_agent', 2600, 520)],
      },
    };

List<JsonMap> _memoryEntries(String caseId, _MemoryPersona persona) => [
      {
        'id': '${caseId}_mem_reminder',
        'content': '用户希望重要会议提前一天提醒。',
        'status': 'active',
        'source_ids': ['${caseId}_input_01'],
        'valid_from': '2026-05-01',
      },
      {
        'id': '${caseId}_mem_diet',
        'content': persona.dietMemory,
        'status': 'active',
        'source_ids': ['${caseId}_input_02'],
      },
      {
        'id': '${caseId}_mem_coffee_old',
        'content': '用户旧偏好是完全不喝咖啡。',
        'status': 'superseded',
        'source_ids': ['${caseId}_input_05'],
      },
      {
        'id': '${caseId}_mem_coffee_latest',
        'content': '用户最新咖啡偏好是上午可以喝一杯，下午不喝。',
        'status': 'active',
        'source_ids': ['${caseId}_input_12'],
        'valid_from': '2026-05-12',
      },
      {
        'id': '${caseId}_mem_pause',
        'content': '${persona.pauseHabit}在 2026-05 暂停，2026-06 起恢复观察。',
        'status': 'active',
        'source_ids': ['${caseId}_input_18'],
        'valid_from': '2026-05-18',
        'valid_until': '2026-05-31',
      },
      {
        'id': '${caseId}_mem_no_guessing',
        'content': '没有记录时回答不确定，不要猜。',
        'status': 'active',
        'source_ids': ['${caseId}_input_24'],
      },
      {
        'id': '${caseId}_mem_project_owner',
        'content': '${persona.project}主要找${persona.owner}对齐。',
        'status': 'active',
        'source_ids': ['${caseId}_input_30'],
      },
    ];

List<JsonMap> _inputs({
  required String caseId,
  required _MemoryPersona persona,
}) {
  final rows = [
    '以后重要会议提前一天提醒我，尤其是${persona.project}相关评审。',
    persona.dietInput,
    '今天${persona.temporaryMood}，只是临时会太多，不要写成长期状态。',
    '今天只是想吃${persona.oneDayFood}，不是长期饮食偏好。',
    '先记一下，我完全不喝咖啡。',
    '同样提醒一下，我还是不喝咖啡，别重复写很多条。',
    '${persona.project}这周要看风险 owner 和回滚预案。',
    '临时咨询一下，怎么写一封更自然的催办消息，明天再整理。',
    '今天家庭里有点争执，这个很私密，不要写进长期记忆。',
    '最近工作日晚上尽量别安排长会。',
    '如果问我饮食，默认按前面那条忌口来。',
    '咖啡偏好更新：最近上午可以喝一杯，下午还是不喝。',
    '刚刚只是路过买了咖啡，不代表每天都喝。',
    '这周想试试早睡，先观察，不写长期习惯。',
    '重要会议提醒里最好带上议程和材料链接。',
    '我今天血压有点高，等医生确认前不要写成长期健康结论。',
    '${persona.project} owner 是 ${persona.owner}，这个可以长期记。',
    '${persona.pauseHabit}这个月先暂停，6月再看要不要恢复。',
    '今天只是想安静一下，不代表以后不要开会。',
    '周末可能去看展，不用写工作提醒。',
    '复盘里先区分事实、推测和建议。',
    '今天只是想吃${persona.oneDayFood}，仍然不是长期偏好。',
    '如果没有记录，回答我时直接说不确定，别猜。',
    '没有证据时不要编地点或时间。',
    '临时查一下${persona.project}竞品，不用写进长期记忆。',
    '我不想让家庭争执进入长期记忆。',
    '下次重要评审前一天提醒我准备截图。',
    '这周工作太碎，今天心情一般，不要写成长期。',
    '如果${persona.owner}提到风险，先问清楚影响范围。',
    '${persona.project}主要找${persona.owner}对齐。',
    '晚上九点后只提醒紧急事项。',
    '我喜欢中文总结，但保留英文 metric id。',
    '重复说一下，重要会议提前一天提醒，不用新增重复记忆。',
    '咖啡规则再确认：上午一杯可以，下午不喝。',
    '月底复盘要列成本、延迟和工具调用次数。',
    '${persona.pauseHabit}暂停只限这个月，不是永久取消。',
    '今天只是突然想买${persona.oneDayFood}，不要更新饮食偏好。',
    '如果我重复说同一条提醒，只合并证据，不要生成多条相似记忆。',
    '这周临时调休，不代表以后周三都空。',
    '问到${persona.project}时，优先引用最近的 owner 和风险记录。',
    '今天对${persona.owner}有点不耐烦，只是临时情绪，不要进长期画像。',
    '下个月如果恢复${persona.pauseHabit}，要把五月暂停理解成已过期。',
    '没有记录不要猜，我宁可看到“不确定”。',
    '如果健康相关只是当天状态，先不要写长期结论。',
    '同事反馈可以进项目事实，但不要写成我的个人偏好。',
    '饮食偏好以第二条为准，今天临时想吃的不算。',
    '咖啡以最新规则为准：上午可以，下午不喝。',
    '把这些长期偏好都保留 source，之后我要能追溯原句。',
  ];
  return [
    for (var i = 0; i < rows.length; i++)
      {
        'id': '${caseId}_input_${_two(i + 1)}',
        'time': _inputTime(i),
        'channel': i % 6 == 2 ? 'voice_transcript' : 'text',
        'content': rows[i],
      }
  ];
}

String _inputTime(int index) {
  final day = DateTime.utc(2026, 5, 1).add(Duration(days: index));
  final hour = [8, 14, 21][index % 3];
  return '2026-${_two(day.month)}-${_two(day.day)}T${_two(hour)}:'
      '${_two((index * 5) % 60)}:00+08:00';
}

JsonMap _taskTrace(String type) => {
      'event_type': 'task',
      'task_id': type,
      'task_type': type,
      'status': 'completed',
      'latency_ms': 1000,
    };

JsonMap _toolTrace(String name) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': 180,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 1100,
    };

String _two(int n) => n.toString().padLeft(2, '0');
String _three(int n) => n.toString().padLeft(3, '0');

class _MemoryPersona {
  const _MemoryPersona({
    required this.userId,
    required this.occupation,
    required this.city,
    required this.project,
    required this.owner,
    required this.dietInput,
    required this.dietMemory,
    required this.dietNeedles,
    required this.temporaryMood,
    required this.oneDayFood,
    required this.pauseHabit,
    required this.preference,
    required this.habits,
  });

  final String userId;
  final String occupation;
  final String city;
  final String project;
  final String owner;
  final String dietInput;
  final String dietMemory;
  final List<String> dietNeedles;
  final String temporaryMood;
  final String oneDayFood;
  final String pauseHabit;
  final String preference;
  final List<String> habits;
}

const _personas = [
  _MemoryPersona(
    userId: 'memory_life_u_001',
    occupation: '产品经理',
    city: '杭州',
    project: '导出项目',
    owner: 'Alex',
    dietInput: '点餐记一下：不要海鲜，少糖，晚上少咖啡。',
    dietMemory: '用户点餐不要海鲜、少糖，晚上少咖啡。',
    dietNeedles: ['不要海鲜', '少糖'],
    temporaryMood: '有点烦',
    oneDayFood: '奶茶',
    pauseHabit: '周三下午需求评审',
    preference: '结论先行',
    habits: ['周三下午需求评审', '晚上复盘'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_002',
    occupation: '跨境电商运营',
    city: '深圳',
    project: '北美站增长',
    owner: 'Jason',
    dietInput: '外卖偏好更新：不要海鲜，少糖，生冷先避开。',
    dietMemory: '用户外卖不要海鲜、少糖，生冷先避开。',
    dietNeedles: ['不要海鲜', '少糖'],
    temporaryMood: '心情差',
    oneDayFood: '冰美式',
    pauseHabit: '周三晚上健身',
    preference: '投流复盘先看异常',
    habits: ['周三晚上健身', '周末看望父母'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_003',
    occupation: '数据分析师',
    city: '上海',
    project: 'Memex eval',
    owner: 'Grace',
    dietInput: '午饭偏好：少油，别点海鲜，下午不要奶茶。',
    dietMemory: '用户午饭少油，不点海鲜，下午不要奶茶。',
    dietNeedles: ['少油', '海鲜'],
    temporaryMood: '不太想说话',
    oneDayFood: '炸鸡',
    pauseHabit: '周四 dashboard review',
    preference: '指标解释保留英文 metric id',
    habits: ['上午深度分析', '周四 dashboard review'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_004',
    occupation: '老师',
    city: '北京',
    project: '公开课改版',
    owner: 'Ada',
    dietInput: '上课前别给我订太辣的，也尽量不要冰饮。',
    dietMemory: '用户上课前不吃太辣，尽量不要冰饮。',
    dietNeedles: ['太辣', '冰饮'],
    temporaryMood: '嗓子不舒服',
    oneDayFood: '辣火锅',
    pauseHabit: '周三线上答疑',
    preference: '反馈不超过三条重点',
    habits: ['周三线上答疑', '课前两天准备讲义'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_005',
    occupation: '律师',
    city: '广州',
    project: '法务合同库',
    owner: 'Annie',
    dietInput: '加班餐清淡一点，不要海鲜，咖啡只放上午。',
    dietMemory: '用户加班餐清淡，不要海鲜，咖啡只放上午。',
    dietNeedles: ['清淡', '海鲜'],
    temporaryMood: '压力大',
    oneDayFood: '蛋糕',
    pauseHabit: '下午审合同',
    preference: '重要结论要列来源',
    habits: ['下午审合同', '周末陪家人'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_006',
    occupation: '财务主管',
    city: '成都',
    project: '预算月结',
    owner: 'Mina',
    dietInput: '月底加班餐别太油，少糖，不要生冷。',
    dietMemory: '用户月底加班餐不要太油、少糖、不要生冷。',
    dietNeedles: ['少糖', '生冷'],
    temporaryMood: '很累',
    oneDayFood: '麻辣烫',
    pauseHabit: '早上核对付款',
    preference: '数字先给口径',
    habits: ['月底结账', '早上核对付款'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_007',
    occupation: '内容运营',
    city: '苏州',
    project: '小红书活动',
    owner: 'Grace',
    dietInput: '拍摄当天午饭少糖少油，不要海鲜，避免犯困。',
    dietMemory: '用户拍摄当天午饭少糖少油，不要海鲜。',
    dietNeedles: ['少糖', '少油', '海鲜'],
    temporaryMood: '有点焦虑',
    oneDayFood: '奶油蛋糕',
    pauseHabit: '晚上看评论',
    preference: '复盘保留素材来源',
    habits: ['晚上看评论', '周五整理选题'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_008',
    occupation: '独立开发者',
    city: '厦门',
    project: '个人工具订阅',
    owner: '小陈',
    dietInput: '写代码时别给我安排高糖饮料，咖啡只上午喝。',
    dietMemory: '用户写代码时避免高糖饮料，咖啡只上午喝。',
    dietNeedles: ['高糖', '咖啡'],
    temporaryMood: '脑子有点空',
    oneDayFood: '可乐',
    pauseHabit: '晚上处理客服',
    preference: '少写空话',
    habits: ['上午写代码', '晚上处理客服'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_009',
    occupation: '医生',
    city: '南京',
    project: '门诊随访系统',
    owner: '周医生',
    dietInput: '值班餐尽量清淡，不要海鲜，夜里不要咖啡。',
    dietMemory: '用户值班餐清淡，不要海鲜，夜里不要咖啡。',
    dietNeedles: ['清淡', '海鲜', '咖啡'],
    temporaryMood: '嗓子有点哑',
    oneDayFood: '炸串',
    pauseHabit: '午后查房',
    preference: '医疗相关必须区分记录和建议',
    habits: ['午后查房', '周五整理随访'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_010',
    occupation: 'HRBP',
    city: '武汉',
    project: '绩效校准',
    owner: 'Sophie',
    dietInput: '面谈前别安排太甜的饮料，午饭尽量少油。',
    dietMemory: '用户面谈前避免太甜饮料，午饭尽量少油。',
    dietNeedles: ['太甜', '少油'],
    temporaryMood: '有点紧张',
    oneDayFood: '奶盖茶',
    pauseHabit: '周一招聘对齐',
    preference: '敏感信息少写细节',
    habits: ['周一对齐招聘', '月底做绩效复盘'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_011',
    occupation: '设计师',
    city: '长沙',
    project: '会员页改版',
    owner: 'Nora',
    dietInput: '评审日午饭少糖，不要冰饮，避免下午困。',
    dietMemory: '用户评审日午饭少糖，不要冰饮。',
    dietNeedles: ['少糖', '冰饮'],
    temporaryMood: '脑子很散',
    oneDayFood: '冰淇淋',
    pauseHabit: '周三设计评审',
    preference: '视觉反馈要带截图来源',
    habits: ['上午画稿', '周三设计评审'],
  ),
  _MemoryPersona(
    userId: 'memory_life_u_012',
    occupation: '创业者',
    city: '青岛',
    project: 'B 端试点',
    owner: 'Ethan',
    dietInput: '跑客户当天少糖少油，咖啡只上午喝。',
    dietMemory: '用户跑客户当天少糖少油，咖啡只上午喝。',
    dietNeedles: ['少糖', '少油', '咖啡'],
    temporaryMood: '压力有点大',
    oneDayFood: '烧烤',
    pauseHabit: '晚上复盘现金流',
    preference: '商务复盘先列风险和下一步',
    habits: ['早上跑客户', '晚上复盘现金流'],
  ),
];
