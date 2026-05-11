import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/v1_medium',
  );
  await outDir.create(recursive: true);

  final cases = <JsonMap>[];
  final profiles = _buildProfiles(50);
  for (var i = 0; i < profiles.length; i++) {
    final n = i + 1;
    final profile = profiles[i];
    cases.add(_cardCase(n, profile));
    cases.add(_memoryCase(n, profile, includeTransientMistake: n % 10 == 0));
    cases.add(_retrievalCase(n, profile));
    cases.add(_toolCase(n, profile));
    if (n % 5 == 0) {
      cases.add(_costCase(n, profile));
    }
  }

  final manifest = {
    'dataset_id': 'memex_agent_eval_v1_medium',
    'version': 1,
    'description':
        'Medium deterministic zh-CN benchmark for Memex Agent eval harness.',
    'created_at': '2026-05-11',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'user_input_language': 'zh-CN',
    'oracle_language': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': profiles.length,
    'case_count': cases.length,
    'families': [
      'card_extraction',
      'memory_write',
      'retrieval_qa',
      'tool_calling',
      'cost_trace',
    ],
    'notes': [
      'Generated deterministically by evals/bin/generate_medium_dataset.dart.',
      'All persona metadata and user inputs target zh-CN users.',
      'Ground truth is the only oracle source.',
      'fixture_observed is only for harness and grader regression tests.',
      'A small number of intentional fixture mistakes are retained for failure-mode reporting.',
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
    'Generated ${cases.length} cases for ${profiles.length} personas at ${outDir.path}',
  );
}

JsonMap _cardCase(int n, JsonMap profile) {
  final userId = _userId(n);
  final person = _people[n % _people.length];
  final place = _places[n % _places.length];
  final topic = _topics[n % _topics.length];
  final day = 12 + (n % 10);
  final hour = 9 + (n % 8);
  final timeIso = '2026-05-${_two(day)}T${_two(hour)}:30:00+08:00';
  final inputId = 'input_${_three(n)}_card';
  final eventId = 'event_${_three(n)}';

  return {
    'case_id': 'medium_card_${_three(n)}',
    'family': 'card_extraction',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'events': [
        {
          'id': eventId,
          'type': 'meeting',
          'title': '和$person讨论$topic',
          'time': timeIso,
          'location': place,
          'participants': [person],
        }
      ],
      'facts': [],
    },
    'input_stream': [
      {
        'id': inputId,
        'time': '2026-05-11T08:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content':
            '帮我记一下，${_weekday(n)}${_timeText(hour)}和$person在$place讨论$topic。',
      }
    ],
    'eval_tasks': [
      {
        'task_id': 'medium_card_${_three(n)}_t1',
        'type': 'card_extraction',
        'expected': {
          'card_type': 'event',
          'time': timeIso,
          'time_tolerance_minutes': 5,
          'participants': [person],
          'location': place,
          'title_contains': [topic],
          'must_not_fields': ['price', 'weather'],
        },
        'fixture_observed': {
          'card': {
            'card_type': 'event',
            'title': '和$person讨论$topic',
            'time': timeIso,
            'participants': [person],
            'location': place,
            'fields': {'source_id': inputId},
          },
          'trace_events': [
            _toolTrace('card_agent', 'save_timeline_card', 500 + n),
          ],
          'llm_calls': [_llmCall('card_agent', 1600 + n, 220)],
        },
      }
    ],
  };
}

