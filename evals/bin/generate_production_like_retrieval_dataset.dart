import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/production_like_retrieval',
  );
  await outDir.create(recursive: true);

  final cases = [
    _productCase(),
    _clinicCase(),
    _legalCase(),
    _teacherCase(),
    _indieDevCase(),
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
    'dataset_id': 'memex_production_like_retrieval',
    'version': 1,
    'description': '生产贴近 Retrieval QA 小样本：手工策划不同职业、不同来源结构、不同问法和噪声密度。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'task_count': taskCount,
    'families': [
      'production_retrieval_product',
      'production_retrieval_clinic',
      'production_retrieval_legal',
      'production_retrieval_teacher',
      'production_retrieval_indie_dev',
    ],
    'notes': [
      '这个数据集刻意不追求整齐等长：不同 case 的输入、来源和任务数量可以不同。',
      '输入包含口语、弱相关背景、职业术语、生活噪声和不完整表达。',
      '用于校准“更像生产环境”的 retrieval/source grounding 评估口径，不替代大规模回归集。',
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
    'Generated ${cases.length} production-like retrieval cases, '
    '$inputCount inputs, $taskCount tasks at ${outDir.path}',
  );
}

JsonMap _productCase() {
  final sources = [
    _source(
      'pm_event_gray_review',
      'event',
      '5月12日 10:30 与 Nora 复盘导出项目灰度，重点看导出失败率和回滚开关。',
    ),
    _source(
      'pm_note_refund',
      'note',
      '导出失败率从 2.1% 升到 3.4%，客服反馈集中在大文件重试和等待时间。',
    ),
    _source(
      'pm_pkm_runbook',
      'pkm',
      'Projects/导出项目/runbook：回滚前先关批量导出入口，再通知客服话术。',
    ),
  ];
  return _case(
    caseId: 'production_retrieval_product_001',
    family: 'production_retrieval_product',
    persona: _persona('prod_u_001', '产品经理', '杭州', ['结论先行', '风险要带来源']),
    sources: sources,
    inputs: [
      _input(
          'pm_in_01',
          '2026-05-12T10:35:00+08:00',
          '刚和 Nora 过完导出灰度，时间是 5 月 12 日 10:30。嗯，重点是失败率和回滚开关，别写得太乐观。',
          'pm_event_gray_review'),
      _input('pm_in_02', '2026-05-12T11:05:00+08:00',
          '导出失败率从 2.1% 到 3.4%，客服说大文件重试和等待时间被问得最多。', 'pm_note_refund'),
      _input('pm_in_03', '2026-05-12T13:12:00+08:00',
          'runbook 放 Projects/导出项目：回滚前先关批量导出入口，再通知客服话术。', 'pm_pkm_runbook'),
      _input('pm_noise_01', '2026-05-13T09:11:00+08:00',
          '早上咖啡洒了，脑子短路。这个不用记，只是吐槽。'),
      _input('pm_noise_02', '2026-05-13T21:18:00+08:00',
          '如果问东京机票，没有记录就说不确定，别顺手编航班号。'),
    ],
    tasks: [
      _qa(
        'pm_q_gray_review',
        'Nora 那次导出灰度复盘是什么时候，主要风险是什么？',
        ['pm_event_gray_review', 'pm_note_refund'],
        ['Nora', '5月12日', '导出失败率'],
        {'person': 'Nora', 'project': '导出项目'},
        sources,
      ),
      _qa(
        'pm_q_rollback',
        '导出项目回滚前应该先做什么？',
        ['pm_pkm_runbook'],
        ['关批量导出入口', '客服话术'],
        {'type': 'pkm'},
        sources,
      ),
      _abstain('pm_q_unknown_flight', '我东京机票订了吗？', ['东京航班号']),
    ],
  );
}

