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

  /// How the span is named beside a gap ("after Standup").
  final String label;

  /// True when the time of day came from the calendar import's reference
  /// rather than from Harvest's clock times — see `placedSpanOf`.
  final bool fromCalendar;

  const InsightSpan({
    required this.start,
    required this.end,
    this.key = '',
    this.label = '',
    this.fromCalendar = false,
  });
}

/// An uncovered stretch inside the work day.
class InsightGap {
  final int start;
  final int end;

  /// The span that ends where this gap starts, or null for a gap opening the
  /// window.
  final InsightSpan? previous;

  /// The span that starts where this gap ends, or null for a gap closing the
  /// window.
  final InsightSpan? next;

  const InsightGap(this.start, this.end, {this.previous, this.next});

  int get minutes => end - start;
}

/// How much of the day can be drawn on a timeline.
enum DayPlacement {
  /// No entry has a time of day: totals only.
  none,

  /// Some entries are placed, others were logged by duration alone. The
  /// stretches between placed spans are *open* — the unplaced work sits
  /// somewhere in them — rather than dead.
  partial,

  /// Every entry is placed, so an uncovered stretch really is unlogged.
  full,
}

class DayInsights {
  /// Gaps at or above the configured threshold, in chronological order.
  final List<InsightGap> gaps;

  /// Time covered by at least one placed span, with overlaps merged.
  final int workedMinutes;

  /// Logged time with no place on the day — duration-only entries.
  final int unplacedMinutes;

  /// Work-day time not accounted for by anything logged, including
  /// sub-threshold gaps: the window minus placed (merged) and unplaced time.
  /// Comes from totals, so it holds without clock times.
  final int deadMinutes;

  /// Length of the work-day window being measured against.
  final int windowMinutes;

  /// Number of spans considered, after clamping to the window.
  final int spanCount;

  /// Times the project/task changed between consecutive spans. Zero unless
  /// [placement] is full: with work unplaced, the order isn't known.
  final int contextSwitches;

  final int avgSessionMinutes;
  final int longestGapMinutes;

  final DayPlacement placement;

  const DayInsights({
    required this.gaps,
    required this.workedMinutes,
    this.unplacedMinutes = 0,
    required this.deadMinutes,
    required this.windowMinutes,
    required this.spanCount,
    required this.contextSwitches,
    required this.avgSessionMinutes,
    required this.longestGapMinutes,
    required this.placement,
  });

  /// Placed and unplaced time together.
  int get loggedMinutes => workedMinutes + unplacedMinutes;

  /// Work-day time no placed span covers. On a full day this is
  /// [deadMinutes]; on a partial one the unplaced work is somewhere in it.
  int get openMinutes => windowMinutes - workedMinutes;

  /// Share of the work-day window covered by logged work, 0..1.
  double get productivity => windowMinutes > 0
      ? (loggedMinutes / windowMinutes).clamp(0.0, 1.0).toDouble()
      : 0;

  static const empty = DayInsights(
    gaps: [],
    workedMinutes: 0,
    deadMinutes: 0,
    windowMinutes: 0,
    spanCount: 0,
    contextSwitches: 0,
    avgSessionMinutes: 0,
    longestGapMinutes: 0,
    placement: DayPlacement.none,
  );
}

/// A run of overlapping spans, remembering the span that opens it and the
/// one that ends it so a gap can name its neighbours.
class _Block {
  final int start;
  final int end;
  final InsightSpan first;
  final InsightSpan last;

  const _Block(this.start, this.end, this.first, this.last);
}

/// Analyses [spans] against the work-day window `[windowStart, windowEnd)`.
///
/// Pass "now" as [windowEnd] for the current day so the part of the afternoon
/// that has not happened yet is not counted as dead time. Spans are clamped to
/// the window and overlaps are merged, so time logged twice is only counted
/// once and an entry spilling past the end of the day does not inflate the
/// total.
///
/// [unplacedMinutes] is logged time with no time of day. With any, the day
/// is [DayPlacement.partial]: gaps are still found between the placed spans,
/// but they are open rather than dead, dead time comes from the totals, and
/// context switches are not counted.
DayInsights computeDayInsights({
  required List<InsightSpan> spans,
  required int windowStart,
  required int windowEnd,
  required int minGapMinutes,
  int unplacedMinutes = 0,
}) {
  final span = windowEnd - windowStart;
  if (span <= 0) return DayInsights.empty;

  final placement = spans.isEmpty
      ? DayPlacement.none
      : unplacedMinutes > 0
          ? DayPlacement.partial
          : DayPlacement.full;

  final clamped = spans
      .map((s) => InsightSpan(
            start: s.start < windowStart ? windowStart : s.start,
            end: s.end > windowEnd ? windowEnd : s.end,
            key: s.key,
            label: s.label,
            fromCalendar: s.fromCalendar,
          ))
      .where((s) => s.end > s.start)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  // Merge overlaps so concurrent or duplicated entries are not double-counted.
  final merged = <_Block>[];
  for (final s in clamped) {
    if (merged.isNotEmpty && s.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(
          s.end > last.end ? _Block(last.start, s.end, last.first, s) : last);
    } else {
      merged.add(_Block(s.start, s.end, s, s));
    }
  }

  final workedMinutes =
      merged.fold<int>(0, (sum, m) => sum + (m.end - m.start));

  // Uncovered stretches: window start → first, between blocks, last → end.
  final gaps = <InsightGap>[];
  var cursor = windowStart;
  InsightSpan? previous;
  for (final m in merged) {
    if (m.start > cursor) {
      gaps.add(InsightGap(cursor, m.start, previous: previous, next: m.first));
    }
    cursor = m.end;
    previous = m.last;
  }
  if (cursor < windowEnd) {
    gaps.add(InsightGap(cursor, windowEnd, previous: previous));
  }

  final significant =
      gaps.where((g) => g.minutes >= minGapMinutes).toList();

  var switches = 0;
  if (placement == DayPlacement.full) {
    for (var i = 1; i < clamped.length; i++) {
      if (clamped[i].key != clamped[i - 1].key) switches++;
    }
  }

  final unplaced = unplacedMinutes < 0 ? 0 : unplacedMinutes;
  final dead = span - workedMinutes - unplaced;

  return DayInsights(
    gaps: significant,
    workedMinutes: workedMinutes,
    unplacedMinutes: unplaced,
    deadMinutes: dead < 0 ? 0 : dead,
    windowMinutes: span,
    spanCount: clamped.length,
    contextSwitches: switches,
    avgSessionMinutes:
        clamped.isEmpty ? 0 : (workedMinutes / clamped.length).round(),
    longestGapMinutes: significant.isEmpty
        ? 0
        : significant.map((g) => g.minutes).reduce((a, b) => a > b ? a : b),
    placement: placement,
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
