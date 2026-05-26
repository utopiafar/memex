import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _casesPerCategory = 16;
const _inputsPerHardCase = 14;
const _hardCategoriesPerPersona = 7;

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
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': _casesPerCategory,
    'case_count': cases.length,
    'input_count': inputCount,
    'inputs_per_case': _inputsPerHardCase,
    'inputs_per_persona_approx': _inputsPerHardCase * _hardCategoriesPerPersona,
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
      '同一个 hard_u_xx 会跨 7 类边界场景出现；每类场景带 $_inputsPerHardCase 条上下文输入，因此每个 hard persona 约 ${_inputsPerHardCase * _hardCategoriesPerPersona} 条输入。',
      '所有 oracle 来自 ground_truth_world 和 expected constraints。',
      '上下文输入刻意加入职业化口吻、碎碎念、无关背景和轻度冗余，避免挑战集只靠固定句式触发规则。',
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
          input: _cycle(_transientInputs, i),
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
                'must_include': [_cycle(_transientNeedles, i)],
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
                  'content': '用户长期${_cycle(_transientNeedles, i)}。',
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
          input: _cycle(_conflictInputs, i),
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
              '不是这周三，是${_ambiguousDateText(i)}晚上七点和${_people[i % _people.length]}在${_places[i % _places.length]}吃饭，帮我改一下。',
          expected: {
            'card_type': 'event',
            'time': _ambiguousIsoTime(i),
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
                  : _ambiguousIsoTime(i),
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
          input: _cycle(_retrievalInputs, i),
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
                  'source_snippets': const <JsonMap>[],
                }
              : {
                  'answer': '记录显示你在5月8日和 Jason 讨论过投流预算。',
                  'retrieved_sources': ['event_budget_$i', 'note_budget_$i'],
                  'cited_sources': ['event_budget_$i', 'note_budget_$i'],
                  'source_snippets': [
                    {
                      'source_id': 'event_budget_$i',
                      'snippet': '2026年5月8日 15:00，和 Jason 通过腾讯会议讨论投流预算。',
                    },
                    {
                      'source_id': 'note_budget_$i',
                      'snippet': 'Jason 讨论投流预算，重点看 CPA 和 ROAS。',
                    },
                  ],
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
          input: _cycle(_superAgentInputs, i),
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
            'source_snippets': [
              {
                'source_id': 'mem_diet_$i',
                'snippet': '用户饮食偏好：不要海鲜、少糖。',
              },
            ],
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
          input: _cycle(_scheduleInputs, i),
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
          input: _cycle(_pkmInputs, i),
          expected: {
            'expected_entries': [
              {
                'path_contains': ['Projects', 'Memex eval'],
                'content_contains': ['hit@k', 'MRR', '失败模式', '下一步'],
                'source_ids': ['input_hard_pkm_organization_${_two(i)}'],
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
                'source_ids': _seededFailure(i)
                    ? const <String>[]
                    : ['input_hard_pkm_organization_${_two(i)}'],
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
        'time': _hardInputTime(index, 0),
        'channel': index % 3 == 0 ? 'voice_transcript' : 'text',
        'content': input,
      },
      ..._hardContextInputs(
        category: category,
        index: index,
        caseId: id,
      ),
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
          'time': _ambiguousIsoTime(index),
          'location': _places[index % _places.length],
        }
      ],
    };
  }
  if (category == 'super_agent_boundary') {
    return {
      ...base,
      'memories': [
        {
          'id': 'mem_diet_$index',
          'content': '用户饮食偏好：不要海鲜、少糖。',
          'source_ids': ['input_hard_super_agent_boundary_${_two(index)}'],
        }
      ],
    };
  }
  return base;
}

bool _seededFailure(int index) =>
    index == 3 || index == 7 || index == 11 || index == 15;

String _cycle(List<String> values, int index) =>
    values[(index - 1) % values.length];

List<JsonMap> _hardContextInputs({
  required String category,
  required int index,
  required String caseId,
}) {
  final occupation = _occupations[index % _occupations.length];
  final city = _cities[index % _cities.length];
  return [
    for (var i = 1; i < _inputsPerHardCase; i++)
      {
        'id': 'context_${caseId}_${_two(i)}',
        'time': _hardInputTime(index, i),
        'channel': (index + i) % 4 == 0 ? 'voice_transcript' : 'text',
        'content': _hardContextContent(
          category: category,
          index: index,
          offset: i,
          occupation: occupation,
          city: city,
        ),
      }
  ];
}

