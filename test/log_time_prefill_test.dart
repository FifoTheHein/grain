import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/day_insights.dart';
import 'package:harvest/models/log_time_prefill.dart';

void main() {
  final date = DateTime(2026, 10, 12);
  const scrum = InsightSpan(start: 540, end: 560, label: 'CRT Daily Scrum');
  const planning =
      InsightSpan(start: 870, end: 900, label: 'Release Planning');
  // 09:20–14:30, 5h 10m.
  const slot = InsightGap(560, 870, previous: scrum, next: planning);

  group('prefillForSlot on a duration account', () {
    test('caps the slot at what is left unlogged', () {
      final p = prefillForSlot(
        date: date,
        gap: slot,
        tracksByStartEnd: false,
        unloggedMinutes: 95,
      )!;
      expect(p.startEnd, isFalse);
      expect(p.minutes, 95);
      expect(p.date, date);
      expect(p.origin, 'open after CRT Daily Scrum');
    });

    test('takes the whole slot when more than that is unlogged', () {
      final p = prefillForSlot(
        date: date,
        gap: slot,
        tracksByStartEnd: false,
        unloggedMinutes: 400,
      )!;
      expect(p.minutes, 310);
    });

    test('offers nothing once the goal is logged', () {
      for (final unlogged in [0, -30]) {
        expect(
          prefillForSlot(
            date: date,
            gap: slot,
            tracksByStartEnd: false,
            unloggedMinutes: unlogged,
          ),
          isNull,
          reason: '$unlogged',
        );
      }
    });
  });

  group('prefillForSlot on a start/end account', () {
    test('hands over the slot itself with captions', () {
      final p = prefillForSlot(
        date: date,
        gap: slot,
        tracksByStartEnd: true,
        unloggedMinutes: 0,
      )!;
      expect(p.startEnd, isTrue);
      expect(p.start, 560);
      expect(p.end, 870);
      expect(p.startCaption, 'after CRT Daily Scrum');
      expect(p.endCaption, 'before Release Planning');
    });

    test('a stretch opening or closing the day has one caption', () {
      final opening = prefillForSlot(
        date: date,
        gap: const InsightGap(510, 540, next: scrum),
        tracksByStartEnd: true,
        unloggedMinutes: 60,
      )!;
      expect(opening.startCaption, isNull);
      expect(opening.endCaption, 'before CRT Daily Scrum');
      expect(opening.origin, 'open before CRT Daily Scrum');

      final closing = prefillForSlot(
        date: date,
        gap: const InsightGap(900, 1020, previous: planning),
        tracksByStartEnd: true,
        unloggedMinutes: 60,
      )!;
      expect(closing.startCaption, 'after Release Planning');
      expect(closing.endCaption, isNull);
    });
  });

  test('slotOrigin falls back to the clock times', () {
    expect(slotOrigin(const InsightGap(510, 540)), 'open 08:30–09:00');
  });
}
