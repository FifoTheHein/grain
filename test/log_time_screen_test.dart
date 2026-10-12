import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/time_entry.dart';
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/mapping_rule_provider.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/quick_template_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/log_time_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Harvest behind a MockClient: one project with one task, no entries.
http.Client harvestMock() => MockClient((req) async {
      if (req.url.path.endsWith('/project_assignments')) {
        return http.Response(
          jsonEncode({
            'project_assignments': [
              {
                'project': {'id': 1, 'name': 'Northwind Retail', 'code': 'NWR001'},
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
      return http.Response(
          jsonEncode({'time_entries': [], 'next_page': null}), 200);
    });

Future<void> pumpLogTime(WidgetTester tester,
    {List<AdoInstance> instances = const []}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harvest = HarvestService(client: harvestMock());
  final assignments = AssignmentProvider(harvest);
  final adoInstances = AdoInstanceProvider()..instances = instances;
  await tester.runAsync(assignments.load);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => AdoService(
              client: MockClient((_) async => http.Response('{}', 404)))),
      ChangeNotifierProvider.value(value: adoInstances),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider(create: (_) => TimeEntryProvider(harvest)),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
      ChangeNotifierProvider(create: (_) => MappingRuleProvider()),
      ChangeNotifierProvider(create: (_) => QuickTemplateProvider()),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      home: const Scaffold(body: LogTimeScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens at zero with Log disabled until a duration is set',
      (tester) async {
    await pumpLogTime(tester);

    expect(find.text('Set a duration first'), findsOneWidget);
    expect(find.text('Duration must be greater than 0'), findsNothing);

    // Tapping the disabled button explains itself.
    await tester.tap(find.byKey(const ValueKey('log-button')));
    await tester.pump();
    expect(find.text('Duration must be greater than 0'), findsOneWidget);

    await tester.tap(find.text('15m'));
    await tester.pump();
    expect(find.text('Duration must be greater than 0'), findsNothing);
    expect(find.text('Log 15m'), findsOneWidget);
    expect(find.text('NWR001 · Development · today'), findsOneWidget);
  });

  testWidgets('Yesterday changes the date word on the bar', (tester) async {
    await pumpLogTime(tester);
    await tester.tap(find.text('30m'));
    await tester.tap(find.text('Yesterday'));
    await tester.pump();
    expect(find.text('NWR001 · Development · yesterday'), findsOneWidget);
  });

  testWidgets('Start & End is remembered and shows the span live',
      (tester) async {
    await pumpLogTime(tester);
    await tester.tap(find.text('Yesterday'));
    await tester.tap(find.text('Start & End'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kLogTimeStartEndKey), isTrue);

    // An empty day: work-day start (08:30) to an hour later.
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(find.text('Log 1h'), findsOneWidget);
    expect(find.text('NWR001 · Development · yesterday 08:30–09:30'),
        findsOneWidget);

    await tester.tap(find.bySemanticsLabel('End plus 5 minutes'));
    await tester.pump();
    expect(find.text('09:35'), findsOneWidget);
    expect(find.text('Log 1h 5m'), findsOneWidget);
  });

  testWidgets('a remembered Start & End choice is restored', (tester) async {
    SharedPreferences.setMockInitialValues({kLogTimeStartEndKey: true});
    await pumpLogTime(tester);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  testWidgets('a #id in the notes offers to link it', (tester) async {
    const instance =
        AdoInstance(label: 'Northwind', baseUrl: 'https://dev.azure.com/nw/p');
    await pumpLogTime(tester, instances: [instance]);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes'), 'Checkout retries for #2207');
    await tester.pump();
    expect(find.text('Found #2207 in your notes · Northwind'), findsOneWidget);

    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detected-work-item')), findsNothing);
    expect(find.widgetWithText(TextFormField, '2207'), findsOneWidget);
    // One instance: selected for you, no picker.
    expect(find.byType(SegmentedButton<AdoInstance>), findsNothing);
  });
}
