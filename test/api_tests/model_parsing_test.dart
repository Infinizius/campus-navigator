import 'dart:convert';
import 'dart:io';

import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/building/parsing/campus_map.dart';
import 'package:campus_navigator/api/building/parsing/html_data.dart';
import 'package:campus_navigator/api/building/roomOccupancyPlan.dart';
import 'package:campus_navigator/api/login.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search fixture extracts display name and formal subname', () {
    final body = File('test/fixtures/search_results.json').readAsStringSync();
    final result = SearchResult.fromJson(jsonDecode(body));

    expect(result.resultsRooms.single.name, 'POT 51');
    expect(result.resultsRooms.single.subName, 'POT/0051/H');
    expect(result.resultsRooms.single.identifier, 'pot/raum/0051');
  });

  test('login response parses token', () {
    expect(LoginResponse.fromJson({'loginToken': 'token'}).loginToken, 'token');
  });

  test('occupancy fixture parses timetable rows', () {
    final fixture = jsonDecode(
        File('test/fixtures/occupancy_plan.json').readAsStringSync());
    final tables = RoomOccupancyPlan.getTableContentFromBody(fixture['html']);

    expect(tables, [
      [
        ['09:00', 'Lecture']
      ]
    ]);
    expect(RoomOccupancyPlan.tableNames, ['Room occupancy']);
  });

  test('campus fixture maps building identifier and coordinates', () {
    final body = File('test/fixtures/campus_map.html').readAsStringSync();
    final map = CampusMapData.fromHTMLText(body);

    expect(map.buildings, hasLength(1));
    expect(map.buildings.single.shortName, 'APB');
    expect(map.buildings.single.query, 'apb/00');
    expect(map.buildings.single.points, [-2, -2, 2, -2, 2, 2, -2, 2]);
    expect(map.buildings.single.polygonCoords, hasLength(4));
  });

  test('minimal building fixture extracts highlighted room polygon', () {
    final body =
        File('test/fixtures/building_page_minimal.html').readAsStringSync();
    final page =
        BuildingPageData.fromHTMLText(body, ['apb', '00', 'raum', '1']);

    expect(page.pngFileName, 'fixture');
    expect(page.rooms['highlightedRoom'], hasLength(1));
    expect(page.rooms['highlightedRoom']!.single.fill, '#ae0000');
  });

  test('missing HTML script produces a controlled format error', () {
    expect(() => HTMLData.fromBody('<html><body>no data</body></html>'),
        throwsFormatException);
  });

  test('highlight referencing an absent room layer produces a format error',
      () {
    final body = '''<html><body><script type="text/javascript">
var png_file_name = "fixture";
var subpics_size = 256;
var data_canv_width = 256;
var data_canv_height = 256;
raumbezData = {textFill: "#000000", text: []};
ETplan.permahighlightRaum(0, missing);
//${'x' * 1100}
</script></body></html>''';

    expect(() => BuildingPageData.fromHTMLText(body, ['apb', '00']),
        throwsFormatException);
  });
}
