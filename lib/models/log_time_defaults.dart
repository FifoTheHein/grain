/// What Log Time suggests before you have typed anything: the unlogged gap
/// since your last entry, and where Start & End should begin and end.
///
/// Pure Dart. Times are minutes from midnight, like `day_insights.dart`, and
/// a day's entries come in as [TimeEntry]s so [TimeEntry.span] decides which
/// carry clock times. Unit tested in `test/log_time_defaults_test.dart`.
library;

import 'day_insights.dart';
import 'entry_display.dart';
import 'time_entry.dart';

/// Gaps shorter than this are not worth offering.
const int kMinGapSuggestionMinutes = 5;

/// The last entry of the day that knows when it ended.
class LastTimedEntry {
  final TimeEntry entry;

  /// When it ended, in minutes from midnight.
  final int end;

  const LastTimedEntry(this.entry, this.end);

  /// How the entry is named in "since … ended": its notes when it has any
  /// worth reading (work item prefixes stripped), otherwise its task.
  String get label {
    final ref = entry.adoReference;
    final notes = ref != null
        ? workItemNotesLine(entry.notes, ref.id.split('_').last)
        : entry.notes?.trim();
    final firstLine = notes?.split('\n').first.trim() ?? '';
    return firstLine.isEmpty ? entry.taskName : firstLine;
  }
}

/// The timed entry that ended latest, or null when none of [entries] carries
/// clock times. Latest *end*, not latest created: a meeting logged afterwards
/// for the morning does not move the suggestion back.
LastTimedEntry? lastTimedEntry(Iterable<TimeEntry> entries) {
  LastTimedEntry? best;
  for (final e in entries) {
    final span = e.span;
    if (span == null) continue;
    if (best == null || span.end > best.end) best = LastTimedEntry(e, span.end);
  }
  return best;
}

/// "1h 20m unlogged since Standup ended at 10:40".
class GapSuggestion {
  final LastTimedEntry since;

  /// Minutes from [since]'s end up to now.
  final int minutes;

  const GapSuggestion({required this.since, required this.minutes});

  String get endClock => formatClock(since.end);
}

/// The time between the end of today's last timed entry and [nowMinutes], or
/// null when there is nothing to offer: no timed entry, a timer running
/// (that time is already being counted), or a gap under [minMinutes].
///
/// The caller passes only today's entries — the suggestion is about "since
/// you stopped", which means nothing on another day.
GapSuggestion? suggestGap(
  Iterable<TimeEntry> todaysEntries, {
  required int nowMinutes,
  int minMinutes = kMinGapSuggestionMinutes,
}) {
  if (todaysEntries.any((e) => e.isRunning)) return null;
  final last = lastTimedEntry(todaysEntries);
  if (last == null) return null;
  final gap = nowMinutes - last.end;
  if (gap < minMinutes) return null;
  return GapSuggestion(since: last, minutes: gap);
}

/// Where a Start & End default came from, for the caption under the time.
enum StartSource { lastEntry, loggedTotal, workDayStart, hourBeforeNow }

class StartEndDefaults {
  final int start;
  final int end;
  final StartSource startSource;

  /// The entry [start] follows, when [startSource] is [StartSource.lastEntry].
  final LastTimedEntry? after;

  /// True when [end] is "now" rather than an hour after the start.
  final bool endIsNow;

  const StartEndDefaults({
    required this.start,
    required this.end,
    required this.startSource,
    this.after,
    this.endIsNow = false,
  });
}

const int _lastMinute = 23 * 60 + 59;

/// Defaults for Start & End on a day holding [entries].
///
/// Start is the end of the day's last timed entry. With none, it is
/// [workDayStart] plus whatever the day already has logged by duration, so an
/// account that does not track clock times still gets "after what you've
/// done" rather than every entry starting at the same minute; on an empty day
/// that is simply the work-day start.
///
/// End is [nowMinutes] when [isToday] and start + 1h otherwise. On today a
/// start already at or past now is pulled back an hour, so the defaults are
/// never an end-before-start error waiting to happen.
///
/// A day ahead ([isFuture]) always starts at [workDayStart], whatever it
/// already holds: time logged ahead is planned, not a record of when the
/// day's work happened.
StartEndDefaults startEndDefaults(
  Iterable<TimeEntry> entries, {
  required int workDayStart,
  required bool isToday,
  required int nowMinutes,
  bool isFuture = false,
}) {
  if (isFuture) {
    final start = workDayStart.clamp(0, _lastMinute);
    return StartEndDefaults(
      start: start,
      end: (start + 60).clamp(0, _lastMinute),
      startSource: StartSource.workDayStart,
    );
  }
  final last = lastTimedEntry(entries);
  int start;
  StartSource source;
  if (last != null) {
    start = last.end;
    source = StartSource.lastEntry;
  } else {
    final logged =
        entries.fold<double>(0, (sum, e) => sum + e.hours * 60).round();
    start = workDayStart + logged;
    source = logged > 0 ? StartSource.loggedTotal : StartSource.workDayStart;
  }
  start = start.clamp(0, _lastMinute);

  if (!isToday) {
    return StartEndDefaults(
      start: start,
      end: (start + 60).clamp(0, _lastMinute),
      startSource: source,
      after: last,
    );
  }

  final now = nowMinutes.clamp(0, _lastMinute);
  if (start >= now) {
    start = (now - 60).clamp(0, _lastMinute);
    // Moved off whatever it was derived from, so say so in the caption.
    return StartEndDefaults(
      start: start,
      end: now,
      startSource: StartSource.hourBeforeNow,
      endIsNow: true,
    );
  }
  return StartEndDefaults(
    start: start,
    end: now,
    startSource: source,
    after: last,
    endIsNow: true,
  );
}

/// One −5 / +5 nudge of a Start & End time, kept within the day and, for the
/// end on today, not past [ceiling].
int nudgeClock(int minutes, int delta, {int ceiling = _lastMinute}) =>
    (minutes + delta).clamp(0, ceiling < _lastMinute ? ceiling : _lastMinute);
