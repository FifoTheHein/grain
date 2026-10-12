import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/calendar_event.dart';
import 'package:harvest/models/mapping_rule.dart';
import 'package:harvest/models/meeting.dart';
import 'package:harvest/models/time_entry.dart';

final now = DateTime.utc(2026, 10, 12, 15);

CalendarEvent event({
  String uid = 'uid-1',
  String summary = 'Sprint review',
  DateTime? start,
  Duration length = const Duration(minutes: 30),
  String? status,
  String? busyStatus = 'BUSY',
  String? transparency = 'OPAQUE',
  String? classification = 'PUBLIC',
  String? location,
  String? description,
  DateTime? occurrence,
}) {
  final s = start ?? DateTime.utc(2026, 10, 12, 8);
  return CalendarEvent(
    uid: uid,
    summary: summary,
    start: s,
    end: s.add(length),
    status: status,
    busyStatus: busyStatus,
    transparency: transparency,
    classification: classification,
    location: location,
    description: description,
    occurrence: occurrence,
  );
}

TimeEntry entry({
  required String spentDate,
  required double hours,
  String? notes,
  String? refId,
}) =>
    TimeEntry(
      id: 1,
      spentDate: spentDate,
      hours: hours,
      notes: notes,
      projectId: 1,
      projectName: 'P',
      taskId: 1,
      taskName: 'T',
      externalReference: refId == null ? null : ExternalReference(id: refId),
    );

MappingMatch match(int project, int task, {String? noteTemplate}) =>
    MappingMatch(MappingRule(
      id: '$project',
      name: 'r$project',
      projectId: project,
      taskId: task,
      noteTemplate: noteTemplate,
    ));

