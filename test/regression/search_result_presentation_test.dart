import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/ui/search_result_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memoizes valid place models for only the current result object', () {
    final cache = SearchResultPresentationCache();
    const result = SearchResult(
      assist: '',
      assist2: '',
      resultsRooms: [
        SearchResultObject(
            name: 'APB E069',
            subName: null,
            identifier: 'apb/00/raum/542100.2860'),
        SearchResultObject(
            name: 'Invalid room', subName: null, identifier: 'not-a-room'),
      ],
      resultsBuildings: [
        SearchResultObject(
            name: 'APB', subName: null, identifier: 'dresden/geb/apb'),
        SearchResultObject(
            name: 'Invalid building', subName: null, identifier: 'invalid'),
      ],
      moreRooms: false,
      moreBuildings: false,
      trenn: 0,
    );

    final first = cache.forResult(result);
    final reused = cache.forResult(result);

    expect(identical(first, reused), isTrue);
    expect(first.rooms.map((entry) => entry.place.roomId), ['542100.2860']);
    expect(
        first.buildings.map((place) => place.identifier), ['dresden/geb/apb']);

    const nextResult = SearchResult(
      assist: '',
      assist2: '',
      resultsRooms: [],
      resultsBuildings: [],
      moreRooms: false,
      moreBuildings: false,
      trenn: 0,
    );
    expect(identical(cache.forResult(nextResult), first), isFalse);
  });
}
