/// How far ahead time can be logged, and how a day is named relative to
/// today.
///
/// Pure Dart. Every screen that lets you choose a date (Recent's arrows,
/// week strip and picker, Log Time's chips, Edit Time's picker) asks
/// [latestSelectableDate] rather than computing its own cap. Insights stays
/// at today. Unit tested in `test/future_days_test.dart`.
library;

import 'package:intl/intl.dart';

/// How many days past today can be chosen: a week, enough for leave or a
/// workshop you already know about, not so much that a mis-tap lands months
/// out.
const int kMaxDaysAhead = 7;

/// [d] at midnight, dropping the time of day.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The last day that can be chosen: today + [kMaxDaysAhead], at midnight.
/// Built from the calendar fields rather than adding a `Duration`, so a DST
/// change inside the week cannot land it an hour short of the day.
DateTime latestSelectableDate(DateTime now) =>
    DateTime(now.year, now.month, now.day + kMaxDaysAhead);

/// Whole calendar days from today to [date]: 1 for tomorrow, −1 for
/// yesterday. Counted on UTC dates so a DST day does not round to 0.
int daysFromToday(DateTime date, DateTime now) {
  final a = DateTime.utc(now.year, now.month, now.day);
  final b = DateTime.utc(date.year, date.month, date.day);
  return b.difference(a).inDays;
}

/// True for tomorrow onwards.
bool isFutureDay(DateTime date, DateTime now) => daysFromToday(date, now) > 0;

/// True up to and including [latestSelectableDate].
bool isSelectableDay(DateTime date, DateTime now) =>
    daysFromToday(date, now) <= kMaxDaysAhead;

/// [isFutureDay] for an entry's `spent_date` (`yyyy-MM-dd`). An unreadable
/// date is not treated as future.
bool isFutureSpentDate(String spentDate, DateTime now) {
  final parsed = DateTime.tryParse(spentDate);
  return parsed != null && isFutureDay(parsed, now);
}

/// [date] clamped into what the pickers accept, so an `initialDate` never
/// trips `showDatePicker`'s assertion.
DateTime clampToSelectable(DateTime date, DateTime now) {
  final last = latestSelectableDate(now);
  return dayOf(date).isAfter(last) ? last : date;
}

/// The two lines over Recent's week strip.
class DayHeading {
  /// "Today", "Tomorrow" or the weekday ("Thursday").
  final String title;

  /// "Mon 12 Oct 2026", with " · in 3 days" from two days out.
  final String subtitle;

  /// Tomorrow onwards: shown with an UPCOMING tag.
  final bool upcoming;

  final bool isToday;

  const DayHeading({
    required this.title,
    required this.subtitle,
    required this.upcoming,
    required this.isToday,
  });
}

DayHeading dayHeading(DateTime date, DateTime now) {
  final days = daysFromToday(date, now);
  final title = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => DateFormat('EEEE').format(date),
  };
  final full = DateFormat('EEE d MMM yyyy').format(date);
  return DayHeading(
    title: title,
    subtitle: days >= 2 ? '$full · in $days days' : full,
    upcoming: days > 0,
    isToday: days == 0,
  );
}
