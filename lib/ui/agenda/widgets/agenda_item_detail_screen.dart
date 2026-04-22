import 'package:flutter/material.dart';
import 'package:memex/domain/models/todo_schedule_model.dart';
import 'package:memex/ui/agenda/view_models/agenda_item_detail_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

class AgendaItemDetailScreen extends StatefulWidget {
  final AgendaItemDetailViewModel viewModel;

  const AgendaItemDetailScreen({super.key, required this.viewModel});

  @override
  State<AgendaItemDetailScreen> createState() => _AgendaItemDetailScreenState();
}

class _AgendaItemDetailScreenState extends State<AgendaItemDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;

    return ChangeNotifierProvider.value(
      value: widget.viewModel,
      child: Consumer<AgendaItemDetailViewModel>(
        builder: (context, vm, _) {
          final item = vm.item;
          final isPending = vm.isPending;

          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.agendaItemDetail),
              actions: [
                if (isPending) ...[
                  TextButton.icon(
                    onPressed: vm.isCompleting ? null : _handleComplete,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(l10n.agendaComplete),
                    style: TextButton.styleFrom(foregroundColor: Colors.green),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'cancel') _handleCancel();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(l10n.agendaCancelAction),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + status
                  _buildTitleSection(context, vm),
                  const SizedBox(height: 20),

                  // Details card
                  _buildDetailsCard(context, vm),
                  const SizedBox(height: 20),

                  // Tags
                  if (item.tags.isNotEmpty) ...[
                    _buildSectionTitle(context, Icons.label_outline, 'Tags'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.tags
                          .map((tag) => Chip(
                                label: Text('#$tag'),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Source context
                  _buildSourceSection(context, vm),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleSection(BuildContext context, AgendaItemDetailViewModel vm) {
    final theme = Theme.of(context);
    final item = vm.item;
    final l10n = UserStorage.l10n;

    final statusColor = switch (vm.currentStatus) {
      'done' => Colors.green,
      'cancelled' => Colors.grey,
      _ => theme.colorScheme.primary,
    };

    final statusText = switch (vm.currentStatus) {
      'done' => l10n.agendaStatusDone,
      'cancelled' => l10n.agendaStatusCancelled,
      _ => l10n.agendaStatusPending,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              item.type == 'schedule' ? Icons.schedule : Icons.check_circle_outline,
              color: statusColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: !vm.isPending ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (item.priority > 0) ...[
              const SizedBox(width: 8),
              const Icon(Icons.flag, color: Colors.red, size: 16),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsCard(BuildContext context, AgendaItemDetailViewModel vm) {
    final item = vm.item;
    final l10n = UserStorage.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDetailRow(
              context,
              Icons.calendar_today_outlined,
              item.type == 'schedule' ? 'Schedule' : l10n.agendaCreatedAt,
              _formatItemDate(item),
            ),
            if (item.completedAt != null)
              _buildDetailRow(
                context,
                Icons.check_circle_outline,
                l10n.agendaCompletedAt,
                _formatDate(item.completedAt!),
              ),
            _buildDetailRow(
              context,
              Icons.access_time,
              l10n.agendaCreatedAt,
              _formatDate(item.createdAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSourceSection(BuildContext context, AgendaItemDetailViewModel vm) {
    final l10n = UserStorage.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, Icons.source_outlined, l10n.agendaSourceContext),
        const SizedBox(height: 8),
        if (vm.isLoadingSourceCard)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (vm.sourceCardDetail != null)
          _buildSourcePreview(context, vm.sourceCardDetail!)
        else
          _buildSourceNotAvailable(context),
      ],
    );
  }

  Widget _buildSourceNotAvailable(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey[400], size: 18),
          const SizedBox(width: 8),
          Text(
            l10n.agendaSourceNotAvailable,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Inline preview of the source card (RelatedFactsList style).
  /// Entire area is tappable to navigate to TimelineCardDetailScreen.
  Widget _buildSourcePreview(BuildContext context, dynamic detail) {
    final rawContent = (detail as dynamic).rawContent as String? ?? '';

    return GestureDetector(
      onTap: () {
        final sourceFactId = widget.viewModel.item.sourceFactId;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TimelineCardDetailScreen(cardId: sourceFactId),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B6CFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.article_outlined,
                      size: 14, color: Color(0xFF5B6CFF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (detail as dynamic).title as String? ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0A0A0A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.open_in_new,
                    size: 16, color: Color(0xFF99A1AF)),
              ],
            ),
            if (rawContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rawContent,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4A5565),
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, dynamic detail) {
    final theme = Theme.of(context);
    final l10n = UserStorage.l10n;

    // Extract rawContent from the CardDetailModel
    final rawContent = (detail as dynamic).rawContent as String? ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rawContent.isNotEmpty) ...[
              Text(
                rawContent.length > 200
                    ? '${rawContent.substring(0, 200)}...'
                    : rawContent,
                style: theme.textTheme.bodyMedium,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final sourceFactId = widget.viewModel.item.sourceFactId;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TimelineCardDetailScreen(cardId: sourceFactId),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.agendaViewSourceCard),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
      BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  String _formatItemDate(TodoScheduleItemModel item) {
    if (item.type == 'schedule') {
      if (item.scheduleStart != null) {
        final start = _formatDate(item.scheduleStart!);
        if (item.scheduleEnd != null) {
          return '$start - ${_formatDate(item.scheduleEnd!)}';
        }
        return start;
      }
    }
    if (item.dueDate != null) {
      return _formatDate(item.dueDate!);
    }
    return UserStorage.l10n.agendaNoDate;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        ' ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _handleComplete() async {
    await widget.viewModel.completeItem();
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _handleCancel() async {
    final l10n = UserStorage.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.agendaCancelAction),
        content: Text(l10n.agendaConfirmCancel),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.agendaCancelAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.viewModel.cancelItem();
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }
}
