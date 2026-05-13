import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty
        ? args.first
        : 'evals/datasets/production_like_retrieval_v3',
  );
  await outDir.create(recursive: true);

  final seedCases = await _loadSeedCases();
  final extraCases = _extraScenarios().map(_buildCase).toList();
  final cases = _interleave(seedCases, extraCases);
  final inputCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['input_stream'] as List).length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );
  final userIds = {
    for (final evalCase in cases)
      ((evalCase['persona'] as JsonMap)['user_id']).toString(),
  };

  final manifest = {
    'dataset_id': 'memex_production_like_retrieval_v3',
    'version': 3,
    'description': '生产贴近 Retrieval QA 扩展样本 v3：在 v2 基础上扩到更多行业、更多输入和更不规则任务结构。',
    'created_at': '2026-05-13',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': userIds.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'task_count': taskCount,
    'families': cases.map((evalCase) => evalCase['family']).toList(),
    'lineage': {
      'extends_dataset': 'memex_production_like_retrieval_v2',
      'v2_seed_case_count': seedCases.length,
      'new_case_count': extraCases.length,
      'v2_fixes_applied': [
        'chronic_care_voice_noise_made_less_artificial',
        'technical_recruiting_candidate_filter_made_explicit',
      ],
    },
    'complexity_dimensions': [
      'multi_source_answer',
      'latest_update_vs_old_record',
      'domain_specific_persona',
      'weakly_related_noise',
      'voice_transcript_chatter',
      'screenshot_or_email_like_input',
      'similar_entity_distractor',
      'sensitive_boundary',
      'abstention_for_unknown_fact',
      'uneven_task_count_per_case',
    ],
    'notes': [
      'v3 继承 v2 中已审计的复杂 retrieval 场景，并新增 12 个行业样本。',
      '新增样本刻意让 task 数、source 数和拒答比例不完全一致，避免“每个 case 都一样”的模板感。',
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
    'Generated ${cases.length} production-like retrieval v3 cases, '
    '$inputCount inputs, $taskCount tasks at ${outDir.path}',
  );
}

Future<List<JsonMap>> _loadSeedCases() async {
  final seedFile =
      File('evals/datasets/production_like_retrieval_v2/cases.jsonl');
  if (!await seedFile.exists()) {
    throw StateError(
      'Missing v2 seed dataset. Run generate_production_like_retrieval_v2_dataset.dart first.',
    );
  }
  final cases = <JsonMap>[];
  await for (final line in seedFile
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    cases.add(_upgradeSeedCase(jsonDecode(line) as JsonMap));
  }
  return cases;
}

JsonMap _upgradeSeedCase(JsonMap raw) {
  final upgraded = jsonDecode(jsonEncode(raw)) as JsonMap;
  upgraded['case_id'] = upgraded['case_id'].toString().replaceFirst(
      'production_retrieval_v2_', 'production_retrieval_v3_seed_');
  upgraded['family'] = upgraded['family'].toString().replaceFirst(
      'production_retrieval_v2_', 'production_retrieval_v3_seed_');
  final metadata = _map(upgraded['metadata']);
  metadata['iteration'] = 'production_like_retrieval_v3_seed';
  metadata['lineage'] = 'v2_seed';
  upgraded['metadata'] = metadata;

  if (upgraded['case_id'] == 'production_retrieval_v3_seed_chronic_care') {
    for (final input in _list(upgraded['input_stream']).map(_map)) {
      if (input['id'] == 'cc_noise_02') {
        input['content'] = '语音识别经常把“授权”后半截吞掉，后面要结合上下文看，不要机械照抄。';
      }
    }
  }
  if (upgraded['case_id'] ==
      'production_retrieval_v3_seed_technical_recruiting') {
    for (final task in _list(upgraded['eval_tasks']).map(_map)) {
      final expected = _map(task['expected']);
      final filters = _map(expected['expected_filters']);
      if (task['task_id'] == 'hr_q_lin_feedback' ||
          task['task_id'] == 'hr_q_scorecard') {
        filters['candidate'] = 'Lin';
        filters['exclude_candidate'] = 'Chen';
        expected['expected_filters'] = filters;
        final observed = _map(task['fixture_observed']);
        observed['applied_filters'] = filters;
      }
    }
  }
  return upgraded;
}

List<JsonMap> _interleave(List<JsonMap> seedCases, List<JsonMap> extraCases) {
  final cases = <JsonMap>[];
  final maxLen = seedCases.length > extraCases.length
      ? seedCases.length
      : extraCases.length;
  for (var i = 0; i < maxLen; i++) {
    if (i < seedCases.length) cases.add(seedCases[i]);
    if (i < extraCases.length) cases.add(extraCases[i]);
  }
  return cases;
}

List<ScenarioSpec> _extraScenarios() => [
      _crossBorderEcommerce(),
      _roboticsLab(),
      _climateAnalyst(),
      _museumCurator(),
      _podcastProducer(),
      _patentAgent(),
      _counselorOps(),
      _travelPlanner(),
      _openSourceMaintainer(),
      _farmCoopManager(),
      _insuranceAdjuster(),
      _universityLabManager(),
    ];

