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
      '输入刻意混合正式记录、语音碎碎念、冗余背景、职业化表达和弱相关闲聊，避免只做模板替换。',
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
    'eval_tasks': _tasks(caseId: caseId, persona: persona, sources: sources),
  };
}

List<_Source> _sources({
  required String caseId,
  required _RetrievalPersona persona,
}) {
  final budgetMetrics = _budgetMetrics(persona);
  final projectRisks = _projectRisks(persona);
  final customerIssues = _customerIssues(persona);
  final reviewSubject = _reviewSubject(persona);
  return [
    _Source(
      id: '${caseId}_event_budget',
      type: 'event',
      content:
          '5月8日 15:00 和 ${persona.primaryPerson} 讨论 ${persona.project} 预算，地点腾讯会议。',
    ),
    _Source(
      id: '${caseId}_note_budget',
      type: 'note',
      content:
          '${persona.project} 预算复盘重点：${budgetMetrics.join('、')}，owner 是 ${persona.primaryPerson}。',
    ),
    _Source(
      id: '${caseId}_mem_meeting_reminder',
      type: 'memory',
      content: '用户希望重要会议提前一天提醒，并在提醒里列出议程。',
    ),
    _Source(
      id: '${caseId}_mem_diet',
      type: 'memory',
      content: '用户点餐偏好：不要海鲜，少糖，${_dietExtra(persona)}。',
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
          'Projects/${persona.project}/周报：风险包括${projectRisks.join('、')}；下一步是补齐 owner。',
    ),
    _Source(
      id: '${caseId}_note_customer',
      type: 'note',
      content:
          '${persona.secondaryPerson} 反馈：客户最常问${customerIssues.join('、')}。',
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
      content: 'Projects/${persona.project}/复盘模板：背景、决策、风险、下一步，结论先行。',
    ),
    _Source(
      id: '${caseId}_mem_no_guessing',
      type: 'memory',
      content: '没有记录时，用户希望回答不确定，不要猜测，尤其是${_highRiskUnknown(persona)}。',
    ),
    _Source(
      id: '${caseId}_event_review',
      type: 'event',
      content: '5月22日 16:00 和设计评审 ${persona.project} 的$reviewSubject，需要带截图。',
    ),
  ];
}

