/// Turning calendar events into Harvest time entries: which meetings to log,
/// what to call them, how to recognise one already logged, and which
/// project/task they go to.
///
/// Pure Dart — no Flutter — and unit tested in `test/meeting_test.dart`.
library;

import 'package:intl/intl.dart';

import 'calendar_event.dart';
import 'mapping_rule.dart';
import 'time_entry.dart';

/// Canonical meeting field names usable in a meeting rule condition — the keys
/// of [meetingMatchContext].
abstract final class MeetingField {
  static const title = 'title';
  static const location = 'location';
  static const description = 'description';
  static const organizer = 'organizer';
  static const busyStatus = 'busyStatus';
  static const isTeams = 'isTeams';

  static const all = [title, location, description, organizer, busyStatus, isTeams];

  static String labelFor(String field) => switch (field) {
        title => 'Title',
        location => 'Location',
        description => 'Description',
        organizer => 'Organizer',
        busyStatus => 'Show as',
        isTeams => 'Is Teams meeting',
        _ => field,
      };
}

/// Why a meeting is not logged. The UI names it, so a missing meeting is
/// explained rather than mysterious.
enum MeetingSkip {
  cancelled('Cancelled'),
  declined('Declined'),
  free('Shown as free'),
  private('Private'),
  notEnded('Not finished yet'),
  tooShort('Shorter than 5 minutes'),
  tooLong('Longer than 8 hours');

  final String label;
  const MeetingSkip(this.label);
}

const kMinMeetingMinutes = 5;
const kMaxMeetingMinutes = 480;

/// Outlook signals a cancelled or declined meeting on a single-mailbox
/// published feed by prefixing the subject, not through STATUS.
final _responsePrefix =
    RegExp(r'^(declined|canceled|cancelled):\s*', caseSensitive: false);

/// The first reason [e] should not be logged, or null when it should.
///
/// Mirrors the Apps Script it replaces: cancelled (by status or subject),
/// declined, shown as free, private, still running, or an implausible length.
MeetingSkip? meetingSkipReason(CalendarEvent e, DateTime now) {
  final summary = e.summary.trim();
  if (e.status == 'CANCELLED' ||
      RegExp(r'^cancell?ed:', caseSensitive: false).hasMatch(summary)) {
    return MeetingSkip.cancelled;
  }
  if (RegExp(r'^declined:', caseSensitive: false).hasMatch(summary)) {
    return MeetingSkip.declined;
  }
  // Free catches cancelled and declined again as a backup, plus anything
  // marked free by hand.
  if (e.busyStatus == 'FREE' || e.transparency == 'TRANSPARENT') {
    return MeetingSkip.free;
  }
  // Outlook redacts a private meeting's subject to "Private Appointment" once
  // the flag syncs — the summary check covers a mangled CLASS.
  if (e.classification == 'PRIVATE' ||
      e.classification == 'CONFIDENTIAL' ||
      summary == 'Private Appointment') {
    return MeetingSkip.private;
  }
  if (e.end.isAfter(now)) return MeetingSkip.notEnded;
  final minutes = e.duration.inMinutes;
  if (minutes < kMinMeetingMinutes) return MeetingSkip.tooShort;
  if (minutes > kMaxMeetingMinutes) return MeetingSkip.tooLong;
  return null;
}

/// The Harvest note for [e]: its subject, minus any response prefix.
String meetingNotes(CalendarEvent e) {
  final cleaned = e.summary.replaceFirst(_responsePrefix, '').trim();
  return cleaned.isEmpty ? '(No title)' : cleaned;
}

/// Hours to log, rounded to two places as Harvest displays them.
double meetingHours(CalendarEvent e) =>
    double.parse((e.duration.inSeconds / 3600).toStringAsFixed(2));

/// The local calendar date the meeting is logged against.
String meetingSpentDate(CalendarEvent e) =>
    DateFormat('yyyy-MM-dd').format(e.start.toLocal());

/// `HH:mm` local clock time, for accounts that track by start and end.
String meetingClock(DateTime utc) => DateFormat('HH:mm').format(utc.toLocal());

/// The instant identifying this occurrence: where it sits in its series, which
/// does not move when an override reschedules it.
DateTime _occurrenceOf(CalendarEvent e) => e.occurrence ?? e.start;

/// Per-occurrence key for the local ledger: the series UID plus the
/// occurrence, so every instance of a recurring meeting is distinct.
String meetingLedgerKey(CalendarEvent e) =>
    '${e.uid}|${_occurrenceOf(e).millisecondsSinceEpoch}';

/// The Harvest `external_reference.id` for a meeting entry. Outlook UIDs run to
/// 112 characters, so the UID is hashed rather than embedded.
String meetingExternalRefId(CalendarEvent e) =>
    '$kMeetingRefPrefix${_hash64(e.uid)}_'
    '${_occurrenceOf(e).millisecondsSinceEpoch ~/ 1000}';

const kMeetingRefPrefix = 'GrainCalendar_';

