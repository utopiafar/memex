import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final rootDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/modules',
  );
  await rootDir.create(recursive: true);

  final allCases = _cases();
  final suites = _moduleSuites();
  final generated = <JsonMap>[];

  for (final suite in suites) {
    final suiteId = suite['id'] as String;
    final familyIds = (suite['families'] as List).cast<String>().toSet();
    final cases = allCases
        .where((evalCase) => familyIds.contains(evalCase['family']))
        .toList(growable: false);
    if (cases.isEmpty) {
      throw StateError('No cases matched module suite $suiteId');
    }

    final outDir = Directory('${rootDir.path}/$suiteId');
    await outDir.create(recursive: true);
    final manifest = _manifestForSuite(
      suite: suite,
      cases: cases,
    );

    await File('${outDir.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    await File('${outDir.path}/cases.jsonl').writeAsString(
      '${cases.map(jsonEncode).join('\n')}\n',
      flush: true,
    );

    generated.add({
      'dataset_id': manifest['dataset_id'],
      'path': '${rootDir.path}/$suiteId',
      'case_count': manifest['case_count'],
      'task_count': manifest['task_count'],
      'families': manifest['families'],
    });
  }

  final collectionManifest = {
    'dataset_id': 'memex_module_smoke_collection',
    'version': 2,
    'description': '中文小样本模块级 Agent eval 数据集集合。每个模块独立成一个小实验，便于单独定位回归。',
    'created_at': '2026-05-12',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'datasets': generated,
    'notes': [
      '所有 persona、输入、oracle 均为中文。',
      'fixture_observed 只用于验证 grader 和指标口径，不代表真实链路产物。',
      '标准答案只来自 ground_truth_world，不从 Memex 输出反推。',
      '模块实验只做局部能力和指标口径验证；端到端质量由 full_chain_serial_smoke 覆盖。',
    ],
  };
  await File('${rootDir.path}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(collectionManifest),
    flush: true,
  );

  stdout.writeln(
    'Generated ${generated.length} module smoke datasets at ${rootDir.path}',
  );
}

List<JsonMap> _moduleSuites() {
  return const [
    {
      'id': 'card_extraction',
      'title': 'Card 抽取',
      'description': '验证自然输入到 card 的结构化抽取，包括类型、时间、人物、地点、标题和幻觉字段。',
      'families': ['card_extraction'],
    },
    {
      'id': 'memory',
      'title': '记忆写入与冲突',
      'description': '验证长期记忆该写是否写、不该写是否过滤，以及新旧偏好冲突是否正确处理。',
      'families': ['memory_write', 'memory_conflict'],
    },
    {
      'id': 'retrieval_qa',
      'title': '检索问答',
      'description': '验证查询时是否召回正确来源，并基于证据回答。',
      'families': ['retrieval_qa'],
    },
    {
      'id': 'router_tool_calling',
      'title': 'Router 与工具调用',
      'description': '验证路由标签、工具选择、工具参数和禁止工具调用。',
      'families': ['tool_calling'],
    },
    {
      'id': 'schedule_refresh',
      'title': '日程刷新',
      'description': '验证日程相关输入是否正确 skip / dirty / refresh，并控制不必要刷新。',
      'families': ['schedule_refresh'],
    },
    {
      'id': 'pkm_organization',
      'title': 'PKM 整理',
      'description': '验证知识条目是否落到正确路径、保留关键信息并引用来源。',
      'families': ['pkm_organization'],
    },
    {
      'id': 'super_agent_qa',
      'title': 'Super Agent 问答',
      'description': '验证 Super Agent 是否基于记忆和来源回答，并遵守只读/写入边界。',
      'families': ['super_agent_qa'],
    },
    {
      'id': 'cost_trace',
      'title': '成本与 Trace',
      'description': '验证 token、延迟、工具调用数量和任务收敛是否在预算内。',
      'families': ['cost_trace'],
    },
  ];
}

