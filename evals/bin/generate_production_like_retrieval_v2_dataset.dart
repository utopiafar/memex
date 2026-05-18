import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty
        ? args.first
        : 'evals/datasets/production_like_retrieval_v2',
  );
  await outDir.create(recursive: true);

  final scenarios = [
    _growthProductScenario(),
    _chronicCareScenario(),
    _financeScenario(),
    _opsScenario(),
    _uxResearchScenario(),
    _editorScenario(),
    _restaurantScenario(),
    _constructionScenario(),
    _gameDesignScenario(),
    _recruitingScenario(),
    _caregiverScenario(),
    _sreScenario(),
  ];
  final cases = scenarios.map(_buildCase).toList();
  final inputCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['input_stream'] as List).length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_production_like_retrieval_v2',
    'version': 2,
    'description': '生产贴近 Retrieval QA 扩展样本：更多用户、行业、噪声形态、修正记录和多来源任务。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'task_count': taskCount,
    'families': scenarios.map((scenario) => scenario.family).toList(),
    'complexity_dimensions': [
      'multi_source_answer',
      'latest_update_vs_old_record',
      'domain_specific_persona',
      'weakly_related_noise',
      'voice_transcript_chatter',
      'screenshot_or_email_like_input',
      'abstention_for_unknown_fact',
      'source_citation_required',
    ],
    'notes': [
      'v2 不是把 v1 简单扩行，而是让每个职业场景有不同来源结构、输入渠道、噪声密度和任务数量。',
      '包含旧记录与最新修正、正式记录与口头碎片、专业术语与生活噪声，模拟真实个人工作流里的混杂信息。',
      '仍是 fixture adapter，用于验证 harness、指标和 LLM judge；不能替代真实 Memex replay。',
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
    'Generated ${cases.length} production-like retrieval v2 cases, '
    '$inputCount inputs, $taskCount tasks at ${outDir.path}',
  );
}

JsonMap _buildCase(ScenarioSpec scenario) {
  final sources = scenario.sources
      .map(
        (source) => {
          'id': source.id,
          'type': source.type,
          'content': source.content,
          if (source.label != null) 'label': source.label,
        },
      )
      .toList();
  final inputs = [
    for (final source in scenario.sources)
      _input(
        source.inputId ?? '${source.id}_input',
        source.time,
        source.channel,
        source.inputContent,
        source.id,
      ),
    ...scenario.noiseInputs.map(
      (noise) => _input(noise.id, noise.time, noise.channel, noise.content),
    ),
  ];
  final tasks = scenario.tasks
      .map((task) => task.shouldAbstain ? _abstain(task) : _qa(task, sources))
      .toList();

  return {
    'case_id': scenario.caseId,
    'family': scenario.family,
    'language': 'zh-CN',
    'persona': {
      'user_id': scenario.userId,
      'profile': {
        'occupation': scenario.occupation,
        'city': scenario.city,
        'preferences': [
          '中文回答',
          '证据不足时说不确定',
          ...scenario.preferences,
        ],
      },
    },
    'metadata': {
      'iteration': 'production_like_retrieval_v2',
      'complexity_tags': scenario.complexityTags,
    },
    'ground_truth_world': {
      'facts': sources.where((source) => source['type'] == 'memory').toList(),
      'events': sources.where((source) => source['type'] == 'event').toList(),
      'notes': sources.where((source) => source['type'] == 'note').toList(),
      'pkm_entries':
          sources.where((source) => source['type'] == 'pkm').toList(),
    },
    'input_stream': inputs,
    'eval_tasks': tasks,
  };
}

ScenarioSpec _growthProductScenario() => ScenarioSpec(
      slug: 'growth_product',
      userId: 'v2_prod_growth_001',
      occupation: '增长产品经理',
      city: '上海',
      preferences: ['增长数据必须分新老用户', '结论要说风险和来源'],
      complexityTags: ['old_vs_new_metrics', 'domain_metrics', 'abstention'],
      sources: [
        _source(
          id: 'gp_event_ab_review',
          type: 'event',
          time: '2026-05-11T14:08:00+08:00',
          channel: 'meeting_note',
          content: '5月11日 14:00 与 Kai 评审邀请链路 A/B 实验，低线城市新用户转化明显偏低。',
          inputContent: 'Kai 那场邀请链路 A/B 评审是 5 月 11 日下午两点。低线城市新用户转化不行，别只看总盘。',
        ),
        _source(
          id: 'gp_note_metrics',
          type: 'note',
          time: '2026-05-11T17:40:00+08:00',
          channel: 'text',
          content: '邀请链路指标：老用户邀请转化 8.2%，新用户 4.7%，弹窗关闭率 31%，大图文版本投诉更高。',
          inputContent:
              '邀请链路今天的数据有点拧巴：老用户邀请转化 8.2%，新用户 4.7%，弹窗关闭率 31%，大图文投诉更多。',
        ),
        _source(
          id: 'gp_pkm_decision',
          type: 'pkm',
          time: '2026-05-12T09:10:00+08:00',
          channel: 'text',
          content: 'Projects/邀请链路/2026Q2：先把邀请弹窗收窄到注册后第2天；暂不做短信唤醒。',
          inputContent: '决策写到 Projects/邀请链路/2026Q2：先把邀请弹窗收窄到注册后第2天，短信唤醒先不做。',
        ),
        _source(
          id: 'gp_memory_style',
          type: 'memory',
          time: '2026-05-12T22:30:00+08:00',
          channel: 'voice_transcript',
          content: '用户看增长实验时要求分新老用户，不接受只给总平均。',
          inputContent: '以后问我增长实验，记得拆新老用户哈，给一个平均数我会觉得很糊弄。',
        ),
        _source(
          id: 'gp_note_2025_distractor',
          type: 'note',
          time: '2026-05-13T12:00:00+08:00',
          channel: 'text',
          content: '2025 春节裂变复盘：红包入口点击高，但不是 2026Q2 邀请链路实验数据。',
          inputContent: '翻到一个 2025 春节裂变复盘，红包入口点击高；这个不是现在邀请链路，别混了。',
        ),
      ],
      noiseInputs: [
        _noise('gp_noise_01', '2026-05-12T08:15:00+08:00', 'voice_transcript',
            '早高峰地铁太吵了，刚才这句可能识别错了，别把“快”听成 Kai。'),
        _noise('gp_noise_02', '2026-05-13T23:20:00+08:00', 'text',
            '如果问 6 月优惠券预算，我其实还没定，别顺手编一个。'),
      ],
      tasks: [
        _task(
          'gp_q_ab_metrics',
          '邀请链路 A/B 实验现在主要问题是什么？要分新老用户说。',
          ['gp_event_ab_review', 'gp_note_metrics', 'gp_memory_style'],
          ['新用户 4.7%', '老用户邀请转化 8.2%', '低线城市'],
          {'project': '邀请链路', 'metric_view': 'new_vs_existing_users'},
        ),
        _task(
          'gp_q_decision',
          '邀请链路下一步决策是什么？',
          ['gp_pkm_decision'],
          ['注册后第2天', '暂不做短信唤醒'],
          {'type': 'pkm', 'project': '邀请链路'},
        ),
        _task(
          'gp_q_old_record_boundary',
          '2025 春节裂变那条能当这次邀请链路证据吗？',
          ['gp_note_2025_distractor'],
          ['不是 2026Q2', '春节裂变'],
          {'time_scope': 'old_distractor'},
        ),
        _unknown(
          'gp_q_unknown_budget',
          '6 月优惠券预算定了多少？',
          ['预算 20 万', '预算 50 万'],
        ),
      ],
    );

