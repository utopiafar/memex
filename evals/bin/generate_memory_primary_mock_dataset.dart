import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main() async {
  final repoRoot = Directory.current.path;
  final caseCount = _intEnv('MEMEX_EVAL_GENERATED_CASES') ?? 8;
  final recordsPerCase = _intEnv('MEMEX_EVAL_GENERATED_RECORDS_PER_CASE') ?? 24;
  final superAgentAsksPerCase =
      _intEnv('MEMEX_EVAL_SUPER_AGENT_ASKS_PER_CASE') ?? 0;
  final outDir = Directory(
    Platform.environment['MEMEX_EVAL_GENERATED_DATASET_DIR'] ??
        p.join(repoRoot, 'evals', 'datasets', 'memory_primary_mock_scale'),
  );
  if (await outDir.exists()) {
    await outDir.delete(recursive: true);
  }
  await outDir.create(recursive: true);

  final cases = <JsonMap>[];
  for (var i = 0; i < caseCount; i++) {
    cases.add(_buildCase(
      i,
      recordsPerCase,
      superAgentAsksPerCase: superAgentAsksPerCase,
    ));
  }

  final caseFile = File(p.join(outDir.path, 'cases.jsonl'));
  final sink = caseFile.openWrite();
  for (final evalCase in cases) {
    sink.writeln(jsonEncode(evalCase));
  }
  await sink.close();

  final recordCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        ((evalCase['operations'] as List)
            .where((operation) => operation['type'] == 'record')
            .length),
  );
  final recallCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        ((evalCase['operations'] as List)
            .where((operation) => operation['type'] == 'memory_recall')
            .length),
  );
  final superAgentAskCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        ((evalCase['operations'] as List)
            .where((operation) => operation['type'] == 'super_agent_ask')
            .length),
  );
  await File(p.join(outDir.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'name': 'memory_primary_mock_scale',
      'description':
          'Synthetic full-chain Memory Primary dataset with cross-day records, corrections, no-op noise, recall probes, and PARA projection.',
      'evidence_level': 'audited_synthetic_fixture',
      'language': 'zh-CN',
      'case_count': cases.length,
      'record_count': recordCount,
      'memory_recall_operation_count': recallCount,
      'super_agent_ask_operation_count': superAgentAskCount,
      'records_per_case': recordsPerCase,
      'super_agent_asks_per_case': superAgentAsksPerCase,
      'generated_by': 'evals/bin/generate_memory_primary_mock_dataset.dart',
      'core_metrics': [
        'memory_expected_hit_rate',
        'memory_must_not_write_precision',
        'memory_recall_hit_rate',
        'super_agent_answer_hit_rate',
        'related_fact_hit_rate',
        'task_settlement_rate',
        'p95_record_elapsed_ms',
      ],
      'notes': [
        'Run first with MEMEX_EVAL_CASE_LIMIT for a small gate.',
        'Use real LLM and embedding credentials for capability evidence.',
        'No-LLM runs validate harness and report generation only.',
      ],
    }),
  );
  stdout.writeln(
    'Generated ${cases.length} cases, $recordCount records, $recallCount recall probes, $superAgentAskCount Super Agent asks at ${outDir.path}',
  );
}

