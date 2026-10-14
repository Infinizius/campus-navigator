import 'package:campus_navigator/api/timetable/recurrence_expander.dart';
import 'package:campus_navigator/api/timetable/timetable_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

IcsTemporal floating(String value) =>
    IcsTemporal(value: value, kind: IcsTemporalKind.floating);
IcsTemporal utc(String value) =>
    IcsTemporal(value: value, kind: IcsTemporalKind.utc);
IcsTemporal berlin(String value) => IcsTemporal(
      value: value,
      kind: IcsTemporalKind.zoned,
      timeZoneId: 'Europe/Berlin',
    );
IcsTemporal date(String value) =>
    IcsTemporal(value: value, kind: IcsTemporalKind.date);

TimetableSeries series({
  required IcsTemporal start,
  IcsTemporal? end,
  Duration? duration,
  String? rule,
  List<IcsTemporal> exclusions = const [],
  List<TimetableOverride> overrides = const [],
}) =>
    TimetableSeries(
      uid: 'class-1',
      summary: 'Synthetic lecture',
      location: 'APB E069',
      start: start,
      end: end,
      duration: duration,
      recurrenceRule: rule,
      exclusions: exclusions,
      overrides: overrides,
    );

DateTime basicUtc(String value) {
  final parts = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$')
      .firstMatch(value)!;
  return DateTime.utc(
    int.parse(parts[1]!),
    int.parse(parts[2]!),
    int.parse(parts[3]!),
    int.parse(parts[4]!),
    int.parse(parts[5]!),
    int.parse(parts[6]!),
  );
}

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  test('expands_weekly_series', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
          rule: 'FREQ=WEEKLY;COUNT=3',
        ),
      ],
      DateTime(2026, 10, 14),
      DateTime(2026, 11, 5),
    );

    // ignore: avoid_print
    expect(events.map((event) => event.start.day), [14, 21, 28]);
    expect(events.every((event) => event.start.hour == 9), isTrue);
  });

  test('berlin_weekly_series_keeps_wall_time_across_dst', () {
    final location = tz.getLocation('Europe/Berlin');
    final events = expandTimetable(
      [
        series(
          start: berlin('20261021T090000'),
          end: berlin('20261021T100000'),
          rule: 'FREQ=WEEKLY;COUNT=4',
        ),
      ],
      tz.TZDateTime(location, 2026, 10, 21),
      tz.TZDateTime(location, 2026, 11, 15),
    );

    expect(events, hasLength(4));
    expect(events.map((event) => event.start.hour), everyElement(9));
    expect(events.map((event) => event.start.timeZoneOffset.inHours),
        [2, 1, 1, 1]);
  });

  test('all_day_series_preserves_calendar_days', () {
    final events = expandTimetable(
      [
        series(
          start: date('20261014'),
          end: date('20261016'),
          rule: 'FREQ=DAILY;COUNT=2',
        ),
      ],
      DateTime(2026, 10, 14),
      DateTime(2026, 10, 18),
    );

    // ignore: avoid_print
    expect(events, hasLength(2));
    expect(events.every((event) => event.allDay), isTrue);
    expect(events.map((event) => event.start.day), [14, 15]);
    expect(events.first.end.day, 16);
  });

  test('exdate_removes_matching_occurrence', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
          rule: 'FREQ=WEEKLY;COUNT=3',
          exclusions: [floating('20261021T090000')],
        ),
      ],
      DateTime(2026, 10, 14),
      DateTime(2026, 11, 1),
    );

    expect(events.map((event) => event.start.day), [14, 28]);
  });

  test('applies_moved_and_cancelled_overrides', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
          rule: 'FREQ=WEEKLY;COUNT=3',
          overrides: [
            TimetableOverride(
              recurrenceId: floating('20261021T090000'),
              cancelled: false,
              start: floating('20261022T110000'),
              end: floating('20261022T120000'),
              summary: 'Moved lecture',
            ),
            TimetableOverride(
              recurrenceId: floating('20261028T090000'),
              cancelled: true,
            ),
          ],
        ),
      ],
      DateTime(2026, 10, 14),
      DateTime(2026, 11, 1),
    );

    expect(events, hasLength(2));
    expect(events.map((event) => event.start.day), [14, 22]);
    expect(events.last.start.hour, 11);
    expect(events.last.title, 'Moved lecture');
  });

  test('includes_dtstart_even_when_byday_excludes_it', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
          rule: 'FREQ=WEEKLY;COUNT=2;BYDAY=MO',
        ),
      ],
      DateTime(2026, 10, 12),
      DateTime(2026, 10, 21),
    );

    expect(events.map((event) => event.start.day), [14, 19]);
  });

  test('count_is_not_restarted_by_late_window', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
          rule: 'FREQ=WEEKLY;COUNT=3',
        ),
      ],
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 26),
    );

    expect(events.map((event) => event.start.day), [21]);
  });

  test('includes_occurrence_equal_to_until', () {
    final events = expandTimetable(
      [
        series(
          start: utc('20261014T090000Z'),
          end: utc('20261014T100000Z'),
          rule: 'FREQ=DAILY;UNTIL=20261016T090000Z',
        ),
      ],
      basicUtc('20261014T000000Z'),
      basicUtc('20261017T000000Z'),
    );

    expect(events.map((event) => event.start.day), [14, 15, 16]);
  });

  test('zoned_until_compares_occurrence_instants_in_event_timezone', () {
    final events = expandTimetable(
      [
        series(
          start: berlin('20261024T090000'),
          end: berlin('20261024T100000'),
          rule: 'FREQ=DAILY;UNTIL=20261025T080000Z',
        ),
      ],
      basicUtc('20261024T000000Z'),
      basicUtc('20261027T000000Z'),
    );

    expect(events.map((event) => event.start.day), [24, 25]);
    expect(events.map((event) => event.start.toUtc().hour), [7, 8]);
  });

  test('date_only_until_includes_its_final_calendar_day', () {
    final events = expandTimetable(
      [
        series(
          start: date('20261014'),
          end: date('20261015'),
          rule: 'FREQ=DAILY;UNTIL=20261016',
        ),
      ],
      DateTime.utc(2026, 10, 14),
      DateTime.utc(2026, 10, 18),
    );

    expect(events.map((event) => event.start.day), [14, 15, 16]);
  });

  test('floating_occurrence_uses_campus_day_window_near_midnight', () {
    final location = tz.getLocation('Europe/Berlin');
    final events = expandTimetable(
      [
        series(
          start: floating('20261015T003000'),
          end: floating('20261015T013000'),
        ),
      ],
      tz.TZDateTime(location, 2026, 10, 15),
      tz.TZDateTime(location, 2026, 10, 16),
    );

    expect(events, hasLength(1));
    expect(events.single.start.day, 15);
    expect(events.single.start.hour, 0);
  });

  test('floating_times_use_campus_timezone_independent_of_device_timezone', () {
    final events = expandTimetable(
      [
        series(
          start: floating('20261014T090000'),
          end: floating('20261014T100000'),
        ),
      ],
      basicUtc('20261014T000000Z'),
      basicUtc('20261015T000000Z'),
    );

    expect(events.single.start, isA<tz.TZDateTime>());
    expect(events.single.start.hour, 9);
    expect(events.single.start.timeZoneOffset, const Duration(hours: 2));
  });
}