ScenarioSpec _chronicCareScenario() => ScenarioSpec(
      slug: 'chronic_care',
      userId: 'v2_clinic_followup_001',
      occupation: '慢病随访医生',
      city: '南京',
      preferences: ['医疗相关必须区分记录和建议', '没有记录不能猜药量'],
      complexityTags: ['medical_boundary', 'voice_noise', 'privacy'],
      sources: [
        _source(
          id: 'cc_note_symptoms',
          type: 'note',
          time: '2026-05-14T08:22:00+08:00',
          channel: 'voice_transcript',
          content: '随访反馈：3 位患者提到夜间咳嗽，2 位反馈问卷入口找不到，1 位担心隐私授权说明不清。',
          inputContent: '随访反馈有点散：三位说夜间咳嗽，两位找不到问卷入口，还有一位一直问隐私授权，先记成反馈，不是诊断。',
        ),
        _source(
          id: 'cc_event_review',
          type: 'event',
          time: '2026-05-16T15:00:00+08:00',
          channel: 'calendar_note',
          content: '5月16日 15:00 与周医生评审门诊随访表单，需要带隐私授权截图和问卷漏斗。',
          inputContent: '5月16日下午三点和周医生评审门诊随访表单，带隐私授权截图，还有问卷漏斗。',
        ),
        _source(
          id: 'cc_memory_boundary',
          type: 'memory',
          time: '2026-05-15T22:01:00+08:00',
          channel: 'text',
          content: '用户要求医疗回答必须说明“这是记录不是诊断建议”；没有来源时不要推断药量。',
          inputContent: '医疗回答一定写清楚这是记录不是诊断建议；没来源时不要推断药量，尤其别给剂量。',
        ),
        _source(
          id: 'cc_pkm_form',
          type: 'pkm',
          time: '2026-05-16T18:20:00+08:00',
          channel: 'text',
          content: 'Projects/门诊随访表单：先修问卷入口，再补隐私授权说明的二级弹窗。',
          inputContent: '评审后动作放 Projects/门诊随访表单：先修问卷入口，再补隐私授权说明的二级弹窗。',
        ),
      ],
      noiseInputs: [
        _noise('cc_noise_01', '2026-05-15T12:20:00+08:00', 'text',
            '今天午饭太晚胃有点空，这只是我自己的临时状态，不要写健康结论。'),
        _noise('cc_noise_02', '2026-05-16T07:50:00+08:00', 'voice_transcript',
            '语音里如果听到“隐私瘦全”，大概率是隐私授权，识别太离谱了。'),
      ],
      tasks: [
        _task(
          'cc_q_feedback',
          '随访反馈集中在哪些问题？',
          ['cc_note_symptoms'],
          ['夜间咳嗽', '问卷入口', '隐私授权'],
          {'project': '门诊随访'},
        ),
        _task(
          'cc_q_review',
          '和周医生评审是什么时候，要带什么？',
          ['cc_event_review'],
          ['5月16日', '隐私授权截图', '问卷漏斗'],
          {'person': '周医生', 'type': 'event'},
        ),
        _task(
          'cc_q_next_action',
          '门诊随访表单评审后的下一步是什么？',
          ['cc_pkm_form'],
          ['先修问卷入口', '二级弹窗'],
          {'type': 'pkm', 'project': '门诊随访表单'},
        ),
        _unknown(
          'cc_q_unknown_dose',
          '这些患者应该把止咳药加到每天两次吗？',
          ['每天两次', '应该加药'],
        ),
      ],
    );

ScenarioSpec _financeScenario() => ScenarioSpec(
      slug: 'finance_fpna',
      userId: 'v2_finance_fpna_001',
      occupation: 'FP&A 分析师',
      city: '深圳',
      preferences: ['财务口径必须说版本', '预测要区分乐观和保守假设'],
      complexityTags: ['versioned_forecast', 'board_context', 'old_forecast'],
      sources: [
        _source(
          id: 'fin_note_q2_forecast',
          type: 'note',
          time: '2026-05-08T20:10:00+08:00',
          channel: 'spreadsheet_note',
          content: 'Q2 最新预测：保守收入 1280 万，乐观收入 1410 万，毛利率风险来自云成本上涨。',
          inputContent:
              'Q2 最新 forecast：保守 1280 万，乐观 1410 万，云成本上涨会压毛利率。这个是今晚版本。',
        ),
        _source(
          id: 'fin_event_board',
          type: 'event',
          time: '2026-05-13T09:30:00+08:00',
          channel: 'calendar_note',
          content: '5月13日 09:30 预算委员会会议，重点看 Q2 forecast、云成本和续费率。',
          inputContent: '5月13日早上九点半预算委员会，看 Q2 forecast、云成本、续费率，别只讲收入。',
        ),
        _source(
          id: 'fin_pkm_model',
          type: 'pkm',
          time: '2026-05-09T11:00:00+08:00',
          channel: 'text',
          content: 'Finance/Q2-model：续费率每下降 1pt，保守收入减少约 36 万；云成本按 12% 上浮。',
          inputContent:
              'Finance/Q2-model 记一下：续费率每下降 1pt，保守收入少 36 万左右；云成本按 12% 上浮。',
        ),
        _source(
          id: 'fin_memory_style',
          type: 'memory',
          time: '2026-05-09T23:40:00+08:00',
          channel: 'voice_transcript',
          content: '用户做财务分析时希望同时给数值、口径版本和核心假设。',
          inputContent: '以后回答财务数，拜托同时说版本和假设，不然我自己都不知道是不是昨晚那个表。',
        ),
        _source(
          id: 'fin_note_old_forecast',
          type: 'note',
          time: '2026-04-26T18:00:00+08:00',
          channel: 'text',
          content: '旧版 Q2 预测：保守收入 1200 万；已被 5月8日版本替换。',
          inputContent: '旧版 Q2 保守 1200 万这条别删，但现在不是最新了，5月8日那版替换它。',
        ),
      ],
      noiseInputs: [
        _noise('fin_noise_01', '2026-05-10T00:30:00+08:00', 'voice_transcript',
            '刚才说的一千二不是预算，是楼下快递柜编号，别离谱地记进 forecast。'),
        _noise('fin_noise_02', '2026-05-12T21:00:00+08:00', 'text',
            '预算会前我可能会焦虑，这个情绪不用进长期记忆。'),
      ],
      tasks: [
        _task(
          'fin_q_latest_forecast',
          'Q2 最新 forecast 的保守和乐观收入是多少？要说主要风险。',
          ['fin_note_q2_forecast', 'fin_memory_style'],
          ['1280 万', '1410 万', '云成本'],
          {'time_scope': 'latest', 'metric': 'forecast'},
        ),
        _task(
          'fin_q_board',
          '预算委员会什么时候开，重点看什么？',
          ['fin_event_board'],
          ['5月13日', '云成本', '续费率'],
          {'type': 'event'},
        ),
        _task(
          'fin_q_model_assumption',
          'Q2 模型里续费率下降和云成本的假设是什么？',
          ['fin_pkm_model'],
          ['下降 1pt', '36 万', '12%'],
          {'type': 'pkm'},
        ),
        _unknown(
          'fin_q_unknown_cash',
          'Q3 现金流缺口是多少？',
          ['现金流缺口 300 万', 'Q3 缺口'],
        ),
      ],
    );

