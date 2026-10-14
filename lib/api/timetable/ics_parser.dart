import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:teno_rrule/teno_rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'ics_time.dart';
import 'timetable_model.dart';

enum IcsImportErrorCode {
  invalidCalendar,
  noEvents,
  incompleteEvent,
  duplicateUid,
  unsupportedFeature,
  invalidDate,
  unknownTimezone,
  invalidTimezone,
}

class IcsImportException implements Exception {
  final IcsImportErrorCode code;

  const IcsImportException(this.code);

  @override
  String toString() => 'IcsImportException(${code.name})';
}

class _Property {
  final String name;
  final Map<String, String> parameters;
  final String value;

  const _Property(this.name, this.parameters, this.value);
}

class _Component {
  final String name;
  final List<_Property> properties = [];
  final List<_Component> children = [];

  _Component(this.name);
}

/// Strictly validates an ICS document before converting supported VEVENT data.
ParsedTimetable parseIcsCalendar(String input) {
  try {
    if (input.isEmpty || input.length > 5 * 1024 * 1024) {
      throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
    }
    initializeTimetableTimeZones();
    final lines = _unfold(input);
    final root = _parseComponents(lines);
    if (root.name != 'VCALENDAR') {
      throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
    }

    // Use icalendar_parser for its supported property model. The adapter below
    // retains parameters and components the package currently omits.
    ICalendar.fromLines(List<String>.of(lines));

    final events = root.children.where((child) => child.name == 'VEVENT');
    if (events.isEmpty) {
      throw const IcsImportException(IcsImportErrorCode.noEvents);
    }
    final masters = <String, TimetableSeries>{};
    final overrides = <String, List<TimetableOverride>>{};
    final masterUids = <String>{};

    for (final component in events) {
      final uid = _single(component, 'UID')?.value.trim();
      final startProperty = _single(component, 'DTSTART');
      if (uid == null || uid.isEmpty || startProperty == null) {
        throw const IcsImportException(IcsImportErrorCode.incompleteEvent);
      }
      final start =
          parseIcsTemporal(startProperty.value, startProperty.parameters);
      final endProperty = _single(component, 'DTEND');
      final durationProperty = _single(component, 'DURATION');
      if (endProperty != null && durationProperty != null) {
        throw const IcsImportException(IcsImportErrorCode.invalidDate);
      }
      final end = endProperty == null
          ? null
          : parseIcsTemporal(endProperty.value, endProperty.parameters);
      final duration = durationProperty == null
          ? null
          : _parseDuration(durationProperty.value);
      final recurrenceId = _single(component, 'RECURRENCE-ID');
      final cancelled =
          _single(component, 'STATUS')?.value.toUpperCase() == 'CANCELLED';
      if (recurrenceId == null && end == null && duration == null ||
          recurrenceId != null &&
              !cancelled &&
              end == null &&
              duration == null) {
        throw const IcsImportException(IcsImportErrorCode.incompleteEvent);
      }
      _validateRange(start, end, duration);

      final summary = _decodeText(_single(component, 'SUMMARY')?.value ?? '');
      if (summary.trim().isEmpty) {
        throw const IcsImportException(IcsImportErrorCode.incompleteEvent);
      }
      final rawDescription = _single(component, 'DESCRIPTION')?.value;
      final rawLocation = _single(component, 'LOCATION')?.value;
      final description =
          rawDescription == null ? null : _decodeText(rawDescription);
      final location = rawLocation == null ? null : _decodeText(rawLocation);

      if (recurrenceId != null) {
        final range = recurrenceId.parameters['RANGE']?.toUpperCase();
        if (range != null && range != 'THISANDFUTURE') {
          throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
        }
        if (range != null) {
          throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
        }
        final id =
            parseIcsTemporal(recurrenceId.value, recurrenceId.parameters);
        overrides.putIfAbsent(uid, () => []).add(TimetableOverride(
              recurrenceId: id,
              cancelled: cancelled,
              summary: summary.isEmpty ? null : summary,
              description: description,
              location: location,
              start: start,
              end: end,
              duration: duration,
            ));
        continue;
      }

      if (!masterUids.add(uid)) {
        throw const IcsImportException(IcsImportErrorCode.duplicateUid);
      }
      final rules = _all(component, 'RRULE');
      if (rules.length > 1 || _all(component, 'RDATE').isNotEmpty) {
        throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
      }
      if (rules.isNotEmpty) _validateRRule(start, rules.single.value);
      final exclusions = <IcsTemporal>[];
      for (final property in _all(component, 'EXDATE')) {
        for (final date in property.value.split(',')) {
          if (date.isEmpty) {
            throw const IcsImportException(IcsImportErrorCode.invalidDate);
          }
          exclusions.add(parseIcsTemporal(date, property.parameters));
        }
      }
      masters[uid] = TimetableSeries(
        uid: uid,
        summary: summary,
        description: description,
        location: location,
        start: start,
        end: end,
        duration: duration,
        recurrenceRule: rules.singleOrNull?.value,
        exclusions: List.unmodifiable(exclusions),
      );
    }

    for (final entry in overrides.entries) {
      final master = masters[entry.key];
      if (master == null) {
        throw const IcsImportException(IcsImportErrorCode.incompleteEvent);
      }
      masters[entry.key] = TimetableSeries(
        uid: master.uid,
        summary: master.summary,
        description: master.description,
        location: master.location,
        start: master.start,
        end: master.end,
        duration: master.duration,
        recurrenceRule: master.recurrenceRule,
        exclusions: master.exclusions,
        overrides: List.unmodifiable(entry.value),
      );
    }
    if (masters.isEmpty) {
      throw const IcsImportException(IcsImportErrorCode.noEvents);
    }
    _validateTimeZones(root, masters.values);
    return ParsedTimetable(series: List.unmodifiable(masters.values));
  } on IcsImportException {
    rethrow;
  } on FormatException {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  } catch (_) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
}

