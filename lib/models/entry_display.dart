import 'day_insights.dart';
import 'meeting.dart';
import 'time_entry.dart';

/// What the Recent card shows as an entry's notes line, given the entry is
/// linked to work item [workItemId].
///
/// Log Time writes linked notes as `{instance} Azure DevOps {type} #{id}`, or
/// `… #{id} - {what you typed}`. The work item preview already says all of
/// the prefix, so a prefix-only note returns null and a prefixed one returns
/// just what was typed after it. Anything else comes back unchanged.
String? workItemNotesLine(String? notes, String workItemId) {
  if (notes == null) return null;
  final text = notes.trim();
  if (text.isEmpty) return null;

  final id = workItemId.isEmpty ? r'\d+' : RegExp.escape(workItemId);
  final match = RegExp(
    '^.*?Azure DevOps .*?#$id(?:\\s+-\\s*(.*))?\$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return text;

  final rest = match.group(1)?.trim() ?? '';
  return rest.isEmpty ? null : rest;
}

/// When the meeting behind a calendar-import reference started, as local
/// time: the epoch seconds at the end of `GrainCalendar_{hash}_{epoch}`.
/// Null for any other or malformed reference.
DateTime? meetingStartFromRefId(String? refId) {
  if (refId == null) return null;
  final match = RegExp('^${RegExp.escape(kMeetingRefPrefix)}'
          r'[0-9a-fA-F]{16}_(\d{1,12})$')
      .firstMatch(refId);
  if (match == null) return null;
  final seconds = int.parse(match.group(1)!);
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      .toLocal();
}

/// When an imported meeting started, from its reference id, or null when
/// [entry] is not one (or the id is malformed).
DateTime? _meetingStart(TimeEntry entry) {
  final refId = entry.externalReference?.id;
  if (refId == null || !refId.startsWith(kMeetingRefPrefix)) return null;
  return meetingStartFromRefId(refId);
}

/// `HH:mm` start time for an imported meeting, or null when [entry] is not
/// one. Harvest's own clock time wins when the account records it; otherwise
/// the time comes from the reference id the importer wrote.
String? meetingStartLabel(TimeEntry entry) {
  final refId = entry.externalReference?.id;
  if (refId == null || !refId.startsWith(kMeetingRefPrefix)) return null;

  final clock = parseClockMinutes(entry.startedTime);
  if (clock != null) return formatClock(clock);

  final start = _meetingStart(entry);
  if (start == null) return null;
  return formatClock(start.hour * 60 + start.minute);
}

/// How an entry is named in a sentence ("after Standup"): the first line of
/// its notes when it has any worth reading (work item prefixes stripped),
/// otherwise its task.
String entryLabel(TimeEntry entry) {
  final ref = entry.adoReference;
  final notes = ref != null
      ? workItemNotesLine(entry.notes, ref.id.split('_').last)
      : entry.notes?.trim();
  final firstLine = notes?.split('\n').first.trim() ?? '';
  return firstLine.isEmpty ? entry.taskName : firstLine;
}

/// Where [entry] sits on its day, for Insights.
///
/// An entry with clock times keeps [TimeEntry.span]. Failing that, an
/// imported meeting is placed from its reference id — the series slot, read
/// as local time — for the entry's hours, and marked
/// [InsightSpan.fromCalendar]. Anything else is null: logged by duration, its
/// time of day unknown. A meeting whose slot is not on the entry's
/// `spentDate`, or whose hours would run past midnight, is not placed.
InsightSpan? placedSpanOf(TimeEntry entry) {
  final timed = entry.span;
  if (timed != null) {
    return InsightSpan(
      start: timed.start,
      end: timed.end,
      key: timed.key,
      label: entryLabel(entry),
    );
  }

  final start = _meetingStart(entry);
  if (start == null) return null;
  final day = DateTime.tryParse(entry.spentDate);
  if (day == null ||
      start.year != day.year ||
      start.month != day.month ||
      start.day != day.day) {
    return null;
  }

  final from = start.hour * 60 + start.minute;
  final to = from + (entry.hours * 60).round();
  if (to <= from || to > 24 * 60) return null;
  return InsightSpan(
    start: from,
    end: to,
    key: '${entry.projectId}:${entry.taskId}',
    label: entryLabel(entry),
    fromCalendar: true,
  );
}