ScenarioSpec _opsScenario() => ScenarioSpec(
      slug: 'ops_warehouse',
      userId: 'v2_ops_warehouse_001',
      occupation: '仓配运营负责人',
      city: '成都',
      preferences: ['异常复盘要写时间线', '先区分临时绕行和长期流程'],
      complexityTags: ['incident_timeline', 'runbook', 'escalation'],
      sources: [
        _source(
          id: 'ops_event_sorter',
          type: 'event',
          time: '2026-05-07T03:18:00+08:00',
          channel: 'incident_note',
          content: '5月7日 03:18 西区分拣线扫码枪离线，03:42 临时切到手工复核。',
          inputContent: '夜里 3:18 西区分拣线扫码枪离线，3:42 临时切手工复核。我有点困，先把时间线记准。',
        ),
        _source(
          id: 'ops_note_defects',
          type: 'note',
          time: '2026-05-07T11:30:00+08:00',
          channel: 'text',
          content: '异常影响：错分 17 单，延迟出库 43 单，客户投诉集中在生鲜延误。',
          inputContent: '异常影响复盘：错分 17 单，延迟出库 43 单，投诉主要是生鲜延误。',
        ),
        _source(
          id: 'ops_pkm_runbook',
          type: 'pkm',
          time: '2026-05-07T16:00:00+08:00',
          channel: 'text',
          content: 'Ops/西区分拣线/runbook：扫码枪离线超过 10 分钟，先启用手工复核，再通知质控。',
          inputContent: 'runbook 写到 Ops/西区分拣线：扫码枪离线超过 10 分钟，先启用手工复核，再通知质控。',
        ),
        _source(
          id: 'ops_memory_escalation',
          type: 'memory',
          time: '2026-05-08T09:10:00+08:00',
          channel: 'text',
          content: '用户要求仓配异常回答必须区分“临时绕行”和“长期流程改造”。',
          inputContent: '以后仓配异常别只说处理了，要分临时绕行和长期流程改造。',
        ),
      ],
      noiseInputs: [
        _noise('ops_noise_01', '2026-05-07T04:10:00+08:00', 'voice_transcript',
            '刚才语音里说的“手工”不是“收工”，千万别写成已经收工。'),
        _noise('ops_noise_02', '2026-05-08T23:55:00+08:00', 'text',
            '今天真的只想睡觉，这个不要进入什么长期偏好，明天还得看报表。'),
      ],
      tasks: [
        _task(
          'ops_q_incident',
          '西区分拣线那次异常的时间线和影响是什么？',
          ['ops_event_sorter', 'ops_note_defects'],
          ['03:18', '03:42', '错分 17 单', '延迟出库 43 单'],
          {'site': '西区分拣线', 'incident': '扫码枪离线'},
        ),
        _task(
          'ops_q_runbook',
          '扫码枪离线超过 10 分钟该怎么处理？',
          ['ops_pkm_runbook'],
          ['手工复核', '通知质控'],
          {'type': 'pkm'},
        ),
        _task(
          'ops_q_style',
          '仓配异常回答时我有什么偏好？',
          ['ops_memory_escalation'],
          ['临时绕行', '长期流程改造'],
          {'type': 'memory'},
        ),
        _unknown(
          'ops_q_unknown_compensation',
          '这次生鲜延误赔付金额是多少？',
          ['赔付 5000', '赔付金额'],
        ),
      ],
    );

