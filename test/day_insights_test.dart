import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/day_insights.dart';
import 'package:harvest/models/entry_display.dart';
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

  group('placedSpanOf', () {
    /// `GrainCalendar_…` for a meeting starting at [hour]:[minute] local time
    /// on 12 Oct 2026.
    String meetingRef(int hour, int minute, {int day = 12}) {
      final epoch =
          DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch ~/ 1000;
      return 'GrainCalendar_0123456789abcdef_$epoch';
    }

    TimeEntry entry({
      String? refId,
      double hours = 0.5,
      String? started,
      String? ended,
      String? notes = 'CRT Daily Scrum',
    }) =>
        TimeEntry(
          id: 1,
          spentDate: '2026-10-12',
          hours: hours,
          notes: notes,
          projectId: 7,
          projectName: 'P',
          taskId: 9,
          taskName: 'Meetings',
          startedTime: started,
          endedTime: ended,
          externalReference: refId == null
              ? null
              : ExternalReference(id: refId, groupId: 'GrainCalendar'),
        );

    test('a meeting reference places the entry for its hours', () {
      final span = placedSpanOf(entry(refId: meetingRef(9, 0), hours: 0.5));
      expect(span, isNotNull);
      expect(span!.start, 9 * 60);
      expect(span.end, 9 * 60 + 30);
      expect(span.key, '7:9');
      expect(span.label, 'CRT Daily Scrum');
      expect(span.fromCalendar, isTrue);
    });

    test('clock times win over the meeting reference', () {
      final span = placedSpanOf(entry(
        refId: meetingRef(9, 0),
        started: '2:00pm',
        ended: '3:00pm',
      ));
      expect(span!.start, 14 * 60);
      expect(span.end, 15 * 60);
      expect(span.fromCalendar, isFalse);
    });

    test('a malformed or foreign reference is not placed', () {
      expect(placedSpanOf(entry(refId: 'GrainCalendar_0123_1791966600')),
          isNull);
      expect(placedSpanOf(entry(refId: 'GrainCalendar_0123456789abcdef_x')),
          isNull);
      expect(placedSpanOf(entry(refId: 'AzureDevOps_guid_Task_13222')),
          isNull);
      expect(placedSpanOf(entry()), isNull);
    });

    test('a meeting outside the entry’s day is not placed', () {
      // The slot is on the 11th but the entry was logged on the 12th.
      expect(placedSpanOf(entry(refId: meetingRef(9, 0, day: 11))), isNull);
      // Running past midnight.
      expect(placedSpanOf(entry(refId: meetingRef(23, 30), hours: 1)),
          isNull);
      // Zero length.
      expect(placedSpanOf(entry(refId: meetingRef(9, 0), hours: 0)), isNull);
    });

    test('the label falls back to the task without notes', () {
      expect(placedSpanOf(entry(refId: meetingRef(9, 0), notes: null))!.label,
          'Meetings');
    });
  });

  group('partial days', () {
    // Three meetings placed — 9:00–9:30, 12:00–13:00, 16:00–16:30 — and
    // 3h logged by duration.
    final meetings = [
      InsightSpan(start: 9 * 60, end: 9 * 60 + 30, key: 'a', label: 'Scrum'),
      InsightSpan(start: 12 * 60, end: 13 * 60, key: 'b', label: 'Planning'),
      InsightSpan(start: 16 * 60, end: 16 * 60 + 30, key: 'a', label: 'Sync'),
    ];

    DayInsights partial({int unplaced = 180}) => computeDayInsights(
          spans: meetings,
          windowStart: dayStart,
          windowEnd: dayEnd,
          minGapMinutes: 15,
          unplacedMinutes: unplaced,
        );

    test('placement says which kind of day it is', () {
      expect(partial().placement, DayPlacement.partial);
      expect(partial(unplaced: 0).placement, DayPlacement.full);
      expect(
          computeDayInsights(
            spans: const [],
            windowStart: dayStart,
            windowEnd: dayEnd,
            minGapMinutes: 15,
            unplacedMinutes: 180,
          ).placement,
          DayPlacement.none);
    });

    test('open stretches are the gaps between placed spans', () {
      final result = partial();
      expect(result.workedMinutes, 120);
      expect(result.openMinutes, 510 - 120);
      expect(
        result.gaps.map((g) => (g.start, g.end)).toList(),
        [
          (dayStart, 9 * 60),
          (9 * 60 + 30, 12 * 60),
          (13 * 60, 16 * 60),
          (16 * 60 + 30, dayEnd),
        ],
      );
      expect(result.longestGapMinutes, 180);
    });

    test('a gap names the spans either side of it', () {
      final gaps = partial().gaps;
      expect(gaps.first.previous, isNull);
      expect(gaps.first.next!.label, 'Scrum');
      expect(gaps[1].previous!.label, 'Scrum');
      expect(gaps[1].next!.label, 'Planning');
      expect(gaps.last.previous!.label, 'Sync');
      expect(gaps.last.next, isNull);
    });

    test('the span ending an overlap names the gap after it', () {
      final result = computeDayInsights(
        spans: [
          InsightSpan(start: 9 * 60, end: 10 * 60, label: 'Long'),
          InsightSpan(start: 9 * 60 + 15, end: 9 * 60 + 45, label: 'Inside'),
          InsightSpan(start: 9 * 60 + 30, end: 10 * 60 + 30, label: 'Late'),
        ],
        windowStart: dayStart,
        windowEnd: dayEnd,
        minGapMinutes: 15,
      );
      expect(result.gaps.last.previous!.label, 'Late');
    });

    test('unplaced minutes count as logged, and dead time from totals', () {
      final result = partial();
      expect(result.unplacedMinutes, 180);
      expect(result.loggedMinutes, 300);
      // 510 window − 120 placed − 180 unplaced.
      expect(result.deadMinutes, 210);
      expect(result.productivity, closeTo(300 / 510, 1e-9));
    });

    test('placed overlaps are merged before the totals', () {
      final result = computeDayInsights(
        spans: [
          InsightSpan(start: 9 * 60, end: 10 * 60),
          InsightSpan(start: 9 * 60 + 30, end: 10 * 60 + 30),
        ],
        windowStart: dayStart,
        windowEnd: dayEnd,
        minGapMinutes: 15,
        unplacedMinutes: 60,
      );
      expect(result.workedMinutes, 90);
      expect(result.deadMinutes, 510 - 90 - 60);
    });

    test('dead time floors at zero when more is logged than the window', () {
      expect(partial(unplaced: 600).deadMinutes, 0);
      expect(partial(unplaced: 600).productivity, 1.0);
    });

    test('context switches only count on a fully timed day', () {
      expect(partial().contextSwitches, 0);
      expect(partial(unplaced: 0).contextSwitches, 2);
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
