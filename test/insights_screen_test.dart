import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/insights_screen.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yesterday, so the whole 08:30–17:00 work day is in the past.
DateTime _day() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - 1);
}

String get _spentDate => DateFormat('yyyy-MM-dd').format(_day());

/// An imported meeting at [hour]:[minute] on [_day], as Harvest returns it
/// for a duration account: no clock times, the slot in the reference id.
Map<String, Object?> _meeting(int id, String title, int hour, int minute,
    double hours, {int projectId = 1}) {
  final d = _day();
  final epoch =
      DateTime(d.year, d.month, d.day, hour, minute).millisecondsSinceEpoch ~/
          1000;
  return {
    ..._entry(id, title, hours, projectId: projectId, task: 'Meetings'),
    'external_reference': {
      'id': 'GrainCalendar_0123456789abcdef_$epoch',
      'group_id': 'GrainCalendar',
    },
  };
}

Map<String, Object?> _entry(int id, String notes, double hours,
        {int projectId = 1,
        String task = 'Development',
        String? started,
        String? ended}) =>
    {
      'id': id,
      'spent_date': _spentDate,
      'hours': hours,
      'notes': notes,
      'project': {
        'id': projectId,
        'name': projectId == 4
            ? 'TFN Project Development | Support Team'
            : 'TFN Project Development | CRT Team',
      },
      'task': {'id': task == 'Meetings' ? 3 : 2, 'name': task},
      'is_running': false,
      'started_time': started,
      'ended_time': ended,
    };

Future<void> _pumpInsights(
    WidgetTester tester, List<Map<String, Object?>> entries) async {
  // Wide enough for four stat tiles in the test font, whose glyphs are each
  // a full em; tall enough that the whole list is built.
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final client = MockClient((req) async {
    if (req.url.path.endsWith('/time_entries') && req.method == 'GET') {
      return http.Response(
          jsonEncode({'time_entries': entries, 'next_page': null}), 200);
    }
    return http.Response('{}', 200);
  });
  final provider = TimeEntryProvider(HarvestService(client: client));

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      home: const Scaffold(body: InsightsScreen()),
    ),
  ));
  await tester.runAsync(() => provider.loadRecentEntries(date: _day()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a partial day places meetings and lists open stretches',
      (tester) async {
    await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _meeting(2, 'Release Planning', 14, 30, 0.5, projectId: 4),
      _entry(3, 'Development kick off', 2.25),
      _entry(4, 'Review spec', 0.75),
    ]);

    expect(find.text('The day'), findsOneWidget);
    expect(find.text('1h placed from your calendar'), findsOneWidget);
    expect(find.byKey(const ValueKey('placed-timeline')), findsOneWidget);
    // The legend names each project on the timeline, by the part after `|`.
    expect(find.text('CRT Team'), findsOneWidget);
    expect(find.text('Support Team'), findsOneWidget);
    expect(find.text('Open: other work or nothing'), findsOneWidget);
    // Hour ticks every other hour on a full work day.
    for (final tick in ['08:30', '10:00', '12:00', '14:00', '16:00', '17:00']) {
      expect(find.text(tick), findsOneWidget, reason: tick);
    }

    // 3h by duration; goal 8h − 4h logged leaves 4h.
    expect(
        find.textContaining('3h of other work isn’t on the timeline',
            findRichText: true),
        findsOneWidget);
    expect(
        find.textContaining('4h of the work day unlogged', findRichText: true),
        findsOneWidget);
    expect(find.text('Development kick off · 2h 15m'), findsOneWidget);
    expect(find.text('Review spec · 45m'), findsOneWidget);

    expect(find.text('Open between meetings'), findsOneWidget);
    expect(find.text('15m or more · longest 5h'), findsOneWidget);
    expect(find.text('before CRT Daily Scrum'), findsOneWidget);
    expect(find.text('after CRT Daily Scrum'), findsOneWidget);
    expect(find.text('09:30 – 14:30'), findsOneWidget);
    expect(find.text('after Release Planning'), findsOneWidget);

    // Totals still read; switches need a fully timed day.
    expect(find.text('from totals, no clock times needed'), findsOneWidget);
    expect(find.text('Switches'), findsNothing);
    expect(find.text('No clock times on these entries'), findsNothing);
    expect(find.textContaining('Gaps of'), findsNothing);
  });

  testWidgets('blocks are titled when wide enough, cut short if need be',
      (tester) async {
    await _pumpInsights(tester, [
      _meeting(1, 'Workshop', 10, 0, 2),
      // ~57 px: too narrow for the whole title in the test font, so it is
      // cut short rather than left out.
      _meeting(2, 'CRT Daily Scrum', 13, 0, 0.5),
      // ~19 px: no room for a title at all.
      _meeting(3, 'Quick sync', 15, 0, 1 / 6),
      _entry(4, 'Development kick off', 2.25),
    ]);

    Finder onTimeline(String text) => find.descendant(
          of: find.byKey(const ValueKey('placed-timeline')),
          matching: find.text(text),
        );
    expect(onTimeline('Workshop'), findsOneWidget);
    expect(onTimeline('CRT Daily Scrum'), findsOneWidget);
    expect(
        tester.widget<Text>(onTimeline('CRT Daily Scrum')).overflow,
        TextOverflow.ellipsis);
    expect(onTimeline('Quick sync'), findsNothing);
  });

  testWidgets('a fully timed day keeps the gap list, meetings merged in',
      (tester) async {
    await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _entry(2, 'Development kick off', 2,
          started: '9:30am', ended: '11:30am'),
    ]);

    expect(find.text('Gaps of 15m or more'), findsOneWidget);
    expect(find.text('Switches'), findsOneWidget);
    expect(find.text('still to account for'), findsOneWidget);
    // 08:30–09:00 before the meeting, 11:30–17:00 after the timed entry.
    expect(find.text('08:30 – 09:00'), findsOneWidget);
    expect(find.text('11:30 – 17:00'), findsOneWidget);
    expect(find.text('Open between meetings'), findsNothing);
    expect(find.text('The day'), findsNothing);
  });

  testWidgets('a day with nothing placeable keeps the no-clock-times card',
      (tester) async {
    await _pumpInsights(tester, [
      _entry(1, 'Development kick off', 2.25),
      _entry(2, 'Review spec', 0.75),
    ]);

    expect(find.text('No clock times on these entries'), findsOneWidget);
    expect(find.text('The day'), findsNothing);
    expect(find.text('Open between meetings'), findsNothing);
    expect(find.text('Switches'), findsNothing);
  });
}
