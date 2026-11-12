import 'dart:convert';
import 'package:campus_navigator/api/mobibike/mobibike.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);
  final urls = {
    'station_information': 'https://gbfs.nextbike.net/custom/info.json',
    'station_status': 'https://gbfs.nextbike.net/custom/state.json',
    'free_bike_status': 'https://gbfs.nextbike.net/custom/vehicles.json'
  };
  final discovery = {
    'data': {
      'de': {
        'feeds': [
          for (final e in urls.entries) {'name': e.key, 'url': e.value}
        ]
      }
    }
  };
  Map<String, dynamic> emptyFeed(String key) => {
        'last_updated': now.millisecondsSinceEpoch ~/ 1000,
        'ttl': 120,
        'data': {key: []}
      };
  test(
      'availability URLs are taken from discovery, with envelope freshness preserved',
      () async {
    final requested = <String>[];
    final service = BikeGbfsService(
        now: () => now,
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return http.Response(
              jsonEncode(request.url.toString() == mobibikeDiscovery
                  ? discovery
                  : emptyFeed(request.url.toString() == urls['free_bike_status']
                      ? 'bikes'
                      : 'stations')),
              200);
        }));
    final result = await service.load();
    expect(requested.toSet(), {mobibikeDiscovery, ...urls.values});
    expect(result.places, isEmpty);
    expect(result.refreshAfter, const Duration(seconds: 120));
    expect(result.updatedAt, now);
    service.close();
  });
  test('server failure propagates instead of presenting an empty fleet',
      () async {
    final service = BikeGbfsService(
        now: () => now,
        client: MockClient((request) async => http.Response(
            jsonEncode(
                request.url.toString() == mobibikeDiscovery ? discovery : {}),
            request.url.toString() == mobibikeDiscovery ? 200 : 503)));
    await expectLater(service.load(), throwsA(isA<http.ClientException>()));
    service.close();
  });
}
