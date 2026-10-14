import 'dart:io';

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/building/room_details.dart';
import 'package:campus_navigator/api/building/room_details_service.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';

import '../apiservice_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('maps the selected floorplan route to its numeric room ID', () {
    expect(
      RoomDetailsService.roomIdFromPageRoute(
          ['pot', '01', 'raum', '325301.0010']),
      '325301.0010',
    );
    expect(
        RoomDetailsService.roomIdFromPageRoute(['pot', '01', 'raum']), isNull);
    expect(
      RoomDetailsService.routeToConnectedRoom(
          ['pot', '01', 'raum', '325301.0010'], '325301.0032'),
      ['pot', '01', 'raum', '325301.0032'],
    );
  });

  late APIServicesMock api;
  late MemoryRoomDetailsCache cache;
  late RoomDetailsService service;
  late String pageFixture;
  late String apiFixture;

  setUp(() async {
    api = APIServicesMock()..storage = _TestStorage();
    cache = MemoryRoomDetailsCache();
    service = RoomDetailsService(api: api, cache: cache);
    pageFixture =
        await File('test/fixtures/room_details/room_325301_0010_en.html')
            .readAsString();
    apiFixture = await File('test/fixtures/room_details/room_325301_0010.json')
        .readAsString();
  });

  test('loads room page and API data for the existing numeric room ID',
      () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    final apiUri = Uri.parse(
        'https://navigator.tu-dresden.de/api/0.1/roominfo/325301.0010');
    when(api.client.get(pageUri))
        .thenAnswer((_) async => http.Response(pageFixture, 200));
    when(api.client.get(apiUri))
        .thenAnswer((_) async => http.Response(apiFixture, 200));

    final details = await service.load('325301.0010', locale: 'en');

    expect(details.roomId, '325301.0010');
    expect(details.name.value, '151');
    expect(details.pageDetails?.places.value, 128);
    expect(details.doors.single.otherRoomFor('325301.0010')?.id, '325301.0032');
    expect(cache.values.keys,
        containsAll([pageUri.toString(), apiUri.toString()]));
    verify(api.client.get(pageUri));
    verify(api.client.get(apiUri));
  });

  test('uses a successful response even if cache reads or writes fail',
      () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    final apiUri = Uri.parse(
        'https://navigator.tu-dresden.de/api/0.1/roominfo/325301.0010');
    cache.readError = StateError('cache read failed');
    cache.failWrites = true;
    when(api.client.get(pageUri))
        .thenAnswer((_) async => http.Response(pageFixture, 200));
    when(api.client.get(apiUri))
        .thenAnswer((_) async => http.Response(apiFixture, 200));

    final details = await service.load('325301.0010', locale: 'en');

    expect(details.name.value, '151');
    expect(details.pageDetails?.places.value, 128);
  });

  test('rejects an invalid room ID before making network requests', () async {
    await expectLater(
      service.load('POT/0151/H', locale: 'en'),
      throwsA(isA<RoomDetailsFormatException>()),
    );

    verifyZeroInteractions(api.client);
  });

  test('reports an HTTP failure with the failing status and URL', () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    when(api.client.get(pageUri))
        .thenAnswer((_) async => http.Response('Unavailable', 503));

    await expectLater(
      service.load('325301.0010', locale: 'en'),
      throwsA(isA<RoomDetailsLoadException>()
          .having((error) => error.statusCode, 'statusCode', 503)
          .having((error) => error.uri, 'uri', pageUri)),
    );
  });

  test('wraps network exceptions with the failing URL and original cause',
      () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    when(api.client.get(pageUri))
        .thenThrow(http.ClientException('offline', pageUri));

    await expectLater(
      service.load('325301.0010', locale: 'en'),
      throwsA(isA<RoomDetailsLoadException>()
          .having((error) => error.uri, 'uri', pageUri)
          .having(
              (error) => error.cause, 'cause', isA<http.ClientException>())),
    );
  });

  test('rejects malformed JSON returned with a successful HTTP status',
      () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    final apiUri = Uri.parse(
        'https://navigator.tu-dresden.de/api/0.1/roominfo/325301.0010');
    when(api.client.get(pageUri))
        .thenAnswer((_) async => http.Response(pageFixture, 200));
    when(api.client.get(apiUri)).thenAnswer(
        (_) async => http.Response('<html>bad payload</html>', 200));

    await expectLater(
      service.load('325301.0010', locale: 'en'),
      throwsA(isA<RoomDetailsFormatException>()),
    );
  });

  test('uses cached room and API responses while offline', () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    final apiUri = Uri.parse(
        'https://navigator.tu-dresden.de/api/0.1/roominfo/325301.0010');
    cache.values[pageUri.toString()] = pageFixture;
    cache.values[apiUri.toString()] = apiFixture;

    final details = await service.load('325301.0010', locale: 'en');

    expect(details.name.value, '151');
    expect(details.pageDetails?.usage.value,
        'Lecture hall with ventilation requirements');
    verifyZeroInteractions(api.client);
  });

  test('falls back to expired cached data when refresh requests fail',
      () async {
    final pageUri = Uri.parse(
        'https://navigator.tu-dresden.de/raum/325301.0010?language=en');
    final apiUri = Uri.parse(
        'https://navigator.tu-dresden.de/api/0.1/roominfo/325301.0010');
    cache.values[pageUri.toString()] = pageFixture;
    cache.values[apiUri.toString()] = apiFixture;
    final expired = DateTime(2020);
    cache.validTill[pageUri.toString()] = expired;
    cache.validTill[apiUri.toString()] = expired;
    when(api.client.get(pageUri))
        .thenThrow(http.ClientException('offline', pageUri));
    when(api.client.get(apiUri))
        .thenThrow(http.ClientException('offline', apiUri));

    final details = await service.load('325301.0010', locale: 'en');

    expect(details.name.value, '151');
    expect(details.pageDetails?.places.value, 128);
    verify(api.client.get(pageUri));
    verify(api.client.get(apiUri));
  });

  test('BaseAPIServices keeps the cache manager supplied by its caller', () {
    final cacheManager = FakeImageCacheManager();
    final service = BaseAPIServices(cacheManager: cacheManager);

    expect(identical(service.cacheManager, cacheManager), isTrue);
  });
}

class FakeImageCacheManager extends Fake implements ImageCacheManager {}

class MemoryRoomDetailsCache implements RoomDetailsCache {
  final Map<String, String> values = {};
  final Map<String, DateTime> validTill = {};
  Object? readError;
  bool failWrites = false;

  @override
  Future<CachedRoomText?> read(String key) async {
    if (readError != null) throw readError!;
    final value = values[key];
    if (value == null) return null;
    return CachedRoomText(
      value: value,
      validTill: validTill[key] ?? DateTime.now().add(const Duration(days: 1)),
    );
  }

  @override
  Future<void> write(String key, String value,
      {required Duration maxAge, required String fileExtension}) async {
    if (failWrites) throw StateError('cache write failed');
    values[key] = value;
    validTill[key] = DateTime.now().add(maxAge);
  }
}

class _TestStorage extends Storage {
  @override
  Future<CacheDuration> getCacheDuration() async => CacheDuration.day;
}
