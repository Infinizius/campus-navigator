import 'dart:ui' as ui;
import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:campus_navigator/ui/components/painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/floor_fixture.dart';

void main() {
  setUp(() => APIServices.Shared = APIServices.withoutCache());
  test('room identity overrides a conflicting legacy highlight', () {
    final floor = syntheticFloor();
    expect(floor.selectedRoom!.id, 'test.318');
    expect(floor.selectedRoom!.name, '318');
    expect(floor.selectedRoom!.polygon.points.single.first, 0);
    expect(syntheticFloor(id: 'unknown').rooms['highlightedRoom'], isNull);
    expect(syntheticFloor().raumBezData.text.last.th, 0.01);
  });

  testWidgets('theme and filter snapshots repaint, unchanged inputs do not',
      (tester) async {
    final floor = syntheticFloor();
    MapPainter? previous;
    Future<MapPainter> build(Brightness brightness) async {
      late MapPainter painter;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Builder(builder: (context) {
            painter = MapPainter(roomResult: floor, context: context);
            return CustomPaint(painter: painter);
          })));
      await tester.pumpAndSettle();
      return painter;
    }

    previous = await build(Brightness.light);
    expect((await build(Brightness.light)).shouldRepaint(previous), isFalse);
    final dark = await build(Brightness.dark);
    expect(dark.shouldRepaint(previous), isTrue);
    APIServices.Shared.storage.filterSet.remove(layerFilterOptions.Labeling);
    expect((await build(Brightness.dark)).shouldRepaint(dark), isTrue);
    APIServices.Shared.storage.filterSet = layerFilterOptions.values.toSet();
  });

  test('dark tile transform lifts black strokes and preserves transparency',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 2, 2),
        Paint()
          ..colorFilter = MapPainter.darkTileFilter
          ..color = Colors.black);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    final bytes = (await image.toByteData())!;
    expect(bytes.getUint8(0), greaterThan(220));
    expect(bytes.getUint8(3), 255);
    expect(bytes.getUint8((3 * 4 + 3) * 4 + 3), 0);
    image.dispose();
    picture.dispose();
  });

  test('empty plan bounds and odd point lists are safe', () {
    final floor = syntheticFloor();
    final empty = BuildingPageData(
        htmlData: floor.htmlData,
        raumBezData: floor.raumBezData,
        numberVariables: {},
        pngFileName: '',
        rooms: {},
        layers: [],
        subpics: [],
        buildingData: floor.buildingData,
        queryParts: []);
    expect(planBounds(empty).width, greaterThan(0));
    expect(mapPoints([1, 2, 3]), [const Offset(1, 2)]);
  });
}
