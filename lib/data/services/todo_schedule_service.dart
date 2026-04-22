import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../db/app_database.dart';
import '../../db/daos/todo_schedule_dao.dart';
import '../../db/tables.dart';

/// Service layer for TodoSchedule items.
/// Wraps DAO operations with business logic (ID generation, timestamp handling).
class TodoScheduleService {
  static final Logger _logger = Logger('TodoScheduleService');
  static final _uuid = const Uuid();

  static final TodoScheduleService _instance = TodoScheduleService._();
  static TodoScheduleService get instance => _instance;
  TodoScheduleService._();

  /// Allow direct construction for backward compatibility
  TodoScheduleService();

  TodoScheduleDao get _dao => AppDatabase.instance.todoScheduleDao;

  /// Create a new todo item
  Future<TodoScheduleItem> createTodo({
    required String userId,
    required String title,
    required String sourceFactId,
    int priority = 0,
    DateTime? dueDate,
    List<String>? tags,
    String sourceType = 'agent',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = _uuid.v7();
    final companion = TodoScheduleItemsCompanion.insert(
      id: id,
      userId: userId,
      title: title,
      type: 'todo',
      sourceFactId: sourceFactId,
      priority: Value(priority),
      dueDate: Value(dueDate != null ? dueDate.millisecondsSinceEpoch ~/ 1000 : null),
      tags: Value(jsonEncode(tags ?? [])),
      sourceType: Value(sourceType),
      createdAt: now,
    );
    await _dao.upsertItem(companion);
    _logger.info('Created todo: $title (id=$id)');
    return (await _dao.getById(id))!;
  }

  /// Create a new schedule item
  Future<TodoScheduleItem> createSchedule({
    required String userId,
    required String title,
    required String sourceFactId,
    required DateTime scheduleStart,
    DateTime? scheduleEnd,
    int priority = 0,
    List<String>? tags,
    String sourceType = 'agent',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = _uuid.v7();
    final companion = TodoScheduleItemsCompanion.insert(
      id: id,
      userId: userId,
      title: title,
      type: 'schedule',
      sourceFactId: sourceFactId,
      priority: Value(priority),
      scheduleStart: Value(scheduleStart.millisecondsSinceEpoch ~/ 1000),
      scheduleEnd: Value(scheduleEnd != null ? scheduleEnd.millisecondsSinceEpoch ~/ 1000 : null),
      tags: Value(jsonEncode(tags ?? [])),
      sourceType: Value(sourceType),
      createdAt: now,
    );
    await _dao.upsertItem(companion);
    _logger.info('Created schedule: $title (id=$id)');
    return (await _dao.getById(id))!;
  }

  /// Mark an item as done.
  Future<bool> completeItem(String id, {String? completedByFactId}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final affected = await _dao.updateStatus(
      id,
      status: 'done',
      completedAt: now,
      completedByFactId: completedByFactId,
    );
    if (affected > 0) {
      _logger.info('Completed item: $id');
      return true;
    }
    _logger.info('Item $id not found');
    return false;
  }

  /// Mark an item as cancelled
  Future<void> cancelItem(String id) async {
    await _dao.updateStatus(id, status: 'cancelled');
    _logger.info('Cancelled item: $id');
  }

  /// Get all pending items for a user (Agenda tab display)
  Future<List<TodoScheduleItem>> getActiveItems(String userId) async {
    return _dao.queryAllActive(userId);
  }

  /// Get today's items
  Future<List<TodoScheduleItem>> getTodayItems(
      String userId, DateTime today) async {
    return _dao.queryTodayItems(userId, today);
  }

  /// Get pending todos (for Agent context — matching completions)
  Future<List<TodoScheduleItem>> getPendingTodos(String userId) async {
    return _dao.queryPendingTodos(userId);
  }

  /// Get a single item by id
  Future<TodoScheduleItem?> getById(String id) async {
    return _dao.getById(id);
  }

  /// Clear all items for a user (cache rebuild)
  Future<void> clearAll(String userId) async {
    await _dao.clearAll(userId);
    _logger.info('Cleared all todo/schedule items for user: $userId');
  }
}
