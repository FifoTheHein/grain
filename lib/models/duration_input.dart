/// Parsing, formatting and stepping for the duration control on Log Time.
///
/// Pure Dart, no Flutter. Everything is in whole minutes. Unit tested in
/// `test/duration_input_test.dart`.
library;

/// The longest duration the control accepts: a full day.
const int kMaxDurationMinutes = 24 * 60;

/// What a tap on ± moves by. Holding speeds up; see [holdStepMinutes].
const int kDurationStepMinutes = 1;

/// How long a ± press waits before it starts repeating, and how often it
/// repeats after that.
const Duration kHoldRepeatDelay = Duration(milliseconds: 350);
const Duration kHoldRepeatInterval = Duration(milliseconds: 90);

/// The step a held ± takes after it has been down for [held]: 1 minute at
/// first, 5 from 1.5 s, 15 from 4 s. Each step snaps onto its own grid (see
/// [stepDuration]), so a hold that started at 1h 23m runs 1h 24m, … 1h 25m,
/// 1h 30m, … 1h 45m, 2h.
int holdStepMinutes(Duration held) {
  if (held >= const Duration(milliseconds: 4000)) return 15;
  if (held >= const Duration(milliseconds: 1500)) return 5;
  return 1;
}

/// How long a press has been held at its [tick]th repeat (1-based): the
/// repeat starts [kHoldRepeatDelay] after the press and ticks every
/// [kHoldRepeatInterval] from there. Counted from ticks rather than read from
/// a clock, so the widget and its tests agree exactly.
Duration holdElapsedAtTick(int tick) =>
    kHoldRepeatDelay + kHoldRepeatInterval * tick;

/// The quick chips under the stepper, in minutes.
const List<int> kQuickDurations = [15, 30, 45, 60, 90, 120];

final _clock = RegExp(r'^(\d{1,2}):(\d{1,2})$');
final _decimal = RegExp(r'^(\d*[.,]\d+|\d+[.,])$');
final _bare = RegExp(r'^\d+$');
final _units = RegExp(
  r'^(?:(\d+(?:[.,]\d+)?)\s*h(?:ours?|rs?)?)?\s*'
  r'(?:(\d+)\s*(?:m(?:in(?:ute)?s?)?)?)?$',
);

/// Reads what was typed into the duration field as minutes.
///
/// - `1:45` — hours and minutes (minutes must be under 60)
/// - `1.75`, `1,75`, `.5` — decimal **hours**
/// - `1h45`, `1h 45m`, `1.5h`, `2 hrs` — explicit units
/// - `105m`, `45 min` — minutes
/// - a bare whole number such as `90` — **minutes**
///
/// Bare whole numbers are minutes because that is what someone typing "90"
/// or "45" almost always means; whole hours are a chip or `2h` away, and the
/// field shows how it read the text before it is committed.
///
/// Returns null for anything unreadable, negative or over
/// [kMaxDurationMinutes]. Fractions round to the nearest minute.
int? parseDurationInput(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  int? result;
  final clock = _clock.firstMatch(text);
  if (clock != null) {
    final m = int.parse(clock.group(2)!);
    if (m > 59) return null;
    result = int.parse(clock.group(1)!) * 60 + m;
  } else if (_decimal.hasMatch(text)) {
    final hours = double.tryParse(text.replaceAll(',', '.'));
    if (hours == null) return null;
    result = (hours * 60).round();
  } else if (_bare.hasMatch(text)) {
    result = int.parse(text);
  } else {
    final units = _units.firstMatch(text);
    if (units == null) return null;
    final h = units.group(1);
    final m = units.group(2);
    // "45" alone is caught above; here the text must have carried a unit.
    if (h == null && m == null) return null;
    final hours = h == null ? 0.0 : double.parse(h.replaceAll(',', '.'));
    result = (hours * 60).round() + (m == null ? 0 : int.parse(m));
  }

  if (result < 0 || result > kMaxDurationMinutes) return null;
  return result;
}

/// Hours and minutes for the big display: `(1, 5)` for 65 minutes.
({int hours, int minutes}) splitDuration(int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  return (hours: safe ~/ 60, minutes: safe % 60);
}

/// `1h 45m`, `45m`, `2h`, `0m` — the compact label used in buttons.
String formatDurationLabel(int minutes) {
  final p = splitDuration(minutes);
  if (p.hours == 0) return '${p.minutes}m';
  if (p.minutes == 0) return '${p.hours}h';
  return '${p.hours}h ${p.minutes}m';
}

/// `1.75 hours` — what Harvest will actually store.
String formatDecimalHours(int minutes) {
  final hours = minutes / 60;
  var text = hours.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text ${text == '1' ? 'hour' : 'hours'}';
}

/// Chip label: `15m`, `1h`, `1½h`, `2h`.
String formatQuickDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  if (m == 30) return '$h½h';
  return formatDurationLabel(minutes);
}

/// One press of + ([up]) or −. Moves to the next multiple of [step] in that
/// direction, so an odd value met by a bigger step, such as 1h 23m under a
/// held 5, snaps onto the grid (1h 25m, then 1h 30m) rather than staying off
/// it. Clamped to `0..max`.
int stepDuration(
  int minutes, {
  required bool up,
  int step = kDurationStepMinutes,
  int max = kMaxDurationMinutes,
}) {
  final next = up
      ? (minutes ~/ step + 1) * step
      : (minutes % step == 0 ? minutes - step : minutes ~/ step * step);
  if (next < 0) return 0;
  if (next > max) return max;
  return next;
}