/// Two 32-bit FNV-1a passes as 16 hex chars. Kept to 32-bit arithmetic with
/// the multiply split, because web compiles `int` to a double and a 64-bit
/// product would lose bits.
String _hash64(String s) {
  int fnv(Iterable<int> units, int seed) {
    var h = seed;
    for (final u in units) {
      h ^= u;
      // h * 16777619 == (h << 24) + h * 403, each part exact in a double.
      h = (((h << 24) & 0xFFFFFFFF) + h * 403) & 0xFFFFFFFF;
    }
    return h;
  }

  final units = s.codeUnits;
  final a = fnv(units, 0x811C9DC5);
  final b = fnv(units.reversed, 0x01000193 ^ 0x811C9DC5);
  return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
}

final _teamsUrl = RegExp(r'https://teams\.microsoft\.com/[^\s<>"]+');

/// The Teams join link from a meeting's description, if any.
String? teamsJoinUrl(CalendarEvent e) =>
    _teamsUrl.firstMatch(e.description ?? '')?.group(0);

/// A work item number in the title: `#12345` or `AB#12345`. Bare numbers are
/// ignored — "Q3 2026 planning" is not a work item.
String? workItemIdFromTitle(String title) =>
    RegExp(r'(?:^|[\s(\[])(?:AB)?#(\d{2,})\b', caseSensitive: false)
        .firstMatch(title)
        ?.group(1);

/// The fields a meeting rule matches against.
MatchContext meetingMatchContext(CalendarEvent e) => {
      MeetingField.title: meetingNotes(e),
      MeetingField.location: e.location,
      MeetingField.description: e.description,
      MeetingField.organizer: [
        if (e.organizerName != null) e.organizerName!,
        if (e.organizerEmail != null) e.organizerEmail!,
      ],
      MeetingField.busyStatus: e.busyStatus,
      MeetingField.isTeams: teamsJoinUrl(e) != null ||
              (e.location ?? '').toLowerCase().contains('teams')
          ? 'yes'
          : 'no',
    };

/// True when [e] is already in Harvest or was logged (or skipped) from here
/// before.
///
/// Three ways to know: the local [ledger] — which also stops a meeting deleted
/// in Harvest from being recreated; an entry carrying this meeting's external
/// reference; or a fingerprint — same date, same hours, notes containing the
/// title — which catches entries the old Apps Script made, and meetings logged
/// against a work item, whose reference slot holds the work item instead.
bool isMeetingLogged(
  CalendarEvent e, {
  required Set<String> ledger,
  required List<TimeEntry> entries,
}) {
  if (ledger.contains(meetingLedgerKey(e))) return true;
  final refId = meetingExternalRefId(e);
  final date = meetingSpentDate(e);
  final hours = meetingHours(e);
  final title = meetingNotes(e).toLowerCase();
  for (final entry in entries) {
    if (entry.externalReference?.id == refId) return true;
    if (entry.spentDate == date &&
        (entry.hours - hours).abs() <= 0.02 &&
        (entry.notes ?? '').toLowerCase().contains(title)) {
      return true;
    }
  }
  return false;
}

/// Where a meeting gets logged, and why.
class MeetingTarget {
  final int projectId;
  final int taskId;
  final MeetingTargetSource source;

  /// The rule that chose it, for a rule-based source.
  final MappingRule? rule;

  const MeetingTarget({
    required this.projectId,
    required this.taskId,
    required this.source,
    this.rule,
  });
}

enum MeetingTargetSource { meetingRule, workItemRule, fallback, manual }

/// Picks the project/task in order: a meeting rule, then the ADO rule for a
/// work item named in the title, then the default. A candidate whose
/// project/task is no longer assigned is passed over, as Log Time does.
MeetingTarget? chooseMeetingTarget({
  MappingMatch? meetingMatch,
  MappingMatch? workItemMatch,
  ({int projectId, int taskId})? fallback,
  required bool Function(int projectId, int taskId) isAssigned,
}) {
  if (meetingMatch != null &&
      isAssigned(meetingMatch.projectId, meetingMatch.taskId)) {
    return MeetingTarget(
      projectId: meetingMatch.projectId,
      taskId: meetingMatch.taskId,
      source: MeetingTargetSource.meetingRule,
      rule: meetingMatch.rule,
    );
  }
  if (workItemMatch != null &&
      isAssigned(workItemMatch.projectId, workItemMatch.taskId)) {
    return MeetingTarget(
      projectId: workItemMatch.projectId,
      taskId: workItemMatch.taskId,
      source: MeetingTargetSource.workItemRule,
      rule: workItemMatch.rule,
    );
  }
  if (fallback != null && isAssigned(fallback.projectId, fallback.taskId)) {
    return MeetingTarget(
      projectId: fallback.projectId,
      taskId: fallback.taskId,
      source: MeetingTargetSource.fallback,
    );
  }
  return null;
}

/// The note for a meeting: a meeting rule's template when it has one,
/// otherwise the cleaned subject.
String meetingNoteFor(CalendarEvent e, MeetingTarget target) {
  final template = target.source == MeetingTargetSource.meetingRule
      ? target.rule?.noteTemplate
      : null;
  if (template == null || template.trim().isEmpty) return meetingNotes(e);
  return renderNoteTemplate(template, meetingMatchContext(e));
}
