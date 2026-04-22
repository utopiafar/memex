import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/db/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('TodoScheduleDao', () {
    test('create and query pending todos', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Create a todo
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: '完成设计文档',
        type: 'todo',
        sourceFactId: '2026/04/21.md#ts_1',
        createdAt: now,
      ));

      final pending = await db.todoScheduleDao.queryPendingTodos('user1');
      expect(pending.length, 1);
      expect(pending.first.title, '完成设计文档');
      expect(pending.first.status, 'pending');
      expect(pending.first.type, 'todo');
    });

    test('queryAllActive only returns pending items', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Create 3 items: pending, done, cancelled
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: 'Pending task',
        type: 'todo',
        sourceFactId: 'f1',
        createdAt: now,
      ));
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-2',
        userId: 'user1',
        title: 'Done task',
        type: 'todo',
        sourceFactId: 'f2',
        status: Value('done'),
        createdAt: now,
      ));
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-3',
        userId: 'user1',
        title: 'Cancelled task',
        type: 'todo',
        sourceFactId: 'f3',
        status: Value('cancelled'),
        createdAt: now,
      ));

      final active = await db.todoScheduleDao.queryAllActive('user1');
      expect(active.length, 1);
      expect(active.first.title, 'Pending task');
    });

    test('complete item updates status', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: 'Task to complete',
        type: 'todo',
        sourceFactId: 'f1',
        createdAt: now,
      ));

      await db.todoScheduleDao.updateStatus(
        'test-1',
        status: 'done',
        completedAt: now,
        completedByFactId: 'f2',
      );

      final item = await db.todoScheduleDao.getById('test-1');
      expect(item!.status, 'done');
      expect(item.completedAt, now);
      expect(item.completedByFactId, 'f2');

      // Should not appear in pending anymore
      final pending = await db.todoScheduleDao.queryPendingTodos('user1');
      expect(pending.length, 0);
    });

    test('cancel item updates status', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: 'Task to cancel',
        type: 'todo',
        sourceFactId: 'f1',
        createdAt: now,
      ));

      await db.todoScheduleDao.updateStatus('test-1', status: 'cancelled');

      final item = await db.todoScheduleDao.getById('test-1');
      expect(item!.status, 'cancelled');
    });

    test('schedule items are separate from todos', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowTs = tomorrow.millisecondsSinceEpoch ~/ 1000;

      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'todo-1',
        userId: 'user1',
        title: 'A todo',
        type: 'todo',
        sourceFactId: 'f1',
        dueDate: Value(tomorrowTs),
        createdAt: now,
      ));
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'sched-1',
        userId: 'user1',
        title: 'A schedule',
        type: 'schedule',
        sourceFactId: 'f2',
        scheduleStart: Value(tomorrowTs),
        createdAt: now,
      ));

      // queryPendingTodos should only return type=todo
      final todos = await db.todoScheduleDao.queryPendingTodos('user1');
      expect(todos.length, 1);
      expect(todos.first.type, 'todo');

      // queryAllActive should return both
      final all = await db.todoScheduleDao.queryAllActive('user1');
      expect(all.length, 2);
    });

    test('clearAll removes all items for a user', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: 'Task 1',
        type: 'todo',
        sourceFactId: 'f1',
        createdAt: now,
      ));
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-2',
        userId: 'user1',
        title: 'Task 2',
        type: 'todo',
        sourceFactId: 'f2',
        createdAt: now,
      ));

      await db.todoScheduleDao.clearAll('user1');
      final active = await db.todoScheduleDao.queryAllActive('user1');
      expect(active.length, 0);
    });

    test('updateStatus returns affected row count', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.todoScheduleDao.upsertItem(TodoScheduleItemsCompanion.insert(
        id: 'test-1',
        userId: 'user1',
        title: 'Task',
        type: 'todo',
        sourceFactId: 'f1',
        createdAt: now,
      ));

      final affected = await db.todoScheduleDao.updateStatus(
        'test-1',
        status: 'done',
        completedAt: now,
      );
      expect(affected, 1);

      // Update non-existent item returns 0
      final affected2 = await db.todoScheduleDao.updateStatus(
        'non-existent',
        status: 'done',
      );
      expect(affected2, 0);
    });
  });
}