JsonMap _memoryCase(
  int n,
  JsonMap profile, {
  required bool includeTransientMistake,
}) {
  final userId = _userId(n);
  final inputA = 'input_${_three(n)}_memory_a';
  final inputB = 'input_${_three(n)}_memory_b';
  final preference = _preferences[n % _preferences.length];
  final transient = _transients[n % _transients.length];
  final entries = <JsonMap>[
    {
      'memory_id': 'mem_${_three(n)}_a',
      'content': preference['memory'],
      'source_ids': [inputA],
      'status': 'active',
    }
  ];
  if (includeTransientMistake) {
    entries.add({
      'memory_id': 'mem_${_three(n)}_noise',
      'content': transient['bad_memory'],
      'source_ids': [inputB],
      'status': 'active',
    });
  }

  return {
    'case_id': 'medium_memory_${_three(n)}',
    'family': 'memory_write',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'facts': [
        {
          'id': 'fact_pref_${_three(n)}',
          'type': 'preference',
          'content': preference['fact'],
          'valid_from': '2026-05-11',
        }
      ],
    },
    'input_stream': [
      {
        'id': inputA,
        'time': '2026-05-11T10:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content': preference['input'],
      },
      {
        'id': inputB,
        'time': '2026-05-11T11:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content': transient['input'],
      },
    ],
    'eval_tasks': [
      {
        'task_id': 'medium_memory_${_three(n)}_t1',
        'type': 'memory_write',
        'expected': {
          'must_write': [
            {
              'id': 'fact_pref_${_three(n)}',
              'must_include': preference['needles'],
              'source_ids': [inputA],
            }
          ],
          'must_not_write': [
            {
              'id': 'transient_${_three(n)}',
              'must_include': transient['needles'],
            }
          ],
          'max_duplicate_rate': 0.0,
        },
        'fixture_observed': {
          'memory_entries': entries,
          'trace_events': [
            _toolTrace('memory_agent', 'append_memories', 430 + n),
          ],
          'llm_calls': [_llmCall('memory_agent', 1400 + n, 180)],
        },
      }
    ],
  };
}

JsonMap _retrievalCase(int n, JsonMap profile) {
  final userId = _userId(n);
  final person = _people[(n + 3) % _people.length];
  final project = _projects[n % _projects.length];
  final factId = 'fact_retrieval_${_three(n)}';
  final eventId = 'event_retrieval_${_three(n)}';
  final day = 13 + (n % 9);
  final hour = 14 + (n % 4);

  return {
    'case_id': 'medium_retrieval_${_three(n)}',
    'family': 'retrieval_qa',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'facts': [
        {
          'id': factId,
          'type': 'project_note',
          'content': '$project 的风险点是上线前要补齐灰度监控和回滚预案。',
          'valid_from': '2026-05-11',
        }
      ],
      'events': [
        {
          'id': eventId,
          'type': 'meeting',
          'title': '和$person复盘$project',
          'time': '2026-05-${_two(day)}T${_two(hour)}:00:00+08:00',
          'location': '飞书会议',
          'participants': [person],
        }
      ],
    },
    'input_stream': [
      {
        'id': 'input_${_three(n)}_retrieval_a',
        'time': '2026-05-11T13:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content': '$project 的风险点先记一下：上线前要补齐灰度监控和回滚预案。',
      },
      {
        'id': 'input_${_three(n)}_retrieval_b',
        'time': '2026-05-11T13:${_two((n + 10) % 60)}:00+08:00',
        'channel': 'text',
        'content': '${_weekday(n)}下午$hour点和$person复盘$project，飞书会议。',
      },
    ],
    'eval_tasks': [
      {
        'task_id': 'medium_retrieval_${_three(n)}_t1',
        'type': 'retrieval_qa',
        'query': '$project 下次和谁复盘？有什么风险要注意？',
        'expected': {
          'expected_sources': [eventId, factId],
          'must_include': [person, project, '灰度监控', '回滚预案'],
          'must_not_include': ['线下会议室', '已经上线'],
          'allowed_uncertainty': false,
        },
        'fixture_observed': {
          'retrieved_sources': [eventId, factId, 'note_noise_${_three(n)}'],
          'answer': '你会和$person复盘$project。风险上，要注意上线前补齐灰度监控和回滚预案。',
          'cited_sources': [eventId, factId],
          'source_snippets': [
            {'source_id': eventId, 'snippet': '和$person复盘$project，地点飞书会议。'},
            {'source_id': factId, 'snippet': '$project 风险：灰度监控和回滚预案。'},
          ],
          'trace_events': [
            _toolTrace('memex_agent', 'hybrid_search', 260 + n),
          ],
          'llm_calls': [_llmCall('memex_agent', 2200 + n, 240)],
        },
      }
    ],
  };
}