ScenarioSpec _uxResearchScenario() => ScenarioSpec(
      slug: 'ux_research',
      userId: 'v2_ux_research_001',
      occupation: '用户研究员',
      city: '杭州',
      preferences: ['访谈必须匿名化', '结论要区分观察和推断'],
      complexityTags: ['participant_codes', 'anonymization', 'mixed_feedback'],
      sources: [
        _source(
          id: 'ux_event_interviews',
          type: 'event',
          time: '2026-05-18T10:00:00+08:00',
          channel: 'calendar_note',
          content: '5月18日 10:00-12:00 完成 P03、P07、P11 三位新手用户访谈。',
          inputContent: '5月18日上午访了 P03、P07、P11 三个新手用户，时间 10 点到 12 点。',
        ),
        _source(
          id: 'ux_note_findings',
          type: 'note',
          time: '2026-05-18T13:20:00+08:00',
          channel: 'voice_transcript',
          content: '访谈观察：P03 找不到导入入口，P07 误解同步状态，P11 担心历史记录丢失。',
          inputContent: '访谈观察先记：P03 找不到导入入口，P07 误解同步状态，P11 一直担心历史记录丢失。别写真名。',
        ),
        _source(
          id: 'ux_pkm_synthesis',
          type: 'pkm',
          time: '2026-05-18T20:40:00+08:00',
          channel: 'text',
          content: 'Research/导入体验/synthesis：先补空状态引导，再把同步状态拆成上传中、已完成、失败。',
          inputContent: 'synthesis 放 Research/导入体验：先补空状态引导，再把同步状态拆成上传中、已完成、失败。',
        ),
        _source(
          id: 'ux_memory_rule',
          type: 'memory',
          time: '2026-05-19T09:00:00+08:00',
          channel: 'text',
          content: '用户研究输出必须匿名化参与者，并明确区分观察事实和研究者推断。',
          inputContent: '以后研究输出都匿名化，参与者只写编号；观察事实和我的推断分开。',
        ),
      ],
      noiseInputs: [
        _noise('ux_noise_01', '2026-05-18T12:10:00+08:00', 'text',
            '午饭想吃面，这个和导入体验没关系，别进研究结论。'),
        _noise('ux_noise_02', '2026-05-19T11:30:00+08:00', 'screenshot_ocr',
            '截图 OCR 里有一堆乱码，真正有用的是“导入中 37% 卡住”。'),
      ],
      tasks: [
        _task(
          'ux_q_findings',
          '导入体验访谈里三个新手用户分别卡在哪里？',
          ['ux_event_interviews', 'ux_note_findings'],
          ['P03', '导入入口', 'P07', '同步状态', 'P11', '历史记录'],
          {'project': '导入体验', 'privacy': 'participant_codes'},
        ),
        _task(
          'ux_q_synthesis',
          '导入体验 synthesis 的下一步设计动作是什么？',
          ['ux_pkm_synthesis'],
          ['空状态引导', '上传中', '失败'],
          {'type': 'pkm'},
        ),
        _task(
          'ux_q_rule',
          '研究输出有什么格式要求？',
          ['ux_memory_rule'],
          ['匿名化', '观察事实', '推断'],
          {'type': 'memory'},
        ),
        _unknown(
          'ux_q_unknown_nps',
          '这轮访谈的 NPS 分数是多少？',
          ['NPS 8', 'NPS 分数'],
        ),
      ],
    );

ScenarioSpec _editorScenario() => ScenarioSpec(
      slug: 'investigative_editor',
      userId: 'v2_editor_001',
      occupation: '深度报道编辑',
      city: '北京',
      preferences: ['未经确认的信息不能下结论', '报道线索必须标来源状态'],
      complexityTags: ['source_status', 'rumor_boundary', 'outline'],
      sources: [
        _source(
          id: 'ed_event_interview',
          type: 'event',
          time: '2026-05-06T19:30:00+08:00',
          channel: 'calendar_note',
          content: '5月6日 19:30 与线人 M 进行电话访谈，对方只愿意匿名引用。',
          inputContent: '5月6日晚上 7:30 和线人 M 电话，对方只愿意匿名引用，别写实名。',
        ),
        _source(
          id: 'ed_note_claims',
          type: 'note',
          time: '2026-05-06T22:10:00+08:00',
          channel: 'voice_transcript',
          content: '线人 M 提供两条已交叉验证线索：采购流程绕过二次审批、验收记录晚于付款日期。',
          inputContent: 'M 的两条线索目前交叉验证过：采购绕过二次审批，验收记录晚于付款日期。语气克制点。',
        ),
        _source(
          id: 'ed_memory_rule',
          type: 'memory',
          time: '2026-05-07T09:00:00+08:00',
          channel: 'text',
          content: '用户要求报道相关回答必须区分已核实、待核实和传闻，不把传闻写成事实。',
          inputContent: '报道相关回答必须分已核实、待核实、传闻，别为了顺嘴把传闻写成事实。',
        ),
        _source(
          id: 'ed_pkm_outline',
          type: 'pkm',
          time: '2026-05-07T21:00:00+08:00',
          channel: 'text',
          content: 'Stories/采购调查/outline：第一节写审批链条，第二节写付款与验收日期错位。',
          inputContent: 'outline 放 Stories/采购调查：第一节审批链条，第二节付款与验收日期错位。',
        ),
        _source(
          id: 'ed_note_rumor',
          type: 'note',
          time: '2026-05-08T10:20:00+08:00',
          channel: 'text',
          content: '未核实传闻：有人提到供应商亲属关系，但没有独立来源确认。',
          inputContent: '有个未核实传闻说供应商亲属关系，没有独立来源确认，这条千万别当事实。',
        ),
      ],
      noiseInputs: [
        _noise('ed_noise_01', '2026-05-07T00:10:00+08:00', 'text',
            '今晚咖啡喝多了，脑子转太快，这不是报道判断。'),
        _noise('ed_noise_02', '2026-05-08T23:30:00+08:00', 'voice_transcript',
            '语音里“验收”可能被识别成“演说”，但上下文是验收记录。'),
      ],
      tasks: [
        _task(
          'ed_q_verified_claims',
          '采购调查目前有哪些已交叉验证的线索？',
          ['ed_note_claims', 'ed_memory_rule'],
          ['采购流程', '二次审批', '验收记录', '付款日期'],
          {'source_status': 'verified'},
        ),
        _task(
          'ed_q_interview',
          '线人 M 的访谈是什么时候，引用限制是什么？',
          ['ed_event_interview'],
          ['5月6日', '匿名引用'],
          {'person': '线人 M'},
        ),
        _task(
          'ed_q_outline',
          '采购调查 outline 怎么安排？',
          ['ed_pkm_outline'],
          ['审批链条', '付款与验收日期错位'],
          {'type': 'pkm'},
        ),
        _task(
          'ed_q_rumor_boundary',
          '供应商亲属关系这条能写成事实吗？',
          ['ed_note_rumor', 'ed_memory_rule'],
          ['未核实传闻', '不把传闻写成事实'],
          {'source_status': 'rumor'},
        ),
      ],
    );

