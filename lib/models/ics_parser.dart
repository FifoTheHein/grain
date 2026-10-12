/// A small iCalendar (RFC 5545) reader, scoped to what a published Outlook
/// feed contains: VEVENTs, the feed's own VTIMEZONE definitions, and recurring
/// series (RRULE / EXDATE / RECURRENCE-ID).
///
/// Pure Dart — no Flutter — and unit tested in `test/ics_parser_test.dart`.
library;

import 'calendar_event.dart';

/// Standard UTC offsets for Windows zone names seen in Outlook feeds, used only
/// when the feed does not define the zone itself. DST is not modelled here —
/// a feed's VTIMEZONE block is the source of truth when present.
const _fallbackOffsetMinutes = {
  'SOUTH AFRICA STANDARD TIME': 120,
  'ATLANTIC STANDARD TIME': -240,
  'W. EUROPE STANDARD TIME': 60,
  'GMT STANDARD TIME': 0,
  'UTC': 0,
};

/// Hard stop on generated occurrences per series, so a malformed rule can
/// never spin.
const _maxIterations = 20000;

/// Parses [text] and returns every concrete meeting overlapping
/// [windowStart, windowEnd), with recurring series expanded. All-day events
/// and events without both a start and an end are dropped.
List<CalendarEvent> parseIcs(
  String text, {
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final components = _readComponents(_unfold(text));
  final zones = <String, _TimeZone>{};
  for (final c in components.where((c) => c.name == 'VTIMEZONE')) {
    final tz = _TimeZone.fromComponent(c);
    if (tz != null) zones[tz.id.toUpperCase()] = tz;
  }
  final resolver = _DateResolver(zones);

  final masters = <_Component>[];
  final overrides = <_Component>[];
  for (final c in components.where((c) => c.name == 'VEVENT')) {
    if (c.first('RECURRENCE-ID') != null) {
      overrides.add(c);
    } else {
      masters.add(c);
    }
  }

  // Overridden occurrences, keyed by series, so expansion can leave them out.
  final overridden = <String, Set<DateTime>>{};
  for (final o in overrides) {
    final id = resolver.resolve(o.first('RECURRENCE-ID'));
    final uid = o.value('UID');
    if (id != null && uid != null) {
      overridden.putIfAbsent(uid, () => {}).add(id.utc);
    }
  }

  bool inWindow(CalendarEvent e) =>
      e.end.isAfter(windowStart) && e.start.isBefore(windowEnd);

  final results = <CalendarEvent>[];
  for (final m in masters) {
    final base = _toEvent(m, resolver);
    if (base == null) continue;
    final rule = m.value('RRULE');
    if (rule == null) {
      if (inWindow(base.event)) results.add(base.event);
      continue;
    }
    final excluded = {
      ...?overridden[base.event.uid],
      for (final p in m.all('EXDATE'))
        for (final v in p.value.split(','))
          if (resolver.resolve(p.withValue(v.trim())) case final d?) d.utc,
    };
    for (final occurrence in _expand(
      rule: _Rule.parse(rule),
      start: base.localStart,
      zone: base.zone,
      resolver: resolver,
      windowEnd: windowEnd,
    )) {
      if (excluded.contains(occurrence)) continue;
      final e = base.event.copyWith(
        start: occurrence,
        end: occurrence.add(base.event.duration),
        occurrence: occurrence,
      );
      if (inWindow(e)) results.add(e);
    }
  }

  for (final o in overrides) {
    final parsed = _toEvent(o, resolver);
    if (parsed == null) continue;
    final occurrence = resolver.resolve(o.first('RECURRENCE-ID'))?.utc;
    final e = parsed.event.copyWith(occurrence: occurrence);
    if (inWindow(e)) results.add(e);
  }

  results.sort((a, b) => a.start.compareTo(b.start));
  return results;
}

// ─── Lines and components ────────────────────────────────────────────────────

/// Joins folded continuation lines (a line break followed by a space or tab).
List<String> _unfold(String text) => text
    .replaceAll(RegExp(r'\r?\n[ \t]'), '')
    .split(RegExp(r'\r?\n'))
    .where((l) => l.isNotEmpty)
    .toList();

class _Property {
  final String name;
  final Map<String, String> params;
  final String value;

  const _Property(this.name, this.params, this.value);

  _Property withValue(String v) => _Property(name, params, v);

  static _Property? parse(String line) {
    // The value starts at the first colon outside a quoted parameter value.
    var inQuotes = false;
    var colon = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') inQuotes = !inQuotes;
      if (ch == ':' && !inQuotes) {
        colon = i;
        break;
      }
    }
    if (colon < 0) return null;
    final head = line.substring(0, colon).split(';');
    final params = <String, String>{};
    for (final p in head.skip(1)) {
      final eq = p.indexOf('=');
      if (eq < 0) continue;
      params[p.substring(0, eq).toUpperCase()] =
          p.substring(eq + 1).replaceAll('"', '');
    }
    return _Property(head.first.toUpperCase(), params, line.substring(colon + 1));
  }
}

