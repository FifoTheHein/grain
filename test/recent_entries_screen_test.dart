import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/future_days.dart';
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/calendar_import_provider.dart';
import 'package:harvest/providers/mapping_rule_provider.dart';
import 'package:harvest/providers/meeting_rule_provider.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/home_screen.dart';
import 'package:harvest/screens/recent_entries_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _fmt = DateFormat('yyyy-MM-dd');

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime _plus(int days) {
  final t = _today();
  return DateTime(t.year, t.month, t.day + days);
}

/// Harvest behind a MockClient holding one 1h 30m entry logged for
/// tomorrow. Answers each week fetch with whatever falls inside its
/// `from`/`to`, and records the ranges asked for.
class _Harvest {
  final ranges = <String>[];

  late final client = MockClient((req) async {
    if (req.url.path.endsWith('/time_entries') && req.method == 'GET') {
      final from = req.url.queryParameters['from']!;
      final to = req.url.queryParameters['to']!;
      ranges.add('$from..$to');
      final tomorrow = _fmt.format(_plus(1));
      final inRange =
          tomorrow.compareTo(from) >= 0 && tomorrow.compareTo(to) <= 0;
      return http.Response(
        jsonEncode({
          'time_entries': [
            if (inRange)
              {
                'id': 7,
                'spent_date': tomorrow,
                'hours': 1.5,
                'notes': 'Dentist, out from 13:00',
                'project': {'id': 1, 'name': 'AgileBridge Operations'},
                'task': {'id': 2, 'name': 'Leave'},
                'is_running': false,
              },
          ],
          'next_page': null,
        }),
        200,
      );
    }
    return http.Response('{}', 200);
  });
}

Future<({TimeEntryProvider entries, _Harvest harvest, List<DateTime> handedOver})>
    _pumpRecent(WidgetTester tester) async {
  // Phone layout (under the 720 px breakpoint), wide enough for the test
  // font, whose glyphs are each a full em.
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final mock = _Harvest();
  final harvest = HarvestService(client: mock.client);
  final ado = AdoService(client: MockClient((_) async => http.Response('{}', 404)));
  final entries = TimeEntryProvider(harvest);
  final instances = AdoInstanceProvider();
  final assignments = AssignmentProvider(harvest);
  final workRules = MappingRuleProvider();
  final meetingRules = MeetingRuleProvider();
  final handedOver = <DateTime>[];

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ado),
      ChangeNotifierProvider.value(value: instances),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider.value(value: entries),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
      ChangeNotifierProvider(
        create: (_) => CalendarImportProvider(
          harvest: harvest,
          entries: entries,
          ado: ado,
          adoInstances: instances,
          assignments: assignments,
          workItemRules: workRules,
          meetingRules: meetingRules,
        ),
      ),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      home: Scaffold(
        body: HomeNavigation(
          logTimeFor: handedOver.add,
          child: const RecentEntriesScreen(),
        ),
      ),
    ),
  ));
  await tester.runAsync(() => entries.loadRecentEntries(date: DateTime.now()));
  await tester.pumpAndSettle();
  return (entries: entries, harvest: mock, handedOver: handedOver);
}

Future<void> _next(WidgetTester tester, TimeEntryProvider entries) async {
  await tester.runAsync(() async {
    await tester.tap(find.byTooltip('Next day'));
    // The tap starts the load; wait for it to land.
    while (entries.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('day-title'))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('today: no Today jump and no UPCOMING tag', (tester) async {
    await _pumpRecent(tester);
    expect(_title(tester), 'Today');
    expect(find.byKey(const ValueKey('jump-today')), findsNothing);
    expect(find.text('UPCOMING'), findsNothing);
    expect(find.byKey(const ValueKey('day-total')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('day-total'))).data,
        startsWith('Total:'));
  });

  testWidgets('› moves into future days, up to the cap and no further',
      (tester) async {
    final r = await _pumpRecent(tester);

    await _next(tester, r.entries);
    expect(_title(tester), 'Tomorrow');
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.byKey(const ValueKey('jump-today')), findsOneWidget);
    // Tomorrow's entry: logged ahead, dashed, no timer.
    expect(find.byKey(const ValueKey('logged-ahead-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('planned-pill')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('day-total'))).data,
        'Logged ahead: 1h 30m');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('day-remaining'))).data,
        endsWith('to goal'));

    for (var i = 2; i <= kMaxDaysAhead; i++) {
      await _next(tester, r.entries);
    }
    final cap = _plus(kMaxDaysAhead);
    expect(r.entries.selectedDate, cap);
    expect(find.textContaining('in $kMaxDaysAhead days'), findsOneWidget);
    // The fetch followed the selection into the next week.
    final monday = DateTime(cap.year, cap.month, cap.day - (cap.weekday - 1));
    expect(r.harvest.ranges.last, startsWith(_fmt.format(monday)));

    // › is disabled at the cap.
    final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(next.onPressed, isNull);

    // A strip day past the cap stays put when tapped. The cap's week holds
    // one unless today is a Sunday, when the cap is itself a Sunday.
    final beyond = _plus(kMaxDaysAhead + 1);
    final beyondTile = find.byKey(ValueKey('week-day-${_fmt.format(beyond)}'));
    if (beyond.weekday != DateTime.monday) {
      expect(beyondTile, findsOneWidget);
      expect(tester.widget<InkWell>(beyondTile).onTap, isNull);
      await tester.tap(beyondTile);
      await tester.pumpAndSettle();
      expect(r.entries.selectedDate, cap);
    }

    // Today jumps straight back.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('jump-today')));
      while (r.entries.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    expect(_title(tester), 'Today');
  });

  testWidgets('a future day on the strip can be selected', (tester) async {
    final r = await _pumpRecent(tester);
    // Tomorrow, from today's week. On a Sunday that week has no future day
    // left, so step into next week and take the day after tomorrow.
    var target = _plus(1);
    if (_today().weekday == DateTime.sunday) {
      await _next(tester, r.entries);
      target = _plus(2);
    }
    final tile = find.byKey(ValueKey('week-day-${_fmt.format(target)}'));
    expect(tile, findsOneWidget);
    expect(tester.widget<InkWell>(tile).onTap, isNotNull);
    await tester.runAsync(() async {
      await tester.tap(tile);
      while (r.entries.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    expect(r.entries.selectedDate, target);
    expect(find.text('UPCOMING'), findsOneWidget);
  });

  testWidgets('an empty future day hands its date to Log Time',
      (tester) async {
    final r = await _pumpRecent(tester);
    await _next(tester, r.entries);
    await _next(tester, r.entries);
    final day = _plus(2);
    expect(find.textContaining('in 2 days'), findsOneWidget);
    expect(find.text('Nothing logged for ${DateFormat('EEEE').format(day)} yet'),
        findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('day-total'))).data,
        'Logged ahead: 0h');

    await tester.tap(find.byKey(const ValueKey('log-time-for-day')));
    await tester.pump();
    expect(find.text('Log time for ${DateFormat('EEE d MMM').format(day)}'),
        findsOneWidget);
    expect(r.handedOver, [day]);
  });
}