ScenarioSpec _restaurantScenario() => ScenarioSpec(
      slug: 'restaurant_owner',
      userId: 'v2_restaurant_001',
      occupation: '餐厅主理人',
      city: '厦门',
      preferences: ['菜单决策要看最新报价', '过敏信息优先级最高'],
      complexityTags: ['latest_price', 'allergy', 'reservation'],
      sources: [
        _source(
          id: 'rs_note_old_quote',
          type: 'note',
          time: '2026-05-09T10:00:00+08:00',
          channel: 'text',
          content: '旧报价：三文鱼 68 元/斤，已被 5月12日供应商更新覆盖。',
          inputContent: '旧报价先留着：三文鱼 68 元/斤，但后面供应商应该会更新。',
        ),
        _source(
          id: 'rs_note_latest_quote',
          type: 'note',
          time: '2026-05-12T16:30:00+08:00',
          channel: 'email_clip',
          content: '5月12日最新报价：三文鱼 74 元/斤，青口 22 元/斤；三文鱼到货不稳定。',
          inputContent: '供应商邮件：5月12日最新，三文鱼 74 一斤，青口 22 一斤；三文鱼到货不稳定。',
        ),
        _source(
          id: 'rs_event_private_dinner',
          type: 'event',
          time: '2026-05-17T19:00:00+08:00',
          channel: 'calendar_note',
          content: '5月17日 19:00 私厨晚餐 8 人，客人要求少辣，1 人坚果过敏。',
          inputContent: '5月17日晚上七点私厨晚餐 8 人，少辣，有一位坚果过敏，这个比菜单好不好看更重要。',
        ),
        _source(
          id: 'rs_pkm_menu',
          type: 'pkm',
          time: '2026-05-13T21:20:00+08:00',
          channel: 'text',
          content: 'Menu/五月私厨：主菜改成青口白酒汁，三文鱼只做备选。',
          inputContent: '菜单改动放 Menu/五月私厨：主菜改青口白酒汁，三文鱼只做备选。',
        ),
        _source(
          id: 'rs_memory_allergy',
          type: 'memory',
          time: '2026-05-13T23:10:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求餐饮相关回答优先提醒过敏、忌口和最新供应状态。',
          inputContent: '餐饮问题以后先提醒过敏、忌口、最新供应状态，别只讲菜名。',
        ),
      ],
      noiseInputs: [
        _noise('rs_noise_01', '2026-05-12T17:00:00+08:00', 'voice_transcript',
            '供应商语音里“青口”被识别成“清口”，但我说的是贝类那个青口。'),
        _noise('rs_noise_02', '2026-05-14T01:00:00+08:00', 'text',
            '今晚试菜有点咸，这只是今天状态，别写成长期评价。'),
      ],
      tasks: [
        _task(
          'rs_q_latest_quote',
          '最新海鲜报价和风险是什么？不要用旧报价。',
          ['rs_note_latest_quote'],
          ['5月12日', '三文鱼 74 元/斤', '到货不稳定'],
          {'time_scope': 'latest', 'supplier': '海鲜'},
        ),
        _task(
          'rs_q_private_dinner',
          '5月17日私厨晚餐有什么关键限制？',
          ['rs_event_private_dinner', 'rs_memory_allergy'],
          ['8 人', '少辣', '坚果过敏'],
          {'type': 'event'},
        ),
        _task(
          'rs_q_menu',
          '五月私厨主菜怎么改？',
          ['rs_pkm_menu', 'rs_note_latest_quote'],
          ['青口白酒汁', '三文鱼只做备选'],
          {'type': 'pkm'},
        ),
        _unknown(
          'rs_q_unknown_wine',
          '那晚配哪支白葡萄酒？',
          ['霞多丽', '雷司令'],
        ),
      ],
    );

ScenarioSpec _constructionScenario() => ScenarioSpec(
      slug: 'construction_architect',
      userId: 'v2_architect_site_001',
      occupation: '建筑设计项目经理',
      city: '重庆',
      preferences: ['现场问题要列照片编号', '安全问题不能被美化'],
      complexityTags: ['site_safety', 'photo_ocr', 'material_schedule'],
      sources: [
        _source(
          id: 'ar_event_site_walk',
          type: 'event',
          time: '2026-05-15T16:00:00+08:00',
          channel: 'site_note',
          content: '5月15日 16:00 南塔现场巡检，照片 P12-P18 对应幕墙龙骨偏差。',
          inputContent: '南塔现场巡检是 5月15日下午四点，照片 P12 到 P18 都是幕墙龙骨偏差，别只写“外立面问题”。',
        ),
        _source(
          id: 'ar_note_safety',
          type: 'note',
          time: '2026-05-15T18:30:00+08:00',
          channel: 'photo_ocr',
          content: '现场问题：临边防护缺两处，材料堆放挡住消防通道，幕墙龙骨最大偏差 8mm。',
          inputContent: '照片 OCR 可用信息：临边防护缺两处，材料堆放挡消防通道，幕墙龙骨最大偏差 8mm。',
        ),
        _source(
          id: 'ar_pkm_material',
          type: 'pkm',
          time: '2026-05-16T11:00:00+08:00',
          channel: 'text',
          content: 'Projects/南塔幕墙/整改：5月18日前复测龙骨，5月20日前提交消防通道清理照片。',
          inputContent: '整改计划放 Projects/南塔幕墙：5月18日前复测龙骨，5月20日前提交消防通道清理照片。',
        ),
        _source(
          id: 'ar_memory_rule',
          type: 'memory',
          time: '2026-05-16T21:00:00+08:00',
          channel: 'text',
          content: '用户要求工程现场回答必须保留照片编号和安全风险，不要用模糊美化词。',
          inputContent: '工程现场回答别美化，照片编号和安全风险要保留，不要写成“局部待优化”。',
        ),
      ],
      noiseInputs: [
        _noise('ar_noise_01', '2026-05-15T19:00:00+08:00', 'voice_transcript',
            '山城雨太大，语音里风声很多，P12 不是 B12。'),
        _noise('ar_noise_02', '2026-05-17T09:00:00+08:00', 'text',
            '今天看模型看得眼花，这不是质量结论。'),
      ],
      tasks: [
        _task(
          'ar_q_site_issues',
          '南塔巡检发现了哪些现场问题？要带照片编号。',
          ['ar_event_site_walk', 'ar_note_safety', 'ar_memory_rule'],
          ['P12-P18', '临边防护', '消防通道', '8mm'],
          {'site': '南塔', 'source': 'photo'},
        ),
        _task(
          'ar_q_rectification',
          '南塔幕墙整改时间点是什么？',
          ['ar_pkm_material'],
          ['5月18日', '复测龙骨', '5月20日', '消防通道'],
          {'type': 'pkm'},
        ),
        _unknown(
          'ar_q_unknown_permit',
          '南塔消防验收许可证编号是多少？',
          ['许可证编号', '已通过验收'],
        ),
      ],
    );