JsonMap _buildCase(
  int index,
  int recordsPerCase, {
  required int superAgentAsksPerCase,
}) {
  final persona = _personas[index % _personas.length];
  final project = _projects[index % _projects.length];
  final oldOwner = _oldOwners[index % _oldOwners.length];
  final newOwner = _newOwners[index % _newOwners.length];
  final preference = _preferences[index % _preferences.length];
  final health = _healthFacts[index % _healthFacts.length];
  final city = _cities[index % _cities.length];
  final baseDate = DateTime(2026, 5, 1 + index, 9);

  final operations = <JsonMap>[];
  final memoryMustContain = <Object>[
    project,
    newOwner,
    preference.expectation,
    health.expectation,
    _cityExpectation(city),
  ];
  final memoryMustNotContain = <Object>[
    _anyOf('temporary frustration', ['今天只是临时烦躁', 'temporary frustration']),
    _anyOf('one-off latte', ['一次性拿铁', 'one-off latte']),
    _anyOf('window display', ['路过看到的橱窗', 'window display']),
  ];
  final cardMustContain = <Object>[project, newOwner];
  final relatedExpectations = <JsonMap>[];

  void addRecord(String id, int dayOffset, int hour, String content) {
    operations.add({
      'id': id,
      'type': 'record',
      'time': baseDate
          .add(Duration(days: dayOffset, hours: hour))
          .toIso8601String(),
      'content': content,
    });
  }

  addRecord(
    'rec_001',
    0,
    0,
    '$project 这周进入灰度准备，暂时我记的是 $oldOwner 负责验收口径，我负责把风险点整理成中文短报告。',
  );
  addRecord(
    'rec_002',
    0,
    2,
    '以后看技术或项目报告时，我更喜欢先给结论、风险和下一步，背景可以放后面。${preference.content}',
  );
  addRecord(
    'rec_003',
    1,
    1,
    '个人偏好补充：我常驻 $city，跨时区安排默认按当地时间理解。${health.content}',
  );
  addRecord(
    'rec_004',
    1,
    3,
    '会议纪要：$project 的导出链路还缺回滚演练、埋点检查和客服 FAQ，验收报告明天下午要给到小组。',
  );
  addRecord(
    'rec_005',
    2,
    0,
    '今天只是临时烦躁，午后喝了一杯一次性拿铁，路过看到的橱窗挺好看，这些不用长期记。',
  );
  addRecord(
    'rec_006',
    2,
    4,
    '以这条为准：$project 的导出灰度 owner 是 $newOwner，之前关于 $oldOwner 负责的说法都覆盖掉。',
  );
  relatedExpectations.add({
    'operation_id': 'rec_006',
    'expected_related_operation_ids': ['rec_001', 'rec_004'],
  });

  var nextId = 7;
  var day = 3;
  while (nextId <= recordsPerCase) {
    final cycle = (nextId - 7) ~/ 6;
    final slot = (nextId - 7) % 6;
    final id = 'rec_${nextId.toString().padLeft(3, '0')}';
    switch (slot) {
      case 0:
        addRecord(
          id,
          day,
          1,
          '$project 第 ${cycle + 2} 轮复盘里，我只想保留能影响后续决策的结论，不需要把寒暄和临时情绪写进长期记忆。',
        );
        break;
      case 1:
        addRecord(
          id,
          day,
          3,
          '记住一个长期偏好：给我做 $project 相关总结时，默认列出 owner、风险、下一步和证据来源。',
        );
        memoryMustContain.add(
          _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
        );
        cardMustContain.add(
          _anyOf('evidence source', ['证据来源', 'evidence source', 'evidence']),
        );
        break;
      case 2:
        addRecord(
          id,
          day,
          5,
          '临时状态：这周我在外地开会，只有这几天不方便晚上同步，别把它当成长期作息。',
        );
        break;
      case 3:
        addRecord(
          id,
          day,
          7,
          '$project 的客服 FAQ 需要增加“导出失败如何恢复”和“灰度期间如何回滚”的两段，$newOwner 会看最终版。',
        );
        relatedExpectations.add({
          'operation_id': id,
          'expected_related_operation_ids': ['rec_001', 'rec_004', 'rec_006'],
        });
        break;
      case 4:
        addRecord(
          id,
          day,
          9,
          '纠正一下：关于报告风格，不是越短越好，而是先结论和风险，必要证据要保留，尤其是 $project 的验收依据。',
        );
        memoryMustContain.add(
          _anyOf('necessary evidence', ['必要证据', 'necessary evidence']),
        );
        break;
      default:
        addRecord(
          id,
          day,
          11,
          '噪声样本：刚刚看到一个截图标题像 $project，但只是随手浏览，不要写成项目事实。',
        );
        day += 1;
    }
    nextId += 1;
  }

  operations.add({
    'id': 'recall_project_owner',
    'type': 'memory_recall',
    'time': baseDate.add(Duration(days: day + 1, hours: 1)).toIso8601String(),
    'query': '$project 当前导出灰度 owner 是谁？',
    'expected': {
      'must_contain': [project, newOwner],
      'must_not_contain': const [],
    },
  });
  operations.add({
    'id': 'recall_report_style',
    'type': 'memory_recall',
    'time': baseDate.add(Duration(days: day + 1, hours: 2)).toIso8601String(),
    'query': '我希望技术报告怎么写？',
    'expected': {
      'must_contain': [
        _anyOf('conclusion', ['结论', 'conclusion', 'conclusions']),
        _anyOf('risk', ['风险', 'risk', 'risks']),
        preference.expectation,
      ],
      'must_not_contain': const [],
    },
  });
  operations.add({
    'id': 'projection_001',
    'type': 'para_projection',
    'time': baseDate.add(Duration(days: day + 1, hours: 3)).toIso8601String(),
  });
  for (var i = 0; i < superAgentAsksPerCase; i++) {
    final asksProjectOwner = i.isEven;
    operations.add({
      'id': 'ask_${(i + 1).toString().padLeft(3, '0')}',
      'type': 'super_agent_ask',
      'time':
          baseDate.add(Duration(days: day + 1, hours: 4 + i)).toIso8601String(),
      'query': asksProjectOwner
          ? '$project 当前导出灰度 owner 是谁？请给出依据。'
          : '以后给我写 $project 相关技术报告时，格式偏好是什么？',
      'quick_query': true,
      'expected': {
        'must_contain': asksProjectOwner
            ? [project, newOwner]
            : [
                project,
                _anyOf('conclusion', ['结论', 'conclusion', 'conclusions']),
                _anyOf('risk', ['风险', 'risk', 'risks']),
                preference.expectation,
              ],
        'must_not_contain': asksProjectOwner
            ? [_staleCurrentOwnerAssertion(oldOwner)]
            : const [],
      },
    });
  }

  return {
    'case_id': 'memory_primary_scale_${(index + 1).toString().padLeft(3, '0')}',
    'persona': {
      'user_id': 'memory_scale_user_${index + 1}',
      'role': persona,
      'city': city,
    },
    'coverage': {
      'scenario_families': [
        'project_status',
        'preference',
        'correction',
        'noise_noop',
        'memory_recall',
        if (superAgentAsksPerCase > 0) 'super_agent_ask',
      ],
      'input_channels': ['text', 'meeting_note', 'browser_clip'],
      'journey_stages': [
        'capture',
        'memory_write',
        'recall',
        'projection',
        if (superAgentAsksPerCase > 0) 'ask',
      ],
    },
    'operations': operations,
    'expected': {
      'memory_must_contain': _dedupeExpectations(memoryMustContain),
      'memory_must_not_contain': _dedupeExpectations(memoryMustNotContain),
      'card_title_or_insight_should_contain': _dedupeExpectations(
        cardMustContain,
      ),
      'related_fact_expectations': relatedExpectations,
    },
  };
}

