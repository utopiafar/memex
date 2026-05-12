import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/v1_medium',
  );
  await outDir.create(recursive: true);

  final cases = <JsonMap>[];
  final profiles = _buildProfiles(80);
  for (var i = 0; i < profiles.length; i++) {
    final n = i + 1;
    final profile = profiles[i];
    cases.add(_longHorizonCase(n, profile));
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
      'long_horizon_timeline',
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
      'Each persona includes a 60-input long-horizon timeline with work, life, emotion, temporary consultation, preferences, and conflicts.',
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

JsonMap _longHorizonCase(int n, JsonMap profile) {
  final userId = _userId(n);
  final person = _people[(n + 2) % _people.length];
  final parentDay = 18 + (n % 8);
  final project = _projects[n % _projects.length];
  final preference = _preferences[n % _preferences.length];
  final conflict = _conflicts[n % _conflicts.length];
  final emotion = _emotions[n % _emotions.length];
  final hobby = _hobbies[n % _hobbies.length];
  final consultation = _consultations[n % _consultations.length];
  final sourcePrefix = 'long_${_three(n)}';
  final parentInputId = '${sourcePrefix}_parent_visit';
  final preferenceInputId = '${sourcePrefix}_preference';
  final conflictOldInputId = '${sourcePrefix}_conflict_old';
  final conflictNewInputId = '${sourcePrefix}_conflict_new';
  final projectRiskInputId = '${sourcePrefix}_project_risk';
  final projectMeetingInputId = '${sourcePrefix}_project_meeting';
  final transientInputId = '${sourcePrefix}_transient_emotion';
  final consultationInputId = '${sourcePrefix}_consultation';
  final inputStream = _longInputs(
    n: n,
    person: person,
    project: project,
    parentDay: parentDay,
    preferenceInput: preference['input'].toString(),
    conflictOldInput: conflict['old_input'].toString(),
    conflictNewInput: conflict['new_input'].toString(),
    emotionInput: emotion['input'].toString(),
    hobbyInput: hobby['input'].toString(),
    consultationInput: consultation['input'].toString(),
    ids: {
      'parent': parentInputId,
      'preference': preferenceInputId,
      'conflict_old': conflictOldInputId,
      'conflict_new': conflictNewInputId,
      'project_risk': projectRiskInputId,
      'project_meeting': projectMeetingInputId,
      'transient': transientInputId,
      'consultation': consultationInputId,
    },
  );
  final memoryEntries = [
    {
      'memory_id': '${sourcePrefix}_mem_preference',
      'content': preference['memory'],
      'source_ids': [preferenceInputId],
      'status': 'active',
    },
    {
      'memory_id': '${sourcePrefix}_mem_conflict_old',
      'content': conflict['old_memory'],
      'source_ids': [conflictOldInputId],
      'status': 'superseded',
    },
    {
      'memory_id': '${sourcePrefix}_mem_conflict_new',
      'content': conflict['new_memory'],
      'source_ids': [conflictNewInputId],
      'status': 'active',
    },
  ];

  return {
    'case_id': 'medium_long_${_three(n)}',
    'family': 'long_horizon_timeline',
    'language': 'zh-CN',
    'persona': {'user_id': userId, 'profile': profile},
    'ground_truth_world': {
      'facts': [
        {
          'id': '${sourcePrefix}_fact_preference',
          'type': 'preference',
          'content': preference['fact'],
          'valid_from': '2026-05-08',
        },
        {
          'id': '${sourcePrefix}_fact_conflict_new',
          'type': 'preference',
          'content': conflict['new_fact'],
          'valid_from': '2026-05-21',
          'supersedes': '${sourcePrefix}_fact_conflict_old',
        },
        {
          'id': '${sourcePrefix}_fact_project_risk',
          'type': 'project_note',
          'content': '$project 要注意灰度监控、客服话术和回滚预案。',
          'valid_from': '2026-05-19',
        },
      ],
      'events': [
        {
          'id': '${sourcePrefix}_event_parent_visit',
          'type': 'personal',
          'title': '周末看望父母',
          'time': '2026-05-${_two(parentDay)}T10:00:00+08:00',
          'location': '父母家',
        },
        {
          'id': '${sourcePrefix}_event_project_meeting',
          'type': 'meeting',
          'title': '和$person复盘$project',
          'time': '2026-05-${_two(20 + (n % 6))}T15:00:00+08:00',
          'location': '飞书会议',
          'participants': [person],
        },
      ],
    },
    'input_stream': inputStream,
    'eval_tasks': [
      {
        'task_id': 'medium_long_${_three(n)}_memory',
        'type': 'memory_write',
        'expected': {
          'must_write': [
            {
              'id': '${sourcePrefix}_fact_preference',
              'must_include': preference['needles'],
              'source_ids': [preferenceInputId],
            },
            {
              'id': '${sourcePrefix}_fact_conflict_new',
              'must_include': conflict['new_needles'],
              'source_ids': [conflictNewInputId],
            },
          ],
          'must_not_write': [
            {
              'id': '${sourcePrefix}_transient_emotion',
              'must_include': emotion['needles'],
            },
            {
              'id': '${sourcePrefix}_consultation_noise',
              'must_include': consultation['noise_needles'],
            },
          ],
          'max_duplicate_rate': 0.0,
        },
        'fixture_observed': {
          'memory_entries': memoryEntries,
          'trace_events': [
            _toolTrace('memory_agent', 'append_memories', 600 + n),
            _toolTrace('memory_agent', 'update_memory_status', 610 + n),
          ],
          'llm_calls': [_llmCall('memory_agent', 3000 + n, 420)],
        },
      },
      {
        'task_id': 'medium_long_${_three(n)}_retrieval_project',
        'type': 'retrieval_qa',
        'query': '$project 后面要注意什么？我和谁什么时候复盘？',
        'expected': {
          'expected_sources': [
            '${sourcePrefix}_fact_project_risk',
            '${sourcePrefix}_event_project_meeting',
          ],
          'must_include': [project, person, '灰度监控', '回滚预案'],
          'must_not_include': ['线下会议室', '已经全部完成'],
          'allowed_uncertainty': false,
        },
        'fixture_observed': {
          'retrieved_sources': [
            '${sourcePrefix}_fact_project_risk',
            '${sourcePrefix}_event_project_meeting',
            '${sourcePrefix}_life_noise',
          ],
          'answer': '$project 后面要注意灰度监控、客服话术和回滚预案；你会和$person在飞书会议复盘。',
          'cited_sources': [
            '${sourcePrefix}_fact_project_risk',
            '${sourcePrefix}_event_project_meeting',
          ],
          'source_snippets': [
            {
              'source_id': '${sourcePrefix}_fact_project_risk',
              'snippet': '$project 风险：灰度监控、客服话术、回滚预案。',
            },
            {
              'source_id': '${sourcePrefix}_event_project_meeting',
              'snippet': '和$person复盘$project，地点飞书会议。',
            },
          ],
          'trace_events': [
            _toolTrace('memex_agent', 'hybrid_search', 500 + n),
            _toolTrace('memex_agent', 'rerank_sources', 520 + n),
          ],
          'llm_calls': [_llmCall('memex_agent', 3600 + n, 360)],
        },
      },
      {
        'task_id': 'medium_long_${_three(n)}_retrieval_life',
        'type': 'retrieval_qa',
        'query': '我这周末有什么生活安排？',
        'expected': {
          'expected_sources': ['${sourcePrefix}_event_parent_visit'],
          'must_include': ['看望父母'],
          'must_not_include': ['加班', '客户续约'],
          'allowed_uncertainty': false,
        },
        'fixture_observed': {
          'retrieved_sources': [
            '${sourcePrefix}_event_parent_visit',
            '${sourcePrefix}_hobby_note',
          ],
          'answer': '你这周末安排了去看望父母。',
          'cited_sources': ['${sourcePrefix}_event_parent_visit'],
          'source_snippets': [
            {
              'source_id': '${sourcePrefix}_event_parent_visit',
              'snippet': '周末上午去父母家看望父母。',
            },
          ],
          'trace_events': [_toolTrace('memex_agent', 'hybrid_search', 450 + n)],
          'llm_calls': [_llmCall('memex_agent', 2600 + n, 260)],
        },
      },
      {
        'task_id': 'medium_long_${_three(n)}_tool_skip',
        'type': 'tool_calling',
        'expected': {
          'expected_tool_calls': [],
          'prohibited_tool_calls': [
            'append_memories',
            'create_calendar_event',
            'create_reminder',
          ],
          'router_label': 'skip',
        },
        'fixture_observed': {
          'predicted_router_label': 'skip',
          'tool_calls': const <JsonMap>[],
          'trace_events': const <JsonMap>[],
          'llm_calls': [_llmCall('memex_agent', 1800 + n, 180)],
        },
      },
      {
        'task_id': 'medium_long_${_three(n)}_cost',
        'type': 'cost_trace',
        'expected': {
          'max_total_tokens': 16000,
          'max_latency_ms': 12000,
          'max_tool_calls': 6,
          'must_include': [project, '父母', '回滚预案'],
        },
        'fixture_observed': {
          'answer': '$project 要注意灰度监控和回滚预案；生活上这周末要看望父母。',
          'trace_events': [
            _toolTrace('memex_agent', 'hybrid_search', 520 + n),
            _toolTrace('memex_agent', 'Read', 260 + n),
            _toolTrace('memex_agent', 'rerank_sources', 300 + n),
          ],
          'llm_calls': [
            _llmCall('memex_agent', 3800 + n, 420),
            _llmCall('memex_agent', 2400 + n, 260),
          ],
        },
      },
    ],
  };
}

List<JsonMap> _longInputs({
  required int n,
  required String person,
  required String project,
  required int parentDay,
  required String preferenceInput,
  required String conflictOldInput,
  required String conflictNewInput,
  required String emotionInput,
  required String hobbyInput,
  required String consultationInput,
  required Map<String, String> ids,
}) {
  final inputs = <JsonMap>[];
  void add(String id, int day, int hour, String content) {
    inputs.add({
      'id': id,
      'time':
          '2026-05-${_two(day)}T${_two(hour)}:${_two((n + inputs.length) % 60)}:00+08:00',
      'channel': 'text',
      'content': content,
    });
  }

  add('${ids['preference']}', 6, 9, preferenceInput);
  add('${ids['conflict_old']}', 7, 10, conflictOldInput);
  add('${ids['transient']}', 8, 21, emotionInput);
  add('${ids['consultation']}', 9, 14, consultationInput);
  add('${ids['parent']}', parentDay - 3, 20, '这周末上午提醒我去父母家看看，顺便带点水果。');
  add('${ids['project_risk']}', 19, 11,
      '$project 这周的风险先记一下：灰度监控、客服话术、回滚预案都要盯住。');
  add('${ids['project_meeting']}', 20, 15,
      '${_weekday(n)}下午三点和$person在飞书会议复盘$project。');
  add('${ids['conflict_new']}', 21, 8, conflictNewInput);
  add('${ids['preference']}_hobby', 22, 22, hobbyInput);

  final templates = [
    '今天通勤路上听了一个关于睡眠的播客，感觉最近确实该早点休息。',
    '午饭试了楼下新开的面馆，牛肉面还不错，但排队太久了。',
    '刚才有点烦躁，主要是会议太密，先别把这个当成长期状态。',
    '临时问一下，如果晚饭想吃清淡一点，附近有什么不油腻的选择？',
    '今天和同事聊到周末露营，感觉挺有意思，但只是随口一说。',
    '晚上跑步 3 公里，膝盖有点紧，明天先别安排太剧烈的运动。',
    '看到一个产品增长案例，核心是先做用户分层再谈投放。',
    '这周家里水槽有点漏，周六下午可能要等师傅上门。',
    '今天心情很好，因为把一个拖很久的小问题解决了。',
    '临时咨询一下，咖啡喝多了心慌，晚上怎么缓一缓？',
    '下周如果有复盘，帮我优先看数据口径有没有变。',
    '今天只是想吐槽一下，别记成我讨厌开会，我只是今天累。',
    '朋友推荐了一部电影，名字先记一下：长安三万里。',
    '最近如果安排外卖，尽量避开太辣的，胃有点不舒服。',
    '下午看了下竞品，会员页的权益说明比我们清楚。',
    '明天早上如果天气好，我想去楼下散步二十分钟。',
    '这个月预算别太激进，先保留一点余量。',
    '今天有个想法：把复盘模板拆成结论、证据、下一步。',
    '家里猫砂快用完了，路过超市可以看看。',
    '临时问下，如果客户一直不回消息，催一次怎么措辞比较自然？',
    '今天不太想社交，只想早点回家休息，这个只是今天的状态。',
    '下次看数据时提醒我把异常值单独标出来。',
    '周末如果去父母家，顺便问问他们体检报告出来没有。',
    '刚才看到一张海报配色不错，蓝绿色加米白，挺清爽。',
    '今天下午茶别点甜的，昨天糖吃多了。',
    '如果晚上还有空，想整理一下书桌。',
    '今天和$person聊到$project，感觉对齐目标比继续堆需求更重要。',
    '$project 的日报里最好把风险和 owner 分开写。',
    '临时咨询：如果明天要早起，今晚几点睡比较合适？',
    '我今天对消息提醒有点敏感，先减少非紧急通知。',
    '这不是长期偏好，只是这两天想少喝冰的。',
    '如果要订餐，最近先避开海鲜，肠胃不太稳。',
    '晚点提醒我看一下家里电费余额。',
    '今天看到一个笑话，差点在地铁上笑出声，心情还不错。',
    '月底前要回顾一次本月最大的三个决策。',
    '临时问问，买降噪耳机主要看哪些参数？',
    '这周先别排太满，下周再恢复正常节奏。',
    '下次写总结时，先说结论，再补证据。',
    '如果周日天气不好，看望父母可以改成晚上视频。',
    '今天脑子有点散，不要把这个当成我长期效率下降。',
    '晚上想试试 10 分钟冥想。',
    '如果明天开会前有时间，先看一下$project 的监控截图。',
    '今天路过花店，觉得向日葵挺好看。',
    '临时咨询：朋友生日送什么比较稳妥？',
    '下周三如果安排会议，尽量别排到晚上。',
    '今天看到一个 bug，复现路径先记在$project 里。',
    '周五晚点如果不忙，想和朋友吃个饭。',
    '以后项目提醒里，如果有时间地点，直接放在第一句。',
    '这两天只是想清淡一点，别写成长期饮食偏好。',
    '睡前想看半小时书，别刷短视频。',
    '如果客户问延期原因，先说风险控制，不要说内部排期混乱。',
  ];

  var index = 0;
  while (inputs.length < 60) {
    final day = 6 + (inputs.length % 24);
    final hour = 8 + (inputs.length % 14);
    add('${ids['preference']}_noise_${_two(index)}', day, hour,
        templates[index % templates.length]);
    index++;
  }
  inputs.sort((a, b) => a['time'].toString().compareTo(b['time'].toString()));
  return inputs;
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

const _conflicts = [
  {
    'old_input': '我之前一直不喝咖啡，下午喝了容易睡不着。',
    'new_input': '最近又开始喝咖啡了，上午一杯可以，下午还是别喝。',
    'old_memory': '用户不喝咖啡。',
    'new_memory': '用户最近上午可以喝一杯咖啡，但下午不喝。',
    'new_fact': '用户最近上午可以喝一杯咖啡，但下午不喝。',
    'new_needles': ['上午', '咖啡', '下午'],
  },
  {
    'old_input': '之前我说过不太想参加线下活动，太消耗精力。',
    'new_input': '最近线下活动可以参加，但最好控制在两小时以内。',
    'old_memory': '用户不太想参加线下活动。',
    'new_memory': '用户可以参加线下活动，但希望控制在两小时以内。',
    'new_fact': '用户可以参加线下活动，但希望控制在两小时以内。',
    'new_needles': ['线下活动', '两小时'],
  },
  {
    'old_input': '我以前不喜欢早会，感觉效率低。',
    'new_input': '现在早会可以接受，但要控制在十五分钟以内。',
    'old_memory': '用户不喜欢早会。',
    'new_memory': '用户可以接受早会，但希望控制在十五分钟以内。',
    'new_fact': '用户可以接受早会，但希望控制在十五分钟以内。',
    'new_needles': ['早会', '十五分钟'],
  },
];

const _emotions = [
  {
    'input': '今天有点低落，可能只是昨晚没睡好，先别当成长期状态。',
    'needles': ['低落', '没睡好'],
  },
  {
    'input': '今天特别烦，主要是临时会太多，这个别记成长期偏好。',
    'needles': ['特别烦', '临时会'],
  },
  {
    'input': '今天效率很低，可能只是天气闷，别写成我最近状态差。',
    'needles': ['效率很低', '天气闷'],
  },
];

const _hobbies = [
  {'input': '最近晚上想重新捡起摄影，先从周末扫街开始。'},
  {'input': '最近想练一点吉他，目标很小，每天十分钟就好。'},
  {'input': '最近想多做饭，先从番茄牛腩和清炒时蔬开始。'},
];

const _consultations = [
  {
    'input': '临时咨询一下，如果今晚睡不着，除了褪黑素还有什么温和一点的方法？',
    'noise_needles': ['睡不着', '褪黑素'],
  },
  {
    'input': '临时问问，如果周末只想短途放松，上海周边有什么不累的选择？',
    'noise_needles': ['短途', '上海周边'],
  },
  {
    'input': '临时咨询，朋友最近压力大，我怎么安慰比较自然，不要太说教？',
    'noise_needles': ['朋友', '压力大'],
  },
];
