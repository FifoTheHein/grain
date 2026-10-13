import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/day_breakdown.dart';
import 'package:harvest/models/time_entry.dart';

TimeEntry _entry(
  int id,
  double hours, {
  String? notes,
  ExternalReference? ref,
}) =>
    TimeEntry(
      id: id,
      spentDate: '2026-10-12',
      hours: hours,
      notes: notes,
      projectId: 1,
      projectName: 'TFN',
      taskId: 2,
      taskName: 'Development',
      externalReference: ref,
    );

const _meetingRef = ExternalReference(
  id: 'GrainCalendar_0123456789abcdef_1791795600',
  groupId: 'GrainCalendar',
  service: 'teams.microsoft.com',
);

ExternalReference _workItem(String id,
        {String host = 'dev.azure.com', bool composite = true}) =>
    ExternalReference(
      id: composite ? 'AzureDevOps_guid_User Story_$id' : id,
      permalink: 'https://$host/org/project/_workitems/edit/$id',
    );

void main() {
  group('meetingLoad', () {
    test('counts imported meetings against everything logged', () {
      final load = meetingLoad([
        _entry(1, 0.5, ref: _meetingRef),
        _entry(2, 1, ref: _meetingRef),
        _entry(3, 2.5),
        _entry(4, 1, ref: _workItem('47994')),
      ]);
      expect(load.count, 2);
      expect(load.minutes, 90);
      expect(load.loggedMinutes, 300);
      expect(load.percentOfLogged, 30);
    });

    test('is empty without meetings', () {
      final load = meetingLoad([_entry(1, 2)]);
      expect(load.count, 0);
      expect(load.minutes, 0);
      expect(load.percentOfLogged, 0);
      expect(meetingLoad(const []).percentOfLogged, 0);
    });

    test('a meeting linked to a work item counts as work', () {
      // Its reference slot holds the work item, so nothing marks it.
      expect(meetingLoad([_entry(1, 1, ref: _workItem('1'))]).count, 0);
    });
  });

  group('groupByWorkItem', () {
    test('groups by work item, largest first, unlinked last', () {
      final groups = groupByWorkItem([
        _entry(1, 0.5,
            ref: _workItem('50938'),
            notes: 'Agile Bridge Azure DevOps Task #50938'),
        _entry(2, 2,
            ref: _workItem('47994'),
            notes: 'Agile Bridge Azure DevOps User Story #47994 - Recon'),
        _entry(3, 1.2, ref: _workItem('47994')),
        _entry(4, 1, ref: _meetingRef, notes: 'Standup'),
        _entry(5, 3, notes: 'Other'),
      ]);

      expect(groups.map((g) => g.workItemId), ['47994', '50938', null]);
      expect(groups[0].minutes, 192);
      expect(groups[0].entries, hasLength(2));
      expect(groups[0].notesTitle, 'Recon');
      // A prefix-only note says nothing the work item doesn't.
      expect(groups[1].notesTitle, isNull);
      expect(groups[1].permalink,
          'https://dev.azure.com/org/project/_workitems/edit/50938');
      // Larger than either work item, but always last.
      expect(groups[2].isUnlinked, isTrue);
      expect(groups[2].minutes, 240);
      expect(groups[2].entries, hasLength(2));
    });

    test('the same item through either id shape is one group', () {
      final groups = groupByWorkItem([
        _entry(1, 1, ref: _workItem('123')),
        _entry(2, 1, ref: _workItem('123', composite: false)),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(2));
    });

    test('the same number on two organisations stays apart', () {
      final groups = groupByWorkItem([
        _entry(1, 1, ref: _workItem('123')),
        _entry(2, 1, ref: _workItem('123', host: 'other.visualstudio.com')),
      ]);
      expect(groups, hasLength(2));
    });

    test('leaves out the unlinked group when everything is linked', () {
      final groups = groupByWorkItem([_entry(1, 1, ref: _workItem('7'))]);
      expect(groups.map((g) => g.workItemId), ['7']);
    });
  });
}