int? _intEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return null;
  return int.tryParse(value);
}

JsonMap _anyOf(String label, List<String> alternatives) {
  return {
    'label': label,
    'any_of': alternatives,
  };
}

JsonMap _staleCurrentOwnerAssertion(String oldOwner) {
  final owner = RegExp.escape(oldOwner);
  return {
    'label': 'stale current owner: $oldOwner',
    'regex': '(当前|current)[^\\n。；;]{0,30}(owner|负责人|负责|导出灰度)[^\\n。；;]{0,30}$owner|'
        '(owner|负责人|负责|导出灰度)[^\\n。；;]{0,20}(是|为|=)[^\\n。；;]{0,10}$owner|'
        '$owner[^\\n。；;]{0,12}(是|为|担任)[^\\n。；;]{0,20}(当前|current|owner|负责人|导出灰度)|'
        '$owner[^\\n。；;]{0,12}负责[^\\n。；;]{0,8}(导出灰度|owner|灰度|负责人)',
  };
}

List<Object> _dedupeExpectations(Iterable<Object> values) {
  final seen = <String>{};
  final result = <Object>[];
  for (final value in values) {
    final key = value is Map
        ? (value['label']?.toString() ?? jsonEncode(value))
        : value.toString();
    if (seen.add(key)) result.add(value);
  }
  return result;
}

