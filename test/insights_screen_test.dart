import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/log_time_prefill.dart';
import 'package:harvest/models/time_entry.dart' show AdoInstance;
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/calendar_import_provider.dart';
import 'package:harvest/providers/mapping_rule_provider.dart';
import 'package:harvest/providers/meeting_rule_provider.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/home_screen.dart';
import 'package:harvest/screens/insights_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/harvest_tokens.dart';
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

const _instance = AdoInstance(
  label: 'Agile Bridge',
  baseUrl: 'https://dev.azure.com/ab/TFN',
  pat: 'test-pat',
);

/// An entry linked to work item [workItem] on [_instance], notes written the
/// way Log Time writes them.
Map<String, Object?> _linked(int id, String workItem, double hours,
        {String typed = ''}) =>
    {
      ..._entry(
          id,
          'Agile Bridge Azure DevOps User Story #$workItem'
          '${typed.isEmpty ? '' : ' - $typed'}',
          hours),
      'external_reference': {
        'id': 'AzureDevOps_guid_User Story_$workItem',
        'group_id': 'AzureDevOpsWorkItem',
        'permalink': '${_instance.baseUrl}/_workitems/edit/$workItem',
      },
    };

typedef _Pumped = ({
  List<(DateTime, LogTimePrefill?)> handedOver,
  CalendarImportProvider calendar,
  AdoService ado,
});

Future<_Pumped> _pumpInsights(
    WidgetTester tester, List<Map<String, Object?>> entries,
    {Map<String, Map<String, Object?>> workItems = const {}}) async {
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
    if (req.url.path.endsWith('/project_assignments')) {
      return http.Response(
          jsonEncode({'project_assignments': [], 'next_page': null}), 200);
    }
    return http.Response('{}', 200);
  });
  final harvest = HarvestService(client: client);
  final provider = TimeEntryProvider(harvest);
  final ado = AdoService(
    client: MockClient((req) async {
      final id = req.url.pathSegments.last;
      final fields = workItems[id];
      return fields == null
          ? http.Response('{}', 404)
          : http.Response(jsonEncode({'id': int.parse(id), 'fields': fields}),
              200);
    }),
  );
  final instances = AdoInstanceProvider()..instances = [_instance];
  final assignments = AssignmentProvider(harvest);
  final calendar = CalendarImportProvider(
    harvest: harvest,
    entries: provider,
    ado: ado,
    adoInstances: instances,
    assignments: assignments,
    workItemRules: MappingRuleProvider(),
    meetingRules: MeetingRuleProvider(),
  );
  final handedOver = <(DateTime, LogTimePrefill?)>[];

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
      ChangeNotifierProvider.value(value: ado),
      ChangeNotifierProvider.value(value: instances),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider.value(value: calendar),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.dark, kThemePalettes.first),
      home: Scaffold(
        body: HomeNavigation(
          logTimeFor: (date, {prefill}) => handedOver.add((date, prefill)),
          child: const InsightsScreen(),
        ),
      ),
    ),
  ));
  await tester.runAsync(() async {
    await provider.loadRecentEntries(date: _day());
    for (final id in workItems.keys) {
      await ado.fetchWorkItem(_instance, id);
    }
  });
  await tester.pumpAndSettle();
  return (handedOver: handedOver, calendar: calendar, ado: ado);
}