List<String> _unfold(String input) {
  if (input.contains('\r') && RegExp(r'\r(?!\n)').hasMatch(input)) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  final physical = input.replaceAll('\r\n', '\n').split('\n');
  if (physical.last.isEmpty) physical.removeLast();
  final result = <String>[];
  for (final line in physical) {
    if (line.startsWith(' ') || line.startsWith('\t')) {
      if (result.isEmpty) {
        throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
      }
      result[result.length - 1] += line.substring(1);
    } else if (line.isEmpty) {
      continue;
    } else {
      result.add(line);
    }
  }
  return result;
}

_Component _parseComponents(List<String> lines) {
  if (lines.isEmpty) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  final stack = <_Component>[];
  _Component? root;
  for (final line in lines) {
    final property = _parseProperty(line);
    if (property.name == 'BEGIN') {
      final name = property.value.toUpperCase();
      if (!{'VCALENDAR', 'VEVENT', 'VTIMEZONE', 'STANDARD', 'DAYLIGHT'}
          .contains(name)) {
        throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
      }
      final component = _Component(name);
      if (stack.isEmpty) {
        if (root != null || name != 'VCALENDAR') {
          throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
        }
        root = component;
      } else {
        stack.last.children.add(component);
      }
      stack.add(component);
      continue;
    }
    if (property.name == 'END') {
      if (stack.isEmpty || stack.last.name != property.value.toUpperCase()) {
        throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
      }
      stack.removeLast();
      continue;
    }
    if (stack.isEmpty) {
      throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
    }
    stack.last.properties.add(property);
  }
  if (stack.isNotEmpty ||
      root == null ||
      root.children.any((c) => c.name == 'VEVENT') &&
          root.properties
              .every((p) => p.name != 'VERSION' || p.value != '2.0')) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  return root;
}

