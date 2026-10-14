enum IcsTemporalKind { date, floating, utc, zoned }

/// The original calendar representation of a date/time, kept losslessly.
class IcsTemporal {
  final String value;
  final IcsTemporalKind kind;
  final String? timeZoneId;

  const IcsTemporal({
    required this.value,
    required this.kind,
    this.timeZoneId,
  });

  Map<String, Object?> toJson() => {
        'value': value,
        'kind': kind.name,
        if (timeZoneId != null) 'timeZoneId': timeZoneId,
      };

  factory IcsTemporal.fromJson(Map<String, Object?> json) => IcsTemporal(
        value: json['value'] as String,
        kind: IcsTemporalKind.values.byName(json['kind'] as String),
        timeZoneId: json['timeZoneId'] as String?,
      );
}

class TimetableOverride {
  final IcsTemporal recurrenceId;
  final bool cancelled;
  final String? summary;
  final String? description;
  final String? location;
  final IcsTemporal? start;
  final IcsTemporal? end;
  final Duration? duration;

  const TimetableOverride({
    required this.recurrenceId,
    required this.cancelled,
    this.summary,
    this.description,
    this.location,
    this.start,
    this.end,
    this.duration,
  });

  Map<String, Object?> toJson() => {
        'recurrenceId': recurrenceId.toJson(),
        'cancelled': cancelled,
        if (summary != null) 'summary': summary,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (start != null) 'start': start!.toJson(),
        if (end != null) 'end': end!.toJson(),
        if (duration != null) 'durationSeconds': duration!.inSeconds,
      };
}

class TimetableSeries {
  final String uid;
  final String summary;
  final String? description;
  final String? location;
  final IcsTemporal start;
  final IcsTemporal? end;
  final Duration? duration;
  final String? recurrenceRule;
  final List<IcsTemporal> exclusions;
  final List<TimetableOverride> overrides;

  const TimetableSeries({
    required this.uid,
    required this.summary,
    this.description,
    this.location,
    required this.start,
    this.end,
    this.duration,
    this.recurrenceRule,
    this.exclusions = const [],
    this.overrides = const [],
  });

  Map<String, Object?> toJson() => {
        'uid': uid,
        'summary': summary,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        'start': start.toJson(),
        if (end != null) 'end': end!.toJson(),
        if (duration != null) 'durationSeconds': duration!.inSeconds,
        if (recurrenceRule != null) 'recurrenceRule': recurrenceRule,
        'exclusions': exclusions.map((value) => value.toJson()).toList(),
        'overrides': overrides.map((value) => value.toJson()).toList(),
      };
}

class ParsedTimetable {
  final List<TimetableSeries> series;

  const ParsedTimetable({required this.series});
}
