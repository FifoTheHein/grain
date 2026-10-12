import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/log_time_defaults.dart';
import 'package:harvest/models/time_entry.dart';

TimeEntry entry({
  int id = 1,
  double hours = 1,
  String? started,
  String? ended,
  String? notes,
  String task = 'Development',
  bool running = false,
  ExternalReference? ref,
}) =>
    TimeEntry(
      id: id,
      spentDate: '2026-10-12',
      hours: hours,
      notes: notes,
      projectId: 10,
      projectName: 'Northwind',
      taskId: 20,
      taskName: task,
      startedTime: started,
      endedTime: ended,
      isRunning: running,
      externalReference: ref,
    );

int at(int h, int m) => h * 60 + m;

void main() {
  group('lastTimedEntry', () {
    test('picks the latest end, not the latest in the list', () {
      final last = lastTimedEntry([
        entry(id: 1, started: '9:00am', ended: '10:40am', notes: 'Standup'),
        entry(id: 2, started: '8:00am', ended: '9:00am', notes: 'Email'),
        entry(id: 3, hours: 2), // untimed
      ]);
      expect(last!.entry.id, 1);
      expect(last.end, at(10, 40));
    });

    test('null when nothing carries clock times', () {
      expect(lastTimedEntry([entry(), entry(id: 2)]), isNull);
      expect(lastTimedEntry([]), isNull);
    });

    test('labels by notes, then task, stripping a work item prefix', () {
      expect(lastTimedEntry([
        entry(started: '09:00', ended: '10:00', notes: 'Standup\nmore'),
      ])!.label, 'Standup');
      expect(lastTimedEntry([
        entry(started: '09:00', ended: '10:00', notes: '  ', task: 'Meetings'),
      ])!.label, 'Meetings');
      expect(lastTimedEntry([
        entry(
          started: '09:00',
          ended: '10:00',
          notes: 'Northwind Azure DevOps Task #2207 - Checkout retries',
          ref: const ExternalReference(id: 'AzureDevOps_abc_Task_2207'),
        ),
      ])!.label, 'Checkout retries');
      expect(lastTimedEntry([
        entry(
          started: '09:00',
          ended: '10:00',
          notes: 'Northwind Azure DevOps Task #2207',
          ref: const ExternalReference(id: 'AzureDevOps_abc_Task_2207'),
        ),
      ])!.label, 'Development');
    });
  });

  group('suggestGap', () {
    final standup =
        entry(started: '10:15am', ended: '10:40am', notes: 'Standup');

    test('offers the time since the last timed entry ended', () {
      final gap = suggestGap([standup], nowMinutes: at(12, 0))!;
      expect(gap.minutes, 80);
      expect(gap.since.label, 'Standup');
      expect(gap.endClock, '10:40');
    });

    test('hidden without a timed entry', () {
      expect(suggestGap([entry(hours: 3)], nowMinutes: at(12, 0)), isNull);
      expect(suggestGap([], nowMinutes: at(12, 0)), isNull);
    });

    test('hidden under 5 minutes, shown at exactly 5', () {
      expect(suggestGap([standup], nowMinutes: at(10, 44)), isNull);
      expect(suggestGap([standup], nowMinutes: at(10, 45))!.minutes, 5);
    });

    test('hidden when the last entry ends after now', () {
      expect(suggestGap([standup], nowMinutes: at(10, 0)), isNull);
    });

    test('hidden while a timer runs', () {
      expect(
        suggestGap([standup, entry(id: 2, started: '10:40am', running: true)],
            nowMinutes: at(12, 0)),
        isNull,
      );
    });
  });

  group('startEndDefaults', () {
    final workDay = at(8, 30);

    test('starts after the last timed entry, ends now on today', () {
      final d = startEndDefaults(
        [entry(started: '9:00', ended: '10:40', notes: 'Standup')],
        workDayStart: workDay,
        isToday: true,
        nowMinutes: at(12, 0),
      );
      expect(d.start, at(10, 40));
      expect(d.end, at(12, 0));
      expect(d.startSource, StartSource.lastEntry);
      expect(d.after!.label, 'Standup');
      expect(d.endIsNow, isTrue);
    });

    test('another day ends an hour after the start', () {
      final d = startEndDefaults(
        [entry(started: '13:00', ended: '15:15')],
        workDayStart: workDay,
        isToday: false,
        nowMinutes: at(9, 0),
      );
      expect(d.start, at(15, 15));
      expect(d.end, at(16, 15));
      expect(d.endIsNow, isFalse);
    });

    test('an empty day starts at the configured work-day start', () {
      final d = startEndDefaults([],
          workDayStart: at(7, 45), isToday: false, nowMinutes: 0);
      expect(d.start, at(7, 45));
      expect(d.end, at(8, 45));
      expect(d.startSource, StartSource.workDayStart);
    });

    test('untimed entries push the start on by what is logged', () {
      final d = startEndDefaults([entry(hours: 1.5), entry(id: 2, hours: 0.5)],
          workDayStart: workDay, isToday: false, nowMinutes: 0);
      expect(d.start, at(10, 30));
      expect(d.startSource, StartSource.loggedTotal);
    });

    test('on today a start at or past now pulls back an hour', () {
      final d = startEndDefaults([],
          workDayStart: workDay, isToday: true, nowMinutes: at(8, 0));
      expect(d.start, at(7, 0));
      expect(d.end, at(8, 0));
      expect(d.startSource, StartSource.hourBeforeNow);
    });

    test('stays inside the day', () {
      final d = startEndDefaults(
        [entry(started: '22:00', ended: '23:30')],
        workDayStart: workDay,
        isToday: false,
        nowMinutes: 0,
      );
      expect(d.start, at(23, 30));
      expect(d.end, at(23, 59));
    });
  });

  test('nudgeClock clamps to the day and the ceiling', () {
    expect(nudgeClock(at(10, 0), 5), at(10, 5));
    expect(nudgeClock(at(10, 0), -5), at(9, 55));
    expect(nudgeClock(2, -5), 0);
    expect(nudgeClock(at(23, 58), 5), at(23, 59));
    expect(nudgeClock(at(11, 58), 5, ceiling: at(12, 0)), at(12, 0));
  });
}
