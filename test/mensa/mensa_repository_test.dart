import 'dart:convert';

import 'package:campus_navigator/api/mensa/mensa_api.dart';
import 'package:campus_navigator/api/mensa/mensa_models.dart';
import 'package:campus_navigator/api/mensa/mensa_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response response(dynamic value, int status) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class MemoryMensaStore implements MensaLocalStore {
  int? favorite;
  List<MensaCanteen>? canteens;
  final Map<int, List<MensaAvailableDay>> days = {};
  final Map<String, MensaMenuPlan> menus = {};

  String _key(int id, DateTime date) =>
      '${id}_${date.year}-${date.month}-${date.day}';

  @override
  Future<int?> readFavoriteCanteenId() async => favorite;
  @override
  Future<void> saveFavoriteCanteenId(int? id) async => favorite = id;
  @override
  Future<List<MensaCanteen>?> readCanteens() async => canteens;
  @override
  Future<void> saveCanteens(List<MensaCanteen> value) async => canteens = value;
  @override
  Future<List<MensaAvailableDay>?> readDays(int id) async => days[id];
  @override
  Future<void> saveDays(int id, List<MensaAvailableDay> value) async =>
      days[id] = value;
  @override
  Future<MensaMenuPlan?> readMenu(int id, DateTime date) async =>
      menus[_key(id, date)];
  @override
  Future<void> saveMenu(MensaMenuPlan value) async =>
      menus[_key(value.canteenId, value.date)] = value;
}

void main() {
  test('persists the selected favorite canteen through the repository',
      () async {
    final store = MemoryMensaStore();
    final repo = MensaRepository(
        MensaApi(client: MockClient((_) async => response([], 200))), store);

    await repo.setFavoriteCanteen(9);

    expect(await repo.favoriteCanteenId(), 9);
  });

  test(
      'stores successful menu with timestamp and returns it as stale on refresh failure',
      () async {
    final store = MemoryMensaStore();
    final fetchedAt = DateTime.utc(2026, 11, 11, 8, 45);
    final goodApi = MensaApi(
        client: MockClient((request) async => response([
              {
                'id': 3,
                'name': 'Falafel',
                'category': 'Ausgabe Mitte',
                'notes': ['Menü ist vegan'],
                'prices': {'Studierende': 2.35}
              }
            ], 200)));
    final saved = await MensaRepository(goodApi, store, now: () => fetchedAt)
        .loadMenu(9, DateTime(2026, 11, 11));
    final failedApi = MensaApi(
        client: MockClient((_) async => response({'error': true}, 503)));

    final cached = await MensaRepository(failedApi, store)
        .loadMenu(9, DateTime(2026, 11, 11));

    expect(saved.isStale, isFalse);
    expect(saved.value.fetchedAt, fetchedAt);
    expect(cached.isStale, isTrue);
    expect(cached.value.meals.single.isVegan, isTrue);
    expect(cached.value.fetchedAt, fetchedAt);
  });

  test('does not return another date cache when a menu request fails',
      () async {
    final store = MemoryMensaStore();
    final date = DateTime(2026, 11, 11);
    await store.saveMenu(MensaMenuPlan(
      canteenId: 9,
      date: date,
      meals: const [],
      fetchedAt: DateTime.utc(2026, 11, 11),
    ));
    final api = MensaApi(client: MockClient((_) async => response([], 503)));

    await expectLater(
        MensaRepository(api, store).loadMenu(9, DateTime(2026, 11, 12)),
        throwsA(isA<MensaApiException>()));
  });

  test('uses matching last published days after a refresh failure', () async {
    final store = MemoryMensaStore();
    store.days[9] = [
      MensaAvailableDay(date: DateTime(2026, 11, 10), closed: false),
      MensaAvailableDay(date: DateTime(2026, 11, 14), closed: true),
    ];
    final api = MensaApi(client: MockClient((_) async => response([], 503)));

    final result =
        await MensaRepository(api, store).loadDays(9, DateTime(2026, 11, 11));

    expect(result.isStale, isTrue);
    expect(result.value.map((day) => day.date), [DateTime(2026, 11, 14)]);
    expect(result.value.single.closed, isTrue);
  });

  test('uses cached canteens when the network cannot refresh the list',
      () async {
    final store = MemoryMensaStore();
    store.canteens = [
      const MensaCanteen(
          id: 9, name: 'Siedepunkt', city: 'Dresden', address: 'Adresse')
    ];
    final api = MensaApi(client: MockClient((_) async => response([], 503)));

    final result = await MensaRepository(api, store).loadCanteens();

    expect(result.isStale, isTrue);
    expect(result.value.single.id, 9);
  });
}
