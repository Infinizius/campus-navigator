import 'dart:convert';
import 'dart:io';

import 'package:campus_navigator/api/mensa/mensa_models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> fixtureString(String name) =>
    File('test/fixtures/$name').readAsString();

void main() {
  test('parses the Studentenwerk canteen listing and optional coordinates',
      () async {
    final json =
        jsonDecode(await fixtureString('mensa/canteens.json')) as List<dynamic>;
    final canteens = json.map((item) => MensaCanteen.fromJson(item)).toList();

    expect(canteens.first.id, 9);
    expect(canteens.first.name, 'Mensa Siedepunkt');
    expect(canteens.first.latitude, closeTo(51.0294606, 0.000001));
    expect(canteens.first.longitude, closeTo(13.7387279, 0.000001));
    expect(canteens.last.city, 'Tharandt');
    expect(canteens.last.menuUrl, isNull);
  });

  test('rejects invalid coordinates while preserving the canteen', () {
    final canteen = MensaCanteen.fromJson({
      'id': 1,
      'name': 'Testmensa',
      'city': 'Dresden',
      'address': 'Adresse',
      'coordinates': [93, 14],
    });

    expect(canteen.latitude, isNull);
    expect(canteen.longitude, isNull);
  });

  test('parses available and explicitly closed dates', () async {
    final json =
        jsonDecode(await fixtureString('mensa/days.json')) as List<dynamic>;
    final days = json.map((item) => MensaAvailableDay.fromJson(item)).toList();

    expect(days.first.date, DateTime(2026, 11, 11));
    expect(days.first.closed, isFalse);
    expect(days.last.date, DateTime(2026, 11, 14));
    expect(days.last.closed, isTrue);
  });

  test('preserves all prices and only uses explicit dietary notes', () async {
    final json =
        jsonDecode(await fixtureString('mensa/meals.json')) as List<dynamic>;
    final meals = json.map((item) => MensaMeal.fromJson(item)).toList();

    expect(meals.first.prices, {'Studierende': 4.32, 'Bedienstete': 7.86});
    expect(meals.first.isVegetarian, isFalse);
    expect(meals[1].isVegan, isTrue);
    expect(meals[1].isVegetarian, isTrue);
    expect(meals[1].soldOut, isTrue);
    expect(meals[2].isVegetarian, isTrue);
    expect(meals[2].prices, isEmpty);
  });

  test('menu snapshots retain the date and successful retrieval time', () {
    final fetchedAt = DateTime.utc(2026, 11, 11, 8, 45);
    final plan = MensaMenuPlan(
      canteenId: 9,
      date: DateTime(2026, 11, 11),
      meals: const [],
      fetchedAt: fetchedAt,
    );

    final restored = MensaMenuPlan.fromJson(plan.toJson());
    expect(restored.canteenId, 9);
    expect(restored.date, DateTime(2026, 11, 11));
    expect(restored.fetchedAt, fetchedAt);
    expect(restored.meals, isEmpty);
  });
}
