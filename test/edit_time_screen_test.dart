import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/time_entry.dart';
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/edit_time_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:harvest/widgets/duration_stepper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimeEntry _entry({double hours = 1.75, bool running = false}) => TimeEntry(
      id: 7,
      spentDate: '2026-10-12',
      hours: hours,
      notes: 'Pairing',
      projectId: 1,
      projectName: 'Northwind Retail',
      taskId: 2,
      taskName: 'Development',
      isRunning: running,
    );

/// Harvest behind a MockClient: one project with one task, and a PATCH that
/// echoes the entry back with whatever hours it was sent. Every PATCH body is
/// recorded in [patches].
http.Client _harvestMock(List<Map<String, dynamic>> patches) =>
    MockClient((req) async {
      if (req.url.path.endsWith('/project_assignments')) {
        return http.Response(
          jsonEncode({
            'project_assignments': [
              {
                'project': {
                  'id': 1,
                  'name': 'Northwind Retail',
                  'code': 'NWR001'
                },
                'client': {'name': 'Northwind'},
                'task_assignments': [
                  {
                    'task': {'id': 2, 'name': 'Development'}
                  }
                ],
              }
            ],
          }),
          200,
        );
      }
      if (req.method == 'PATCH') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        patches.add(body);
        return http.Response(
          jsonEncode({
            'id': 7,
            'spent_date': body['spent_date'],
            'hours': body['hours'] ?? 1.75,
            'notes': body['notes'],
            'project': {'id': 1, 'name': 'Northwind Retail'},
            'task': {'id': 2, 'name': 'Development'},
            'is_running': false,
          }),
          200,
        );
      }
      return http.Response(
          jsonEncode({'time_entries': [], 'next_page': null}), 200);
    });

Future<void> _pumpEditTime(
  WidgetTester tester,
  TimeEntry entry, {
  List<Map<String, dynamic>>? patches,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harvest = HarvestService(client: _harvestMock(patches ?? []));
  final assignments = AssignmentProvider(harvest);
  await tester.runAsync(assignments.load);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => AdoService(
              client: MockClient((_) async => http.Response('{}', 404)))),
      ChangeNotifierProvider(create: (_) => AdoInstanceProvider()),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider(
          create: (_) => TimeEntryProvider(harvest)..entries = [entry]),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      // A route under home, so the save's pop has somewhere to go.
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EditTimeScreen(entry: entry))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the stepper opens on the entry\'s hours, to the minute',
      (tester) async {
    // 1.3h is 78 minutes — the old 5-minute dropdown showed 1h 20m.
    await _pumpEditTime(tester, _entry(hours: 1.3));

    expect(find.byType(DurationStepper), findsOneWidget);
    expect(find.text('1.3 hours'), findsOneWidget);
    expect(find.text('Hours'), findsNothing);
    expect(find.text('Minutes'), findsNothing);
  });

  testWidgets('± moves the value and Update sends the new hours',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpEditTime(tester, _entry(), patches: patches);
    expect(find.text('1.75 hours'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Increase duration'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel('Increase duration'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel('Decrease duration'));
    await tester.pump(const Duration(milliseconds: 600));
    // 105 + 1 + 1 − 1 = 106 minutes.
    expect(find.text('1.77 hours'), findsOneWidget);

    await tester.tap(find.text('Update Entry'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(patches, hasLength(1));
    expect(patches.single['hours'], closeTo(106 / 60, 1e-9));
  });

  testWidgets('a quick chip sets the value', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpEditTime(tester, _entry(), patches: patches);

    await tester.tap(find.text('30m'));
    await tester.pump();
    expect(find.text('0.5 hours'), findsOneWidget);

    await tester.tap(find.text('Update Entry'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(patches.single['hours'], 0.5);
  });

  testWidgets('untouched minutes send the entry\'s own hours back',
      (tester) async {
    // 1.33h is 79.8 minutes: the stepper shows 1h 20m, but saving a notes
    // edit must not round the entry (and push the difference to ADO).
    final patches = <Map<String, dynamic>>[];
    await _pumpEditTime(tester, _entry(hours: 1.33), patches: patches);

    await tester.tap(find.text('Update Entry'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(patches.single['hours'], 1.33);
  });

  testWidgets('zero refuses to save and says why', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpEditTime(tester, _entry(hours: 0.005), patches: patches);
    // 0.005h is 18 seconds, which rounds to 0 minutes.
    expect(find.text('Duration must be greater than 0'), findsNothing);

    expect(find.text('tap to type'), findsOneWidget);
    await tester.tap(find.text('Update Entry'));
    await tester.pump();
    expect(find.text('Duration must be greater than 0'), findsOneWidget);
    expect(patches, isEmpty);
  });

  testWidgets('a running entry shows the timer panel and sends no hours',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpEditTime(tester, _entry(running: true), patches: patches);

    expect(find.text('TIMER RUNNING'), findsOneWidget);
    expect(find.text('Timing now'), findsOneWidget);
    expect(find.byType(DurationStepper), findsNothing);

    await tester.tap(find.text('Update Entry'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(patches, hasLength(1));
    expect(patches.single.containsKey('hours'), isFalse);
  });
}
