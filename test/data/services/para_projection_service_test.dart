import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/data/services/para_projection_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParaProjectionService', () {
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserStorage.initL10n();
      root = await Directory.systemTemp.createTemp('memex_para_projection_');
      await FileSystemService.init(root.path);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('writes a markdown projection without becoming source of truth',
        () async {
      await MemoryPrimaryService.instance.applyPatches(
        userId: 'user-a',
        sourceAgent: 'test_agent',
        patches: const [
          MemoryPatch(
            op: 'create',
            type: 'project_context',
            title: 'Atlas Launch',
            content: 'User is preparing Project Atlas launch.',
            entityIds: ['Project Atlas'],
            evidenceFactIds: ['2026/06/09.md#ts_1'],
          ),
          MemoryPatch(
            op: 'create',
            type: 'preference',
            title: 'Reports',
            content: 'User prefers concise reports.',
          ),
        ],
      );

      final result = await ParaProjectionService.instance
          .projectMemoryPrimaryToPara(userId: 'user-a');
      final file = File(result.filePath);
      final content = await file.readAsString();

      expect(file.existsSync(), isTrue);
      expect(result.memoryCount, 2);
      expect(content, contains('This document is a projection'));
      expect(content, contains('## Projects'));
      expect(content, contains('## Areas'));
      expect(content, contains('`mem_101`'));
      expect(content, contains('`2026/06/09.md#ts_1`'));
    });
  });
}
