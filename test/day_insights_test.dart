import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/day_insights.dart';
import 'package:harvest/models/time_entry.dart';

/// 08:30 and 17:00 — the app's default work day.
const dayStart = 8 * 60 + 30;
const dayEnd = 17 * 60;

InsightSpan span(int startHour, int startMin, int endHour, int endMin,
        {String key = 'a'}) =>
    InsightSpan(
      start: startHour * 60 + startMin,
      end: endHour * 60 + endMin,
      key: key,
    );

DayInsights compute(List<InsightSpan> spans,
        {int start = dayStart, int end = dayEnd, int minGap = 15}) =>
    computeDayInsights(
      spans: spans,
      windowStart: start,
      windowEnd: end,
      minGapMinutes: minGap,
    );

void main() {
  group('computeDayInsights', () {
    test('a fully covered day has no gaps and no dead time', () {
      final result = compute([span(8, 30, 17, 0)]);
      expect(result.workedMinutes, 510);
      expect(result.deadMinutes, 0);
      expect(result.gaps, isEmpty);
      expect(result.productivity, 1.0);
    });

    test('finds a gap between two blocks', () {
      final result = compute([span(8, 30, 10, 0), span(11, 0, 17, 0)]);
      expect(result.gaps.length, 1);
      expect(result.gaps.single.start, 10 * 60);
      expect(result.gaps.single.end, 11 * 60);
      expect(result.gaps.single.minutes, 60);
      expect(result.longestGapMinutes, 60);
      expect(result.workedMinutes, 90 + 360);
      expect(result.deadMinutes, 60);
    });

    test('gaps below the threshold are excluded but still count as dead', () {
      final result =
          compute([span(8, 30, 12, 0), span(12, 5, 17, 0)], minGap: 15);
      expect(result.gaps, isEmpty, reason: '5m is under the 15m threshold');
      expect(result.deadMinutes, 5, reason: 'dead time counts every gap');
      expect(result.longestGapMinutes, 0);
    });

    test('overlapping entries are merged, not double-counted', () {
      final result = compute([span(9, 0, 12, 0), span(10, 0, 11, 0)]);
      expect(result.workedMinutes, 180);
      expect(result.spanCount, 2, reason: 'both entries are still counted');
    });

    test('back-to-back entries leave no gap', () {
      final result = compute([span(9, 0, 10, 0), span(10, 0, 11, 0)]);
      final between =
          result.gaps.where((g) => g.start >= 10 * 60 && g.end <= 11 * 60);
      expect(between, isEmpty);
    });

    test('entries outside the window are clamped', () {
      final result = compute([span(7, 0, 18, 0)]);
      expect(result.workedMinutes, 510, reason: 'clamped to 08:30–17:00');
      expect(result.deadMinutes, 0);
    });

    test('an entry entirely outside the window is dropped', () {
      final result = compute([span(6, 0, 7, 0)]);
      expect(result.spanCount, 0);
      expect(result.workedMinutes, 0);
      expect(result.deadMinutes, 510);
    });

    test('leading and trailing gaps are reported', () {
      final result = compute([span(10, 0, 12, 0)]);
      expect(result.gaps.length, 2);
      expect(result.gaps.first.start, dayStart);
      expect(result.gaps.first.end, 10 * 60);
      expect(result.gaps.last.start, 12 * 60);
      expect(result.gaps.last.end, dayEnd);
    });

    test('a window ending at now does not count the rest of the day as dead',
        () {
      // Same entries, but the day is only measured up to 12:00.
      final full = compute([span(8, 30, 11, 0)]);
      final soFar = compute([span(8, 30, 11, 0)], end: 12 * 60);
      expect(full.deadMinutes, 360);
      expect(soFar.deadMinutes, 60);
    });

    test('context switches count project/task changes, not entry count', () {
      final result = compute([
        span(9, 0, 10, 0, key: 'p1'),
        span(10, 0, 11, 0, key: 'p1'),
        span(11, 0, 12, 0, key: 'p2'),
        span(12, 0, 13, 0, key: 'p1'),
      ]);
      expect(result.contextSwitches, 2);
      expect(result.spanCount, 4);
    });

    test('average session uses worked time over span count', () {
      final result = compute([span(9, 0, 10, 0), span(11, 0, 13, 0)]);
      expect(result.avgSessionMinutes, 90);
    });

    test('an empty day is all dead time', () {
      final result = compute([]);
      expect(result.workedMinutes, 0);
      expect(result.deadMinutes, 510);
      expect(result.gaps.length, 1);
      expect(result.productivity, 0);
      expect(result.avgSessionMinutes, 0);
    });

    test('a zero-length window returns the empty result', () {
      final result = compute([span(9, 0, 10, 0)], start: 540, end: 540);
      expect(result.windowMinutes, 0);
      expect(result.productivity, 0);
    });

    test('unsorted input is handled', () {
      final result = compute([span(14, 0, 15, 0), span(9, 0, 10, 0)]);
      expect(result.gaps.map((g) => g.minutes), [30, 240, 120]);
    });
  });

  group('parseClockMinutes', () {
    test('parses the Harvest 12-hour formats', () {
      expect(parseClockMinutes('8:30am'), 8 * 60 + 30);
      expect(parseClockMinutes('8:30 AM'), 8 * 60 + 30);
      expect(parseClockMinutes('3:00pm'), 15 * 60);
      expect(parseClockMinutes('12:00am'), 0);
      expect(parseClockMinutes('12:30pm'), 12 * 60 + 30);
      expect(parseClockMinutes('9am'), 9 * 60);
    });

    test('parses 24-hour times', () {
      expect(parseClockMinutes('08:30'), 8 * 60 + 30);
      expect(parseClockMinutes('17:05'), 17 * 60 + 5);
      expect(parseClockMinutes('0:00'), 0);
    });

    test('returns null for missing or malformed values', () {
      expect(parseClockMinutes(null), isNull);
      expect(parseClockMinutes(''), isNull);
      expect(parseClockMinutes('not a time'), isNull);
      expect(parseClockMinutes('25:00'), isNull);
      expect(parseClockMinutes('8:75'), isNull);
      expect(parseClockMinutes('13:00pm'), isNull);
    });
  });

  group('TimeEntry spans', () {
    TimeEntry entry({String? started, String? ended}) => TimeEntry(
          id: 1,
          spentDate: '2026-08-17',
          hours: 1,
          projectId: 7,
          projectName: 'P',
          taskId: 9,
          taskName: 'T',
          startedTime: started,
          endedTime: ended,
        );

    test('an entry with both times becomes a keyed span', () {
      final span = entry(started: '8:30am', ended: '10:00am').span;
      expect(span, isNotNull);
      expect(span!.start, 8 * 60 + 30);
      expect(span.end, 10 * 60);
      expect(span.key, '7:9');
    });

    test('duration-only entries have no span', () {
      expect(entry().span, isNull);
      expect(entry().hasClockTimes, isFalse);
      expect(entry(started: '8:30am').span, isNull);
    });

    test('an entry ending at or before its start is dropped', () {
      expect(entry(started: '5:00pm', ended: '9:00am').span, isNull);
      expect(entry(started: '9:00am', ended: '9:00am').span, isNull);
    });
  });

  group('formatting', () {
    test('formatDuration drops empty parts and floors at zero', () {
      expect(formatDuration(0), '0m');
      expect(formatDuration(45), '45m');
      expect(formatDuration(60), '1h');
      expect(formatDuration(135), '2h 15m');
      expect(formatDuration(-30), '0m');
    });

    test('formatClock pads to HH:mm', () {
      expect(formatClock(8 * 60 + 5), '08:05');
      expect(formatClock(17 * 60), '17:00');
    });
  });
}