class _Component {
  final String name;
  final List<_Property> props = [];
  final List<_Component> children = [];

  _Component(this.name);

  _Property? first(String name) =>
      props.where((p) => p.name == name).firstOrNull;

  Iterable<_Property> all(String name) => props.where((p) => p.name == name);

  String? value(String name) => first(name)?.value;
}

/// Reads top-level components (VEVENT, VTIMEZONE…) below VCALENDAR, keeping
/// one level of children for VTIMEZONE's STANDARD/DAYLIGHT blocks.
List<_Component> _readComponents(List<String> lines) {
  final top = <_Component>[];
  final stack = <_Component>[];
  for (final line in lines) {
    final prop = _Property.parse(line);
    if (prop == null) continue;
    if (prop.name == 'BEGIN') {
      final c = _Component(prop.value.trim().toUpperCase());
      if (c.name == 'VCALENDAR') continue;
      if (stack.isEmpty) {
        top.add(c);
      } else {
        stack.last.children.add(c);
      }
      stack.add(c);
    } else if (prop.name == 'END') {
      if (stack.isNotEmpty &&
          stack.last.name == prop.value.trim().toUpperCase()) {
        stack.removeLast();
      }
    } else if (stack.isNotEmpty) {
      stack.last.props.add(prop);
    }
  }
  return top;
}

String _unescape(String v) => v.replaceAllMapped(
      RegExp(r'\\([\\;,nN])'),
      (m) => switch (m.group(1)) {
        'n' || 'N' => '\n',
        final other => other!,
      },
    );

// ─── Dates and time zones ────────────────────────────────────────────────────

/// A wall-clock date-time with no zone, carried as a UTC DateTime purely so
/// its fields and arithmetic are stable.
typedef _Wall = DateTime;

