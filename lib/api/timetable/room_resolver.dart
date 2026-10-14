import '../saved_places.dart';
import '../search.dart';

enum RoomResolutionStatus { uniqueRoom, ambiguous, buildingOnly, unresolved }

class RoomResolution {
  final RoomResolutionStatus status;
  final List<SavedPlace> candidates;

  const RoomResolution._(this.status, this.candidates);

  SavedPlace? get room =>
      status == RoomResolutionStatus.uniqueRoom ? candidates.single : null;

  SavedPlace? get building =>
      status == RoomResolutionStatus.buildingOnly ? candidates.single : null;
}

/// Resolves only the calendar LOCATION field through validated campus results.
class RoomResolver {
  final Future<SearchResult> Function(String location) _search;

  RoomResolver({required Future<SearchResult> Function(String) search})
      : _search = search;

  Future<RoomResolution> resolve(String location) async {
    final query = location.trim();
    if (query.isEmpty) return _unresolved();
    final normalizedQuery = normalizeRoomLocation(query);
    try {
      final response = await _search(query);
      final roomMatches = <String, SavedPlace>{};
      final roomCandidates = <String, SavedPlace>{};
      for (final result in response.resultsRooms) {
        final place = SavedPlace.tryFromSearch(result, PlaceKind.room);
        if (place == null) continue;
        roomCandidates.putIfAbsent(place.identifier, () => place);
        if (_aliases(result).contains(normalizedQuery)) {
          roomMatches.putIfAbsent(place.identifier, () => place);
        }
      }
      if (roomMatches.length == 1) {
        return RoomResolution._(
          RoomResolutionStatus.uniqueRoom,
          List.unmodifiable(roomMatches.values),
        );
      }
      if (roomMatches.length > 1) {
        return RoomResolution._(
          RoomResolutionStatus.ambiguous,
          List.unmodifiable(roomMatches.values),
        );
      }

      final buildingMatches = <String, SavedPlace>{};
      for (final result in response.resultsBuildings) {
        final place = SavedPlace.tryFromSearch(result, PlaceKind.building);
        if (place == null || !_aliases(result).contains(normalizedQuery)) {
          continue;
        }
        buildingMatches.putIfAbsent(place.identifier, () => place);
      }
      if (buildingMatches.length == 1) {
        return RoomResolution._(
          RoomResolutionStatus.buildingOnly,
          List.unmodifiable(buildingMatches.values),
        );
      }
      if (buildingMatches.length > 1) {
        return RoomResolution._(
          RoomResolutionStatus.ambiguous,
          List.unmodifiable(buildingMatches.values),
        );
      }
      return RoomResolution._(
        RoomResolutionStatus.unresolved,
        List.unmodifiable(roomCandidates.values),
      );
    } catch (_) {
      return _unresolved();
    }
  }

  RoomResolution _unresolved() => const RoomResolution._(
        RoomResolutionStatus.unresolved,
        [],
      );
}

Set<String> _aliases(SearchResultObject result) {
  final values = <String>{
    normalizeRoomLocation(result.name),
    if (result.subName != null) normalizeRoomLocation(result.subName!),
    if (result.detail != null) normalizeRoomLocation(result.detail!),
  };
  final name = normalizeRoomLocation(result.name);
  final detail = normalizeRoomLocation(result.detail ?? '');
  if (name.isNotEmpty && detail.isNotEmpty) values.add('$detail$name');

  // TU room sub-names use canonical paths such as APB/EG/raum/E069. Their
  // stable building and room segments also cover common timetable spellings.
  final path = (result.subName ?? result.identifier).split('/');
  final roomMarker = path.indexWhere((part) => part.toLowerCase() == 'raum');
  if (roomMarker > 0 && roomMarker + 1 < path.length) {
    final building = normalizeRoomLocation(path.first);
    final room = normalizeRoomLocation(path[roomMarker + 1]);
    if (building.isNotEmpty && room.isNotEmpty) {
      values.add('$building$room');
      values.add('$building/$room');
    }
  }
  return values.where((value) => value.isNotEmpty).toSet();
}

String normalizeRoomLocation(String value) {
  final folded = value
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  return folded.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}
