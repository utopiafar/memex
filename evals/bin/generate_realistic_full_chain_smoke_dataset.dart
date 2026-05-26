import 'dart:convert';
import 'dart:io';

typedef JsonMap = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  final outDir = Directory(
    args.isNotEmpty ? args.first : 'evals/datasets/full_chain_realistic_smoke',
  );
  await outDir.create(recursive: true);

  final cases = [_productReleaseCase(), _familyCareCase()];
  final operationCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['operations'] as List).length,
  );
  final recordCount = cases.fold<int>(
    0,
    (sum, evalCase) =>
        sum +
        (evalCase['operations'] as List)
            .where(
              (operation) => operation is Map && operation['type'] == 'record',
            )
            .length,
  );
  final taskCount = cases.fold<int>(
    0,
    (sum, evalCase) => sum + (evalCase['eval_tasks'] as List).length,
  );

  final manifest = {
    'dataset_id': 'memex_full_chain_realistic_smoke',
    'version': 1,
    'description':
        '小样本真实 App 行为串行全链路 replay：跨天记录、回看、评论、日程刷新、洞察刷新、记忆等待和 Super Agent 问答。',
    'created_at': '2026-05-16',
    'language': 'zh-CN',
    'locale': 'zh-CN',
    'case_file': 'cases.jsonl',
    'case_count': cases.length,
    'persona_count': cases.length,
    'operation_count': operationCount,
    'record_operation_count': recordCount,
    'eval_task_count': taskCount,
    'families': ['full_chain_realistic_replay'],
    'evidence_goal': '先用少量样本跑通真实链路和日志闭环，再扩到更多 persona、输入和指标。',
    'feature_points': [
      'record_input',
      'timeline_card',
      'timeline_browse',
      'comment',
      'memory',
      'pkm',
      'schedule',
      'knowledge_insight',
      'super_agent',
      'cost_trace',
    ],
    'notes': [
      '每个 record 操作后等待 LocalTaskExecutor idle，模拟用户逐条记录后的后台处理。',
      'operation.time 传入 submitInput(createdAt)，用于测试跨天/跨周时间上下文。',
      'channel 字段保留真实来源形态：text、voice_transcript、ocr_clip。',
      '本数据集不追求一次性大规模；目标是让真实 replay、replay_file 评分、debug_log 和 report 全部闭环。',
    ],
  };

  await File('${outDir.path}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File(
    '${outDir.path}/cases.jsonl',
  ).writeAsString('${cases.map(jsonEncode).join('\n')}\n', flush: true);

  stdout.writeln(
    'Generated ${cases.length} realistic full-chain cases, '
    '$operationCount operations, $recordCount records at ${outDir.path}',
  );
}

