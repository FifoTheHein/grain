import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/entry_display.dart';
import 'package:harvest/models/time_entry.dart';

TimeEntry _entry({String? refId, String? startedTime}) => TimeEntry(
      id: 1,
      spentDate: '2026-10-12',
      hours: 0.5,
      projectId: 1,
      projectName: 'Project',
      taskId: 2,
      taskName: 'Meetings',
      externalReference: refId == null ? null : ExternalReference(id: refId),
      startedTime: startedTime,
    );

void main() {
  group('entryLabel', () {
    TimeEntry linked(String? notes) => TimeEntry(
          id: 1,
          spentDate: '2026-10-12',
          hours: 1,
          notes: notes,
          projectId: 1,
          projectName: 'Project',
          taskId: 2,
          taskName: 'Development',
          externalReference: const ExternalReference(
            id: 'AzureDevOps_guid_User Story_47994',
            permalink: 'https://dev.azure.com/ab/TFN/_workitems/edit/47994',
          ),
        );
    const prefixOnly = 'Agile Bridge Azure DevOps User Story #47994';

    test('a prefix-only note reads as the work item title', () {
      expect(entryLabel(linked(prefixOnly), workItemTitle: 'Recon process'),
          'Recon process');
    });

    test('what was typed wins over the title', () {
      expect(
          entryLabel(linked('$prefixOnly - Pairing'),
              workItemTitle: 'Recon process'),
          'Pairing');
    });

    test('falls back to the task without a title', () {
      expect(entryLabel(linked(prefixOnly)), 'Development');
      expect(entryLabel(linked(prefixOnly), workItemTitle: '  '),
          'Development');
    });
  });

  group('workItemNotesLine', () {
    const prefix = 'TFN Project Azure DevOps Task #13222';

    test('drops a note that is only the auto prefix', () {
      expect(workItemNotesLine(prefix, '13222'), isNull);
    });

    test('keeps what was typed after the prefix', () {
      expect(workItemNotesLine('$prefix - Mapped the new depot columns',
              '13222'),
          'Mapped the new depot columns');
    });

    test('a dangling separator counts as prefix only', () {
      expect(workItemNotesLine('$prefix - ', '13222'), isNull);
    });

    test('works for multi-word types and instance labels', () {
      expect(
          workItemNotesLine(
              'Agile Bridge Azure DevOps User Story #13480 - Recon', '13480'),
          'Recon');
    });

    test('a hyphenated note keeps everything after the first separator', () {
      expect(workItemNotesLine('$prefix - fix - part 2', '13222'),
          'fix - part 2');
    });

    test('a prefix for another work item is left alone', () {
      expect(workItemNotesLine(prefix, '999'), prefix);
    });

    test('notes written by hand come back unchanged', () {
      expect(workItemNotesLine('Paired on the recon export', '13222'),
          'Paired on the recon export');
    });

    test('empty and null notes give null', () {
      expect(workItemNotesLine(null, '13222'), isNull);
      expect(workItemNotesLine('   ', '13222'), isNull);
    });
  });

  group('meetingStartFromRefId', () {
    test('reads the epoch seconds as local time', () {
      final start =
          meetingStartFromRefId('GrainCalendar_0123456789abcdef_1791966600');
      expect(start, isNotNull);
      expect(start!.isUtc, isFalse);
      expect(
          start,
          DateTime.fromMillisecondsSinceEpoch(1791966600 * 1000, isUtc: true)
              .toLocal());
    });

    test('malformed or foreign ids give null', () {
      for (final id in [
        null,
        '',
        'GrainCalendar_',
        'GrainCalendar_0123456789abcdef',
        'GrainCalendar_0123456789abcdef_',
        'GrainCalendar_0123456789abcdef_12ab',
        'GrainCalendar_0123456789abcdeg_1791966600',
        'GrainCalendar_0123_1791966600',
        'GrainCalendar_0123456789abcdef_1791966600_extra',
        'AzureDevOps_guid_Task_13222',
        '13222',
      ]) {
        expect(meetingStartFromRefId(id), isNull, reason: '$id');
      }
    });
  });

  group('meetingStartLabel', () {
    test('formats the reference time as HH:mm', () {
      // 2026-10-12 08:30 local, whatever zone the test runs in.
      final local = DateTime(2026, 10, 12, 8, 30);
      final epoch = local.millisecondsSinceEpoch ~/ 1000;
      expect(
          meetingStartLabel(
              _entry(refId: 'GrainCalendar_0123456789abcdef_$epoch')),
          '08:30');
    });

    test("Harvest's clock time wins when present", () {
      final epoch = DateTime(2026, 10, 12, 8, 30).millisecondsSinceEpoch ~/
          1000;
      expect(
          meetingStartLabel(_entry(
              refId: 'GrainCalendar_0123456789abcdef_$epoch',
              startedTime: '2:15pm')),
          '14:15');
    });

    test('null for entries that are not imported meetings', () {
      expect(meetingStartLabel(_entry()), isNull);
      expect(meetingStartLabel(_entry(refId: 'AzureDevOps_g_Task_1')), isNull);
      expect(meetingStartLabel(_entry(startedTime: '9:00am')), isNull);
    });

    test('a malformed meeting id with no clock time gives null', () {
      expect(meetingStartLabel(_entry(refId: 'GrainCalendar_bad')), isNull);
    });
  });
}
