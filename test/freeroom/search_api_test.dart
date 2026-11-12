import 'dart:convert';
import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/freeroom_search/search.dart';
import 'package:campus_navigator/api/freeroom_search/search_options.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('serializes weekly and biweekly inclusive week ranges', () async {
    final requests = <Map<String, String>>[];
    final api = BaseAPIServices();
    api.client = MockClient((request) async {
      requests.add(request.bodyFields);
      return http.Response(
          jsonEncode({'rooms': [], 'taken': [], 'roominfo': {}}), 200);
    });
    for (final repeat in [Repetition.weekly, Repetition.biWeekly]) {
      await api.searchFreeRooms(
          startWeek: 50,
          endWeek: 52,
          universities: {UserUniversity.TUD},
          repetition: repeat);
    }
    expect(requests.map((r) => r['type']), ['2', '3']);
    expect(
        requests.every((r) => r['startwoche'] == '50' && r['endwoche'] == '52'),
        isTrue);
  });
  test('sends current week and optional capacity and accepts Latin-1',
      () async {
    final api = BaseAPIServices();
    api.client = MockClient((request) async {
      expect(request.bodyFields, {
        'startwoche': '53',
        'endwoche': '53',
        'type': '1',
        'mincapacity': '25',
        'maxcapacity': '-1',
        'hochschule': '0'
      });
      final json = jsonEncode({
        'rooms': ['GÖR/1/U'],
        'taken': List.generate(63, (_) => <int>[]),
        'roominfo': <String, dynamic>{},
        'htw_rooms': <String>[],
        'htw_taken': <dynamic>[],
        'htw_roominfo': <String, dynamic>{}
      });
      return http.Response.bytes(latin1.encode(json), 200,
          headers: {'content-type': 'text/plain; charset=ISO-8859-1'});
    });
    final result = await api.searchFreeRooms(
        startWeek: 53,
        endWeek: 53,
        universities: {UserUniversity.TUD, UserUniversity.HTW},
        minCapacity: 25);
    expect(result.freeRoomsFor(0, 0), ['GÖR/1/U']);
  });
  test('reports authentication requirement', () async {
    final api = BaseAPIServices()
      ..client = MockClient((_) async => http.Response('not authorized', 401));
    expect(
        api.searchFreeRooms(
            startWeek: 1, endWeek: 1, universities: {UserUniversity.TUD}),
        throwsA(isA<FreeRoomLoginRequired>()));
  });

  test('rejects a response missing the requested occupancy data', () async {
    final api = BaseAPIServices()
      ..client = MockClient((_) async => http.Response('{}', 200));
    expect(
      api.searchFreeRooms(
          startWeek: 1, endWeek: 1, universities: {UserUniversity.TUD}),
      throwsFormatException,
    );
  });
}
