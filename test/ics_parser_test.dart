import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/calendar_event.dart';
import 'package:harvest/models/ics_parser.dart';

/// Wraps VEVENT/VTIMEZONE bodies in a calendar, CRLF-terminated like Outlook.
String cal(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${body.trim().replaceAll('\n', '\r\n')}\r\nEND:VCALENDAR\r\n';

const saTz = '''
BEGIN:VTIMEZONE
TZID:South Africa Standard Time
BEGIN:STANDARD
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T000000
TZOFFSETFROM:+0200
TZOFFSETTO:+0200
END:DAYLIGHT
END:VTIMEZONE
''';

const weTz = '''
BEGIN:VTIMEZONE
TZID:W. Europe Standard Time
BEGIN:STANDARD
DTSTART:16010101T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
''';

final wideStart = DateTime.utc(2020);
final wideEnd = DateTime.utc(2030);

List<CalendarEvent> parse(String body,
        {DateTime? from, DateTime? to}) =>
    parseIcs(cal(body), windowStart: from ?? wideStart, windowEnd: to ?? wideEnd);

void main() {
  group('lines and text', () {
    test('unfolds continuation lines and unescapes text', () {
      final events = parse('''
BEGIN:VEVENT
UID:abc
SUMMARY:Sprint planning\\, part one \\; with
  folded tail
DESCRIPTION:Line one\\nLine two
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
END:VEVENT
''');
      expect(events, hasLength(1));
      expect(events.single.summary, 'Sprint planning, part one ; with folded tail');
      expect(events.single.description, 'Line one\nLine two');
    });

    test('reads Outlook status fields upper-cased', () {
      final e = parse('''
BEGIN:VEVENT
UID:abc
SUMMARY:x
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
STATUS:confirmed
TRANSP:TRANSPARENT
CLASS:PRIVATE
X-MICROSOFT-CDO-BUSYSTATUS:Tentative
LOCATION:Microsoft Teams Meeting
ORGANIZER;CN=Jane Doe:mailto:jane@example.com
END:VEVENT
''').single;
      expect(e.status, 'CONFIRMED');
      expect(e.transparency, 'TRANSPARENT');
      expect(e.classification, 'PRIVATE');
      expect(e.busyStatus, 'TENTATIVE');
      expect(e.location, 'Microsoft Teams Meeting');
      expect(e.organizerName, 'Jane Doe');
      expect(e.organizerEmail, 'jane@example.com');
    });

    test('skips all-day events and events missing times', () {
      expect(parse('''
BEGIN:VEVENT
UID:a
SUMMARY:Public holiday
DTSTART;VALUE=DATE:20261012
DTEND;VALUE=DATE:20261013
END:VEVENT
BEGIN:VEVENT
UID:b
SUMMARY:No end
DTSTART:20261012T080000Z
END:VEVENT
'''), isEmpty);
    });
  });

  group('time zones', () {
    test('UTC values are taken as-is', () {
      final e = parse('''
BEGIN:VEVENT
UID:a
SUMMARY:x
DTSTART:20261012T080000Z
DTEND:20261012T093000Z
END:VEVENT
''').single;
      expect(e.start, DateTime.utc(2026, 10, 12, 8));
      expect(e.end, DateTime.utc(2026, 10, 12, 9, 30));
    });

    test('TZID uses the feed VTIMEZONE offset', () {
      final e = parse('''
$saTz
BEGIN:VEVENT
UID:a
SUMMARY:x
DTSTART;TZID=South Africa Standard Time:20261012T100000
DTEND;TZID=South Africa Standard Time:20261012T110000
END:VEVENT
''').single;
      expect(e.start, DateTime.utc(2026, 10, 12, 8));
    });

    test('VTIMEZONE daylight rules apply on the right side of the switch', () {
      // W. Europe leaves summer time on the last Sunday of October (25 Oct
      // 2026): 09:00 local is 07:00Z the Friday before, 08:00Z the Monday after.
      final events = parse('''
$weTz
BEGIN:VEVENT
UID:summer
SUMMARY:x
DTSTART;TZID=W. Europe Standard Time:20261023T090000
DTEND;TZID=W. Europe Standard Time:20261023T100000
END:VEVENT
BEGIN:VEVENT
UID:winter
SUMMARY:x
DTSTART;TZID=W. Europe Standard Time:20261026T090000
DTEND;TZID=W. Europe Standard Time:20261026T100000
END:VEVENT
''');
      final byUid = {for (final e in events) e.uid: e};
      expect(byUid['summer']!.start, DateTime.utc(2026, 10, 23, 7));
      expect(byUid['winter']!.start, DateTime.utc(2026, 10, 26, 8));
    });

    test('falls back to the known Windows zone table without a VTIMEZONE', () {
      final e = parse('''
BEGIN:VEVENT
UID:a
SUMMARY:x
DTSTART;TZID=South Africa Standard Time:20261012T100000
DTEND;TZID=South Africa Standard Time:20261012T110000
END:VEVENT
''').single;
      expect(e.start, DateTime.utc(2026, 10, 12, 8));
    });

    test('an unknown zone or a bare time is read as UTC', () {
      final events = parse('''
BEGIN:VEVENT
UID:a
SUMMARY:x
DTSTART;TZID=Nowhere Time:20261012T100000
DTEND;TZID=Nowhere Time:20261012T110000
END:VEVENT
BEGIN:VEVENT
UID:b
SUMMARY:x
DTSTART:20261012T100000
DTEND:20261012T110000
END:VEVENT
''');
      expect(events.map((e) => e.start),
          everyElement(DateTime.utc(2026, 10, 12, 10)));
    });
  });

  group('recurrence', () {
    List<DateTime> starts(List<CalendarEvent> events) =>
        events.map((e) => e.start).toList()..sort();

    test('a one-off event has no occurrence marker', () {
      final e = parse('''
BEGIN:VEVENT
UID:a
SUMMARY:x
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
END:VEVENT
''').single;
      expect(e.occurrence, isNull);
    });

    test('weekly BYDAY expands within the window, keeping duration', () {
      // Mon 12 Oct 2026 08:30 SAST, Mondays and Fridays.
      final events = parse('''
$saTz
BEGIN:VEVENT
UID:standup
SUMMARY:Standup
RRULE:FREQ=WEEKLY;UNTIL=20271011T063000Z;INTERVAL=1;BYDAY=MO,FR;WKST=SU
DTSTART;TZID=South Africa Standard Time:20261012T083000
DTEND;TZID=South Africa Standard Time:20261012T084500
END:VEVENT
''', from: DateTime.utc(2026, 10, 12), to: DateTime.utc(2026, 10, 24));
      expect(starts(events), [
        DateTime.utc(2026, 10, 12, 6, 30),
        DateTime.utc(2026, 10, 16, 6, 30),
        DateTime.utc(2026, 10, 19, 6, 30),
        DateTime.utc(2026, 10, 23, 6, 30),
      ]);
      expect(events.every((e) => e.duration == const Duration(minutes: 15)),
          isTrue);
      expect(events.first.occurrence, events.first.start);
    });

    test('INTERVAL=2 skips alternate weeks from the series start', () {
      final events = parse('''
BEGIN:VEVENT
UID:retro
SUMMARY:Retro
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;WKST=SU
DTSTART:20261006T120000Z
DTEND:20261006T130000Z
END:VEVENT
''', from: DateTime.utc(2026, 10, 1), to: DateTime.utc(2026, 11, 4));
      expect(starts(events), [
        DateTime.utc(2026, 10, 6, 12),
        DateTime.utc(2026, 10, 20, 12),
        DateTime.utc(2026, 11, 3, 12),
      ]);
    });

    test('UNTIL and COUNT end the series', () {
      final until = parse('''
BEGIN:VEVENT
UID:u
SUMMARY:x
RRULE:FREQ=DAILY;UNTIL=20261014T080000Z
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
END:VEVENT
''');
      expect(until, hasLength(3));
      final count = parse('''
BEGIN:VEVENT
UID:c
SUMMARY:x
RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
END:VEVENT
''');
      expect(starts(count), [
        DateTime.utc(2026, 10, 12, 8),
        DateTime.utc(2026, 10, 14, 8),
        DateTime.utc(2026, 10, 19, 8),
        DateTime.utc(2026, 10, 21, 8),
      ]);
    });

    test('COUNT counts occurrences before the window too', () {
      final events = parse('''
BEGIN:VEVENT
UID:c
SUMMARY:x
RRULE:FREQ=DAILY;COUNT=5
DTSTART:20261001T080000Z
DTEND:20261001T090000Z
END:VEVENT
''', from: DateTime.utc(2026, 10, 4), to: DateTime.utc(2026, 10, 30));
      expect(starts(events),
          [DateTime.utc(2026, 10, 4, 8), DateTime.utc(2026, 10, 5, 8)]);
    });

    test('monthly BYMONTHDAY and ordinal BYDAY', () {
      final byDay = parse('''
BEGIN:VEVENT
UID:m
SUMMARY:x
RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3
DTSTART:20260715T080000Z
DTEND:20260715T090000Z
END:VEVENT
''');
      expect(starts(byDay), [
        DateTime.utc(2026, 7, 15, 8),
        DateTime.utc(2026, 8, 15, 8),
        DateTime.utc(2026, 9, 15, 8),
      ]);
      final nth = parse('''
BEGIN:VEVENT
UID:n
SUMMARY:x
RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=2
DTSTART:20261030T080000Z
DTEND:20261030T090000Z
END:VEVENT
''');
      expect(starts(nth),
          [DateTime.utc(2026, 10, 30, 8), DateTime.utc(2026, 11, 27, 8)]);
    });

    test('EXDATE removes occurrences', () {
      final events = parse('''
$saTz
BEGIN:VEVENT
UID:x
SUMMARY:x
RRULE:FREQ=DAILY;COUNT=3
EXDATE;TZID=South Africa Standard Time:20261013T100000
DTSTART;TZID=South Africa Standard Time:20261012T100000
DTEND;TZID=South Africa Standard Time:20261012T110000
END:VEVENT
''');
      expect(starts(events),
          [DateTime.utc(2026, 10, 12, 8), DateTime.utc(2026, 10, 14, 8)]);
    });

    test('a RECURRENCE-ID override replaces its generated occurrence', () {
      final events = parse('''
$saTz
BEGIN:VEVENT
UID:series
SUMMARY:Weekly sync
RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO
DTSTART;TZID=South Africa Standard Time:20261012T100000
DTEND;TZID=South Africa Standard Time:20261012T110000
END:VEVENT
BEGIN:VEVENT
UID:series
RECURRENCE-ID;TZID=South Africa Standard Time:20261019T100000
SUMMARY:Weekly sync (moved)
DTSTART;TZID=South Africa Standard Time:20261019T140000
DTEND;TZID=South Africa Standard Time:20261019T150000
END:VEVENT
''');
      expect(events, hasLength(3));
      final moved = events.singleWhere((e) => e.summary.contains('moved'));
      expect(moved.start, DateTime.utc(2026, 10, 19, 12));
      expect(moved.occurrence, DateTime.utc(2026, 10, 19, 8));
      expect(starts(events), [
        DateTime.utc(2026, 10, 12, 8),
        DateTime.utc(2026, 10, 19, 12),
        DateTime.utc(2026, 10, 26, 8),
      ]);
    });
  });

  test('window keeps only events overlapping it', () {
    final events = parse('''
BEGIN:VEVENT
UID:before
SUMMARY:x
DTSTART:20261011T080000Z
DTEND:20261011T090000Z
END:VEVENT
BEGIN:VEVENT
UID:inside
SUMMARY:x
DTSTART:20261012T080000Z
DTEND:20261012T090000Z
END:VEVENT
''', from: DateTime.utc(2026, 10, 12), to: DateTime.utc(2026, 10, 13));
    expect(events.map((e) => e.uid), ['inside']);
  });
}
