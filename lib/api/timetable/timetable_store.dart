import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../saved_places.dart';
import '../storage.dart';
import 'room_resolver.dart';
import 'timetable_model.dart';

enum TimetableImportMode { update, replace }

class TimetableRoomMapping {
  final String uid;
  final String normalizedLocation;
  final SavedPlace room;

  const TimetableRoomMapping({
    required this.uid,
    required this.normalizedLocation,
    required this.room,
  });

  String get key => '$uid\u0000$normalizedLocation';

  Map<String, Object?> toJson() => {
        'uid': uid,
        'normalizedLocation': normalizedLocation,
        'room': room.toJson(),
      };

  factory TimetableRoomMapping.fromJson(Map<String, Object?> json) =>
      TimetableRoomMapping(
        uid: json['uid'] as String,
        normalizedLocation: json['normalizedLocation'] as String,
        room:
            SavedPlace.fromJson(Map<String, dynamic>.from(json['room'] as Map)),
      );
}

/// Persists the active timetable as a single versioned secure-storage snapshot.
class TimetableStore extends ChangeNotifier {
  static const storageKey = 'Timetable.v1';

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  List<TimetableSeries> _events = [];
  List<TimetableRoomMapping> _mappings = [];
  Future<bool>? _loading;
  Future<void> _writes = Future<void>.value();
  int _pendingWrites = 0;
  bool _disposed = false;

  bool ready = false;
  bool loadFailed = false;
  bool lastOperationFailed = false;

  TimetableStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  })  : _read = read ?? (() => Storage.Shared.storage.read(key: storageKey)),
        _write = write ??
            ((value) =>
                Storage.Shared.storage.write(key: storageKey, value: value));

  List<TimetableSeries> get events => List.unmodifiable(_events);
  List<TimetableRoomMapping> get mappings => List.unmodifiable(_mappings);
  bool get loading => _loading != null;
  bool get saving => _pendingWrites > 0;

  Future<bool> load() {
    if (_loading != null) return _loading!;
    _loading = Future<bool>.microtask(() async {
      try {
        final raw = await _read();
        if (raw == null) {
          _events = [];
          _mappings = [];
        } else {
          final decoded = jsonDecode(raw);
          if (decoded is! Map ||
              decoded['version'] != 1 ||
              decoded['events'] is! List ||
              decoded['mappings'] is! List) {
            throw const FormatException('Unsupported timetable document');
          }
          final events = (decoded['events'] as List)
              .map((value) => TimetableSeries.fromJson(
                  Map<String, Object?>.from(value as Map)))
              .toList(growable: false);
          final byUid = <String, TimetableSeries>{};
          for (final event in events) {
            if (event.uid.trim().isEmpty ||
                event.summary.trim().isEmpty ||
                byUid.containsKey(event.uid)) {
              throw const FormatException('Invalid timetable series');
            }
            byUid[event.uid] = event;
          }
          final mappings = (decoded['mappings'] as List)
              .map((value) => TimetableRoomMapping.fromJson(
                  Map<String, Object?>.from(value as Map)))
              .toList(growable: false);
          final byKey = <String, TimetableRoomMapping>{};
          for (final mapping in mappings) {
            final event = byUid[mapping.uid];
            if (event == null ||
                mapping.room.kind != PlaceKind.room ||
                mapping.normalizedLocation !=
                    normalizeRoomLocation(event.location ?? '') ||
                byKey.containsKey(mapping.key)) {
              throw const FormatException('Invalid timetable room mapping');
            }
            byKey[mapping.key] = mapping;
          }
          _events = List.unmodifiable(byUid.values);
          _mappings = List.unmodifiable(byKey.values);
        }
        ready = true;
        loadFailed = false;
        lastOperationFailed = false;
        return true;
      } catch (_) {
        // Never replace a corrupt/unreadable document with an empty schedule.
        ready = false;
        loadFailed = true;
        lastOperationFailed = true;
        return false;
      } finally {
        _loading = null;
        _notify();
      }
    });
    _notify();
    return _loading!;
  }

  TimetableSeries? eventFor(String uid) {
    for (final event in _events) {
      if (event.uid == uid) return event;
    }
    return null;
  }

  TimetableRoomMapping? mappingFor(String uid, String location) {
    final normalized = normalizeRoomLocation(location);
    for (final mapping in _mappings) {
      if (mapping.uid == uid && mapping.normalizedLocation == normalized) {
        return mapping;
      }
    }
    return null;
  }

  SavedPlace? roomFor(String uid, String location) =>
      mappingFor(uid, location)?.room;

  Future<bool> importCalendar(
    ParsedTimetable calendar,
    TimetableImportMode mode,
  ) async {
    if (!ready && !await load()) return false;
    if (calendar.series.isEmpty ||
        calendar.series.map((event) => event.uid).toSet().length !=
            calendar.series.length) {
      lastOperationFailed = true;
      _notify();
      return false;
    }
    return _commit(() {
      final nextEvents = mode == TimetableImportMode.replace
          ? <String, TimetableSeries>{}
          : {for (final event in _events) event.uid: event};
      for (final event in calendar.series) {
        if (event.uid.trim().isEmpty || event.summary.trim().isEmpty) {
          throw const FormatException('Invalid timetable event');
        }
        nextEvents[event.uid] = event;
      }

      final nextMappings = <String, TimetableRoomMapping>{};
      if (mode == TimetableImportMode.update) {
        for (final mapping in _mappings) {
          final updatedEvent = nextEvents[mapping.uid];
          if (updatedEvent != null &&
              normalizeRoomLocation(updatedEvent.location ?? '') ==
                  mapping.normalizedLocation) {
            nextMappings[mapping.key] = mapping;
          }
        }
      }
      return (nextEvents.values.toList(), nextMappings.values.toList());
    });
  }

  Future<bool> assignRoom(
    String uid,
    String normalizedLocation,
    SavedPlace room,
  ) async {
    if (!ready && !await load()) return false;
    final event = eventFor(uid);
    final normalized = normalizeRoomLocation(normalizedLocation);
    if (event == null ||
        room.kind != PlaceKind.room ||
        normalized.isEmpty ||
        normalized != normalizeRoomLocation(event.location ?? '')) {
      return false;
    }
    return _commit(() {
      final nextEvents = List<TimetableSeries>.of(_events);
      final mapping = TimetableRoomMapping(
        uid: uid,
        normalizedLocation: normalized,
        room: room,
      );
      final nextMappings = {
        for (final value in _mappings)
          if (value.key != mapping.key) value.key: value,
        mapping.key: mapping,
      };
      return (nextEvents, nextMappings.values.toList());
    });
  }

  Future<bool> clear() async {
    if (!ready && !await load()) return false;
    return _commit(() => (<TimetableSeries>[], <TimetableRoomMapping>[]));
  }

  Future<bool> _commit(
    (List<TimetableSeries>, List<TimetableRoomMapping>) Function() prepare,
  ) async {
    if (!ready || _disposed) return false;
    _pendingWrites++;
    _notify();
    var success = false;
    final operation = _writes.then((_) async {
      try {
        final (events, mappings) = prepare();
        final value = jsonEncode({
          'version': 1,
          'events': events.map((event) => event.toJson()).toList(),
          'mappings': mappings.map((mapping) => mapping.toJson()).toList(),
        });
        await _write(value);
        _events = List.unmodifiable(events);
        _mappings = List.unmodifiable(mappings);
        lastOperationFailed = false;
        success = true;
      } catch (_) {
        lastOperationFailed = true;
      } finally {
        _pendingWrites--;
        _notify();
      }
    });
    _writes = operation;
    await operation;
    return success;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
