import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/duration_input.dart';

void main() {
  group('parseDurationInput', () {
    test('reads every accepted shape', () {
      expect(parseDurationInput('1:45'), 105);
      expect(parseDurationInput('0:05'), 5);
      expect(parseDurationInput('1.75'), 105);
      expect(parseDurationInput('1,5'), 90);
      expect(parseDurationInput('.5'), 30);
      expect(parseDurationInput('2.'), 120);
      expect(parseDurationInput('1h45'), 105);
      expect(parseDurationInput('1h 45m'), 105);
      expect(parseDurationInput('1H 45M'), 105);
      expect(parseDurationInput('2h'), 120);
      expect(parseDurationInput('1.5h'), 90);
      expect(parseDurationInput('2 hrs'), 120);
      expect(parseDurationInput('1 hour 30 minutes'), 90);
      expect(parseDurationInput('105m'), 105);
      expect(parseDurationInput('45 min'), 45);
      expect(parseDurationInput('  90  '), 90);
    });

    test('a bare whole number is minutes, a decimal is hours', () {
      expect(parseDurationInput('90'), 90);
      expect(parseDurationInput('2'), 2);
      expect(parseDurationInput('2.0'), 120);
    });

    test('rounds fractional minutes', () {
      expect(parseDurationInput('0.33'), 20);
      expect(parseDurationInput('1.01'), 61);
    });

    test('accepts zero and the 24h cap, rejects past it', () {
      expect(parseDurationInput('0'), 0);
      expect(parseDurationInput('24h'), 1440);
      expect(parseDurationInput('24:00'), 1440);
      expect(parseDurationInput('24:05'), isNull);
      expect(parseDurationInput('1441'), isNull);
      expect(parseDurationInput('25'), 25); // minutes, so fine
    });

    test('rejects nonsense', () {
      for (final bad in ['', '  ', 'abc', 'h', 'm', '1:75', '-1', '1h-5',
          '1 45', '1:2:3', '1..5']) {
        expect(parseDurationInput(bad), isNull, reason: bad);
      }
    });
  });

  test('formatDurationLabel', () {
    expect(formatDurationLabel(0), '0m');
    expect(formatDurationLabel(45), '45m');
    expect(formatDurationLabel(60), '1h');
    expect(formatDurationLabel(105), '1h 45m');
  });

  test('formatDecimalHours', () {
    expect(formatDecimalHours(105), '1.75 hours');
    expect(formatDecimalHours(60), '1 hour');
    expect(formatDecimalHours(90), '1.5 hours');
    expect(formatDecimalHours(20), '0.33 hours');
    expect(formatDecimalHours(120), '2 hours');
  });

  test('formatQuickDuration', () {
    expect(kQuickDurations.map(formatQuickDuration).toList(),
        ['15m', '30m', '45m', '1h', '1½h', '2h']);
  });

  group('stepDuration', () {
    test('steps by 5 minutes', () {
      expect(stepDuration(0, up: true), 5);
      expect(stepDuration(90, up: true), 95);
      expect(stepDuration(90, up: false), 85);
    });

    test('snaps an off-grid value onto the grid', () {
      expect(stepDuration(83, up: true), 85);
      expect(stepDuration(83, up: false), 80);
    });

    test('clamps at 0 and 24h', () {
      expect(stepDuration(0, up: false), 0);
      expect(stepDuration(3, up: false), 0);
      expect(stepDuration(1440, up: true), 1440);
      expect(stepDuration(1438, up: true), 1440);
    });
  });
}