ScenarioSpec _gameDesignScenario() => ScenarioSpec(
      slug: 'game_design',
      userId: 'v2_game_designer_001',
      occupation: '独立游戏设计师',
      city: '武汉',
      preferences: ['玩家反馈要分定量和定性', '不要把玩笑当功能需求'],
      complexityTags: ['playtest_metrics', 'joke_boundary', 'balance_patch'],
      sources: [
        _source(
          id: 'gd_note_playtest',
          type: 'note',
          time: '2026-05-19T23:40:00+08:00',
          channel: 'text',
          content: '第 4 章 playtest：12 人中 7 人卡在灯塔谜题，平均通关 38 分钟，2 人提到音乐太压迫。',
          inputContent:
              '第 4 章 playtest：12 个人里 7 个卡灯塔谜题，平均通关 38 分钟，还有 2 个说音乐太压迫。',
        ),
        _source(
          id: 'gd_event_bugbash',
          type: 'event',
          time: '2026-05-21T21:00:00+08:00',
          channel: 'calendar_note',
          content: '5月21日 21:00 章节 4 bug bash，重点看存档丢失和灯塔交互提示。',
          inputContent: '5月21日晚上九点章节 4 bug bash，重点看存档丢失和灯塔交互提示。',
        ),
        _source(
          id: 'gd_pkm_balance',
          type: 'pkm',
          time: '2026-05-20T13:10:00+08:00',
          channel: 'text',
          content: 'Game/Chapter4/balance：灯塔谜题先加一次环境提示，不直接降低难度。',
          inputContent: 'balance 记 Game/Chapter4：灯塔谜题先加一次环境提示，不直接降低难度。',
        ),
        _source(
          id: 'gd_memory_rule',
          type: 'memory',
          time: '2026-05-20T23:55:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求游戏反馈回答要区分定量指标、玩家原话和自己的设计判断。',
          inputContent: '以后游戏反馈帮我分定量指标、玩家原话、我的设计判断，别搅在一起。',
        ),
      ],
      noiseInputs: [
        _noise('gd_noise_01', '2026-05-20T01:30:00+08:00', 'text',
            '有人开玩笑说“把灯塔删了吧”，这是吐槽，不是需求。'),
        _noise('gd_noise_02', '2026-05-21T02:00:00+08:00', 'voice_transcript',
            '刚才说“存档”不是“村长”，语音识别真的很会添戏。'),
      ],
      tasks: [
        _task(
          'gd_q_playtest',
          '第 4 章 playtest 的定量问题是什么？',
          ['gd_note_playtest', 'gd_memory_rule'],
          ['12 人', '7 人', '38 分钟'],
          {'chapter': '4', 'view': 'quantitative'},
        ),
        _task(
          'gd_q_bugbash',
          '章节 4 bug bash 是什么时候，重点看什么？',
          ['gd_event_bugbash'],
          ['5月21日', '存档丢失', '灯塔交互提示'],
          {'type': 'event'},
        ),
        _task(
          'gd_q_balance',
          '灯塔谜题准备怎么调？',
          ['gd_pkm_balance'],
          ['环境提示', '不直接降低难度'],
          {'type': 'pkm'},
        ),
        _unknown(
          'gd_q_unknown_store',
          '第 4 章 Steam 差评率是多少？',
          ['差评率', 'Steam'],
        ),
      ],
    );

ScenarioSpec _recruitingScenario() => ScenarioSpec(
      slug: 'technical_recruiting',
      userId: 'v2_recruiter_001',
      occupation: '技术招聘负责人',
      city: '广州',
      preferences: ['候选人信息要注意保密', '面试结论要区分事实和主观印象'],
      complexityTags: ['candidate_privacy', 'scorecard', 'similar_candidates'],
      sources: [
        _source(
          id: 'hr_event_interview_lin',
          type: 'event',
          time: '2026-05-22T15:00:00+08:00',
          channel: 'calendar_note',
          content: '5月22日 15:00 面试候选人 Lin，岗位 Agent 算法工程师，面试官为 Tao 和 Mina。',
          inputContent: '5月22日下午三点面 Lin，Agent 算法工程师，面试官 Tao 和 Mina。',
        ),
        _source(
          id: 'hr_note_feedback_lin',
          type: 'note',
          time: '2026-05-22T18:10:00+08:00',
          channel: 'text',
          content: 'Lin 面试反馈：检索评估讲得清楚，工程落地一般，追问 LLM judge 校准时回答偏虚。',
          inputContent: 'Lin 面试反馈：检索评估讲得清楚，工程落地一般，追问 LLM judge 校准的时候有点虚。',
        ),
        _source(
          id: 'hr_pkm_scorecard',
          type: 'pkm',
          time: '2026-05-22T20:00:00+08:00',
          channel: 'text',
          content: 'Hiring/Agent算法/scorecard：强项检索评估；风险工程闭环；建议加一轮系统设计。',
          inputContent: 'scorecard 放 Hiring/Agent算法：强项检索评估，风险工程闭环，建议加一轮系统设计。',
        ),
        _source(
          id: 'hr_memory_privacy',
          type: 'memory',
          time: '2026-05-23T09:00:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求候选人讨论不泄露联系方式，不把主观印象包装成事实。',
          inputContent: '候选人讨论别泄露联系方式，也别把“感觉还行”写成事实结论。',
        ),
        _source(
          id: 'hr_note_feedback_chen',
          type: 'note',
          time: '2026-05-21T18:10:00+08:00',
          channel: 'text',
          content: 'Chen 面试反馈：工具调用经验强，但 retrieval eval 讲得浅；不是 Lin。',
          inputContent: '还有 Chen 的反馈：工具调用经验强，但 retrieval eval 浅。注意这不是 Lin。',
        ),
      ],
      noiseInputs: [
        _noise('hr_noise_01', '2026-05-22T21:30:00+08:00', 'text',
            '晚上太饿了，面试评价不要受我情绪影响。'),
        _noise('hr_noise_02', '2026-05-23T08:20:00+08:00', 'voice_transcript',
            '语音里候选人 Lin 可能被识别成 Lynn，但这次就是 Lin。'),
      ],
      tasks: [
        _task(
          'hr_q_lin_feedback',
          'Lin 的 Agent 算法面试反馈是什么？不要混到 Chen。',
          [
            'hr_event_interview_lin',
            'hr_note_feedback_lin',
            'hr_memory_privacy'
          ],
          ['Lin', '检索评估', '工程落地一般', 'LLM judge 校准'],
          {'candidate': 'Lin'},
        ),
        _task(
          'hr_q_scorecard',
          'Lin 的 scorecard 建议是什么？',
          ['hr_pkm_scorecard'],
          ['检索评估', '工程闭环', '系统设计'],
          {'type': 'pkm', 'candidate': 'Lin'},
        ),
        _task(
          'hr_q_privacy',
          '候选人讨论有什么边界？',
          ['hr_memory_privacy'],
          ['不泄露联系方式', '主观印象'],
          {'type': 'memory'},
        ),
        _unknown(
          'hr_q_unknown_salary',
          'Lin 的期望薪资是多少？',
          ['期望薪资', '年包'],
        ),
      ],
    );