JsonMap _productReleaseCase() {
  const caseId = 'realistic_chain_product_release';
  final operations = [
    _record(
      id: 'prd_r001',
      time: '2026-04-28T09:10:00+08:00',
      channel: 'text',
      content: '以后重要发布会提前一天提醒我，尤其是灰度和回滚相关的评审，别临近了才说。',
    ),
    _record(
      id: 'prd_r002',
      time: '2026-04-29T18:35:00+08:00',
      channel: 'voice_transcript',
      content: '语音记一下，下周二上午十点和 Mina 看导出灰度风险，记得带最近三天的失败率截图。',
    ),
    _record(
      id: 'prd_r003',
      time: '2026-05-01T21:20:00+08:00',
      channel: 'ocr_clip',
      content: '小票 OCR：芝士蛋糕、拿铁、排队 28 分钟。只是今天嘴馋，不要写成长期饮食偏好。',
    ),
    _record(
      id: 'prd_r004',
      time: '2026-05-04T08:45:00+08:00',
      channel: 'text',
      content: '之前说完全不喝咖啡要改一下，最近上午可以喝一杯，下午还是别喝。',
    ),
    _record(
      id: 'prd_r005',
      time: '2026-05-06T16:30:00+08:00',
      channel: 'voice_transcript',
      content: '客服反馈里“找不到导出入口”归到可发现性问题，别和权限错误混在一起。',
    ),
    _record(
      id: 'prd_r006',
      time: '2026-05-10T20:40:00+08:00',
      channel: 'text',
      content: '发布复盘模板要保留背景、决策、风险、owner、下一步，不要只写结论。',
    ),
    {
      'id': 'prd_fetch_001',
      'type': 'fetch_timeline',
      'time': '2026-05-11T09:00:00+08:00',
      'date_from': '2026-04-28T00:00:00+08:00',
      'date_to': '2026-05-11T23:59:59+08:00',
      'limit': 20,
    },
    {
      'id': 'prd_comment_001',
      'type': 'post_comment',
      'time': '2026-05-11T09:10:00+08:00',
      'target_operation_id': 'prd_r006',
      'content': '补充：复盘里风险要和 owner 对齐，下一步要有日期。',
    },
    {
      'id': 'prd_schedule_001',
      'type': 'refresh_schedule_aggregation',
      'time': '2026-05-11T09:20:00+08:00',
    },
    {
      'id': 'prd_insight_001',
      'type': 'refresh_knowledge_insights',
      'time': '2026-05-11T09:40:00+08:00',
    },
    {
      'id': 'prd_wait_memory_001',
      'type': 'wait_memory',
      'time': '2026-05-11T10:00:00+08:00',
      'timeout_seconds': 180,
      'must_include_any': ['发布会', '咖啡'],
    },
    {
      'id': 'prd_ask_001',
      'type': 'ask_super_agent',
      'time': '2026-05-11T10:10:00+08:00',
      'query': '我上午能喝咖啡吗？重要发布评审要怎么提醒我？',
      'quick_query': true,
    },
  ];

  return {
    'case_id': caseId,
    'family': 'full_chain_realistic_replay',
    'language': 'zh-CN',
    'persona': {
      'user_id': 'eval_realistic_product_001',
      'profile': {
        'occupation': '增长产品经理',
        'city': '上海',
        'preferences': ['结论先行', '重要事项要提前提醒', '不把临时情绪长期化'],
      },
    },
    'ground_truth_world': {
      'facts': [
        {'id': 'prd_r001', 'content': '重要发布/评审提前一天提醒。'},
        {'id': 'prd_r004', 'content': '最新咖啡偏好：上午可以一杯，下午不喝。'},
        {'id': 'prd_r006', 'content': '发布复盘模板包含背景、决策、风险、owner、下一步。'},
      ],
    },
    'operations': operations,
    'eval_tasks': [
      _costTask(
        caseId: caseId,
        minRecordOperations: 6,
        minJourneySpanDays: 12,
        expectedOperationTypes: const [
          'record',
          'fetch_timeline',
          'post_comment',
          'refresh_schedule_aggregation',
          'refresh_knowledge_insights',
          'wait_memory',
          'ask_super_agent',
        ],
        expectedFeatureTriggers: const [
          'record_input',
          'timeline_card',
          'timeline_browse',
          'comment',
          'memory',
          'pkm',
          'schedule',
          'knowledge_insight',
          'super_agent',
        ],
      ),
      {
        'task_id': '${caseId}_memory',
        'type': 'memory_write',
        'expected': {
          'must_write': [
            {
              'id': 'release_reminder',
              'must_include': ['发布', '提前一天'],
            },
            {
              'id': 'coffee_latest',
              'must_include': ['上午', '咖啡'],
            },
          ],
          'must_not_write': [
            {
              'id': 'temporary_dessert',
              'must_include': ['芝士蛋糕'],
            },
          ],
          'conflicts': [
            {
              'latest_should_include': ['上午', '咖啡'],
              'superseded_should_not_be_active': ['完全不喝咖啡'],
            },
          ],
          'evaluate_write_precision': false,
        },
      },
      {
        'task_id': '${caseId}_super_agent',
        'type': 'super_agent_qa',
        'query': '我上午能喝咖啡吗？重要发布评审要怎么提醒我？',
        'expected': {
          'operation_id': 'prd_ask_001',
          'must_include': ['上午', '咖啡', '提前'],
          'must_not_include': ['完全不喝咖啡'],
          'allowed_uncertainty': false,
          'read_only': true,
          'prohibited_tool_calls': ['update_memory', 'delete_memory', 'save'],
        },
      },
    ],
  };
}

