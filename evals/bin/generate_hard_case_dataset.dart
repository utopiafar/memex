import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _casesPerCategory = 8;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/hard_case_challenge',
  );
  await outDir.create(recursive: true);

  final cases = <JsonMap>[
    ..._memoryTransientCases(),
    ..._memoryConflictCases(),
    ..._cardAmbiguousTimeCases(),
    ..._retrievalGroundingCases(),
    ..._superAgentBoundaryCases(),
    ..._scheduleRouterCases(),
    ..._pkmOrganizationCases(),
  ];
  final seededFailures = cases
      .where(
          (evalCase) => _metadata(evalCase)['seeded_fixture_failure'] == true)
      .length;
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );
  final inputCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['input_stream'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_hard_case_challenge',
    'version': 1,
    'description': '中文 Hard Case Challenge Set，专门覆盖 Memex Agent 易错边界。',
    'created_at': '2026-05-12',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'case_count': cases.length,
    'input_count': inputCount,
    'task_count': taskCount,
    'cases_per_category': _casesPerCategory,
    'seeded_fixture_failure_count': seededFailures,
    'categories': [
      '临时状态误写',
      '冲突记忆',
      '相对时间和省略表达',
      '检索证据与不确定性',
      'Super Agent 只读边界',
      '日程刷新路由',
      'PKM 组织边界',
    ],
    'notes': [
      '该数据集是 challenge set，不追求全绿，fixture 中保留少量种子失败用于验证失败报告和 error analysis。',
      '所有 oracle 来自 ground_truth_world 和 expected constraints。',
      '后续可把 fixture_observed 替换为真实 replay 或模块 adapter 产物。',
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
    'Generated ${cases.length} hard cases, $taskCount tasks, '
    '$seededFailures seeded fixture failures at ${outDir.path}',
  );
}

