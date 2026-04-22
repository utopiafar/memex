import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'todo_schedule_dao.g.dart';

@DriftAccessor(tables: [TodoScheduleItems])
class TodoScheduleDao extends DatabaseAccessor<AppDatabase>
    with _$TodoScheduleDaoMixin {
  TodoScheduleDao(super.db);

  /// Query items by date range (dueDate or scheduleStart falls in range)
  Future<List<TodoScheduleItem>> queryByDateRange(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final fromTs = from.millisecondsSinceEpoch ~/ 1000;
    final toTs = to.millisecondsSinceEpoch ~/ 1000;

    return (select(todoScheduleItems)
          ..where((t) => t.userId.equals(userId))
          ..where((t) =>
              (t.dueDate.isBiggerOrEqualValue(fromTs) &
                  t.dueDate.isSmallerOrEqualValue(toTs)) |
              (t.scheduleStart.isBiggerOrEqualValue(fromTs) &
                  t.scheduleStart.isSmallerOrEqualValue(toTs))))
        .get();
  }

  /// Query items by status
  Future<List<TodoScheduleItem>> queryByStatus(
    String userId,
    List<String> statuses,
  ) async {
    return (select(todoScheduleItems)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.status.isIn(statuses)))
        .get();
  }

  /// Get all pending todos (not done, not cancelled)
  Future<List<TodoScheduleItem>> queryPendingTodos(String userId) async {
    return (select(todoScheduleItems)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.type.equals('todo'))
          ..where((t) => t.status.equals('pending'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            (t) =>
                OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Get today's items (todos due today + schedules starting today)
  Future<List<TodoScheduleItem>> queryTodayItems(
    String userId,
    DateTime today,
  ) async {
    final startOfDay =
        DateTime(today.year, today.month, today.day).millisecondsSinceEpoch ~/
            1000;
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59)
            .millisecondsSinceEpoch ~/
        1000;

    return (select(todoScheduleItems)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.status.equals('pending'))
          ..where((t) =>
              (t.dueDate.isBiggerOrEqualValue(startOfDay) &
                  t.dueDate.isSmallerOrEqualValue(endOfDay)) |
              (t.scheduleStart.isBiggerOrEqualValue(startOfDay) &
                  t.scheduleStart.isSmallerOrEqualValue(endOfDay)))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            (t) => OrderingTerm(
                expression: t.scheduleStart, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Get all items for a user (for Agenda tab display)
  Future<List<TodoScheduleItem>> queryAllActive(String userId) async {
    return (select(todoScheduleItems)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.status.equals('pending'))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            (t) => OrderingTerm(
                expression: t.scheduleStart, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Insert or update an item
  Future<void> upsertItem(TodoScheduleItemsCompanion item) async {
    await into(todoScheduleItems).insertOnConflictUpdate(item);
  }

  /// Update status for an item. Returns affected row count.
  Future<int> updateStatus(
    String id, {
    required String status,
    int? completedAt,
    String? completedByFactId,
  }) async {
    return (update(todoScheduleItems)
          ..where((t) => t.id.equals(id)))
        .write(
      TodoScheduleItemsCompanion(
        status: Value(status),
        completedAt: Value(completedAt),
        completedByFactId: Value(completedByFactId),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }

  /// Get a single item by id
  Future<TodoScheduleItem?> getById(String id) async {
    return (select(todoScheduleItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Delete an item by id
  Future<void> deleteItem(String id) async {
    await (delete(todoScheduleItems)..where((t) => t.id.equals(id))).go();
  }

  /// Delete all items for a user (for cache rebuild)
  Future<void> clearAll(String userId) async {
    await (delete(todoScheduleItems)
          ..where((t) => t.userId.equals(userId)))
        .go();
  }
}
