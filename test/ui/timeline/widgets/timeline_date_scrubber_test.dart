import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/timeline/widgets/timeline_date_scrubber.dart';

void main() {
  group('TimelineDateScrubber', () {
    testWidgets('does not render scrubber controls without enough cards', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: [_card(0)]);

      expect(find.byKey(timelineDateScrubberOverlayKey), findsNothing);
      expect(find.byKey(timelineDateScrubberGestureKey), findsNothing);
      expect(find.byKey(timelineDateScrubberHandleKey), findsNothing);
    });

    testWidgets('stays inert when content is not scrollable', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(2));

      expect(find.byKey(timelineDateScrubberOverlayKey), findsNothing);
      expect(find.byKey(timelineDateScrubberGestureKey), findsNothing);
      expect(controller.offset, 0);
    });

    testWidgets('renders with two cards once the content is scrollable', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(2),
        height: 120,
        itemExtent: 96,
      );
      await _revealScrubber(tester);

      expect(find.byKey(timelineDateScrubberOverlayKey), findsOneWidget);
      expect(find.byKey(timelineDateScrubberHandleKey), findsOneWidget);
    });

    testWidgets('does not render scrubber controls when disabled', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(40),
        enabled: false,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump();

      expect(find.byKey(timelineDateScrubberOverlayKey), findsNothing);
      expect(find.byKey(timelineDateScrubberGestureKey), findsNothing);
    });

    testWidgets('does not jump from an invisible right-edge tap', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(40));

      final overlay = tester.widget<AnimatedOpacity>(
        find.byKey(timelineDateScrubberOverlayKey),
      );
      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );

      expect(overlay.opacity, 0);
      await tester.tapAt(gestureArea.center);
      await tester.pump();

      expect(controller.offset, 0);
    });

    testWidgets('shows date overlay while the timeline scrolls', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(20));

      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump();

      final overlay = tester.widget<AnimatedOpacity>(
        find.byKey(timelineDateScrubberOverlayKey),
      );
      expect(overlay.opacity, 1);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('hides the overlay after scrolling stops', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(40));
      await _revealScrubber(tester);

      expect(_overlayOpacity(tester), 1);

      await tester.pump(const Duration(milliseconds: 1040));

      expect(_overlayOpacity(tester), 0);
    });

    testWidgets('dragging the handle jumps to older dates', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(180));
      await _revealScrubber(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.dragFrom(
        gestureArea.topCenter + const Offset(0, 24),
        Offset(0, gestureArea.height - 72),
      );
      await tester.pump();

      expect(
        controller.offset,
        greaterThan(controller.position.maxScrollExtent * 0.7),
      );
      expect(find.text('2025'), findsOneWidget);
    });

    testWidgets('clamps drags beyond the top and bottom of the track', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(180));
      await _revealScrubber(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      controller.jumpTo(controller.position.maxScrollExtent * 0.5);
      await tester.pump();

      await tester.dragFrom(gestureArea.center, const Offset(0, -5000));
      await tester.pump();

      expect(controller.offset, 0);

      await _revealScrubber(tester);
      await tester.dragFrom(gestureArea.center, const Offset(0, 5000));
      await tester.pump();

      expect(controller.offset, controller.position.maxScrollExtent);
    });

    testWidgets('keeps the overlay visible while dragging', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(180));
      await _revealScrubber(tester);

      final start = tester
          .getRect(find.byKey(timelineDateScrubberGestureKey))
          .topRight
          .translate(-20, 32);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(_overlayOpacity(tester), 1);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1040));

      expect(_overlayOpacity(tester), 0);
    });

    testWidgets('moving the drag left slows vertical scrubbing', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(180));
      await _revealScrubber(tester);

      final start = tester
          .getRect(find.byKey(timelineDateScrubberGestureKey))
          .topRight
          .translate(-20, 32);

      final fastGesture = await tester.startGesture(start);
      await fastGesture.moveBy(const Offset(0, 20));
      await fastGesture.moveBy(const Offset(0, 220));
      await fastGesture.up();
      await tester.pump();
      final fastOffset = controller.offset;

      controller.jumpTo(0);
      await tester.pump();

      final slowGesture = await tester.startGesture(start);
      await slowGesture.moveBy(const Offset(0, 20));
      await slowGesture.moveBy(const Offset(-220, 0));
      await slowGesture.moveBy(const Offset(0, 220));
      await slowGesture.up();
      await tester.pump();
      final slowOffset = controller.offset;

      expect(slowOffset, lessThan(fastOffset * 0.6));
      expect(slowOffset, greaterThan(0));
    });

    testWidgets('shows year rail while dragging across multiple years', (
      tester,
    ) async {
      final controller = ScrollController();
      final cards = _cardsWithDates(
        900,
        (index) => DateTime(2026, 12, 31).subtract(Duration(days: index * 7)),
      );

      await _pumpScrubber(tester, controller: controller, cards: cards);
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      final gesture = await tester.startGesture(
        gestureArea.topCenter + const Offset(0, 24),
      );
      await gesture.moveBy(const Offset(0, 240));
      await tester.pump();

      expect(find.byKey(timelineDateScrubberYearRailKey), findsOneWidget);
      _expectInsideHorizontalViewport(
        tester.getRect(find.byKey(timelineDateScrubberYearRailKey)),
        390,
      );

      final activeYearText = tester.widget<Text>(
        find.byKey(timelineDateScrubberActiveYearKey),
      );
      expect(activeYearText.style?.fontWeight, FontWeight.w800);
      expect(activeYearText.style?.fontSize, 18);

      await gesture.up();
      await tester.pump();

      expect(find.byKey(timelineDateScrubberYearRailKey), findsNothing);
    });

    testWidgets('does not show year rail for a single-year timeline', (
      tester,
    ) async {
      final controller = ScrollController();
      final cards = _cardsWithDates(300, (_) => DateTime(2026, 12, 31));

      await _pumpScrubber(tester, controller: controller, cards: cards);
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      final gesture = await tester.startGesture(
        gestureArea.topCenter + const Offset(0, 24),
      );
      await gesture.moveBy(const Offset(0, 240));
      await tester.pump();

      expect(find.byKey(timelineDateScrubberYearRailKey), findsNothing);

      await gesture.up();
    });

    testWidgets('handles a very large card set across a huge date range', (
      tester,
    ) async {
      final controller = ScrollController();
      final cards = _cardsWithDates(
        10000,
        (index) => DateTime(2099, 12, 31).subtract(Duration(days: index * 7)),
      );

      await _pumpScrubber(tester, controller: controller, cards: cards);
      await _revealScrubber(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();

      expect(
        controller.offset,
        controller.position.maxScrollExtent,
      );
      expect(find.text(cards.last.timestamp.year.toString()), findsOneWidget);
    });

    testWidgets('handles many records on the same date without label churn', (
      tester,
    ) async {
      final controller = ScrollController();
      final cards = _cardsWithDates(300, (_) => DateTime(2026, 12, 31));

      await _pumpScrubber(tester, controller: controller, cards: cards);
      await _revealScrubber(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.dragFrom(
        gestureArea.topCenter + const Offset(0, 24),
        Offset(0, gestureArea.height - 72),
      );
      await tester.pump();

      expect(find.text('2026'), findsOneWidget);
      expect(find.textContaining('Dec'), findsOneWidget);
    });

    testWidgets('falls back when locale date data is unavailable', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(180),
        localeName: 'not-a-real-locale',
      );
      await _revealScrubber(tester);

      expect(find.text('2026'), findsOneWidget);
      expect(find.textContaining('May'), findsOneWidget);
    });

    testWidgets('requests more cards when the scrub reaches the bottom', (
      tester,
    ) async {
      final controller = ScrollController();
      var loadMoreCalls = 0;

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(40),
        hasMore: true,
        onLoadMore: () async {
          loadMoreCalls++;
        },
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();

      expect(loadMoreCalls, 1);
    });

    testWidgets('recovers if loadMore fails while scrubbing at the bottom', (
      tester,
    ) async {
      final controller = ScrollController();
      var loadMoreCalls = 0;

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(40),
        hasMore: true,
        onLoadMore: () async {
          loadMoreCalls++;
          if (loadMoreCalls == 1) {
            throw StateError('temporary failure');
          }
        },
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();

      expect(loadMoreCalls, 2);
    });

    testWidgets('does not duplicate loadMore while one is in flight', (
      tester,
    ) async {
      final controller = ScrollController();
      final loadMoreCompleter = Completer<void>();
      var loadMoreCalls = 0;

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(40),
        hasMore: true,
        onLoadMore: () {
          loadMoreCalls++;
          return loadMoreCompleter.future;
        },
      );
      await _revealScrubber(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();
      await tester.tapAt(gestureArea.bottomCenter - const Offset(0, 8));
      await tester.pump();

      expect(loadMoreCalls, 1);

      loadMoreCompleter.complete();
      await tester.pump();
    });

    testWidgets('hides controls when cards shrink below scrubber threshold', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(tester, controller: controller, cards: _cards(40));
      await _revealScrubber(tester);

      expect(find.byKey(timelineDateScrubberOverlayKey), findsOneWidget);

      controller.jumpTo(0);
      await _pumpScrubber(tester, controller: controller, cards: [_card(0)]);
      await tester.pump();

      expect(find.byKey(timelineDateScrubberOverlayKey), findsNothing);
      expect(find.byKey(timelineDateScrubberGestureKey), findsNothing);
    });

    testWidgets('does not throw in an unusually small viewport', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(20),
        width: 140,
        height: 32,
        itemExtent: 80,
      );
      await _revealScrubber(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(timelineDateScrubberOverlayKey), findsOneWidget);
    });

    testWidgets('keeps bubble and handle inside a narrow phone viewport', (
      tester,
    ) async {
      final controller = ScrollController();
      const width = 160.0;

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(60),
        width: width,
        height: 568,
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      _expectInsideHorizontalViewport(
        tester.getRect(find.byKey(timelineDateScrubberBubbleKey)),
        width,
      );
      _expectInsideHorizontalViewport(
        tester.getRect(find.byKey(timelineDateScrubberHandleKey)),
        width,
      );
    });

    testWidgets('keeps scrubbing usable in compact landscape', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(120),
        width: 844,
        height: 390,
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.dragFrom(
        gestureArea.topCenter + const Offset(0, 24),
        Offset(0, gestureArea.height - 72),
      );
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      expect(find.byKey(timelineDateScrubberBubbleKey), findsOneWidget);
    });

    testWidgets('keeps scrubbing usable on a tablet viewport', (tester) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(240),
        width: 1024,
        height: 1366,
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      await tester.tapAt(gestureArea.centerRight - const Offset(8, 0));
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      _expectInsideHorizontalViewport(
        tester.getRect(find.byKey(timelineDateScrubberBubbleKey)),
        1024,
      );
    });

    testWidgets('hides the bubble but keeps the handle on ultra narrow panes', (
      tester,
    ) async {
      final controller = ScrollController();

      await _pumpScrubber(
        tester,
        controller: controller,
        cards: _cards(60),
        width: 96,
        height: 480,
      );
      await _revealScrubber(tester);
      await _settleScrubberEntrance(tester);

      expect(find.byKey(timelineDateScrubberBubbleKey), findsNothing);
      expect(find.byKey(timelineDateScrubberHandleKey), findsOneWidget);

      final gestureArea = tester.getRect(
        find.byKey(timelineDateScrubberGestureKey),
      );
      final gesture = await tester.startGesture(
        gestureArea.topCenter + const Offset(0, 24),
      );
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();

      expect(find.byKey(timelineDateScrubberYearRailKey), findsNothing);
      expect(controller.offset, greaterThan(0));

      await gesture.up();
    });
  });
}