_Property _parseProperty(String line) {
  var quoted = false;
  var escaped = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (escaped) {
      escaped = false;
    } else if (c == r'\') {
      escaped = true;
    } else if (c == '"') {
      quoted = !quoted;
    } else if (c == ':' && !quoted) {
      colon = i;
      break;
    }
  }
  if (colon <= 0 || quoted) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  final head = line.substring(0, colon).split(';');
  final name = head.first.toUpperCase();
  if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(name)) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  final params = <String, String>{};
  for (final item in head.skip(1)) {
    final equals = item.indexOf('=');
    if (equals <= 0) {
      throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
    }
    final key = item.substring(0, equals).toUpperCase();
    var value = item.substring(equals + 1);
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    if (params.containsKey(key)) {
      throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
    }
    params[key] = value;
  }
  return _Property(name, params, line.substring(colon + 1));
}

_Property? _single(_Component component, String name) {
  final values = _all(component, name);
  if (values.length > 1) {
    throw const IcsImportException(IcsImportErrorCode.invalidCalendar);
  }
  return values.singleOrNull;
}

List<_Property> _all(_Component component, String name) =>
    component.properties.where((property) => property.name == name).toList();

String _decodeText(String value) => value
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');

void _validateRRule(IcsTemporal start, String value) {
  try {
    final dateTime = start.value.replaceFirst(RegExp(r'Z$'), '');
    final extended = dateTime.length == 8
        ? '${dateTime.substring(0, 4)}-${dateTime.substring(4, 6)}-${dateTime.substring(6, 8)}'
        : '${dateTime.substring(0, 4)}-${dateTime.substring(4, 6)}-${dateTime.substring(6, 8)}'
            'T${dateTime.substring(9, 11)}:${dateTime.substring(11, 13)}:${dateTime.substring(13, 15)}';
    final startLine =
        'DTSTART:$extended${start.kind == IcsTemporalKind.utc ? 'Z' : ''}';
    final normalizedRule = value.replaceAllMapped(
      RegExp(r'UNTIL=(\d{8}T\d{6}Z?)', caseSensitive: false),
      (match) {
        final raw = match[1]!;
        final compact = raw.replaceFirst(RegExp(r'Z$'), '');
        final formatted =
            '${compact.substring(0, 4)}-${compact.substring(4, 6)}-${compact.substring(6, 8)}'
            'T${compact.substring(9, 11)}:${compact.substring(11, 13)}:${compact.substring(13, 15)}';
        return 'UNTIL=$formatted${raw.endsWith('Z') ? 'Z' : ''}';
      },
    );
    final parsed = RecurrenceRule.from('$startLine\nRRULE:$normalizedRule');
    if (parsed == null || parsed.count == 0 || parsed.interval <= 0) {
      throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
    }
  } on IcsImportException {
    rethrow;
  } catch (_) {
    throw const IcsImportException(IcsImportErrorCode.unsupportedFeature);
  }
}

Duration _parseDuration(String raw) {
  final match = RegExp(
    r'^([+-])?P(?:(\d+)W|(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$',
  ).firstMatch(raw);
  if (match == null || !raw.contains(RegExp(r'\d'))) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  final sign = match.group(1) == '-' ? -1 : 1;
  final weeks = int.tryParse(match.group(2) ?? '0') ?? 0;
  final days = int.tryParse(match.group(3) ?? '0') ?? 0;
  final hours = int.tryParse(match.group(4) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(5) ?? '0') ?? 0;
  final seconds = int.tryParse(match.group(6) ?? '0') ?? 0;
  if (raw.startsWith('-') ||
      (weeks == 0 && days == 0 && hours == 0 && minutes == 0 && seconds == 0)) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  return Duration(
    seconds: sign *
        (weeks * Duration.secondsPerDay * 7 +
            days * Duration.secondsPerDay +
            hours * Duration.secondsPerHour +
            minutes * Duration.secondsPerMinute +
            seconds),
  );
}

