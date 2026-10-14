import 'dart:convert';
import 'dart:io';

import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/building/room_details.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/ui/components/bottom_sheet_view.dart';
import 'package:campus_navigator/ui/screens/building_screen.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/floor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selected canonical room displays its API room details',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themeData(AppTheme.lightColorScheme),
      home: BuildingScreen(
        room: Future.value(_canonicalSelectedFloor()),
        name: 'APB E069',
        loadRoomDetails: (_, __) async => _roomDetailsFromFixture(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _expandDetails(tester);

    expect(find.text('Raumdetails werden geladen …'), findsNothing);
    expect(find.textContaining('Raumdetails'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room detail favorite is saved to the existing places store',
      (tester) async {
    var savedPlacesDocument = '';
    final places = PlaceStore(
      read: () async =>
          savedPlacesDocument.isEmpty ? null : savedPlacesDocument,
      write: (value) async => savedPlacesDocument = value,
    );
    await places.load();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themeData(AppTheme.lightColorScheme),
      home: BuildingScreen(
        room: Future.value(_canonicalSelectedFloor()),
        name: 'APB E069',
        places: places,
        loadRoomDetails: (_, __) async => _roomDetailsFromFixture(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pump();
    await _expandDetails(tester);

    final detailFavorite = find.byTooltip('Zu Favoriten hinzufügen');
    expect(detailFavorite, findsOneWidget);
    await tester.tap(detailFavorite);
    await tester.pump();
    await tester.pump();

    expect(
      places.contains(SavedPlace(
        kind: PlaceKind.room,
        identifier: 'apb/00/raum/325301.0010',
        name: '151',
      )),
      isTrue,
    );
    expect(savedPlacesDocument, contains('325301.0010'));
    await tester.pumpWidget(const SizedBox());
    places.dispose();
  });
}

BuildingPageData _canonicalSelectedFloor() {
  final baseFloor = syntheticFloor();
  return BuildingPageData(
    selectedRoom:
        SelectedRoom('325301.0010', 'E069', baseFloor.selectedRoom!.polygon),
    htmlData: baseFloor.htmlData,
    raumBezData: baseFloor.raumBezData,
    numberVariables: baseFloor.numberVariables,
    pngFileName: baseFloor.pngFileName,
    rooms: baseFloor.rooms,
    layers: baseFloor.layers,
    subpics: baseFloor.subpics,
    buildingData: baseFloor.buildingData,
    queryParts: const ['apb', '00', 'raum', '325301.0010'],
  );
}

RoomDetails _roomDetailsFromFixture() {
  final page = File('test/fixtures/room_details/room_325301_0010.html')
      .readAsStringSync();
  final json = jsonDecode(
      File('test/fixtures/room_details/room_325301_0010.json')
          .readAsStringSync()) as Map<String, dynamic>;
  return RoomDetails.fromJson('325301.0010', json)
      .withPageDetails(RoomPageDetails.fromHtml(page));
}

Future<void> _expandDetails(WidgetTester tester) async {
  await tester.tap(find.byType(Grabber));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}
