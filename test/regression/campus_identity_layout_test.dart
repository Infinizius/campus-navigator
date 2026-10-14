import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/ui/components/floor_view.dart';
import 'package:campus_navigator/ui/screens/building_screen.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/ui/campus_identity.dart';
import 'package:campus_navigator/ui/screens/search_screen.dart';
import 'package:campus_navigator/ui/search_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'saved_places_test.dart' show MemoryPlaces, room;
import '../support/floor_fixture.dart';

Widget layoutApp(Widget home, {double scale = 1}) => MaterialApp(
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: CampusIdentity.themeData(Brightness.light),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: home);

void main() {
  testWidgets(
      'redundant server room path stays available without repeating in the row',
      (tester) async {
    final places = MemoryPlaces().create();
    await places.toggle(SavedPlace(
        kind: PlaceKind.room,
        identifier: 'apb/00/raum/542100.2860',
        name: 'APB E069',
        subName: 'APB/E069/P'));
    final search = RoomSearchController(prefetch: false);
    await tester
        .pumpWidget(layoutApp(SearchScreen(places: places, search: search)));
    await tester.pumpAndSettle();
    expect(find.text('APB · Etage 00'), findsOneWidget);
    expect(find.byTooltip('APB/E069/P'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    places.dispose();
    search.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('floor keeps its drawing palette and fits at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(layoutApp(
          BuildingScreen(room: Future.value(syntheticFloor()), name: 'BEY/318'),
          scale: scale));
      await tester.pumpAndSettle();
      final floor = tester.element(find.byType(FloorView));
      expect(Theme.of(floor).colorScheme.primary,
          AppTheme.lightColorScheme.primary,
          reason:
              'The Campus UI palette must not alter architectural drawings.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('search action status stays inside a compact phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final places = MemoryPlaces().create();
    final search = RoomSearchController(prefetch: false);
    await tester
        .pumpWidget(layoutApp(SearchScreen(places: places, search: search)));
    await tester.pumpAndSettle();
    for (final badge in find.byType(Badge).evaluate()) {
      final labels = find.descendant(
          of: find.byWidget(badge.widget), matching: find.byType(Text));
      for (final label in labels.evaluate()) {
        expect(tester.getRect(find.byWidget(label.widget)).right,
            lessThanOrEqualTo(320),
            reason: 'Development status must be readable inside the screen.');
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    places.dispose();
    search.dispose();
  });

  testWidgets(
      'many favorites remain scrollable and the final room opens at large text size',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final places = MemoryPlaces().create();
    await places.load();
    for (var index = 0; index < 25; index++) {
      await places.toggle(room('bey', 'room.$index'));
    }
    final search = RoomSearchController(prefetch: false);
    String? opened;
    await tester.pumpWidget(layoutApp(
        SearchScreen(
          places: places,
          search: search,
          loadPlace: (place) {
            opened = place.identifier;
            return Future<BuildingPageData>.error(
                const FormatException('Test transport unavailable'));
          },
        ),
        scale: 2));
    await tester.pumpAndSettle();
    final finalRoom =
        find.byKey(const ValueKey('place-favorite-room:bey:room.24'));
    await tester.scrollUntilVisible(finalRoom, 400,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(finalRoom);
    await tester.pumpAndSettle();
    expect(opened, 'bey/03/raum/room.24');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    places.dispose();
    search.dispose();
  });
}