/// An ICS feed holding [titles] as half-hour meetings on [_day], from 10:00.
String _ics(List<String> titles) {
  String utc(DateTime local) =>
      '${DateFormat("yyyyMMdd'T'HHmmss").format(local.toUtc())}Z';
  final d = _day();
  final events = [
    for (var i = 0; i < titles.length; i++)
      [
        'BEGIN:VEVENT',
        'UID:pending-$i',
        'SUMMARY:${titles[i]}',
        'DTSTART:${utc(DateTime(d.year, d.month, d.day, 10 + i))}',
        'DTEND:${utc(DateTime(d.year, d.month, d.day, 10 + i, 30))}',
        'END:VEVENT',
      ].join('\r\n'),
  ];
  return ['BEGIN:VCALENDAR', ...events, 'END:VCALENDAR'].join('\r\n');
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
  testWidgets('Log this hands a duration to Log Time on a duration account',
      (tester) async {
    final pumped = await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _meeting(2, 'Release Planning', 14, 30, 0.5, projectId: 4),
      _entry(3, 'Development kick off', 2.25),
      _entry(4, 'Review spec', 0.75),
    ]);

    // 09:30–14:30 is 5h, but only 4h of the 8h goal is still unlogged.
    final row = find.ancestor(
        of: find.text('after CRT Daily Scrum'), matching: find.byType(Row));
    await tester.tap(
        find.descendant(of: row.first, matching: find.text('Log this')));
    await tester.pump();

    expect(pumped.handedOver, hasLength(1));
    final (date, prefill) = pumped.handedOver.single;
    expect(date, _day());
    expect(prefill!.startEnd, isFalse);
    expect(prefill.minutes, 240);
    expect(prefill.origin, 'open after CRT Daily Scrum');
  });

  testWidgets('Log this is disabled once the goal is logged', (tester) async {
    final pumped = await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _entry(2, 'Development kick off', 7.5),
    ]);

    final buttons = tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Log this'));
    expect(buttons, isNotEmpty);
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && (w.message ?? '').startsWith('Nothing left to log')),
        findsWidgets);
    await tester.tap(find.text('Log this').first, warnIfMissed: false);
    expect(pumped.handedOver, isEmpty);
  });

  testWidgets('a fully timed day hands over the gap’s own times',
      (tester) async {
    final pumped = await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _entry(2, 'Development kick off', 2,
          started: '9:30am', ended: '11:30am'),
    ]);

    // The longest gap, outlined, with nothing logged in it.
    expect(find.byKey(const ValueKey('focus-window')), findsOneWidget);
    expect(
        find.text('Longest focus window: 11:30 – 17:00 · 5h 30m '
            'with nothing logged', findRichText: true),
        findsOneWidget);

    final row = find.ancestor(
        of: find.text('11:30 – 17:00'), matching: find.byType(Row));
    await tester.tap(
        find.descendant(of: row.first, matching: find.text('Log this')));
    final prefill = pumped.handedOver.single.$2!;
    expect(prefill.startEnd, isTrue);
    expect(prefill.start, 11 * 60 + 30);
    expect(prefill.end, 17 * 60);
    expect(prefill.startCaption, 'after Development kick off');
  });

  testWidgets('the Meetings tile and the focus window on a partial day',
      (tester) async {
    await _pumpInsights(tester, [
      _meeting(1, 'CRT Daily Scrum', 9, 0, 0.5),
      _meeting(2, 'Release Planning', 14, 30, 0.5, projectId: 4),
      _entry(3, 'Development kick off', 2.25),
      _entry(4, 'Review spec', 0.75),
    ]);

    expect(find.text('Meetings'), findsOneWidget);
    // 1h of 4h logged.
    expect(find.text('25% of logged · 2 meetings'), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-window')), findsOneWidget);
    expect(
        find.text('Longest focus window: 09:30 – 14:30 · 5h with no meetings',
            findRichText: true),
        findsOneWidget);
  });

  testWidgets('no Meetings tile without imported meetings', (tester) async {
    await _pumpInsights(tester, [
      _entry(1, 'Development kick off', 2.25),
    ]);
    expect(find.text('Meetings'), findsNothing);
    expect(find.byKey(const ValueKey('focus-window')), findsNothing);
  });

  testWidgets('Where it went switches to work items and remembers it',
      (tester) async {
    await _pumpInsights(tester, [
      _linked(1, '47994', 2),
      _linked(2, '47994', 1.2),
      _linked(3, '50938', 0.75, typed: 'Rounding design'),
      _meeting(4, 'CRT Daily Scrum', 9, 0, 0.5),
    ], workItems: {
      '47994': {
        'System.Title': 'Recon process between Mamastops and TFN',
        'System.State': 'Active',
      },
    });

    expect(find.text('TFN Project Development | CRT Team · Development'),
        findsOneWidget);
    await tester.tap(find.text('Work item'));
    await tester.pumpAndSettle();

    // Cached: the ADO title, in the state's colour.
    expect(find.text('Recon process between Mamastops and TFN'),
        findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('3h 12m'), findsOneWidget);
    final id = tester.widget<Text>(find.text('#47994'));
    expect(id.style?.color, HarvestTokens.stateActive);
    // Not cached: what was typed after the prefix.
    expect(find.text('Rounding design'), findsOneWidget);
    expect(find.text('No work item'), findsOneWidget);
    expect(find.text('TFN Project Development | CRT Team · Development'),
        findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kInsightsByWorkItemKey), isTrue);
  });

  testWidgets('the remembered work item view is restored', (tester) async {
    SharedPreferences.setMockInitialValues({kInsightsByWorkItemKey: true});
    await _pumpInsights(tester, [_entry(1, 'Development kick off', 2.25)]);
    expect(find.text('No work item'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
  });

  testWidgets('unlogged meetings get a banner that opens the review sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'calendar_lookback_hours': 168});
    final pumped = await _pumpInsights(tester, [
      _entry(1, 'Development kick off', 2.25),
    ]);
    expect(find.textContaining('aren’t logged', findRichText: true),
        findsNothing);

    await tester.runAsync(() async {
      await pumped.calendar.load();
      await pumped.calendar
          .sync(icsText: _ics(['Sprint retro', 'Vendor sync']));
    });
    await tester.pumpAndSettle();

    expect(
        find.text(
            '2 meetings from yesterday aren’t logged · Sprint retro and Vendor sync need a project',
            findRichText: true),
        findsOneWidget,
        reason: pumped.calendar.error ?? '');

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('2 meetings need a project'), findsOneWidget);
  });
}