JsonMap _familyCareCase() {
  const caseId = 'realistic_chain_family_care';
  final operations = [
    _record(
      id: 'care_r001',
      time: '2026-04-20T07:50:00+08:00',
      channel: 'text',
      content: '妈妈的晚间用药先按晚上 8 点提醒，先记着，后面如果医生改时间再更新。',
    ),
    _record(
      id: 'care_r002',
      time: '2026-04-22T19:10:00+08:00',
      channel: 'voice_transcript',
      content: '周五下午带爸去复诊，记得带上三月体检报告和医保卡，别只提醒我出门。',
    ),
    _record(
      id: 'care_r003',
      time: '2026-04-24T22:05:00+08:00',
      channel: 'text',
      content: '我这两天胃有点不舒服，晚饭想清淡一点，这只是短期状态，不要当成长期饮食偏好。',
    ),
    _record(
      id: 'care_r004',
      time: '2026-04-29T11:15:00+08:00',
      channel: 'ocr_clip',
      content: '体检报告 OCR：LDL-C 3.6，医生让下次复诊带最近两周血压记录。',
    ),
    _record(
      id: 'care_r005',
      time: '2026-05-02T15:45:00+08:00',
      channel: 'text',
      content: '妈妈对青霉素过敏，这个是长期重要信息，涉及用药时一定提醒我。',
    ),
    _record(
      id: 'care_r006',
      time: '2026-05-07T20:30:00+08:00',
      channel: 'voice_transcript',
      content: '医生今天说妈妈晚间用药改到晚上 9 点半，之前 8 点那个提醒要覆盖掉。',
    ),
    _record(
      id: 'care_r007',
      time: '2026-05-12T10:20:00+08:00',
      channel: 'text',
      content: '周末去药房拿降压药，顺便问下血压计袖带有没有小号。',
    ),
    {
      'id': 'care_fetch_001',
      'type': 'fetch_timeline',
      'time': '2026-05-12T11:00:00+08:00',
      'date_from': '2026-04-20T00:00:00+08:00',
      'date_to': '2026-05-12T23:59:59+08:00',
      'limit': 20,
    },
    {
      'id': 'care_schedule_001',
      'type': 'refresh_schedule_aggregation',
      'time': '2026-05-12T11:10:00+08:00',
    },
    {
      'id': 'care_insight_001',
      'type': 'refresh_knowledge_insights',
      'time': '2026-05-12T11:30:00+08:00',
    },
    {
      'id': 'care_wait_memory_001',
      'type': 'wait_memory',
      'time': '2026-05-12T12:00:00+08:00',
      'timeout_seconds': 180,
      'must_include_any': ['青霉素', '9 点半'],
    },
    {
      'id': 'care_ask_001',
      'type': 'ask_super_agent',
      'time': '2026-05-12T12:10:00+08:00',
      'query': '妈妈晚间用药现在应该几点提醒？她有什么用药过敏要注意？',
      'quick_query': true,
    },
  ];

  return {
    'case_id': caseId,
    'family': 'full_chain_realistic_replay',
    'language': 'zh-CN',
    'persona': {
      'user_id': 'eval_realistic_care_001',
      'profile': {
        'occupation': '家庭照护者',
        'city': '杭州',
        'preferences': ['照护事项要明确时间', '医疗信息要有边界', '临时身体状态不要长期化'],
      },
    },
    'ground_truth_world': {
      'facts': [
        {'id': 'care_r005', 'content': '妈妈对青霉素过敏。'},
        {'id': 'care_r006', 'content': '妈妈晚间用药最新提醒时间为晚上 9 点半。'},
      ],
    },
    'operations': operations,
    'eval_tasks': [
      _costTask(
        caseId: caseId,
        minRecordOperations: 7,
        minJourneySpanDays: 21,
        expectedOperationTypes: const [
          'record',
          'fetch_timeline',
          'refresh_schedule_aggregation',
          'refresh_knowledge_insights',
          'wait_memory',
          'ask_super_agent',
        ],
        expectedFeatureTriggers: const [
          'record_input',
          'timeline_card',
          'timeline_browse',
          'memory',
          'pkm',
          'schedule',
          'knowledge_insight',
          'super_agent',
        ],
      ),
      {
        'task_id': '${caseId}_memory',
        'type': 'memory_write',
        'expected': {
          'must_write': [
            {
              'id': 'penicillin_allergy',
              'must_include': ['青霉素', '过敏'],
            },
            {
              'id': 'medicine_time_latest',
              'must_include': ['9 点半'],
            },
          ],
          'must_not_write': [
            {
              'id': 'temporary_stomach',
              'must_include': ['胃有点不舒服'],
            },
          ],
          'conflicts': [
            {
              'latest_should_include': ['9 点半'],
              'superseded_should_not_be_active': ['晚上 8 点'],
            },
          ],
          'evaluate_write_precision': false,
        },
      },
      {
        'task_id': '${caseId}_super_agent',
        'type': 'super_agent_qa',
        'query': '妈妈晚间用药现在应该几点提醒？她有什么用药过敏要注意？',
        'expected': {
          'operation_id': 'care_ask_001',
          'must_include': ['9 点半', '青霉素', '过敏'],
          'must_not_include': ['晚上 8 点'],
          'allowed_uncertainty': false,
          'read_only': true,
          'prohibited_tool_calls': ['update_memory', 'delete_memory', 'save'],
        },
      },
    ],
  };
}

JsonMap _record({
  required String id,
  required String time,
  required String channel,
  required String content,
}) => {
  'id': id,
  'type': 'record',
  'time': time,
  'channel': channel,
  'content': content,
};

JsonMap _costTask({
  required String caseId,
  required int minRecordOperations,
  required int minJourneySpanDays,
  required List<String> expectedOperationTypes,
  required List<String> expectedFeatureTriggers,
}) => {
  'task_id': '${caseId}_cost',
  'type': 'cost_trace',
  'expected': {
    'max_total_tokens': 2000000,
    'max_tokens_per_input': 250000,
    'max_latency_ms': 7200000,
    'max_tool_calls': 2500,
    'max_retry_rate': 0,
    'max_failed_task_rate': 0,
    'require_all_tasks_completed': true,
    'min_record_operations': minRecordOperations,
    'min_journey_span_days': minJourneySpanDays,
    'expected_operation_types': expectedOperationTypes,
    'expected_input_channels': ['text', 'voice_transcript', 'ocr_clip'],
    'expected_feature_triggers': expectedFeatureTriggers,
    'expected_trace_events': [
      'card_agent_task',
      'pkm_agent_task',
      'schedule_refresh_router_task',
    ],
    'must_include': ['Facts', 'Cards', 'Super Agent'],
  },
};