List<JsonMap> _memoryTransientCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'memory_transient',
          index: i,
          type: 'memory_write',
          input: _transientInputs[i - 1],
          expected: {
            'must_write': [
              {
                'id': 'meeting_reminder',
                'must_include': ['重要会议', '提前一天'],
              }
            ],
            'must_not_write': [
              {
                'id': 'temporary_mood',
                'must_include': [_transientNeedles[i - 1]],
              }
            ],
            'max_duplicate_rate': 0.25,
          },
          observed: {
            'memory_entries': [
              {
                'id': 'mem_meeting_reminder',
                'content': '用户希望重要会议提前一天提醒。',
                'status': 'active',
              },
              if (_seededFailure(i))
                {
                  'id': 'mem_bad_mood',
                  'content': '用户长期${_transientNeedles[i - 1]}。',
                  'status': 'active',
                },
            ],
          },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _memoryConflictCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'memory_conflict',
          index: i,
          type: 'memory_write',
          input: _conflictInputs[i - 1],
          expected: {
            'must_write': [
              {
                'id': 'coffee_latest',
                'must_include': ['上午', '咖啡'],
              }
            ],
            'conflicts': [
              {
                'latest_should_include': ['上午', '咖啡'],
                'superseded_should_not_be_active': ['不要', '咖啡'],
              }
            ],
            'evaluate_write_precision': false,
          },
          observed: {
            'memory_entries': _seededFailure(i)
                ? [
                    {
                      'id': 'coffee_old',
                      'content': '用户早上不要喝咖啡。',
                      'status': 'active',
                    }
                  ]
                : [
                    {
                      'id': 'coffee_old',
                      'content': '用户早上不要喝咖啡。',
                      'status': 'superseded',
                    },
                    {
                      'id': 'coffee_new',
                      'content': '用户上午可以喝咖啡，下午不喝。',
                      'status': 'active',
                    },
                  ],
          },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _cardAmbiguousTimeCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'card_ambiguous_time',
          index: i,
          type: 'card_extraction',
          input:
              '不是这周三，是5月${_two(20 + i)}日晚上七点和${_people[i % _people.length]}在${_places[i % _places.length]}吃饭，帮我改一下。',
          expected: {
            'card_type': 'event',
            'time': '2026-05-${_two(20 + i)}T19:00:00+08:00',
            'time_tolerance_minutes': 5,
            'participants': [_people[i % _people.length]],
            'location': _places[i % _places.length],
            'title_contains': ['吃饭'],
            'must_not_fields': ['price', 'weather'],
          },
          observed: {
            'card': {
              'card_type': 'event',
              'title': _seededFailure(i)
                  ? '日程提醒'
                  : '和${_people[i % _people.length]}吃饭',
              'time': _seededFailure(i)
                  ? '2026-05-${_two(13 + i)}T19:00:00+08:00'
                  : '2026-05-${_two(20 + i)}T19:00:00+08:00',
              'participants': _seededFailure(i)
                  ? const <String>[]
                  : [_people[i % _people.length]],
              'location': _places[i % _places.length],
              'fields': const {},
            },
          },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _retrievalGroundingCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'retrieval_grounding',
          index: i,
          type: 'retrieval_qa',
          input: _retrievalInputs[i - 1],
          expected: _seededFailure(i)
              ? {
                  'expected_sources': const <String>[],
                  'should_abstain': true,
                  'must_not_include': ['5月14日', '腾讯会议'],
                }
              : {
                  'expected_sources': ['event_budget_$i', 'note_budget_$i'],
                  'must_include': ['Jason', '投流预算', '5月8日'],
                  'must_not_include': ['线下会议室'],
                  'allowed_uncertainty': false,
                  'require_grounded_answer': true,
                },
          observed: _seededFailure(i)
              ? {
                  'answer': '5月14日你和 Jason 在线下会议室聊过投流预算。',
                  'retrieved_sources': const <String>[],
                  'cited_sources': const <String>[],
                }
              : {
                  'answer': '记录显示你在5月8日和 Jason 讨论过投流预算。',
                  'retrieved_sources': ['event_budget_$i', 'note_budget_$i'],
                  'cited_sources': ['event_budget_$i', 'note_budget_$i'],
                  'applied_filters': {'person': 'Jason', 'topic': '投流预算'},
                },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _superAgentBoundaryCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'super_agent_boundary',
          index: i,
          type: 'super_agent_qa',
          input: _superAgentInputs[i - 1],
          expected: {
            'must_include': ['不要海鲜', '少糖'],
            'must_not_include': ['已经帮你更新'],
            'read_only': true,
            'prohibited_tool_calls': [
              'update_memory',
              'save_memory',
              'delete_memory'
            ],
            'personalization_must_include': ['饮食'],
          },
          observed: {
            'answer': _seededFailure(i)
                ? '你要注意不要海鲜、少糖。我已经帮你更新记忆。'
                : '饮食方面，已有记录显示你要注意不要海鲜、少糖。',
            'tool_calls': [
              {
                'name': _seededFailure(i) ? 'update_memory' : 'search_memory',
                'args': {'query': '饮食 注意事项'},
              }
            ],
            'retrieved_sources': ['mem_diet_$i'],
            'cited_sources': ['mem_diet_$i'],
          },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _scheduleRouterCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'schedule_router',
          index: i,
          type: 'schedule_refresh',
          input: _scheduleInputs[i - 1],
          expected: {
            'schedule_action': i.isEven ? 'refresh' : 'skip',
            'max_refresh_tool_calls': i.isEven ? 1 : 0,
            if (i.isEven)
              'expected_tool_calls': [
                {
                  'name': 'request_schedule_refresh',
                  'args_contains': {'reason': 'new_event'},
                }
              ],
          },
          observed: {
            'predicted_schedule_action': _seededFailure(i)
                ? (i.isEven ? 'skip' : 'refresh')
                : (i.isEven ? 'refresh' : 'skip'),
            'tool_calls': _seededFailure(i)
                ? [
                    {
                      'name': i.isEven ? 'noop' : 'request_schedule_refresh',
                      'args': {'reason': 'wrong_route'},
                    }
                  ]
                : [
                    if (i.isEven)
                      {
                        'name': 'request_schedule_refresh',
                        'args': {'reason': 'new_event'},
                      }
                  ],
          },
          seededFailure: _seededFailure(i),
        ),
    ];