void _validateRange(IcsTemporal start, IcsTemporal? end, Duration? duration) {
  if (duration != null && duration.inMicroseconds <= 0) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  if (end == null) return;
  if (start.kind != end.kind || start.timeZoneId != end.timeZoneId) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  if (start.kind == IcsTemporalKind.date) {
    if (end.value.compareTo(start.value) <= 0) {
      throw const IcsImportException(IcsImportErrorCode.invalidDate);
    }
  } else {
    final startValue = _parseBasicDateTime(start.value);
    final endValue = _parseBasicDateTime(end.value);
    if (!endValue.isAfter(startValue)) {
      throw const IcsImportException(IcsImportErrorCode.invalidDate);
    }
  }
}

DateTime _parseBasicDateTime(String value) {
  final parts = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$')
      .firstMatch(value);
  if (parts == null) {
    throw const IcsImportException(IcsImportErrorCode.invalidDate);
  }
  return DateTime.utc(
    int.parse(parts[1]!),
    int.parse(parts[2]!),
    int.parse(parts[3]!),
    int.parse(parts[4]!),
    int.parse(parts[5]!),
    int.parse(parts[6]!),
  );
}

void _validateTimeZones(_Component root, Iterable<TimetableSeries> series) {
  final embedded = root.children.where((child) => child.name == 'VTIMEZONE');
  final seen = <String>{};
  final importedSeries = series.toList(growable: false);
  for (final component in embedded) {
    final id = _single(component, 'TZID')?.value;
    if (id == null || !seen.add(id)) {
      throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
    }
    final expected = series.any((event) =>
        event.start.timeZoneId == id ||
        event.exclusions.any((value) => value.timeZoneId == id) ||
        event.overrides.any((value) => value.start?.timeZoneId == id));
    if (!expected) continue;

    final observances = component.children;
    if (observances.isEmpty ||
        observances.any(
            (value) => value.name != 'STANDARD' && value.name != 'DAYLIGHT')) {
      throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
    }
    final relevant = importedSeries.where((event) =>
        event.start.timeZoneId == id ||
        event.exclusions.any((value) => value.timeZoneId == id) ||
        event.overrides.any((value) => value.start?.timeZoneId == id));
    final years = relevant.expand(_yearsForSeries).toList();
    if (years.isEmpty) continue;
    final firstYear = years.reduce((a, b) => a < b ? a : b);
    // Validate the IANA rule beyond DTSTART so recurring calendars cannot
    // carry a stale or incomplete one-off VTIMEZONE transition table.
    final lastYear = (years.reduce((a, b) => a > b ? a : b) + 10).clamp(
      firstYear,
      2100,
    );
    final firstInstant = DateTime.utc(firstYear, 1).millisecondsSinceEpoch;
    final endInstant = DateTime.utc(lastYear + 1, 1).millisecondsSinceEpoch;
    final location = tz.getLocation(id);
    final parsedObservances = <_TimezoneObservance>[];
    for (final observance in observances) {
      final localStart = _single(observance, 'DTSTART')?.value;
      final offsetFrom = _single(observance, 'TZOFFSETFROM')?.value;
      final offsetTo = _single(observance, 'TZOFFSETTO')?.value;
      if (localStart == null || offsetFrom == null || offsetTo == null) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
      final fromSeconds = _parseUtcOffset(offsetFrom);
      final toSeconds = _parseUtcOffset(offsetTo);
      final local = _parseBasicDateTime(localStart);
      final ruleProperties = _all(observance, 'RRULE');
      final rdateProperties = _all(observance, 'RDATE');
      if (ruleProperties.length > 1 || rdateProperties.length > 1) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
      final rdates = <DateTime>[];
      for (final property in rdateProperties) {
        for (final value in property.value.split(',')) {
          rdates.add(_parseBasicDateTime(value));
        }
      }
      parsedObservances.add(_TimezoneObservance(
        start: local,
        offsetFrom: fromSeconds,
        offsetTo: toSeconds,
        rule: ruleProperties.isEmpty
            ? null
            : _parseTimezoneRule(ruleProperties.single.value),
        rdates: rdates,
      ));
    }

    final matchedObservances = <int>{};
    var actualTransitions = 0;
    for (var i = 0; i < location.transitionAt.length; i++) {
      final instant = location.transitionAt[i];
      if (instant < firstInstant || instant >= endInstant) continue;
      final before = location.timeZone(instant - 1000).offset ~/ 1000;
      final after = location.timeZone(instant).offset ~/ 1000;
      if (before == after) continue;
      actualTransitions++;
      final transitionUtc =
          DateTime.fromMillisecondsSinceEpoch(instant, isUtc: true);
      var matched = false;
      for (var index = 0; index < parsedObservances.length; index++) {
        final observance = parsedObservances[index];
        if (observance.offsetFrom != before || observance.offsetTo != after) {
          continue;
        }
        if (_matchesTimezoneObservance(
          observance,
          transitionUtc.add(Duration(seconds: observance.offsetFrom)),
        )) {
          matched = true;
          matchedObservances.add(index);
        }
      }
      if (!matched) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
    }
    if (actualTransitions == 0) {
      final eventStart = relevant.first.start;
      final localEvent = _parseBasicDateTime(eventStart.value);
      final zoneOffset = tz.TZDateTime(
        location,
        localEvent.year,
        localEvent.month,
        localEvent.day,
        localEvent.hour,
        localEvent.minute,
        localEvent.second,
      ).timeZoneOffset.inSeconds;
      if (!parsedObservances.any((value) => value.offsetTo == zoneOffset)) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
    } else if (matchedObservances.length != parsedObservances.length) {
      throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
    }
  }
}

