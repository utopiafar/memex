import 'package:drift/drift.dart' as drift;
import 'package:logging/logging.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/event_bus_message.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('PinCard');

/// Pin duration options
enum PinDuration {
  today,
  thisWeek,
  custom,
}

/// Calculate pinned_until timestamp based on duration
int _calculatePinnedUntil(PinDuration duration, {DateTime? customUntil}) {
  final now = DateTime.now();
  switch (duration) {
    case PinDuration.today:
      return DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch ~/
          1000;
    case PinDuration.thisWeek:
      // End of Sunday of this week
      final endOfWeek = DateTime(
          now.year, now.month, now.day + (7 - now.weekday));
      return endOfWeek.millisecondsSinceEpoch ~/ 1000;
    case PinDuration.custom:
      if (customUntil == null) {
        throw ArgumentError('customUntil must be provided for custom duration');
      }
      return customUntil.millisecondsSinceEpoch ~/ 1000;
  }
}

/// Pin a card to the top of the timeline
Future<void> pinCard({
  required String factId,
  required PinDuration duration,
  int priority = 0,
  DateTime? customUntil,
}) async {
  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    final fileService = FileSystemService.instance;
    final pinnedUntil = _calculatePinnedUntil(duration, customUntil: customUntil);

    // Update card YAML
    await fileService.updateCardFile(userId, factId, (card) {
      return card.copyWith(
        isPinned: true,
        pinnedUntil: pinnedUntil,
        pinPriority: priority,
      );
    });

    // Update cache
    final updatedCard = await fileService.readCardFile(userId, factId);
    if (updatedCard != null) {
      await fileService.updateCardCache(userId, factId, updatedCard);
    }

    // Emit event for UI update
    final cardData = await fileService.readCardFile(userId, factId);
    if (cardData != null) {
      EventBusService.instance.emitEvent(CardUpdatedMessage(
        id: factId,
        html: '',
        timestamp: cardData.timestamp,
        tags: cardData.tags,
        status: cardData.status,
        title: cardData.title,
        uiConfigs: cardData.uiConfigs,
        isPinned: true,
        pinnedUntil: pinnedUntil,
        pinPriority: priority,
      ));
    }

    _logger.info('Card $factId pinned until $pinnedUntil (priority: $priority)');
  } catch (e) {
    _logger.severe('Failed to pin card $factId: $e');
    rethrow;
  }
}

/// Unpin a card from the top of the timeline
Future<void> unpinCard({required String factId}) async {
  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    final fileService = FileSystemService.instance;

    // Update card YAML
    await fileService.updateCardFile(userId, factId, (card) {
      return card.copyWith(
        isPinned: false,
        pinnedUntil: null,
        pinPriority: 0,
      );
    });

    // Update cache
    final updatedCard = await fileService.readCardFile(userId, factId);
    if (updatedCard != null) {
      await fileService.updateCardCache(userId, factId, updatedCard);
    }

    // Emit event for UI update
    final cardData = await fileService.readCardFile(userId, factId);
    if (cardData != null) {
      EventBusService.instance.emitEvent(CardUpdatedMessage(
        id: factId,
        html: '',
        timestamp: cardData.timestamp,
        tags: cardData.tags,
        status: cardData.status,
        title: cardData.title,
        uiConfigs: cardData.uiConfigs,
        isPinned: false,
      ));
    }

    _logger.info('Card $factId unpinned');
  } catch (e) {
    _logger.severe('Failed to unpin card $factId: $e');
    rethrow;
  }
}

/// Clean up expired pinned cards. Called by scheduled task.
Future<void> cleanupExpiredPins() async {
  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    final fileService = FileSystemService.instance;
    final db = AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Query all pinned cards with expired pinned_until
    final pinnedCards = await (db.select(db.cardCache)
          ..where((t) => t.isPinned.equals(true))
          ..where((t) => t.pinnedUntil.isSmallerThanValue(now)))
        .get();

    _logger.info('Found ${pinnedCards.length} expired pinned cards to cleanup');

    for (final cached in pinnedCards) {
      try {
        await fileService.updateCardFile(userId, cached.factId, (card) {
          return card.copyWith(
            isPinned: false,
            pinnedUntil: null,
            pinPriority: 0,
          );
        });

        final updatedCard =
            await fileService.readCardFile(userId, cached.factId);
        if (updatedCard != null) {
          await fileService.updateCardCache(userId, cached.factId, updatedCard);

          EventBusService.instance.emitEvent(CardUpdatedMessage(
            id: cached.factId,
            html: '',
            timestamp: updatedCard.timestamp,
            tags: updatedCard.tags,
            status: updatedCard.status,
            title: updatedCard.title,
            uiConfigs: updatedCard.uiConfigs,
            isPinned: false,
          ));
        }
      } catch (e) {
        _logger.warning('Failed to cleanup pin for ${cached.factId}: $e');
      }
    }
  } catch (e) {
    _logger.severe('Failed to cleanup expired pins: $e');
  }
}