List<JsonMap> _inputs({
  required String caseId,
  required _RetrievalPersona persona,
  required List<_Source> sources,
}) {
  final seedInputs = _retrievalSeedInputs(persona);
  final fillers = _retrievalFillers(persona);
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

List<String> _retrievalSeedInputs(_RetrievalPersona persona) {
  final texture = _workTexture(persona);
  final aside = _casualAside(persona.userId.hashCode);
  final budgetMetrics = _budgetMetrics(persona);
  final projectRisks = _projectRisks(persona);
  final customerIssues = _customerIssues(persona);
  final reviewSubject = _reviewSubject(persona);
  return [
    '$aside 5月8日下午三点，和${persona.primaryPerson}在腾讯会议过了一遍${persona.project}预算；先别写成大结论，会上主要盯${budgetMetrics.join('、')}。',
    '补一条，不然我后面肯定忘：${persona.project}预算复盘 owner 暂时按${persona.primaryPerson}，问这个项目先找 TA 对齐。$texture',
    '以后重要会议提前一天提醒我，提醒里顺手列议程。别只弹一个“明天开会”，那种我会忽略。',
    '点餐偏好还是记一下吧：不要海鲜、少糖，${_dietExtra(persona)}；今天嘴馋不算长期规则。',
    '咖啡规则更新，上午可以喝一杯，下午不要喝。嗯，下午喝完我晚上脑子会很亮但人很废。',
    '把${persona.project}周报放到 Projects，风险写${projectRisks.join('、')}；不要塞到 Resources 里当素材。',
    '${persona.secondaryPerson}刚才反馈，客户最常问${customerIssues.join('、')}。这个是客户反馈，不是我个人偏好。',
    '5月18日上午十点去父母家，记得带${persona.familyItem}。这个和项目无关，之后别从工作笔记里推断。',
    '${persona.project}的${persona.metric}上升，先排查口径，再看模型结果；先别急着甩给算法。',
    '${persona.project}复盘模板就按背景、决策、风险、下一步来，写的时候结论先行。',
    '没有记录就直接说不确定，不要为了显得聪明补${_highRiskUnknown(persona)}这些细节。',
    '5月22日下午四点和设计评审${persona.project}的$reviewSubject，提醒我带截图；这个要按日程看，不要只搜项目笔记。',
  ];
}

List<String> _retrievalFillers(_RetrievalPersona persona) {
  final domain = _domainTexture(persona);
  final terms = _domainTerms(persona);
  return [
    '今天$terms[0]先别下结论，等$terms[1]对齐完再写进项目复盘。',
    '刚看到$terms[2]有点不对，可能只是临时口径，不要当成长期问题。',
    '$terms[3]这块如果后面问到，先找原始记录，不要只看我这句碎碎念。',
    '我现在只是把$terms[4]丢进来占个坑，明天再决定放 Projects 还是 Resources。',
    '如果$terms[5]和${persona.metric}同时出现，先判断是不是同一批数据。',
    '$terms[6]相关内容很容易被误读，回答时最好带上具体来源。',
    '这条有点像自言自语：$terms[7]还没定，不要生成日程，也不要写长期偏好。',
    '后面如果搜$terms[8]，记得过滤${persona.project}，别把别的项目混进来。',
    '今天$terms[9]只是临时插曲，不代表流程已经改了。',
    '$terms[10]如果没有明确 owner，就先标不确定，别自动猜${persona.primaryPerson}。',
    '今天只是有点累，可能是会太密，别写成长期状态。',
    '${persona.city}今天下雨，线下沟通多留二十分钟；这个只是天气背景。',
    '临时查了一下会议纪要怎么压缩，明天再整理，先不要进项目结论。',
    '晚上听了个播客，里面说复盘要区分事实、推测和建议，挺对但先当闲聊。',
    '如果我问“那个风险”，大概率指最近的${persona.project}发布风险，不过还是要看来源。',
    '下次周报最后要有 owner 和回滚预案，别只写“持续观察”。',
    '今天想喝奶茶只是嘴馋，不要更新饮食偏好。',
    '${persona.habits.first}这件事尽量不要和深度工作冲突，先记背景就行。',
    '重要报告里保留来源，别只写结论；面向老板可以短，但证据不能丢。',
    '客户案例可以放资源库，不要写进个人偏好。$domain',
    '这周可能加班，但不是常态，别生成“长期晚上加班”。',
    '如果工具调用太多，要单独标成本风险，尤其是连续检索那种。',
    '周末可能看展，只是想法，不用放工作日程。',
    '今天情绪一般，和事情碎有关，不要进长期画像。',
    '指标口径变更一定要记录日期，后面回看时很容易混。',
    '没有证据时宁可说不确定，这条比猜中一次更重要。',
    '今晚九点后只提醒紧急事项，普通材料明早再看。',
    '阅读材料放 Resources，不要混到项目周报。',
    '复盘时先看异常，再看整体趋势；不要一上来讲平均值。',
    '和${persona.secondaryPerson}相关的内容多半是客户反馈或素材反馈，但也别无脑归类。',
    '如果问到${persona.project}的长期经验，优先看 PKM，再看散落 notes。',
    '今天只是想买点零食，别写成饮食规则。',
    '最近材料很多，查找时先按项目过滤会更准。',
    '周报里的风险要和真实来源一起出现，不要只凭记忆总结。',
    '如果问家庭安排，只看 event，不要用项目笔记推测。',
    '今天突然想去旅行，只是想法，不代表已经订票。',
    '复盘里如果出现${persona.metric}，要看日期和上下文。',
    '重要提醒不要只召回最近一条，可能需要同时看偏好和日程。',
    '客户反馈和项目决策要分开引用，不然会把抱怨当结论。',
    '如果没有 source id，回答里不要装作查到了。',
    '晚上只是想喝咖啡不代表规则变了，仍按上午可以、下午不喝。',
    '问到${persona.primaryPerson}时，先查人名再查项目。',
    '问到${persona.secondaryPerson}时，多半和客户反馈或素材反馈有关。',
    '今天看了一个医疗科普，别当成我的个人健康记录。',
    '如果是票务、航班、药量这类高风险问题，没有记录就明确不确定。',
    '资料归档时不要把 Resources 和 Projects 混在一起。',
  ];
}

String _extraRetrievalInput(int index, _RetrievalPersona persona) {
  final detail = _retrievalDetails[index % _retrievalDetails.length];
  final intent = _retrievalIntents[index % _retrievalIntents.length];
  final scope = _retrievalScopes[index % _retrievalScopes.length];
  final terms = _domainTerms(persona);
  final person = index.isEven ? persona.primaryPerson : persona.secondaryPerson;
  final templates = [
    '刚在路上想到${persona.project}的${terms[index % terms.length]}，话说一半也先记着，之后问$intent 时别只靠最近一条。',
    '$person 刚刚提到$detail，和${terms[(index + 1) % terms.length]}有关，先作为项目背景放着，不要写成我的长期偏好。',
    '如果我问“上次那个$detail”，先按${persona.project}和$person过滤，再看${terms[(index + 2) % terms.length]}，别把相似词硬凑。',
    '临时查了$intent 的资料，还没执行，尤其是${terms[(index + 3) % terms.length]}这块，别当成已经发生过的计划。',
    '${persona.city}这边今天只是临时线下沟通，地点不要被推断成正式会议地点；${terms[(index + 4) % terms.length]}也还没定。',
    '${persona.project}的$scope 只基于记录回答，没有 source 就说不确定，别补剧情。',
    '我把$detail 放在项目笔记里，后面回答时要引用来源，不要只给漂亮总结。',
    '如果查询涉及$person，先查人名，再查${persona.project}，最后再看时间范围。',
    '今天只是想到$intent 的一个可能方向，还没决策，别写成最终结论。',
    '复盘时如果提到${persona.metric}，要说明来自哪条 note 或 PKM。',
    '如果问家庭、票务、药量这类问题，没有明确记录就直接说不确定。',
    '$scope 的问题不要只靠向量相似，要结合项目、人物和类型过滤。',
    '嗯还有个小尾巴：$detail 可能和${persona.habits.last}冲突，先别自动排日程。',
    '这个可能没价值：今天脑子有点乱，看到$intent 就想先收藏，明天再判断。',
  ];
  return templates[index % templates.length];
}

String _workTexture(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return '顺带看一下广告组和物流口径，别把退款率和投诉率混了。';
    case '数据分析师':
      return '如果后面写分析，metric id 保留英文，口径写清楚。';
    case '律师':
      return '风险结论必须列来源，别只写一句“需要注意”。';
    case '财务主管':
      return '数字先给口径，再给差异，不然月结会对不上。';
    case '内容运营':
      return '素材来源和投放反馈分开放，别混进一个结论。';
    case '独立开发者':
      return '少写空话，最好直接能变成 backlog 或 changelog。';
    case '老师':
      return '如果涉及课程反馈，别超过三条重点。';
    case '医生':
      return '医疗相关只能区分记录和建议，别自动下结论。';
    case 'HRBP':
      return '敏感信息少写细节，只保留必要上下文。';
    case '设计师':
      return '视觉反馈最好带截图来源，不然之后对不上版本。';
    case '创业者':
      return '商务复盘先列风险和下一步，别写成鸡汤。';
    default:
      return '结论先行，但证据和来源不要丢。';
  }
}

