import 'package:icalendar_parser/icalendar_parser.dart';
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

    // The bundled IANA database is authoritative. Accept embedded definitions
    // only when each observance's offset pair and local transition date agrees
    // with an actual IANA transition in the imported series' date span.
    final observances = component.children;
    if (observances.isEmpty) {
      throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
    }
    for (final observance in observances) {
      final localStart = _single(observance, 'DTSTART')?.value;
      final offsetFrom = _single(observance, 'TZOFFSETFROM')?.value;
      final offsetTo = _single(observance, 'TZOFFSETTO')?.value;
      if (localStart == null || offsetFrom == null || offsetTo == null) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
      final transitionLocal = _parseBasicDateTime(localStart);
      final candidate = tz.TZDateTime(
        tz.getLocation(id),
        transitionLocal.year,
        transitionLocal.month,
        transitionLocal.day,
        transitionLocal.hour,
        transitionLocal.minute,
        transitionLocal.second,
      );
      if (_formatOffset(candidate.timeZoneOffset) != offsetTo ||
          !_offsetTransitionExists(id, candidate, offsetFrom, offsetTo)) {
        throw const IcsImportException(IcsImportErrorCode.invalidTimezone);
      }
    }
  }
}

bool _offsetTransitionExists(
    String id, DateTime local, String from, String to) {
  final location = tz.getLocation(id);
  final before = tz.TZDateTime(location, local.year, local.month, local.day,
      local.hour, local.minute, local.second - 1);
  final after = tz.TZDateTime(location, local.year, local.month, local.day,
      local.hour, local.minute, local.second);
  return _formatOffset(before.timeZoneOffset) == from &&
      _formatOffset(after.timeZoneOffset) == to;
}

String _formatOffset(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final absolute = minutes.abs();
  return '$sign${(absolute ~/ 60).toString().padLeft(2, '0')}'
      '${(absolute % 60).toString().padLeft(2, '0')}';
}