class _TimezoneObservance {
  final DateTime start;
  final int offsetFrom;
  final int offsetTo;
  final Map<String, List<String>>? rule;
  final List<DateTime> rdates;

  const _TimezoneObservance({
    required this.start,
    required this.offsetFrom,
    required this.offsetTo,
    required this.rule,
    required this.rdates,
  });
}

Map<String, List<String>> _parseTimezoneRule(String value) {
  try {
    _validateRRule(
      const IcsTemporal(
          value: '20000101T000000', kind: IcsTemporalKind.floating),
      value,
    );
    final parts = <String, List<String>>{};
    const supported = {
      'FREQ',
      'INTERVAL',
      'BYMONTH',
      'BYMONTHDAY',
      'BYDAY',
      'WKST',
      'UNTIL',
      'COUNT',
    };
    for (final part in value.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0 || separator == part.length - 1) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
      final key = part.substring(0, separator).toUpperCase();
      if (!supported.contains(key) || parts.containsKey(key)) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
      parts[key] = part.substring(separator + 1).toUpperCase().split(',');
    }
    if (parts['FREQ']?.single != 'YEARLY' || parts.containsKey('COUNT')) {
      throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
    }
    return parts;
  } on IcsImportException {
    rethrow;
  } catch (_) {
    throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
  }
}