String _domainTexture(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return '广告投放、listing、物流这些要分开看。';
    case '数据分析师':
      return 'SQL 口径、dashboard 备注和临时结论不要混。';
    case '律师':
      return '合同条款、客户口述和正式意见要分层。';
    case '财务主管':
      return '发票、付款、预算差异最好能追到原始记录。';
    case '内容运营':
      return '素材灵感、评论反馈和最终选题不要混。';
    case '独立开发者':
      return '用户反馈、bug 和产品想法最好能分开归档。';
    case '老师':
      return '备课灵感和学生反馈不是同一种来源。';
    case '医生':
      return '随访记录和医学建议必须分开。';
    case 'HRBP':
      return '绩效校准内容要尽量少暴露个人细节。';
    case '设计师':
      return '截图版本、视觉反馈和最终改稿要能互相对上。';
    case '创业者':
      return '客户承诺、试点风险和现金流判断要分开。';
    default:
      return '项目事实和个人偏好要分开。';
  }
}

String _casualAside(int seed) {
  const asides = [
    '顺手记一下，别嫌碎：',
    '嗯，这条可能以后会问到：',
    '先记个不太工整的版本：',
    '刚开完会脑子有点乱，但重点是：',
  ];
  return asides[seed.abs() % asides.length];
}

List<String> _budgetMetrics(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return ['广告花费', 'ROAS', '退款率'];
    case '数据分析师':
      return ['样本覆盖率', 'retry rate', 'p95 latency'];
    case '律师':
      return ['合同风险数', '审批时长', '条款争议'];
    case '财务主管':
      return ['预算差异率', '付款延迟', '发票异常'];
    case '内容运营':
      return ['互动率', '素材消耗', '转化评论'];
    case '独立开发者':
      return ['激活率', '退款工单', '订阅续费'];
    case '老师':
      return ['完课率', '试听转化', '作业提交率'];
    case '医生':
      return ['随访完成率', '预约爽约率', '问卷回收'];
    case 'HRBP':
      return ['校准争议数', '面评完成率', '敏感反馈'];
    case '设计师':
      return ['点击率', '首屏停留', '转化路径'];
    case '创业者':
      return ['试点转化率', '客单价', '回款周期'];
    default:
      return ['CPA', 'ROAS', '退款率'];
  }
}

