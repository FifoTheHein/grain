import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/theme/grain_theme.dart';
import 'package:harvest/theme/theme_palettes.dart';
import 'package:harvest/widgets/duration_stepper.dart';
import 'package:harvest/widgets/log_action_bar.dart';

/// Hosts a [DurationStepper] that owns its value the way Log Time does.
class _Host extends StatefulWidget {
  final int initial;
  final void Function(int)? onChange;
  const _Host({this.initial = 0, this.onChange});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int minutes = widget.initial;

  @override
  Widget build(BuildContext context) => DurationStepper(
        minutes: minutes,
        onChanged: (m) {
          setState(() => minutes = m);
          widget.onChange?.call(m);
        },
      );
}

Widget app(Widget child) => MaterialApp(
      theme: buildGrainTheme(Brightness.light, kThemePalettes.first),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('DurationStepper', () {
    testWidgets('starts at zero with − disabled', (tester) async {
      var changes = 0;
      await tester.pumpWidget(app(_Host(onChange: (_) => changes++)));
      expect(find.text('tap to type'), findsOneWidget);
      expect(find.text('tap ±1 min · hold '), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Decrease duration'));
      await tester.pump();
      expect(changes, 0);
    });

    testWidgets('± step by 1 minute', (tester) async {
      int? last;
      await tester.pumpWidget(app(_Host(initial: 60, onChange: (m) => last = m)));
      await tester.tap(find.bySemanticsLabel('Increase duration'));
      await tester.pump();
      expect(last, 61);
      expect(find.text('1.02 hours'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Decrease duration'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Decrease duration'));
      await tester.pump();
      expect(last, 59);
    });

    testWidgets('holding + repeats a minute at a time at first',
        (tester) async {
      int? last;
      await tester.pumpWidget(app(_Host(onChange: (m) => last = m)));
      final gesture = await tester
          .startGesture(tester.getCenter(find.bySemanticsLabel('Increase duration')));
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      // One on press, then four ticks — and nothing after release.
      expect(last, 5);
    });

    testWidgets('holding longer speeds up to 5, then 15', (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(app(_Host(onChange: seen.add)));
      final gesture = await tester
          .startGesture(tester.getCenter(find.bySemanticsLabel('Increase duration')));
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      final steps = [
        for (var i = 1; i < seen.length; i++) seen[i] - seen[i - 1],
      ];
      expect(steps.take(12), everyElement(1));
      expect(steps.skip(13).take(27), everyElement(5));
      expect(steps.skip(40), everyElement(15));
      expect(seen.last, 150 + 5 * 15);
    });

    testWidgets('a chip sets the value and highlights while it matches',
        (tester) async {
      int? last;
      bool selected(String label) => tester
          .getSemantics(find.text(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
          Tristate.isTrue;
      await tester.pumpWidget(app(_Host(onChange: (m) => last = m)));
      await tester.tap(find.text('1½h'));
      await tester.pump();
      expect(last, 90);
      expect(find.text('1.5 hours'), findsOneWidget);
      expect(selected('1½h'), isTrue);
      expect(selected('2h'), isFalse);
      await tester.tap(find.bySemanticsLabel('Increase duration'));
      await tester.pump();
      expect(selected('1½h'), isFalse);
    });

    testWidgets('tapping the number accepts typed entry', (tester) async {
      int? last;
      await tester.pumpWidget(app(_Host(onChange: (m) => last = m)));
      await tester.tap(find.byKey(const ValueKey('duration-display')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('duration-field')), '1:45');
      await tester.pump();
      expect(find.text('= 1h 45m'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(last, 105);
      expect(find.text('1.75 hours'), findsOneWidget);
    });

    testWidgets('unreadable typing leaves the value alone', (tester) async {
      int? last;
      await tester.pumpWidget(app(_Host(initial: 30, onChange: (m) => last = m)));
      await tester.tap(find.byKey(const ValueKey('duration-display')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('duration-field')), 'abc');
      await tester.pump();
      expect(find.text('Try 1:45, 1.75 or 105m'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(last, isNull);
      expect(find.text('0.5 hours'), findsOneWidget);
    });
  });

  group('LogActionBar', () {
    testWidgets('disabled with a reason, and the tap is reported',
        (tester) async {
      var logged = 0;
      var disabledTaps = 0;
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: LogActionBar(
          title: 'Log 0m',
          subtitle: 'NWR001 · Development · today',
          disabledReason: 'Set a duration first',
          onLog: () => logged++,
          onDisabledTap: () => disabledTaps++,
          onStartTimer: () {},
          timerTooltip: 'Start a timer',
        ),
      )));
      expect(find.text('Log time'), findsOneWidget);
      expect(find.text('Set a duration first'), findsOneWidget);
      expect(find.text('NWR001 · Development · today'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('log-button')));
      expect(logged, 0);
      expect(disabledTaps, 1);
    });

    testWidgets('enabled shows what will be sent', (tester) async {
      var logged = 0;
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: LogActionBar(
          title: 'Log 1h 45m',
          subtitle: 'NWR001 · Development · today',
          onLog: () => logged++,
          onStartTimer: () {},
          timerTooltip: 'Start a timer',
        ),
      )));
      expect(find.text('Log 1h 45m'), findsOneWidget);
      expect(find.text('NWR001 · Development · today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('log-button')));
      expect(logged, 1);
    });

    testWidgets('timer button disabled while another runs', (tester) async {
      await tester.pumpWidget(app(Align(
        alignment: Alignment.bottomCenter,
        child: LogActionBar(
          title: 'Log 1h',
          subtitle: '',
          onLog: () {},
          onStartTimer: null,
          timerTooltip: 'Timer already running on Northwind',
        ),
      )));
      final button = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('timer-button')));
      expect(button.onPressed, isNull);
      expect(find.byTooltip('Timer already running on Northwind'), findsOneWidget);
    });
  });
}
