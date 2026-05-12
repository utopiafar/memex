import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

const _inputsPerPersona = 100;
const _tasksPerPersona = 12;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/retrieval_source_grounding',
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
    'dataset_id': 'memex_retrieval_source_grounding',
    'version': 1,
    'description':
        '中文 Retrieval / Source Grounding Benchmark，评估跨 card、memory、PKM、note 的召回、引用和拒答。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'inputs_per_persona': _inputsPerPersona,
    'task_count': taskCount,
    'tasks_per_persona': _tasksPerPersona,
    'families': ['retrieval_source_grounding'],
    'notes': [
      '每个 persona 有 $_inputsPerPersona 条中文历史输入，构成隐藏世界中的 card、memory、note、PKM 来源。',
      '每个 persona 有 $_tasksPerPersona 个 retrieval_qa 任务，覆盖人物、时间、项目、类型、多来源组合和证据不足拒答。',
      'fixture_observed 是理想检索结果，用于验证 hit@k、MRR、citation、grounded answer 和 abstention 口径。',
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
    'Generated ${cases.length} retrieval cases, $inputCount inputs, '
    '$taskCount tasks at ${outDir.path}',
  );
}

JsonMap _case(int n, _RetrievalPersona persona) {
  final caseId = 'retrieval_grounding_${_three(n)}';
  final sources = _sources(caseId: caseId, persona: persona);
  return {
    'case_id': caseId,
    'family': 'retrieval_source_grounding',
    'language': 'zh-CN',
    'persona': {
      'user_id': persona.userId,
      'profile': {
        'occupation': persona.occupation,
        'city': persona.city,
        'habits': persona.habits,
        'preferences': ['中文回答', '证据不足时说不确定', persona.preference],
      },
    },
    'ground_truth_world': {
      'facts': sources
          .where((s) => s.type == 'memory')
          .map((s) => s.toJson())
          .toList(),
      'events': sources
          .where((s) => s.type == 'event')
          .map((s) => s.toJson())
          .toList(),
      'notes': sources
          .where((s) => s.type == 'note')
          .map((s) => s.toJson())
          .toList(),
      'pkm_entries':
          sources.where((s) => s.type == 'pkm').map((s) => s.toJson()).toList(),
    },
    'input_stream': _inputs(caseId: caseId, persona: persona, sources: sources),
    'eval_tasks': _tasks(caseId: caseId, persona: persona),
  };
}

List<_Source> _sources({
  required String caseId,
  required _RetrievalPersona persona,
}) =>
    [
      _Source(
        id: '${caseId}_event_budget',
        type: 'event',
        content:
            '2026-05-08 15:00 和 ${persona.primaryPerson} 讨论 ${persona.project} 预算，地点腾讯会议。',
      ),
      _Source(
        id: '${caseId}_note_budget',
        type: 'note',
        content:
            '${persona.project} 预算复盘重点：CPA、ROAS、退款率，owner 是 ${persona.primaryPerson}。',
      ),
      _Source(
        id: '${caseId}_mem_meeting_reminder',
        type: 'memory',
        content: '用户希望重要会议提前一天提醒，并在提醒里列出议程。',
      ),
      _Source(
        id: '${caseId}_mem_diet',
        type: 'memory',
        content: '用户点餐偏好：不要海鲜，少糖，晚上少咖啡。',
      ),
      _Source(
        id: '${caseId}_mem_coffee_latest',
        type: 'memory',
        content: '用户最新咖啡偏好：上午可以喝一杯，下午不喝。',
      ),
      _Source(
        id: '${caseId}_pkm_weekly',
        type: 'pkm',
        content:
            'Projects/${persona.project}/周报：风险包括灰度监控、客服话术、回滚预案；下一步是补齐 owner。',
      ),
      _Source(
        id: '${caseId}_note_customer',
        type: 'note',
        content: '${persona.secondaryPerson} 反馈：客户最常问导出失败后的重试和数据延迟。',
      ),
      _Source(
        id: '${caseId}_event_family',
        type: 'event',
        content: '2026-05-18 10:00 去父母家，带 ${persona.familyItem}。',
      ),
      _Source(
        id: '${caseId}_note_metric',
        type: 'note',
        content: '${persona.project} 指标异常：${persona.metric} 上升，需要先排查口径，再看模型结果。',
      ),
      _Source(
        id: '${caseId}_pkm_retro',
        type: 'pkm',
        content: 'Projects/${persona.project}/复盘模板：背景、决策、风险、下一步，结论要先行。',
      ),
      _Source(
        id: '${caseId}_mem_no_guessing',
        type: 'memory',
        content: '没有记录时，用户希望回答不确定，不要猜测。',
      ),
      _Source(
        id: '${caseId}_event_review',
        type: 'event',
        content: '2026-05-22 16:00 和设计评审 ${persona.project} 页面，需要带截图。',
      ),
    ];