bool _matchesTimezoneObservance(
  _TimezoneObservance observance,
  DateTime wallTime,
) {
  if (wallTime.hour != observance.start.hour ||
      wallTime.minute != observance.start.minute ||
      wallTime.second != observance.start.second) {
    return false;
  }
  if (wallTime.year == observance.start.year &&
      wallTime.month == observance.start.month &&
      wallTime.day == observance.start.day) {
    return true;
  }
  if (observance.rdates.any((value) =>
      value.year == wallTime.year &&
      value.month == wallTime.month &&
      value.day == wallTime.day &&
      value.hour == wallTime.hour &&
      value.minute == wallTime.minute &&
      value.second == wallTime.second)) {
    return true;
  }
  final rule = observance.rule;
  if (rule == null || wallTime.year < observance.start.year) return false;
  final interval = int.tryParse(rule['INTERVAL']?.single ?? '1') ?? 0;
  if (interval < 1 || (wallTime.year - observance.start.year) % interval != 0) {
    return false;
  }
  final until = rule['UNTIL']?.single;
  if (until != null && wallTime.isAfter(_parseBasicDateTime(until))) {
    return false;
  }
  final months = rule['BYMONTH']?.map(int.tryParse).toList();
  if (months != null &&
      (months.any((value) => value == null || value < 1 || value > 12) ||
          !months.contains(wallTime.month))) {
    return false;
  }
  final monthDays = rule['BYMONTHDAY']?.map(int.tryParse).toList();
  if (monthDays != null) {
    final lastDay = DateTime.utc(wallTime.year, wallTime.month + 1, 0).day;
    final selectedDays = monthDays.map((value) => value == null
        ? 0
        : value < 0
            ? lastDay + value + 1
            : value);
    if (monthDays.any((value) => value == null || value == 0) ||
        !selectedDays.contains(wallTime.day)) {
      return false;
    }
  }
  final weekdays = rule['BYDAY'];
  if (weekdays != null &&
      !weekdays
          .any((value) => _matchesByDay(wallTime, value, months != null))) {
    return false;
  }
  if (months == null && monthDays == null && weekdays == null) {
    return wallTime.month == observance.start.month &&
        wallTime.day == observance.start.day;
  }
  return true;
}

bool _matchesByDay(DateTime date, String value, bool monthScoped) {
  final match =
      RegExp(r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(value);
  if (match == null) return false;
  const weekdayNumbers = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };
  if (date.weekday != weekdayNumbers[match[2]]) return false;
  final ordinal = int.tryParse(match[1] ?? '');
  if (ordinal == null) return true;
  if (ordinal == 0) return false;
  final firstDay = monthScoped
      ? DateTime.utc(date.year, date.month, 1)
      : DateTime.utc(date.year, 1, 1);
  final lastDay = monthScoped
      ? DateTime.utc(date.year, date.month + 1, 0)
      : DateTime.utc(date.year + 1, 1, 0);
  final dateOnly = DateTime.utc(date.year, date.month, date.day);
  var occurrence = 0;
  var reverseOccurrence = 0;
  for (var day = firstDay;
      !day.isAfter(dateOnly);
      day = day.add(const Duration(days: 1))) {
    if (day.weekday == date.weekday) occurrence++;
  }
  for (var day = lastDay;
      !day.isBefore(dateOnly);
      day = day.subtract(const Duration(days: 1))) {
    if (day.weekday == date.weekday) reverseOccurrence++;
  }
  return ordinal > 0 ? occurrence == ordinal : reverseOccurrence == -ordinal;
}

Iterable<int> _yearsForSeries(TimetableSeries event) sync* {
  for (final temporal in <IcsTemporal>[
    event.start,
    ...event.exclusions,
    ...event.overrides.map((value) => value.start).whereType<IcsTemporal>(),
  ]) {
    if (temporal.kind == IcsTemporalKind.zoned &&
        temporal.timeZoneId == event.start.timeZoneId) {
      yield int.parse(temporal.value.substring(0, 4));
    }
  }
}

int _parseUtcOffset(String value) {
  final match = RegExp(r'^([+-])(\d{2})(\d{2})(\d{2})?$').firstMatch(value);
  if (match == null) {
    throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
  }
  final hours = int.parse(match[2]!);
  final minutes = int.parse(match[3]!);
  final seconds = int.parse(match[4] ?? '0');
  if (minutes > 59 ||
      seconds > 59 ||
      hours > 24 ||
      (hours == 24 && (minutes != 0 || seconds != 0))) {
    throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
  }
  final total = hours * 3600 + minutes * 60 + seconds;
  return match[1] == '-' ? -total : total;
}
