import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/calendar_event.dart';
import 'package:harvest/models/meeting.dart';
import 'package:harvest/providers/calendar_import_provider.dart';
import 'package:harvest/services/calendar_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/services/meeting_importer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime.utc(2026, 10, 12, 15);
final windowStart = now.subtract(const Duration(hours: 24));

CalendarEvent meeting(String summary,
    {int hour = 8, int minutes = 30, String uid = 'u', String? busy}) {
  final start = DateTime.utc(2026, 10, 12, hour);
  return CalendarEvent(
    uid: '$uid-$summary',
    summary: summary,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    busyStatus: busy ?? 'BUSY',
    description: 'Join https://teams.microsoft.com/l/meetup-join/abc',
  );
}

Map<String, dynamic> entryJson(
        {int id = 1,
        required String spentDate,
        required double hours,
        String? notes,
        Map<String, dynamic>? ref}) =>
    {
      'id': id,
      'spent_date': spentDate,
      'hours': hours,
      'notes': notes,
      'project': {'id': 7, 'name': 'Meetings'},
      'task': {'id': 9, 'name': 'Meetings'},
      'external_reference': ?ref,
    };

/// A fake Harvest: serves [existing] for GETs, records POSTed bodies, and
/// fails POSTs whose notes are in [failNotes].
class FakeHarvest {
  final List<Map<String, dynamic>> existing;
  final Set<String> failNotes;
  final posts = <Map<String, dynamic>>[];
  final gets = <Uri>[];

  FakeHarvest({this.existing = const [], this.failNotes = const {}});

