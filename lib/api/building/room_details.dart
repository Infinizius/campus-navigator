import 'package:html/dom.dart';
import 'package:html/parser.dart';

enum RoomFieldState { absent, unknown, value }

/// Optional room data can be missing, explicitly unknown, or known.
class RoomField<T> {
  final RoomFieldState state;
  final T? value;

  const RoomField._(this.state, this.value);

  const RoomField.absent() : this._(RoomFieldState.absent, null);

  const RoomField.unknown() : this._(RoomFieldState.unknown, null);

  const RoomField.value(T value) : this._(RoomFieldState.value, value);
}

class RoomDetailsFormatException implements Exception {
  final String message;

  const RoomDetailsFormatException(this.message);

  @override
  String toString() => 'RoomDetailsFormatException: $message';
}

class RoomDetails {
  final String roomId;
  final RoomField<String> name;
  final int? typeCode;
  final List<RoomDoorConnection> doors;
  final RoomField<String> accessibility;
  final RoomField<String> doorplate;
  final RoomPageDetails? pageDetails;

  const RoomDetails({
    required this.roomId,
    required this.name,
    required this.typeCode,
    required this.doors,
    required this.accessibility,
    required this.doorplate,
    this.pageDetails,
  });

  factory RoomDetails.fromJson(String roomId, Map<String, dynamic> json) {
    if (!_roomIdPattern.hasMatch(roomId)) {
      throw const RoomDetailsFormatException('Invalid room ID');
    }

    final rawDoors = json['doors'];
    if (rawDoors != null && rawDoors is! List) {
      throw const RoomDetailsFormatException('Expected doors to be a list');
    }

    final doors = <RoomDoorConnection>[];
    for (final rawDoor in rawDoors ?? const []) {
      if (rawDoor is! Map) {
        throw const RoomDetailsFormatException(
            'Expected each door to be an object');
      }
      doors
          .add(RoomDoorConnection.fromJson(Map<String, dynamic>.from(rawDoor)));
    }

    final rawType = json['type'];
    final typeCode = rawType is int
        ? rawType
        : rawType is num && rawType == rawType.roundToDouble()
            ? rawType.toInt()
            : null;

    return RoomDetails(
      roomId: roomId,
      name: _stringField(json['name']),
      typeCode: typeCode,
      doors: List.unmodifiable(doors),
      accessibility: json.containsKey('accessibility')
          ? const RoomField<String>.unknown()
          : const RoomField<String>.absent(),
      doorplate: json.containsKey('doorplate')
          ? const RoomField<String>.unknown()
          : const RoomField<String>.absent(),
    );
  }

  RoomDetails withPageDetails(RoomPageDetails details) => RoomDetails(
        roomId: roomId,
        name: name,
        typeCode: typeCode,
        doors: doors,
        accessibility: accessibility,
        doorplate: doorplate,
        pageDetails: details,
      );
}

class RoomDoorConnection {
  final String? doorId;
  final RoomDoorEnd? room1;
  final RoomDoorEnd? room2;

  const RoomDoorConnection({
    required this.doorId,
    required this.room1,
    required this.room2,
  });

  factory RoomDoorConnection.fromJson(Map<String, dynamic> json) {
    return RoomDoorConnection(
      doorId: _optionalString(json['doorid']),
      room1: _doorEnd(json['room1']),
      room2: _doorEnd(json['room2']),
    );
  }

  RoomDoorEnd? otherRoomFor(String roomId) {
    if (room1?.id == roomId) return room2;
    if (room2?.id == roomId) return room1;
    return null;
  }
}

class RoomDoorEnd {
  final String? id;
  final String? room;
  final String? floor;
  final String? buildingNumber;

  const RoomDoorEnd({
    required this.id,
    required this.room,
    required this.floor,
    required this.buildingNumber,
  });

  factory RoomDoorEnd.fromJson(Map<String, dynamic> json) => RoomDoorEnd(
        id: _optionalString(json['ID']),
        room: _optionalString(json['room']),
        floor: _optionalString(json['floor']),
        buildingNumber: _optionalString(json['buildingNumber']),
      );
}

class RoomPageDetails {
  final RoomField<String> roomName;
  final RoomField<String> buildingPart;
  final RoomField<String> buildingNumber;
  final RoomField<String> floor;
  final RoomField<int> places;
  final RoomField<String> remark;
  final RoomField<String> usage;
  final RoomField<String> doorplateGerman;
  final RoomField<String> doorplateEnglish;

  const RoomPageDetails({
    required this.roomName,
    required this.buildingPart,
    required this.buildingNumber,
    required this.floor,
    required this.places,
    required this.remark,
    required this.usage,
    required this.doorplateGerman,
    required this.doorplateEnglish,
  });

