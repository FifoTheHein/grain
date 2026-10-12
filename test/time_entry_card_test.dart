import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/time_entry.dart';
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/edit_time_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:harvest/widgets/time_entry_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _instance = AdoInstance(
  label: 'TFN',
  baseUrl: 'https://dev.azure.com/agile/TFN',
  pat: 'pat',
);

TimeEntry _entry({
  int id = 1,
  String taskName = 'Development',
  String? notes,
  ExternalReference? ref,
  bool running = false,
  String spentDate = '2026-10-12',
}) =>
    TimeEntry(
      id: id,
      spentDate: spentDate,
      hours: 0.5,
      notes: notes,
      projectId: 10,
      projectName: 'TFN Project',
      taskId: 20,
      taskName: taskName,
      externalReference: ref,
      isRunning: running,
    );

/// One card with every provider it (and Edit Time, which a tap opens) reads.
/// Harvest gets an empty 200; ADO answers every work item fetch with #13222.
Widget _app(TimeEntry entry, {List<TimeEntry>? entries}) {
  final harvest = HarvestService(
      client: MockClient((_) async => http.Response('{}', 200)));
  final ado = AdoService(
    client: MockClient((_) async => http.Response(
          jsonEncode({
            'id': 13222,
            'fields': {
              'System.Title': 'Depot balance effect on reversals',
              'System.State': 'Active',
              'System.WorkItemType': 'Task',
              'System.CreatedBy': {'displayName': 'Heinrich Nel'},
            },
          }),
          200,
        )),
  );
  final timeEntries = TimeEntryProvider(harvest)..entries = entries ?? [entry];
  final instances = AdoInstanceProvider()..instances = [_instance];
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ado),
      ChangeNotifierProvider.value(value: instances),
      ChangeNotifierProvider(create: (_) => AssignmentProvider(harvest)),
      ChangeNotifierProvider.value(value: timeEntries),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.light, kThemePalettes.first),
      home: Scaffold(body: ListView(children: [TimeEntryCard(entry: entry)])),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('compact card has no pencil, and a tap opens Edit Time',
      (tester) async {
    await tester.pumpWidget(_app(_entry(notes: 'PR Reviews')));
    await tester.pump();

    expect(find.text('Development'), findsOneWidget);
    expect(find.text('PR Reviews'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('Edit entry'), findsNothing);
    expect(find.byTooltip('Continue timing this entry'), findsOneWidget);

    await tester.tap(find.text('PR Reviews'));
    await tester.pumpAndSettle();
    expect(find.byType(EditTimeScreen), findsOneWidget);
  });

  testWidgets('a work item entry keeps the preview and drops a prefix note',
      (tester) async {
    await tester.pumpWidget(_app(_entry(
      notes: 'TFN Azure DevOps Task #13222',
      ref: const ExternalReference(
        id: 'AzureDevOps_guid_Task_13222',
        permalink: 'https://dev.azure.com/agile/TFN/_workitems/edit/13222',
      ),
    )));
    // First frame schedules the fetch; the next ones render the result.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Depot balance effect on reversals'), findsOneWidget);
    expect(find.text('#13222'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('HN'), findsOneWidget);
    expect(find.text('TFN Azure DevOps Task #13222'), findsNothing);
  });

  testWidgets('a work item note shows only what was typed after the prefix',
      (tester) async {
    await tester.pumpWidget(_app(_entry(
      notes: 'TFN Azure DevOps Task #13222 - Mapped the depot columns',
      ref: const ExternalReference(
        id: 'AzureDevOps_guid_Task_13222',
        permalink: 'https://dev.azure.com/agile/TFN/_workitems/edit/13222',
      ),
    )));
    await tester.pump();

    expect(find.text('Mapped the depot columns'), findsOneWidget);
  });

  testWidgets('an imported meeting shows a calendar marker and its start',
      (tester) async {
    final epoch =
        DateTime(2026, 10, 12, 8, 30).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(_app(_entry(
      taskName: 'Meetings',
      notes: 'Morning Check-in',
      ref: ExternalReference(
        id: 'GrainCalendar_0123456789abcdef_$epoch',
        groupId: 'GrainCalendar',
      ),
    )));
    await tester.pump();

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('Morning Check-in'), findsOneWidget);
  });

  testWidgets('an ordinary entry shows no meeting marker', (tester) async {
    await tester.pumpWidget(_app(_entry(notes: 'PR Reviews')));
    await tester.pump();

    expect(find.byIcon(Icons.event_outlined), findsNothing);
  });

  testWidgets('the running entry shows Stop and an accent border',
      (tester) async {
    final running = _entry(running: true);
    await tester.pumpWidget(_app(running));
    await tester.pump();

    expect(find.byTooltip('Stop timer'), findsOneWidget);
    expect(find.byTooltip('Continue timing this entry'), findsNothing);

    final card = tester.widget<Card>(find.byType(Card));
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.side.color, kThemePalettes.first.light.brand);
  });

  testWidgets('Continue is disabled while another entry runs', (tester) async {
    final stopped = _entry(id: 1);
    await tester.pumpWidget(
        _app(stopped, entries: [stopped, _entry(id: 2, running: true)]));
    await tester.pump();

    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.play_circle_outline),
      matching: find.byType(IconButton),
    ));
    expect(button.onPressed, isNull);
    expect(find.byTooltip('Stop the running timer first'), findsOneWidget);
  });

  testWidgets('an entry logged ahead has a dashed pill and no Continue',
      (tester) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final ahead = _entry(
        spentDate:
            '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-'
            '${tomorrow.day.toString().padLeft(2, '0')}');
    await tester.pumpWidget(_app(ahead));
    await tester.pump();

    expect(find.byKey(const ValueKey('planned-pill')), findsOneWidget);
    final button = tester
        .widget<IconButton>(find.byKey(const ValueKey('continue-timer')));
    expect(button.onPressed, isNull);
    expect(find.byTooltip('Timers only run for today'), findsOneWidget);
    expect(find.byTooltip('Continue timing this entry'), findsNothing);
  });

  testWidgets('an entry for today keeps its solid pill and Continue',
      (tester) async {
    final now = DateTime.now();
    final today = _entry(
        spentDate: '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}');
    await tester.pumpWidget(_app(today));
    await tester.pump();

    expect(find.byKey(const ValueKey('planned-pill')), findsNothing);
    final button = tester
        .widget<IconButton>(find.byKey(const ValueKey('continue-timer')));
    expect(button.onPressed, isNotNull);
  });
}
