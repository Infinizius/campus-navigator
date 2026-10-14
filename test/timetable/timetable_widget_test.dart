import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_navigator/api/campus/campus_catalog.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/api/timetable/room_resolver.dart';
import 'package:campus_navigator/api/timetable/timetable_model.dart';
import 'package:campus_navigator/api/timetable/timetable_store.dart';
import 'package:campus_navigator/ui/screens/home_screen.dart';
import 'package:campus_navigator/ui/screens/timetable_screen.dart';
import 'package:campus_navigator/ui/search_controller.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const String calendar = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Campus Navigator//Widget Test//EN
BEGIN:VEVENT
UID:imported
DTSTART:20261014T090000
DTEND:20261014T100000
SUMMARY:Synthetic imported lecture
LOCATION:APB E069
END:VEVENT
END:VCALENDAR
''';

IcsTemporal at(String value) =>
    IcsTemporal(value: value, kind: IcsTemporalKind.floating);

TimetableSeries event(String uid, String title, String value,
        {String location = 'APB E069'}) =>
    TimetableSeries(
      uid: uid,
      summary: title,
      location: location,
      start: at(value),
      end: at(
          '${value.substring(0, 9)}${(int.parse(value.substring(9, 11)) + 1).toString().padLeft(2, '0')}${value.substring(11)}'),
    );

SearchResult response({
  List<SearchResultObject> rooms = const [],
  List<SearchResultObject> buildings = const [],
}) =>
    SearchResult(
      assist: '',
      assist2: '',
      resultsBuildings: buildings,
      resultsRooms: rooms,
      moreBuildings: false,
      moreRooms: false,
      trenn: 0,
    );

SearchResultObject campusRoom() => const SearchResultObject(
      name: 'E069',
      subName: 'APB/EG/raum/E069',
      identifier: 'apb/eg/raum/e069',
      detail: 'APB',
    );

Future<TimetableStore> makeStore(List<TimetableSeries> events) async {
  String? document;
  final store = TimetableStore(
    read: () async => document,
    write: (value) async => document = value,
  );
  await store.load();
  if (events.isNotEmpty) {
    await store.importCalendar(
      ParsedTimetable(series: events),
      TimetableImportMode.replace,
    );
  }
  return store;
}

String tomorrowAtNine() {
  final date = DateTime.now().add(const Duration(days: 1));
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}T090000';
}

PlaceStore makePlaces() => PlaceStore(
      read: () async => null,
      write: (_) async {},
    );

CampusCatalog makeCatalog() => CampusCatalog(
      readCache: () async => null,
      fetch: () async => jsonEncode([
        {
          'krz': 'APB',
          'name': 'Andreas-Pfitzmann-Bau',
          'punkte': [
            [
              {'x': 13.72, 'y': 51.02},
              {'x': 13.73, 'y': 51.02},
              {'x': 13.73, 'y': 51.03}
            ]
          ]
        }
      ]),
      writeCache: (_) async {},
    );

Widget app(Widget home, {bool dark = false}) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themeData(
          dark ? AppTheme.darkColorScheme : AppTheme.lightColorScheme),
      home: home,
    );

Future<void> pumpScreen(
  WidgetTester tester,
  TimetableScreen screen, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app(screen, dark: dark));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home_has_timetable_destination_on_phone_and_rail',
      (tester) async {
    final timetable = await makeStore([]);
    final places = makePlaces();
    final search = RoomSearchController(prefetch: false);
    final catalog = makeCatalog();
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(HomeScreen(
      timetable: timetable,
      catalog: catalog,
      places: places,
      search: search,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Timetable'), findsOneWidget);
    await tester.tap(find.text('Timetable'));
    await tester.pumpAndSettle();
    expect(find.byType(TimetableScreen), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(app(HomeScreen(
      timetable: timetable,
      catalog: catalog,
      places: places,
      search: search,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Timetable')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    timetable.dispose();
    places.dispose();
    search.dispose();
    catalog.dispose();
  });

  testWidgets('search_home_shows_next_event_preview', (tester) async {
    final store = await makeStore([
      event('home-next', 'Home preview event', tomorrowAtNine()),
    ]);
    final home = HomeScreen(
      timetable: store,
      places: makePlaces(),
      search: RoomSearchController(prefetch: false),
      catalog: makeCatalog(),
    );
    await tester.pumpWidget(app(home));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('next-event-preview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('today_and_week_views_show_sorted_events', (tester) async {
    final store = await makeStore([
      event('late', 'Later lecture', '20261014T130000'),
      event('early', 'Earlier lecture', '20261014T090000'),
      event('tomorrow', 'Tomorrow lecture', '20261015T110000'),
    ]);
    await pumpScreen(
      tester,
      TimetableScreen(store: store, clock: () => DateTime(2026, 10, 14, 8)),
    );

    expect(find.text('Earlier lecture'), findsOneWidget);
    expect(find.text('Later lecture'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Earlier lecture')).dy,
      lessThan(tester.getTopLeft(find.text('Later lecture')).dy),
    );
    final tomorrow = find.byKey(const ValueKey('timetable-day-20261015'));
    await tester.ensureVisible(tomorrow);
    await tester.pumpAndSettle();
    await tester.tap(tomorrow);
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow lecture'), findsOneWidget);
    expect(find.text('Earlier lecture'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('import_uses_ics_picker_and_offers_update_or_replace',
      (tester) async {
    final store = await makeStore([]);
    var pickerCalls = 0;
    await pumpScreen(
      tester,
      TimetableScreen(
        store: store,
        clock: () => DateTime(2026, 10, 14, 8),
        pickIcsBytes: () async {
          pickerCalls++;
          return Uint8List.fromList(utf8.encode(calendar));
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('timetable-import')));
    await tester.pumpAndSettle();
    expect(pickerCalls, 1);
    expect(
        find.byKey(const ValueKey('timetable-import-update')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('timetable-import-replace')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timetable-import-replace')));
    await tester.pumpAndSettle();
    expect(store.events.single.uid, 'imported');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('invalid_import_preserves_schedule', (tester) async {
    final store =
        await makeStore([event('kept', 'Saved lecture', '20261014T090000')]);
    await pumpScreen(
      tester,
      TimetableScreen(
        store: store,
        clock: () => DateTime(2026, 10, 14, 8),
        pickIcsBytes: () async => Uint8List.fromList(utf8.encode('not ICS')),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('timetable-import')));
    await tester.pumpAndSettle();
    expect(store.events.single.uid, 'kept');
    expect(
        find.byKey(const ValueKey('timetable-import-replace')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('room_action_opens_verified_place', (tester) async {
    final store = await makeStore([
      event('room', 'Room lecture', '20261014T090000'),
    ]);
    SavedPlace? loaded;
    final resolver = RoomResolver(
      search: (_) async => response(rooms: [campusRoom()]),
    );
    await pumpScreen(
      tester,
      TimetableScreen(
        store: store,
        resolver: resolver,
        clock: () => DateTime(2026, 10, 14, 8),
        loadPlace: (place) async {
          loaded = place;
          throw StateError('synthetic stop after identity handoff');
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('timetable-room-room')));
    await tester.pumpAndSettle();
    expect(loaded?.identifier, 'apb/eg/raum/e069');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('maps_action_uses_verified_building_uri', (tester) async {
    final store = await makeStore([
      event('route', 'Route lecture', '20261014T090000'),
    ]);
    final catalog = makeCatalog();
    Uri? opened;
    await pumpScreen(
      tester,
      TimetableScreen(
        store: store,
        catalog: catalog,
        resolver: RoomResolver(
          search: (_) async => response(rooms: [campusRoom()]),
        ),
        clock: () => DateTime(2026, 10, 14, 8),
        launchRoute: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('timetable-navigate-route')));
    await tester.pumpAndSettle();
    expect(opened?.host, 'www.google.com');
    expect(opened?.queryParameters['travelmode'], 'walking');
    expect(opened?.queryParameters['destination'], isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    catalog.dispose();
  });

  testWidgets('unresolved_room_offers_manual_assignment', (tester) async {
    final store = await makeStore([
      event('manual', 'Manual lecture', '20261014T090000',
          location: 'Room from old timetable'),
    ]);
    await pumpScreen(
      tester,
      TimetableScreen(
        store: store,
        resolver: RoomResolver(
          search: (_) async => response(rooms: [campusRoom()]),
        ),
        clock: () => DateTime(2026, 10, 14, 8),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('timetable-assign-manual')));
    await tester.pumpAndSettle();
    expect(find.text('E069'), findsWidgets);
    await tester.tap(
        find.byKey(const ValueKey('timetable-candidate-apb/eg/raum/e069')));
    await tester.pumpAndSettle();
    expect(store.roomFor('manual', 'Room from old timetable')?.identifier,
        'apb/eg/raum/e069');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('timetable_uses_light_and_dark_theme_tokens', (tester) async {
    final store =
        await makeStore([event('theme', 'Theme lecture', '20261014T090000')]);
    await pumpScreen(
      tester,
      TimetableScreen(store: store, clock: () => DateTime(2026, 10, 14, 8)),
    );
    expect(find.text('Timetable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(
      tester,
      TimetableScreen(store: store, clock: () => DateTime(2026, 10, 14, 8)),
      dark: true,
    );
    expect(find.text('Timetable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
