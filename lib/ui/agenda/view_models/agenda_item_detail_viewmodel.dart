import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/todo_schedule_model.dart';

class AgendaItemDetailViewModel extends ChangeNotifier {
  final TodoScheduleItemModel item;
  final MemexRouter _router;

  CardDetailModel? _sourceCardDetail;
  bool _isLoadingSourceCard = false;
  String? _sourceCardError;
  bool _isCompleting = false;
  bool _isCancelling = false;
  String? _currentStatus;

  AgendaItemDetailViewModel({
    required this.item,
    required MemexRouter router,
  })  : _router = router,
        _currentStatus = item.status;

  CardDetailModel? get sourceCardDetail => _sourceCardDetail;
  bool get isLoadingSourceCard => _isLoadingSourceCard;
  String? get sourceCardError => _sourceCardError;
  bool get isCompleting => _isCompleting;
  bool get isCancelling => _isCancelling;
  String get currentStatus => _currentStatus ?? item.status;
  bool get isPending => currentStatus == 'pending';

  void init() {
    loadSourceCard();
  }

  Future<void> loadSourceCard() async {
    if (item.sourceFactId.isEmpty) return;

    _isLoadingSourceCard = true;
    _sourceCardError = null;
    notifyListeners();

    try {
      _sourceCardDetail = await _router.fetchCardDetail(item.sourceFactId);
    } catch (e) {
      _sourceCardError = e.toString();
    }

    _isLoadingSourceCard = false;
    notifyListeners();
  }

  Future<void> completeItem() async {
    if (_isCompleting || !isPending) return;
    _isCompleting = true;
    notifyListeners();

    try {
      await _router.markTodoCompleteViaUI(item.id, item.title);
      _currentStatus = 'done';
      EventBusService.instance.emitEvent(TodoItemsUpdatedMessage());
    } finally {
      _isCompleting = false;
      notifyListeners();
    }
  }

  Future<void> cancelItem() async {
    if (_isCancelling || !isPending) return;
    _isCancelling = true;
    notifyListeners();

    try {
      await _router.cancelTodoViaUI(item.id, item.title);
      _currentStatus = 'cancelled';
      EventBusService.instance.emitEvent(TodoItemsUpdatedMessage());
    } finally {
      _isCancelling = false;
      notifyListeners();
    }
  }
}
