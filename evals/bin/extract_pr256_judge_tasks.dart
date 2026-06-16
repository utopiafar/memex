import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef JsonMap = Map<String, dynamic>;

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run evals/bin/extract_pr256_judge_tasks.dart '
      '<metrics.json> [output.jsonl] [mode]',
    );
    exitCode = 64;
    return;
  }

  final metricsFile = File(args[0]);
  if (!await metricsFile.exists()) {
    throw StateError('Metrics file does not exist: ${metricsFile.path}');
  }

  final outputFile = File(
    args.length >= 2
        ? args[1]
        : p.join(p.dirname(metricsFile.path), 'judge_tasks.jsonl'),
  );
  final modeFilter = args.length >= 3 ? args[2] : null;

  final doc = jsonDecode(await metricsFile.readAsString()) as JsonMap;
  final metricsByMode = (doc['metrics_by_mode'] as Map).cast<String, dynamic>();
  final tasks = <JsonMap>[];
  for (final entry in metricsByMode.entries) {
    if (modeFilter != null && entry.key != modeFilter) continue;
    final modeMetrics = entry.value as JsonMap;
    for (final task in _list(modeMetrics['judge_tasks'])) {
      tasks.add((task as Map).cast<String, dynamic>());
    }
  }

  await outputFile.parent.create(recursive: true);
  final sink = outputFile.openWrite();
  try {
    for (final task in tasks) {
      sink.writeln(jsonEncode(task));
    }
  } finally {
    await sink.close();
  }

  stdout.writeln('Wrote ${tasks.length} judge tasks to ${outputFile.path}');
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  return const [];
}
