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
  const personaTeacher = {
    'user_id': 'module_u_004',
    'profile': {
      'occupation': '高校老师',
      'city': '北京',
      'preferences': ['喜欢先看摘要', '提醒需要留出通勤时间'],
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
    ..._expandedCases(
      personaOps: personaOps,
      personaPm: personaPm,
      personaAnalyst: personaAnalyst,
      personaTeacher: personaTeacher,
    ),
  ];
}

List<JsonMap> _expandedCases({
  required JsonMap personaOps,
  required JsonMap personaPm,
  required JsonMap personaAnalyst,
  required JsonMap personaTeacher,
}) {
  return [
    {
      'case_id': 'module_card_task_002',
      'family': 'card_extraction',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'tasks': [
          {
            'id': 'task_card_002',
            'title': '给研究生开题报告写反馈',
            'due_time': '2026-05-15T21:00:00+08:00',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'input_card_002',
          'time': '2026-05-12T20:30:00+08:00',
          'channel': 'text',
          'content': '周五晚上九点前把小林的开题报告反馈写完，别忘了。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_card_task_002',
          'type': 'card_extraction',
          'expected': {
            'card_type': 'task',
            'time': '2026-05-15T21:00:00+08:00',
            'participants': ['小林'],
            'title_contains': ['开题报告', '反馈'],
            'entities': ['小林', '开题报告', '反馈'],
            'max_latency_ms': 6000,
            'must_not_fields': ['location'],
          },
          'fixture_observed': {
            'card': {
              'card_type': 'task',
              'title': '给小林的开题报告写反馈',
              'time': '2026-05-15T21:00:00+08:00',
              'participants': ['小林'],
              'fields': {'topic': '开题报告反馈'},
            },
            'latency_ms': 3200,
          },
        }
      ],
    },
    {
      'case_id': 'module_card_mixed_003',
      'family': 'card_extraction',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'notes': [
          {
            'id': 'note_card_003',
            'content': '用户今天对发布节奏有压力，但重点是记录灰度发布风险。',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'input_card_003',
          'time': '2026-05-13T11:10:00+08:00',
          'channel': 'text',
          'content': '今天有点焦虑，不过重点记一下：灰度发布风险是支付回调和老版本兼容。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_card_mixed_003',
          'type': 'card_extraction',
          'expected': {
            'card_type': 'note',
            'title_contains': ['灰度发布', '风险'],
            'field_contains': {
              'summary': ['支付回调', '老版本兼容'],
            },
            'entities': ['灰度发布', '支付回调', '老版本兼容'],
            'must_not_fields': ['event_time', 'meeting_room'],
            'max_latency_ms': 5000,
          },
          'fixture_observed': {
            'card': {
              'card_type': 'note',
              'title': '灰度发布风险记录',
              'fields': {'summary': '风险集中在支付回调和老版本兼容。'},
            },
            'latency_ms': 2800,
          },
        }
      ],
    },
    {
      'case_id': 'module_card_event_correction_004',
      'family': 'card_extraction',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'events': [
          {
            'id': 'event_card_004',
            'title': '和 Jason 复盘广告预算',
            'time': '2026-05-22T15:00:00+08:00',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'input_card_004a',
          'time': '2026-05-12T09:00:00+08:00',
          'channel': 'text',
          'content': 'Jason 那个预算会先记周四三点。',
        },
        {
          'id': 'input_card_004b',
          'time': '2026-05-12T09:05:00+08:00',
          'channel': 'text',
          'content': '不对，改到周五下午三点，主题是复盘广告预算。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_card_event_correction_004',
          'type': 'card_extraction',
          'expected': {
            'card_type': 'event',
            'time': '2026-05-22T15:00:00+08:00',
            'participants': ['Jason'],
            'title_contains': ['Jason', '广告预算'],
            'entities': ['Jason', '广告预算', '周五'],
            'status': 'active',
          },
          'fixture_observed': {
            'card': {
              'card_type': 'event',
              'status': 'active',
              'title': '和 Jason 复盘广告预算',
              'time': '2026-05-22T15:00:00+08:00',
              'participants': ['Jason'],
              'fields': {'day_hint': '周五'},
            },
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_health_002',
      'family': 'memory_write',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_memory_003', 'content': '用户对花生过敏。'},
          {'id': 'fact_memory_004', 'content': '用户这周嗓子不舒服，是临时状态。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_memory_003',
          'time': '2026-05-12T08:00:00+08:00',
          'channel': 'text',
          'content': '以后订下午茶记得避开花生，我对花生过敏。',
        },
        {
          'id': 'fact_memory_004',
          'time': '2026-05-12T08:10:00+08:00',
          'channel': 'text',
          'content': '这周嗓子不舒服，课间少说话就行，不用记长期。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_health_002',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_peanut_allergy',
                'must_include': ['花生', '过敏'],
                'source_ids': ['fact_memory_003'],
                'valid_from': '2026-05-12',
              }
            ],
            'must_not_write': [
              {
                'id': 'mem_sore_throat_week',
                'must_include': ['这周', '嗓子不舒服'],
              }
            ],
            'sensitive_must_not_write': [
              {
                'id': 'mem_health_overgeneralized',
                'must_include': ['长期', '嗓子'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [
              {
                'id': 'mem_peanut_allergy',
                'content': '用户对花生过敏，订下午茶需要避开花生。',
                'source_ids': ['fact_memory_003'],
                'valid_from': '2026-05-12',
                'status': 'active',
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_workhabit_003',
      'family': 'memory_write',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_memory_005', 'content': '用户希望上午深度分析，下午开会。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_memory_005',
          'time': '2026-05-13T09:00:00+08:00',
          'channel': 'text',
          'content': '以后上午尽量留给深度分析，下午再排会。',
        },
        {
          'id': 'fact_memory_006',
          'time': '2026-05-13T09:03:00+08:00',
          'channel': 'text',
          'content': '对，上午别打断我这个习惯挺重要的。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_workhabit_003',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_deep_work_morning',
                'must_include': ['上午', '深度分析', '下午', '开会'],
                'source_ids': ['fact_memory_005'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [
              {
                'id': 'mem_deep_work_morning',
                'content': '用户希望上午留给深度分析，下午开会。',
                'source_ids': ['fact_memory_005'],
                'status': 'active',
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_conflict_location_004',
      'family': 'memory_conflict',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_commute_old', 'content': '用户周三晚上通常在学校。'},
          {'id': 'fact_commute_new', 'content': '本学期周三晚上改为在家线上答疑。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_commute_old',
          'time': '2026-04-01T09:00:00+08:00',
          'channel': 'text',
          'content': '以前周三晚上我一般都在学校。',
        },
        {
          'id': 'fact_commute_new',
          'time': '2026-05-14T09:00:00+08:00',
          'channel': 'text',
          'content': '更新一下，本学期周三晚上改成在家线上答疑。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_conflict_location_004',
          'type': 'memory_write',
          'expected': {
            'must_write': [
              {
                'id': 'mem_wed_evening_online',
                'must_include': ['本学期', '周三晚上', '在家', '线上答疑'],
                'source_ids': ['fact_commute_new'],
                'valid_from': '2026-05-14',
              }
            ],
            'conflicts': [
              {
                'latest_should_include': ['周三晚上', '在家', '线上答疑'],
                'superseded_should_not_be_active': ['周三晚上', '学校'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [
              {
                'id': 'mem_wed_evening_school',
                'content': '用户周三晚上通常在学校。',
                'source_ids': ['fact_commute_old'],
                'status': 'superseded',
              },
              {
                'id': 'mem_wed_evening_online',
                'content': '本学期用户周三晚上在家线上答疑。',
                'source_ids': ['fact_commute_new'],
                'valid_from': '2026-05-14',
                'status': 'active',
              },
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_memory_temporary_mood_005',
      'family': 'memory_write',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_mood_001', 'content': '用户今天被客户催得烦，是临时情绪。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_mood_001',
          'time': '2026-05-13T18:00:00+08:00',
          'channel': 'text',
          'content': '今天被客户催得有点烦，先让我安静会儿，这不是长期偏好。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_memory_temporary_mood_005',
          'type': 'memory_write',
          'expected': {
            'must_not_write': [
              {
                'id': 'mem_always_quiet',
                'must_include': ['安静', '长期'],
              }
            ],
            'sensitive_must_not_write': [
              {
                'id': 'mem_customer_mood',
                'must_include': ['客户', '烦'],
              }
            ],
            'max_duplicate_rate': 0,
          },
          'fixture_observed': {
            'memory_entries': [],
          },
        }
      ],
    },
    {
      'case_id': 'module_retrieval_time_filter_002',
      'family': 'retrieval_qa',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'sources': [
          {'id': 'event_office_001', 'content': '5月18日10:00 和小林办公室讨论论文。'},
          {'id': 'event_office_002', 'content': '4月10日和小林讨论过开题。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_retrieval_time_filter_002',
          'type': 'retrieval_qa',
          'query': '我最近一次和小林讨论论文是什么时候？',
          'expected': {
            'expected_sources': ['event_office_001'],
            'expected_filters': {'person': '小林', 'time_range': '最近'},
            'must_include': ['5月18日', '10:00', '小林', '论文'],
            'must_not_include': ['4月10日'],
            'allowed_uncertainty': false,
            'require_grounded_answer': true,
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'event_office_001'},
              {'source_id': 'event_office_002'},
            ],
            'applied_filters': {'person': '小林', 'time_range': '最近'},
            'answer': '最近一次是5月18日10:00，你和小林讨论论文。',
            'cited_sources': ['event_office_001'],
          },
        }
      ],
    },
    {
      'case_id': 'module_retrieval_abstain_003',
      'family': 'retrieval_qa',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'sources': [],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_retrieval_abstain_003',
          'type': 'retrieval_qa',
          'query': '我上个月有没有和 Alex 聊过裁员计划？',
          'expected': {
            'expected_sources': [],
            'must_include': ['没有记录'],
            'must_not_include': ['裁员计划已确定'],
            'should_abstain': true,
          },
          'fixture_observed': {
            'retrieved_sources': [],
            'answer': '我没有记录你上个月和 Alex 聊过裁员计划，无法确认。',
            'cited_sources': [],
          },
        }
      ],
    },
    {
      'case_id': 'module_retrieval_project_filter_004',
      'family': 'retrieval_qa',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {
        'sources': [
          {
            'id': 'note_metric_001',
            'content': 'Memex eval 周报关注 retry rate 和队列等待。'
          },
          {'id': 'note_metric_002', 'content': 'CRM 看转化率。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_retrieval_project_filter_004',
          'type': 'retrieval_qa',
          'query': 'Memex eval 周报要盯哪些稳定性指标？',
          'expected': {
            'expected_sources': ['note_metric_001'],
            'expected_filters': {'project': 'Memex eval', 'type': 'note'},
            'must_include': ['retry rate', '队列等待'],
            'must_not_include': ['CRM', '转化率'],
            'allowed_uncertainty': false,
            'require_grounded_answer': true,
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'note_metric_001'},
              {'source_id': 'note_metric_002'},
            ],
            'applied_filters': {'project': 'Memex eval', 'type': 'note'},
            'answer': 'Memex eval 周报要盯 retry rate 和队列等待。',
            'cited_sources': ['note_metric_001'],
          },
        }
      ],
    },
    {
      'case_id': 'module_router_write_memory_002',
      'family': 'tool_calling',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'router_input_002',
          'time': '2026-05-12T12:00:00+08:00',
          'channel': 'text',
          'content': '以后排公开课提醒我提前两天准备讲义。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_router_write_memory_002',
          'type': 'tool_calling',
          'expected': {
            'router_label': 'memory_write',
            'expected_tool_calls': [
              {
                'name': 'update_memory',
                'args_contains': {'source_id': 'router_input_002'},
              }
            ],
            'prohibited_tool_calls': ['delete_memory'],
            'max_tool_calls': 2,
            'expected_trace_events': ['llm_call', 'update_memory'],
          },
          'fixture_observed': {
            'predicted_router_label': 'memory_write',
            'tool_calls': [
              {
                'name': 'update_memory',
                'args': {'source_id': 'router_input_002', 'mode': 'upsert'},
              }
            ],
            'trace_events': [
              {'event_type': 'llm_call', 'agent_name': 'router_agent'},
              {'event_type': 'tool_call', 'tool_name': 'update_memory'},
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_router_read_card_003',
      'family': 'tool_calling',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {},
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_router_read_card_003',
          'type': 'tool_calling',
          'expected': {
            'router_label': 'card_read',
            'expected_tool_calls': [
              {
                'name': 'get_timeline_card',
                'args_contains': {'card_id': 'card_release_risk'},
              }
            ],
            'prohibited_tool_calls': ['update_timeline_card'],
            'max_tool_calls': 1,
          },
          'fixture_observed': {
            'predicted_router_label': 'card_read',
            'tool_calls': [
              {
                'name': 'get_timeline_card',
                'args': {'card_id': 'card_release_risk'},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_router_pkm_write_004',
      'family': 'tool_calling',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'router_input_004',
          'time': '2026-05-12T15:00:00+08:00',
          'channel': 'text',
          'content': '把这次指标复盘整理到 Memex eval 项目笔记。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_router_pkm_write_004',
          'type': 'tool_calling',
          'expected': {
            'router_label': 'pkm_write',
            'expected_tool_calls': [
              {
                'name': 'write_pkm_entry',
                'args_contains': {'project': 'Memex eval'},
              }
            ],
            'max_tool_calls': 2,
            'expected_trace_events': ['write_pkm_entry'],
          },
          'fixture_observed': {
            'predicted_router_label': 'pkm_write',
            'tool_calls': [
              {
                'name': 'write_pkm_entry',
                'args': {'project': 'Memex eval', 'mode': 'append'},
              }
            ],
            'trace_events': [
              {'event_type': 'tool_call', 'tool_name': 'write_pkm_entry'},
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_schedule_dirty_003',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'schedule_input_003',
          'time': '2026-05-13T10:00:00+08:00',
          'channel': 'text',
          'content': '周五公开课地点从二教改到三教，提醒里也同步一下。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_dirty_003',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'dirty',
            'router_label': 'dirty',
            'expected_tool_calls': [
              {
                'name': 'mark_schedule_dirty',
                'args_contains': {'card_id': 'card_public_class'},
              }
            ],
            'max_refresh_tool_calls': 0,
          },
          'fixture_observed': {
            'predicted_schedule_action': 'dirty',
            'predicted_router_label': 'dirty',
            'tool_calls': [
              {
                'name': 'mark_schedule_dirty',
                'args': {'card_id': 'card_public_class'},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_schedule_cancel_004',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'schedule_input_004',
          'time': '2026-05-13T16:00:00+08:00',
          'channel': 'text',
          'content': '明天和 Alex 的需求评审取消了。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_cancel_004',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'refresh',
            'router_label': 'refresh',
            'expected_tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args_contains': {'reason': 'cancel_event'},
              }
            ],
            'max_refresh_tool_calls': 1,
          },
          'fixture_observed': {
            'predicted_schedule_action': 'refresh',
            'predicted_router_label': 'refresh',
            'tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args': {'reason': 'cancel_event', 'card_id': 'card_review'},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_schedule_skip_note_005',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'schedule_input_005',
          'time': '2026-05-13T18:00:00+08:00',
          'channel': 'text',
          'content': '今天复盘里记一下：异常值主要来自埋点延迟。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_skip_note_005',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'skip',
            'router_label': 'skip',
            'prohibited_tool_calls': ['request_schedule_refresh'],
            'max_refresh_tool_calls': 0,
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
      'case_id': 'module_schedule_recurring_006',
      'family': 'schedule_refresh',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'schedule_input_006',
          'time': '2026-05-14T09:00:00+08:00',
          'channel': 'text',
          'content': '本学期每周三晚上八点线上答疑，提前一天提醒。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_schedule_recurring_006',
          'type': 'schedule_refresh',
          'expected': {
            'schedule_action': 'refresh',
            'router_label': 'refresh',
            'expected_tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args_contains': {'recurrence': 'weekly'},
              }
            ],
            'max_refresh_tool_calls': 1,
          },
          'fixture_observed': {
            'predicted_schedule_action': 'refresh',
            'predicted_router_label': 'refresh',
            'tool_calls': [
              {
                'name': 'request_schedule_refresh',
                'args': {'recurrence': 'weekly', 'weekday': '三'},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_pkm_meeting_002',
      'family': 'pkm_organization',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {
        'facts': [
          {
            'id': 'fact_pkm_002',
            'content': '需求评审结论：先做导出，owner 是 Alex，下周五验收。',
          }
        ],
      },
      'input_stream': [
        {
          'id': 'fact_pkm_002',
          'time': '2026-05-13T17:00:00+08:00',
          'channel': 'text',
          'content': '需求评审结论记到项目里：先做导出，owner Alex，下周五验收。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_pkm_meeting_002',
          'type': 'pkm_organization',
          'expected': {
            'expected_entries': [
              {
                'path_contains': ['Projects', '需求评审'],
                'content_contains': ['先做导出', 'owner Alex', '下周五验收'],
                'source_ids': ['fact_pkm_002'],
                'updated_after': '2026-05-13T16:59:00+08:00',
              }
            ],
            'min_entry_count': 1,
            'max_entry_count': 1,
            'prohibited_content': ['今天有点累'],
          },
          'fixture_observed': {
            'pkm_entries': [
              {
                'path': 'PKM/Projects/需求评审/结论.md',
                'title': '需求评审结论',
                'content': '先做导出；owner Alex；下周五验收。',
                'source_ids': ['fact_pkm_002'],
                'updated_at': '2026-05-13T17:01:00+08:00',
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_pkm_learning_003',
      'family': 'pkm_organization',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'facts': [
          {
            'id': 'fact_pkm_003',
            'content': '论文阅读笔记：核心是 retrieval eval 的 MRR 和 recall。'
          },
          {'id': 'fact_pkm_004', 'content': '后续要补 hit@k 对比。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_pkm_003',
          'time': '2026-05-14T20:00:00+08:00',
          'channel': 'text',
          'content': '论文阅读笔记：retrieval eval 重点是 MRR 和 recall。',
        },
        {
          'id': 'fact_pkm_004',
          'time': '2026-05-14T20:20:00+08:00',
          'channel': 'text',
          'content': '同一篇笔记里再补一句，后续要加 hit@k 对比。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_pkm_learning_003',
          'type': 'pkm_organization',
          'expected': {
            'expected_entries': [
              {
                'path_contains': ['Areas', '学习'],
                'content_contains': ['MRR', 'recall', 'hit@k'],
                'source_ids': ['fact_pkm_003', 'fact_pkm_004'],
              }
            ],
            'min_entry_count': 1,
            'max_entry_count': 1,
          },
          'fixture_observed': {
            'pkm_entries': [
              {
                'path': 'PKM/Areas/学习/Retrieval Eval.md',
                'title': 'Retrieval Eval 阅读笔记',
                'content': '重点关注 MRR、recall，并补充 hit@k 对比。',
                'source_ids': ['fact_pkm_003', 'fact_pkm_004'],
                'updated_at': '2026-05-14T20:25:00+08:00',
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_pkm_travel_004',
      'family': 'pkm_organization',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'facts': [
          {'id': 'fact_pkm_005', 'content': '周末去广州看父母，带降压药和保温杯。'},
        ],
      },
      'input_stream': [
        {
          'id': 'fact_pkm_005',
          'time': '2026-05-15T12:00:00+08:00',
          'channel': 'text',
          'content': '周末去广州看爸妈，备忘里写：带降压药和保温杯。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_pkm_travel_004',
          'type': 'pkm_organization',
          'expected': {
            'expected_entries': [
              {
                'path_contains': ['Resources', '家庭'],
                'content_contains': ['广州', '爸妈', '降压药', '保温杯'],
                'source_ids': ['fact_pkm_005'],
              }
            ],
            'prohibited_content': ['酒店已预订'],
            'min_entry_count': 1,
            'max_entry_count': 1,
          },
          'fixture_observed': {
            'pkm_entries': [
              {
                'path': 'PKM/Resources/家庭/周末探望父母.md',
                'title': '周末去广州看爸妈',
                'content': '需要带降压药和保温杯。',
                'source_ids': ['fact_pkm_005'],
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_super_agent_personalized_002',
      'family': 'super_agent_qa',
      'language': 'zh-CN',
      'persona': personaTeacher,
      'ground_truth_world': {
        'memory': [
          {'id': 'mem_commute_buffer', 'content': '公开课提醒要留出通勤时间。'},
          {'id': 'mem_summary_first', 'content': '用户喜欢先看摘要。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_super_agent_personalized_002',
          'type': 'super_agent_qa',
          'query': '明天公开课提醒我时要注意什么？',
          'expected': {
            'expected_sources': ['mem_commute_buffer', 'mem_summary_first'],
            'must_include': ['先看摘要', '留出通勤时间'],
            'personalization_must_include': ['先看摘要', '通勤时间'],
            'allowed_uncertainty': false,
            'read_only': true,
            'expected_tool_calls': [
              {
                'name': 'search_memory',
                'args_contains': {'query': '公开课 提醒'},
              }
            ],
            'max_tool_calls': 1,
            'prohibited_tool_calls': ['update_memory'],
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'mem_commute_buffer'},
              {'source_id': 'mem_summary_first'},
            ],
            'answer': '提醒时先看摘要，并明确留出通勤时间。',
            'cited_sources': ['mem_commute_buffer', 'mem_summary_first'],
            'tool_calls': [
              {
                'name': 'search_memory',
                'args': {'query': '公开课 提醒', 'limit': 5},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_super_agent_clarify_003',
      'family': 'super_agent_qa',
      'language': 'zh-CN',
      'persona': personaOps,
      'ground_truth_world': {
        'memory': [],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_super_agent_clarify_003',
          'type': 'super_agent_qa',
          'query': '我上次说的那个客户预算到底是多少？',
          'expected': {
            'expected_sources': [],
            'must_include': ['没有找到', '客户预算'],
            'must_not_include': ['预算是10万'],
            'should_clarify': true,
            'read_only': true,
            'prohibited_tool_calls': ['update_memory', 'write_pkm_entry'],
          },
          'fixture_observed': {
            'retrieved_sources': [],
            'answer': '我没有找到明确的客户预算记录，需要你补充是哪个客户或哪次会议。',
            'cited_sources': [],
            'tool_calls': [
              {
                'name': 'search_memory',
                'args': {'query': '客户预算', 'limit': 5},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_super_agent_conflict_004',
      'family': 'super_agent_qa',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {
        'memory': [
          {'id': 'mem_old', 'content': '用户以前晚上分析数据。', 'status': 'superseded'},
          {'id': 'mem_new', 'content': '用户现在上午做深度分析，下午开会。'},
        ],
      },
      'input_stream': [],
      'eval_tasks': [
        {
          'task_id': 'task_super_agent_conflict_004',
          'type': 'super_agent_qa',
          'query': '明天上午适合安排数据分析吗？',
          'expected': {
            'expected_sources': ['mem_new'],
            'must_include': ['上午', '深度分析', '适合'],
            'must_not_include': ['晚上分析数据'],
            'allowed_uncertainty': false,
            'read_only': true,
            'personalization_must_include': ['上午', '深度分析'],
          },
          'fixture_observed': {
            'retrieved_sources': [
              {'source_id': 'mem_new'},
              {'source_id': 'mem_old'},
            ],
            'answer': '适合。你现在的习惯是上午做深度分析，下午开会。',
            'cited_sources': ['mem_new'],
            'tool_calls': [
              {
                'name': 'search_memory',
                'args': {'query': '上午 数据分析', 'limit': 5},
              }
            ],
          },
        }
      ],
    },
    {
      'case_id': 'module_cost_trace_queue_002',
      'family': 'cost_trace',
      'language': 'zh-CN',
      'persona': personaAnalyst,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'cost_input_002',
          'time': '2026-05-12T10:00:00+08:00',
          'channel': 'text',
          'content': '记录一下今天指标复盘。',
        },
        {
          'id': 'cost_input_003',
          'time': '2026-05-12T10:05:00+08:00',
          'channel': 'text',
          'content': '补充一个异常值说明。',
        },
      ],
      'eval_tasks': [
        {
          'task_id': 'task_cost_trace_queue_002',
          'type': 'cost_trace',
          'expected': {
            'max_total_tokens': 18000,
            'max_tokens_per_input': 9000,
            'max_latency_ms': 35000,
            'max_tool_calls': 6,
            'max_retry_rate': 0,
            'max_failed_task_rate': 0,
            'max_queue_idle_ms': 5000,
            'require_all_tasks_completed': true,
            'expected_trace_events': ['task', 'tool_call', 'llm_call'],
            'must_include': ['Facts', 'Cards'],
          },
          'fixture_observed': {
            'answer': '本次链路写入 Facts 和 Cards，任务全部完成。',
            'input_count': 2,
            'queue_idle_ms': 1200,
            'llm_calls': [
              {
                'agent_name': 'card_agent',
                'prompt_tokens': 3500,
                'completion_tokens': 700,
                'total_tokens': 4200,
                'latency_ms': 9000,
              }
            ],
            'trace_events': [
              {
                'event_type': 'task',
                'task_type': 'card_agent_task',
                'status': 'completed',
                'latency_ms': 9000,
              },
              {
                'event_type': 'tool_call',
                'tool_name': 'update_timeline_card',
                'latency_ms': 120,
              }
            ],
            'tasks_settled': true,
          },
        }
      ],
    },
    {
      'case_id': 'module_cost_trace_stability_003',
      'family': 'cost_trace',
      'language': 'zh-CN',
      'persona': personaPm,
      'ground_truth_world': {},
      'input_stream': [
        {
          'id': 'cost_input_004',
          'time': '2026-05-12T11:00:00+08:00',
          'channel': 'text',
          'content': '把发布风险和 owner 记一下。',
        }
      ],
      'eval_tasks': [
        {
          'task_id': 'task_cost_trace_stability_003',
          'type': 'cost_trace',
          'expected': {
            'max_total_tokens': 10000,
            'max_tokens_per_input': 10000,
            'max_latency_ms': 25000,
            'max_tool_calls': 5,
            'max_retry_rate': 0,
            'max_failed_task_rate': 0,
            'require_all_tasks_completed': true,
            'expected_trace_events': ['task', 'tool_call'],
            'must_include': ['owner'],
          },
          'fixture_observed': {
            'answer': '发布风险和 owner 已记录。',
            'input_count': 1,
            'llm_calls': [
              {
                'agent_name': 'pkm_agent',
                'prompt_tokens': 2400,
                'completion_tokens': 600,
                'total_tokens': 3000,
                'latency_ms': 7000,
              }
            ],
            'trace_events': [
              {
                'event_type': 'task',
                'task_type': 'pkm_agent_task',
                'status': 'completed',
                'latency_ms': 7000,
              },
              {
                'event_type': 'tool_call',
                'tool_name': 'write_pkm_entry',
                'latency_ms': 90,
              }
            ],
            'tasks_settled': true,
          },
        }
      ],
    },
  ];
}
