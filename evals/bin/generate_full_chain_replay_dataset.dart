import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/full_chain_medium',
  );
  await outDir.create(recursive: true);

  final cases = <JsonMap>[
    _case(
      n: 1,
      occupation: '跨境电商运营',
      city: '深圳',
      inputs: [
        _input('a', '2026-05-11T09:10:00+08:00', '明天上午十点提醒我和 Ada 过一下投流预算。'),
        _input('b', '2026-05-11T09:13:00+08:00', '周五下午三点和老王在腾讯会议复盘客户续约，记一下。'),
      ],
      titleNeedles: {
        'a': ['投流预算'],
        'b': ['客户续约'],
      },
    ),
    _case(
      n: 2,
      occupation: '产品经理',
      city: '杭州',
      inputs: [
        _input('a', '2026-05-11T10:02:00+08:00', '下周三晚上七点提醒我去望京和 Annie 吃饭。'),
        _input('b', '2026-05-11T10:05:00+08:00', '今天下班前提醒我把数据看板周报发给 Leo。'),
      ],
      titleNeedles: {
        'a': ['吃饭'],
        'b': ['数据看板'],
      },
    ),
    _case(
      n: 3,
      occupation: '律师',
      city: '广州',
      inputs: [
        _input('a', '2026-05-11T11:20:00+08:00', '5月16日下午两点和 Mina 线上确认合同风险。'),
        _input('b', '2026-05-11T11:24:00+08:00', '明早九点提醒我检查版本灰度监控和回滚预案。'),
      ],
      titleNeedles: {
        'a': ['合同风险'],
        'b': ['灰度'],
      },
    ),
    _case(
      n: 4,
      occupation: '财务主管',
      city: '成都',
      inputs: [
        _input('a', '2026-05-11T13:00:00+08:00', '周四中午前提醒我确认供应商付款清单。'),
        _input(
            'b', '2026-05-11T13:04:00+08:00', '明天下午四点和 Jason 讨论预算调整，地点飞书会议。'),
      ],
      titleNeedles: {
        'a': ['付款清单'],
        'b': ['预算调整'],
      },
    ),
    _case(
      n: 5,
      occupation: '内容运营',
      city: '苏州',
      inputs: [
        _input('a', '2026-05-11T15:30:00+08:00', '这周五提醒我整理小红书活动复盘素材。'),
        _input('b', '2026-05-11T15:35:00+08:00', '5月18日上午十点和 Grace 看一下选题排期。'),
      ],
      titleNeedles: {
        'a': ['小红书'],
        'b': ['选题排期'],
      },
    ),
    _case(
      n: 6,
      occupation: '数据分析师',
      city: '武汉',
      inputs: [
        _input('a', '2026-05-11T16:40:00+08:00', '明天早上提醒我检查实验埋点有没有漏字段。'),
        _input('b', '2026-05-11T16:43:00+08:00', '周三下午两点和小陈复盘转化漏斗异常。'),
      ],
      titleNeedles: {
        'a': ['埋点'],
        'b': ['转化漏斗'],
      },
    ),
  ];

  final manifest = {
    'dataset_id': 'memex_full_chain_replay_medium',
    'version': 1,
    'description': '中等规模中文全链路 replay 数据集。',
    'created_at': '2026-05-11',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'persona_count': cases.length,
    'case_count': cases.length,
    'input_count': cases.fold<int>(
      0,
      (sum, evalCase) => sum + (evalCase['input_stream'] as List).length,
    ),
    'task_count': cases.fold<int>(
      0,
      (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
    ),
    'families': ['full_chain_replay'],
    'notes': [
      '所有 persona 和用户输入均为 zh-CN。',
      '该数据集用于真实 submitInput / LocalTaskExecutor replay。',
      'oracle 只约束链路稳定性、card 状态、关键标题信息和成本预算，不强行绑定具体模板类型。',
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
    'Generated ${cases.length} full-chain replay cases at ${outDir.path}',
  );
}

JsonMap _case({
  required int n,
  required String occupation,
  required String city,
  required List<JsonMap> inputs,
  required Map<String, List<String>> titleNeedles,
}) {
  final caseId = 'full_chain_medium_${_three(n)}';
  final userId = 'eval_fc_medium_${_three(n)}';
  final tasks = <JsonMap>[];
  for (final input in inputs) {
    final suffix = input['suffix'] as String;
    final inputId = input['id'] as String;
    tasks.add({
      'task_id': '${caseId}_card_$suffix',
      'type': 'card_extraction',
      'expected': {
        'input_id': inputId,
        'status': 'completed',
        'title_contains': titleNeedles[suffix] ?? const <String>[],
        'must_not_fields': ['weather', 'price'],
      },
    });
  }
  tasks.add({
    'task_id': '${caseId}_cost',
    'type': 'cost_trace',
    'expected': {
      'max_total_tokens': 60000,
      'max_latency_ms': 120000,
      'max_tool_calls': 50,
      'require_all_tasks_completed': true,
      'must_include': ['Facts', 'Cards', 'tasks'],
    },
  });

  return {
    'case_id': caseId,
    'family': 'full_chain_replay',
    'language': 'zh-CN',
    'persona': {
      'user_id': userId,
      'profile': {
        'occupation': occupation,
        'city': city,
        'preferences': ['偏好中文输出', '喜欢明确提醒'],
      },
    },
    'ground_truth_world': {
      'facts': [
        {
          'id': 'fact_$caseId',
          'type': 'replay_expectation',
          'content': '该 persona 的输入应写入 Facts、生成 Cards、完成后台任务并产生 trace。',
        }
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

JsonMap _input(String suffix, String time, String content) => {
      'suffix': suffix,
      'id':
          'input_fc_${suffix}_${time.replaceAll(RegExp(r'[^0-9]'), '').substring(8, 12)}',
      'time': time,
      'content': content,
    };

String _three(int n) => n.toString().padLeft(3, '0');
