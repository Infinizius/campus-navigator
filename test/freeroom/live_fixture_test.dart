import 'dart:convert';
import 'dart:io';
import 'package:campus_navigator/api/freeroom_search/search_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public timetable bookings are excluded for their day and period', () {
    final json = jsonDecode(
        File('test/fixtures/freeroom/tu_week46_timetable.json')
            .readAsStringSync());
    final result = FreeroomSearchResult.fromJson(json);
    final cases = [
      ('ZEU/0160/H', 2, 0),
      ('ZEU/0148/U', 3, 0),
      ('JAN/0027/H', 4, 0),
      ('TRE/PHYS/E', 0, 1),
      ('ZEU/0260/H', 1, 1),
      ('HSZ/0301/U', 3, 3),
      ('HSZ/0301/U', 3, 4),
      ('MS1/0322/U', 4, 1),
    ];
    for (final (room, day, period) in cases) {
      expect(result.freeRoomsFor(day, period), isNot(contains(room)),
          reason: '$room day $day period $period');
    }
  });

  test('parses reduced live TU and HTW response', () {
    final json = jsonDecode(
        File('test/fixtures/freeroom/tu_htw_sample.json').readAsStringSync());
    final result = FreeroomSearchResult.fromJson(json);
    expect(result.rooms, hasLength(3));
    expect(result.htwRooms, hasLength(3));
    for (var day = 0; day < 7; day++) {
      for (var period = 0; period < 7; period++) {
        expect(result.freeRoomsFor(day, period).every(result.rooms.contains),
            isTrue);
        expect(
            result
                .freeRoomsFor(day, period, htw: true)
                .every(result.htwRooms.contains),
            isTrue);
      }
    }
  });
}