List<String> _projectRisks(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return ['预算超投', '物流时效', '素材疲劳'];
    case '数据分析师':
      return ['样本偏差', '口径漂移', '任务重试'];
    case '律师':
      return ['条款歧义', '审批滞后', '合规口径'];
    case '财务主管':
      return ['发票缺失', '付款延迟', '预算占用'];
    case '内容运营':
      return ['素材撞题', '评论误读', '发布时间'];
    case '独立开发者':
      return ['支付失败', '客服堆积', '灰度回滚'];
    case '老师':
      return ['讲义延迟', '学生反馈', '直播设备'];
    case '医生':
      return ['随访漏记', '隐私边界', '预约冲突'];
    case 'HRBP':
      return ['敏感泄露', '校准争议', '面评缺口'];
    case '设计师':
      return ['截图版本', '视觉一致性', '交互误解'];
    case '创业者':
      return ['客户承诺', '交付范围', '现金流'];
    default:
      return ['灰度监控', '客服话术', '回滚预案'];
  }
}

List<String> _customerIssues(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return ['优惠券失效', '物流延迟', '退款入口'];
    case '数据分析师':
      return ['看板加载慢', '筛选条件丢失', '口径解释'];
    case '律师':
      return ['条款版本找不到', '审批意见分散', '签署状态不清'];
    case '财务主管':
      return ['发票抬头错误', '付款状态延迟', '预算占用不准'];
    case '内容运营':
      return ['素材授权', '评论抽样', '发布时间'];
    case '独立开发者':
      return ['订阅激活失败', '退款工单', '导入报错'];
    case '老师':
      return ['回放打不开', '作业入口', '讲义下载'];
    case '医生':
      return ['随访提醒', '问卷提交', '隐私授权'];
    case 'HRBP':
      return ['面评入口', '校准记录', '敏感备注'];
    case '设计师':
      return ['截图版本', '按钮文案', '动效卡顿'];
    case '创业者':
      return ['试点排期', '报价边界', '验收材料'];
    default:
      return ['导出失败后的重试', '数据延迟'];
  }
}

String _reviewSubject(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '律师':
      return '合同风险页';
    case '财务主管':
      return '月结差异页';
    case '医生':
      return '随访表单页';
    case '老师':
      return '公开课报名页';
    case '设计师':
      return '会员首屏';
    case '创业者':
      return '试点报价页';
    case '跨境电商运营':
      return '投流看板';
    default:
      return '页面';
  }
}

String _dietExtra(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '医生':
      return '夜班前别安排咖啡';
    case '老师':
      return '上课前不要太辣';
    case '财务主管':
      return '月底加班餐别太油';
    case '设计师':
      return '评审前少冰饮';
    default:
      return '晚上少咖啡';
  }
}

String _highRiskUnknown(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '医生':
      return '药量、诊断、隐私授权';
    case '律师':
      return '合同条款、签署状态、法律意见';
    case '财务主管':
      return '付款状态、发票金额、预算占用';
    case 'HRBP':
      return '绩效评级、敏感反馈、候选人隐私';
    default:
      return '航班号、药量、地点';
  }
}

