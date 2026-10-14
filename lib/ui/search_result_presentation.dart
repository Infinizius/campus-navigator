import '../api/saved_places.dart';
import '../api/search.dart';

typedef SearchRoomPresentationEntry = ({
  SavedPlace place,
  SearchResultObject result,
});

class SearchResultPresentation {
  final List<SearchRoomPresentationEntry> rooms;
  final List<SavedPlace> buildings;

  SearchResultPresentation._({
    required this.rooms,
    required this.buildings,
  });
}

/// Keeps converted rows for only the current result object. Search results
/// are replaced as snapshots by the search controller and are not mutated by
/// the search flow; the cache is owned by one search screen.
class SearchResultPresentationCache {
  SearchResult? _source;
  SearchResultPresentation? _presentation;

  SearchResultPresentation forResult(SearchResult result) {
    if (identical(_source, result)) return _presentation!;

    final rooms = <SearchRoomPresentationEntry>[];
    for (final entry in result.resultsRooms) {
      final place = SavedPlace.tryFromSearch(entry, PlaceKind.room);
      if (place != null) rooms.add((place: place, result: entry));
    }
    final buildings = <SavedPlace>[];
    for (final entry in result.resultsBuildings) {
      final place = SavedPlace.tryFromSearch(entry, PlaceKind.building);
      if (place != null) buildings.add(place);
    }

    _source = result;
    return _presentation = SearchResultPresentation._(
      rooms: List.unmodifiable(rooms),
      buildings: List.unmodifiable(buildings),
    );
  }
}
