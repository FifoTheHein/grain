import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/providers/ado_instance_provider.dart';
import 'package:harvest/providers/assignment_provider.dart';
import 'package:harvest/providers/calendar_import_provider.dart';
import 'package:harvest/providers/mapping_rule_provider.dart';
import 'package:harvest/providers/meeting_rule_provider.dart';
import 'package:harvest/providers/project_category_provider.dart';
import 'package:harvest/providers/quick_template_provider.dart';
import 'package:harvest/providers/theme_mode_provider.dart';
import 'package:harvest/providers/theme_palette_provider.dart';
import 'package:harvest/providers/time_entry_provider.dart';
import 'package:harvest/screens/settings_screen.dart';
import 'package:harvest/services/ado_service.dart';
import 'package:harvest/services/harvest_service.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:harvest/widgets/app_version_label.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings with every provider it reads, offline: Harvest calls get an empty
/// 200 so nothing touches the network.
Widget settingsApp({required Size size}) {
  final harvest = HarvestService(
      client: MockClient((_) async => http.Response('{}', 200)));
  final ado = AdoService(client: MockClient((_) async => http.Response('{}', 200)));
  final entries = TimeEntryProvider(harvest);
  final instances = AdoInstanceProvider();
  final assignments = AssignmentProvider(harvest);
  final workRules = MappingRuleProvider();
  final meetingRules = MeetingRuleProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ado),
      ChangeNotifierProvider.value(value: instances),
      ChangeNotifierProvider.value(value: assignments),
      ChangeNotifierProvider.value(value: entries),
      ChangeNotifierProvider(create: (_) => ProjectCategoryProvider()),
      ChangeNotifierProvider.value(value: workRules),
      ChangeNotifierProvider.value(value: meetingRules),
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
      ChangeNotifierProvider(create: (_) => QuickTemplateProvider()),
      ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
      ChangeNotifierProvider(create: (_) => ThemePaletteProvider()),
    ],
    child: MaterialApp(
      theme: buildGrainTheme(Brightness.light, kThemePalettes.first),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'harvest',
      packageName: 'harvest',
      version: '1.2.5',
      buildNumber: '8',
      buildSignature: '',
    );
  });

  test('formatAppVersion', () {
    expect(formatAppVersion('1.2.5', '8'), 'Grain 1.2.5 (build 8)');
    expect(formatAppVersion('1.2.5', ''), 'Grain 1.2.5');
    expect(formatAppVersion(' ', '8'), 'Grain');
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(settingsApp(size: size));
    await tester.pump();
  }

  const groups = [
    'Harvest account',
    'Time tracking',
    'Azure DevOps',
    'Calendar',
    'Appearance',
    'Maintenance',
  ];

  group('narrow', () {
    const phone = Size(400, 900);

    testWidgets('the home list shows every group with a summary', (tester) async {
      await pumpAt(tester, phone);
      for (final title in groups) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.textContaining('refresh every'), findsOneWidget);
      expect(find.textContaining('meeting rule'), findsOneWidget);
    });

    testWidgets('the list ends with the app version', (tester) async {
      await pumpAt(tester, phone);
      await tester.pumpAndSettle();
      expect(find.text('Grain 1.2.5 (build 8)'), findsOneWidget);
    });

    testWidgets('a group opens its page and back returns to the list',
        (tester) async {
      await pumpAt(tester, phone);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Colour palette'), findsOneWidget);
      expect(find.text('Harvest account'), findsNothing,
          reason: 'the list is replaced by the page');

      await tester.tap(find.byTooltip('All settings'));
      await tester.pumpAndSettle();
      expect(find.text('Harvest account'), findsOneWidget);
      expect(find.text('Colour palette'), findsNothing);
    });

    testWidgets('every group opens without errors', (tester) async {
      await pumpAt(tester, phone);
      for (final title in groups) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
        expect(find.byTooltip('All settings'), findsOneWidget, reason: title);
        await tester.tap(find.byTooltip('All settings'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Reset to defaults asks before doing anything', (tester) async {
      await pumpAt(tester, phone);
      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(find.text('Reset to defaults?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Reset to defaults?'), findsNothing);
    });
  });

  group('wide', () {
    testWidgets('the list is a sidebar beside the open page', (tester) async {
      await pumpAt(tester, const Size(1100, 900));
      for (final title in groups) {
        expect(find.text(title), findsOneWidget);
      }
      // Harvest account opens by default, beside the list.
      expect(find.text('Harvest Credentials'), findsOneWidget);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.text('Meeting Rules'), findsOneWidget);
      expect(find.text('Harvest account'), findsOneWidget,
          reason: 'the sidebar stays');
      expect(find.byTooltip('All settings'), findsNothing);
    });

    testWidgets('the sidebar shows the app version', (tester) async {
      await pumpAt(tester, const Size(1100, 900));
      await tester.pumpAndSettle();
      expect(find.text('Grain 1.2.5 (build 8)'), findsOneWidget);
    });
  });
}
