import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/agenda/view_models/agenda_item_detail_viewmodel.dart';
import 'package:memex/ui/agenda/widgets/agenda_item_card.dart';
import 'package:memex/ui/agenda/widgets/agenda_item_detail_screen.dart';
import 'package:memex/ui/agenda/view_models/agenda_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, required this.viewModel});
  final AgendaViewModel viewModel;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.viewModel,
      child: Consumer<AgendaViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading &&
              vm.todayTodos.isEmpty &&
              vm.todaySchedules.isEmpty &&
              vm.upcomingItems.isEmpty &&
              vm.noDateItems.isEmpty &&
              vm.completedItems.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (vm.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: ${vm.errorMessage}',
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: vm.refreshData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final hasPending = vm.todayTodos.isNotEmpty ||
              vm.todaySchedules.isNotEmpty ||
              vm.upcomingItems.isNotEmpty ||
              vm.noDateItems.isNotEmpty;

          if (!hasPending && vm.completedItems.isEmpty) {
            return RefreshIndicator(
              onRefresh: vm.refreshData,
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.checklist_outlined,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            UserStorage.l10n.agendaEmpty,
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            UserStorage.l10n.agendaEmptyHint,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[400]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: vm.refreshData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                // Today's Todos
                if (vm.todayTodos.isNotEmpty) ...[
                  _buildSectionHeader(context, Icons.checklist,
                      UserStorage.l10n.agendaTodayTasks),
                  const SizedBox(height: 8),
                  ...vm.todayTodos.map((item) => AgendaItemCard(
                        item: item,
                        isCompleting: vm.isCompleting(item.id),
                        onCheckChanged: () =>
                            vm.completeTodo(item.id, item.title),
                        onTap: () => _openDetail(context, item),
                      )),
                  const SizedBox(height: 20),
                ],

                // Today's Schedules
                if (vm.todaySchedules.isNotEmpty) ...[
                  _buildSectionHeader(context, Icons.calendar_today,
                      UserStorage.l10n.agendaTodaySchedule),
                  const SizedBox(height: 8),
                  ...vm.todaySchedules.map((item) => AgendaItemCard(
                        item: item,
                        onTap: () => _openDetail(context, item),
                      )),
                  const SizedBox(height: 20),
                ],

                // Upcoming Items
                if (vm.upcomingItems.isNotEmpty) ...[
                  _buildSectionHeader(context, Icons.event_note,
                      UserStorage.l10n.agendaThisWeek),
                  const SizedBox(height: 8),
                  ...vm.upcomingItems.map((item) => AgendaItemCard(
                        item: item,
                        isCompleting: vm.isCompleting(item.id),
                        onCheckChanged: item.type == 'todo'
                            ? () => vm.completeTodo(item.id, item.title)
                            : null,
                        onTap: () => _openDetail(context, item),
                      )),
                  const SizedBox(height: 20),
                ],

                // No Date Items
                if (vm.noDateItems.isNotEmpty) ...[
                  _buildSectionHeader(context, Icons.checklist_outlined,
                      UserStorage.l10n.agendaNoDate),
                  const SizedBox(height: 8),
                  ...vm.noDateItems.map((item) => AgendaItemCard(
                        item: item,
                        isCompleting: vm.isCompleting(item.id),
                        onCheckChanged: () =>
                            vm.completeTodo(item.id, item.title),
                        onTap: () => _openDetail(context, item),
                      )),
                  const SizedBox(height: 20),
                ],

                // Completed items (grayed out at bottom)
                if (vm.completedItems.isNotEmpty) ...[
                  _buildSectionHeader(
                      context, Icons.check_circle_outline, UserStorage.l10n.agendaStatusDone,
                      color: const Color(0xFF99A1AF)),
                  const SizedBox(height: 8),
                  ...vm.completedItems.map((item) => AgendaItemCard(
                        item: item,
                        showCompleted: true,
                        onTap: () => _openDetail(context, item),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title,
      {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 20, color: c),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }

  Future<void> _openDetail(BuildContext context, dynamic item) async {
    final detailVm = AgendaItemDetailViewModel(
      item: item as dynamic,
      router: MemexRouter(),
    );
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgendaItemDetailScreen(viewModel: detailVm),
      ),
    );
    if (result == true) {
      widget.viewModel.refreshData();
    }
  }
}
