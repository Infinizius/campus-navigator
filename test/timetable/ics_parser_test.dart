import 'package:campus_navigator/api/timetable/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String calendar(String events, {String extra = ''}) => '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Campus Navigator//Timetable Test//EN
$extra$events
END:VCALENDAR
''';

String event(String body) => '''
BEGIN:VEVENT
$body
END:VEVENT
''';

void main() {
  test('parses_single_event_and_unescapes_text', () {
    final parsed = parseIcsCalendar(calendar(event('''
UID:lecture-1
DTSTART:20261014T090000
DTEND:20261014T104500
SUMMARY:Line 1\\nLine 2\\, continued
DESCRIPTION:Bring a\\; pencil
LOCATION:APB E069
''')));

    expect(parsed.series, hasLength(1));
    expect(parsed.series.single.uid, 'lecture-1');
    expect(parsed.series.single.summary, 'Line 1\nLine 2, continued');
    expect(parsed.series.single.description, 'Bring a; pencil');
    expect(parsed.series.single.location, 'APB E069');
    expect(parsed.series.single.start.value, '20261014T090000');
    expect(parsed.series.single.end!.value, '20261014T104500');
  });

  test('parses_all_day_exclusive_end', () {
    final parsed = parseIcsCalendar(calendar(event('''
UID:block-1
DTSTART;VALUE=DATE:20261014
DTEND;VALUE=DATE:20261016
SUMMARY:Conference
''')));

    expect(parsed.series.single.start.kind.name, 'date');
    expect(parsed.series.single.start.value, '20261014');
    expect(parsed.series.single.end!.value, '20261016');
  });

  test('parses_duration_event', () {
    final parsed = parseIcsCalendar(calendar(event('''
UID:duration-1
DTSTART:20261014T090000Z
DURATION:PT90M
SUMMARY:Lab
''')));

    expect(parsed.series.single.duration, const Duration(minutes: 90));
    expect(parsed.series.single.start.kind.name, 'utc');
  });

  test('preserves_tzid_and_recurrence_identity', () {
    final parsed = parseIcsCalendar(calendar(event('''
UID:weekly-1
DTSTART;TZID=Europe/Berlin:20261014T090000
DTEND;TZID=Europe/Berlin:20261014T104500
RRULE:FREQ=WEEKLY;COUNT=8;BYDAY=WE
EXDATE;TZID=Europe/Berlin:20261028T090000,20261104T090000
SUMMARY:Seminar
''') + event('''
UID:weekly-1
RECURRENCE-ID;TZID=Europe/Berlin:20261028T090000
DTSTART;TZID=Europe/Berlin:20261029T110000
DTEND;TZID=Europe/Berlin:20261029T124500
SUMMARY:Seminar moved
''')));

    final series = parsed.series.single;
    expect(series.start.timeZoneId, 'Europe/Berlin');
    expect(series.recurrenceRule, 'FREQ=WEEKLY;COUNT=8;BYDAY=WE');
    expect(series.exclusions, hasLength(2));
    expect(series.overrides, hasLength(1));
    expect(series.overrides.single.recurrenceId.value, '20261028T090000');
    expect(series.overrides.single.start!.value, '20261029T110000');
  });

  test('combines_repeated_exdate_lines', () {
    final parsed = parseIcsCalendar(calendar(event('''
UID:weekly-2
DTSTART;TZID=Europe/Berlin:20261014T090000
DTEND;TZID=Europe/Berlin:20261014T100000
RRULE:FREQ=WEEKLY
EXDATE;TZID=Europe/Berlin:20261021T090000
EXDATE;TZID=Europe/Berlin:20261028T090000
SUMMARY:Seminar
''')));

    expect(parsed.series.single.exclusions.map((e) => e.value),
        ['20261021T090000', '20261028T090000']);
  });

  test('rejects_duplicate_uid_and_incomplete_event', () {
    final duplicate = event('''
UID:dup
DTSTART:20261014T090000
DTEND:20261014T100000
SUMMARY:A
''');
    expect(
      () => parseIcsCalendar(calendar(duplicate + duplicate)),
      throwsA(isA<IcsImportException>()),
    );
    expect(
      () => parseIcsCalendar(calendar(event('''
UID:missing-end
DTSTART:20261014T090000
SUMMARY:Incomplete
'''))),
      throwsA(isA<IcsImportException>()),
    );
  });

  test('rejects_unknown_tzid', () {
    expect(
      () => parseIcsCalendar(calendar(event('''
UID:unknown-zone
DTSTART;TZID=Moon/Base:20261014T090000
DTEND;TZID=Moon/Base:20261014T100000
SUMMARY:Unknown
'''))),
      throwsA(isA<IcsImportException>()),
    );
  });

  test('rejects_malformed_rrule_before_import', () {
    expect(
      () => parseIcsCalendar(calendar(event('''
UID:bad-rule
DTSTART:20261014T090000
DTEND:20261014T100000
SUMMARY:Bad rule
RRULE:FREQ=NOT_A_FREQUENCY
'''))),
      throwsA(isA<IcsImportException>()),
    );
  });

  test('rejects_rdate_multiple_rrules_and_range', () {
    const base = '''
UID:unsupported
DTSTART:20261014T090000
DTEND:20261014T100000
SUMMARY:Unsupported
''';
    for (final extra in [
      'RDATE:20261021T090000\n',
      'RRULE:FREQ=WEEKLY\nRRULE:FREQ=MONTHLY\n',
      'RECURRENCE-ID;RANGE=THISANDFUTURE:20261021T090000\n',
    ]) {
      expect(
        () => parseIcsCalendar(calendar(event('$base$extra'))),
        throwsA(isA<IcsImportException>()),
        reason: 'must reject $extra',
      );
    }
  });

  test('rejects_mismatched_iana_vtimezone', () {
    const zone = '''
BEGIN:VTIMEZONE
TZID:Europe/Berlin
BEGIN:STANDARD
DTSTART:20261025T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
END:STANDARD
END:VTIMEZONE
''';
    expect(
      () => parseIcsCalendar(calendar(event('''
UID:mismatch
DTSTART;TZID=Europe/Berlin:20261014T090000
DTEND;TZID=Europe/Berlin:20261014T100000
SUMMARY:Mismatch
'''), extra: zone)),
      throwsA(isA<IcsImportException>()),
    );
  });

  test('accepts_matching_iana_vtimezone', () {
    const zone = '''
BEGIN:VTIMEZONE
TZID:Europe/Berlin
BEGIN:DAYLIGHT
DTSTART:19700329T020000
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
END:DAYLIGHT
BEGIN:STANDARD
DTSTART:19701025T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
END:STANDARD
END:VTIMEZONE
''';
    final parsed = parseIcsCalendar(calendar(event('''
UID:matching-zone
DTSTART;TZID=Europe/Berlin:20261014T090000
DTEND;TZID=Europe/Berlin:20261014T100000
SUMMARY:Berlin lecture
'''), extra: zone));

    expect(parsed.series.single.start.timeZoneId, 'Europe/Berlin');
  });
}
