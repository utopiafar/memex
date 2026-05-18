import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/full_chain_medium',
  );
  await outDir.create(recursive: true);

  final cases = [
    for (var i = 0; i < _profiles.length; i++) _case(i + 1, _profiles[i]),
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
    'dataset_id': 'memex_full_chain_replay_medium',
    'version': 2,
    'description': '中等规模中文长时间线全链路 replay 数据集。',
    'created_at': '2026-05-12',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': inputCount,
    'task_count': taskCount,
    'inputs_per_persona': 16,
    'families': ['full_chain_replay'],
    'notes': [
      '所有 persona 和用户输入均为 zh-CN。',
      '每个 persona 覆盖 5 周左右时间线，混合工作、生活、情绪、临时咨询、长期偏好和冲突更新。',
      '所有输入都会走真实 submitInput / LocalTaskExecutor replay。',
      'oracle 只对关键 actionable 输入做 card 断言，对全部链路做成本和任务收敛断言。',
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
    'Generated ${cases.length} full-chain replay cases, '
    '$inputCount inputs, $taskCount tasks at ${outDir.path}',
  );
}

JsonMap _case(int n, JsonMap profile) {
  final caseId = 'full_chain_medium_${_three(n)}';
  final userId = 'eval_fc_medium_${_three(n)}';
  final project = _projects[n % _projects.length];
  final person = _people[(n + 2) % _people.length];
  final inputs = _inputs(n, project, person);
  final titleNeedles = <String, List<String>>{
    'i01': [project],
    'i04': ['父母'],
    'i08': ['回滚'],
    'i12': ['周报'],
    'i15': ['异常值'],
  };
  final tasks = <JsonMap>[
    for (final input in inputs.where(
      (input) => titleNeedles.containsKey(input['suffix']),
    ))
      {
        'task_id': '${caseId}_card_${input['suffix']}',
        'type': 'card_extraction',
        'expected': {
          'input_id': input['id'],
          'status': 'completed',
          'title_contains': titleNeedles[input['suffix']] ?? const <String>[],
          'must_not_fields': ['weather', 'price'],
        },
      },
    {
      'task_id': '${caseId}_cost',
      'type': 'cost_trace',
      'expected': {
        'max_total_tokens': 1500000,
        'max_latency_ms': 1200000,
        'max_tool_calls': 4000,
        'require_all_tasks_completed': true,
        'must_include': ['Facts', 'Cards', 'tasks'],
      },
    },
  ];

  return {
    'case_id': caseId,
    'family': 'full_chain_replay',
    'language': 'zh-CN',
    'persona': {
      'user_id': userId,
      'profile': profile,
    },
    'ground_truth_world': {
      'facts': [
        {
          'id': 'fact_${caseId}_preference',
          'type': 'preference',
          'content': '用户偏好中文输出，喜欢明确提醒，但临时情绪和临时咨询不应自动写成长记忆。',
        },
        {
          'id': 'fact_${caseId}_project',
          'type': 'project_note',
          'content': '$project 需要关注灰度监控、客服话术、回滚预案和预算余量。',
        },
      ],
    },
    'input_stream': inputs
        .map(
          (input) => {
            'id': input['id'],
            'time': input['time'],
            'channel': 'text',
            'content': input['content'],
          },
        )
        .toList(),
    'eval_tasks': tasks,
  };
}

List<JsonMap> _inputs(int n, String project, String person) {
  final rows = [
    ['i00', 1, 9, '这周状态有点乱，先记一下：我想把工作和生活记录都放到 Memex 里，但别把今天的情绪当成长期状态。'],
    ['i01', 2, 10, '下周二上午十点和$person开会，讨论$project 的灰度计划，帮我记一下。'],
    ['i02', 3, 21, '今天下班路上看到一家新开的面馆，味道不错，但排队太久了，只是生活记录。'],
    ['i03', 4, 14, '临时咨询一下，如果晚上睡不着，除了褪黑素还有什么温和一点的方法？'],
    ['i04', 5, 20, '这周六上午提醒我去父母家，顺便带水果和他们的体检报告复印件。'],
    ['i05', 7, 11, '以后重要会议尽量提前一天提醒我，别临近了才说。'],
    ['i06', 9, 22, '今天有点烦，主要是临时会太多，这只是今天，不要当成长期偏好。'],
    ['i07', 12, 16, '如果下次写项目结论，先给判断，再列证据和下一步。'],
    ['i08', 15, 13, '$project 这周风险：灰度监控、客服话术和回滚预案都要盯住。'],
    ['i09', 18, 8, '我之前说不喝咖啡，但最近上午可以喝一杯，下午还是别喝。'],
    ['i10', 21, 19, '朋友推荐了一部电影，名字叫宇宙探索编辑部，先随手记一下。'],
    ['i11', 24, 15, '临时问问，如果客户一直不回消息，催一次怎么措辞比较自然？'],
    ['i12', 27, 17, '周五下班前提醒我把$project 周报发给 Leo，重点写风险和 owner。'],
    ['i13', 30, 9, '今天通勤路上听了一个睡眠播客，感觉最近应该早点睡。'],
    ['i14', 33, 21, '这两天只是想吃清淡一点，别记成长期饮食偏好。'],
    ['i15', 36, 10, '下次看数据时提醒我把异常值单独标出来，别混在整体均值里。'],
  ];

  return rows
      .map(
        (row) => _input(
          n: n,
          suffix: row[0] as String,
          dayOffset: row[1] as int,
          hour: row[2] as int,
          content: row[3] as String,
        ),
      )
      .toList();
}

JsonMap _input({
  required int n,
  required String suffix,
  required int dayOffset,
  required int hour,
  required String content,
}) {
  final day = DateTime.utc(2026, 5, 1).add(Duration(days: dayOffset));
  final month = day.month.toString().padLeft(2, '0');
  final dayText = day.day.toString().padLeft(2, '0');
  final hourText = hour.toString().padLeft(2, '0');
  final minuteText = ((n * 7 + dayOffset) % 60).toString().padLeft(2, '0');
  return {
    'suffix': suffix,
    'id': 'input_fc_${_three(n)}_$suffix',
    'time': '2026-$month-${dayText}T$hourText:$minuteText:00+08:00',
    'content': content,
  };
}

String _three(int n) => n.toString().padLeft(3, '0');

final _profiles = <JsonMap>[
  for (var i = 0; i < 8; i++)
    {
      'occupation': _occupations[i % _occupations.length],
      'city': _cities[i % _cities.length],
      'habits': [_habits[i % _habits.length]],
      'preferences': ['偏好中文输出', _prefs[i % _prefs.length]],
    }
];

const _occupations = [
  '跨境电商运营',
  '产品经理',
  '律师',
  '财务主管',
  '内容运营',
  '数据分析师',
  '独立开发者',
  '咨询顾问',
];

const _cities = ['深圳', '杭州', '广州', '成都', '苏州', '武汉', '上海', '厦门'];
const _habits = ['每周三健身', '周末看望父母', '上午深度工作', '晚上复盘当天工作'];
const _prefs = ['喜欢明确提醒', '重要事项要列来源', '不喜欢太长总结', '能判断时少问澄清'];
const _projects = ['北美站增长', '会员召回', 'Memex eval', '法务合同库', '数据中台', '小红书活动'];
const _people = ['Jason', 'Ada', '老王', 'Annie', 'Leo', 'Mina', '小陈', 'Grace'];
