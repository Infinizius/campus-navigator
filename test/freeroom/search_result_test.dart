import 'package:campus_navigator/api/freeroom_search/search_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single university responses and occupied slots', () {
    final data = FreeroomSearchResult.fromJson({
      'rooms': ['APB/E001/U', 'APB/E002/U'],
      'taken': List.generate(63, (i) => i == 0 ? [1] : <int>[]),
      'roominfo': <String, dynamic>{},
    });
    expect(data.freeRoomsFor(0, 0), ['APB/E001/U']);
    expect(data.freeRoomsFor(0, 1), ['APB/E001/U', 'APB/E002/U']);
    expect(data.htwRooms, isEmpty);
  });
  test('HTW only and empty lists are safe', () {
    final data = FreeroomSearchResult.fromJson({
      'htw_rooms': ['S 221'],
      'htw_taken': List.generate(63, (i) => <int>[]),
      'htw_roominfo': <String, dynamic>{},
    });
    expect(data.freeRoomsFor(1, 0, htw: true), ['S 221']);
    expect(data.freeRoomsFor(1, 0), isEmpty);
  });
  test('incomplete occupancy data must never imply free rooms', () {
    final data = FreeroomSearchResult.fromJson({
      'rooms': ['APB/E001/U'],
      'taken': <dynamic>[],
      'roominfo': <String, dynamic>{},
    });
    expect(() => data.freeRoomsFor(0, 0), throwsFormatException);
  });

  test('unknown occupied indices cannot be treated as free', () {
    final data = FreeroomSearchResult.fromJson({
      'rooms': ['APB/E001/U'],
      'taken': [[-1, 5]],
      'roominfo': <String, dynamic>{},
    });
    expect(() => data.freeRoomsFor(0, 0), throwsFormatException);
  });

  test('the observed -1 server sentinel is ignored', () {
    final data = FreeroomSearchResult.fromJson({
      'rooms': ['APB/E001/U'],
      'taken': [[-1]],
      'roominfo': <String, dynamic>{},
    });
    expect(data.freeRoomsFor(0, 0), ['APB/E001/U']);
  });
}
