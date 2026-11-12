import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_navigator/api/mensa/mensa_api.dart';
import 'package:campus_navigator/api/mensa/mensa_models.dart';
import 'package:campus_navigator/api/mensa/mensa_repository.dart';
import 'package:campus_navigator/ui/screens/mensa_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

dynamic fixture(String name) =>
    jsonDecode(File('test/fixtures/mensa/$name').readAsStringSync());

http.Response jsonResponse(dynamic value, int status) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class MemoryMensaStore implements MensaLocalStore {
  int? favorite;
  List<MensaCanteen>? canteens;
  List<MensaAvailableDay>? days;
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
  Future<List<MensaAvailableDay>?> readDays(int id) async => days;
  @override
  Future<void> saveDays(int id, List<MensaAvailableDay> value) async =>
      days = value;
  @override
  Future<MensaMenuPlan?> readMenu(int id, DateTime date) async =>
      menus[_key(id, date)];
  @override
  Future<void> saveMenu(MensaMenuPlan value) async =>
      menus[_key(value.canteenId, value.date)] = value;
}

Widget app(MensaScreen screen) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(useMaterial3: true),
      home: screen,
    );

Future<void> pumpMensaFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('first visit asks for a canteen and saves its menu as favorite',
      (tester) async {
    final canteens = fixture('canteens.json');
    final days = fixture('days.json');
    final meals = fixture('meals.json');
    final store = MemoryMensaStore();
    var menuCalls = 0;
    (double, double, String)? requestedDirections;
    final api = MensaApi(client: MockClient((request) async {
      if (request.url.path.endsWith('/canteens')) {
        return jsonResponse(canteens, 200);
      }
      if (request.url.path.endsWith('/days')) return jsonResponse(days, 200);
      if (request.url.path.endsWith('/meals')) {
        menuCalls++;
        return jsonResponse(meals, 200);
      }
      return jsonResponse([], 404);
    }));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
      launchDirections: (latitude, longitude, label) async {
        requestedDirections = (latitude, longitude, label);
        return true;
      },
    )));
    await pumpMensaFrames(tester);

    expect(find.text('Bitte zuerst eine Mensa auswählen.'), findsOneWidget);
    expect(menuCalls, 0);
    await tester.tap(find.byKey(const ValueKey('mensa-canteen-selector')));
    await pumpMensaFrames(tester);
    await tester.tap(find.text('Mensa Siedepunkt').last);
    await pumpMensaFrames(tester);

    expect(store.favorite, 9);
    expect(find.text('Falafelbrätling mit Pommes frites'), findsOneWidget);
    expect(find.textContaining('Studierende'), findsWidgets);
    expect(find.textContaining('Menü ist vegan'), findsOneWidget);
    expect(menuCalls, 1);

    await tester.tap(find.byKey(const ValueKey('mensa-directions-action')));
    await pumpMensaFrames(tester);
    expect(requestedDirections, (
      51.02946063983054,
      13.738727867603302,
      'Mensa Siedepunkt',
    ));
  });

  testWidgets('replaces a favorite missing from the current canteen list',
      (tester) async {
    final store = MemoryMensaStore()..favorite = 999;
    final canteens = fixture('canteens.json');
    final days = fixture('days.json');
    final meals = fixture('meals.json');
    final api = MensaApi(client: MockClient((request) async {
      if (request.url.path.endsWith('/canteens')) {
        return jsonResponse(canteens, 200);
      }
      if (request.url.path.endsWith('/days')) return jsonResponse(days, 200);
      return jsonResponse(meals, 200);
    }));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);
    expect(find.text('Bitte zuerst eine Mensa auswählen.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mensa-canteen-selector')));
    await pumpMensaFrames(tester);
    await tester.tap(find.text('Mensa Siedepunkt').last);
    await pumpMensaFrames(tester);

    expect(store.favorite, 9);
  });

  testWidgets('shows loading while the canteen list request is pending',
      (tester) async {
    final canteensResponse = Completer<http.Response>();
    final api = MensaApi(client: MockClient((request) {
      if (request.url.path.endsWith('/canteens')) {
        return canteensResponse.future;
      }
      return Future.value(jsonResponse([], 200));
    }));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: MemoryMensaStore(),
      today: DateTime(2026, 11, 11),
    )));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    canteensResponse.complete(jsonResponse(fixture('canteens.json'), 200));
    await pumpMensaFrames(tester);
    expect(find.text('Bitte zuerst eine Mensa auswählen.'), findsOneWidget);
  });

  testWidgets('offers only explicitly labeled vegetarian and vegan dishes',
      (tester) async {
    final store = MemoryMensaStore()..favorite = 9;
    final canteens = fixture('canteens.json');
    final days = fixture('days.json');
    final meals = fixture('meals.json');
    final api = MensaApi(
        client: MockClient((request) async => jsonResponse(
            request.url.path.endsWith('/canteens')
                ? canteens
                : request.url.path.endsWith('/days')
                    ? days
                    : meals,
            200)));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);
    expect(
        find.text('Paella mit Wildlachs und Hähnchenfleisch'), findsOneWidget);
    expect(find.text('Falafelbrätling mit Pommes frites'), findsOneWidget);
    expect(find.text('Halloumi-Zucchiniburger'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mensa-filter-vegetarian')));
    await pumpMensaFrames(tester);
    expect(find.text('Paella mit Wildlachs und Hähnchenfleisch'), findsNothing);
    expect(find.text('Falafelbrätling mit Pommes frites'), findsOneWidget);
    expect(find.text('Halloumi-Zucchiniburger'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mensa-filter-vegan')));
    await pumpMensaFrames(tester);
    expect(find.text('Falafelbrätling mit Pommes frites'), findsOneWidget);
    expect(find.text('Halloumi-Zucchiniburger'), findsNothing);
  });

  testWidgets('labels closed dates separately from a missing current plan',
      (tester) async {
    final store = MemoryMensaStore()..favorite = 9;
    final canteens = fixture('canteens.json');
    final days = fixture('days.json');
    final meals = fixture('meals.json');
    var mealCalls = 0;
    final api = MensaApi(client: MockClient((request) async {
      if (request.url.path.endsWith('/canteens')) {
        return jsonResponse(canteens, 200);
      }
      if (request.url.path.endsWith('/days')) return jsonResponse(days, 200);
      if (request.url.path.endsWith('/meals')) {
        mealCalls++;
        return jsonResponse(meals, 200);
      }
      return jsonResponse([], 404);
    }));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);
    expect(mealCalls, 1);

    await tester.tap(find.byKey(const ValueKey('mensa-day-selector')));
    await pumpMensaFrames(tester);
    await tester.tap(find.textContaining('14.11.2026').last);
    await pumpMensaFrames(tester);
    expect(find.text('Diese Mensa ist an diesem Tag geschlossen.'),
        findsOneWidget);
    expect(mealCalls, 1);
  });

  testWidgets('shows no-plan when the API omits today from available days',
      (tester) async {
    final store = MemoryMensaStore()..favorite = 9;
    final canteens = fixture('canteens.json');
    final api = MensaApi(
        client: MockClient((request) async => jsonResponse(
            request.url.path.endsWith('/canteens') ? canteens : [], 200)));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);

    expect(find.text('Für diesen Tag ist kein Speiseplan verfügbar.'),
        findsOneWidget);
  });

  testWidgets('retries a failed available-days request', (tester) async {
    final store = MemoryMensaStore()..favorite = 9;
    final canteens = fixture('canteens.json');
    final days = fixture('days.json');
    var dayCalls = 0;
    final api = MensaApi(client: MockClient((request) async {
      if (request.url.path.endsWith('/canteens')) {
        return jsonResponse(canteens, 200);
      }
      if (request.url.path.endsWith('/days')) {
        dayCalls++;
        return jsonResponse(dayCalls == 1 ? {'error': 'unavailable'} : days,
            dayCalls == 1 ? 503 : 200);
      }
      return jsonResponse(fixture('meals.json'), 200);
    }));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);
    expect(find.text('Verfügbare Tage konnten nicht geladen werden.'),
        findsOneWidget);

    await tester.tap(find.text('Erneut versuchen'));
    await pumpMensaFrames(tester);
    expect(dayCalls, 2);
    expect(find.text('Falafelbrätling mit Pommes frites'), findsOneWidget);
  });

  testWidgets('shows the cached retrieval time after an offline refresh',
      (tester) async {
    final store = MemoryMensaStore()
      ..favorite = 9
      ..canteens = [
        const MensaCanteen(
            id: 9,
            name: 'Mensa Siedepunkt',
            city: 'Dresden',
            address: 'Adresse')
      ]
      ..days = [MensaAvailableDay(date: DateTime(2026, 11, 11), closed: false)];
    store.menus['9_2026-11-11'] = MensaMenuPlan(
      canteenId: 9,
      date: DateTime(2026, 11, 11),
      meals: [
        const MensaMeal(
            id: 1,
            name: 'Linsengericht',
            notes: [],
            prices: {},
            soldOut: false,
            category: 'Ausgabe')
      ],
      fetchedAt: DateTime(2026, 11, 11, 8, 45),
    );
    final api =
        MensaApi(client: MockClient((_) async => jsonResponse({}, 503)));

    await tester.pumpWidget(app(MensaScreen(
      api: api,
      store: store,
      today: DateTime(2026, 11, 11),
    )));
    await pumpMensaFrames(tester);

    expect(find.text('Linsengericht'), findsOneWidget);
    expect(find.textContaining('08:45'), findsOneWidget);
    expect(find.textContaining('Offline: gespeicherter Speiseplan'),
        findsOneWidget);
  });
}