JsonMap _cityExpectation(String city) {
  return _anyOf(city, [city, _cityEnglish[city] ?? city]);
}

const _personas = [
  '增长产品经理',
  'SRE 负责人',
  '临床运营负责人',
  '独立开发者',
  '公益项目协调人',
  '咖啡店主理人',
  '财务分析师',
  '用户研究员',
];

const _projects = [
  'Project Atlas',
  'Nimbus 迁移',
  '慢病随访看板',
  'SoloKit 发布',
  '社区物资协作',
  '烘焙订阅系统',
  '预算滚动预测',
  '访谈洞察库',
];

const _oldOwners = ['Jason', 'Lina', 'Dr. Chen', 'Wei', 'April', 'Noah'];

const _newOwners = ['Ming', 'Yuki', 'Qiao', 'Rui', 'Tara', 'Hao'];

const _cities = ['上海', '深圳', '杭州', '北京', '成都', '广州', '苏州', '南京'];

const _cityEnglish = {
  '上海': 'Shanghai',
  '深圳': 'Shenzhen',
  '杭州': 'Hangzhou',
  '北京': 'Beijing',
  '成都': 'Chengdu',
  '广州': 'Guangzhou',
  '苏州': 'Suzhou',
  '南京': 'Nanjing',
};

const _preferences = [
  _Fact(
    content: '如果有冲突，请优先告诉我最新结论。',
    mustContain: '最新结论',
    alternatives: [
      '最新结论',
      '最新的结论',
      '冲突',
      'latest conclusion',
      'latest conclusions'
    ],
  ),
  _Fact(
    content: '我不喜欢长篇铺垫，最好把风险前置。',
    mustContain: '风险前置',
    alternatives: [
      '风险前置',
      '风险必须前置',
      '风险和下一步行动优先',
      'risks first',
      'prioritize risks'
    ],
  ),
  _Fact(
    content: '需要行动项时，请按 owner 和截止时间拆开。',
    mustContain: '截止时间',
    alternatives: ['截止时间', 'deadline', 'due date'],
  ),
  _Fact(
    content: '涉及客户影响时，请单独列出影响面。',
    mustContain: '影响面',
    alternatives: ['影响面', 'impact scope', 'customer impact'],
  ),
];

const _healthFacts = [
  _Fact(
    content: '我对花生过敏，聚餐建议里要避开。',
    mustContain: '花生过敏',
    alternatives: ['花生过敏', '花生严重过敏', 'allergic to peanuts', 'peanut allergy'],
  ),
  _Fact(
    content: '我晚上九点后通常不安排高强度会议。',
    mustContain: '九点后',
    alternatives: ['九点后', 'after 9pm', 'after nine'],
  ),
  _Fact(
    content: '我偏好低咖啡因饮品，下午尽量别推荐浓咖啡。',
    mustContain: '低咖啡因',
    alternatives: ['低咖啡因', 'low caffeine', 'low-caffeine'],
  ),
  _Fact(
    content: '我周末一般留给家人，不默认安排工作同步。',
    mustContain: '周末',
    alternatives: ['周末', 'weekend', 'weekends'],
  ),
];

class _Fact {
  const _Fact({
    required this.content,
    required this.mustContain,
    required this.alternatives,
  });

  final String content;
  final String mustContain;
  final List<String> alternatives;

  JsonMap get expectation => _anyOf(mustContain, alternatives);
}