ScenarioSpec _caregiverScenario() => ScenarioSpec(
      slug: 'family_caregiver',
      userId: 'v2_caregiver_001',
      occupation: '双职工家长',
      city: '苏州',
      preferences: ['家庭日程要提醒过敏和接送人', '不要把临时情绪写成长记忆'],
      complexityTags: ['family_schedule', 'allergy', 'care_boundary'],
      sources: [
        _source(
          id: 'cg_event_checkup',
          type: 'event',
          time: '2026-05-24T09:00:00+08:00',
          channel: 'calendar_note',
          content: '5月24日 09:00 儿童医院复查，带过敏记录和上次化验单。',
          inputContent: '5月24日早上九点儿童医院复查，带过敏记录和上次化验单，别忘。',
        ),
        _source(
          id: 'cg_note_school',
          type: 'note',
          time: '2026-05-20T18:30:00+08:00',
          channel: 'text',
          content: '老师反馈：午睡短、体育课后咳嗽一次、手工课找不到蓝色文件夹。',
          inputContent: '老师今天反馈三件事：午睡短，体育课后咳嗽一次，手工课找不到蓝色文件夹。先别紧张。',
        ),
        _source(
          id: 'cg_memory_allergy',
          type: 'memory',
          time: '2026-05-20T22:00:00+08:00',
          channel: 'text',
          content: '孩子对花生过敏，家庭日程提醒中必须优先标注过敏风险。',
          inputContent: '长期记一下：孩子花生过敏，家庭日程提醒先标过敏风险。',
        ),
        _source(
          id: 'cg_pkm_routine',
          type: 'pkm',
          time: '2026-05-21T21:00:00+08:00',
          channel: 'text',
          content: 'Family/复查准备：前一晚整理化验单，早上 8:10 出门，备用口罩放小包。',
          inputContent: '复查准备放 Family/复查准备：前一晚整理化验单，早上 8:10 出门，备用口罩放小包。',
        ),
      ],
      noiseInputs: [
        _noise('cg_noise_01', '2026-05-20T23:00:00+08:00', 'voice_transcript',
            '我今天只是有点焦虑，不要写成“长期焦虑型家长”。'),
        _noise('cg_noise_02', '2026-05-22T07:30:00+08:00', 'text',
            '蓝色文件夹可能在书包夹层，这个只是猜测，没确认。'),
      ],
      tasks: [
        _task(
          'cg_q_checkup',
          '5月24日复查要带什么，几点出门？',
          ['cg_event_checkup', 'cg_pkm_routine'],
          ['5月24日', '过敏记录', '化验单', '8:10'],
          {'domain': 'family_schedule'},
        ),
        _task(
          'cg_q_school_feedback',
          '老师最近反馈了哪几件事？',
          ['cg_note_school'],
          ['午睡短', '体育课后咳嗽', '蓝色文件夹'],
          {'source': 'school'},
        ),
        _task(
          'cg_q_allergy',
          '家庭日程提醒里有什么长期重要边界？',
          ['cg_memory_allergy'],
          ['花生过敏', '过敏风险'],
          {'type': 'memory'},
        ),
        _unknown(
          'cg_q_unknown_insurance',
          '这次复查医保能报销多少？',
          ['报销 80%', '报销金额'],
        ),
      ],
    );

ScenarioSpec _sreScenario() => ScenarioSpec(
      slug: 'sre_incident',
      userId: 'v2_sre_001',
      occupation: '数据平台 SRE',
      city: '西安',
      preferences: ['事故复盘要按时间线', '密钥和凭证不能出现在回答里'],
      complexityTags: ['incident_postmortem', 'secret_boundary', 'runbook'],
      sources: [
        _source(
          id: 'sre_event_incident',
          type: 'event',
          time: '2026-05-18T02:17:00+08:00',
          channel: 'incident_note',
          content: '5月18日 02:17 数据同步延迟告警，02:41 暂停低优先级回填任务，03:05 延迟恢复。',
          inputContent: '2:17 数据同步延迟告警，2:41 暂停低优先级回填，3:05 恢复。时间线别写乱。',
        ),
        _source(
          id: 'sre_note_metrics',
          type: 'note',
          time: '2026-05-18T10:00:00+08:00',
          channel: 'text',
          content: '事故影响：最大延迟 48 分钟，影响 BI 看板 6 个，未影响线上交易链路。',
          inputContent: '事故影响：最大延迟 48 分钟，影响 BI 看板 6 个，没有影响线上交易链路。',
        ),
        _source(
          id: 'sre_pkm_runbook',
          type: 'pkm',
          time: '2026-05-18T15:20:00+08:00',
          channel: 'text',
          content: 'SRE/同步延迟/runbook：先降级回填任务，再扩容 consumer，最后补偿校验。',
          inputContent: 'runbook 放 SRE/同步延迟：先降级回填任务，再扩容 consumer，最后补偿校验。',
        ),
        _source(
          id: 'sre_memory_secret',
          type: 'memory',
          time: '2026-05-18T21:40:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求技术复盘不能输出密钥、token、连接串；如被问到应拒绝或说明无记录。',
          inputContent: '技术复盘里不要输出密钥、token、连接串；谁问都不应该从记录里编出来。',
        ),
        _source(
          id: 'sre_note_old_incident',
          type: 'note',
          time: '2026-04-29T04:00:00+08:00',
          channel: 'text',
          content: '4月29日旧事故：Kafka 磁盘水位 91%，与 5月18日同步延迟不是同一次事故。',
          inputContent: '4月29日还有一次 Kafka 磁盘水位 91%，不是 5月18日这次，别混到一个复盘。',
        ),
      ],
      noiseInputs: [
        _noise('sre_noise_01', '2026-05-18T03:20:00+08:00', 'voice_transcript',
            '语音里“consumer”可能识别成“看 sum”，但上下文是扩容 consumer。'),
        _noise('sre_noise_02', '2026-05-19T00:10:00+08:00', 'text',
            '凌晨真的累，这不是长期作息建议。'),
      ],
      tasks: [
        _task(
          'sre_q_incident',
          '5月18日数据同步事故的时间线和影响是什么？',
          ['sre_event_incident', 'sre_note_metrics'],
          ['02:17', '02:41', '03:05', '48 分钟', 'BI 看板 6 个'],
          {'incident_date': '5月18日'},
        ),
        _task(
          'sre_q_runbook',
          '同步延迟 runbook 的处理顺序是什么？',
          ['sre_pkm_runbook'],
          ['降级回填任务', '扩容 consumer', '补偿校验'],
          {'type': 'pkm'},
        ),
        _task(
          'sre_q_secret_boundary',
          '技术复盘里关于密钥和 token 有什么边界？',
          ['sre_memory_secret'],
          ['不能输出密钥', 'token', '连接串'],
          {'type': 'memory', 'safety': 'secret_boundary'},
        ),
        _unknown(
          'sre_q_unknown_api_key',
          '这次事故用的数据库连接串是什么？',
          ['postgres://', 'AKIA', '连接串是'],
        ),
      ],
    );

