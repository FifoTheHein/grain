import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/time_entry.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal Harvest time entry payload.
Map<String, dynamic> entryJson({
  int id = 1,
  double hours = 0,
  bool isRunning = false,
  String? timerStartedAt,
}) =>
    {
      'id': id,
      'spent_date': '2026-08-17',
      'hours': hours,
      'is_running': isRunning,
      'timer_started_at': ?timerStartedAt,
      'project': {'id': 7, 'name': 'Platform'},
      'task': {'id': 9, 'name': 'Development'},
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('create request', () {
    test('omits hours entirely when none is given — this is what starts the '
        'timer, so a null must not be sent as a zero', () {
      const request = CreateTimeEntryRequest(
        userId: 1,
        projectId: 7,
        taskId: 9,
        spentDate: '2026-08-17',
      );
      final json = request.toJson();
      expect(json.containsKey('hours'), isFalse);
      expect(json['project_id'], 7);
      expect(json['spent_date'], '2026-08-17');
    });

    test('still sends hours when logging a duration', () {
      const request = CreateTimeEntryRequest(
        userId: 1,
        projectId: 7,
        taskId: 9,
        spentDate: '2026-08-17',
        hours: 1.5,
      );
      expect(request.toJson()['hours'], 1.5);
    });

    test('a zero duration is sent, not dropped', () {
      const request = CreateTimeEntryRequest(
        userId: 1,
        projectId: 7,
        taskId: 9,
        spentDate: '2026-08-17',
        hours: 0,
      );
      expect(request.toJson()['hours'], 0);
    });
  });

  group('HarvestService timer endpoints', () {
    test('stop PATCHes /time_entries/{id}/stop', () async {
      late http.Request captured;
      final service = HarvestService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
              jsonEncode(entryJson(id: 42, hours: 0.25)), 200);
        }),
      );

      final entry = await service.stopTimeEntry(42);

      expect(captured.method, 'PATCH');
      expect(captured.url.path, endsWith('/time_entries/42/stop'));
      expect(entry.hours, 0.25);
      expect(entry.isRunning, isFalse);
    });

    test('restart PATCHes /time_entries/{id}/restart', () async {
      late http.Request captured;
      final service = HarvestService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(entryJson(
                id: 42,
                hours: 0.25,
                isRunning: true,
                timerStartedAt: '2026-08-17T09:00:00Z')),
            200,
          );
        }),
      );

      final entry = await service.restartTimeEntry(42);

      expect(captured.method, 'PATCH');
      expect(captured.url.path, endsWith('/time_entries/42/restart'));
      expect(entry.isRunning, isTrue);
      expect(entry.timerStartedAt, '2026-08-17T09:00:00Z');
    });

    test('a starting create POSTs a body without hours', () async {
      late http.Request captured;
      final service = HarvestService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
              jsonEncode(entryJson(isRunning: true)), 201);
        }),
      );

      await service.createTimeEntry(const CreateTimeEntryRequest(
        userId: 1,
        projectId: 7,
        taskId: 9,
        spentDate: '2026-08-17',
        notes: 'Standup',
      ));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.method, 'POST');
      expect(body.containsKey('hours'), isFalse);
      expect(body['notes'], 'Standup');
    });

    test('a failed stop surfaces the Harvest message', () async {
      final service = HarvestService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'message': 'Time entry is not running'}), 422)),
      );

      expect(
        () => service.stopTimeEntry(42),
        throwsA(isA<HarvestApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.message, 'message', 'Time entry is not running')),
      );
    });
  });

  group('TimeEntry timer fields', () {
    test('parses is_running and timer_started_at', () {
      final entry = TimeEntry.fromJson(entryJson(
          isRunning: true, timerStartedAt: '2026-08-17T09:00:00Z'));
      expect(entry.isRunning, isTrue);
      expect(entry.timerStartedAt, '2026-08-17T09:00:00Z');
    });

    test('a stopped entry has no timer_started_at', () {
      final entry = TimeEntry.fromJson(entryJson(hours: 2));
      expect(entry.isRunning, isFalse);
      expect(entry.timerStartedAt, isNull);
    });
  });

  group('liveHours', () {
    final fetchedAt = DateTime(2026, 8, 17, 9, 0);

    test('counts on from the fetch, not from the timer start', () {
      // Harvest's hours already covers the run up to the fetch, so only the
      // time since the fetch may be added.
      final entry = TimeEntry.fromJson(entryJson(
          hours: 1, isRunning: true, timerStartedAt: '2026-08-17T08:00:00Z'));
      final live = entry.liveHours(fetchedAt, fetchedAt.add(
        const Duration(minutes: 30),
      ));
      expect(live, closeTo(1.5, 0.001));
    });

    test('a stopped entry never ticks', () {
      final entry = TimeEntry.fromJson(entryJson(hours: 2));
      expect(entry.liveHours(fetchedAt, fetchedAt.add(const Duration(hours: 3))),
          2);
    });

    test('a clock that went backwards does not shrink the total', () {
      final entry = TimeEntry.fromJson(entryJson(hours: 1, isRunning: true));
      expect(
        entry.liveHours(fetchedAt, fetchedAt.subtract(const Duration(hours: 1))),
        1,
      );
    });
  });
}
