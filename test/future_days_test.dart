import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/future_days.dart';

void main() {
  // A Monday, mid-afternoon.
  final now = DateTime(2026, 10, 12, 15, 40);

  group('the week-ahead cap', () {
    test('is today + 7 days, at midnight', () {
      expect(kMaxDaysAhead, 7);
      expect(latestSelectableDate(now), DateTime(2026, 10, 19));
    });

    test('crosses a month end by the calendar, not by hours', () {
      expect(latestSelectableDate(DateTime(2026, 10, 28, 23, 59)),
          DateTime(2026, 11, 4));
      expect(latestSelectableDate(DateTime(2026, 12, 30)), DateTime(2027, 1, 6));
    });

    test('lands on the right day across a DST change', () {
      // Europe and the US move clocks in late March / early November; a
      // Duration-based cap would land an hour short in either direction.
      final march = DateTime(2026, 3, 25, 0, 30);
      expect(latestSelectableDate(march), DateTime(2026, 4, 1));
      expect(daysFromToday(DateTime(2026, 4, 1), march), 7);
    });

    test('allows up to the cap and nothing past it', () {
      expect(isSelectableDay(DateTime(2026, 10, 19, 23, 59), now), isTrue);
      expect(isSelectableDay(DateTime(2026, 10, 20), now), isFalse);
      expect(isSelectableDay(DateTime(2020, 1, 1), now), isTrue);
    });

    test('clamps a picker start date into range', () {
      expect(clampToSelectable(DateTime(2026, 11, 30), now),
          DateTime(2026, 10, 19));
      final ok = DateTime(2026, 10, 14);
      expect(clampToSelectable(ok, now), ok);
    });
  });

  group('future days', () {
    test('tomorrow onwards is future; later today is not', () {
      expect(isFutureDay(DateTime(2026, 10, 12, 23, 59), now), isFalse);
      expect(isFutureDay(DateTime(2026, 10, 13), now), isTrue);
      expect(isFutureDay(DateTime(2026, 10, 11), now), isFalse);
    });

    test('reads a spent_date', () {
      expect(isFutureSpentDate('2026-10-13', now), isTrue);
      expect(isFutureSpentDate('2026-10-12', now), isFalse);
      expect(isFutureSpentDate('not a date', now), isFalse);
    });

    test('counts calendar days either way', () {
      expect(daysFromToday(DateTime(2026, 10, 12), now), 0);
      expect(daysFromToday(DateTime(2026, 10, 15), now), 3);
      expect(daysFromToday(DateTime(2026, 10, 9), now), -3);
    });
  });

  group('Recent header labels', () {
    test('today', () {
      final h = dayHeading(DateTime(2026, 10, 12), now);
      expect(h.title, 'Today');
      expect(h.subtitle, 'Mon 12 Oct 2026');
      expect(h.upcoming, isFalse);
      expect(h.isToday, isTrue);
    });

    test('tomorrow, upcoming, without a count', () {
      final h = dayHeading(DateTime(2026, 10, 13), now);
      expect(h.title, 'Tomorrow');
      expect(h.subtitle, 'Tue 13 Oct 2026');
      expect(h.upcoming, isTrue);
      expect(h.isToday, isFalse);
    });

    test('the weekday and "in N days" from two days out', () {
      final h = dayHeading(DateTime(2026, 10, 15), now);
      expect(h.title, 'Thursday');
      expect(h.subtitle, 'Thu 15 Oct 2026 · in 3 days');
      expect(h.upcoming, isTrue);
      expect(dayHeading(DateTime(2026, 10, 14), now).subtitle,
          'Wed 14 Oct 2026 · in 2 days');
      expect(dayHeading(DateTime(2026, 10, 19), now).subtitle,
          'Mon 19 Oct 2026 · in 7 days');
    });

    test('a past day is its weekday, not upcoming', () {
      final h = dayHeading(DateTime(2026, 10, 9), now);
      expect(h.title, 'Friday');
      expect(h.subtitle, 'Fri 9 Oct 2026');
      expect(h.upcoming, isFalse);
    });
  });
}