_Wall? _parseWall(String v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$')
      .firstMatch(v.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
}

class _Resolved {
  final DateTime utc;
  final _Wall wall;
  final _TimeZone? zone;
  const _Resolved(this.utc, this.wall, this.zone);
}

class _DateResolver {
  final Map<String, _TimeZone> zones;
  const _DateResolver(this.zones);

  /// Resolves a DTSTART-style property to an instant. Null for date-only values.
  _Resolved? resolve(_Property? p) {
    if (p == null || p.params['VALUE']?.toUpperCase() == 'DATE') return null;
    final raw = p.value.trim();
    final wall = _parseWall(raw);
    if (wall == null) return null;
    if (raw.endsWith('Z')) return _Resolved(wall, wall, null);
    final tzid = p.params['TZID'];
    final zone = tzid == null ? null : zoneFor(tzid);
    return _Resolved(toUtc(wall, zone), wall, zone);
  }

  _TimeZone? zoneFor(String tzid) {
    final key = tzid.trim().toUpperCase();
    final defined = zones[key];
    if (defined != null) return defined;
    final fallback = _fallbackOffsetMinutes[key];
    return fallback == null ? null : _TimeZone.fixed(key, fallback);
  }

  /// Converts a wall time to UTC. With no zone the time is read as UTC —
  /// bare times are rare in Outlook feeds and UTC is the least-surprising read.
  DateTime toUtc(_Wall wall, _TimeZone? zone) => zone == null
      ? wall
      : wall.subtract(Duration(minutes: zone.offsetAt(wall)));
}

/// A yearly transition like "last Sunday of October at 03:00".
class _Transition {
  final int month;
  final int weekday; // DateTime.monday..sunday
  final int ordinal; // 1..5, or -1 for last
  final int minuteOfDay;

  const _Transition(this.month, this.weekday, this.ordinal, this.minuteOfDay);

  _Wall inYear(int year) {
    final day = _nthWeekdayOfMonth(year, month, weekday, ordinal) ?? 1;
    return DateTime.utc(year, month, day).add(Duration(minutes: minuteOfDay));
  }
}

class _TimeZone {
  final String id;
  final int standardOffset;
  final int? daylightOffset;
  final _Transition? toStandard;
  final _Transition? toDaylight;

  const _TimeZone(this.id, this.standardOffset,
      [this.daylightOffset, this.toStandard, this.toDaylight]);

  factory _TimeZone.fixed(String id, int offset) => _TimeZone(id, offset);

  static _TimeZone? fromComponent(_Component c) {
    final id = c.value('TZID');
    if (id == null) return null;
    final std = c.children.where((x) => x.name == 'STANDARD').firstOrNull;
    final dst = c.children.where((x) => x.name == 'DAYLIGHT').firstOrNull;
    final stdOffset = _parseOffset(std?.value('TZOFFSETTO'));
    if (stdOffset == null) return null;
    final dstOffset = _parseOffset(dst?.value('TZOFFSETTO'));
    final toStd = std == null ? null : _transitionOf(std);
    final toDst = dst == null ? null : _transitionOf(dst);
    if (dstOffset == null || toStd == null || toDst == null) {
      return _TimeZone(id, stdOffset);
    }
    return _TimeZone(id, stdOffset, dstOffset, toStd, toDst);
  }

  static _Transition? _transitionOf(_Component c) {
    final rule = c.value('RRULE');
    final start = _parseWall(c.value('DTSTART') ?? '');
    if (rule == null || start == null) return null;
    final r = _Rule.parse(rule);
    final month = r.byMonth.firstOrNull;
    final day = r.byDay.firstOrNull;
    if (month == null || day == null) return null;
    return _Transition(
        month, day.weekday, day.ordinal ?? 1, start.hour * 60 + start.minute);
  }

  /// UTC offset in minutes for a wall time in this zone. Works in wall time on
  /// both sides of the switch, which is exact everywhere but the hour the
  /// clocks repeat or skip.
  int offsetAt(_Wall wall) {
    final dst = daylightOffset;
    final toStd = toStandard;
    final toDst = toDaylight;
    if (dst == null || toStd == null || toDst == null) return standardOffset;
    final dstStart = toDst.inYear(wall.year);
    final dstEnd = toStd.inYear(wall.year);
    final inDst = dstStart.isBefore(dstEnd)
        // Northern hemisphere: summer sits inside the calendar year.
        ? !wall.isBefore(dstStart) && wall.isBefore(dstEnd)
        // Southern hemisphere: summer wraps the new year.
        : !wall.isBefore(dstStart) || wall.isBefore(dstEnd);
    return inDst ? dst : standardOffset;
  }
}

int? _parseOffset(String? v) {
  final m = RegExp(r'^([+-])(\d{2})(\d{2})').firstMatch(v?.trim() ?? '');
  if (m == null) return null;
  final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  return m.group(1) == '-' ? -minutes : minutes;
}

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Day of the month for the [ordinal]th [weekday] (-1 = last), or null when the
/// month has no such day (a fifth Monday).
int? _nthWeekdayOfMonth(int year, int month, int weekday, int ordinal) {
  final days = _daysInMonth(year, month);
  if (ordinal > 0) {
    final first = DateTime.utc(year, month, 1).weekday;
    final day = 1 + (weekday - first + 7) % 7 + (ordinal - 1) * 7;
    return day <= days ? day : null;
  }
  final last = DateTime.utc(year, month, days).weekday;
  final day = days - (last - weekday + 7) % 7 + (ordinal + 1) * 7;
  return day >= 1 ? day : null;
}

// ─── Recurrence ──────────────────────────────────────────────────────────────

class _ByDay {
  final int weekday;
  final int? ordinal;
  const _ByDay(this.weekday, this.ordinal);
}

const _weekdays = {
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

class _Rule {
  final String freq;
  final int interval;
  final int? count;
  final String? until;
  final List<_ByDay> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final int weekStart;

  const _Rule({
    required this.freq,
    required this.interval,
    this.count,
    this.until,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.weekStart = DateTime.monday,
  });

  factory _Rule.parse(String raw) {
    final parts = <String, String>{};
    for (final p in raw.split(';')) {
      final eq = p.indexOf('=');
      if (eq > 0) parts[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
    }
    List<int> ints(String? v) => (v ?? '')
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    return _Rule(
      freq: (parts['FREQ'] ?? '').toUpperCase(),
      interval: (int.tryParse(parts['INTERVAL'] ?? '') ?? 1).clamp(1, 1000),
      count: int.tryParse(parts['COUNT'] ?? ''),
      until: parts['UNTIL'],
      byDay: [
        for (final d in (parts['BYDAY'] ?? '').split(','))
          if (RegExp(r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$')
                  .firstMatch(d.trim().toUpperCase())
              case final m?)
            _ByDay(_weekdays[m.group(2)]!,
                m.group(1) == null ? null : int.parse(m.group(1)!)),
      ],
      byMonthDay: ints(parts['BYMONTHDAY']),
      byMonth: ints(parts['BYMONTH']),
      weekStart: _weekdays[(parts['WKST'] ?? 'MO').toUpperCase()] ??
          DateTime.monday,
    );
  }
}

/// Generates occurrence starts (UTC) for a series, from its first occurrence
/// up to [windowEnd]. Iterates in wall time so a series keeps its local clock
/// time across a DST change.
Iterable<DateTime> _expand({
  required _Rule rule,
  required _Wall start,
  required _TimeZone? zone,
  required _DateResolver resolver,
  required DateTime windowEnd,
}) sync* {
  final untilWall = rule.until == null ? null : _parseWall(rule.until!);
  final DateTime? untilUtc = untilWall == null
      ? null
      : rule.until!.endsWith('Z')
          ? untilWall
          : resolver.toUtc(untilWall, zone);
  final timeOfDay = Duration(
      hours: start.hour, minutes: start.minute, seconds: start.second);
  var emitted = 0;

  bool stop(DateTime utc) =>
      (untilUtc != null && utc.isAfter(untilUtc)) ||
      (rule.count != null && emitted >= rule.count!) ||
      !utc.isBefore(windowEnd);

  for (var period = 0; period < _maxIterations; period++) {
    final candidates = _periodDays(rule, start, period);
    if (candidates == null) return; // unsupported FREQ
    for (final day in candidates) {
      final wall = day.add(timeOfDay);
      if (wall.isBefore(start)) continue;
      final utc = resolver.toUtc(wall, zone);
      if (stop(utc)) return;
      emitted++;
      yield utc;
    }
  }
}

/// The dates (midnight, wall time) a rule produces in its [period]th interval,
/// in order. Null when the frequency is not supported.
List<_Wall>? _periodDays(_Rule rule, _Wall start, int period) {
  final startDay = DateTime.utc(start.year, start.month, start.day);
  switch (rule.freq) {
    case 'DAILY':
      return [startDay.add(Duration(days: period * rule.interval))];
    case 'WEEKLY':
      final offset = (startDay.weekday - rule.weekStart + 7) % 7;
      final weekStart = startDay
          .subtract(Duration(days: offset))
          .add(Duration(days: 7 * period * rule.interval));
      final weekdays = rule.byDay.isEmpty
          ? [startDay.weekday]
          : rule.byDay.map((d) => d.weekday).toList();
      final days = weekdays
          .map((wd) => weekStart.add(Duration(days: (wd - rule.weekStart + 7) % 7)))
          .toList()
        ..sort();
      return days;
    case 'MONTHLY':
      final monthIndex = start.month - 1 + period * rule.interval;
      final year = start.year + monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      final days = <int>[];
      if (rule.byDay.isNotEmpty) {
        for (final d in rule.byDay) {
          final ordinal = d.ordinal;
          if (ordinal != null) {
            final day = _nthWeekdayOfMonth(year, month, d.weekday, ordinal);
            if (day != null) days.add(day);
          } else {
            for (var n = 1; n <= 5; n++) {
              final day = _nthWeekdayOfMonth(year, month, d.weekday, n);
              if (day != null) days.add(day);
            }
          }
        }
      } else {
        final dim = _daysInMonth(year, month);
        for (final md in rule.byMonthDay.isEmpty ? [start.day] : rule.byMonthDay) {
          final day = md < 0 ? dim + md + 1 : md;
          if (day >= 1 && day <= dim) days.add(day);
        }
      }
      days.sort();
      return days.map((d) => DateTime.utc(year, month, d)).toList();
    case 'YEARLY':
      final year = start.year + period * rule.interval;
      if (start.day > _daysInMonth(year, start.month)) return const [];
      return [DateTime.utc(year, start.month, start.day)];
    default:
      return null;
  }
}

// ─── Events ──────────────────────────────────────────────────────────────────

class _ParsedEvent {
  final CalendarEvent event;
  final _Wall localStart;
  final _TimeZone? zone;
  const _ParsedEvent(this.event, this.localStart, this.zone);
}

_ParsedEvent? _toEvent(_Component c, _DateResolver resolver) {
  final start = resolver.resolve(c.first('DTSTART'));
  final end = resolver.resolve(c.first('DTEND'));
  if (start == null || end == null) return null;
  String? upper(String name) => c.value(name)?.trim().toUpperCase();
  String? text(String name) {
    final v = c.value(name);
    return v == null ? null : _unescape(v).trim();
  }

  final organizer = c.first('ORGANIZER');
  final mail = organizer?.value.replaceFirst(RegExp(r'^mailto:', caseSensitive: false), '');
  final uid = c.value('UID')?.trim();
  final summary = text('SUMMARY') ?? '';
  return _ParsedEvent(
    CalendarEvent(
      // A block without a UID falls back to its title, as the old script did.
      uid: (uid == null || uid.isEmpty) ? 'nouid:$summary' : uid,
      summary: summary,
      start: start.utc,
      end: end.utc,
      status: upper('STATUS'),
      busyStatus: upper('X-MICROSOFT-CDO-BUSYSTATUS'),
      transparency: upper('TRANSP'),
      classification: upper('CLASS'),
      location: text('LOCATION'),
      description: text('DESCRIPTION'),
      organizerName: organizer?.params['CN'],
      organizerEmail: (mail == null || mail.isEmpty) ? null : mail,
    ),
    start.wall,
    start.zone,
  );
}