JsonMap _manifestForSuite({
  required JsonMap suite,
  required List<JsonMap> cases,
}) {
  final families =
      cases.map((evalCase) => evalCase['family'] as String).toSet();
  return {
    'dataset_id': 'memex_module_${suite['id']}_smoke',
    'version': 2,
    'title': suite['title'],
    'description': suite['description'],
    'created_at': '2026-05-12',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'case_count': cases.length,
    'persona_count': _personaCount(cases),
    'input_count': cases.fold<int>(
      0,
      (sum, evalCase) =>
          sum + ((evalCase['input_stream'] as List?)?.length ?? 0),
    ),
    'task_count': cases.fold<int>(
      0,
      (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
    ),
    'families': families.toList()..sort(),
    'notes': [
      '所有 persona、输入、oracle 均为中文。',
      'fixture_observed 只用于验证 grader 和指标口径，不代表真实链路产物。',
      '标准答案只来自 ground_truth_world，不从 Memex 输出反推。',
    ],
  };
}

int _personaCount(List<JsonMap> cases) {
  final userIds = <String>{};
  for (final evalCase in cases) {
    final persona = evalCase['persona'];
    if (persona is Map && persona['user_id'] != null) {
      userIds.add(persona['user_id'].toString());
    }
  }
  return userIds.length;
}

List<JsonMap> _cases() {
  const personaOps = {
    'user_id': 'module_u_001',
    'profile': {
      'occupation': '跨境电商运营',
      'city': '深圳',
      'preferences': ['偏好中文输出', '重要事项提前提醒'],
    },
  };
  const personaPm = {
    'user_id': 'module_u_002',
    'profile': {
      'occupation': '产品经理',
      'city': '杭州',
      'preferences': ['结论先行', '保留来源'],
    },
  };
  const personaAnalyst = {
    'user_id': 'module_u_003',
    'profile': {
      'occupation': '数据分析师',
      'city': '上海',
      'preferences': ['关注异常值', '不喜欢无来源判断'],
    },
  };

  return [
    {
      'case_id': 'module_card_event_001',
      'family': 'card_extraction',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'events': [
          {
            'id': 'event_card_001',
            'title': '和 Jason 讨论投流预算',
            'time': '2026-05-20T19:00:00+08:00',
            'location': '望京',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'input_card_001',
          'time': '2026-05-12T09:00:00+08:00',
          'channel': 'text',
          'content': '下周三晚上七点提醒我去望京和 Jason 讨论投流预算。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_card_event_001',
          'type': 'card_extraction',
          'expected': {
            'card_type': 'event',
            'time': '2026-05-20T19:00:00+08:00',
            'participants': ['Jason'],
            'location': '望京',
            'title_contains': ['Jason', '投流预算'],
            'must_not_fields': ['weather', 'price'],
          },
          'fixture_observed': {
            'card': {
              'card_type': 'event',
              'title': '和 Jason 讨论投流预算',
              'time': '2026-05-20T19:00:00+08:00',
              'participants': ['Jason'],
              'location': '望京',
              'fields': {'topic': '投流预算'},
            },
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_write_001',
      'family': 'memory_write',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'facts': [
          {
            'id': 'fact_memory_001',
            'content': '用户希望重要会议提前一天提醒。',
          },
          {
            'id': 'fact_memory_002',
            'content': '用户今天上午想安静一会儿，只是临时状态。',
          },
        ],
      },
      'input_stream': [
        {
          'id': 'fact_memory_001',
          'time': '2026-05-12T10:00:00+08:00',
          'channel': 'text',
          'content': '以后重要会议尽量提前一天提醒我，别临近了才说。',
        },
        {
          'id': 'fact_memory_002',
          'time': '2026-05-12T10:30:00+08:00',
          'channel': 'text',
          'content': '我今天上午想安静一会儿，这只是今天。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_write_001',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_meeting_reminder',
                'must_include': ['重要会议', '提前一天提醒'],
                'source_ids': ['fact_memory_001'],
              }
            ],
            'must_not_write': [
              {
                'id': 'mem_today_quiet',
                'must_include': ['今天上午', '安静'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [
              {
                'id': 'mem_meeting_reminder',
                'content': '用户希望重要会议提前一天提醒。',
                'source_ids': ['fact_memory_001'],
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_conflict_001',
      'family': 'memory_conflict',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_coffee_old', 'content': '用户不喝咖啡。'},
          {'id': 'fact_coffee_new', 'content': '用户最近上午可以喝一杯咖啡，下午不喝。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_coffee_old',
          'time': '2026-05-01T09:00:00+08:00',
          'channel': 'text',
          'content': '我不喝咖啡，早上也不要。',
        },
        {
          'id': 'fact_coffee_new',
          'time': '2026-05-12T09:00:00+08:00',
          'channel': 'text',
          'content': '我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_conflict_001',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_coffee_latest',
                'must_include': ['上午', '可以喝一杯', '咖啡'],
                'source_ids': ['fact_coffee_new'],
              }
            ],
            'conflicts': [
              {
                'latest_should_include': ['上午', '可以喝一杯', '咖啡'],
                'superseded_should_not_be_active': ['早上', '不要', '咖啡'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [
              {
                'id': 'mem_coffee_old',
                'content': '用户早上不要咖啡。',
                'source_ids': ['fact_coffee_old'],
                'status': 'superseded',
              },
              {
                'id': 'mem_coffee_latest',
                'content': '用户最近上午可以喝一杯咖啡，下午不喝。',
                'source_ids': ['fact_coffee_new'],
                'status': 'active',
              },
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_retrieval_qa_001',
      'family': 'retrieval_qa',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'sources': [
          {'id': 'event_014', 'content': '周四15:00 和 Jason 讨论投流预算。'},
          {'id': 'fact_001', 'content': '用户不吃海鲜。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_retrieval_qa_001',
          'type': 'retrieval_qa',
          'query': '我周四下午有什么安排？顺便有什么饮食注意事项？',
          'expected': {
            'expected_sources': ['event_014', 'fact_001'],
            'must_include': ['周四15:00', 'Jason', '投流预算', '不要吃海鲜'],
            'must_not_include': ['线下会议室', '晚餐'],
            'allowed_uncertainty': false,
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'event_014'},
              {'source_id': 'fact_001'},
              {'source_id': 'note_other'},
            ],
            'answer': '你周四15:00要和 Jason 讨论投流预算。饮食上记得不要吃海鲜。',
            'cited_sources': ['event_014', 'fact_001'],
          },
        }
      ],
    },
    {
      'case_id': 'module_router_tool_001',
      'family': 'tool_calling',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {},
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_router_tool_001',
          'type': 'tool_calling',
          'expected': {
            'router_label': 'memory_read',
            'expected_tool_calls': [
              {
                'name': 'search_memory',
                'args_contains': {'query': '咖啡'},
              }
            ],
            'prohibited_tool_calls': ['update_memory', 'delete_card'],
          },
          'fixture_observed': {
            'predicted_router_label': 'memory_read',
            'tool_calls': [
              {
                'name': 'search_memory',
                'args': {'query': '咖啡', 'limit': 5},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_schedule_refresh_001',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {},
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_refresh_001',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'refresh',
            'router_label': 'refresh',
            'expected_tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args_contains': {'card_id': 'card_meeting_budget'},
              }
            ],
          },
          'fixture_observed': {
            'predicted_schedule_action': 'refresh',
            'predicted_router_label': 'refresh',
            'tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args': {'card_id': 'card_meeting_budget'},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_schedule_skip_001',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {},
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_skip_001',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'skip',
            'router_label': 'skip',
            'prohibited_tool_calls': ['request_schedule_refresh'],
          },
          'fixture_observed': {
            'predicted_schedule_action': 'skip',
            'predicted_router_label': 'skip',
            'tool_calls': [],
          },
        }
      ],
    },
    {
      'case_id': 'module_pkm_organization_001',
      'family': 'pkm_organization',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {
        'facts': [
          {
            'id': 'fact_pkm_001',
            'content': 'Memex eval 项目周报需要记录风险、owner 和回滚预案。',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'fact_pkm_001',
          'time': '2026-05-12T16:00:00+08:00',
          'channel': 'text',
          'content': 'Memex eval 周报重点写风险、owner 和回滚预案。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_pkm_organization_001',
          'type': 'pkm_organization',
          'expected': {
            'expected_entries': [
              {
                'path_contains': ['Projects', 'Memex eval'],
                'content_contains': ['风险', 'owner', '回滚预案'],
                'source_ids': ['fact_pkm_001'],
              }
            ],
            'prohibited_content': ['今天心情不好'],
          },
          'fixture_observed': {
            'pkm_entries': [
              {
                'path': 'PKM/Projects/Memex eval/周报.md',
                'title': 'Memex eval 周报',
                'content': '重点记录风险、owner 和回滚预案。',
                'source_ids': ['fact_pkm_001'],
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_super_agent_qa_001',
      'family': 'super_agent_qa',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'memory': [
          {'id': 'mem_coffee_latest', 'content': '用户最近上午可以喝一杯咖啡，下午不喝。'},
          {'id': 'mem_meeting_reminder', 'content': '重要会议提前一天提醒用户。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_super_agent_qa_001',
          'type': 'super_agent_qa',
          'query': '我现在早上能喝咖啡吗？重要会议提醒偏好是什么？',
          'expected': {
            'expected_sources': ['mem_coffee_latest', 'mem_meeting_reminder'],
            'must_include': ['上午可以喝一杯咖啡', '重要会议', '提前一天提醒'],
            'must_not_include': ['完全不喝咖啡'],
            'allowed_uncertainty': false,
            'read_only': true,
            'expected_tool_calls': [
              {
                'name': 'search_memory',
                'args_contains': {'query': '咖啡 重要会议'},
              }
            ],
            'prohibited_tool_calls': ['update_memory', 'delete_memory'],
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'mem_coffee_latest'},
              {'source_id': 'mem_meeting_reminder'},
            ],
            'answer': '可以。你最近的偏好是上午可以喝一杯咖啡，下午别喝；重要会议希望提前一天提醒。',
            'cited_sources': ['mem_coffee_latest', 'mem_meeting_reminder'],
            'tool_calls': [
              {
                'name': 'search_memory',
                'args': {'query': '咖啡 重要会议', 'limit': 5},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_cost_trace_001',
      'family': 'cost_trace',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {},
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_cost_trace_001',
          'type': 'cost_trace',
          'expected': {
            'max_total_tokens': 12000,
            'max_latency_ms': 30000,
            'max_tool_calls': 8,
            'require_all_tasks_completed': true,
            'must_include': ['Facts', 'Cards'],
          },
          'fixture_observed': {
            'answer': '本次链路写入 Facts 和 Cards，任务全部完成。',
            'llm_calls': [
              {
                'agent_name': 'card_agent',
                'prompt_tokens': 2000,
                'completion_tokens': 500,
                'total_tokens': 2500,
                'latency_ms': 8000,
              }
            ],
            'trace_events': [
              {
                'event_type': 'task',
                'task_type': 'card_agent_task',
                'status': 'completed',
                'latency_ms': 8000,
              },
              {
                'event_type': 'tool_call',
                'tool_name': 'update_timeline_card',
                'latency_ms': 100,
              }
            ],
            'tasks_settled': true,
          },
        }
      ],
    },
  ];
}