  http.Client get client => MockClient((req) async {
        if (req.method == 'GET') {
          gets.add(req.url);
          return http.Response(jsonEncode({'time_entries': existing}), 200);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (failNotes.contains(body['notes'])) {
          return http.Response(jsonEncode({'message': 'Nope'}), 422);
        }
        posts.add(body);
        return http.Response(
            jsonEncode(entryJson(
                id: posts.length,
                spentDate: body['spent_date'] as String,
                hours: (body['hours'] as num).toDouble(),
                notes: body['notes'] as String?)),
            201);
      });
}

MeetingPlan planFor(CalendarEvent e) => MeetingPlan(
      target: const MeetingTarget(
          projectId: 7, taskId: 9, source: MeetingTargetSource.fallback),
      notes: meetingNotes(e),
      externalReference: meetingReference(e),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(MeetingImportResult, Set<String>)> runImport(
    FakeHarvest fake,
    List<CalendarEvent> events, {
    Set<String>? ledger,
    bool tracksByStartEnd = false,
    MeetingResolver? resolve,
  }) async {
    final keys = ledger ?? <String>{};
    final importer = MeetingImporter(
      harvest: HarvestService(client: fake.client),
      resolve: resolve ?? (e) async => planFor(e),
    );
    final result = await importer.run(
      events: events,
      windowStart: windowStart,
      now: now,
      ledger: keys,
      tracksByStartEnd: tracksByStartEnd,
      markLogged: (e) async => keys.add(meetingLedgerKey(e)),
    );
    return (result, keys);
  }

  test('logs finished meetings with hours, notes and a Teams reference',
      () async {
    final fake = FakeHarvest();
    final (result, ledger) =
        await runImport(fake, [meeting('Declined: Nope'), meeting('Standup')]);
    expect(result.logged.map((e) => e.summary), ['Standup']);
    expect(result.skipped, {MeetingSkip.declined: 1});
    final post = fake.posts.single;
    expect(post['hours'], 0.5);
    expect(post['notes'], 'Standup');
    expect(post['project_id'], 7);
    expect(post.containsKey('started_time'), isFalse);
    final ref = post['external_reference'] as Map<String, dynamic>;
    expect(ref['id'], startsWith(kMeetingRefPrefix));
    expect(ref['group_id'], 'GrainCalendarEvent');
    expect(ref['permalink'], contains('teams.microsoft.com'));
    expect(ledger, hasLength(1));
  });

  test('sends clock times only to a start/end account', () async {
    final fake = FakeHarvest();
    await runImport(fake, [meeting('Standup')], tracksByStartEnd: true);
    expect(fake.posts.single['started_time'], meetingClock(DateTime.utc(2026, 10, 12, 8)));
    expect(fake.posts.single['ended_time'], meetingClock(DateTime.utc(2026, 10, 12, 8, 30)));
  });

  test('a second run posts nothing', () async {
    final fake = FakeHarvest();
    final events = [meeting('Standup'), meeting('Retro', hour: 10)];
    final (_, ledger) = await runImport(fake, events);
    expect(fake.posts, hasLength(2));
    final (second, _) = await runImport(fake, events, ledger: ledger);
    expect(fake.posts, hasLength(2));
    expect(second.alreadyLogged, 2);
  });

  test('an entry already in Harvest is not posted again, even with an empty '
      'ledger', () async {
    final logged = meeting('Standup');
    final script = meeting('Retro', hour: 10);
    final fake = FakeHarvest(existing: [
      entryJson(
          spentDate: meetingSpentDate(logged),
          hours: 9,
          ref: {'id': meetingExternalRefId(logged)}),
      // What the Apps Script created: no reference, same date/hours/title.
      entryJson(id: 2, spentDate: meetingSpentDate(script), hours: 0.5, notes: 'Retro'),
    ]);
    final (result, _) = await runImport(fake, [logged, script]);
    expect(fake.posts, isEmpty);
    expect(result.alreadyLogged, 2);
  });

  test('a failed post is reported and not ledgered, so it retries', () async {
    final fake = FakeHarvest(failNotes: {'Retro'});
    final (result, ledger) =
        await runImport(fake, [meeting('Standup'), meeting('Retro', hour: 10)]);
    expect(result.logged, hasLength(1));
    expect(result.failed.single.message, '422: Nope');
    expect(ledger, hasLength(1));
    expect(ledger.single, contains('Standup'));
  });

  test('unplaceable meetings are pending, not posted', () async {
    final fake = FakeHarvest();
    final (result, ledger) = await runImport(fake, [meeting('Standup')],
        resolve: (_) async => null);
    expect(result.pending, hasLength(1));
    expect(fake.posts, isEmpty);
    expect(ledger, isEmpty);
  });

  test('meetings outside the window or still running are left alone',
      () async {
    final fake = FakeHarvest();
    final old = CalendarEvent(
      uid: 'old',
      summary: 'Old',
      start: windowStart.subtract(const Duration(hours: 2)),
      end: windowStart.subtract(const Duration(hours: 1)),
    );
    final running = CalendarEvent(
      uid: 'live',
      summary: 'Live',
      start: now.subtract(const Duration(minutes: 10)),
      end: now.add(const Duration(minutes: 20)),
    );
    final (result, _) = await runImport(fake, [old, running]);
    expect(fake.posts, isEmpty);
    expect(fake.gets, isEmpty, reason: 'nothing to check, so no Harvest call');
    expect(result.skipped, isEmpty);
  });

  test('afterLogged runs with the hours, and its failure keeps the entry',
      () async {
    final fake = FakeHarvest();
    double? pushed;
    final (result, ledger) = await runImport(fake, [meeting('Standup')],
        resolve: (e) async => MeetingPlan(
              target: planFor(e).target,
              notes: 'x',
              externalReference: meetingReference(e),
              afterLogged: (h) async {
                pushed = h;
                throw Exception('ADO down');
              },
            ));
    expect(pushed, 0.5);
    expect(result.logged, hasLength(1));
    expect(ledger, hasLength(1));
  });

  group('CalendarService', () {
    test('turns webcal into https and decodes UTF-8', () async {
      late Uri requested;
      final service = CalendarService(
          client: MockClient((req) async {
        requested = req.url;
        return http.Response.bytes(utf8.encode('SUMMARY:Café'), 200);
      }));
      final body = await service.fetchIcs('webcal://example.com/cal.ics');
      expect(requested.scheme, 'https');
      expect(body, 'SUMMARY:Café');
    });

    test('throws on a non-200', () async {
      final service = CalendarService(
          client: MockClient((_) async => http.Response('', 404)));
      expect(() => service.fetchIcs('https://example.com/x.ics'),
          throwsA(isA<CalendarFetchException>()));
    });
  });

  group('importWindowStart', () {
    final now = DateTime.utc(2026, 10, 12, 10);
    final lookback = now.subtract(const Duration(hours: 24));
    final enabledAt = DateTime.utc(2026, 10, 12, 9, 45);

    test('the automatic sync never reaches back past when auto-log was enabled',
        () {
      expect(
          importWindowStart(
              now: now, lookbackHours: 24, importSince: enabledAt, explicit: false),
          enabledAt);
    });

    test('Sync now and uploads use the full look-back', () {
      expect(
          importWindowStart(
              now: now, lookbackHours: 24, importSince: enabledAt, explicit: true),
          lookback);
    });

    test('an import-since older than the look-back changes nothing', () {
      expect(
          importWindowStart(
              now: now,
              lookbackHours: 24,
              importSince: DateTime.utc(2026, 10, 1),
              explicit: false),
          lookback);
      expect(
          importWindowStart(
              now: now, lookbackHours: 24, importSince: null, explicit: false),
          lookback);
    });
  });
}