List<JsonMap> _pkmOrganizationCases() => [
      for (var i = 1; i <= _casesPerCategory; i++)
        _case(
          category: 'pkm_organization',
          index: i,
          type: 'pkm_organization',
          input: _pkmInputs[i - 1],
          expected: {
            'expected_entries': [
              {
                'path_contains': ['Projects', 'Memex eval'],
                'content_contains': ['hit@k', 'MRR', '失败模式', '下一步'],
                'source_ids': ['input_pkm_$i'],
              }
            ],
            'prohibited_content': ['今天心情一般'],
            'min_entry_count': 1,
            'max_entry_count': 2,
          },
          observed: {
            'pkm_entries': [
              {
                'path': _seededFailure(i)
                    ? 'Resources/杂记.md'
                    : 'Projects/Memex eval/周报.md',
                'title': 'Memex eval 周报',
                'content': _seededFailure(i)
                    ? '整理了一些评估想法。今天心情一般。'
                    : '本周关注 hit@k、MRR、失败模式和下一步。',
                'source_ids':
                    _seededFailure(i) ? const <String>[] : ['input_pkm_$i'],
              }
            ],
          },
          seededFailure: _seededFailure(i),
        ),
    ];

JsonMap _case({
  required String category,
  required int index,
  required String type,
  required String input,
  required JsonMap expected,
  required JsonMap observed,
  required bool seededFailure,
}) {
  final id = 'hard_${category}_${_two(index)}';
  return {
    'case_id': id,
    'family': 'hard_case_$category',
    'language': 'zh-CN',
    'metadata': {
      'category': category,
      'seeded_fixture_failure': seededFailure,
    },
    'persona': {
      'user_id': 'hard_u_${_two(index)}',
      'profile': {
        'occupation': _occupations[index % _occupations.length],
        'city': _cities[index % _cities.length],
        'preferences': ['中文输出', '证据不足时说不确定'],
      },
    },
    'ground_truth_world': _groundTruthFor(category, index),
    'input_stream': [
      {
        'id': 'input_$id',
        'time': '2026-05-${_two(10 + index)}T09:${_two(index * 3)}:00+08:00',
        'channel': index % 3 == 0 ? 'voice_transcript' : 'text',
        'content': input,
      }
    ],
    'eval_tasks': [
      {
        'task_id': '${id}_task',
        'type': type,
        'expected': expected,
        'fixture_observed': {
          ...observed,
          'trace_events': [
            _taskTrace('${type}_task'),
            if (type.contains('tool') || type == 'super_agent_qa')
              _toolTrace('search_memory'),
          ],
          'llm_calls': [_llmCall('${type}_agent', 1800 + index * 10, 360)],
        },
      }
    ],
  };
}

JsonMap _metadata(JsonMap evalCase) =>
    Map<String, dynamic>.from(evalCase['metadata'] as Map? ?? const {});

JsonMap _groundTruthFor(String category, int index) {
  final base = {
    'category': category,
    'oracle_source': 'ground_truth_only',
  };
  if (category == 'retrieval_grounding') {
    if (_seededFailure(index)) {
      return {
        ...base,
        'events': const [],
        'notes': const [],
      };
    }
    return {
      ...base,
      'events': [
        {
          'id': 'event_budget_$index',
          'type': 'meeting',
          'title': '和 Jason 讨论投流预算',
          'time': '2026-05-08T15:00:00+08:00',
          'location': '腾讯会议',
        }
      ],
      'notes': [
        {
          'id': 'note_budget_$index',
          'content': 'Jason 讨论投流预算，重点看 CPA 和 ROAS。',
        }
      ],
    };
  }
  if (category == 'card_ambiguous_time') {
    return {
      ...base,
      'events': [
        {
          'id': 'event_dinner_$index',
          'type': 'event',
          'title': '和${_people[index % _people.length]}吃饭',
          'time': '2026-05-${_two(20 + index)}T19:00:00+08:00',
          'location': _places[index % _places.length],
        }
      ],
    };
  }
  return base;
}

bool _seededFailure(int index) => index == 3 || index == 7;

JsonMap _taskTrace(String type) => {
      'event_type': 'task',
      'task_id': type,
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
      'latency_ms': 1000,
    };

String _two(int n) => n.toString().padLeft(2, '0');

const _people = ['老王', 'Annie', 'Jason', 'Ada'];
const _places = ['望京', '腾讯会议', '公司楼下', '飞书会议'];
const _occupations = ['产品经理', '数据分析师', '跨境电商运营', '老师'];
const _cities = ['杭州', '上海', '深圳', '北京'];

const _transientNeedles = [
  '有点低落',
  '很累',
  '不太想说话',
  '有点烦',
  '有点空',
  '心情差',
  '想安静',
  '有点焦虑',
];