  factory RoomPageDetails.fromHtml(String html) {
    final document = parse(html);
    final information = document.querySelector('#menu_cont_right');
    final informationText = _textNodes(information);
    final allText = _textNodes(document.body);

    return RoomPageDetails(
      roomName: _firstMatching(informationText, (text) {
        for (final prefix in const ['Raum ', 'Room ']) {
          if (text.startsWith(prefix)) {
            return _valueAfterColon(text) ?? text.substring(prefix.length);
          }
        }
        return null;
      }),
      buildingPart:
          _fieldAfter(informationText, const ['Teilgebäude', 'Building part']),
      buildingNumber: _fieldAfter(informationText, const [
        'Gebäude-Nr.',
        'Gebäudenr.',
        'Building-nr',
        'Building-nr.',
        'Building no.'
      ]),
      floor: _fieldAfter(informationText, const ['Etage', 'Floor']),
      places: _intFieldAfter(informationText, const ['Plätze', 'Places']),
      remark: _fieldAfter(informationText, const ['Bemerkung', 'Remark']),
      usage: _fieldAfter(informationText, const ['Nutzung', 'Usage']),
      doorplateGerman: _fieldAfter(
          allText, const ['Org.einheit* (deutsch)', 'Organiz. unit* (german)']),
      doorplateEnglish: _fieldAfter(allText,
          const ['Org.einheit* (englisch)', 'Organiz. unit* (english)']),
    );
  }
}

final _roomIdPattern = RegExp(r'^\d{6}\.\d{4}$');

RoomDoorEnd? _doorEnd(dynamic json) {
  if (json == null) return null;
  if (json is! Map) {
    throw const RoomDetailsFormatException(
        'Expected connected room data to be an object');
  }
  return RoomDoorEnd.fromJson(Map<String, dynamic>.from(json));
}

RoomField<String> _stringField(dynamic raw) {
  if (raw == null) return const RoomField<String>.absent();
  if (raw is! String) {
    throw const RoomDetailsFormatException('Expected text room data');
  }
  final value = raw.trim();
  if (value.isEmpty) return const RoomField<String>.absent();
  if (value.toUpperCase() == 'NO_INFO') {
    return const RoomField<String>.unknown();
  }
  return RoomField<String>.value(value);
}

String? _optionalString(dynamic raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const RoomDetailsFormatException('Expected text in room connection');
  }
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

RoomField<String> _fieldAfter(List<String> texts, List<String> labels) =>
    _firstMatching(texts, (text) {
      final value = _valueAfterLabels(text, labels);
      if (value != null) return value;
      if (_matchesLabel(text, labels)) return _nextAfter(texts, text);
      return null;
    });

RoomField<int> _intFieldAfter(List<String> texts, List<String> labels) {
  final textValue = _fieldAfter(texts, labels);
  if (textValue.state == RoomFieldState.absent) {
    return const RoomField<int>.absent();
  }
  if (textValue.state == RoomFieldState.unknown) {
    return const RoomField<int>.unknown();
  }
  final parsed = int.tryParse(textValue.value!);
  return parsed == null
      ? const RoomField<int>.unknown()
      : RoomField<int>.value(parsed);
}

RoomField<T> _firstMatching<T>(
    List<String> texts, String? Function(String text) extractor) {
  for (var index = 0; index < texts.length; index++) {
    final value = extractor(texts[index]);
    if (value == null) continue;
    if (value.trim().isEmpty) return RoomField<T>.absent();
    if (value.trim().toUpperCase() == 'NO_INFO') {
      return RoomField<T>.unknown();
    }
    if (T == int) {
      final parsed = int.tryParse(value.trim());
      return parsed == null
          ? RoomField<T>.unknown()
          : RoomField<T>.value(parsed as T);
    }
    return RoomField<T>.value(value.trim() as T);
  }
  return RoomField<T>.absent();
}

bool _matchesLabel(String text, List<String> labels) {
  final normalized = _normalizeLabel(text);
  return labels.map(_normalizeLabel).contains(normalized);
}

String? _valueAfterLabels(String text, List<String> labels) {
  for (final label in labels) {
    final normalizedText = text.trim();
    final prefix = '$label:';
    if (normalizedText.toLowerCase().startsWith(prefix.toLowerCase())) {
      final remainder = normalizedText.substring(prefix.length).trim();
      if (remainder.isNotEmpty) return remainder;
    }
  }
  return null;
}

String? _valueAfterColon(String text) {
  final colon = text.indexOf(':');
  if (colon < 0) return null;
  final value = text.substring(colon + 1).trim();
  return value.isEmpty ? null : value;
}

String _normalizeLabel(String value) =>
    value.trim().replaceAll(RegExp(r'[:\s]+$'), '').toLowerCase();

String? _nextAfter(List<String> texts, String text) {
  final index = texts.indexOf(text);
  if (index < 0 || index + 1 >= texts.length) return null;
  return texts[index + 1];
}

List<String> _textNodes(Node? root) {
  if (root == null) return const [];
  final results = <String>[];
  void visit(Node node) {
    if (node is Text) {
      final normalized = node.data.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isNotEmpty) results.add(normalized);
      return;
    }
    for (final child in node.nodes) {
      visit(child);
    }
  }

  visit(root);
  return results;
}
