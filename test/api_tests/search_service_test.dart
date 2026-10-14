import 'dart:convert';

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/networking.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../storage_mock.dart';
import '../support/test_cache_manager.dart';

const searchResponse = '{"assist":"","assist2":"","results_geb":[],'
    '"results_raum":[["POT 51 <span class=\'sml\'>(POT/0051/H)</span>",'
    '"pot/raum/0051"]],"more_geb":false,"more_raum":false,"trenn":0}';

String searchCacheKey(String query) {
  final uri = Uri.parse('$baseURL/search');
  final body = {'query': query, 'from': '/', 'geocode': '1'};
  return '${uri.toString()} - ${jsonEncode(body)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestCacheManager cache;
  late List<http.Request> requests;
  late http.Client client;
  late BaseAPIServices services;

  setUp(() async {
    cache = await TestCacheManager.create();
    requests = [];
    client = MockClient((request) async {
      requests.add(request);
      return http.Response(searchResponse, 200);
    });
    services = BaseAPIServices(
      client: client,
      cacheManager: cache,
      storage: StorageMock(),
    );
  });

  tearDown(() async {
    client.close();
    await cache.disposeAndDelete();
  });

  test('cache miss posts exact request and caches valid result', () async {
    final result = await SearchResult.searchRoom('POT 51', services: services);

    expect(result.resultsRooms.single.identifier, 'pot/raum/0051');
    expect(requests, hasLength(1));
    expect(requests.single.url, Uri.parse('$baseURL/search'));
    expect(requests.single.bodyFields, {
      'query': 'POT 51',
      'from': '/',
      'geocode': '1',
    });
    expect(await cache.getFileFromCache(searchCacheKey('POT 51')), isNotNull);
  });

  test('cache hit skips HTTP', () async {
    await cache.putFile(
      searchCacheKey('POT 51'),
      utf8.encode(searchResponse),
      key: searchCacheKey('POT 51'),
      fileExtension: 'json',
    );

    final result = await SearchResult.searchRoom('POT 51', services: services);

    expect(result.resultsRooms.single.identifier, 'pot/raum/0051');
    expect(requests, isEmpty);
  });

  test('non-200 response is not cached', () async {
    client.close();
    client = MockClient((request) async {
      requests.add(request);
      return http.Response('unavailable', 503);
    });
    services = BaseAPIServices(
      client: client,
      cacheManager: cache,
      storage: StorageMock(),
    );

    await expectLater(
      SearchResult.searchRoom('POT 51', services: services),
      throwsException,
    );
    expect(await cache.getFileFromCache(searchCacheKey('POT 51')), isNull);
  });

  test('empty response fails and is not cached', () async {
    client.close();
    client = MockClient((request) async => http.Response('', 200));
    services = BaseAPIServices(
      client: client,
      cacheManager: cache,
      storage: StorageMock(),
    );

    await expectLater(
      SearchResult.searchRoom('POT 51', services: services),
      throwsException,
    );
    expect(await cache.getFileFromCache(searchCacheKey('POT 51')), isNull);
  });

  test('client exception is propagated and not cached', () async {
    client.close();
    client =
        MockClient((request) async => throw http.ClientException('offline'));
    services = BaseAPIServices(
      client: client,
      cacheManager: cache,
      storage: StorageMock(),
    );

    await expectLater(
      SearchResult.searchRoom('POT 51', services: services),
      throwsA(isA<http.ClientException>()),
    );
    expect(await cache.getFileFromCache(searchCacheKey('POT 51')), isNull);
  });
}
