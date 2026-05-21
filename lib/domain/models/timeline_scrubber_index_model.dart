class TimelineScrubberIndexItem {
  const TimelineScrubberIndexItem({
    required this.id,
    required this.timestamp,
  });

  final String id;
  final DateTime timestamp;
}

class TimelineScrubberIndexModel {
  const TimelineScrubberIndexModel({required this.items});

  final List<TimelineScrubberIndexItem> items;

  int get totalCount => items.length;

  List<DateTime> get timestamps =>
      items.map((item) => item.timestamp).toList(growable: false);
}