void main() {
  group('meetingSkipReason', () {
    test('a normal finished meeting is logged', () {
      expect(meetingSkipReason(event(), now), isNull);
    });

    test('each skip reason', () {
      expect(meetingSkipReason(event(status: 'CANCELLED'), now),
          MeetingSkip.cancelled);
      expect(meetingSkipReason(event(summary: 'Canceled: Retro'), now),
          MeetingSkip.cancelled);
      expect(meetingSkipReason(event(summary: 'Cancelled: Retro'), now),
          MeetingSkip.cancelled);
      expect(meetingSkipReason(event(summary: 'Declined: Retro'), now),
          MeetingSkip.declined);
      expect(meetingSkipReason(event(busyStatus: 'FREE'), now),
          MeetingSkip.free);
      expect(meetingSkipReason(event(transparency: 'TRANSPARENT'), now),
          MeetingSkip.free);
      expect(meetingSkipReason(event(classification: 'PRIVATE'), now),
          MeetingSkip.private);
      expect(meetingSkipReason(event(classification: 'CONFIDENTIAL'), now),
          MeetingSkip.private);
      expect(meetingSkipReason(event(summary: 'Private Appointment'), now),
          MeetingSkip.private);
      expect(
          meetingSkipReason(
              event(start: now.subtract(const Duration(minutes: 10))), now),
          MeetingSkip.notEnded);
      expect(meetingSkipReason(event(length: const Duration(minutes: 4)), now),
          MeetingSkip.tooShort);
      expect(
          meetingSkipReason(
              event(start: DateTime.utc(2026, 10, 12, 5), length: const Duration(hours: 9)),
              now),
          MeetingSkip.tooLong);
    });

    test('tentative and out-of-office still log, as the script did', () {
      expect(meetingSkipReason(event(busyStatus: 'TENTATIVE'), now), isNull);
      expect(meetingSkipReason(event(busyStatus: 'OOF'), now), isNull);
    });

    test('a meeting ending exactly now has ended', () {
      expect(
          meetingSkipReason(
              event(start: now.subtract(const Duration(minutes: 30))), now),
          isNull);
    });
  });

  group('naming and keys', () {
    test('notes strip the response prefix and fall back for a blank title', () {
      expect(meetingNotes(event(summary: 'Declined: Retro')), 'Retro');
      expect(meetingNotes(event(summary: '  ')), '(No title)');
    });

    test('hours round to two places', () {
      expect(meetingHours(event(length: const Duration(minutes: 20))), 0.33);
      expect(meetingHours(event(length: const Duration(minutes: 90))), 1.5);
    });

    test('keys use the series occurrence, not a rescheduled start', () {
      final original = DateTime.utc(2026, 10, 19, 8);
      final moved = event(start: DateTime.utc(2026, 10, 19, 12), occurrence: original);
      final unmoved = event(start: original, occurrence: original);
      expect(meetingLedgerKey(moved), meetingLedgerKey(unmoved));
      expect(meetingExternalRefId(moved), meetingExternalRefId(unmoved));
    });

    test('occurrences of one series get distinct keys', () {
      final a = event(start: DateTime.utc(2026, 10, 12, 8));
      final b = event(start: DateTime.utc(2026, 10, 13, 8));
      expect(meetingLedgerKey(a), isNot(meetingLedgerKey(b)));
      expect(meetingExternalRefId(a), isNot(meetingExternalRefId(b)));
    });

    test('external ref id is stable, prefixed and short', () {
      final id = meetingExternalRefId(event(uid: 'x' * 112));
      expect(id, meetingExternalRefId(event(uid: 'x' * 112)));
      expect(id, startsWith(kMeetingRefPrefix));
      expect(id, matches(RegExp(r'^GrainCalendar_[0-9a-f]{16}_\d+$')));
      expect(meetingExternalRefId(event(uid: 'y' * 112)), isNot(id));
    });

    test('finds the Teams join link', () {
      expect(
          teamsJoinUrl(event(
              description:
                  'Join: <https://teams.microsoft.com/l/meetup-join/19%3a/0?context=x>\nMore')),
          'https://teams.microsoft.com/l/meetup-join/19%3a/0?context=x');
      expect(teamsJoinUrl(event(description: 'No link')), isNull);
    });

    test('work item numbers need a hash', () {
      expect(workItemIdFromTitle('Refinement #12345'), '12345');
      expect(workItemIdFromTitle('AB#678 walkthrough'), '678');
      expect(workItemIdFromTitle('#42 kickoff'), '42');
      expect(workItemIdFromTitle('Q3 2026 planning'), isNull);
      expect(workItemIdFromTitle('Issue#5'), isNull);
    });
  });

  group('isMeetingLogged', () {
    final e = event(summary: 'Sprint review', length: const Duration(minutes: 30));
    final date = meetingSpentDate(e);

    test('nothing matches a fresh meeting', () {
      expect(
          isMeetingLogged(e, ledger: {}, entries: [
            entry(spentDate: date, hours: 1, notes: 'Something else'),
          ]),
          isFalse);
    });

    test('the local ledger counts', () {
      expect(isMeetingLogged(e, ledger: {meetingLedgerKey(e)}, entries: []),
          isTrue);
    });

    test('an entry carrying the external reference counts', () {
      expect(
          isMeetingLogged(e, ledger: {}, entries: [
            entry(
                spentDate: '2000-01-01',
                hours: 9,
                refId: meetingExternalRefId(e)),
          ]),
          isTrue);
    });

    test('an Apps-Script-style entry matches by fingerprint', () {
      expect(
          isMeetingLogged(e, ledger: {}, entries: [
            entry(spentDate: date, hours: 0.5, notes: 'Sprint review'),
          ]),
          isTrue);
    });

    test('a work-item-prefixed note still matches by fingerprint', () {
      expect(
          isMeetingLogged(e, ledger: {}, entries: [
            entry(
                spentDate: date,
                hours: 0.5,
                notes: 'Transport Azure DevOps Task #1 - Sprint Review'),
          ]),
          isTrue);
    });

    test('fingerprint needs the same date and hours', () {
      expect(
          isMeetingLogged(e, ledger: {}, entries: [
            entry(spentDate: '2026-10-13', hours: 0.5, notes: 'Sprint review'),
            entry(spentDate: date, hours: 1, notes: 'Sprint review'),
          ]),
          isFalse);
    });
  });

  group('chooseMeetingTarget', () {
    bool all(int p, int t) => true;

    test('meeting rule beats work item rule beats fallback', () {
      final t = chooseMeetingTarget(
        meetingMatch: match(1, 1),
        workItemMatch: match(2, 2),
        fallback: (projectId: 3, taskId: 3),
        isAssigned: all,
      )!;
      expect(t.source, MeetingTargetSource.meetingRule);
      expect(t.projectId, 1);

      final w = chooseMeetingTarget(
        workItemMatch: match(2, 2),
        fallback: (projectId: 3, taskId: 3),
        isAssigned: all,
      )!;
      expect(w.source, MeetingTargetSource.workItemRule);

      final f = chooseMeetingTarget(
          fallback: (projectId: 3, taskId: 3), isAssigned: all)!;
      expect(f.source, MeetingTargetSource.fallback);
      expect(f.projectId, 3);
    });

    test('unassigned candidates are passed over', () {
      final t = chooseMeetingTarget(
        meetingMatch: match(1, 1),
        fallback: (projectId: 3, taskId: 3),
        isAssigned: (p, _) => p == 3,
      )!;
      expect(t.projectId, 3);
    });

    test('nothing to go on means pending', () {
      expect(chooseMeetingTarget(isAssigned: all), isNull);
    });
  });

  group('meeting rules', () {
    test('match on meeting fields', () {
      final rules = [
        MappingRule(
          id: 'a',
          name: 'Scrums',
          projectId: 7,
          taskId: 8,
          conditions: const [
            MappingCondition(
                field: MeetingField.title,
                operator: ConditionOperator.contains,
                value: 'scrum'),
            MappingCondition(
                field: MeetingField.isTeams,
                operator: ConditionOperator.equals,
                value: 'yes'),
          ],
        ),
      ];
      final scrum = event(
          summary: 'Daily Scrum | TFN', location: 'Microsoft Teams Meeting');
      expect(resolveMapping(rules, meetingMatchContext(scrum))?.projectId, 7);
      expect(resolveMapping(rules, meetingMatchContext(event())), isNull);
    });

    test('note template expands meeting placeholders', () {
      final e = event(summary: 'Declined: Retro', location: 'Room 4');
      final target = chooseMeetingTarget(
        meetingMatch: match(1, 1, noteTemplate: 'Meeting: {title} @ {location}'),
        isAssigned: (_, _) => true,
      )!;
      expect(meetingNoteFor(e, target), 'Meeting: Retro @ Room 4');
    });

    test('fallback uses the cleaned subject', () {
      final target = chooseMeetingTarget(
          fallback: (projectId: 1, taskId: 1), isAssigned: (_, _) => true)!;
      expect(meetingNoteFor(event(summary: 'Retro'), target), 'Retro');
    });
  });
}
