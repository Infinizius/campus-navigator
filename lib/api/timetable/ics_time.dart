import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'timetable_model.dart';

bool _timeZonesInitialized = false;

void initializeTimetableTimeZones() {
  if (_timeZonesInitialized) return;
  timezone_data.initializeTimeZones();
  _timeZonesInitialized = true;
}

IcsTemporal parseIcsTemporal(String raw, Map<String, String> parameters) {
  initializeTimetableTimeZones();
  final value = raw.trim();
  final valueType = parameters['VALUE']?.toUpperCase();
  final zoneId = parameters['TZID'];
  if (valueType != null && valueType != 'DATE' && valueType != 'DATE-TIME') {
    throw const FormatException('Unsupported calendar date type');
  }

  if (valueType == 'DATE' || RegExp(r'^\d{8}$').hasMatch(value)) {
    if (zoneId != null || !_validDate(value)) {
      throw const FormatException('Invalid all-day calendar date');
    }
    return IcsTemporal(value: value, kind: IcsTemporalKind.date);
  }

  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
      .firstMatch(value);
  if (match == null) throw const FormatException('Invalid calendar date-time');
  final parts = match
      .groups([1, 2, 3, 4, 5, 6])!
      .map((part) => int.parse(part!))
      .toList();
  if (!_validDate(value.substring(0, 8)) ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 60) {
    throw const FormatException('Invalid calendar date-time');
  }
  final isUtc = match.group(7) == 'Z';
  if (isUtc && zoneId != null) {
    throw const FormatException('UTC date-time cannot also specify TZID');
  }
  if (zoneId != null) {
    if (isUtc || !tz.timeZoneDatabase.locations.containsKey(zoneId)) {
      throw const FormatException('Unknown or invalid calendar timezone');
    }
    return IcsTemporal(
      value: value,
      kind: IcsTemporalKind.zoned,
      timeZoneId: zoneId,
    );
  }
  return IcsTemporal(
    value: value,
    kind: isUtc ? IcsTemporalKind.utc : IcsTemporalKind.floating,
  );
}

bool _validDate(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value)) return false;
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(4, 6));
  final day = int.parse(value.substring(6, 8));
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}