Future<void> _pumpScrubber(
  WidgetTester tester, {
  required ScrollController controller,
  required List<TimelineCardModel> cards,
  bool hasMore = false,
  Future<void> Function()? onLoadMore,
  String localeName = 'en',
  bool enabled = true,
  double width = 390,
  double height = 640,
  double itemExtent = 72,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: TimelineDateScrubber(
            cards: cards,
            scrollController: controller,
            hasMore: hasMore,
            onLoadMore: onLoadMore,
            localeName: localeName,
            enabled: enabled,
            trackInsets: const EdgeInsets.symmetric(vertical: 20),
            child: ListView.builder(
              controller: controller,
              itemExtent: itemExtent,
              itemCount: cards.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(cards[index].id),
                  subtitle: Text(cards[index].timestamp.toIso8601String()),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _revealScrubber(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -24));
  await tester.pump();
}

Future<void> _settleScrubberEntrance(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 180));
}

double _overlayOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(find.byKey(timelineDateScrubberOverlayKey))
      .opacity;
}

void _expectInsideHorizontalViewport(Rect rect, double width) {
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
}

List<TimelineCardModel> _cards(int count) {
  return List.generate(count, _card);
}

List<TimelineCardModel> _cardsWithDates(
  int count,
  DateTime Function(int index) timestampForIndex,
) {
  return List.generate(count, (index) {
    return _card(index, timestamp: timestampForIndex(index));
  });
}

TimelineCardModel _card(int index, {DateTime? timestamp}) {
  return TimelineCardModel(
    id: 'card-$index',
    timestamp:
        timestamp ?? DateTime(2026, 5, 14).subtract(Duration(days: index * 2)),
    tags: const [],
    status: 'done',
    title: 'Card $index',
    uiConfigs: const [],
  );
}
