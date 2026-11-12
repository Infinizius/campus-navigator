import 'package:flutter_test/flutter_test.dart';
import 'package:campus_navigator/api/mobibike/mobibike.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);
  final timestamp = now.millisecondsSinceEpoch ~/ 1000;
  Map<String, dynamic> feed(String key, List<dynamic> rows) => {
        'last_updated': timestamp,
        'ttl': 60,
        'data': {key: rows}
      };
  Map<String, dynamic> station(String id) =>
      {'station_id': id, 'name': 'Campus $id', 'lat': 51.03, 'lon': 13.73};
  Map<String, dynamic> status(String id, {bool renting = true}) => {
        'station_id': id,
        'is_installed': true,
        'is_renting': renting,
        'num_bikes_available': 3,
        'last_reported': timestamp
      };
  Map<String, dynamic> bike(String id,
          {bool reserved = false, bool disabled = false, String? stationId}) =>
      {
        'bike_id': id,
        'lat': 51.03,
        'lon': 13.73,
        'is_reserved': reserved,
        'is_disabled': disabled,
        if (stationId != null) 'station_id': stationId
      };

  test(
      'only rentable stations and available free-standing bikes are shown once',
      () {
    final result = BikeSnapshot.parse(
        feed('stations', [station('a'), station('b')]),
        feed('stations', [status('a'), status('b', renting: false)]),
        feed('bikes', [
          bike('1'),
          bike('1'),
          bike('2', reserved: true),
          bike('3', disabled: true),
          bike('4', stationId: 'a')
        ]),
        now);
    expect(result.places.map((p) => p.id), ['station:a', 'bike:1']);
    expect(result.places.first.available, 3);
    expect(result.refreshAfter, const Duration(seconds: 60));
    expect(result.isStale(now), false);
    expect(result.isStale(now.add(const Duration(minutes: 6))), true);
  });

  test(
      'invalid coordinates, missing availability and stale station reports are excluded',
      () {
    final old = status('old')..['last_reported'] = timestamp - 3600;
    final invalid = station('invalid')..['lat'] = 500;
    final result = BikeSnapshot.parse(
        feed('stations', [station('old'), invalid, station('missing')]),
        feed('stations', [old, status('invalid')]),
        feed('bikes', [bike('bad')..remove('is_reserved')]),
        now);
    expect(result.places, isEmpty);
  });

  test('unrecognized feed structure fails rather than reporting an empty fleet',
      () {
    expect(() => BikeSnapshot.parse({}, {}, {}, now), throwsFormatException);
  });
}
