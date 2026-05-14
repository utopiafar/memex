import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/logger.dart';

final _logger = getLogger('TimelineDateScrubber');

const timelineDateScrubberOverlayKey = ValueKey<String>(
  'timeline_date_scrubber_overlay',
);
const timelineDateScrubberGestureKey = ValueKey<String>(
  'timeline_date_scrubber_gesture',
);
const timelineDateScrubberHandleKey = ValueKey<String>(
  'timeline_date_scrubber_handle',
);
const timelineDateScrubberBubbleKey = ValueKey<String>(
  'timeline_date_scrubber_bubble',
);
const timelineDateScrubberYearRailKey = ValueKey<String>(
  'timeline_date_scrubber_year_rail',
);
const timelineDateScrubberActiveYearKey = ValueKey<String>(
  'timeline_date_scrubber_active_year',
);

class TimelineDateScrubber extends StatefulWidget {
  const TimelineDateScrubber({
    super.key,
    required this.child,
    required this.cards,
    required this.scrollController,
    this.hasMore = false,
    this.onLoadMore,
    this.localeName,
    this.enabled = true,
    this.trackInsets = const EdgeInsets.only(top: 16, bottom: 104),
  });

  final Widget child;
  final List<TimelineCardModel> cards;
  final ScrollController scrollController;
  final bool hasMore;
  final Future<void> Function()? onLoadMore;
  final String? localeName;
  final bool enabled;
  final EdgeInsets trackInsets;

  @override
  State<TimelineDateScrubber> createState() => _TimelineDateScrubberState();
}

class _TimelineDateScrubberState extends State<TimelineDateScrubber> {
  static const double _gestureWidth = 56;
  static const double _handleWidth = 32;
  static const double _handleHeight = 52;
  static const double _bubbleWidth = 98;
  static const double _bubbleHeight = 58;
  static const double _yearRailWidth = 64;
  static const double _yearRailRowHeight = 26;
  static const int _maxYearRailRows = 7;
  static const Duration _hideDelay = Duration(milliseconds: 900);

  Timer? _hideTimer;
  bool _isVisible = false;
  bool _isDragging = false;
  bool _isScrollable = false;
  bool _loadMoreInFlight = false;
  double _fraction = 0;
  double _dragFraction = 0;
  List<int> _timelineYears = const [];

  bool get _hasEnoughCards => widget.enabled && widget.cards.length > 1;

  bool get _hasScrollableMetrics {
    if (!_hasEnoughCards || !widget.scrollController.hasClients) {
      return false;
    }
    final maxScrollExtent = widget.scrollController.position.maxScrollExtent;
    return maxScrollExtent.isFinite && maxScrollExtent > 1;
  }

  bool get _canScrub => _isScrollable && _hasScrollableMetrics;

