import 'dart:async';

import 'package:campus_navigator/api/building/room_details.dart';
import 'package:campus_navigator/ui/components/room_details_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lays out in light and dark themes at phone and tablet widths',
      (tester) async {
    final details = RoomDetails.fromJson('325301.0010', {
      'name': '151',
      'doors': <dynamic>[],
    }).withPageDetails(RoomPageDetails.fromHtml('''
      <div id="menu_cont_right"><p>Plätze: 128</p><p>Nutzung: Lecture hall</p></div>
    '''));
    for (final width in [400.0, 1024.0]) {
      tester.view.physicalSize = Size(width * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      for (final theme in [
        ThemeData.light().copyWith(splashFactory: NoSplash.splashFactory),
        ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
      ]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: RoomDetailsView(
              details: details,
              isFavorite: false,
              title: 'Room details · 151',
              placesLabel: 'Places',
              floorLabel: 'Floor',
              buildingLabel: 'Building',
              buildingPartLabel: 'Building part',
              usageLabel: 'Usage',
              remarkLabel: 'Remark',
              doorplateLabel: 'Doorplate unit',
              connectedRoomsLabel: 'Connected rooms',
              favoriteLabel: 'Add to favorites',
              removeFavoriteLabel: 'Remove from favorites',
              onFavoriteChanged: (_) {},
              onOpenRoom: (_) {},
            ),
          ),
        ));
        expect(find.text('128'), findsOneWidget);
        expect(find.text('Lecture hall'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('renders available room facts and favorite control',
      (tester) async {
    final details = RoomDetails.fromJson('325301.0010', {
      'name': '151',
      'doors': <dynamic>[],
      'accessibility': 'opaque',
    }).withPageDetails(RoomPageDetails.fromHtml('''
      <div id="menu_cont_right"><p>Plätze: 128</p><p>Bemerkung: mobile Liege</p></div>
      <p>Org.einheit* (deutsch): Bewirt. Flächen Zentraler Lehrraum</p>
    '''));
    bool? favorite;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: RoomDetailsView(
          details: details,
          isFavorite: false,
          title: 'Room details · 151',
          placesLabel: 'Places',
          floorLabel: 'Floor',
          buildingLabel: 'Building',
          buildingPartLabel: 'Building part',
          usageLabel: 'Usage',
          remarkLabel: 'Remark',
          doorplateLabel: 'Doorplate unit',
          connectedRoomsLabel: 'Connected rooms',
          favoriteLabel: 'Add to favorites',
          removeFavoriteLabel: 'Remove from favorites',
          onFavoriteChanged: (value) => favorite = value,
          onOpenRoom: (_) {},
        ),
      ),
    ));

    expect(find.text('128'), findsOneWidget);
    expect(find.text('mobile Liege'), findsOneWidget);
    expect(find.text('Bewirt. Flächen Zentraler Lehrraum'), findsOneWidget);
    expect(find.text('opaque'), findsNothing);
    await tester.tap(find.byTooltip('Add to favorites'));
    expect(favorite, isTrue);
  });

  testWidgets('shows a retry button on failure and invokes retry',
      (tester) async {
    var retried = false;
    final pending = Completer<RoomDetails>();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: RoomDetailsLoadView(
          future: pending.future,
          loadingLabel: 'Loading',
          errorLabel: 'Could not load details',
          retryLabel: 'Retry',
          onRetry: () => retried = true,
          builder: (_) => const Text('Loaded'),
        ),
      ),
    ));
    pending.completeError(Exception('network'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load details'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