List<JsonMap> _inputs({
  required String caseId,
  required _RetrievalPersona persona,
  required List<_Source> sources,
}) {
  final seedInputs = [
    '5月8日下午三点和${persona.primaryPerson}在腾讯会议讨论${persona.project}预算，重点看 CPA、ROAS 和退款率。',
    '${persona.project}预算复盘 owner 先写${persona.primaryPerson}，后面问这个项目先找他对齐。',
    '以后重要会议提前一天提醒我，并且提醒里要列一下议程。',
    '点餐偏好记一下：不要海鲜、少糖，晚上少喝咖啡。',
    '咖啡偏好更新：上午可以喝一杯，下午不要喝。',
    '把${persona.project}周报放到 Projects，风险包括灰度监控、客服话术、回滚预案。',
    '${persona.secondaryPerson}反馈客户最常问导出失败后的重试和数据延迟。',
    '5月18日上午十点去父母家，带${persona.familyItem}。',
    '${persona.project}的${persona.metric}上升，先排查口径，再看模型结果。',
    '${persona.project}复盘模板保留背景、决策、风险、下一步，结论先行。',
    '如果没有记录，回答我时直接说不确定，别猜。',
    '5月22日下午四点和设计评审${persona.project}页面，提醒我带截图。',
  ];
  final fillers = [
    '今天只是有点累，不要写成长期偏好。',
    '${persona.city}今天下雨，线下会议多留二十分钟。',
    '临时查一下会议纪要怎么压缩，明天再整理。',
    '晚上听了一个播客，说产品复盘要区分事实和推测。',
    '如果问“那个风险”，通常指最近的${persona.project}发布风险。',
    '下次周报最后要有 owner 和回滚预案。',
    '不要把今天想喝奶茶写成长期饮食偏好。',
    '${persona.habits.first}这件事尽量不要和深度工作冲突。',
    '重要报告里保留来源，别只写结论。',
    '客户案例可以放资源库，不要写进个人偏好。',
    '这周可能加班，但不是常态。',
    '如果工具调用太多，要单独标成本风险。',
    '周末可能看展，这个不用放工作日程。',
    '今天情绪一般，别写成长期状态。',
    '指标口径变更一定要记录日期。',
    '没有证据时宁可说不确定。',
    '今晚九点后只提醒紧急事项。',
    '阅读材料放 Resources，不要混到项目周报。',
    '复盘时先看异常，再看整体趋势。',
    '和${persona.secondaryPerson}相关的内容多半是客户反馈。',
    '如果问到${persona.project}的长期经验，优先看 PKM 再看散落 notes。',
    '今天只是想买点零食，别写成饮食规则。',
    '最近材料很多，查找时先按项目过滤会更准。',
    '周报里的风险要和真实来源一起出现。',
    '如果问家庭安排，只看 event，不要用项目笔记推测。',
    '今天突然想去旅行，只是想法，不代表已经订票。',
    '复盘里如果出现${persona.metric}，要看日期和上下文。',
    '重要提醒不要只召回最近一条，可能需要同时看偏好和日程。',
    '客户反馈和项目决策要分开引用。',
    '如果没有 source id，回答里不要装作查到了。',
    '晚上只是想喝咖啡不代表规则变了，仍按上午可以、下午不喝。',
    '问到${persona.primaryPerson}时，先查人名再查项目。',
    '问到${persona.secondaryPerson}时，多半和客户反馈或素材反馈有关。',
    '今天看了一个医疗科普，别当成我的个人健康记录。',
    '如果是票务、航班、药量这类高风险问题，没有记录就明确不确定。',
    '资料归档时不要把 Resources 和 Projects 混在一起。',
  ];
  final rows = [...seedInputs, ...fillers];
  while (rows.length < _inputsPerPersona) {
    rows.add(_extraRetrievalInput(rows.length, persona));
  }
  return [
    for (var i = 0; i < rows.length; i++)
      {
        'id': '${caseId}_input_${_two(i + 1)}',
        'time': _inputTime(i),
        'channel': i % 7 == 2 ? 'voice_transcript' : 'text',
        'content': rows[i],
        if (i < sources.length) 'source_id': sources[i].id,
      }
  ];
}