String _hardContextContent({
  required String category,
  required int index,
  required int offset,
  required String occupation,
  required String city,
}) {
  final topic = _cycle(_hardNoiseTopics, index + offset);
  final person = _people[(index + offset) % _people.length];
  final place = _places[(index + offset) % _places.length];
  final workTexture = _occupationTexture(occupation, index + offset);
  final scenarioTexture = _categoryTexture(category, index + offset);
  final templates = [
    '刚在$city路上想起$topic，先碎碎念一句：$scenarioTexture',
    '作为$occupation，我临时问一下$topic 的写法，$workTexture',
    '$person 提到$topic 时要看原始来源，不要因为相似词就强行关联；这条可能只是背景。',
    '如果这条只是随手记录，就别自动触发后续动作。嗯，我现在只是怕忘。',
    '晚上可能去$place，但还没确定，后面问起来没有记录就说不确定。',
    '关于$topic，我更关心来源和时间，不要补没有出现过的地点。',
    '这周重复提到$topic 时，应该合并证据，不要生成很多近似条目。',
    '今天情绪一般，和$topic卡住有关，先别急着给我贴长期标签。',
    '如果我只是说“帮我看一下”，那就只读回答；别顺手改资料。',
    '把$topic 放到项目笔记时，别混进生活杂记，也别写入今天心情。',
    '日程相关内容只有明确时间和行动时才刷新，普通想法先跳过。',
    '$person 的反馈如果没有 source id，回答时要明确不确定。',
    '临时改期要覆盖旧时间，不能同时保留两个活跃日程。',
    '这句可能没啥用：刚才咖啡洒了一点，脑子短路，但$topic 这块明天还要看。',
    '语音转文字可能有错别字，$topic 相关内容最好结合前后文判断。',
    '$workTexture 另外，如果没有证据，少写一点也比编得完整好。',
    '$scenarioTexture 顺便把无关的心情、天气、路况都当噪声处理。',
  ];
  return templates[(offset - 1) % templates.length];
}

String _occupationTexture(String occupation, int seed) {
  final options = switch (occupation) {
    '数据分析师' => [
        'SQL 口径、dashboard 截图和临时判断别混在一起。',
        '如果涉及指标，先写口径，再写结论。',
      ],
    '跨境电商运营' => [
        '广告组、listing、物流和退款原因要拆开看。',
        '投流复盘先看异常，再看整体趋势。',
      ],
    '老师' => [
        '备课灵感和学生反馈不是同一种来源。',
        '课堂安排要保留日期，别只写“下次”。',
      ],
    _ => [
        '项目事实、个人偏好和临时状态要分开。',
        '结论可以短，但来源别丢。',
      ],
  };
  return options[seed.abs() % options.length];
}

String _categoryTexture(String category, int seed) {
  final options = switch (category) {
    'memory_transient' => [
        '今天这个状态大概只是被会打断了，不代表长期习惯。',
        '我只是当下有点烦，长期偏好还是要看反复出现的记录。',
      ],
    'memory_conflict' => [
        '旧说法和新说法撞上时，应该以最近明确更新为准。',
        '如果我说“改一下”，旧规则别继续当现行规则用。',
      ],
    'card_ambiguous_time' => [
        '我说“不是这周三”的时候，多半是在纠正旧日程。',
        '时间、地点、人物都要从句子里取，别自己补天气和价格。',
      ],
    'retrieval_grounding' => [
        '问历史记录时宁可慢一点，也别把没有来源的细节讲得很确定。',
        '同名人物和相似项目要用时间和来源再确认一次。',
      ],
    'super_agent_boundary' => [
        '只读查询就是只读，不要因为回答顺手写 memory。',
        '如果我说不要修改，工具调用也要克制一点。',
      ],
    'schedule_router' => [
        '只是心情或想法不用刷新日程，有明确时间再动。',
        '新增会议和普通随手记要区分，不然提醒会爆炸。',
      ],
    'pkm_organization' => [
        '项目复盘归项目，生活杂感不要混进去。',
        '整理笔记时保留来源，别把今天心情写进周报。',
      ],
    _ => [
        '这条只是背景，不要过度推断。',
        '先按来源和时间判断，不要凭感觉扩写。',
      ],
  };
  return options[seed.abs() % options.length];
}

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

String _hardInputTime(int index, int offset) {
  final date = DateTime.utc(2026, 5, 10 + index).add(Duration(days: offset));
  final hour = [9, 13, 20][offset % 3];
  return '${date.year}-${_two(date.month)}-${_two(date.day)}T'
      '${_two(hour)}:${_two((index * 3 + offset * 5) % 60)}:00+08:00';
}

String _ambiguousDateText(int index) {
  final date = DateTime.utc(2026, 5, 20).add(Duration(days: index - 1));
  return '${date.month}月${date.day}日';
}

String _ambiguousIsoTime(int index) {
  final date = DateTime.utc(2026, 5, 20).add(Duration(days: index - 1));
  return '${date.year}-${_two(date.month)}-${_two(date.day)}T19:00:00+08:00';
}

const _people = ['老王', 'Annie', 'Jason', 'Ada'];
const _places = ['望京', '腾讯会议', '公司楼下', '飞书会议'];
const _occupations = ['产品经理', '数据分析师', '跨境电商运营', '老师'];
const _cities = ['杭州', '上海', '深圳', '北京'];

const _hardNoiseTopics = [
  '会议提醒',
  '预算复盘',
  '饮食限制',
  '临时情绪',
  '客户反馈',
  '项目周报',
  '日程改期',
  '证据引用',
  'PKM 归档',
  '工具调用',
  '时间解析',
  '冲突记忆',
  '只读问答',
  '来源追溯',
];

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
