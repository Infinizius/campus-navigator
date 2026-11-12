import 'dart:io';

import 'package:campus_navigator/api/mensa/mensa_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<String> fixtureString(String name) =>
    File('test/fixtures/mensa/$name').readAsString();

http.Response jsonResponse(String body, int statusCode) => http.Response(
      body,
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('loads Studentenwerk canteens from the configured base URL', () async {
    final body = await fixtureString('canteens.json');
    late Uri requested;
    final api = MensaApi(
        baseUrl: 'https://example.test/openmensa/v2',
        client: MockClient((request) async {
          requested = request.url;
          expect(request.headers['accept'], contains('application/json'));
          return jsonResponse(body, 200);
        }));

    final canteens = await api.fetchCanteens();

    expect(requested.toString(), 'https://example.test/openmensa/v2/canteens');
    expect(canteens.map((canteen) => canteen.id), [9, 10]);
  });

  test('requests published days from the requested local date', () async {
    final body = await fixtureString('days.json');
    late Uri requested;
    final api = MensaApi(
        baseUrl: 'https://example.test/openmensa/v2',
        client: MockClient((request) async {
          requested = request.url;
          return jsonResponse(body, 200);
        }));

    final days = await api.fetchDays(9, DateTime(2026, 11, 11));

    expect(requested.path, '/openmensa/v2/canteens/9/days');
    expect(requested.queryParameters['start'], '2026-11-11');
    expect(days, hasLength(2));
    expect(days.last.closed, isTrue);
  });

  test('loads categorized meal data for one exact date', () async {
    final body = await fixtureString('meals.json');
    late Uri requested;
    final api = MensaApi(
        baseUrl: 'https://example.test/openmensa/v2',
        client: MockClient((request) async {
          requested = request.url;
          return jsonResponse(body, 200);
        }));

    final meals = await api.fetchMeals(9, DateTime(2026, 11, 11));

    expect(requested.path, '/openmensa/v2/canteens/9/days/2026-11-11/meals');
    expect(meals.map((meal) => meal.category).toSet(),
        {'Ausgabe links', 'Ausgabe Mitte', 'Ausgabe rechts'});
  });

  test('reports server errors without turning them into empty menus', () async {
    final api = MensaApi(
        client: MockClient((_) async => http.Response('unavailable', 503)));

    await expectLater(
        api.fetchCanteens(),
        throwsA(isA<MensaApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)));
  });

  test('rejects malformed JSON instead of returning no canteens', () async {
    final api = MensaApi(
        client: MockClient((_) async => http.Response('{broken', 200)));

    await expectLater(api.fetchCanteens(), throwsFormatException);
  });
}
