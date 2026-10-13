/// How a day's entries break down for Insights: the share that went on
/// meetings, and the time per work item.
///
/// Pure Dart, unit tested in `test/day_breakdown_test.dart`.
library;

import 'entry_display.dart';
import 'meeting.dart' show kMeetingRefPrefix;
import 'time_entry.dart';

/// Time spent in meetings the calendar import logged.
class MeetingLoad {
  final int minutes;
  final int count;

  /// All logged time on the day, meetings included.
  final int loggedMinutes;

  const MeetingLoad({
    required this.minutes,
    required this.count,
    required this.loggedMinutes,
  });

  /// Meetings as a whole percentage of logged time, 0 when nothing is logged.
  int get percentOfLogged =>
      loggedMinutes > 0 ? (minutes * 100 / loggedMinutes).round() : 0;
}

/// True for an entry the calendar import created and tagged with its
/// `GrainCalendar_…` reference.
bool isImportedMeeting(TimeEntry entry) =>
    entry.externalReference?.id.startsWith(kMeetingRefPrefix) ?? false;

/// The imported meetings among [entries], placed on the timeline or not.
///
/// A meeting linked to a work item carries the work item's reference instead
/// of the calendar's, so it counts as work here: nothing on the entry says it
/// was a meeting.
MeetingLoad meetingLoad(List<TimeEntry> entries) {
  var meetingHours = 0.0;
  var loggedHours = 0.0;
  var count = 0;
  for (final e in entries) {
    loggedHours += e.hours;
    if (isImportedMeeting(e)) {
      meetingHours += e.hours;
      count++;
    }
  }
  return MeetingLoad(
    minutes: (meetingHours * 60).round(),
    count: count,
    loggedMinutes: (loggedHours * 60).round(),
  );
}

/// The day's time on one work item — or, with a null [workItemId], on
/// everything not linked to one.
class WorkItemGroup {
  /// The work item number, or null for the "No work item" group.
  final String? workItemId;

  /// The work item's URL, from the first entry carrying one; lets the screen
  /// find the ADO instance the item's cached title lives under.
  final String? permalink;

  /// What the entries' notes say beyond the work item prefix, from the first
  /// entry with anything — the fallback title when the item isn't cached.
  final String? notesTitle;

  final List<TimeEntry> entries;
  final int minutes;

  const WorkItemGroup({
    required this.workItemId,
    required this.permalink,
    required this.notesTitle,
    required this.entries,
    required this.minutes,
  });

  bool get isUnlinked => workItemId == null;
}

/// Groups [entries] by the work item they are linked to, largest first, with
/// the entries linked to nothing gathered last into one group (left out when
/// there are none).
///
/// Entries are keyed by the work item number plus the permalink's host, so the
/// same item reached through `AzureDevOps_{guid}_{type}_{n}` and through a
/// bare `n` lands in one group, while #123 on two ADO organisations stays
/// apart.
List<WorkItemGroup> groupByWorkItem(List<TimeEntry> entries) {
  final linked = <String, List<TimeEntry>>{};
  final unlinked = <TimeEntry>[];
  for (final e in entries) {
    final ref = e.adoReference;
    if (ref == null) {
      unlinked.add(e);
      continue;
    }
    final id = ref.id.split('_').last;
    final host = Uri.tryParse(ref.permalink ?? '')?.host.toLowerCase() ?? '';
    linked.putIfAbsent('$host#$id', () => []).add(e);
  }

  int minutesOf(List<TimeEntry> group) =>
      (group.fold<double>(0, (sum, e) => sum + e.hours) * 60).round();

  final groups = [
    for (final group in linked.values)
      () {
        final id = group.first.adoReference!.id.split('_').last;
        String? notesTitle;
        for (final e in group) {
          final line = workItemNotesLine(e.notes, id)?.split('\n').first.trim();
          if (line != null && line.isNotEmpty) {
            notesTitle = line;
            break;
          }
        }
        return WorkItemGroup(
          workItemId: id,
          permalink: group
              .map((e) => e.adoReference!.permalink)
              .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null),
          notesTitle: notesTitle,
          entries: group,
          minutes: minutesOf(group),
        );
      }(),
  ]..sort((a, b) => b.minutes.compareTo(a.minutes));

  return [
    ...groups,
    if (unlinked.isNotEmpty)
      WorkItemGroup(
        workItemId: null,
        permalink: null,
        notesTitle: null,
        entries: unlinked,
        minutes: minutesOf(unlinked),
      ),
  ];
}
