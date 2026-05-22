import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
    this.timelineTimestamps = const [],
    this.hasMore = false,
    this.onLoadMore,
    this.onLoadToIndex,
    this.localeName,
    this.enabled = true,
    this.trackInsets = const EdgeInsets.only(top: 16, bottom: 104),
  });

  final Widget child;
  final List<TimelineCardModel> cards;
  final ScrollController scrollController;
  final List<DateTime> timelineTimestamps;
  final bool hasMore;
  final Future<void> Function()? onLoadMore;
  final Future<void> Function(int targetIndex)? onLoadToIndex;
  final String? localeName;
  final bool enabled;
  final EdgeInsets trackInsets;

  @override
  State<TimelineDateScrubber> createState() => _TimelineDateScrubberState();
}

class _TimelineDateScrubberState extends State<TimelineDateScrubber> {
  static const double _gestureHitWidth = 88;
  static const double _visualGestureWidth = 56;
  static const double _handleWidth = 32;
  static const double _handleHeight = 52;
  static const double _bubbleWidth = 98;
  static const double _bubbleHeight = 58;
  static const double _yearRailWidth = 64;
  static const double _yearRailRowHeight = 26;
  static const int _maxYearRailRows = 7;
  static const Duration _hideDelay = Duration(milliseconds: 900);
  static const Duration _targetLoadDebounce = Duration(milliseconds: 180);
  static const Duration _visibilityTransitionDuration = Duration(
    milliseconds: 140,
  );

  Timer? _hideTimer;
  Timer? _targetLoadTimer;
  bool _isVisible = false;
  bool _isDragging = false;
  bool _isScrollable = false;
  bool _loadMoreInFlight = false;
  double _fraction = 0;
  double _dragHandleOffset = 0;
  int? _queuedLoadTargetIndex;
  double? _queuedLoadTargetFraction;
  int? _pendingLoadTargetIndex;
  double? _pendingLoadTargetFraction;
  int? _activePointer;
  bool _jumpFrameScheduled = false;
  int? _queuedJumpTargetIndex;
  double? _queuedJumpFraction;
  List<int> _timelineYears = const [];
  final Map<int, _ScrubberDateLabel> _dateLabelCache = {};
  late final ValueNotifier<_ScrubberVisualState> _visualState = ValueNotifier(
    _ScrubberVisualState(
      visible: _isVisible,
      dragging: _isDragging,
      fraction: _fraction,
    ),
  );

  List<DateTime> get _scrubberTimestamps {
    if (widget.timelineTimestamps.isNotEmpty) return widget.timelineTimestamps;
    return widget.cards.map((card) => card.timestamp).toList(growable: false);
  }