String _extraRetrievalInput(int index, _RetrievalPersona persona) {
  final detail = _retrievalDetails[index % _retrievalDetails.length];
  final intent = _retrievalIntents[index % _retrievalIntents.length];
  final scope = _retrievalScopes[index % _retrievalScopes.length];
  final person = index.isEven ? persona.primaryPerson : persona.secondaryPerson;
  final templates = [
    '今天补了一条${persona.project}的$detail，之后问到$intent 时优先看这类记录。',
    '$person 刚刚提到$detail，先作为项目背景放着，不要写成我的长期偏好。',
    '如果我问“上次那个$detail”，默认先按${persona.project}和$person过滤。',
    '临时查了$intent 的资料，先不要当作已经执行过的计划。',
    '${persona.city}这边今天只是临时线下沟通，地点不要被推断进正式来源。',
    '${persona.project}的$scope 只基于记录回答，没有 source 就说不确定。',
    '我把$detail 放在项目笔记里，后面回答时要引用来源，不要只给总结。',
    '如果查询涉及$person，先查人名，再查${persona.project}，最后再看时间范围。',
    '今天只是想到$intent 的一个可能方向，还没决策，不要当成最终结论。',
    '复盘时如果提到${persona.metric}，要说明来自哪条 note 或 PKM。',
    '如果问家庭、票务、药量这类问题，没有明确记录就直接说不确定。',
    '$scope 的问题不要只靠向量相似，要结合项目、人物和类型过滤。',
  ];
  return templates[index % templates.length];
}

List<JsonMap> _tasks({
  required String caseId,
  required _RetrievalPersona persona,
}) {
  final specs = [
    _RetrievalTaskSpec(
      suffix: 'budget_when',
      query: '我上次和${persona.primaryPerson}讨论${persona.project}预算是什么时候？',
      expectedSources: ['${caseId}_event_budget', '${caseId}_note_budget'],
      mustInclude: [persona.primaryPerson, persona.project, '5月8日'],
      filters: {'person': persona.primaryPerson, 'topic': '预算'},
    ),
    _RetrievalTaskSpec(
      suffix: 'meeting_reminder',
      query: '重要会议提醒偏好是什么？',
      expectedSources: ['${caseId}_mem_meeting_reminder'],
      mustInclude: ['重要会议', '提前一天', '议程'],
      filters: {'type': 'memory'},
    ),
    _RetrievalTaskSpec(
      suffix: 'diet',
      query: '我点餐有什么注意事项？',
      expectedSources: ['${caseId}_mem_diet'],
      mustInclude: ['不要海鲜', '少糖'],
      filters: {'type': 'memory', 'topic': '饮食'},
    ),
    _RetrievalTaskSpec(
      suffix: 'coffee_latest',
      query: '我最近咖啡偏好是什么？',
      expectedSources: ['${caseId}_mem_coffee_latest'],
      mustInclude: ['上午', '咖啡', '下午不喝'],
      mustNotInclude: ['完全不喝咖啡'],
    ),
    _RetrievalTaskSpec(
      suffix: 'project_risks',
      query: '${persona.project}最近有哪些风险和下一步？',
      expectedSources: ['${caseId}_pkm_weekly', '${caseId}_pkm_retro'],
      mustInclude: ['灰度监控', '回滚预案', '下一步'],
      filters: {'project': persona.project},
    ),
    _RetrievalTaskSpec(
      suffix: 'customer_feedback',
      query: '${persona.secondaryPerson}反馈的客户问题是什么？',
      expectedSources: ['${caseId}_note_customer'],
      mustInclude: [persona.secondaryPerson, '重试', '数据延迟'],
      filters: {'person': persona.secondaryPerson},
    ),
    _RetrievalTaskSpec(
      suffix: 'family_event',
      query: '我去父母家要带什么？',
      expectedSources: ['${caseId}_event_family'],
      mustInclude: ['父母', persona.familyItem],
      filters: {'type': 'event'},
    ),
    _RetrievalTaskSpec(
      suffix: 'metric_anomaly',
      query: '${persona.project}哪个指标异常？应该先做什么？',
      expectedSources: ['${caseId}_note_metric'],
      mustInclude: [persona.metric, '排查口径'],
      filters: {'project': persona.project, 'type': 'note'},
    ),
    _RetrievalTaskSpec(
      suffix: 'design_review',
      query: '我哪天要和设计评审页面，需要带什么？',
      expectedSources: ['${caseId}_event_review'],
      mustInclude: ['5月22日', '设计', '截图'],
      filters: {'type': 'event', 'person': '设计'},
    ),
    _RetrievalTaskSpec(
      suffix: 'multi_source_summary',
      query: '帮我总结${persona.project}的预算、风险和复盘要求。',
      expectedSources: [
        '${caseId}_event_budget',
        '${caseId}_pkm_weekly',
        '${caseId}_pkm_retro',
      ],
      mustInclude: ['预算', '风险', '结论先行'],
      filters: {'project': persona.project},
    ),
    const _RetrievalTaskSpec(
      suffix: 'unknown_travel',
      query: '我下个月去东京的机票订了吗？',
      expectedSources: [],
      mustInclude: ['不确定'],
      mustNotInclude: ['已经订了', '东京航班号'],
      shouldAbstain: true,
    ),
    const _RetrievalTaskSpec(
      suffix: 'unknown_medical',
      query: '我最近有没有记录过降压药剂量？',
      expectedSources: [],
      mustInclude: ['不确定'],
      mustNotInclude: ['每天两片', '医生建议'],
      shouldAbstain: true,
    ),
  ];
  return [
    for (final spec in specs) _retrievalTask(caseId: caseId, spec: spec),
  ];
}

