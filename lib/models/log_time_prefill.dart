/// What Insights' "Log this" hands to Log Time for an open stretch of the
/// day, and whether it can hand anything over at all.
///
/// Pure Dart, unit tested in `test/log_time_prefill_test.dart`.
library;

import 'day_insights.dart';

/// A form Log Time opens pre-filled, rather than at its defaults.
class LogTimePrefill {
  final DateTime date;

  /// Start & End mode when true, Duration otherwise. Not persisted: the
  /// remembered mode stays the user's own choice.
  final bool startEnd;

  /// Duration mode's minutes.
  final int minutes;

  /// Start & End mode's times, in minutes from midnight.
  final int start;
  final int end;

  /// Captions under the clock boxes ("after Standup", "before Planning").
  final String? startCaption;
  final String? endCaption;

  /// Where the stretch sits, for "From Insights · open after Standup".
  final String origin;

  const LogTimePrefill({
    required this.date,
    required this.startEnd,
    this.minutes = 0,
    this.start = 0,
    this.end = 0,
    this.startCaption,
    this.endCaption,
    required this.origin,
  });
}

/// How an open stretch is named: after the span before it, else before the
/// one after it, else by its clock times.
String slotOrigin(InsightGap gap) {
  final previous = gap.previous;
  final next = gap.next;
  if (previous != null && previous.label.isNotEmpty) {
    return 'open after ${previous.label}';
  }
  if (next != null && next.label.isNotEmpty) return 'open before ${next.label}';
  return 'open ${formatClock(gap.start)}–${formatClock(gap.end)}';
}

/// The Log Time form for logging [gap] on [date], or null when there is
/// nothing to log.
///
/// An account that tracks by start and end gets the stretch's own times. A
/// duration account ignores clock times, and part of the stretch may already
/// be covered by work logged by duration alone, so it gets a duration: the
/// stretch, capped at [unloggedMinutes] (the day's goal less everything
/// logged). Null when that leaves nothing — logging it would count the same
/// time twice.
LogTimePrefill? prefillForSlot({
  required DateTime date,
  required InsightGap gap,
  required bool tracksByStartEnd,
  required int unloggedMinutes,
}) {
  if (gap.minutes <= 0) return null;
  final origin = slotOrigin(gap);
  if (tracksByStartEnd) {
    final previous = gap.previous?.label ?? '';
    final next = gap.next?.label ?? '';
    return LogTimePrefill(
      date: date,
      startEnd: true,
      start: gap.start,
      end: gap.end,
      startCaption: previous.isEmpty ? null : 'after $previous',
      endCaption: next.isEmpty ? null : 'before $next',
      origin: origin,
    );
  }
  final minutes = gap.minutes < unloggedMinutes ? gap.minutes : unloggedMinutes;
  if (minutes <= 0) return null;
  return LogTimePrefill(
    date: date,
    startEnd: false,
    minutes: minutes,
    origin: origin,
  );
}
