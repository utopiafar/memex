import 'package:flutter/material.dart';
import 'package:memex/domain/models/todo_schedule_model.dart';
import 'package:memex/ui/core/cards/ui/glass_card.dart';

/// Agenda item card matching TaskCard visual style.
/// - GlassCard container (20px radius, white, shadow)
/// - Circular checkbox (20x20, #5B6CFF)
/// - 17px bold title with strikethrough when done
/// - Tags as small chips
class AgendaItemCard extends StatelessWidget {
  final TodoScheduleItemModel item;
  final VoidCallback? onTap;
  final VoidCallback? onCheckChanged;
  final bool isCompleting;
  final bool showCompleted;

  const AgendaItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onCheckChanged,
    this.isCompleting = false,
    this.showCompleted = false,
  });

  static const _primaryColor = Color(0xFF5B6CFF);
  static const _successColor = Color(0xFF10B981);
  static const _textPrimary = Color(0xFF0A0A0A);
  static const _textTertiary = Color(0xFF99A1AF);

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == 'done' || showCompleted;
    final isPending = item.status == 'pending';
    final isSchedule = item.type == 'schedule';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: checkbox + title + priority
            Row(
              children: [
                // Checkbox / Type icon
                GestureDetector(
                  onTap: isPending && onCheckChanged != null
                      ? onCheckChanged
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: _buildLeading(isDone, isSchedule),
                ),
                const SizedBox(width: 12),
                // Title
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: _textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Priority flag
                if (item.priority > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child:
                        Icon(Icons.priority_high, size: 16, color: Color(0xFFF43F5E)),
                  ),
              ],
            ),

            // Date/time subtitle
            if (item.dueDate != null || item.scheduleStart != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  _formatDateTime(),
                  style: const TextStyle(fontSize: 11, color: _textTertiary),
                ),
              ),
            ],

            // Tags
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: _buildTags(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(bool isDone, bool isSchedule) {
    if (isCompleting) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
      );
    }

    if (isSchedule && !isDone) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _primaryColor.withValues(alpha: 0.1),
        ),
        child: const Icon(Icons.schedule, size: 12, color: _primaryColor),
      );
    }

    // Circular checkbox matching TaskCard
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDone ? _successColor : _primaryColor,
          width: 2,
        ),
        color: isDone ? _successColor : Colors.transparent,
      ),
      child: isDone
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }

  Widget _buildTags() {
    final displayTags = item.tags.take(2).toList();
    final overflow = item.tags.length - 2;

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        ...displayTags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#$tag',
                style: const TextStyle(
                    fontSize: 11, color: _primaryColor, fontWeight: FontWeight.w500),
              ),
            )),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              '+$overflow',
              style: const TextStyle(fontSize: 11, color: _textTertiary),
            ),
          ),
      ],
    );
  }

  String _formatDateTime() {
    if (item.type == 'schedule' && item.scheduleStart != null) {
      final start = _formatTime(item.scheduleStart!);
      final end = item.scheduleEnd != null
          ? ' - ${_formatTime(item.scheduleEnd!)}'
          : '';
      final date = _formatDate(item.scheduleStart!);
      return '$date $start$end';
    }
    if (item.dueDate != null) {
      return _formatDate(item.dueDate!);
    }
    return '';
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}';
  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
