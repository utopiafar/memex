// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recalls Memory Primary atoms restored from a PR256 case log', () async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
    final root = await Directory.systemTemp.createTemp(
      'memex_case_log_recall_debug_',
    );
    await FileSystemService.init(root.path);
    final repoRoot = Directory.current.path;
    final logPath = p.join(
      repoRoot,
      'evals',
      'runs',
      'pr256_full_metric_large_p8_r400_memory_primary_persona01_v12_sgp_a_20260615',
      'case_logs',
      'memory_primary',
      'pr256_full_metric_persona_01.json',
    );
    final sourceLog =
        jsonDecode(await File(logPath).readAsString()) as Map<String, dynamic>;
    final atoms = (sourceLog['final_memory_atoms'] as List)
        .whereType<Map>()
        .map((atom) => Map<String, dynamic>.from(atom))
        .toList(growable: false);
    const userId = 'case_log_recall_debug';
    final file = File(FileSystemService.instance.getMemoryAtomsPath(userId));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'next_memory_id': 10000,
        'atoms': atoms,
      }),
    );

    final activeAtoms =
        await MemoryPrimaryService.instance.listActiveAtoms(userId);
    expect(activeAtoms, hasLength(22));

    final report = await searchMemoryPrimaryForTool(
      userId: userId,
      query: '以后写 Project Orion B 或 Meridian 导出 B 相关技术报告，格式偏好是什么？',
      limit: 10,
    );
    final relationship = await searchMemoryPrimaryForTool(
      userId: userId,
      query: '产品评审找谁？合同付款和发票确认找谁？',
      limit: 10,
    );
    final routine = await searchMemoryPrimaryForTool(
      userId: userId,
      query: '我常驻哪里？周四上午 一般怎么安排？',
      limit: 10,
    );

    expect(report.map((r) => r.atom.id), contains('mem_108'));
    expect(relationship.map((r) => r.atom.id), contains('mem_107'));
    expect(routine.map((r) => r.atom.id), containsAll(['mem_103', 'mem_104']));
  });
}