JsonMap _clinicCase() {
  final sources = [
    _source('clinic_note_privacy', 'note', '随访系统投诉集中在问卷提交失败、隐私授权说明不清、复诊提醒重复。'),
    _source('clinic_event_review', 'event',
        '5月16日 15:00 与周医生评审门诊随访系统表单，需要带隐私授权截图。'),
    _source('clinic_mem_boundary', 'memory', '医疗相关回答必须区分记录和建议；没有记录时不能猜药量。'),
  ];
  return _case(
    caseId: 'production_retrieval_clinic_001',
    family: 'production_retrieval_clinic',
    persona: _persona('clinic_u_001', '医生', '南京', ['医疗相关必须谨慎', '先区分记录和建议']),
    sources: sources,
    inputs: [
      _input(
          'clinic_in_01',
          '2026-05-14T08:20:00+08:00',
          '随访系统这两天投诉有点散：问卷提交失败、隐私授权说明不清、复诊提醒重复。先记一下，别写成诊断。',
          'clinic_note_privacy'),
      _input('clinic_in_02', '2026-05-15T18:44:00+08:00',
          '5月16日下午三点和周医生评审门诊随访系统表单，记得带隐私授权截图。', 'clinic_event_review'),
      _input('clinic_in_03', '2026-05-15T22:01:00+08:00',
          '医疗相关回答必须区分记录和建议；没有记录时不能猜药量，这点非常重要。', 'clinic_mem_boundary'),
      _input('clinic_noise_01', '2026-05-17T12:20:00+08:00',
          '今天午饭太晚了，胃有点空，这只是今天状态，不要写健康结论。'),
    ],
    tasks: [
      _qa(
        'clinic_q_complaints',
        '随访系统最近投诉集中在哪些点？',
        ['clinic_note_privacy'],
        ['问卷提交失败', '隐私授权'],
        {'project': '门诊随访系统'},
        sources,
      ),
      _qa(
        'clinic_q_review',
        '我和周医生什么时候评审表单，要带什么？',
        ['clinic_event_review'],
        ['5月16日', '隐私授权截图'],
        {'person': '周医生', 'type': 'event'},
        sources,
      ),
      _abstain('clinic_q_dose', '我最近记录过降压药剂量吗？', ['每天两片', '医生建议']),
    ],
  );
}

JsonMap _legalCase() {
  final sources = [
    _source('legal_note_clause', 'note', '法务合同库本轮重点是 SLA 违约责任、数据删除期限、审计日志保留。'),
    _source(
        'legal_event_annie', 'event', '5月9日 18:30 与 Annie 对齐合同风险清单，地点飞书会议。'),
    _source('legal_mem_source', 'memory', '用户要求重要法律结论必须列来源，不要把客户口述当正式意见。'),
    _source('legal_pkm_redline', 'pkm',
        'Projects/法务合同库/redline：先改数据删除期限，再补审计日志条款。'),
  ];
  return _case(
    caseId: 'production_retrieval_legal_001',
    family: 'production_retrieval_legal',
    persona: _persona('legal_u_001', '律师', '广州', ['重要结论列来源', '客户口述和正式意见分开']),
    sources: sources,
    inputs: [
      _input('legal_in_01', '2026-05-09T18:32:00+08:00',
          '和 Annie 飞书会议对了一版合同风险清单，5 月 9 日 18:30，别忘。', 'legal_event_annie'),
      _input(
          'legal_in_02',
          '2026-05-09T19:10:00+08:00',
          '法务合同库这轮重点是 SLA 违约责任、数据删除期限、审计日志保留。客户口述不能当正式意见。',
          'legal_note_clause'),
      _input('legal_in_03', '2026-05-10T08:00:00+08:00',
          '重要法律结论必须列来源，不要只写“风险较高”。', 'legal_mem_source'),
      _input('legal_in_04', '2026-05-10T21:22:00+08:00',
          'redline 放 Projects/法务合同库：先改数据删除期限，再补审计日志条款。', 'legal_pkm_redline'),
      _input('legal_noise_01', '2026-05-11T10:00:00+08:00',
          '今天只是临时翻了一个案例，不代表这个案子适用，别自动引用。'),
    ],
    tasks: [
      _qa(
        'legal_q_risks',
        '法务合同库这轮主要合同风险是什么？',
        ['legal_note_clause', 'legal_pkm_redline'],
        ['SLA', '数据删除期限', '审计日志'],
        {'project': '法务合同库'},
        sources,
      ),
      _qa(
        'legal_q_annie',
        '我什么时候和 Annie 对齐合同风险？',
        ['legal_event_annie'],
        ['5月9日', 'Annie'],
        {'person': 'Annie'},
        sources,
      ),
      _qa(
        'legal_q_source_rule',
        '法律结论回答时有什么偏好？',
        ['legal_mem_source'],
        ['列来源', '客户口述'],
        {'type': 'memory'},
        sources,
      ),
    ],
  );
}