JsonMap _retrievalTask({
  required String caseId,
  required _RetrievalTaskSpec spec,
}) {
  final taskId = '${caseId}_${spec.suffix}';
  final expected = {
    'expected_sources': spec.expectedSources,
    if (spec.mustInclude.isNotEmpty) 'must_include': spec.mustInclude,
    if (spec.mustNotInclude.isNotEmpty) 'must_not_include': spec.mustNotInclude,
    if (spec.filters.isNotEmpty) 'expected_filters': spec.filters,
    if (spec.expectedSources.isNotEmpty) 'allowed_uncertainty': false,
    if (spec.expectedSources.isNotEmpty) 'require_grounded_answer': true,
    if (spec.shouldAbstain) 'should_abstain': true,
  };
  final answer = spec.shouldAbstain
      ? '我没有找到相关记录，因此不确定。'
      : '根据记录，${spec.mustInclude.join('、')}。';
  final observed = {
    'answer': answer,
    'retrieved_sources': spec.expectedSources,
    'cited_sources': spec.expectedSources,
    if (spec.filters.isNotEmpty) 'applied_filters': spec.filters,
    'source_snippets': [
      for (final sourceId in spec.expectedSources)
        {'source_id': sourceId, 'snippet': 'fixture source for $sourceId'}
    ],
    'trace_events': [_toolTrace('hybrid_search'), _toolTrace('rerank_sources')],
    'llm_calls': [_llmCall('retrieval_agent', 1800, 420)],
  };
  return {
    'task_id': taskId,
    'type': 'retrieval_qa',
    'query': spec.query,
    'expected': expected,
    'fixture_observed': observed,
  };
}

String _inputTime(int index) {
  final day = DateTime.utc(2026, 5, 1).add(Duration(days: index));
  final hour = [9, 14, 21][index % 3];
  return '2026-${_two(day.month)}-${_two(day.day)}T${_two(hour)}:'
      '${_two((index * 7) % 60)}:00+08:00';
}

JsonMap _toolTrace(String name) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': 120,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 900,
    };

String _two(int n) => n.toString().padLeft(2, '0');
String _three(int n) => n.toString().padLeft(3, '0');

class _Source {
  const _Source({
    required this.id,
    required this.type,
    required this.content,
  });

  final String id;
  final String type;
  final String content;

  JsonMap toJson() => {'id': id, 'type': type, 'content': content};
}

class _RetrievalTaskSpec {
  const _RetrievalTaskSpec({
    required this.suffix,
    required this.query,
    required this.expectedSources,
    required this.mustInclude,
    this.mustNotInclude = const [],
    this.filters = const <String, dynamic>{},
    this.shouldAbstain = false,
  });

  final String suffix;
  final String query;
  final List<String> expectedSources;
  final List<String> mustInclude;
  final List<String> mustNotInclude;
  final JsonMap filters;
  final bool shouldAbstain;
}

