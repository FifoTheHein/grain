import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/time_entry.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const instance = AdoInstance(
  label: 'TFN Project',
  baseUrl: 'https://dev.azure.com/agile-bridge/TFN%20Project',
  pat: 'secret',
);

const completedWorkField = 'Microsoft.VSTS.Scheduling.CompletedWork';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('addCompletedWork', () {
    test('adds to whatever ADO already holds', () async {
      final requests = <http.Request>[];
      final service = AdoService(
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
                jsonEncode({
                  'fields': {completedWorkField: 2.0}
                }),
                200);
          }
          return http.Response('{}', 200);
        }),
      );

      await service.addCompletedWork(instance, '48395', 0.5);

      expect(requests.first.method, 'GET');
      final patch = requests.last;
      expect(patch.method, 'PATCH');
      expect(patch.url.path, contains('/_apis/wit/workitems/48395'));
      final body = jsonDecode(patch.body) as List<dynamic>;
      expect(body.single['path'], '/fields/$completedWorkField');
      expect(body.single['value'], 2.5);
    });

    test('treats a work item with no Completed Work as zero', () async {
      late http.Request patch;
      final service = AdoService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'fields': {}}), 200);
          }
          patch = request;
          return http.Response('{}', 200);
        }),
      );

      await service.addCompletedWork(instance, '48395', 1.25);

      expect((jsonDecode(patch.body) as List<dynamic>).single['value'], 1.25);
    });

    test('a failed read still writes, rather than skipping the sync', () async {
      late http.Request patch;
      final service = AdoService(
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('nope', 500);
          patch = request;
          return http.Response('{}', 200);
        }),
      );

      await service.addCompletedWork(instance, '48395', 0.75);

      expect((jsonDecode(patch.body) as List<dynamic>).single['value'], 0.75);
    });

    test('never writes a negative total', () async {
      late http.Request patch;
      final service = AdoService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
                jsonEncode({
                  'fields': {completedWorkField: 0.5}
                }),
                200);
          }
          patch = request;
          return http.Response('{}', 200);
        }),
      );

      await service.addCompletedWork(instance, '48395', -2);

      expect((jsonDecode(patch.body) as List<dynamic>).single['value'], 0.0);
    });

    test('a rejected patch throws rather than reporting success', () async {
      final service = AdoService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'fields': {}}), 200);
          }
          return http.Response('forbidden', 403);
        }),
      );

      expect(
        () => service.addCompletedWork(instance, '48395', 1),
        throwsA(isA<Exception>()),
      );
    });

    test('does nothing without a PAT', () async {
      var called = false;
      final service = AdoService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => service.addCompletedWork(
            const AdoInstance(label: 'No PAT', baseUrl: 'https://x/y'), '1', 1),
        throwsA(isA<Exception>()),
      );
      expect(called, isFalse, reason: 'the read is skipped too');
    });
  });

  group('entry → work item resolution', () {
    test('parses the work item id out of a composite reference', () {
      expect(
        AdoService.parseWorkItemId(
            'AzureDevOps_4b6afb17-0252-4bf2-b64a-cf7227b6f0d6_User Story_48395'),
        '48395',
      );
    });

    test('a plain numeric reference passes through', () {
      expect(AdoService.parseWorkItemId('48395'), '48395');
    });

    test('matches the instance by permalink', () {
      expect(
        instance.matchesPermalink(
            'https://dev.azure.com/agile-bridge/TFN%20Project/_workitems/edit/48395'),
        isTrue,
      );
      expect(
        instance.matchesPermalink('https://dev.azure.com/other-org/X/_workitems/edit/1'),
        isFalse,
      );
    });
  });
}
