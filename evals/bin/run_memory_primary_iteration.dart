import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _smallDataset = 'evals/datasets/pr256_full_metric_small/cases.jsonl';
const _scaleDataset =
    'evals/datasets/pr256_full_metric_large_p12_r600_q50/cases.jsonl';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    _printUsage();
    return;
  }

  final action = args.first;
  final rest = args.skip(1).toList(growable: false);
  final code = switch (action) {
    'doctor' => await _doctor(),
    'generate-small' => await _generateSmall(),
    'generate-scale' => await _generateScale(),
    'plan-scale' => await _planScale(rest),
    'preflight' => await _preflight(),
    'small' => await _smallGate(),
    'scale-shard' => await _scaleShard(),
    'merge' => await _merge(rest),
    'audit' => await _audit(rest),
    'audit-dataset' => await _auditDataset(rest),
    'audit-shards' => await _auditShards(rest),
    'badcases' => await _badcases(rest),
    'report' => await _report(rest),
    'status' => await _status(rest),
    'watch-status' => await _watchStatus(rest),
    'judge' => await _judge(rest),
    _ => _unknownAction(action),
  };
  if (code != 0) exitCode = code;
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run evals/bin/run_memory_primary_iteration.dart <action>

Actions:
  doctor          Print redacted eval environment readiness.
  generate-small  Regenerate the tracked 3 persona / 48 record / 6 ask fixture.
  generate-scale  Generate the ignored 12 persona / 600 record / 50 ask dataset.
  plan-scale      Write a 12-user scale shard manifest and command plan.
  preflight       Run real-provider LLM preflight only.
  small           Run the real small gate replay.
  scale-shard     Run one real scale shard; set MEMEX_EVAL_CASE_OFFSET/LIMIT.
  merge           Merge completed shard run dirs; pass dirs or MEMEX_EVAL_MERGE_RUN_DIRS.
  audit           Audit a run dir for required artifacts, metrics, logs, and redaction.
  audit-dataset   Audit PR256 dataset shape, query interleaving, and diversity.
  audit-shards    Audit scale shard manifest completion and case coverage.
  badcases        Render badcases.md/jsonl from failures, observations, and dataset.
  report          Render a Chinese iteration report from a run dir.
  status          Summarize progress/metrics/gate/judge/audit for run dirs.
  watch-status    Poll shard audit/status at a fixed interval for long scale runs.
  judge           Run judge over a run dir; pass run dir as arg or MEMEX_EVAL_RUN_DIR.

Secrets:
  Export provider keys in the shell before running this script. The script does
  not accept API keys as arguments and does not write them to files.