  bool get _hasEnoughCards => widget.enabled && _scrubberTimestamps.length > 1;

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
    if (oldWidget.cards != widget.cards ||
        oldWidget.timelineTimestamps != widget.timelineTimestamps) {
      _syncTimelineYears();
      _clearDateLabelCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncFractionFromScroll();
      });
    }
    if (oldWidget.localeName != widget.localeName) {
      _clearDateLabelCache();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _targetLoadTimer?.cancel();
    widget.scrollController.removeListener(_syncFractionFromScroll);
    _visualState.dispose();
    super.dispose();
  }

  void _publishVisualState() {
    final next = _ScrubberVisualState(
      visible: _isVisible,
      dragging: _isDragging,
      fraction: _fraction,
    );
    if (_visualState.value != next) {
      _visualState.value = next;
    }
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
        _publishVisualState();
      }
      return;
    }

    final pendingTargetFraction = _pendingLoadTargetFraction;
    if (_isDragging || pendingTargetFraction != null) {
      final nextFraction = pendingTargetFraction ?? _fraction;
      final scrollableChanged = !_isScrollable;
      final fractionChanged = (nextFraction - _fraction).abs() >= 0.002;
      if (scrollableChanged) {
        setState(() {
          _isScrollable = true;
          _fraction = nextFraction;
        });
        _publishVisualState();
      } else if (fractionChanged) {
        _fraction = nextFraction;
        _publishVisualState();
      }
      return;
    }

    final position = widget.scrollController.position;
    final scrollFraction = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final nextFraction = _fractionForLoadedScroll(scrollFraction);
    if (_isScrollable && (nextFraction - _fraction).abs() < 0.002) return;
    if (!_isScrollable) {
      setState(() {
        _isScrollable = true;
        _fraction = nextFraction;
      });
    } else {
      _fraction = nextFraction;
    }
    _publishVisualState();
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
      _isVisible = true;
      _publishVisualState();
    }
    if (!_isDragging) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || _isDragging) return;
      _isVisible = false;
      _publishVisualState();
    });
  }

  void _handlePointerDown(PointerDownEvent event, double height) {
    if (!_canScrub || _activePointer != null) return;
    final trackHeight = _trackHeight(height);
    if (trackHeight <= 0) return;

    _activePointer = event.pointer;
    _hideTimer?.cancel();
    _isDragging = true;
    _isVisible = true;

    final trackCenterY = _trackCenterYForFraction(_fraction, height);
    final handleCenterY = _handleCenterYForFraction(_fraction, height);
    final touchesHandle =
        (event.localPosition.dy - handleCenterY).abs() <= _handleHeight / 2;
    final handleIsClamped = (handleCenterY - trackCenterY).abs() > 0.5;
    final rawGrabOffset = event.localPosition.dy - trackCenterY;
    _dragHandleOffset = touchesHandle &&
            !handleIsClamped &&
            rawGrabOffset.abs() <= _handleHeight / 2
        ? rawGrabOffset
        : 0;

    if (!touchesHandle) {
      _fraction = _fractionForLocalY(event.localPosition.dy, height);
    }
    _publishVisualState();
    if (!touchesHandle) {
      _jumpToFraction(_fraction, loadImmediately: true);
    }
  }

  void _handlePointerMove(PointerMoveEvent event, double height) {
    if (event.pointer != _activePointer || !_canScrub) return;
    final trackHeight = _trackHeight(height);
    if (trackHeight <= 0) return;

    final nextFraction = _fractionForLocalY(
      event.localPosition.dy - _dragHandleOffset,
      height,
    );

    _isVisible = true;
    _fraction = nextFraction;
    _publishVisualState();
    _jumpToFraction(
      nextFraction,
      loadImmediately: false,
      jumpImmediately: false,
    );
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _endDrag();
  }

  void _endDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    _publishVisualState();
    _flushQueuedJump();
    _flushQueuedTargetLoad();
    _scheduleHide();
  }

  void _jumpToFraction(
    double fraction, {
    required bool loadImmediately,
    bool jumpImmediately = true,
  }) {
    final targetIndex = _indexForFraction(fraction);
    if (_shouldLoadToTarget(targetIndex)) {
      _rememberPendingLoadTarget(targetIndex, fraction);
    }
    if (jumpImmediately) {
      _jumpWithinLoadedExtent(targetIndex: targetIndex, fraction: fraction);
    } else {
      _queueJumpWithinLoadedExtent(
          targetIndex: targetIndex, fraction: fraction);
    }
    if (loadImmediately) {
      unawaited(_maybeLoadForTarget(targetIndex, fraction));
    } else {
      _queueLoadForTarget(targetIndex, fraction);
    }
  }

  double _fractionForLoadedScroll(double scrollFraction) {
    if (widget.timelineTimestamps.isEmpty || widget.cards.isEmpty) {
      return scrollFraction;
    }

    final loadedIndex = ((widget.cards.length - 1) * scrollFraction)
        .round()
        .clamp(0, widget.timelineTimestamps.length - 1);
    return loadedIndex / math.max(1, widget.timelineTimestamps.length - 1);
  }

  void _jumpWithinLoadedExtent({
    required int targetIndex,
    required double fraction,
  }) {
    final position = widget.scrollController.position;
    final loadedFraction = widget.timelineTimestamps.isNotEmpty
        ? (targetIndex / math.max(1, widget.cards.length - 1)).clamp(0.0, 1.0)
        : fraction;
    final target = (position.maxScrollExtent * loadedFraction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.scrollController.jumpTo(target);
  }

  void _queueJumpWithinLoadedExtent({
    required int targetIndex,
    required double fraction,
  }) {
    _queuedJumpTargetIndex = targetIndex;
    _queuedJumpFraction = fraction;
    if (_jumpFrameScheduled) return;

    _jumpFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _jumpFrameScheduled = false;
      _flushQueuedJump();
    });
  }

  void _flushQueuedJump() {
    final targetIndex = _queuedJumpTargetIndex;
    final fraction = _queuedJumpFraction;
    _queuedJumpTargetIndex = null;
    _queuedJumpFraction = null;
    if (!mounted ||
        targetIndex == null ||
        fraction == null ||
        !widget.scrollController.hasClients) {
      return;
    }

    _jumpWithinLoadedExtent(targetIndex: targetIndex, fraction: fraction);
  }

  bool _shouldLoadToTarget(int targetIndex) {
    return widget.hasMore &&
        widget.timelineTimestamps.isNotEmpty &&
        widget.onLoadToIndex != null &&
        targetIndex >= math.max(0, widget.cards.length - 1);
  }

  bool _shouldLoadNextPage() {
    return widget.hasMore &&
        widget.timelineTimestamps.isEmpty &&
        widget.onLoadMore != null &&
        _fraction >= 0.92;
  }

  void _queueLoadForTarget(int targetIndex, double fraction) {
    if (!_shouldLoadToTarget(targetIndex) && !_shouldLoadNextPage()) {
      return;
    }

    _queuedLoadTargetIndex = targetIndex;
    _queuedLoadTargetFraction = fraction;
    _targetLoadTimer?.cancel();
    _targetLoadTimer = Timer(_targetLoadDebounce, _flushQueuedTargetLoad);
  }

  void _flushQueuedTargetLoad() {
    _targetLoadTimer?.cancel();
    _targetLoadTimer = null;

    final targetIndex = _queuedLoadTargetIndex;
    final fraction = _queuedLoadTargetFraction;
    _queuedLoadTargetIndex = null;
    _queuedLoadTargetFraction = null;

    if (targetIndex == null || fraction == null) return;
    unawaited(_maybeLoadForTarget(targetIndex, fraction));
  }

  void _rememberPendingLoadTarget(int targetIndex, double fraction) {
    _pendingLoadTargetIndex = targetIndex;
    _pendingLoadTargetFraction = fraction;
  }

  void _clearPendingLoadTarget() {
    _pendingLoadTargetIndex = null;
    _pendingLoadTargetFraction = null;
  }

  void _restoreTargetAfterLoad({
    required int targetIndex,
    required double fraction,
  }) {
    if (!mounted || !widget.scrollController.hasClients) return;

    _fraction = fraction;
    _publishVisualState();
    _jumpWithinLoadedExtent(targetIndex: targetIndex, fraction: fraction);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      _jumpWithinLoadedExtent(targetIndex: targetIndex, fraction: fraction);
    });
  }

  Future<void> _maybeLoadForTarget(int targetIndex, double fraction) async {
    if (!widget.hasMore) {
      return;
    }

    final shouldLoadToTarget = _shouldLoadToTarget(targetIndex);
    final shouldLoadNextPage = !shouldLoadToTarget && _shouldLoadNextPage();

    if (!shouldLoadToTarget && !shouldLoadNextPage) return;

    if (_loadMoreInFlight) {
      if (shouldLoadToTarget) {
        _rememberPendingLoadTarget(targetIndex, fraction);
        _queuedLoadTargetIndex = targetIndex;
        _queuedLoadTargetFraction = fraction;
      }
      return;
    }

    if (shouldLoadToTarget) {
      _rememberPendingLoadTarget(targetIndex, fraction);
    }

    _loadMoreInFlight = true;
    try {
      if (shouldLoadToTarget) {
        await widget.onLoadToIndex!.call(targetIndex);
      } else {
        await widget.onLoadMore!.call();
      }
      if (mounted && widget.scrollController.hasClients) {
        if (shouldLoadToTarget) {
          _restoreTargetAfterLoad(
            targetIndex: _pendingLoadTargetIndex ?? targetIndex,
            fraction: _pendingLoadTargetFraction ?? fraction,
          );
        } else {
          _jumpWithinLoadedExtent(
            targetIndex: _indexForFraction(_fraction),
            fraction: _fraction,
          );
        }
      }
    } catch (e, st) {
      _logger.warning('Failed to load more cards from date scrubber', e, st);
    } finally {
      if (mounted) {
        _loadMoreInFlight = false;
        _clearPendingLoadTarget();
        final queuedTargetIndex = _queuedLoadTargetIndex;
        final queuedFraction = _queuedLoadTargetFraction;
        _queuedLoadTargetIndex = null;
        _queuedLoadTargetFraction = null;
        if (queuedTargetIndex != null && queuedFraction != null) {
          unawaited(_maybeLoadForTarget(queuedTargetIndex, queuedFraction));
        }
      }
    }
  }

  double _fractionForLocalY(double localY, double height) {
    final top = _trackTop(height);
    final trackHeight = _trackHeight(height);
    if (trackHeight <= 0) return 0;
    return ((localY - top) / trackHeight).clamp(0.0, 1.0);
  }

  double _trackCenterYForFraction(double fraction, double height) {
    return _trackTop(height) + _trackHeight(height) * fraction;
  }

  double _handleCenterYForFraction(double fraction, double height) {
    final top = _trackTop(height);
    final bottom = _trackBottom(height);
    final handleTop = _clampIntoTrack(
      value: _trackCenterYForFraction(fraction, height) - _handleHeight / 2,
      top: top,
      bottom: bottom,
      height: height,
      extent: _handleHeight,
    );
    return handleTop + _handleHeight / 2;
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

  int _indexForFraction(double fraction) {
    final timestamps = _scrubberTimestamps;
    if (timestamps.isEmpty) return 0;
    return ((timestamps.length - 1) * fraction).round().clamp(
          0,
          timestamps.length - 1,
        );
  }

  DateTime? _timestampForFraction(double fraction) {
    final timestamps = _scrubberTimestamps;
    if (timestamps.isEmpty) return null;
    return timestamps[_indexForFraction(fraction)];
  }

  _ScrubberDateLabel _dateLabelForFraction(double fraction) {
    final timestamps = _scrubberTimestamps;
    if (timestamps.isEmpty) {
      return _formatDateLabel(DateTime.now());
    }

    final index = _indexForFraction(fraction);
    return _dateLabelCache[index] ??= _formatDateLabel(timestamps[index]);
  }

  _ScrubberDateLabel _formatDateLabel(DateTime timestamp) {
    return _ScrubberDateLabel(
      year: _formatDate(timestamp, (locale) => DateFormat.y(locale)),
      day: _formatDate(timestamp, (locale) => DateFormat.MMMd(locale)),
    );
  }

  void _clearDateLabelCache() {
    _dateLabelCache.clear();
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
    for (final timestamp in _scrubberTimestamps) {
      years.add(timestamp.year);
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
            RepaintBoundary(child: widget.child),
            if (_hasEnoughCards && _isScrollable)
              Positioned.fill(
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ValueListenableBuilder<_ScrubberVisualState>(
                        valueListenable: _visualState,
                        builder: (context, visualState, _) {
                          return Stack(
                            children: [
                              IgnorePointer(
                                child: _buildScrubberVisuals(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  visualState: visualState,
                                ),
                              ),
                              Positioned(
                                key: timelineDateScrubberGestureKey,
                                top: 0,
                                right: 0,
                                bottom: 0,
                                width: math.min(
                                  _gestureHitWidth,
                                  constraints.maxWidth,
                                ),
                                child: IgnorePointer(
                                  ignoring: !visualState.visible &&
                                      !visualState.dragging,
                                  child: Listener(
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: (event) =>
                                        _handlePointerDown(
                                      event,
                                      constraints.maxHeight,
                                    ),
                                    onPointerMove: (event) =>
                                        _handlePointerMove(
                                      event,
                                      constraints.maxHeight,
                                    ),
                                    onPointerUp: _handlePointerEnd,
                                    onPointerCancel: _handlePointerEnd,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
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
    required _ScrubberVisualState visualState,
  }) {
    final top = _trackTop(height);
    final bottom = _trackBottom(height);
    final trackHeight = _trackHeight(height);
    final fraction = visualState.fraction;
    final centerY = top + trackHeight * fraction;
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
    final label = _dateLabelForFraction(fraction);
    final visualGestureWidth = math.min(_visualGestureWidth, width);
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
    final activeYear = _timestampForFraction(fraction)?.year;
    final showYearRail = visualState.dragging &&
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
      offset: visualState.visible ? Offset.zero : const Offset(0.18, 0),
      duration:
          visualState.dragging ? Duration.zero : _visibilityTransitionDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        key: timelineDateScrubberOverlayKey,
        opacity: visualState.visible ? 1 : 0,
        duration: visualState.dragging
            ? Duration.zero
            : _visibilityTransitionDuration,
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

class _ScrubberVisualState {
  const _ScrubberVisualState({
    required this.visible,
    required this.dragging,
    required this.fraction,
  });

  final bool visible;
  final bool dragging;
  final double fraction;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ScrubberVisualState &&
            other.visible == visible &&
            other.dragging == dragging &&
            other.fraction == fraction;
  }

  @override
  int get hashCode => Object.hash(visible, dragging, fraction);
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
        child: Transform.scale(
          scale: active ? 1 : 0.88,
          alignment: Alignment.center,
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
