import 'dart:convert';

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/freeroom_search/room_links.dart';
import 'package:campus_navigator/api/freeroom_search/search_options.dart';
import 'package:campus_navigator/api/freeroom_search/search_result.dart';
import 'package:campus_navigator/api/networking.dart';

import '../storage.dart';

class FreeRoomLoginRequired implements Exception {
  const FreeRoomLoginRequired();
}

extension FreeroomSearchResult_APIExtension on BaseAPIServices {
  Future<FreeroomSearchResult> searchFreeRooms(
      {required int startWeek,
      required int endWeek,
      required Set<UserUniversity> universities,
      int minCapacity = -1,
      int maxCapacity = -1,
      Repetition repetition = Repetition.once}) async {
    final uri = Uri.parse("$baseURL/huefm/ajax_findfreerooms");

    String type;
    if (universities.length == 2) {
      type = "0";
    } else {
      type = universities.first.toString();
    }

    final response = await client.post(uri, body: {
      "startwoche": startWeek.toString(),
      "endwoche": endWeek.toString(),
      "type": repetition.serialize(),
      "mincapacity": minCapacity.toString(),
      "maxcapacity": maxCapacity.toString(),
      "hochschule": type,
    }).timeout(requestTimeout);

    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 302 ||
        (response.body.trimLeft().startsWith('<') &&
            response.body.toLowerCase().contains('login'))) {
      throw const FreeRoomLoginRequired();
    }
    if (response.statusCode != 200) {
      throw Exception('Free room search returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        (universities.contains(UserUniversity.TUD) &&
            (!decoded.containsKey('rooms') || !decoded.containsKey('taken'))) ||
        (universities.contains(UserUniversity.HTW) &&
            (!decoded.containsKey('htw_rooms') ||
                !decoded.containsKey('htw_taken')))) {
      throw const FormatException('Missing free-room data');
    }
    return FreeroomSearchResult.fromJson(decoded);
  }

  Future<RoomLinks> listBuildingRoomLinks(String building) async {
    final uri = Uri.parse("$baseURL/export/search/$building");

    final responseText = await cachedStringRequest(uri,
        requestFunction: (uri) => client.post(uri), fileExtension: 'json');

    if (responseText == null) {
      throw Exception("brug");
    }

    return RoomLinks.fromJson(jsonDecode(responseText));
  }

  /// Returns the links to all lecture rooms?
  /// Example: roomLink("MER", "MER/0003/U") = ["https://navigator.tu-dresden.de/etplan/mer/00/raum/143100.0280"]
  Future<List<String>> fetchRoomLink(
      String building, String formalRoomName) async {
    final uri =
        Uri.parse("$baseURL/export/findroomurl/$building/$formalRoomName");

    final responseText = await cachedStringRequest(uri,
        requestFunction: (uri) => client.post(uri), fileExtension: 'json');

    if (responseText == null) {
      throw Exception("brug");
    }

    final decoded = jsonDecode(responseText) as Map<String, dynamic>;
    final foundRoom = decoded["foundRoom"] as List<dynamic>;

    return foundRoom.map((e) => e as String).toList();
  }
}