JsonMap _teacherCase() {
  final sources = [
    _source('teacher_event_trial', 'event',
        '5月20日 19:00 公开课改版试听，课前两小时检查直播回放和讲义下载。'),
    _source('teacher_note_feedback', 'note', '学生反馈：讲义下载慢、回放入口藏得深、作业入口找不到。'),
    _source('teacher_pkm_plan', 'pkm', 'Projects/公开课改版/迭代：先改回放入口，再压缩讲义 PDF。'),
  ];
  return _case(
    caseId: 'production_retrieval_teacher_001',
    family: 'production_retrieval_teacher',
    persona: _persona('teacher_u_001', '老师', '北京', ['反馈不超过三条重点', '课前两天准备讲义']),
    sources: sources,
    inputs: [
      _input('teacher_in_01', '2026-05-18T09:30:00+08:00',
          '公开课改版试听是 5 月 20 日晚上七点，课前两小时检查直播回放和讲义下载。', 'teacher_event_trial'),
      _input('teacher_in_02', '2026-05-18T22:10:00+08:00',
          '学生反馈有点碎：讲义下载慢、回放入口藏得深、作业入口找不到。', 'teacher_note_feedback'),
      _input('teacher_in_04', '2026-05-19T21:18:00+08:00',
          '公开课改版迭代：先改回放入口，再压缩讲义 PDF。放项目里。', 'teacher_pkm_plan'),
      _input('teacher_noise_01', '2026-05-20T12:00:00+08:00',
          '今天嗓子有点哑，只是临时状态，不要写长期健康。'),
    ],
    tasks: [
      _qa(
        'teacher_q_trial',
        '公开课试听是什么时候，课前要检查什么？',
        ['teacher_event_trial'],
        ['5月20日', '直播回放', '讲义下载'],
        {'type': 'event'},
        sources,
      ),
      _qa(
        'teacher_q_feedback',
        '学生主要反馈哪三件事？',
        ['teacher_note_feedback'],
        ['讲义下载慢', '回放入口', '作业入口'],
        {'project': '公开课改版'},
        sources,
      ),
      _qa(
        'teacher_q_next',
        '公开课改版下一步先改什么？',
        ['teacher_pkm_plan'],
        ['回放入口', '讲义 PDF'],
        {'type': 'pkm'},
        sources,
      ),
    ],
  );
}

JsonMap _indieDevCase() {
  final sources = [
    _source('dev_note_activation', 'note', '个人工具订阅反馈：订阅激活失败、支付回调慢、导入报错。'),
    _source(
        'dev_event_bugbash', 'event', '5月21日 21:00 做订阅 bug bash，重点看支付回调和退款工单。'),
    _source('dev_mem_style', 'memory', '用户偏好少写空话，最好直接变成 backlog 或 changelog。'),
    _source('dev_pkm_changelog', 'pkm',
        'Projects/个人工具订阅/changelog：先修激活失败，再补导入错误提示。'),
  ];
  return _case(
    caseId: 'production_retrieval_indie_dev_001',
    family: 'production_retrieval_indie_dev',
    persona: _persona('dev_u_001', '独立开发者', '厦门', ['少写空话', '上午写代码']),
    sources: sources,
    inputs: [
      _input(
          'dev_in_01',
          '2026-05-19T23:10:00+08:00',
          '个人工具订阅反馈先记：订阅激活失败、支付回调慢、导入报错。别写漂亮话，能进 backlog 就行。',
          'dev_note_activation'),
      _input('dev_in_02', '2026-05-20T08:40:00+08:00',
          '5月21日晚上九点做订阅 bug bash，重点看支付回调和退款工单。', 'dev_event_bugbash'),
      _input('dev_in_03', '2026-05-20T10:00:00+08:00',
          '我的偏好：少写空话，最好直接变成 backlog 或 changelog。', 'dev_mem_style'),
      _input('dev_in_04', '2026-05-21T23:40:00+08:00',
          'changelog 放 Projects/个人工具订阅：先修激活失败，再补导入错误提示。', 'dev_pkm_changelog'),
      _input('dev_noise_01', '2026-05-22T01:00:00+08:00', '凌晨脑子有点亢奋，别写成长期作息。'),
    ],
    tasks: [
      _qa(
        'dev_q_feedback',
        '个人工具订阅最近主要反馈什么问题？',
        ['dev_note_activation'],
        ['订阅激活失败', '支付回调', '导入报错'],
        {'project': '个人工具订阅'},
        sources,
      ),
      _qa(
        'dev_q_bugbash',
        '订阅 bug bash 是什么时候，重点看什么？',
        ['dev_event_bugbash'],
        ['5月21日', '支付回调', '退款工单'],
        {'type': 'event'},
        sources,
      ),
      _qa(
        'dev_q_style',
        '我写项目结论有什么偏好？',
        ['dev_mem_style'],
        ['少写空话', 'backlog'],
        {'type': 'memory'},
        sources,
      ),
      _abstain('dev_q_unknown_hotel', '我下周去上海的酒店订了吗？', ['酒店地址', '已预订']),
    ],
  );
}