List<String> _domainTerms(_RetrievalPersona persona) {
  switch (persona.occupation) {
    case '跨境电商运营':
      return [
        '广告组预算',
        '物流时效',
        '优惠券入口',
        'listing 文案',
        '北美仓库存',
        '退款原因',
        '投放素材',
        '黑五节奏',
        'ROAS 看板',
        '客服工单',
        '渠道 owner',
      ];
    case '数据分析师':
      return [
        'SQL 口径',
        'dashboard 版本',
        '样本窗口',
        '埋点漏数',
        '重试任务',
        'p95 latency',
        '异常归因',
        '实验分桶',
        '指标血缘',
        '数据延迟',
        '分析 owner',
      ];
    case '律师':
      return [
        '合同条款',
        '审批意见',
        '签署状态',
        '合规风险',
        '版本红线',
        '法务备忘',
        '客户口述',
        '授权范围',
        '争议条款',
        '归档编号',
        '案件 owner',
      ];
    case '财务主管':
      return [
        '发票抬头',
        '付款批次',
        '预算占用',
        '月结差异',
        '成本中心',
        '对账备注',
        '报销附件',
        '供应商编号',
        '现金流预测',
        '审批节点',
        '财务 owner',
      ];
    case '内容运营':
      return [
        '选题池',
        '评论样本',
        '素材授权',
        '发布时间',
        '互动率',
        '达人反馈',
        '封面版本',
        '话题标签',
        '转化评论',
        '内容排期',
        '运营 owner',
      ];
    case '独立开发者':
      return [
        '订阅激活',
        '退款工单',
        '导入报错',
        '支付回调',
        'changelog',
        '客服邮件',
        '灰度用户',
        '崩溃日志',
        '产品 backlog',
        '续费提醒',
        '开发 owner',
      ];
    case '老师':
      return [
        '讲义版本',
        '学生反馈',
        '作业入口',
        '直播回放',
        '试听名单',
        '板书截图',
        '课前提醒',
        '答疑问题',
        '完课率',
        '家长沟通',
        '课程 owner',
      ];
    case '医生':
      return [
        '随访问卷',
        '预约冲突',
        '病历摘要',
        '隐私授权',
        '复诊提醒',
        '问诊记录',
        '指标复查',
        '患者反馈',
        '医嘱边界',
        '门诊排班',
        '随访 owner',
      ];
    case 'HRBP':
      return [
        '面评入口',
        '绩效校准',
        '敏感备注',
        '候选人隐私',
        '招聘进度',
        '用人反馈',
        '争议记录',
        '组织调整',
        '面试官排期',
        'offer 风险',
        'HR owner',
      ];
    case '设计师':
      return [
        '截图版本',
        '首屏文案',
        '按钮状态',
        '动效卡顿',
        '用户测试',
        '走查清单',
        '视觉稿',
        '组件间距',
        '转化路径',
        '评审意见',
        '设计 owner',
      ];
    case '创业者':
      return [
        '试点排期',
        '报价边界',
        '客户承诺',
        '验收材料',
        '现金流',
        '交付范围',
        '回款周期',
        '渠道线索',
        '商务跟进',
        '风险清单',
        '试点 owner',
      ];
    default:
      return [
        '灰度监控',
        '客服话术',
        '回滚预案',
        '预算口径',
        '项目周报',
        '客户反馈',
        '截图版本',
        '指标异常',
        '复盘模板',
        '工具成本',
        '项目 owner',
      ];
  }
}

List<JsonMap> _tasks({
  required String caseId,
  required _RetrievalPersona persona,
  required List<_Source> sources,
}) {
  final sourcesById = {for (final source in sources) source.id: source};
  final projectRisks = _projectRisks(persona);
  final customerIssues = _customerIssues(persona);
  final reviewSubject = _reviewSubject(persona);
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
      mustInclude: [projectRisks.first, projectRisks.last, '下一步'],
      filters: {'project': persona.project},
    ),
    _RetrievalTaskSpec(
      suffix: 'customer_feedback',
      query: '${persona.secondaryPerson}反馈的客户问题是什么？',
      expectedSources: ['${caseId}_note_customer'],
      mustInclude: [persona.secondaryPerson, customerIssues.first],
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
      query: '我哪天要和设计评审$reviewSubject，需要带什么？',
      expectedSources: ['${caseId}_event_review'],
      mustInclude: ['5月22日', reviewSubject, '截图'],
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
      mustInclude: ['预算', projectRisks.first, '结论先行'],
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
    for (final spec in specs)
      _retrievalTask(caseId: caseId, spec: spec, sourcesById: sourcesById),
  ];
}

JsonMap _retrievalTask({
  required String caseId,
  required _RetrievalTaskSpec spec,
  required Map<String, _Source> sourcesById,
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
  final sourceSnippets = [
    for (final sourceId in spec.expectedSources)
      {
        'source_id': sourceId,
        'snippet': sourcesById[sourceId]?.content ?? 'missing source $sourceId'
      }
  ];
  final answer = spec.shouldAbstain
      ? '我没有找到相关记录，因此不确定。'
      : '根据记录：${sourceSnippets.map((s) => s['snippet']).join('；')}';
  final observed = {
    'answer': answer,
    'retrieved_sources': spec.expectedSources,
    'cited_sources': spec.expectedSources,
    if (spec.filters.isNotEmpty) 'applied_filters': spec.filters,
    'source_snippets': sourceSnippets,
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
