import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/api/timetable/room_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult response({
  List<SearchResultObject> rooms = const [],
  List<SearchResultObject> buildings = const [],
}) =>
    SearchResult(
      assist: '',
      assist2: '',
      resultsBuildings: buildings,
      resultsRooms: rooms,
      moreBuildings: false,
      moreRooms: false,
      trenn: 0,
    );

SearchResultObject room({
  required String code,
  required String floor,
  required String id,
  required String name,
  String? subName,
  String? detail,
}) =>
    SearchResultObject(
      name: name,
      subName: subName,
      identifier: '$code/$floor/raum/$id',
      detail: detail,
    );

void main() {
  test('matches_apb_separator_variants', () async {
    final candidate = room(
      code: 'apb',
      floor: 'eg',
      id: 'e069',
      name: 'E069',
      subName: 'APB/EG/raum/E069',
    );
    for (final location in ['APB E069', 'APB/E069']) {
      final result = await RoomResolver(
        search: (_) async => response(rooms: [candidate]),
      ).resolve(location);
      expect(result.status, RoomResolutionStatus.uniqueRoom);
      expect(result.room?.identifier, 'apb/eg/raum/e069');
    }
  });

  test('matches_full_building_name_and_room', () async {
    final result = await RoomResolver(
      search: (_) async => response(
        rooms: [
          room(
            code: 'apb',
            floor: 'eg',
            id: 'e069',
            name: 'E069',
            subName: 'APB/EG/raum/E069',
            detail: 'Andreas-Pfitzmann-Bau',
          ),
        ],
      ),
    ).resolve('Andreas-Pfitzmann-Bau, E069');

    expect(result.status, RoomResolutionStatus.uniqueRoom);
    expect(result.room?.identifier, 'apb/eg/raum/e069');
  });

  test('matches_bey_and_bar_examples', () async {
    final cases = [
      ('BEY 318', 'bey', '03', '318'),
      ('BAR/218', 'bar', '02', '218'),
    ];
    for (final (location, code, floor, roomId) in cases) {
      final result = await RoomResolver(
        search: (_) async => response(
          rooms: [
            room(
              code: code,
              floor: floor,
              id: roomId,
              name: roomId,
              subName: '$code/$floor/raum/$roomId',
            ),
          ],
        ),
      ).resolve(location);
      expect(result.status, RoomResolutionStatus.uniqueRoom);
      expect(result.room?.roomId, roomId);
    }
  });

  test('ambiguous_room_is_never_auto_assigned', () async {
    final result = await RoomResolver(
      search: (_) async => response(rooms: [
        room(code: 'apb', floor: 'eg', id: 'e069', name: 'E069'),
        room(code: 'bey', floor: '03', id: 'e069', name: 'E069'),
      ]),
    ).resolve('E069');

    expect(result.status, RoomResolutionStatus.ambiguous);
    expect(result.room, isNull);
    expect(result.candidates, hasLength(2));
  });

  test('returns_building_only_without_room', () async {
    final result = await RoomResolver(
      search: (_) async => response(buildings: const [
        SearchResultObject(
          name: 'Andreas-Pfitzmann-Bau',
          subName: 'APB',
          identifier: 'dresden/geb/apb',
        ),
      ]),
    ).resolve('Andreas-Pfitzmann-Bau');

    expect(result.status, RoomResolutionStatus.buildingOnly);
    expect(result.building?.kind, PlaceKind.building);
  });

  test('returns_unresolved_for_unknown_room', () async {
    final result = await RoomResolver(
      search: (_) async => response(rooms: [
        room(code: 'apb', floor: 'eg', id: 'e069', name: 'E069'),
      ]),
    ).resolve('Unknown building room');

    expect(result.status, RoomResolutionStatus.unresolved);
    expect(result.room, isNull);
  });

  test('sends_location_only_to_search', () async {
    String? query;
    final result = await RoomResolver(
      search: (value) async {
        query = value;
        return response();
      },
    ).resolve('APB E069');

    expect(result.status, RoomResolutionStatus.unresolved);
    expect(query, 'APB E069');
  });
}