JsonMap _toolCase(int n, JsonMap profile) {
  final userId = _userId(n);
  final person = _people[(n + 5) % _people.length];
  final actionKind = n % 4;
  final content = switch (actionKind) {
    0 => '把明天上午10点和$person同步${_topics[n % _topics.length]}加到日历。',
    1 => '提醒我周五下班前把${_projects[n % _projects.length]}周报发出去。',
    2 => '我之前说过沟通风格上有什么偏好吗？',
    _ => '这条只是随手感慨一下，今天节奏有点碎。',
  };
  final expected = switch (actionKind) {
    0 => {
        'expected_tool_calls': [
          {
            'name': 'create_calendar_event',
            'args_contains': {
              'title': '同步${_topics[n % _topics.length]}',
              'start_time': '2026-05-12 10:00:00',
            },
          }
        ],
        'prohibited_tool_calls': ['append_memories'],
        'router_label': 'calendar_create',
      },
    1 => {
        'expected_tool_calls': [
          {
            'name': 'create_reminder',
            'args_contains': {'title': '周报', 'due_time': '2026-05-15'},
          }
        ],
        'prohibited_tool_calls': ['create_calendar_event'],
        'router_label': 'reminder_create',
      },
    2 => {
        'expected_tool_calls': [
          {
            'name': 'Read',
            'args_contains': {'file_path': 'memory'},
          }
        ],
        'prohibited_tool_calls': ['append_memories', 'create_calendar_event'],
        'router_label': 'read_only_query',
      },
    _ => {
        'expected_tool_calls': [],
        'prohibited_tool_calls': [
          'append_memories',
          'create_calendar_event',
          'create_reminder',
        ],
        'router_label': 'skip',
      },
  };
  final calls = switch (actionKind) {
    0 => [
        {
          'name': 'create_calendar_event',
          'args': {
            'title': '同步${_topics[n % _topics.length]}',
            'start_time': '2026-05-12 10:00:00',
            'participants': [person],
          },
        }
      ],
    1 => [
        {
          'name': 'create_reminder',
          'args': {'title': '发送周报', 'due_time': '2026-05-15 18:00:00'},
        }
      ],
    2 => [
        {
          'name': 'Read',
          'args': {'file_path': '/workspace/$userId/_System/memory.json'},
        }
      ],
    _ => const <JsonMap>[],
  };

  return {
    'case_id': 'medium_tool_${_three(n)}',
    'family': 'tool_calling',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'facts': [
        {
          'id': 'fact_tool_${_three(n)}',
          'type': 'preference',
          'content': '用户希望助手在能判断时直接给建议，少问澄清问题。',
        }
      ],
    },
    'input_stream': [
      {
        'id': 'input_${_three(n)}_tool',
        'time': '2026-05-11T15:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content': content,
      }
    ],
    'eval_tasks': [
      {
        'task_id': 'medium_tool_${_three(n)}_t1',
        'type': 'tool_calling',
        'expected': expected,
        'fixture_observed': {
          'predicted_router_label': expected['router_label'],
          'tool_calls': calls,
          'trace_events': calls
              .map(
                (call) => _toolTrace(
                  'memex_agent',
                  call['name'].toString(),
                  300 + n,
                ),
              )
              .toList(),
          'llm_calls': [_llmCall('memex_agent', 1700 + n, 190)],
        },
      }
    ],
  };
}

JsonMap _costCase(int n, JsonMap profile) {
  final userId = _userId(n);
  final project = _projects[n % _projects.length];
  return {
    'case_id': 'medium_cost_${_three(n)}',
    'family': 'cost_trace',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'facts': [
        {
          'id': 'fact_cost_${_three(n)}',
          'type': 'project_note',
          'content': '$project 最近三次实验分别提升点击、降低成本、暴露履约风险。',
        }
      ],
    },
    'input_stream': [
      {
        'id': 'input_${_three(n)}_cost',
        'time': '2026-05-11T17:${_two(n % 60)}:00+08:00',
        'channel': 'text',
        'content': '帮我简短回顾$project 最近三次实验，控制在几句话。',
      }
    ],
    'eval_tasks': [
      {
        'task_id': 'medium_cost_${_three(n)}_t1',
        'type': 'cost_trace',
        'expected': {
          'max_total_tokens': 8000,
          'max_latency_ms': 7000,
          'max_tool_calls': 3,
          'must_include': [project, '点击', '成本', '履约风险'],
        },
        'fixture_observed': {
          'answer': '$project 最近三次实验可以概括为：点击有提升，成本有下降，但也暴露了履约风险。',
          'trace_events': [
            _toolTrace('memex_agent', 'hybrid_search', 300 + n),
            _toolTrace('memex_agent', 'Read', 180 + n),
          ],
          'llm_calls': [
            _llmCall('memex_agent', 2600 + n, 320),
            _llmCall('memex_agent', 1800 + n, 220),
          ],
        },
      }
    ],
  };
}