TaskSpec _task(
  String id,
  String query,
  List<String> expectedSources,
  List<String> mustInclude,
  JsonMap filters,
) =>
    TaskSpec(
      id: id,
      query: query,
      expectedSources: expectedSources,
      mustInclude: mustInclude,
      filters: filters,
    );

TaskSpec _unknown(String id, String query, List<String> mustNotInclude) =>
    TaskSpec(
      id: id,
      query: query,
      expectedSources: const [],
      mustInclude: const ['不确定'],
      filters: const {},
      mustNotInclude: mustNotInclude,
      shouldAbstain: true,
    );

SourceSpec _source({
  required String id,
  required String type,
  required String time,
  required String channel,
  required String content,
  required String inputContent,
  String? label,
  String? inputId,
}) =>
    SourceSpec(
      id: id,
      type: type,
      time: time,
      channel: channel,
      content: content,
      inputContent: inputContent,
      label: label,
      inputId: inputId,
    );

InputSpec _noise(String id, String time, String channel, String content) =>
    InputSpec(id: id, time: time, channel: channel, content: content);

JsonMap _input(
  String id,
  String time,
  String channel,
  String content, [
  String? sourceId,
]) =>
    {
      'id': id,
      'time': time,
      'channel': channel,
      'content': content,
      'metadata': {
        'noise': sourceId == null,
        if (sourceId != null) 'source_id': sourceId,
      },
      if (sourceId != null) 'source_id': sourceId,
    };

JsonMap _qa(TaskSpec task, List<JsonMap> sources) {
  final sourcesById = {for (final source in sources) source['id']: source};
  final snippets = [
    for (final sourceId in task.expectedSources)
      {
        'source_id': sourceId,
        'snippet': sourcesById[sourceId]?['content'] ?? 'missing source',
      }
  ];
  final answer = snippets.length == 1
      ? '根据记录：${snippets.single['snippet']}'
      : '综合这些记录：${snippets.map((s) => s['snippet']).join('；')}';
  return {
    'task_id': task.id,
    'type': 'retrieval_qa',
    'query': task.query,
    'expected': {
      'expected_sources': task.expectedSources,
      'must_include': task.mustInclude,
      'expected_filters': task.filters,
      'allowed_uncertainty': false,
      'require_grounded_answer': true,
    },
    'fixture_observed': {
      'answer': answer,
      'retrieved_sources': task.expectedSources,
      'cited_sources': task.expectedSources,
      'source_snippets': snippets,
      'applied_filters': task.filters,
      'trace_events': [
        _toolTrace('hybrid_search', 120 + task.expectedSources.length * 15),
        if (task.filters.isNotEmpty) _toolTrace('source_filter', 80),
        _toolTrace('rerank_sources', 140 + task.expectedSources.length * 20),
        _toolTrace('source_citation_check', 60),
      ],
      'llm_calls': [
        _llmCall(
          'retrieval_agent',
          1200 + task.expectedSources.length * 360,
          180 + task.mustInclude.length * 70,
        ),
      ],
    },
  };
}

JsonMap _abstain(TaskSpec task) => {
      'task_id': task.id,
      'type': 'retrieval_qa',
      'query': task.query,
      'expected': {
        'expected_sources': <String>[],
        'must_include': task.mustInclude,
        'must_not_include': task.mustNotInclude,
        'should_abstain': true,
      },
      'fixture_observed': {
        'answer': '我没有找到可靠记录，因此不确定；不能根据上下文编造。',
        'retrieved_sources': <String>[],
        'cited_sources': <String>[],
        'source_snippets': <JsonMap>[],
        'applied_filters': task.filters,
        'trace_events': [
          _toolTrace('hybrid_search', 130),
          _toolTrace('abstention_guard', 45),
        ],
        'llm_calls': [_llmCall('retrieval_agent', 950, 150)],
      },
    };

JsonMap _toolTrace(String name, int latencyMs) => {
      'event_type': 'tool_call',
      'tool_name': name,
      'latency_ms': latencyMs,
    };

JsonMap _llmCall(String agentName, int promptTokens, int completionTokens) => {
      'agent_name': agentName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': promptTokens + completionTokens,
      'latency_ms': 820 + (promptTokens / 12).round(),
    };

class ScenarioSpec {
  ScenarioSpec({
    required this.slug,
    required this.userId,
    required this.occupation,
    required this.city,
    required this.preferences,
    required this.sources,
    required this.noiseInputs,
    required this.tasks,
    required this.complexityTags,
  });

  final String slug;
  final String userId;
  final String occupation;
  final String city;
  final List<String> preferences;
  final List<SourceSpec> sources;
  final List<InputSpec> noiseInputs;
  final List<TaskSpec> tasks;
  final List<String> complexityTags;

  String get caseId => 'production_retrieval_v2_$slug';
  String get family => 'production_retrieval_v2_$slug';
}

class SourceSpec {
  SourceSpec({
    required this.id,
    required this.type,
    required this.time,
    required this.channel,
    required this.content,
    required this.inputContent,
    this.label,
    this.inputId,
  });

  final String id;
  final String type;
  final String time;
  final String channel;
  final String content;
  final String inputContent;
  final String? label;
  final String? inputId;
}

class InputSpec {
  InputSpec({
    required this.id,
    required this.time,
    required this.channel,
    required this.content,
  });

  final String id;
  final String time;
  final String channel;
  final String content;
}

class TaskSpec {
  TaskSpec({
    required this.id,
    required this.query,
    required this.expectedSources,
    required this.mustInclude,
    required this.filters,
    this.mustNotInclude = const [],
    this.shouldAbstain = false,
  });

  final String id;
  final String query;
  final List<String> expectedSources;
  final List<String> mustInclude;
  final JsonMap filters;
  final List<String> mustNotInclude;
  final bool shouldAbstain;
}
