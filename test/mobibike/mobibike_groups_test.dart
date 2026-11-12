import 'package:campus_navigator/api/mobibike/mobibike.dart';
import 'package:campus_navigator/api/mobibike/bike_groups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  BikePlace bike(String id, double northMeters) => BikePlace(
      id, id, LatLng(51.03 + northMeters / 111320, 13.73), 1, false, null);
  test('overview never groups bikes hundreds of meters apart', () {
    final groups = groupBikePlaces([bike('a', 0), bike('b', 250)], 12);
    expect(groups, hasLength(2));
  });
  test('nearby bikes may group but a chain cannot exceed 100 meters', () {
    final places = [bike('a', 0), bike('b', 20), bike('c', 70), bike('d', 150)];
    final groups = groupBikePlaces(places, 12);
    expect(groups.length, lessThan(places.length));
    for (final group in groups) {
      for (final a in group) {
        for (final b in group) {
          expect(const Distance().as(LengthUnit.Meter, a.point, b.point),
              lessThanOrEqualTo(100));
        }
      }
    }
  });
  test('overlapping campus markers group and separate once they fit on screen',
      () {
    final places = [bike('a', 0), bike('b', 50)];
    expect(groupBikePlaces(places, 15), hasLength(1));
    expect(groupBikePlaces(places, 17), hasLength(2));
    expect(
        groupBikePlaces(places, 12)
            .map((g) => g.map((p) => p.id).toList())
            .toList(),
        groupBikePlaces(places.reversed.toList(), 12)
            .map((g) => g.map((p) => p.id).toList())
            .toList());
  });
  test('empty stations do not clutter overview but remain visible close up',
      () {
    final empty =
        BikePlace('station:empty', 'Empty', bike('p', 0).point, 0, true, null);
    expect(groupBikePlaces([empty], 14), isEmpty);
    expect(groupBikePlaces([empty], 16), hasLength(1));
  });
}