  @override
  void initState() {
    super.initState();
    _syncTimelineYears();
    widget.scrollController.addListener(_syncFractionFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFractionFromScroll();
    });
  }

  @override
  void didUpdateWidget(covariant TimelineDateScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncFractionFromScroll);
      widget.scrollController.addListener(_syncFractionFromScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncFractionFromScroll();
      });
    }
    if (oldWidget.cards != widget.cards) {
      _syncTimelineYears();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncFractionFromScroll();
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.scrollController.removeListener(_syncFractionFromScroll);
    super.dispose();
  }

  void _syncFractionFromScroll() {
    final canScroll = _hasScrollableMetrics;
    if (!canScroll) {
      if (_isScrollable || _isVisible) {
        setState(() {
          _isScrollable = false;
          _isVisible = false;
          _fraction = 0;
        });
      }
      return;
    }

    final position = widget.scrollController.position;
    final nextFraction = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    if (_isScrollable && (nextFraction - _fraction).abs() < 0.002) return;
    setState(() {
      _isScrollable = true;
      _fraction = nextFraction;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || !_hasEnoughCards) {
      return false;
    }

    if (!_isScrollable && notification.metrics.maxScrollExtent > 1) {
      setState(() => _isScrollable = true);
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _showTemporarily();
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle &&
        !_isDragging) {
      _scheduleHide();
    }
    return false;
  }

  void _showTemporarily() {
    if (!_canScrub) return;
    _hideTimer?.cancel();
    if (!_isVisible) {
      setState(() => _isVisible = true);
    }
    if (!_isDragging) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || _isDragging) return;
      setState(() => _isVisible = false);
    });
  }

  void _beginDrag(DragStartDetails details, double height) {
    if (!_canScrub) return;
    _hideTimer?.cancel();
    _isDragging = true;
    _dragFraction = _fraction;
    setState(() {
      _isVisible = true;
    });
  }

  void _updateDrag(DragUpdateDetails details, double height) {
    if (!_canScrub) return;
    final trackHeight = _trackHeight(height);
    if (trackHeight <= 0) return;

    final distanceFromRight = _gestureWidth - details.localPosition.dx;
    final slowdown = ((distanceFromRight - _handleWidth) / 180).clamp(0.0, 1.0);
    final sensitivity = lerpDouble(1.0, 0.28, slowdown) ?? 1.0;
    final nextFraction =
        (_dragFraction + details.delta.dy / trackHeight * sensitivity).clamp(
      0.0,
      1.0,
    );

    _dragFraction = nextFraction;
    setState(() {
      _isVisible = true;
      _fraction = nextFraction;
    });
    _jumpToFraction(nextFraction);
  }

  void _endDrag() {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _scheduleHide();
  }

  void _handleTapDown(TapDownDetails details, double height) {
    if (!_canScrub) return;
    final nextFraction = _fractionForLocalY(details.localPosition.dy, height);
    setState(() {
      _isVisible = true;
      _fraction = nextFraction;
    });
    _jumpToFraction(nextFraction);
    _scheduleHide();
  }

  void _jumpToFraction(double fraction) {
    final position = widget.scrollController.position;
    final target = (position.maxScrollExtent * fraction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.scrollController.jumpTo(target);
    _maybeLoadMore(fraction);
  }

  Future<void> _maybeLoadMore(double fraction) async {
    if (!widget.hasMore ||
        widget.onLoadMore == null ||
        fraction < 0.92 ||
        _loadMoreInFlight) {
      return;
    }
    _loadMoreInFlight = true;
    try {
      await widget.onLoadMore!.call();
    } catch (e, st) {
      _logger.warning('Failed to load more cards from date scrubber', e, st);
    } finally {
      if (mounted) _loadMoreInFlight = false;
    }
  }

  double _fractionForLocalY(double localY, double height) {
    final top = _trackTop(height);
    final trackHeight = _trackHeight(height);
    if (trackHeight <= 0) return 0;
    return ((localY - top) / trackHeight).clamp(0.0, 1.0);
  }

  double _trackTop(double height) {
    if (height <= 0) return 0;
    if (height < widget.trackInsets.vertical + _handleHeight) {
      return math.min(8, height / 2);
    }
    return widget.trackInsets.top.clamp(0.0, height).toDouble();
  }

  double _trackBottom(double height) {
    if (height <= 0) return 0;
    if (height < widget.trackInsets.vertical + _handleHeight) {
      return math.min(8, height / 2);
    }
    return widget.trackInsets.bottom.clamp(0.0, height).toDouble();
  }

  double _trackHeight(double height) {
    return math.max(0.0, height - _trackTop(height) - _trackBottom(height));
  }

  double _clampIntoTrack({
    required double value,
    required double top,
    required double bottom,
    required double height,
    required double extent,
  }) {
    final maxTop = height - bottom - extent;
    if (maxTop < top) return top;
    return value.clamp(top, maxTop).toDouble();
  }

  TimelineCardModel? _cardForFraction(double fraction) {
    if (widget.cards.isEmpty) return null;
    final index = ((widget.cards.length - 1) * fraction).round().clamp(
          0,
          widget.cards.length - 1,
        );
    return widget.cards[index];
  }

  _ScrubberDateLabel _dateLabelForFraction(double fraction) {
    final card = _cardForFraction(fraction);
    final timestamp = card?.timestamp ?? DateTime.now();
    return _ScrubberDateLabel(
      year: _formatDate(timestamp, (locale) => DateFormat.y(locale)),
      day: _formatDate(timestamp, (locale) => DateFormat.MMMd(locale)),
    );
  }

  String _formatDate(
    DateTime timestamp,
    DateFormat Function(String? locale) formatterBuilder,
  ) {
    try {
      return formatterBuilder(widget.localeName).format(timestamp);
    } catch (_) {
      return formatterBuilder(null).format(timestamp);
    }
  }

  void _syncTimelineYears() {
    final years = <int>{};
    for (final card in widget.cards) {
      years.add(card.timestamp.year);
    }
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    _timelineYears = sortedYears;
  }

  List<int> _visibleYearsForRail({
    required int activeYear,
    required int maxRows,
  }) {
    if (_timelineYears.length <= maxRows) return _timelineYears;
    final activeIndex = _timelineYears.indexOf(activeYear);
    if (activeIndex == -1) return _timelineYears.take(maxRows).toList();

    final maxStart = _timelineYears.length - maxRows;
    final start = (activeIndex - maxRows ~/ 2).clamp(0, maxStart);
    return _timelineYears.sublist(start, start + maxRows);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncFractionFromScroll();
        });
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_hasEnoughCards && _isScrollable)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        IgnorePointer(
                          child: _buildScrubberVisuals(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          ),
                        ),
                        Positioned(
                          key: timelineDateScrubberGestureKey,
                          top: 0,
                          right: 0,
                          bottom: 0,
                          width: math.min(_gestureWidth, constraints.maxWidth),
                          child: IgnorePointer(
                            ignoring: !_isVisible && !_isDragging,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapDown: (details) => _handleTapDown(
                                details,
                                constraints.maxHeight,
                              ),
                              onVerticalDragStart: (details) => _beginDrag(
                                details,
                                constraints.maxHeight,
                              ),
                              onVerticalDragUpdate: (details) => _updateDrag(
                                details,
                                constraints.maxHeight,
                              ),
                              onVerticalDragEnd: (_) => _endDrag(),
                              onVerticalDragCancel: _endDrag,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrubberVisuals({
    required double width,
    required double height,
  }) {
    final top = _trackTop(height);
    final bottom = _trackBottom(height);
    final trackHeight = _trackHeight(height);
    final centerY = top + trackHeight * _fraction;
    final handleTop = _clampIntoTrack(
      value: centerY - _handleHeight / 2,
      top: top,
      bottom: bottom,
      height: height,
      extent: _handleHeight,
    );
    final bubbleTop = _clampIntoTrack(
      value: centerY - _bubbleHeight / 2,
      top: top,
      bottom: bottom,
      height: height,
      extent: _bubbleHeight,
    );
    final label = _dateLabelForFraction(_fraction);
    final visualGestureWidth = math.min(_gestureWidth, width);
    final visualHandleWidth = math.min(_handleWidth, visualGestureWidth);
    final bubbleWidth = math.min(
      _bubbleWidth,
      math.max(0.0, width - visualGestureWidth - 16),
    );
    final showBubble = bubbleWidth >= 48;
    final bubbleRight = math.min(
      visualGestureWidth + 8,
      math.max(0.0, width - bubbleWidth - 8),
    );
    final yearRailRight =
        showBubble ? bubbleRight + bubbleWidth + 8 : visualGestureWidth + 8;
    final maxYearRows = math.min(
      _maxYearRailRows,
      math.max(2, ((trackHeight - 12) / _yearRailRowHeight).floor()),
    );
    final activeYear = _cardForFraction(_fraction)?.timestamp.year;
    final showYearRail = _isDragging &&
        activeYear != null &&
        _timelineYears.length > 1 &&
        maxYearRows >= 2 &&
        width - yearRailRight >= _yearRailWidth + 8 &&
        trackHeight >= _yearRailRowHeight * 2;
    final visibleYears = showYearRail
        ? _visibleYearsForRail(activeYear: activeYear, maxRows: maxYearRows)
        : const <int>[];
    final yearRailHeight = visibleYears.length * _yearRailRowHeight + 12;
    final yearRailTop = _clampIntoTrack(
      value: centerY - yearRailHeight / 2,
      top: top,
      bottom: bottom,
      height: height,
      extent: yearRailHeight,
    );

    return AnimatedSlide(
      offset: _isVisible ? Offset.zero : const Offset(0.18, 0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        key: timelineDateScrubberOverlayKey,
        opacity: _isVisible ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Semantics(
          label: 'Timeline date scrubber',
          value: '${label.day} ${label.year}',
          child: Stack(
            children: [
              Positioned(
                top: top,
                bottom: bottom,
                right: 15,
                width: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              if (showBubble)
                Positioned(
                  key: timelineDateScrubberBubbleKey,
                  top: bubbleTop,
                  right: bubbleRight,
                  width: bubbleWidth,
                  height: _bubbleHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF202124).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(_bubbleHeight / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: math.max(0.0, bubbleWidth - 24),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label.year,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            width: math.max(0.0, bubbleWidth - 20),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label.day,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.05,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (showYearRail)
                Positioned(
                  key: timelineDateScrubberYearRailKey,
                  top: yearRailTop,
                  right: yearRailRight,
                  width: _yearRailWidth,
                  height: yearRailHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF202124).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final year in visibleYears)
                            _YearRailLabel(
                              year: year,
                              active: year == activeYear,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: handleTop,
                right: 0,
                width: visualGestureWidth,
                height: _handleHeight,
                child: Center(
                  child: Container(
                    key: timelineDateScrubberHandleKey,
                    width: visualHandleWidth,
                    height: _handleHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        visualHandleWidth / 2,
                      ),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 18,
                          color: Color(0xFF3C4043),
                        ),
                        SizedBox(height: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Color(0xFF3C4043),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrubberDateLabel {
  const _ScrubberDateLabel({required this.year, required this.day});

  final String year;
  final String day;
}

class _YearRailLabel extends StatelessWidget {
  const _YearRailLabel({required this.year, required this.active});

  final int year;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _TimelineDateScrubberState._yearRailRowHeight,
      child: Center(
        child: AnimatedScale(
          scale: active ? 1 : 0.88,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: Text(
            '$year',
            key: active ? timelineDateScrubberActiveYearKey : null,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 1 : 0.62),
              fontSize: active ? 18 : 13,
              height: 1,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