JsonMap _case({
  required String caseId,
  required String family,
  required JsonMap persona,
  required List<JsonMap> sources,
  required List<JsonMap> inputs,
  required List<JsonMap> tasks,
}) {
  return {
    'case_id': caseId,
    'family': family,
    'language': 'zh-CN',
    'persona': persona,
    'ground_truth_world': {
      'facts': sources.where((s) => s['type'] == 'memory').toList(),
      'events': sources.where((s) => s['type'] == 'event').toList(),
      'notes': sources.where((s) => s['type'] == 'note').toList(),
      'pkm_entries': sources.where((s) => s['type'] == 'pkm').toList(),
    },
    'input_stream': inputs,
    'eval_tasks': tasks,
  };
}

JsonMap _persona(
  String userId,
  String occupation,
  String city,
  List<String> preferences,
) =>
    {
      'user_id': userId,
      'profile': {
        'occupation': occupation,
        'city': city,
        'preferences': ['中文回答', '证据不足时说不确定', ...preferences],
      },
    };

JsonMap _source(String id, String type, String content) =>
    {'id': id, 'type': type, 'content': content};

JsonMap _input(String id, String time, String content, [String? sourceId]) => {
      'id': id,
      'time': time,
      'channel': id.contains('noise') ? 'voice_transcript' : 'text',
      'content': content,
      if (sourceId != null) 'source_id': sourceId,
    };

JsonMap _qa(
  String taskId,
  String query,
  List<String> expectedSources,
  List<String> mustInclude,
  JsonMap filters,
  List<JsonMap> sources,
) {
  final sourcesById = {for (final source in sources) source['id']: source};
  final snippets = [
    for (final sourceId in expectedSources)
      {
        'source_id': sourceId,
        'snippet': sourcesById[sourceId]?['content'] ?? 'missing source',
      }
  ];
  return {
    'task_id': taskId,
    'type': 'retrieval_qa',
    'query': query,
    'expected': {
      'expected_sources': expectedSources,
      'must_include': mustInclude,
      'expected_filters': filters,
      'allowed_uncertainty': false,
      'require_grounded_answer': true,
    },
    'fixture_observed': {
      'answer': '根据记录：${snippets.map((s) => s['snippet']).join('；')}',
      'retrieved_sources': expectedSources,
      'cited_sources': expectedSources,
      'source_snippets': snippets,
      'applied_filters': filters,
      'trace_events': [
        _toolTrace('hybrid_search'),
        _toolTrace('rerank_sources')
      ],
      'llm_calls': [_llmCall('retrieval_agent', 1500, 360)],
    },
  };
}

JsonMap _abstain(String taskId, String query, List<String> mustNotInclude) => {
      'task_id': taskId,
      'type': 'retrieval_qa',
      'query': query,
      'expected': {
        'expected_sources': <String>[],
        'must_include': ['不确定'],
        'must_not_include': mustNotInclude,
        'should_abstain': true,
      },
      'fixture_observed': {
        'answer': '我没有找到相关记录，因此不确定。',
        'retrieved_sources': <String>[],
        'cited_sources': <String>[],
        'source_snippets': <JsonMap>[],
        'trace_events': [_toolTrace('hybrid_search')],
        'llm_calls': [_llmCall('retrieval_agent', 900, 120)],
      },
    };

JsonMap _toolTrace(String name) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': 140,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 900,
    };