class _RetrievalPersona {
  const _RetrievalPersona({
    required this.userId,
    required this.occupation,
    required this.city,
    required this.project,
    required this.primaryPerson,
    required this.secondaryPerson,
    required this.metric,
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
  final String metric;
  final String familyItem;
  final String preference;
  final List<String> habits;
}

const _personas = [
  _RetrievalPersona(
    userId: 'retrieval_u_001',
    occupation: '产品经理',
    city: '杭州',
    project: '导出项目',
    primaryPerson: 'Alex',
    secondaryPerson: 'Leo',
    metric: '导出失败率',
    familyItem: '体检报告复印件',
    preference: '结论先行',
    habits: ['周三下午需求评审', '晚上复盘'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_002',
    occupation: '跨境电商运营',
    city: '深圳',
    project: '北美站增长',
    primaryPerson: 'Jason',
    secondaryPerson: 'Mina',
    metric: '退款率',
    familyItem: '保温杯和降压药',
    preference: '投流复盘先看异常',
    habits: ['周三健身', '周末看望父母'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_003',
    occupation: '数据分析师',
    city: '上海',
    project: 'Memex eval',
    primaryPerson: 'Grace',
    secondaryPerson: '小陈',
    metric: 'retry rate',
    familyItem: '眼药水',
    preference: '保留英文 metric id',
    habits: ['上午深度分析', '周四看 dashboard'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_004',
    occupation: '律师',
    city: '广州',
    project: '法务合同库',
    primaryPerson: 'Annie',
    secondaryPerson: '老王',
    metric: '合同风险数',
    familyItem: '医保卡',
    preference: '重要结论要列来源',
    habits: ['下午审合同', '周末陪家人'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_005',
    occupation: '财务主管',
    city: '成都',
    project: '预算月结',
    primaryPerson: 'Mina',
    secondaryPerson: 'Ada',
    metric: '应付差异率',
    familyItem: '血压计',
    preference: '数字先给口径',
    habits: ['月底结账', '早上核对付款'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_006',
    occupation: '内容运营',
    city: '苏州',
    project: '小红书活动',
    primaryPerson: 'Grace',
    secondaryPerson: 'Jason',
    metric: '互动率',
    familyItem: '水果',
    preference: '复盘保留素材来源',
    habits: ['晚上看评论', '周五整理选题'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_007',
    occupation: '独立开发者',
    city: '厦门',
    project: '个人工具订阅',
    primaryPerson: '小陈',
    secondaryPerson: 'Alex',
    metric: '激活率',
    familyItem: '充电器',
    preference: '少写空话',
    habits: ['上午写代码', '晚上处理客服'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_008',
    occupation: '老师',
    city: '北京',
    project: '公开课改版',
    primaryPerson: 'Ada',
    secondaryPerson: 'Annie',
    metric: '完课率',
    familyItem: '讲义打印件',
    preference: '反馈不超过三条重点',
    habits: ['周三线上答疑', '课前两天准备讲义'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_009',
    occupation: '医生',
    city: '南京',
    project: '门诊随访系统',
    primaryPerson: '周医生',
    secondaryPerson: '小赵',
    metric: '随访完成率',
    familyItem: '病历夹',
    preference: '医疗相关必须区分记录和建议',
    habits: ['午后查房', '周五整理随访'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_010',
    occupation: 'HRBP',
    city: '武汉',
    project: '绩效校准',
    primaryPerson: 'Sophie',
    secondaryPerson: '老李',
    metric: '校准争议数',
    familyItem: '合同复印件',
    preference: '敏感信息少写细节',
    habits: ['周一对齐招聘', '月底做绩效复盘'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_011',
    occupation: '设计师',
    city: '长沙',
    project: '会员页改版',
    primaryPerson: 'Nora',
    secondaryPerson: 'Ken',
    metric: '点击率',
    familyItem: '相机电池',
    preference: '视觉反馈要带截图来源',
    habits: ['上午画稿', '周三设计评审'],
  ),
  _RetrievalPersona(
    userId: 'retrieval_u_012',
    occupation: '创业者',
    city: '青岛',
    project: 'B 端试点',
    primaryPerson: 'Ethan',
    secondaryPerson: 'Ivy',
    metric: '试点转化率',
    familyItem: '车钥匙',
    preference: '商务复盘先列风险和下一步',
    habits: ['早上跑客户', '晚上复盘现金流'],
  ),
];

const _retrievalDetails = [
  '灰度风险',
  '客户反馈',
  '预算口径',
  '会议结论',
  '回滚预案',
  '指标异常',
  '素材来源',
  '工具调用成本',
  '负责人变更',
  '数据延迟',
  '周报下一步',
  '复盘模板',
];

const _retrievalIntents = [
  '最近一次讨论',
  '项目风险',
  '饮食注意事项',
  '会议提醒偏好',
  '客户问题',
  '家庭安排',
  '证据不足的问题',
  '设计评审',
];

const _retrievalScopes = [
  '按时间过滤',
  '按人物过滤',
  '按项目过滤',
  '按类型过滤',
  '跨来源总结',
  '证据引用',
  '拒答边界',
  '最新事实优先',
];