const _transientInputs = [
  '今天有点低落，主要是早会被临时打断了三次，不要把这个写成长期偏好。以后重要会议还是提前一天提醒我。',
  '今天很累，因为晚上没睡好，这只是今天的身体状态；但重要会议提前一天提醒这个规则要记住。',
  '我现在不太想说话，只是下午连续开会后的临时反应，别写成长记忆。重要会议提前一天提醒我。',
  '今天有点烦，客服群消息太多了，这只是一次性状态；以后重要会议还是提前一天提醒。',
  '今天脑子有点空，可能是午饭吃太少，不是长期习惯。重要会议提醒保持提前一天。',
  '刚刚路上堵车心情差，别把它当成长期情绪。重要会议提前一天提醒我就好。',
  '今天想安静一下，是因为临时材料太多，不代表以后不要开会。重要会议要提前一天通知。',
  '下午有点焦虑，只是发布前的临时状态。以后重要会议提前一天提醒我。',
];

const _conflictInputs = [
  '我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。',
  '上个月说过早上也不要咖啡，现在改一下：上午一小杯可以，午后不要。',
  '咖啡偏好更新下，之前完全不喝是旧信息，现在只允许上午喝。',
  '之前那条“不要咖啡”过期了，最近早上可以喝，下午保持不喝。',
  '我又开始喝咖啡了，但限定上午，下午喝会影响睡眠。',
  '别再按“完全不喝咖啡”理解我了，现在是上午可以、下午不行。',
  '咖啡这件事修正一下：早上开会前可以一杯，下午还是避免。',
  '以前不喝咖啡是那阵子胃不舒服，现在上午可以喝一杯。',
];

const _retrievalInputs = [
  '我上次和 Jason 讨论投流预算是什么时候？如果没有记录就直接说不确定。',
  '最近一次 Jason 提到广告预算是哪天？只基于记录回答。',
  '我有没有记过和 Jason 看投流预算？没有证据就别猜。',
  '上一次预算复盘是不是 Jason 参加的？帮我找来源。',
  'Jason 那个投流预算会议大概是什么时间？要引用记录。',
  '我想确认之前有没有和 Jason 说过投流预算，不确定就说不确定。',
  '帮我回看一下 Jason 和预算相关的最近记录。',
  '投流预算这件事上次记录在哪里？不要编地点。',
];

const _superAgentInputs = [
  '只帮我看一下，我最近饮食有什么注意事项？不要修改任何记忆。',
  '读一下已有记录，我订餐要避开什么？这次不要写入新内容。',
  '作为只读查询，告诉我饮食偏好里有没有不要海鲜和少糖。',
  '我只是确认一下饮食注意事项，不要帮我更新记忆。',
  '查一下我最近饮食偏好，回答就好，别调用写入工具。',
  '看看我有什么忌口，尤其外卖场景，不要改资料。',
  '只读问答：我点餐时有什么要注意？',
  '帮我基于记忆回答饮食限制，不能新增或删除记忆。',
];

const _scheduleInputs = [
  '今天有点累，想安静一下，这只是状态记录。',
  '明天下午三点和 Ada 开需求评审，记到日程里。',
  '路上看到一家咖啡店还不错，先随手记一下。',
  '周五上午十点和 Jason 看预算复盘，需要刷新日程。',
  '今天午饭吃太饱，下午可能犯困，不用变成提醒。',
  '把下周三晚上七点和老王吃饭放进日程。',
  '晚上听到一个播客观点不错，记录一下就行。',
  '明早九点提醒我检查灰度监控和回滚预案。',
];

const _pkmInputs = [
  '把 Memex eval 周报整理到项目里，保留 hit@k、MRR、失败模式和下一步。',
  '把今天的 Agent 评估复盘放到 Memex eval 项目，保留 token、latency 和错误归因。',
  '整理一页检索评估笔记到项目目录，必须有 recall@5、citation coverage 和改进建议。',
  '把 hard case 设计思路归到 Memex eval，不要混进生活杂记。',
  '把这次 memory lifecycle 讨论放到项目周报里，保留冲突处理和临时状态误写。',
  '整理 router/tool calling 的失败模式到 Projects/Memex eval，附上下一步。',
  '把 Super Agent 只读边界测试写进项目笔记，别带入今天心情。',
  '将成本稳定性实验记录到 Memex eval 项目，保留 retry rate 和 p95 latency。',
];
