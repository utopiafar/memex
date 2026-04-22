import 'dart:convert';
import 'package:memex/db/app_database.dart';

/// UI-layer model for TodoSchedule items, derived from the Drift data class.
class TodoScheduleItemModel {
  final String id;
  final String title;
  final String type; // 'todo' | 'schedule'
  final String status; // 'pending' | 'done' | 'cancelled'
  final int priority;
  final DateTime? dueDate;
  final DateTime? scheduleStart;
  final DateTime? scheduleEnd;
  final List<String> tags;
  final String sourceFactId;
  final String? completedByFactId;
  final DateTime? completedAt;
  final DateTime createdAt;

  const TodoScheduleItemModel({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.priority,
    this.dueDate,
    this.scheduleStart,
    this.scheduleEnd,
    required this.tags,
    required this.sourceFactId,
    this.completedByFactId,
    this.completedAt,
    required this.createdAt,
  });

  factory TodoScheduleItemModel.fromDb(TodoScheduleItem item) {
    return TodoScheduleItemModel(
      id: item.id,
      title: item.title,
      type: item.type,
      status: item.status,
      priority: item.priority,
      dueDate: item.dueDate != null
          ? DateTime.fromMillisecondsSinceEpoch(item.dueDate! * 1000)
          : null,
      scheduleStart: item.scheduleStart != null
          ? DateTime.fromMillisecondsSinceEpoch(item.scheduleStart! * 1000)
          : null,
      scheduleEnd: item.scheduleEnd != null
          ? DateTime.fromMillisecondsSinceEpoch(item.scheduleEnd! * 1000)
          : null,
      tags: _parseTags(item.tags),
      sourceFactId: item.sourceFactId,
      completedByFactId: item.completedByFactId,
      completedAt: item.completedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(item.completedAt! * 1000)
          : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(item.createdAt * 1000),
    );
  }

  static List<String> _parseTags(String tagsJson) {
    try {
      if (tagsJson.startsWith('[')) {
        return (jsonDecode(tagsJson) as List).cast<String>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