JsonMap _toolTrace(String agent, String tool, int latencyMs) => {
      'event_type': 'tool_call',
      'agent_name': agent,
      'tool_name': tool,
      'latency_ms': latencyMs,
      'tool_args': const <String, dynamic>{},
    };

JsonMap _llmCall(String agent, int promptTokens, int completionTokens) => {
      'agent_name': agent,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 1800 + (promptTokens % 900),
    };

String _userId(int n) => 'eval_medium_${_three(n)}';
String _three(int n) => n.toString().padLeft(3, '0');
String _two(int n) => n.toString().padLeft(2, '0');
String _weekday(int n) => ['周二', '周三', '周四', '周五'][n % 4];
String _timeText(int hour) {
  if (hour < 12) return '上午$hour点半';
  if (hour == 12) return '中午12点半';
  return '下午${hour - 12}点半';
}

List<JsonMap> _buildProfiles(int count) => [
      for (var i = 0; i < count; i++)
        {
          'occupation': _occupations[i % _occupations.length],
          'city': _cities[i % _cities.length],
          'habits': [_habits[i % _habits.length]],
          'preferences': [_profilePrefs[i % _profilePrefs.length]],
        }
    ];

const _occupations = [
  '跨境电商运营',
  '产品经理',
  '独立开发者',
  '市场经理',
  '律师',
  '财务主管',
  '内容运营',
  '咨询顾问',
  '游戏策划',
  '数据分析师',
];

const _cities = ['深圳', '杭州', '上海', '北京', '广州', '成都', '苏州', '厦门', '南京', '武汉'];
const _habits = ['每周三健身', '周末看望父母', '上午深度工作', '晚上复盘当天工作', '通勤路上听播客'];
const _profilePrefs = [
  '喜欢提前一天提醒',
  '不喜欢太长的总结',
  '重要事项要列来源',
  '能判断时少问澄清',
  '偏好中文输出'
];
const _people = ['Jason', 'Ada', '老王', 'Annie', 'Leo', 'Mina', '小陈', 'Grace'];
const _places = ['腾讯会议', '飞书会议', '望京', '深圳湾办公室', '公司 12 楼会议室', '线上会议'];
const _topics = ['投流预算', '版本灰度', '客户续约', '活动复盘', '合同风险', '数据看板'];
const _projects = ['北美站增长', '会员召回', 'Memex eval', '法务合同库', '数据中台', '小红书活动'];

const _preferences = [
  {
    'input': '以后重要会议尽量提前一天提醒我，别临近了才说。',
    'fact': '用户喜欢重要会议提前一天提醒。',
    'memory': '用户喜欢重要会议提前一天提醒。',
    'needles': ['重要会议', '提前一天'],
  },
  {
    'input': '我一般上午适合深度工作，下午再安排同步会。',
    'fact': '用户偏好上午深度工作，下午开同步会。',
    'memory': '用户偏好上午深度工作，下午开同步会。',
    'needles': ['上午', '深度工作', '下午'],
  },
  {
    'input': '以后给我项目结论时，最好带上来源，不要只给判断。',
    'fact': '用户希望项目结论带来源。',
    'memory': '用户希望项目结论带来源。',
    'needles': ['项目结论', '来源'],
  },
];

const _transients = [
  {
    'input': '我今天上午想安静一会儿，但只是今天。',
    'bad_memory': '用户今天上午想安静一会儿。',
    'needles': ['今天上午', '安静'],
  },
  {
    'input': '今天突然想喝奶茶，别当成长期习惯。',
    'bad_memory': '用户今天想喝奶茶。',
    'needles': ['奶茶'],
  },
  {
    'input': '这周先别给我排太满，下周再恢复正常。',
    'bad_memory': '用户不喜欢排太满。',
    'needles': ['排太满'],
  },
];