''');
}

int _unknownAction(String action) {
  stderr.writeln('Unknown action: $action');
  _printUsage();
  return 64;
}

Future<int> _doctor() async {
  stdout.writeln('Memory Primary eval environment');
  _printEnvStatus('MiMo agent chain', [
    'MEMEX_EVAL_LLM_BASE_URLS',
    'MEMEX_EVAL_LLM_API_KEYS',
    'MEMEX_EVAL_LLM_BASE_URL',
    'MEMEX_EVAL_LLM_API_KEY',
  ]);
  _printEnvStatus('MiMo judge', [
    'MEMEX_EVAL_JUDGE_BASE_URLS',
    'MEMEX_EVAL_JUDGE_API_KEYS',
    'MEMEX_EVAL_JUDGE_BASE_URL',
    'MEMEX_EVAL_JUDGE_API_KEY',
  ]);
  _printEnvStatus('OpenRouter embedding', [
    'MEMEX_EVAL_EMBEDDING_API_KEY',
    'OPENROUTER_API_KEY',
    'MEMEX_EVAL_EMBEDDING_BASE_URL',
    'MEMEX_EVAL_EMBEDDING_MODEL',
  ]);
  stdout.writeln(
      'small_dataset=${File(_smallDataset).existsSync() ? 'present' : 'missing'}');
  stdout.writeln(
      'scale_dataset=${File(_scaleDataset).existsSync() ? 'present' : 'missing'}');
  return 0;
}

Future<int> _generateSmall() {
  return _run([
    'dart',
    'run',
    'evals/bin/generate_pr256_full_metric_dataset.dart',
  ], extraEnv: {
    'MEMEX_EVAL_PERSONA_COUNT': '3',
    'MEMEX_EVAL_RECORDS_PER_PERSONA': '48',
    'MEMEX_EVAL_AGENT_QUERIES_PER_PERSONA': '6',
    'MEMEX_EVAL_GENERATED_DATASET_DIR':
        'evals/datasets/pr256_full_metric_small',
  });
}

Future<int> _generateScale() {
  return _run([
    'dart',
    'run',
    'evals/bin/generate_pr256_full_metric_dataset.dart',
  ], extraEnv: {
    'MEMEX_EVAL_PERSONA_COUNT': '12',
    'MEMEX_EVAL_RECORDS_PER_PERSONA': '600',
    'MEMEX_EVAL_AGENT_QUERIES_PER_PERSONA': '50',
    'MEMEX_EVAL_GENERATED_DATASET_DIR':
        'evals/datasets/pr256_full_metric_large_p12_r600_q50',
  });
}

Future<int> _planScale(List<String> args) {
  final dataset = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_SCALE_DATASET'] ?? _scaleDataset;
  return _run([
    'dart',
    'run',
    'evals/bin/plan_memory_primary_scale_shards.dart',
    dataset,
  ]);
}

Future<int> _preflight() async {
  final missing = _missingReplaySecrets();
  if (missing.isNotEmpty) return _missingEnvFailure(missing);

  return _runFlutterReplay(extraEnv: {
    ..._realReplayDefaults(),
    'MEMEX_EVAL_LLM_PREFLIGHT_ONLY': '1',
    'MEMEX_EVAL_RUN_DIR': _envOrDefault(
      'MEMEX_EVAL_RUN_DIR',
      'evals/runs/pr256_next_preflight_${_timestamp()}',
    ),
  });
}

Future<int> _smallGate() async {
  final missing = _missingReplaySecrets();
  if (missing.isNotEmpty) return _missingEnvFailure(missing);
  if (!File(_smallDataset).existsSync()) {
    stderr.writeln('Small dataset is missing. Run generate-small first.');
    return 66;
  }

  return _runFlutterReplay(extraEnv: {
    ..._realReplayDefaults(),
    'MEMEX_EVAL_DATASET': _envOrDefault('MEMEX_EVAL_DATASET', _smallDataset),
    'MEMEX_EVAL_RUN_DIR': _envOrDefault(
      'MEMEX_EVAL_RUN_DIR',
      'evals/runs/pr256_next_small_real_${_timestamp()}',
    ),
    'MEMEX_EVAL_GATE_PROFILE':
        _envOrDefault('MEMEX_EVAL_GATE_PROFILE', 'pr256_full'),
    'MEMEX_EVAL_SUITE_TIMEOUT_SECONDS':
        _envOrDefault('MEMEX_EVAL_SUITE_TIMEOUT_SECONDS', '21600'),
  });
}

Future<int> _scaleShard() async {
  final missing = _missingReplaySecrets();
  if (missing.isNotEmpty) return _missingEnvFailure(missing);
  final dataset = _envOrDefault('MEMEX_EVAL_DATASET', _scaleDataset);
  if (!File(dataset).existsSync()) {
    stderr.writeln('Scale dataset is missing: $dataset');
    stderr.writeln('Run generate-scale first.');
    return 66;
  }
  final offset = Platform.environment['MEMEX_EVAL_CASE_OFFSET'];
  final limit = Platform.environment['MEMEX_EVAL_CASE_LIMIT'];
  if ((offset == null || offset.isEmpty || limit == null || limit.isEmpty) &&
      Platform.environment['MEMEX_EVAL_ALLOW_FULL_SCALE'] != '1') {
    stderr.writeln(
      'Set MEMEX_EVAL_CASE_OFFSET and MEMEX_EVAL_CASE_LIMIT for scale-shard, '
      'or set MEMEX_EVAL_ALLOW_FULL_SCALE=1 intentionally.',
    );
    return 64;
  }

  return _runFlutterReplay(extraEnv: {
    ..._realReplayDefaults(),
    'MEMEX_EVAL_DATASET': dataset,
    'MEMEX_EVAL_RUN_DIR': _envOrDefault(
      'MEMEX_EVAL_RUN_DIR',
      'evals/runs/pr256_next_scale_p12_r600_q50_offset_${offset ?? 'all'}_${_timestamp()}',
    ),
    'MEMEX_EVAL_ABORT_CASE_AFTER_CONSECUTIVE_UNSETTLED_RECORDS': _envOrDefault(
      'MEMEX_EVAL_ABORT_CASE_AFTER_CONSECUTIVE_UNSETTLED_RECORDS',
      '3',
    ),
    'MEMEX_EVAL_GATE_PROFILE':
        _envOrDefault('MEMEX_EVAL_GATE_PROFILE', 'pr256_full'),
    'MEMEX_EVAL_SUITE_TIMEOUT_SECONDS':
        _envOrDefault('MEMEX_EVAL_SUITE_TIMEOUT_SECONDS', '86400'),
  });
}

Future<int> _judge(List<String> args) async {
  final missing = _missingJudgeSecrets();
  if (missing.isNotEmpty) return _missingEnvFailure(missing);
  final runDir =
      args.isNotEmpty ? args.first : Platform.environment['MEMEX_EVAL_RUN_DIR'];
  final extra = <String, String>{
    ..._judgeDefaults(),
  };
  if (runDir != null && runDir.trim().isNotEmpty) {
    extra['MEMEX_EVAL_JUDGE_TASKS'] = _envOrDefault(
      'MEMEX_EVAL_JUDGE_TASKS',
      '$runDir/judge_tasks.jsonl',
    );
    extra['MEMEX_EVAL_JUDGE_OUT_DIR'] = _envOrDefault(
      'MEMEX_EVAL_JUDGE_OUT_DIR',
      '$runDir/judge',
    );
  } else if (!_isSet('MEMEX_EVAL_JUDGE_TASKS')) {
    stderr.writeln('Pass a run dir or set MEMEX_EVAL_JUDGE_TASKS.');
    return 64;
  }

  return _run([
    'dart',
    'run',
    'evals/bin/run_pr256_judge.dart',
  ], extraEnv: extra);
}

Future<int> _merge(List<String> args) {
  return _run([
    'dart',
    'run',
    'evals/bin/merge_memory_primary_eval_runs.dart',
    ...args,
  ]);
}

Future<int> _audit(List<String> args) {
  return _run([
    'dart',
    'run',
    'evals/bin/audit_memory_primary_iteration_artifacts.dart',
    ...args,
  ]);
}

Future<int> _auditDataset(List<String> args) {
  final requested = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_DATASET'] ?? _smallDataset;
  final dataset = _resolveDatasetFilePath(requested);
  final scriptArgs = <String>[dataset];
  return _run([
    'dart',
    'run',
    'evals/bin/audit_pr256_full_metric_dataset.dart',
    ...scriptArgs,
  ]);
}

Future<int> _auditShards(List<String> args) {
  final manifest = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_SCALE_SHARD_MANIFEST'];
  if (manifest == null || manifest.trim().isEmpty) {
    stderr.writeln('Pass a scale_shard_manifest.json path.');
    return Future.value(64);
  }
  return _run([
    'dart',
    'run',
    'evals/bin/audit_memory_primary_scale_shards.dart',
    manifest,
  ]);
}

Future<int> _badcases(List<String> args) {
  final runDir = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_BADCASE_RUN_DIR'] ??
          Platform.environment['MEMEX_EVAL_RUN_DIR'];
  if (runDir == null || runDir.trim().isEmpty) {
    stderr.writeln('Pass a run dir or set MEMEX_EVAL_BADCASE_RUN_DIR.');
    return Future.value(64);
  }
  return _run([
    'dart',
    'run',
    'evals/bin/render_memory_primary_badcases.dart',
    runDir,
  ]);
}

Future<int> _report(List<String> args) {
  final runDir = args.isNotEmpty
      ? args.first
      : Platform.environment['MEMEX_EVAL_REPORT_RUN_DIR'] ??
          Platform.environment['MEMEX_EVAL_RUN_DIR'];
  if (runDir == null || runDir.trim().isEmpty) {
    stderr.writeln('Pass a run dir or set MEMEX_EVAL_REPORT_RUN_DIR.');
    return Future.value(64);
  }
  final scriptArgs = <String>[runDir];
  if (args.length > 1) scriptArgs.add(args[1]);
  return _run([
    'dart',
    'run',
    'evals/bin/render_memory_primary_iteration_report.dart',
    ...scriptArgs,
  ]);
}

Future<int> _status(List<String> args) {
  final runDirs = args.isNotEmpty
      ? args
      : [
          if (Platform.environment['MEMEX_EVAL_RUN_DIR'] != null)
            Platform.environment['MEMEX_EVAL_RUN_DIR']!,
        ];
  if (runDirs.isEmpty) {
    stderr.writeln('Pass a run dir or set MEMEX_EVAL_RUN_DIR.');
    return Future.value(64);
  }
  return _run([
    'dart',
    'run',
    'evals/bin/summarize_memory_primary_run_status.dart',
    ...runDirs,
  ]);
}

Future<int> _watchStatus(List<String> args) async {
  var manifest = Platform.environment['MEMEX_EVAL_SCALE_SHARD_MANIFEST'];
  var runDirs = <String>[];

  if (args.length == 1 && _looksLikeManifestPath(args.first)) {
    manifest = args.first;
  } else if (args.isNotEmpty) {
    runDirs = args;
  }

  if ((manifest == null || manifest.trim().isEmpty) &&
      Platform.environment['MEMEX_EVAL_STATUS_RUN_DIRS'] != null) {
    runDirs = Platform.environment['MEMEX_EVAL_STATUS_RUN_DIRS']!
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (runDirs.isEmpty && _isSet('MEMEX_EVAL_RUN_DIR')) {
    runDirs = [Platform.environment['MEMEX_EVAL_RUN_DIR']!];
  }
  if (manifest != null && manifest.trim().isNotEmpty) {
    runDirs = await _runDirsFromManifest(manifest) ?? runDirs;
  }

  if ((manifest == null || manifest.trim().isEmpty) && runDirs.isEmpty) {
    stderr.writeln(
      'Pass run dirs, pass scale_shard_manifest.json, or set '
      'MEMEX_EVAL_SCALE_SHARD_MANIFEST / MEMEX_EVAL_STATUS_RUN_DIRS.',
    );
    return 64;
  }

  final intervalSeconds = _positiveIntEnv(
        'MEMEX_EVAL_STATUS_INTERVAL_SECONDS',
      ) ??
      300;
  final maxTicks = int.tryParse(
        Platform.environment['MEMEX_EVAL_STATUS_MAX_TICKS'] ?? '',
      ) ??
      0;

  var tick = 0;
  var lastCode = 0;
  while (maxTicks == 0 || tick < maxTicks) {
    tick += 1;
    stdout.writeln('');
    stdout.writeln('=== Memory Primary eval status tick $tick '
        '@ ${DateTime.now().toUtc().toIso8601String()} ===');

    if (manifest != null && manifest.trim().isNotEmpty) {
      final code = await _run([
        'dart',
        'run',
        'evals/bin/audit_memory_primary_scale_shards.dart',
        manifest,
      ], extraEnv: {
        'MEMEX_EVAL_SHARD_AUDIT_ALLOW_INCOMPLETE': _envOrDefault(
          'MEMEX_EVAL_SHARD_AUDIT_ALLOW_INCOMPLETE',
          '1',
        ),
      });
      if (code != 0) lastCode = code;
    }

    if (runDirs.isNotEmpty) {
      final code = await _status(runDirs);
      if (code != 0) lastCode = code;
    }

    if (maxTicks != 0 && tick >= maxTicks) break;
    stdout.writeln(
      'Next status tick in ${intervalSeconds}s. Press Ctrl+C to stop.',
    );
    await Future<void>.delayed(Duration(seconds: intervalSeconds));
  }
  return lastCode;
}

Future<int> _runFlutterReplay({required Map<String, String> extraEnv}) {
  return _run([
    'flutter',
    'test',
    '--no-pub',
    'evals/replay/memory_primary_full_chain_replay_test.dart',
  ], extraEnv: extraEnv);
}

Map<String, String> _realReplayDefaults() {
  return {
    ..._defaults({
      'MEMEX_EVAL_LLM_TYPE': 'mimo',
      'MEMEX_EVAL_LLM_MODEL': 'mimo-v2.5',
      'MEMEX_EVAL_EMBEDDING_BASE_URL': 'https://openrouter.ai/api/v1',
      'MEMEX_EVAL_EMBEDDING_MODEL': 'qwen/qwen3-embedding-8b',
      'MEMEX_EVAL_EMBEDDING_ENABLED': '1',
      'MEMEX_EVAL_TASK_TIMEOUT_SECONDS': '240',
      'MEMEX_EVAL_ASK_TIMEOUT_SECONDS': '240',
    }),
    'MEMEX_EVAL_ENABLE_LLM': '1',
  };
}

Map<String, String> _judgeDefaults() {
  return {
    ..._defaults({
      'MEMEX_EVAL_JUDGE_MODEL': 'mimo-v2.5-pro',
      'MEMEX_EVAL_JUDGE_MAX_TOKENS': '4096',
      'MEMEX_EVAL_JUDGE_PROVIDER_COOLDOWN_MS': '5000',
      'MEMEX_EVAL_JUDGE_PROVIDER_MIN_INTERVAL_MS': '2500',
      'MEMEX_EVAL_JUDGE_REQUEST_TIMEOUT_SECONDS': '120',
      'MEMEX_EVAL_JUDGE_RETRY_FAILED': '1',
      'MEMEX_EVAL_JUDGE_RESUME': '1',
    }),
  };
}

List<String> _missingReplaySecrets() {
  final missing = <String>[];
  if (!_hasAnyPair(
    pluralBase: 'MEMEX_EVAL_LLM_BASE_URLS',
    pluralKey: 'MEMEX_EVAL_LLM_API_KEYS',
    singleBase: 'MEMEX_EVAL_LLM_BASE_URL',
    singleKey: 'MEMEX_EVAL_LLM_API_KEY',
  )) {
    missing.add('MEMEX_EVAL_LLM_BASE_URL(S) + MEMEX_EVAL_LLM_API_KEY(S)');
  }
  if (!_isSet('MEMEX_EVAL_EMBEDDING_API_KEY') &&
      !_isSet('OPENROUTER_API_KEY')) {
    missing.add('MEMEX_EVAL_EMBEDDING_API_KEY or OPENROUTER_API_KEY');
  }
  return missing;
}

List<String> _missingJudgeSecrets() {
  if (_hasAnyPair(
    pluralBase: 'MEMEX_EVAL_JUDGE_BASE_URLS',
    pluralKey: 'MEMEX_EVAL_JUDGE_API_KEYS',
    singleBase: 'MEMEX_EVAL_JUDGE_BASE_URL',
    singleKey: 'MEMEX_EVAL_JUDGE_API_KEY',
  )) {
    return const [];
  }
  return const [
    'MEMEX_EVAL_JUDGE_BASE_URL(S) + MEMEX_EVAL_JUDGE_API_KEY(S)',
  ];
}

int _missingEnvFailure(List<String> missing) {
  stderr.writeln('Missing required eval environment:');
  for (final item in missing) {
    stderr.writeln('- $item');
  }
  stderr.writeln(
      'Run `dart run evals/bin/run_memory_primary_iteration.dart doctor` for status.');
  return 78;
}

bool _hasAnyPair({
  required String pluralBase,
  required String pluralKey,
  required String singleBase,
  required String singleKey,
}) {
  return (_isSet(pluralBase) && _isSet(pluralKey)) ||
      (_isSet(singleBase) && _isSet(singleKey));
}

Map<String, String> _defaults(Map<String, String> values) {
  return {
    for (final entry in values.entries)
      if (!_isSet(entry.key)) entry.key: entry.value,
  };
}

String _envOrDefault(String key, String fallback) {
  final value = Platform.environment[key];
  return value == null || value.trim().isEmpty ? fallback : value;
}

bool _isSet(String key) {
  final value = Platform.environment[key];
  return value != null && value.trim().isNotEmpty;
}

int? _positiveIntEnv(String key) {
  final value = int.tryParse(Platform.environment[key] ?? '');
  if (value == null || value <= 0) return null;
  return value;
}

bool _looksLikeManifestPath(String value) {
  final lower = value.toLowerCase();
  return lower.endsWith('.json') || lower.contains('scale_shard_manifest');
}

String _resolveDatasetFilePath(String path) {
  if (Directory(path).existsSync()) return p.join(path, 'cases.jsonl');
  return path;
}

Future<List<String>?> _runDirsFromManifest(String manifestPath) async {
  final file = File(manifestPath);
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    final shards = decoded['shards'];
    if (shards is! List) return null;
    return shards
        .whereType<Map>()
        .map((item) => item['run_dir']?.toString() ?? '')
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  } catch (error) {
    stderr.writeln('Could not parse shard manifest: $manifestPath ($error)');
    return null;
  }
}

Future<int> _run(
  List<String> command, {
  Map<String, String> extraEnv = const {},
}) async {
  final env = Map<String, String>.from(Platform.environment)
    ..remove('ws_proxy')
    ..remove('wss_proxy')
    ..remove('WS_PROXY')
    ..remove('WSS_PROXY')
    ..['NO_PROXY'] = 'localhost,127.0.0.1,::1'
    ..['no_proxy'] = 'localhost,127.0.0.1,::1'
    ..addAll(extraEnv);

  stdout.writeln('> ${command.map(_quoteForLog).join(' ')}');
  final process = await Process.start(
    command.first,
    command.sublist(1),
    workingDirectory: Directory.current.path,
    environment: env,
    includeParentEnvironment: false,
  );
  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  return process.exitCode;
}

void _printEnvStatus(String label, List<String> keys) {
  stdout.writeln(label);
  for (final key in keys) {
    stdout.writeln('  $key=${_isSet(key) ? 'set' : 'unset'}');
  }
}

String _timestamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String _quoteForLog(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}
