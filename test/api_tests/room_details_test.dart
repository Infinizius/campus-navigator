import 'dart:convert';
import 'dart:io';

import 'package:campus_navigator/api/building/room_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomDetails API response', () {
    test('parses the observed room fields and related door room', () async {
      final fixture =
          await File('test/fixtures/room_details/room_325301_0010.json')
              .readAsString();

      final details = RoomDetails.fromJson(
          '325301.0010', jsonDecode(fixture) as Map<String, dynamic>);

      expect(details.roomId, '325301.0010');
      expect(details.name.value, '151');
      expect(details.typeCode, 22);
      expect(details.doors, hasLength(1));
      expect(details.doors.single.doorId, '325301O.000074');
      expect(
          details.doors.single.otherRoomFor('325301.0010')?.id, '325301.0032');
      expect(
          details.doors.single.otherRoomFor('325301.0032')?.id, '325301.0010');
    });

    test('keeps an empty door list for a room with no connections', () async {
      final fixture =
          await File('test/fixtures/room_details/room_325301_0032.json')
              .readAsString();

      final details = RoomDetails.fromJson(
          '325301.0032', jsonDecode(fixture) as Map<String, dynamic>);

      expect(details.name.value, '151C');
      expect(details.typeCode, 25);
      expect(details.doors, isEmpty);
    });

    test('does not treat opaque accessibility objects as accessibility facts',
        () async {
      final fixture = await File(
              'test/fixtures/room_details/room_325301_0010_optional.json')
          .readAsString();
      final details = RoomDetails.fromJson(
          '325301.0010', jsonDecode(fixture) as Map<String, dynamic>);

      expect(details.accessibility.state, RoomFieldState.unknown);
      expect(details.doorplate.state, RoomFieldState.unknown);
    });

    test('rejects malformed door structures instead of inventing connections',
        () {
      expect(
        () => RoomDetails.fromJson('325301.0010', {
          'doors': 'not-a-list',
          'name': '151',
        }),
        throwsA(isA<RoomDetailsFormatException>()),
      );
    });
  });

  test('parses labeled page details and distinguishes absent from NO_INFO',
      () async {
    final fixture =
        await File('test/fixtures/room_details/room_325301_0010.html')
            .readAsString();

    final page = RoomPageDetails.fromHtml(fixture);

    expect(page.roomName.value, '151');
    expect(page.buildingPart.value,
        'POT Gerhart-Potthoff-Bau Haus 2, Hettnerstr. 1, 3');
    expect(page.buildingNumber.value, '3253');
    expect(page.floor.value, 'Etage 1');
    expect(page.places.value, 128);
    expect(page.remark.value, 'mobile Liege');
    expect(page.usage.value,
        'Hör-/Lehrsaal ansteigend ohne Experimentierbühne mit RLT-Anforderungen');
    expect(page.doorplateGerman.value, 'Bewirt. Flächen Zentraler Lehrraum');
    expect(page.doorplateEnglish.state, RoomFieldState.absent);

    final sparse = RoomPageDetails.fromHtml('''
      <div id="menu_cont_right">
        <p>Teilgebäude:</p><p>NO_INFO</p>
      </div>
    ''');
    expect(sparse.buildingPart.state, RoomFieldState.unknown);
    expect(sparse.places.state, RoomFieldState.absent);

    final englishFixture =
        await File('test/fixtures/room_details/room_325301_0010_en.html')
            .readAsString();
    final english = RoomPageDetails.fromHtml(englishFixture);
    expect(english.roomName.value, '151');
    expect(english.buildingPart.value,
        'POT Gerhart-Potthoff-Bau Haus 2, Hettnerstr. 1, 3');
    expect(english.buildingNumber.value, '3253');
    expect(english.floor.value, 'floor 1');
    expect(english.places.value, 128);
    expect(english.usage.value, 'Lecture hall with ventilation requirements');
    expect(english.doorplateGerman.value, 'Bewirt. Flächen Zentraler Lehrraum');
  });
}
