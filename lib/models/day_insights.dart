/// Dead-time / productivity analysis for a single day.
///
/// Everything here is pure — no I/O, no Flutter — and works in minutes from
/// midnight, which is all the precision a day view needs and keeps the maths
/// free of time zones. Unit tested in `test/day_insights_test.dart`.
library;

/// A single logged stretch of work, in minutes from midnight.
class InsightSpan {
  final int start;
  final int end;

  /// Identity used to detect context switches — project + task in practice.
  final String key;

  const InsightSpan({
    required this.start,
    required this.end,
    this.key = '',
  });
}

/// An uncovered stretch inside the work day.
class InsightGap {
  final int start;
  final int end;

  const InsightGap(this.start, this.end);

  int get minutes => end - start;
}

class DayInsights {
  /// Gaps at or above the configured threshold, in chronological order.
  final List<InsightGap> gaps;

  /// Time covered by at least one entry, with overlaps merged.
  final int workedMinutes;

  /// Work-day time not covered by any entry — including sub-threshold gaps.
  final int deadMinutes;

  /// Length of the work-day window being measured against.
  final int windowMinutes;

  /// Number of spans considered, after clamping to the window.
  final int spanCount;

  /// Times the project/task changed between consecutive spans.
  final int contextSwitches;

  final int avgSessionMinutes;
  final int longestGapMinutes;

  const DayInsights({
    required this.gaps,
    required this.workedMinutes,
    required this.deadMinutes,
    required this.windowMinutes,
    required this.spanCount,
    required this.contextSwitches,
    required this.avgSessionMinutes,
    required this.longestGapMinutes,
  });

  /// Share of the work-day window covered by logged work, 0..1.
  double get productivity =>
      windowMinutes > 0 ? workedMinutes / windowMinutes : 0;

  static const empty = DayInsights(
    gaps: [],
    workedMinutes: 0,
    deadMinutes: 0,
    windowMinutes: 0,
    spanCount: 0,
    contextSwitches: 0,
    avgSessionMinutes: 0,
    longestGapMinutes: 0,
  );
}

/// Analyses [spans] against the work-day window `[windowStart, windowEnd)`.
///
/// Pass "now" as [windowEnd] for the current day so the part of the afternoon
/// that has not happened yet is not counted as dead time. Spans are clamped to
/// the window and overlaps are merged, so time logged twice is only counted
/// once and an entry spilling past the end of the day does not inflate the
/// total.
DayInsights computeDayInsights({
  required List<InsightSpan> spans,
  required int windowStart,
  required int windowEnd,
  required int minGapMinutes,
}) {
  final span = windowEnd - windowStart;
  if (span <= 0) return DayInsights.empty;

  final clamped = spans
      .map((s) => InsightSpan(
            start: s.start < windowStart ? windowStart : s.start,
            end: s.end > windowEnd ? windowEnd : s.end,
            key: s.key,
          ))
      .where((s) => s.end > s.start)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  // Merge overlaps so concurrent or duplicated entries are not double-counted.
  final merged = <InsightGap>[];
  for (final s in clamped) {
    if (merged.isNotEmpty && s.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(InsightGap(last.start, s.end > last.end ? s.end : last.end));
    } else {
      merged.add(InsightGap(s.start, s.end));
    }
  }

  final workedMinutes = merged.fold<int>(0, (sum, m) => sum + m.minutes);

  // Uncovered stretches: window start → first, between blocks, last → end.
  final gaps = <InsightGap>[];
  var cursor = windowStart;
  for (final m in merged) {
    if (m.start > cursor) gaps.add(InsightGap(cursor, m.start));
    if (m.end > cursor) cursor = m.end;
  }
  if (cursor < windowEnd) gaps.add(InsightGap(cursor, windowEnd));

  final significant =
      gaps.where((g) => g.minutes >= minGapMinutes).toList();

  var switches = 0;
  for (var i = 1; i < clamped.length; i++) {
    if (clamped[i].key != clamped[i - 1].key) switches++;
  }

  return DayInsights(
    gaps: significant,
    workedMinutes: workedMinutes,
    deadMinutes: span - workedMinutes,
    windowMinutes: span,
    spanCount: clamped.length,
    contextSwitches: switches,
    avgSessionMinutes:
        clamped.isEmpty ? 0 : (workedMinutes / clamped.length).round(),
    longestGapMinutes: significant.isEmpty
        ? 0
        : significant.map((g) => g.minutes).reduce((a, b) => a > b ? a : b),
  );
}

/// Parses a Harvest clock time into minutes from midnight.
///
/// Harvest returns `started_time` / `ended_time` as display strings, which vary
/// with the account's time format — `"8:30am"`, `"8:30 AM"` and `"08:30"` are
/// all possible. Returns null for anything unparseable, including the nulls
/// sent by duration-tracking accounts.
int? parseClockMinutes(String? raw) {
  if (raw == null) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  final match =
      RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$').firstMatch(text);
  if (match == null) return null;

  var hour = int.parse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  final meridiem = match.group(3);

  if (minute > 59) return null;
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return null;
    if (meridiem == 'pm' && hour != 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
  } else if (hour > 23) {
    return null;
  }
  return hour * 60 + minute;
}

/// Formats minutes from midnight as `HH:mm`.
String formatClock(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Formats a duration in minutes as `Xh Ym`, dropping empty parts.
String formatDuration(int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  final h = safe ~/ 60;
  final m = safe % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
