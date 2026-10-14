import 'dart:convert';

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/building/room_details.dart';
import 'package:campus_navigator/api/networking.dart';

abstract interface class RoomDetailsCache {
  Future<CachedRoomText?> read(String key);

  Future<void> write(String key, String value,
      {required Duration maxAge, required String fileExtension});
}

class CachedRoomText {
  final String value;
  final DateTime validTill;

  const CachedRoomText({required this.value, required this.validTill});
}

class RoomDetailsLoadException implements Exception {
  final Uri uri;
  final int? statusCode;
  final Object? cause;

  const RoomDetailsLoadException(
      {required this.uri, this.statusCode, this.cause});

  @override
  String toString() => statusCode == null
      ? 'Unable to load room details from $uri'
      : 'Room details request to $uri failed with HTTP $statusCode';
}

/// Loads the public room page and the room-info API without mixing in
/// authenticated occupancy or schedule data.
class RoomDetailsService {
  final BaseAPIServices api;
  final RoomDetailsCache cache;

  RoomDetailsService({required this.api, required this.cache});

  static String? roomIdFromPageRoute(List<String> queryParts) {
    if (queryParts.isEmpty) return null;
    final id = queryParts.last;
    return RegExp(r'^\d{6}\.\d{4}$').hasMatch(id) ? id : null;
  }

  static List<String> routeToConnectedRoom(
      List<String> queryParts, String destinationRoomId) {
    if (roomIdFromPageRoute([destinationRoomId]) == null ||
        queryParts.isEmpty) {
      throw const RoomDetailsFormatException('Invalid room route');
    }
    return [...queryParts.take(queryParts.length - 1), destinationRoomId];
  }

  Future<RoomDetails> load(String roomId, {required String locale}) async {
    if (!RegExp(r'^\d{6}\.\d{4}$').hasMatch(roomId)) {
      throw const RoomDetailsFormatException('Invalid room ID');
    }

    final pageUri = Uri.parse('$baseURL/raum/$roomId')
        .replace(queryParameters: {'language': locale});
    final apiUri = Uri.parse('$baseURL/api/0.1/roominfo/$roomId');
    final page = await _loadText(pageUri, fileExtension: 'html');
    final jsonText = await _loadText(apiUri, fileExtension: 'json');

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw RoomDetailsFormatException('Invalid room API response: $error');
    }
    if (decoded is! Map) {
      throw const RoomDetailsFormatException(
          'Expected room API response to be an object');
    }

    return RoomDetails.fromJson(roomId, Map<String, dynamic>.from(decoded))
        .withPageDetails(RoomPageDetails.fromHtml(page));
  }

  Future<String> _loadText(Uri uri, {required String fileExtension}) async {
    CachedRoomText? cachedResponse;
    try {
      cachedResponse = await cache.read(uri.toString());
    } catch (_) {
      // A broken cache must not prevent a network refresh.
    }
    final cached =
        cachedResponse != null && cachedResponse.value.trim().isNotEmpty
            ? cachedResponse
            : null;
    if (cached != null &&
        cached.value.isNotEmpty &&
        cached.validTill.isAfter(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await api.client.get(uri);
      if (response.statusCode != 200) {
        if (cached != null && response.statusCode >= 500) return cached.value;
        throw RoomDetailsLoadException(
            uri: uri, statusCode: response.statusCode);
      }
      final text = response.body;
      if (text.isEmpty) {
        if (cached != null) return cached.value;
        throw RoomDetailsFormatException('Empty response from $uri');
      }
      if (fileExtension == 'json') {
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) {
            if (cached != null) return cached.value;
            throw const RoomDetailsFormatException(
                'Expected room API response to be an object');
          }
          try {
            RoomDetails.fromJson(
                uri.pathSegments.last, Map<String, dynamic>.from(decoded));
          } on RoomDetailsFormatException {
            if (cached != null) return cached.value;
            rethrow;
          }
        } on FormatException catch (error) {
          if (cached != null) return cached.value;
          throw RoomDetailsFormatException('Invalid room API response: $error');
        }
      }
      var maxAge = const Duration(days: 1);
      try {
        maxAge = (await api.storage.getCacheDuration()).value;
      } catch (_) {
        // The response can still be used if preferences are unavailable.
      }
      try {
        await cache.write(uri.toString(), text,
            maxAge: maxAge, fileExtension: fileExtension);
      } catch (_) {
        // Cache persistence failure does not invalidate a successful response.
      }
      return text;
    } on RoomDetailsLoadException {
      rethrow;
    } on RoomDetailsFormatException {
      rethrow;
    } catch (error) {
      if (cached != null) return cached.value;
      throw RoomDetailsLoadException(uri: uri, cause: error);
    }
  }
}

class NavigatorRoomDetailsCache implements RoomDetailsCache {
  final BaseAPIServices api;

  const NavigatorRoomDetailsCache(this.api);

  @override
  Future<CachedRoomText?> read(String key) async {
    final file = await api.cacheManager?.getFileFromCache(key);
    if (file == null) return null;
    return CachedRoomText(
        value: await file.file.readAsString(), validTill: file.validTill);
  }

  @override
  Future<void> write(String key, String value,
      {required Duration maxAge, required String fileExtension}) async {
    await api.cacheManager?.putFile(key, utf8.encode(value),
        maxAge: maxAge, fileExtension: fileExtension);
  }
}
