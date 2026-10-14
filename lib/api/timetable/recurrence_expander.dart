import 'package:teno_rrule/teno_rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'ics_parser.dart';
import 'ics_time.dart';
import 'timetable_model.dart';

const int maxOccurrencesPerSeries = 20000;

/// Expands a bounded display window. `begin` is inclusive and `end` exclusive.
List<TimetableOccurrence> expandTimetable(
  Iterable<TimetableSeries> series,
  DateTime begin,
  DateTime end,
) {
  if (!end.isAfter(begin)) return const [];
  initializeTimetableTimeZones();
  final result = <TimetableOccurrence>[];
  for (final item in series) {
    final candidates = _expandSeries(item, begin, end);
    if (candidates.length > maxOccurrencesPerSeries) {
      throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
    }
    result.addAll(candidates);
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(result);
}

List<TimetableOccurrence> _expandSeries(
  TimetableSeries series,
  DateTime begin,
  DateTime end,
) {
  final start = _toDateTime(series.start);
  final allDay = series.start.kind == IcsTemporalKind.date;
  final eventDuration = _durationOf(series, start);
  final overrideById = {
    for (final value in series.overrides)
      _temporalKey(value.recurrenceId): value,
  };
  final exclusions = series.exclusions.map(_temporalKey).toSet();

  List<DateTime> instances;
  if (series.recurrenceRule == null) {
    instances = [start];
  } else {
    final rule = _parseRule(series);
    final count = rule.count;
    final queryBegin = count == null
        ? _windowValue(begin, series.start).subtract(const Duration(seconds: 1))
        : start.subtract(const Duration(seconds: 1));
    final queryEnd =
        _windowValue(end, series.start).add(const Duration(seconds: 1));
    if (queryEnd.year > 2100) {
      throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
    }
    instances = rule.between(queryBegin, queryEnd);
    if (instances.length > maxOccurrencesPerSeries) {
      throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
    }
    // RFC recurrence sets always contain DTSTART, including when the supplied
    // rule's BY* parts do not select it. COUNT includes this first set member.
    if (!instances.any((instance) =>
        _temporalKey(_fromDateTime(instance, series.start)) ==
        _temporalKey(series.start))) {
      instances.add(start);
    }
    instances.sort((a, b) => a.compareTo(b));
    if (count != null && instances.length > count) {
      instances = instances.take(count).toList();
    }
    final until = _untilFromRule(series.recurrenceRule!);
    if (until != null) {
      instances =
          instances.where((instance) => !instance.isAfter(until)).toList();
    }
  }

  final byId = <String, TimetableOccurrence>{};
  for (final rawInstance in instances) {
    final instance = _preserveWallTime(rawInstance, series.start);
    final recurrenceId = _fromDateTime(instance, series.start);
    final key = _temporalKey(recurrenceId);
    final override = overrideById[key];
    if (exclusions.contains(key) && override == null) continue;
    if (override?.cancelled == true) continue;

    final occurrenceStart =
        override?.start == null ? instance : _toDateTime(override!.start!);
    final occurrenceEnd = override?.end != null
        ? _toDateTime(override!.end!)
        : override?.duration != null
            ? occurrenceStart.add(override!.duration!)
            : _addDuration(occurrenceStart, eventDuration, allDay);
    final effective = TimetableOccurrence(
      uid: series.uid,
      recurrenceId: key,
      title: override?.summary ?? series.summary,
      description: override?.description ?? series.description,
      location: override?.location ?? series.location,
      start: occurrenceStart,
      end: occurrenceEnd,
      allDay: allDay,
      timeZoneId: override?.start?.timeZoneId ?? series.start.timeZoneId,
    );
    if (_inWindow(effective.start, begin, end, allDay)) {
      byId[key] = effective;
    }
  }

  // A detached instance may have moved into this window from a recurrence slot
  // outside it, so include all moved overrides independently of the base query.
  for (final override in series.overrides) {
    if (override.cancelled || override.start == null) continue;
    final key = _temporalKey(override.recurrenceId);
    if (byId.containsKey(key)) continue;
    final movedStart = _toDateTime(override.start!);
    if (!_inWindow(movedStart, begin, end, allDay)) continue;
    final movedEnd = override.end == null
        ? _addDuration(movedStart, override.duration ?? eventDuration, allDay)
        : _toDateTime(override.end!);
    byId[key] = TimetableOccurrence(
      uid: series.uid,
      recurrenceId: key,
      title: override.summary ?? series.summary,
      description: override.description ?? series.description,
      location: override.location ?? series.location,
      start: movedStart,
      end: movedEnd,
      allDay: allDay,
      timeZoneId: override.start!.timeZoneId ?? series.start.timeZoneId,
    );
  }
  return byId.values.toList();
}

RecurrenceRule _parseRule(TimetableSeries series) {
  final start = series.start;
  // The 0.0.8 engine advances zoned instances by elapsed duration. Generate
  // local calendar dates, then restore the event's wall clock in its IANA zone.
  final startLine =
      'DTSTART:${_toExtended(start.value)}${start.kind == IcsTemporalKind.utc ? 'Z' : ''}';
  final ruleValue = series.recurrenceRule!
      .replaceAll(RegExp(r';?UNTIL=\d{8}T\d{6}Z?', caseSensitive: false), '');
  // teno_rrule 0.0.8 parses EXDATE into a set and compares by day, so EXDATEs
  // are intentionally applied by this adapter using exact recurrence IDs.
  final rule = RecurrenceRule.from('$startLine\nRRULE:$ruleValue');
  if (rule == null) {
    throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
  }
  return rule.copyWith(excludedDates: const {});
}

DateTime? _untilFromRule(String rule) {
  final match = RegExp(r'(?:^|;)UNTIL=(\d{8}T\d{6}Z?)', caseSensitive: false)
      .firstMatch(rule);
  if (match == null) return null;
  final raw = match[1]!;
  return _toDateTime(IcsTemporal(
    value: raw,
    kind: raw.endsWith('Z') ? IcsTemporalKind.utc : IcsTemporalKind.floating,
  ));
}

Duration _durationOf(TimetableSeries series, DateTime start) {
  if (series.duration != null) return series.duration!;
  final end = series.end;
  if (end == null) return Duration.zero;
  if (series.start.kind == IcsTemporalKind.date) {
    final startDate = _dateOnly(series.start.value);
    final endDate = _dateOnly(end.value);
    return Duration(days: endDate.difference(startDate).inDays);
  }
  return _toDateTime(end).difference(start);
}

DateTime _addDuration(DateTime start, Duration duration, bool allDay) {
  if (!allDay) return start.add(duration);
  return DateTime.utc(start.year, start.month, start.day + duration.inDays);
}

bool _inWindow(DateTime value, DateTime begin, DateTime end, bool allDay) {
  if (!allDay) return !value.isBefore(begin) && value.isBefore(end);
  final dateValue = DateTime.utc(value.year, value.month, value.day);
  final dateBegin = DateTime.utc(begin.year, begin.month, begin.day);
  final dateEnd = DateTime.utc(end.year, end.month, end.day);
  return !dateValue.isBefore(dateBegin) && dateValue.isBefore(dateEnd);
}

DateTime _windowValue(DateTime value, IcsTemporal basis) {
  if (basis.kind == IcsTemporalKind.date) {
    return DateTime.utc(value.year, value.month, value.day);
  }
  if (basis.kind == IcsTemporalKind.zoned) {
    return tz.TZDateTime.from(value.toUtc(), tz.getLocation(basis.timeZoneId!));
  }
  if (basis.kind == IcsTemporalKind.floating) return value.toLocal();
  return value.toUtc();
}

DateTime _toDateTime(IcsTemporal temporal) {
  final value = temporal.value;
  if (temporal.kind == IcsTemporalKind.date) return _dateOnly(value);
  final parts = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$')
      .firstMatch(value);
  if (parts == null) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  final values = [for (var i = 1; i <= 6; i++) int.parse(parts[i]!)];
  if (temporal.kind == IcsTemporalKind.zoned) {
    return tz.TZDateTime(
      tz.getLocation(temporal.timeZoneId!),
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
  }
  if (temporal.kind == IcsTemporalKind.utc) {
    return DateTime.utc(
        values[0], values[1], values[2], values[3], values[4], values[5]);
  }
  return DateTime(
      values[0], values[1], values[2], values[3], values[4], values[5]);
}

DateTime _preserveWallTime(DateTime occurrence, IcsTemporal basis) {
  if (basis.kind == IcsTemporalKind.zoned) {
    final start = _toDateTime(basis);
    return tz.TZDateTime(
      tz.getLocation(basis.timeZoneId!),
      occurrence.year,
      occurrence.month,
      occurrence.day,
      start.hour,
      start.minute,
      start.second,
    );
  }
  if (basis.kind == IcsTemporalKind.floating) {
    final start = _toDateTime(basis);
    return DateTime(
      occurrence.year,
      occurrence.month,
      occurrence.day,
      start.hour,
      start.minute,
      start.second,
    );
  }
  return occurrence;
}

DateTime _dateOnly(String value) => DateTime.utc(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
    );

IcsTemporal _fromDateTime(DateTime value, IcsTemporal basis) {
  final date = basis.kind == IcsTemporalKind.date;
  final formatted = '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';
  if (date) {
    return IcsTemporal(value: formatted, kind: IcsTemporalKind.date);
  }
  final time = 'T${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';
  return IcsTemporal(
    value: '$formatted$time${basis.kind == IcsTemporalKind.utc ? 'Z' : ''}',
    kind: basis.kind,
    timeZoneId: basis.timeZoneId,
  );
}

String _temporalKey(IcsTemporal temporal) =>
    '${temporal.kind.name}:${temporal.timeZoneId ?? ''}:${temporal.value}';

String _toExtended(String value) {
  final compact = value.replaceFirst(RegExp(r'Z$'), '');
  if (compact.length == 8) {
    return '${compact.substring(0, 4)}-${compact.substring(4, 6)}-${compact.substring(6, 8)}';
  }
  return '${compact.substring(0, 4)}-${compact.substring(4, 6)}-${compact.substring(6, 8)}'
      'T${compact.substring(9, 11)}:${compact.substring(11, 13)}:${compact.substring(13, 15)}';
}