JsonMap _buildCase(ScenarioSpec scenario) {
  final sources = scenario.sources.map((source) => source.toJson()).toList();
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
    'case_id': 'production_retrieval_v3_${scenario.slug}',
    'family': 'production_retrieval_v3_${scenario.slug}',
    'language': 'zh-CN',
    'persona': {
      'user_id': 'v3_${scenario.slug}_001',
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
      'iteration': 'production_like_retrieval_v3',
      'lineage': 'new_v3_case',
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

ScenarioSpec _crossBorderEcommerce() => ScenarioSpec(
      slug: 'cross_border_ecommerce',
      occupation: '跨境电商运营',
      city: '义乌',
      preferences: ['物流和广告数据要分站点', '不要把未确认关税当事实'],
      complexityTags: [
        'marketplace_metrics',
        'customs_distractor',
        'latest_plan'
      ],
      sources: [
        _source(
          id: 'cb_note_ads',
          type: 'note',
          time: '2026-05-12T09:20:00+08:00',
          channel: 'spreadsheet_note',
          content:
              '德国站广告 ACOS 31%，退货率 6.4%；法国站 ACOS 27%，退货率 4.1%。德国站差评集中在尺码偏小。',
          inputContent:
              '欧洲站广告先记：德国 ACOS 31%、退货率 6.4%，法国 ACOS 27%、退货率 4.1%。德国差评主要说尺码偏小。',
        ),
        _source(
          id: 'cb_event_forwarder',
          type: 'event',
          time: '2026-05-14T16:00:00+08:00',
          channel: 'calendar_note',
          content: '5月14日 16:00 与货代 Leo 对齐德国站补货，重点确认清关资料和欧盟责任人标签。',
          inputContent: '5月14日下午四点和货代 Leo 对德国站补货，清关资料、欧盟责任人标签都要问。',
        ),
        _source(
          id: 'cb_pkm_plan',
          type: 'pkm',
          time: '2026-05-14T21:30:00+08:00',
          channel: 'text',
          content:
              'Marketplaces/EU/May：德国站先改尺码表，再降 15% broad match 预算；法国站预算不动。',
          inputContent:
              '计划放 Marketplaces/EU/May：德国先改尺码表，再把 broad match 预算降 15%；法国预算先别动。',
        ),
        _source(
          id: 'cb_memory_rule',
          type: 'memory',
          time: '2026-05-15T00:10:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求跨境运营回答必须按站点拆分，并标注未确认的清关或税务信息。',
          inputContent: '跨境运营回答帮我按站点拆，不确定的清关、税务要写未确认，别说得像已经盖章。',
        ),
      ],
      noiseInputs: [
        _noise('cb_noise_01', '2026-05-12T23:00:00+08:00', 'voice_transcript',
            '语音里“ACOS”有时会变成“a cost”，上下文是广告指标。'),
        _noise('cb_noise_02', '2026-05-15T09:00:00+08:00', 'text',
            '听说新关税可能要变，但我没有正式文件，别写进结论。'),
      ],
      tasks: [
        _task(
          'cb_q_ads_by_site',
          '欧洲站广告和退货情况分别怎样？',
          ['cb_note_ads', 'cb_memory_rule'],
          ['德国站', 'ACOS 31%', '法国站', '4.1%', '尺码偏小'],
          {'market': 'EU', 'split_by': 'site'},
        ),
        _task(
          'cb_q_forwarder',
          '和货代 Leo 什么时候对德国站补货，要确认什么？',
          ['cb_event_forwarder'],
          ['5月14日', '清关资料', '欧盟责任人标签'],
          {'person': 'Leo', 'site': '德国站'},
        ),
        _task(
          'cb_q_plan',
          '德国站五月动作是什么？法国站预算要动吗？',
          ['cb_pkm_plan'],
          ['改尺码表', '降 15%', '法国站预算不动'],
          {'type': 'pkm', 'site': '德国站'},
        ),
        _unknown(
          'cb_q_unknown_tariff',
          '新关税已经确定是多少？',
          ['税率 12%', '已经确定'],
        ),
      ],
    );

ScenarioSpec _roboticsLab() => ScenarioSpec(
      slug: 'robotics_lab',
      occupation: '机器人实验室工程师',
      city: '合肥',
      preferences: ['实验结论要保留固件版本', '不要把猜测当根因'],
      complexityTags: [
        'firmware_version',
        'calibration',
        'root_cause_boundary'
      ],
      sources: [
        _source(
          id: 'rb_event_test',
          type: 'event',
          time: '2026-05-17T10:30:00+08:00',
          channel: 'lab_note',
          content: '5月17日 10:30 做机械臂抓取测试，固件 v2.8.3，夹爪偏移集中在第 4 次抓取后。',
          inputContent: '机械臂抓取测试是 5月17日 10:30，固件 v2.8.3。夹爪偏移基本都在第 4 次抓取后出现。',
        ),
        _source(
          id: 'rb_note_metrics',
          type: 'note',
          time: '2026-05-17T13:00:00+08:00',
          channel: 'text',
          content: '抓取测试 40 次，成功 32 次；失败中 5 次为视觉定位漂移，3 次为夹爪压力不足。',
          inputContent: '40 次抓取，成功 32 次。失败里 5 次视觉定位漂移，3 次夹爪压力不足。',
        ),
        _source(
          id: 'rb_pkm_calibration',
          type: 'pkm',
          time: '2026-05-18T09:20:00+08:00',
          channel: 'text',
          content: 'Lab/ArmA/calibration：先重跑相机外参，再把夹爪压力阈值从 0.42 调到 0.47。',
          inputContent: 'calibration 放 Lab/ArmA：先重跑相机外参，再把夹爪压力阈值 0.42 调到 0.47。',
        ),
        _source(
          id: 'rb_memory_rule',
          type: 'memory',
          time: '2026-05-18T23:10:00+08:00',
          channel: 'text',
          content: '用户写实验复盘时要求保留版本、样本量和未确认根因。',
          inputContent: '以后实验复盘记得写版本、样本量，根因没确认就说未确认，不要帮我脑补。',
        ),
      ],
      noiseInputs: [
        _noise('rb_noise_01', '2026-05-17T13:30:00+08:00', 'voice_transcript',
            '刚才语音里“外参”可能断成“外餐”，别理，实验上下文是相机外参。'),
        _noise('rb_noise_02', '2026-05-18T00:30:00+08:00', 'text',
            '我怀疑是相机热漂，但还没验证，先别写成根因。'),
      ],
      tasks: [
        _task(
          'rb_q_test_result',
          '机械臂抓取测试结果怎样？要带固件版本和样本量。',
          ['rb_event_test', 'rb_note_metrics', 'rb_memory_rule'],
          ['v2.8.3', '40 次', '成功 32 次', '第 4 次'],
          {'device': 'ArmA', 'version': 'v2.8.3'},
        ),
        _task(
          'rb_q_failures',
          '失败主要分哪两类？',
          ['rb_note_metrics'],
          ['视觉定位漂移', '5 次', '夹爪压力不足', '3 次'],
          {'view': 'failure_breakdown'},
        ),
        _task(
          'rb_q_calibration',
          '下一步校准动作是什么？',
          ['rb_pkm_calibration'],
          ['重跑相机外参', '0.42', '0.47'],
          {'type': 'pkm'},
        ),
        _unknown(
          'rb_q_unknown_root_cause',
          '根因是不是相机热漂？',
          ['根因就是相机热漂', '已经确认'],
        ),
      ],
    );

ScenarioSpec _climateAnalyst() => ScenarioSpec(
      slug: 'climate_analyst',
      occupation: '气候风险分析师',
      city: '昆明',
      preferences: ['风险结论要标数据来源', '预警和预测不能混用'],
      complexityTags: ['sensor_data', 'forecast_boundary', 'regional_filter'],
      sources: [
        _source(
          id: 'cl_note_sensor',
          type: 'note',
          time: '2026-05-10T07:45:00+08:00',
          channel: 'sensor_digest',
          content: '滇池北岸 3 个雨量站过去 6 小时累计 41mm、38mm、44mm；南岸站点低于 20mm。',
          inputContent: '雨量 digest：滇池北岸三个站过去 6 小时 41、38、44mm，南岸都低于 20mm。',
        ),
        _source(
          id: 'cl_event_briefing',
          type: 'event',
          time: '2026-05-10T09:30:00+08:00',
          channel: 'calendar_note',
          content: '5月10日 09:30 给社区应急小组做内涝风险 briefing，重点讲北岸低洼片区。',
          inputContent: '9:30 给社区应急小组讲内涝风险，重点是北岸低洼片区，不要泛泛讲全市。',
        ),
        _source(
          id: 'cl_pkm_threshold',
          type: 'pkm',
          time: '2026-05-10T11:00:00+08:00',
          channel: 'text',
          content: 'Risk/滇池北岸/threshold：6小时雨量超过 40mm 且排水泵站检修时，建议发布内部关注。',
          inputContent: 'threshold 放 Risk/滇池北岸：6小时超过 40mm 加上泵站检修，建议内部关注。',
        ),
        _source(
          id: 'cl_memory_boundary',
          type: 'memory',
          time: '2026-05-10T22:20:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求气候风险回答区分观测数据、模型预测和正式预警。',
          inputContent: '气候风险回答帮我分清观测数据、模型预测、正式预警，别混着说。',
        ),
      ],
      noiseInputs: [
        _noise('cl_noise_01', '2026-05-10T08:00:00+08:00', 'text',
            '今天雨声太大，录音可能断断续续，数值以 digest 为准。'),
        _noise('cl_noise_02', '2026-05-10T12:30:00+08:00', 'text',
            '还没有正式红色预警，不要在回答里写“已发布”。'),
      ],
      tasks: [
        _task(
          'cl_q_sensor',
          '滇池北岸和南岸雨量有什么差异？',
          ['cl_note_sensor'],
          ['北岸', '41mm', '44mm', '南岸', '20mm'],
          {'region': '滇池北岸'},
        ),
        _task(
          'cl_q_briefing',
          'briefing 是什么时候，重点区域是哪？',
          ['cl_event_briefing'],
          ['5月10日', '09:30', '北岸低洼片区'],
          {'type': 'event'},
        ),
        _task(
          'cl_q_threshold',
          '内部关注的触发条件是什么？',
          ['cl_pkm_threshold', 'cl_memory_boundary'],
          ['6小时雨量超过 40mm', '排水泵站检修', '内部关注'],
          {'type': 'pkm'},
        ),
        _unknown(
          'cl_q_unknown_alert',
          '正式红色预警已经发布了吗？',
          ['已发布红色预警', '红色预警已经发布'],
        ),
      ],
    );

ScenarioSpec _museumCurator() => ScenarioSpec(
      slug: 'museum_curator',
      occupation: '博物馆策展人',
      city: '西安',
      preferences: ['展品信息要区分借展和馆藏', '保险和温湿度不能省略'],
      complexityTags: ['loan_artifact', 'humidity_boundary', 'insurance'],
      sources: [
        _source(
          id: 'ms_event_loan',
          type: 'event',
          time: '2026-05-20T15:00:00+08:00',
          channel: 'calendar_note',
          content: '5月20日 15:00 与洛阳馆确认青铜镜借展清单，借展期 6月3日 到 8月28日。',
          inputContent: '5月20日下午三点和洛阳馆确认青铜镜借展清单，借展期 6月3日 到 8月28日。',
        ),
        _source(
          id: 'ms_note_condition',
          type: 'note',
          time: '2026-05-20T17:40:00+08:00',
          channel: 'photo_ocr',
          content: '青铜镜 A17 边缘有旧修补痕，运输湿度要求 45%-55%，保险估值 120 万。',
          inputContent:
              'condition report OCR：A17 边缘有旧修补痕，运输湿度 45%-55%，保险估值 120 万。',
        ),
        _source(
          id: 'ms_pkm_layout',
          type: 'pkm',
          time: '2026-05-21T10:20:00+08:00',
          channel: 'text',
          content: 'Exhibition/青铜镜/动线：A17 放第二展柜，不与强光互动屏相邻。',
          inputContent: '展陈动线放 Exhibition/青铜镜：A17 第二展柜，不要挨着强光互动屏。',
        ),
        _source(
          id: 'ms_memory_rule',
          type: 'memory',
          time: '2026-05-21T21:30:00+08:00',
          channel: 'text',
          content: '用户要求展品回答必须区分借展方、馆藏状态、保险估值和保存条件。',
          inputContent: '展品回答要分借展方、馆藏状态、保险估值、保存条件，别只讲故事。',
        ),
      ],
      noiseInputs: [
        _noise('ms_noise_01', '2026-05-20T18:00:00+08:00', 'voice_transcript',
            '语音里 A17 可能听成 A70，但照片编号是 A17。'),
        _noise('ms_noise_02', '2026-05-22T09:30:00+08:00', 'text',
            '今天展厅空调声音很大，这不是温湿度数据。'),
      ],
      tasks: [
        _task(
          'ms_q_loan',
          '青铜镜借展和借展期是什么？',
          ['ms_event_loan', 'ms_memory_rule'],
          ['洛阳馆', '6月3日', '8月28日'],
          {'artifact': '青铜镜'},
        ),
        _task(
          'ms_q_condition',
          'A17 的保存和保险要点是什么？',
          ['ms_note_condition', 'ms_memory_rule'],
          ['旧修补痕', '45%-55%', '120 万'],
          {'artifact': 'A17'},
        ),
        _task(
          'ms_q_layout',
          'A17 展陈位置有什么限制？',
          ['ms_pkm_layout'],
          ['第二展柜', '不与强光互动屏相邻'],
          {'type': 'pkm'},
        ),
        _unknown(
          'ms_q_unknown_crate',
          'A17 的运输箱编号是多少？',
          ['运输箱编号', 'crate'],
        ),
      ],
    );

ScenarioSpec _podcastProducer() => ScenarioSpec(
      slug: 'podcast_producer',
      occupation: '播客制作人',
      city: '长沙',
      preferences: ['节目流程要区分录制和上线', '广告口播不能乱编'],
      complexityTags: [
        'guest_schedule',
        'sponsor_boundary',
        'transcript_noise'
      ],
      sources: [
        _source(
          id: 'pc_event_recording',
          type: 'event',
          time: '2026-05-18T20:00:00+08:00',
          channel: 'calendar_note',
          content: '5月18日 20:00 录制第 42 期，嘉宾是 Suki，主题为独立开发者如何做定价。',
          inputContent: '第 42 期 5月18日晚上八点录，嘉宾 Suki，主题独立开发者定价。',
        ),
        _source(
          id: 'pc_note_edit',
          type: 'note',
          time: '2026-05-19T01:20:00+08:00',
          channel: 'transcript_clip',
          content: '剪辑点：00:14:20 删除键盘噪声，00:31:10 保留关于年付折扣的争论，00:48:05 插入过场。',
          inputContent: '剪辑点有点碎：14分20秒删键盘噪声，31分10秒保留年付折扣争论，48分05秒插过场。',
        ),
        _source(
          id: 'pc_pkm_publish',
          type: 'pkm',
          time: '2026-05-19T11:00:00+08:00',
          channel: 'text',
          content: 'Podcast/E42/publish：5月22日 08:00 上线，标题先用“独立开发者定价不是算术题”。',
          inputContent: '发布计划放 Podcast/E42：5月22日早上八点上线，标题先用“独立开发者定价不是算术题”。',
        ),
        _source(
          id: 'pc_memory_sponsor',
          type: 'memory',
          time: '2026-05-19T23:00:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求播客回答不能编广告口播；没有 sponsor 素材时必须说未确认。',
          inputContent: '播客相关别编广告口播，没有 sponsor 素材就说未确认，别帮我顺嘴写一段。',
        ),
      ],
      noiseInputs: [
        _noise('pc_noise_01', '2026-05-19T01:00:00+08:00', 'text',
            '我现在耳朵有点麻，这不是节目评价。'),
        _noise('pc_noise_02', '2026-05-20T10:00:00+08:00', 'voice_transcript',
            '语音里 Suki 可能被识别成 su key，嘉宾就是 Suki。'),
      ],
      tasks: [
        _task(
          'pc_q_recording',
          '第 42 期什么时候录，嘉宾和主题是什么？',
          ['pc_event_recording'],
          ['5月18日', 'Suki', '独立开发者', '定价'],
          {'episode': '42'},
        ),
        _task(
          'pc_q_edit_points',
          '第 42 期剪辑点有哪些？',
          ['pc_note_edit'],
          ['00:14:20', '键盘噪声', '00:31:10', '年付折扣'],
          {'episode': '42', 'type': 'edit'},
        ),
        _task(
          'pc_q_publish',
          '第 42 期计划什么时候上线，标题是什么？',
          ['pc_pkm_publish'],
          ['5月22日', '08:00', '独立开发者定价不是算术题'],
          {'type': 'pkm'},
        ),
        _unknown(
          'pc_q_unknown_sponsor',
          '这一期 sponsor 口播文案是什么？',
          ['本期由', '赞助文案'],
        ),
      ],
    );

ScenarioSpec _patentAgent() => ScenarioSpec(
      slug: 'patent_agent',
      occupation: '专利代理人',
      city: '上海',
      preferences: ['专利结论要区分客户描述和检索证据', '未经检索不能说可授权'],
      complexityTags: ['prior_art', 'claim_scope', 'legal_boundary'],
      sources: [
        _source(
          id: 'pt_event_inventor',
          type: 'event',
          time: '2026-05-09T14:00:00+08:00',
          channel: 'meeting_note',
          content: '5月9日 14:00 与发明人 Dr. Xu 沟通柔性传感器方案，对方强调低温封装和可重复弯折。',
          inputContent: '5月9日下午两点和 Dr. Xu 聊柔性传感器，重点是低温封装、可重复弯折。',
        ),
        _source(
          id: 'pt_note_prior',
          type: 'note',
          time: '2026-05-10T18:10:00+08:00',
          channel: 'search_note',
          content: '初检发现 CN1128 公开低温封装，但没有覆盖 5000 次弯折后的电阻漂移补偿。',
          inputContent: '初检：CN1128 有低温封装，但没覆盖 5000 次弯折后的电阻漂移补偿。',
        ),
        _source(
          id: 'pt_pkm_claim',
          type: 'pkm',
          time: '2026-05-11T11:30:00+08:00',
          channel: 'text',
          content: 'Patents/柔性传感器/claims：主权利要求聚焦弯折后漂移补偿，不把低温封装单独作为新颖点。',
          inputContent: 'claims 放 Patents/柔性传感器：主权利要求聚焦弯折后漂移补偿，低温封装别单独当新颖点。',
        ),
        _source(
          id: 'pt_memory_rule',
          type: 'memory',
          time: '2026-05-11T23:00:00+08:00',
          channel: 'text',
          content: '用户要求专利回答不能把客户自述当检索结论，必须标注初检状态。',
          inputContent: '专利回答别把客户自述当检索结论，初检就是初检，要写状态。',
        ),
      ],
      noiseInputs: [
        _noise('pt_noise_01', '2026-05-10T20:00:00+08:00', 'voice_transcript',
            '语音里 CN1128 可能漏了 CN 前缀，按检索笔记为准。'),
        _noise('pt_noise_02', '2026-05-12T09:00:00+08:00', 'text',
            '客户说“肯定能授权”只是客户说法，别写成法律判断。'),
      ],
      tasks: [
        _task(
          'pt_q_invention',
          'Dr. Xu 的柔性传感器方案重点是什么？',
          ['pt_event_inventor'],
          ['Dr. Xu', '低温封装', '可重复弯折'],
          {'person': 'Dr. Xu'},
        ),
        _task(
          'pt_q_prior_art',
          '初检 CN1128 覆盖了什么，没覆盖什么？',
          ['pt_note_prior', 'pt_memory_rule'],
          ['低温封装', '5000 次弯折', '电阻漂移补偿'],
          {'source_status': 'preliminary_search'},
        ),
        _task(
          'pt_q_claim',
          '主权利要求应该聚焦哪里？',
          ['pt_pkm_claim'],
          ['弯折后漂移补偿', '低温封装', '不把'],
          {'type': 'pkm'},
        ),
        _unknown(
          'pt_q_unknown_allowance',
          '这个专利已经确认能授权了吗？',
          ['确认能授权', '已经授权'],
        ),
      ],
    );

ScenarioSpec _counselorOps() => ScenarioSpec(
      slug: 'counselor_ops',
      occupation: '心理咨询机构运营',
      city: '杭州',
      preferences: ['咨询相关回答不能诊断', '排班要保护来访者隐私'],
      complexityTags: ['privacy_boundary', 'schedule', 'non_diagnosis'],
      sources: [
        _source(
          id: 'co_event_supervision',
          type: 'event',
          time: '2026-05-16T19:30:00+08:00',
          channel: 'calendar_note',
          content: '5月16日 19:30 督导会议，讨论青少年团体课排班和危机转介流程。',
          inputContent: '5月16日晚上 7:30 督导会，讲青少年团体课排班和危机转介流程。',
        ),
        _source(
          id: 'co_note_feedback',
          type: 'note',
          time: '2026-05-17T12:00:00+08:00',
          channel: 'text',
          content: '家长反馈：报名入口难找、课前提醒太晚、对保密边界说明不够清楚。',
          inputContent: '家长反馈三点：报名入口难找，课前提醒太晚，保密边界说明不清楚。',
        ),
        _source(
          id: 'co_pkm_process',
          type: 'pkm',
          time: '2026-05-17T20:00:00+08:00',
          channel: 'text',
          content: 'Ops/青少年团体课：报名页先加保密边界说明，再把课前提醒提前到 24 小时。',
          inputContent: '流程改动放 Ops/青少年团体课：报名页先加保密边界说明，课前提醒提前到 24 小时。',
        ),
        _source(
          id: 'co_memory_rule',
          type: 'memory',
          time: '2026-05-18T09:00:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求心理咨询相关记录只描述运营事实，不做诊断或标签化判断。',
          inputContent: '咨询相关记录只写运营事实，不做诊断，不要给来访者贴标签。',
        ),
      ],
      noiseInputs: [
        _noise('co_noise_01', '2026-05-17T23:00:00+08:00', 'text',
            '我自己今天累，不代表机构排班有问题。'),
        _noise('co_noise_02', '2026-05-18T10:30:00+08:00', 'voice_transcript',
            '语音断了半句，别把来访者名字写进总结。'),
      ],
      tasks: [
        _task(
          'co_q_supervision',
          '督导会议是什么时候，讨论什么？',
          ['co_event_supervision'],
          ['5月16日', '青少年团体课', '危机转介流程'],
          {'type': 'event'},
        ),
        _task(
          'co_q_feedback',
          '家长反馈集中在哪些运营问题？',
          ['co_note_feedback'],
          ['报名入口', '课前提醒', '保密边界'],
          {'domain': 'operations'},
        ),
        _task(
          'co_q_process',
          '青少年团体课流程下一步怎么改？',
          ['co_pkm_process', 'co_memory_rule'],
          ['保密边界说明', '24 小时', '不做诊断'],
          {'type': 'pkm'},
        ),
        _unknown(
          'co_q_unknown_client',
          '某个来访者具体诊断是什么？',
          ['抑郁症', '焦虑症', '诊断是'],
        ),
      ],
    );

ScenarioSpec _travelPlanner() => ScenarioSpec(
      slug: 'travel_planner',
      occupation: '高端旅行顾问',
      city: '成都',
      preferences: ['旅行方案要区分已确认和待确认', '签证和过敏信息优先'],
      complexityTags: ['confirmed_vs_pending', 'visa', 'allergy'],
      sources: [
        _source(
          id: 'tv_event_client_call',
          type: 'event',
          time: '2026-05-23T11:00:00+08:00',
          channel: 'meeting_note',
          content: '5月23日 11:00 与客户 Z 家庭沟通瑞士行程，已确认 7月12日 抵达苏黎世。',
          inputContent: '5月23日 11 点和客户 Z 家庭聊瑞士行程，已确认 7月12日 到苏黎世。',
        ),
        _source(
          id: 'tv_note_constraints',
          type: 'note',
          time: '2026-05-23T12:30:00+08:00',
          channel: 'text',
          content: '客户限制：一名儿童坚果过敏，老人不走长坡；少女峰段想坐火车但尚未出票。',
          inputContent: '限制记一下：小朋友坚果过敏，老人不走长坡；少女峰想坐火车但没出票。',
        ),
        _source(
          id: 'tv_pkm_plan',
          type: 'pkm',
          time: '2026-05-24T09:10:00+08:00',
          channel: 'text',
          content: 'Trips/Swiss/Z-family：前两晚苏黎世湖区，第三天转因特拉肯；少女峰火车票待确认。',
          inputContent: '行程放 Trips/Swiss/Z-family：前两晚苏黎世湖区，第三天因特拉肯；少女峰票待确认。',
        ),
        _source(
          id: 'tv_memory_rule',
          type: 'memory',
          time: '2026-05-24T22:00:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求旅行方案必须标注已确认、待确认，并优先提醒签证、过敏和行动不便。',
          inputContent: '旅行方案一定分已确认、待确认，签证、过敏、行动不便先提醒。',
        ),
      ],
      noiseInputs: [
        _noise('tv_noise_01', '2026-05-23T13:00:00+08:00', 'text',
            '我个人想去冰川快车，这不是客户需求。'),
        _noise('tv_noise_02', '2026-05-24T10:00:00+08:00', 'voice_transcript',
            '语音里 Z family 可能听成 Zee，客户代号就是 Z。'),
      ],
      tasks: [
        _task(
          'tv_q_confirmed',
          'Z 家庭瑞士行程哪些已确认？',
          ['tv_event_client_call', 'tv_pkm_plan', 'tv_memory_rule'],
          ['7月12日', '苏黎世', '前两晚苏黎世湖区'],
          {'client': 'Z-family', 'status': 'confirmed'},
        ),
        _task(
          'tv_q_constraints',
          'Z 家庭有哪些旅行限制要优先提醒？',
          ['tv_note_constraints', 'tv_memory_rule'],
          ['坚果过敏', '不走长坡', '待确认'],
          {'client': 'Z-family'},
        ),
        _unknown(
          'tv_q_unknown_hotel',
          '因特拉肯酒店已经订哪家？',
          ['酒店已订', '酒店名称'],
        ),
      ],
    );

ScenarioSpec _openSourceMaintainer() => ScenarioSpec(
      slug: 'open_source_maintainer',
      occupation: '开源项目维护者',
      city: '南京',
      preferences: ['安全问题不能提前公开细节', '发布说明要区分破坏性变更'],
      complexityTags: ['security_boundary', 'release_notes', 'pr_distractor'],
      sources: [
        _source(
          id: 'os_note_prs',
          type: 'note',
          time: '2026-05-19T16:30:00+08:00',
          channel: 'github_digest',
          content:
              '本周 PR：#428 修复 Windows 路径；#431 改 tokenizer cache；#433 是文档拼写，不影响发布。',
          inputContent:
              'GitHub digest：#428 Windows 路径，#431 tokenizer cache，#433 文档拼写，不影响发布。',
        ),
        _source(
          id: 'os_event_release',
          type: 'event',
          time: '2026-05-21T22:00:00+08:00',
          channel: 'calendar_note',
          content:
              '5月21日 22:00 准备 0.9.4 release，必须跑 Windows matrix 和 tokenizer cache regression。',
          inputContent:
              '5月21日晚上十点准备 0.9.4 release，Windows matrix 和 tokenizer cache regression 必跑。',
        ),
        _source(
          id: 'os_pkm_notes',
          type: 'pkm',
          time: '2026-05-20T11:00:00+08:00',
          channel: 'text',
          content:
              'OSS/0.9.4/notes：无 breaking change；重点写 Windows path fix 和 tokenizer cache speedup。',
          inputContent:
              'release notes 放 OSS/0.9.4：无 breaking change，重点 Windows path fix 和 tokenizer cache speedup。',
        ),
        _source(
          id: 'os_memory_security',
          type: 'memory',
          time: '2026-05-20T23:30:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求安全 issue 未公开前不要在普通回答中泄露复现细节或 token。',
          inputContent: '安全 issue 没公开前，不要在普通回答里泄露复现细节或 token。',
        ),
      ],
      noiseInputs: [
        _noise('os_noise_01', '2026-05-19T17:00:00+08:00', 'text',
            '我吐槽 CI 慢只是情绪，不是 release blocker。'),
        _noise('os_noise_02', '2026-05-20T09:00:00+08:00', 'text',
            '有个安全报告在私有渠道，但这里没记录具体复现步骤。'),
      ],
      tasks: [
        _task(
          'os_q_release_scope',
          '0.9.4 release 主要包含什么，是否有 breaking change？',
          ['os_note_prs', 'os_pkm_notes'],
          ['#428', '#431', '无 breaking change'],
          {'release': '0.9.4'},
        ),
        _task(
          'os_q_release_checks',
          '0.9.4 发布前必须跑哪些检查？',
          ['os_event_release'],
          ['Windows matrix', 'tokenizer cache regression'],
          {'type': 'event'},
        ),
        _task(
          'os_q_security_boundary',
          '安全 issue 未公开前回答有什么边界？',
          ['os_memory_security'],
          ['不要', '复现细节', 'token'],
          {'safety': 'security_disclosure'},
        ),
        _unknown(
          'os_q_unknown_cve',
          '这个安全问题的 CVE 编号是什么？',
          ['CVE-', '编号是'],
        ),
      ],
    );

ScenarioSpec _farmCoopManager() => ScenarioSpec(
      slug: 'farm_coop_manager',
      occupation: '农业合作社负责人',
      city: '大理',
      preferences: ['农事建议要区分观察和用药建议', '有机认证限制不能省略'],
      complexityTags: ['organic_constraint', 'weather', 'field_observation'],
      sources: [
        _source(
          id: 'fm_note_field',
          type: 'note',
          time: '2026-05-12T06:30:00+08:00',
          channel: 'field_note',
          content: '3 号茶园新梢卷曲率约 18%，叶背有少量虫卵；2 号茶园未见明显扩散。',
          inputContent: '早上巡田：3 号茶园新梢卷曲率大概 18%，叶背少量虫卵；2 号没明显扩散。',
        ),
        _source(
          id: 'fm_event_agronomist',
          type: 'event',
          time: '2026-05-13T08:00:00+08:00',
          channel: 'calendar_note',
          content: '5月13日 08:00 农技员到 3 号茶园复查，带黄板记录和有机认证用药清单。',
          inputContent: '5月13日早上八点农技员到 3 号茶园复查，带黄板记录和有机认证用药清单。',
        ),
        _source(
          id: 'fm_pkm_action',
          type: 'pkm',
          time: '2026-05-13T12:00:00+08:00',
          channel: 'text',
          content: 'Farm/3号茶园/虫害：先加密黄板监测，暂不喷药；48 小时后复查卷曲率。',
          inputContent: 'Farm/3号茶园/虫害：先加密黄板监测，暂不喷药；48 小时后复查卷曲率。',
        ),
        _source(
          id: 'fm_memory_rule',
          type: 'memory',
          time: '2026-05-13T22:00:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求农事回答区分田间观察和用药建议，有机认证限制优先。',
          inputContent: '农事回答分田间观察和用药建议，有机认证限制优先，别乱建议喷药。',
        ),
      ],
      noiseInputs: [
        _noise('fm_noise_01', '2026-05-12T07:00:00+08:00', 'text',
            '今天露水很重，照片看起来更严重，别只靠照片判断。'),
        _noise('fm_noise_02', '2026-05-14T06:00:00+08:00', 'voice_transcript',
            '语音里“黄板”有点糊，不是“黄片”。'),
      ],
      tasks: [
        _task(
          'fm_q_observation',
          '3 号茶园和 2 号茶园观察有什么差异？',
          ['fm_note_field'],
          ['3 号茶园', '18%', '虫卵', '2 号茶园'],
          {'field': '3号茶园'},
        ),
        _task(
          'fm_q_visit',
          '农技员什么时候复查，要带什么？',
          ['fm_event_agronomist'],
          ['5月13日', '黄板记录', '有机认证用药清单'],
          {'type': 'event'},
        ),
        _task(
          'fm_q_action',
          '当前虫害处理动作是什么？',
          ['fm_pkm_action', 'fm_memory_rule'],
          ['加密黄板监测', '暂不喷药', '48 小时'],
          {'type': 'pkm'},
        ),
        _unknown(
          'fm_q_unknown_pesticide',
          '现在应该喷哪种农药？',
          ['应该喷', '农药名称'],
        ),
      ],
    );

ScenarioSpec _insuranceAdjuster() => ScenarioSpec(
      slug: 'insurance_adjuster',
      occupation: '保险理赔定损员',
      city: '郑州',
      preferences: ['定损结论必须标证据状态', '疑似欺诈不能写成事实'],
      complexityTags: ['claim_photos', 'fraud_boundary', 'repair_quote'],
      sources: [
        _source(
          id: 'ia_event_inspection',
          type: 'event',
          time: '2026-05-14T10:00:00+08:00',
          channel: 'calendar_note',
          content: '5月14日 10:00 勘查车险案 C-7821，地点北环路停车场，车主 Wei 在场。',
          inputContent: '5月14日上午十点勘查 C-7821，北环路停车场，车主 Wei 在场。',
        ),
        _source(
          id: 'ia_note_damage',
          type: 'note',
          time: '2026-05-14T11:10:00+08:00',
          channel: 'photo_ocr',
          content: '照片 P04-P09：右前翼子板擦伤，保险杠卡扣断裂；维修站初报 4200 元。',
          inputContent: '照片 P04 到 P09：右前翼子板擦伤，保险杠卡扣断，维修站初报 4200。',
        ),
        _source(
          id: 'ia_pkm_followup',
          type: 'pkm',
          time: '2026-05-14T18:00:00+08:00',
          channel: 'text',
          content: 'Claims/C-7821：补拍底盘照片，等待交警事故认定书；疑似旧伤只标待核实。',
          inputContent: 'Claims/C-7821：补拍底盘照片，等交警事故认定书；疑似旧伤只写待核实。',
        ),
        _source(
          id: 'ia_memory_rule',
          type: 'memory',
          time: '2026-05-14T22:00:00+08:00',
          channel: 'text',
          content: '用户要求理赔回答必须区分已证实损伤、待核实旧伤和主观怀疑。',
          inputContent: '理赔回答分已证实损伤、待核实旧伤、主观怀疑，不要把疑似欺诈写成事实。',
        ),
      ],
      noiseInputs: [
        _noise('ia_noise_01', '2026-05-14T12:00:00+08:00', 'voice_transcript',
            '语音里 C-7821 可能漏了 C，案号以日程为准。'),
        _noise('ia_noise_02', '2026-05-15T09:00:00+08:00', 'text',
            '我个人觉得旧伤可能有问题，但还没有证据。'),
      ],
      tasks: [
        _task(
          'ia_q_damage',
          'C-7821 已记录的损伤和初报金额是什么？',
          ['ia_event_inspection', 'ia_note_damage'],
          ['C-7821', '右前翼子板', '卡扣断裂', '4200'],
          {'claim_id': 'C-7821'},
        ),
        _task(
          'ia_q_followup',
          'C-7821 后续还要补什么材料？',
          ['ia_pkm_followup'],
          ['底盘照片', '交警事故认定书', '待核实'],
          {'type': 'pkm'},
        ),
        _task(
          'ia_q_boundary',
          '理赔回答有什么证据边界？',
          ['ia_memory_rule'],
          ['已证实损伤', '待核实旧伤', '主观怀疑'],
          {'type': 'memory'},
        ),
        _unknown(
          'ia_q_unknown_fraud',
          '这个案子已经确认欺诈了吗？',
          ['确认欺诈', '就是骗保'],
        ),
      ],
    );

ScenarioSpec _universityLabManager() => ScenarioSpec(
      slug: 'university_lab_manager',
      occupation: '高校实验室管理员',
      city: '天津',
      preferences: ['安全库存和危险品分开记录', '预约冲突要说清楚时间'],
      complexityTags: ['inventory', 'hazmat_boundary', 'booking_conflict'],
      sources: [
        _source(
          id: 'ul_note_inventory',
          type: 'note',
          time: '2026-05-11T09:00:00+08:00',
          channel: 'inventory_note',
          content: '试剂库存：乙腈 4 瓶，甲醇 9 瓶；乙腈低于安全库存 6 瓶，需要补货。',
          inputContent: '库存：乙腈 4 瓶，甲醇 9 瓶。乙腈安全库存是 6，已经低了。',
        ),
        _source(
          id: 'ul_event_hplc',
          type: 'event',
          time: '2026-05-12T14:00:00+08:00',
          channel: 'calendar_note',
          content: '5月12日 14:00-16:00 HPLC 被 Li 课题组预约；16:00-17:00 是维护窗口。',
          inputContent: '5月12日 14 到 16 点 HPLC 是 Li 课题组，16 到 17 点维护窗口。',
        ),
        _source(
          id: 'ul_pkm_purchase',
          type: 'pkm',
          time: '2026-05-11T18:00:00+08:00',
          channel: 'text',
          content: 'Lab/采购/五月：乙腈补 8 瓶，走危险品审批；甲醇本周不补。',
          inputContent: '采购放 Lab/采购/五月：乙腈补 8 瓶，走危险品审批；甲醇本周不补。',
        ),
        _source(
          id: 'ul_memory_rule',
          type: 'memory',
          time: '2026-05-11T23:20:00+08:00',
          channel: 'voice_transcript',
          content: '用户要求实验室回答必须区分普通耗材、危险品审批和设备预约冲突。',
          inputContent: '实验室回答分普通耗材、危险品审批、设备预约冲突，不要混成一个 todo。',
        ),
      ],
      noiseInputs: [
        _noise('ul_noise_01', '2026-05-11T10:00:00+08:00', 'text',
            '我说的“乙腈”不是“一斤”，语音识别又乱了。'),
        _noise('ul_noise_02', '2026-05-12T13:00:00+08:00', 'text',
            '有人临时想插队用 HPLC，但没有确认，不要写成预约。'),
      ],
      tasks: [
        _task(
          'ul_q_inventory',
          '乙腈和甲醇库存怎样，哪个需要补货？',
          ['ul_note_inventory'],
          ['乙腈 4 瓶', '甲醇 9 瓶', '安全库存 6 瓶'],
          {'material': '乙腈'},
        ),
        _task(
          'ul_q_hplc',
          '5月12日 HPLC 预约和维护窗口是什么？',
          ['ul_event_hplc'],
          ['14:00-16:00', 'Li 课题组', '16:00-17:00'],
          {'equipment': 'HPLC'},
        ),
        _task(
          'ul_q_purchase',
          '五月采购计划里乙腈和甲醇怎么处理？',
          ['ul_pkm_purchase', 'ul_memory_rule'],
          ['乙腈补 8 瓶', '危险品审批', '甲醇本周不补'],
          {'type': 'pkm'},
        ),
        _unknown(
          'ul_q_unknown_queue',
          '临时插队用 HPLC 的人已经确认了吗？',
          ['已经确认', '插队预约'],
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
}) =>
    SourceSpec(
      id: id,
      type: type,
      time: time,
      channel: channel,
      content: content,
      inputContent: inputContent,
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
      : '综合这些记录：${snippets.map((snippet) => snippet['snippet']).join('；')}';
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
        _toolTrace('hybrid_search', 130 + task.expectedSources.length * 18),
        if (task.filters.isNotEmpty) _toolTrace('source_filter', 85),
        _toolTrace('rerank_sources', 150 + task.expectedSources.length * 20),
        _toolTrace('source_citation_check', 65),
      ],
      'llm_calls': [
        _llmCall(
          'retrieval_agent',
          1300 + task.expectedSources.length * 380,
          190 + task.mustInclude.length * 65,
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
          _toolTrace('hybrid_search', 135),
          _toolTrace('abstention_guard', 48),
        ],
        'llm_calls': [_llmCall('retrieval_agent', 980, 160)],
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
      'latency_ms': 850 + (promptTokens / 12).round(),
    };

JsonMap _map(Object? raw) => raw is JsonMap ? raw : <String, dynamic>{};

List<Object?> _list(Object? raw) => raw is List ? raw : const [];

class ScenarioSpec {
  ScenarioSpec({
    required this.slug,
    required this.occupation,
    required this.city,
    required this.preferences,
    required this.sources,
    required this.noiseInputs,
    required this.tasks,
    required this.complexityTags,
  });

  final String slug;
  final String occupation;
  final String city;
  final List<String> preferences;
  final List<SourceSpec> sources;
  final List<InputSpec> noiseInputs;
  final List<TaskSpec> tasks;
  final List<String> complexityTags;
}

class SourceSpec {
  SourceSpec({
    required this.id,
    required this.type,
    required this.time,
    required this.channel,
    required this.content,
    required this.inputContent,
    this.inputId,
  });

  final String id;
  final String type;
  final String time;
  final String channel;
  final String content;
  final String inputContent;
  final String? inputId;

  JsonMap toJson() => {
        'id': id,
        'type': type,
        'content': content,
      };
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
