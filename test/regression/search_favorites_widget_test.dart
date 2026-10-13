import 'dart:async';
import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/ui/screens/building_screen.dart';
import 'package:campus_navigator/ui/screens/search_screen.dart';
import 'package:campus_navigator/ui/search_controller.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/floor_fixture.dart';
import 'saved_places_test.dart' show MemoryPlaces, room, building;

SearchResult results(
        {List<SearchResultObject> rooms = const [],
        List<SearchResultObject> buildings = const []}) =>
    SearchResult(
        assist: '',
        assist2: '',
        resultsBuildings: buildings,
        resultsRooms: rooms,
        moreBuildings: false,
        moreRooms: false,
        trenn: 0);

Widget app(Widget home, {bool dark = false}) => MaterialApp(
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.themeData(
        dark ? AppTheme.darkColorScheme : AppTheme.lightColorScheme),
    home: home);

void main() {
  setUp(() => APIServices.Shared = APIServices.withoutCache());

  testWidgets('empty home fits small phone and landscape tablet in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(320, 640), const Size(1280, 800)]) {
      tester.view.physicalSize = size;
      for (final dark in [false, true]) {
        final store = MemoryPlaces().create();
        await tester.pumpWidget(app(SearchScreen(places: store), dark: dark));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Favoriten'), findsOneWidget);
        expect(find.text('Zuletzt aufgerufen'), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
      'favorite room also in history and same-name other room navigate by ID',
      (tester) async {
    final memory = MemoryPlaces();
    final store = memory.create();
    final a = room('test', 'test.318');
    final b = room('other', 'test.319A');
    await store.toggle(a);
    await store.recordVisit(a);
    await store.recordVisit(b);
    String? opened;
    await tester.pumpWidget(app(SearchScreen(
        places: store,
        loadPlace: (place) async {
          opened = place.identifier;
          return syntheticFloor(id: place.roomId!);
        })));
    await tester.pumpAndSettle();
    expect(tester.takeException(),
        isNull); // Duplicate favorite/history IDs are valid.
    await tester.tap(find.byKey(ValueKey('place-recent-${b.key}')));
    await tester.pumpAndSettle();
    expect(opened, b.identifier);
    final map = tester.widget<BuildingScreen>(find.byType(BuildingScreen));
    expect((await map.room).selectedRoom!.id, b.roomId);
    await tester.tap(find.byKey(ValueKey('favorite-${b.key}')));
    await tester.pumpAndSettle();
    expect(store.contains(b), isTrue);
    expect(find.byTooltip('Favorit entfernen'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('favorite-${b.key}')));
    await tester.pumpAndSettle();
    expect(store.contains(b), isFalse);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(store.recent.first.key, b.key);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('search stars persist across a fresh home, removal also persists',
      (tester) async {
    final memory = MemoryPlaces();
    final store = memory.create();
    final search = RoomSearchController(
        prefetch: false,
        search: (_) async => results(rooms: [
              const SearchResultObject(
                  name: 'BEY 318',
                  subName: null,
                  identifier: 'bey/03/raum/111103.5220')
            ], buildings: [
              const SearchResultObject(
                  name: 'Beyer-Bau',
                  subName: null,
                  identifier: 'dresden/geb/bey')
            ]));
    await tester.pumpWidget(app(SearchScreen(places: store, search: search)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BEY');
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pumpAndSettle();
    expect(find.text('BEY 318'), findsOneWidget);
    expect(find.text('Beyer-Bau'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('favorite-${building.key}')));
    await tester.pumpAndSettle();
    final roomKey = room('bey', '111103.5220').key;
    await tester.tap(find.byKey(ValueKey('favorite-$roomKey')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    search.dispose();
    final restored = memory.create();
    await tester.pumpWidget(app(SearchScreen(places: restored)));
    await tester.pumpAndSettle();
    expect(find.text('BEY 318'), findsOneWidget);
    expect(find.text('Beyer-Bau'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('favorite-${building.key}')));
    await tester.pumpAndSettle();
    final restarted = memory.create();
    await restarted.load();
    expect(restarted.contains(building), isFalse);
    expect(restarted.favorites.single.key, roomKey);
    await tester.pumpWidget(const SizedBox());
    restored.dispose();
    restarted.dispose();
  });

  testWidgets(
      'loading, network error, retry, no results and clear search recover',
      (tester) async {
    final memory = MemoryPlaces();
    final store = memory.create();
    final pending = Completer<SearchResult>();
    var calls = 0;
    final search = RoomSearchController(
        prefetch: false,
        search: (_) {
          calls++;
          if (calls == 1) return pending.future;
          return Future.value(results());
        });
    await tester.pumpWidget(app(SearchScreen(places: store, search: search)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no room');
    await tester.pump(const Duration(milliseconds: 401));
    expect(find.text('Suche läuft …'), findsOneWidget);
    pending.completeError(StateError('network secret must not be displayed'));
    await tester.pumpAndSettle();
    expect(find.text('Suche nicht verfügbar. Bitte Verbindung prüfen.'),
        findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Keine Treffer.'), findsOneWidget);
    await tester.tap(find.byTooltip('Suche leeren'));
    await tester.pumpAndSettle();
    expect(find.text('Favoriten'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    search.dispose();
  });

  testWidgets('failed opening creates no history and a later tap can retry',
      (tester) async {
    final store = MemoryPlaces().create();
    await store.toggle(building);
    var calls = 0;
    await tester.pumpWidget(app(SearchScreen(
        places: store,
        loadPlace: (_) async {
          calls++;
          throw StateError('unavailable');
        })));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(ValueKey('place-favorite-${building.key}')));
      await tester.pumpAndSettle();
    }
    expect(calls, 2);
    expect(store.recent, isEmpty);
    expect(find.byType(BuildingScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('unavailable local storage shows retry and reloads successfully',
      (tester) async {
    final memory = MemoryPlaces()..failRead = true;
    final store = memory.create();
    await tester.pumpWidget(app(SearchScreen(places: store)));
    await tester.pumpAndSettle();
    expect(find.text('Favoriten und Verlauf konnten nicht geladen werden.'),
        findsOneWidget);
    memory.failRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(store.ready, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
