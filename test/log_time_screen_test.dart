import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/log_time_prefill.dart';
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
import 'package:intl/intl.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Harvest behind a MockClient: one project with one task, and [entries]
/// (none by default) for every time entry fetch.
http.Client harvestMock({List<Map<String, Object?>> entries = const []}) =>
    MockClient((req) async {
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
          jsonEncode({'time_entries': entries, 'next_page': null}), 200);
    });

Future<void> pumpLogTime(WidgetTester tester,
    {List<AdoInstance> instances = const [],
    DateTime? initialDate,
    LogTimePrefill? prefill,
    http.Client? client,
    http.Client? adoClient,
    DateTime? loadWeekOf}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harvest = HarvestService(client: client ?? harvestMock());
  final assignments = AssignmentProvider(harvest);
  final adoInstances = AdoInstanceProvider()..instances = instances;
  final entries = TimeEntryProvider(harvest);
  await tester.runAsync(assignments.load);
  if (loadWeekOf != null) {
    await tester.runAsync(() => entries.loadRecentEntries(date: loadWeekOf));
  }

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => AdoService(
              client: adoClient ??
                  MockClient((_) async => http.Response('{}', 404)))),
      ChangeNotifierProvider.value(value: adoInstances),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider.value(value: entries),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
      ChangeNotifierProvider(create: (_) => MappingRuleProvider()),
      ChangeNotifierProvider(create: (_) => QuickTemplateProvider()),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      home: Scaffold(
          body: LogTimeScreen(initialDate: initialDate, prefill: prefill)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// ADO behind a MockClient: every work item is titled `Title of #id`.
http.Client adoMock() => MockClient((req) async {
      final id = req.url.pathSegments.last;
      return http.Response(
          jsonEncode({
            'fields': {
              'System.Title': 'Title of #$id',
              'System.State': 'Active',
              'System.WorkItemType': 'User Story',
            }
          }),
          200);
    });

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

    await tester.tap(find.bySemanticsLabel('End plus 1 minute'));
    await tester.pump();
    expect(find.text('09:31'), findsOneWidget);
    expect(find.text('Log 1h 1m'), findsOneWidget);
  });

  testWidgets('Tomorrow logs ahead: no timer, and a line saying so',
      (tester) async {
    await pumpLogTime(tester);
    expect(find.byKey(const ValueKey('logging-ahead')), findsNothing);
    OutlinedButton timer() => tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('timer-button')));
    expect(timer().onPressed, isNotNull);

    await tester.tap(find.text('30m'));
    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    expect(find.byKey(const ValueKey('logging-ahead')), findsOneWidget);
    expect(find.text('Logging ahead. Timers only run for today.'),
        findsOneWidget);
    expect(find.text('NWR001 · Development · tomorrow'), findsOneWidget);
    expect(timer().onPressed, isNull);
    expect(find.byTooltip('Timers only run for today'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.byKey(const ValueKey('logging-ahead')), findsNothing);
    expect(timer().onPressed, isNotNull);
  });

  testWidgets('Start & End on a future day runs from the work-day start',
      (tester) async {
    await pumpLogTime(tester);
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('Start & End'));
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(find.text('NWR001 · Development · tomorrow 08:30–09:30'),
        findsOneWidget);
  });

  testWidgets('a future day ignores what it already holds', (tester) async {
    // Tomorrow already has 1h 30m logged by duration; Start & End still
    // opens at the work-day start rather than after it.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final spent = DateFormat('yyyy-MM-dd').format(tomorrow);
    await pumpLogTime(tester,
        client: harvestMock(entries: [
          {
            'id': 9,
            'spent_date': spent,
            'hours': 1.5,
            'project': {'id': 1, 'name': 'Northwind Retail'},
            'task': {'id': 2, 'name': 'Development'},
          }
        ]),
        loadWeekOf: tomorrow);
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('Start & End'));
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(find.text('work day start'), findsOneWidget);
  });

  testWidgets('opens on a date handed over from Recent', (tester) async {
    final now = DateTime.now();
    final inThree = DateTime(now.year, now.month, now.day + 3);
    await pumpLogTime(tester, initialDate: inThree);
    await tester.tap(find.text('15m'));
    await tester.pump();
    expect(
        find.text('NWR001 · Development · ${DateFormat('EEE d MMM').format(inThree)}'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('logging-ahead')), findsOneWidget);
  });

  testWidgets('a remembered Start & End choice is restored', (tester) async {
    SharedPreferences.setMockInitialValues({kLogTimeStartEndKey: true});
    await pumpLogTime(tester);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  group('a prefill from Insights', () {
    DateTime yesterday() {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day - 1);
    }

    testWidgets('opens in Duration with the remembered mode left alone',
        (tester) async {
      SharedPreferences.setMockInitialValues({kLogTimeStartEndKey: true});
      final date = yesterday();
      await pumpLogTime(tester,
          initialDate: date,
          prefill: LogTimePrefill(
            date: date,
            startEnd: false,
            minutes: 95,
            origin: 'open after CRT Daily Scrum',
          ));

      expect(find.text('From Insights · open after CRT Daily Scrum',
          findRichText: true), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(find.text('Log 1h 35m'), findsOneWidget);
      expect(find.text('NWR001 · Development · yesterday'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kLogTimeStartEndKey), isTrue);

      // Changing the date by hand drops the prefill and the mode returns to
      // the remembered one.
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From Insights', findRichText: true),
          findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(prefs.getBool(kLogTimeStartEndKey), isTrue);
    });

    testWidgets('opens in Start & End with the slot and its captions',
        (tester) async {
      final date = yesterday();
      await pumpLogTime(tester,
          initialDate: date,
          prefill: LogTimePrefill(
            date: date,
            startEnd: true,
            start: 9 * 60 + 20,
            end: 14 * 60 + 30,
            startCaption: 'after CRT Daily Scrum',
            endCaption: 'before Release Planning',
            origin: 'open after CRT Daily Scrum',
          ));

      expect(find.text('09:20'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('after CRT Daily Scrum'), findsOneWidget);
      expect(find.text('before Release Planning'), findsOneWidget);
      expect(find.text('Log 5h 10m'), findsOneWidget);
      // Not remembered: the prefill chose the mode for this visit only.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kLogTimeStartEndKey), isNull);

      // A nudge keeps the line but the captions no longer describe the times.
      await tester.tap(find.bySemanticsLabel('End plus 1 minute'));
      await tester.pump();
      expect(find.text('14:31'), findsOneWidget);
      expect(find.text('before Release Planning'), findsNothing);
      expect(find.textContaining('From Insights', findRichText: true),
          findsOneWidget);

      // Switching mode by hand clears it and is remembered as usual.
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From Insights', findRichText: true),
          findsNothing);
      expect(prefs.getBool(kLogTimeStartEndKey), isFalse);
    });
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

  group('work item title in Notes', () {
    const instance = AdoInstance(
        label: 'Northwind',
        baseUrl: 'https://dev.azure.com/nw/p',
        pat: 'secret');

    Finder notesField() => find.widgetWithText(TextFormField, 'Notes');
    Finder idField() => find.widgetWithText(TextFormField, 'Work Item #');

    Future<void> linkItem(WidgetTester tester, String id) async {
      await tester.enterText(idField(), id);
      // The preview is debounced 600 ms, then the fetch runs.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    Future<void> tickLink(WidgetTester tester) async {
      await tester.tap(find.text('Link Azure DevOps Work Item'));
      await tester.pumpAndSettle();
    }

    String notes(WidgetTester tester) =>
        tester.widget<TextFormField>(notesField()).controller!.text;

    testWidgets('fills empty Notes with the title once it loads',
        (tester) async {
      await pumpLogTime(tester, instances: [instance], adoClient: adoMock());
      await tickLink(tester);
      await linkItem(tester, '2207');
      expect(notes(tester), 'Title of #2207');
    });

    testWidgets('leaves what you already wrote alone', (tester) async {
      await pumpLogTime(tester, instances: [instance], adoClient: adoMock());
      await tester.enterText(notesField(), 'Pairing on the retry logic');
      await tester.pump();
      await tickLink(tester);
      await linkItem(tester, '2207');
      expect(notes(tester), 'Pairing on the retry logic');
    });

    testWidgets('a different work item swaps the title, not your edit',
        (tester) async {
      await pumpLogTime(tester, instances: [instance], adoClient: adoMock());
      await tickLink(tester);
      await linkItem(tester, '2207');
      await linkItem(tester, '2208');
      expect(notes(tester), 'Title of #2208');

      await tester.enterText(notesField(), 'Title of #2208, plus my words');
      await tester.pump();
      await linkItem(tester, '2209');
      expect(notes(tester), 'Title of #2208, plus my words');
    });

    testWidgets('unlinking takes the title back out', (tester) async {
      await pumpLogTime(tester, instances: [instance], adoClient: adoMock());
      await tickLink(tester);
      await linkItem(tester, '2207');
      await tickLink(tester);
      expect(notes(tester), isEmpty);
    });
  });
}
