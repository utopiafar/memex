import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/timeline_scrubber_index_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('GetTimelineScrubberIndexEndpoint');

Future<TimelineScrubberIndexModel> getTimelineScrubberIndex({
  List<String>? tags,
  DateTime? dateFrom,
  DateTime? dateTo,
}) async {
  _logger.info(
    'getTimelineScrubberIndex called: tags=$tags, dateFrom=$dateFrom, dateTo=$dateTo',
  );

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found, returning empty scrubber index');
      return const TimelineScrubberIndexModel(items: []);
    }

    final db = AppDatabase.instance;
    if (await db.cardDao.isCacheEmpty()) {
      _logger.info('Card cache is empty, triggering rebuild...');
      await FileSystemService.instance.rebuildCardCache(userId);
    }

    final cachedCards = await db.cardDao.getCardIndex(
      tags: tags,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    final items = cachedCards.map((cachedCard) {
      return TimelineScrubberIndexItem(
        id: cachedCard.factId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          cachedCard.timestamp * 1000,
          isUtc: true,
        ).toLocal(),
      );
    }).toList(growable: false);

    _logger.info('Returned ${items.length} scrubber index entries');
    return TimelineScrubberIndexModel(items: items);
  } catch (e) {
    _logger.severe('Failed to fetch timeline scrubber index: $e');
    return const TimelineScrubberIndexModel(items: []);
  }
}
