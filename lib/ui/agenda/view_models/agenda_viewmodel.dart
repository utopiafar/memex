import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/todo_schedule_model.dart';

class AgendaViewModel extends ChangeNotifier {
  final MemexRouter _router;

  List<TodoScheduleItemModel> _todayTodos = [];
  List<TodoScheduleItemModel> _todaySchedules = [];
  List<TodoScheduleItemModel> _upcomingItems = [];
  List<TodoScheduleItemModel> _noDateItems = [];
  List<TodoScheduleItemModel> _completedItems = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _eventBusSetup = false;
  final Set<String> _completingIds = {};

  AgendaViewModel({required MemexRouter router}) : _router = router;

  List<TodoScheduleItemModel> get todayTodos => _todayTodos;
  List<TodoScheduleItemModel> get todaySchedules => _todaySchedules;
  List<TodoScheduleItemModel> get upcomingItems => _upcomingItems;
  List<TodoScheduleItemModel> get noDateItems => _noDateItems;
  List<TodoScheduleItemModel> get completedItems => _completedItems;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool isCompleting(String id) => _completingIds.contains(id);

  void init() {
    _setupEventBus();
    refreshData();
  }

  void _setupEventBus() {
    if (_eventBusSetup) return;
    _eventBusSetup = true;
    final eventBus = EventBusService.instance;
    eventBus.addHandler(
      EventBusMessageType.todoItemsUpdated,
      _handleTodoItemsUpdated,
    );
  }

  void _handleTodoItemsUpdated(EventBusMessage message) {
    refreshData();
  }

  Future<void> refreshData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final items = await _router.fetchAgendaItems();
      final models = items
          .map((item) => TodoScheduleItemModel.fromDb(item as dynamic))
          .toList();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final pending = models.where((m) => m.status == 'pending').toList();

      // Today: todos due today + schedules starting today
      _todayTodos = pending
          .where((m) =>
              m.type == 'todo' &&
              m.dueDate != null &&
              m.dueDate!.year == today.year &&
              m.dueDate!.month == today.month &&
              m.dueDate!.day == today.day)
          .toList();

      _todaySchedules = pending
          .where((m) =>
              m.type == 'schedule' &&
              m.scheduleStart != null &&
              m.scheduleStart!.year == today.year &&
              m.scheduleStart!.month == today.month &&
              m.scheduleStart!.day == today.day)
          .toList();

      // Upcoming: items with future dates
      final todayItemIds = {
        ..._todayTodos.map((m) => m.id),
        ..._todaySchedules.map((m) => m.id),
      };
      _upcomingItems = pending
          .where((m) =>
              !todayItemIds.contains(m.id) &&
              ((m.dueDate != null && m.dueDate!.isAfter(today)) ||
                  (m.scheduleStart != null && m.scheduleStart!.isAfter(today))))
          .toList();

      // No date: items without any date that aren't already categorized
      final datedIds = {
        ...todayItemIds,
        ..._upcomingItems.map((m) => m.id),
      };
      _noDateItems = pending
          .where((m) =>
              !datedIds.contains(m.id) &&
              m.dueDate == null &&
              m.scheduleStart == null)
          .toList();

      // Completed items (shown at bottom, grayed out)
      _completedItems = models
          .where((m) => m.status == 'done')
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> completeTodo(String todoId, String title) async {
    if (_completingIds.contains(todoId)) return;
    _completingIds.add(todoId);
    notifyListeners();
    try {
      await _router.markTodoCompleteViaUI(todoId, title);
    } finally {
      _completingIds.remove(todoId);
      await refreshData();
    }
  }

  @override
  void dispose() {
    if (_eventBusSetup) {
      final eventBus = EventBusService.instance;
      eventBus.removeHandler(
        EventBusMessageType.todoItemsUpdated,
        _handleTodoItemsUpdated,
      );
    }
    super.dispose();
  }
}
