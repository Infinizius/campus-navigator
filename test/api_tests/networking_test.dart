import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/networking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../storage_mock.dart';
import '../support/test_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BaseAPIServices keeps injected client cache and storage', () async {
    final cache = await TestCacheManager.create();
    final client = http.Client();
    final storage = StorageMock();
    addTearDown(client.close);
    addTearDown(cache.disposeAndDelete);

    final services = BaseAPIServices(
      client: client,
      cacheManager: cache,
      storage: storage,
    );

    expect(services.client, same(client));
    expect(services.cacheManager, same(cache));
    expect(services.storage, same(storage));
  });

  test('cachedStringRequest uses injected client and caches successful body',
      () async {
    final cache = await TestCacheManager.create();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('<html>fixture</html>', 200);
    });
    final services = BaseAPIServices(
        client: client, cacheManager: cache, storage: StorageMock());
    addTearDown(client.close);
    addTearDown(cache.disposeAndDelete);

    final uri = Uri.parse('$baseURL/fixture');
    expect(await services.cachedStringRequest(uri), '<html>fixture</html>');
    expect(requests.single.url, uri);
    expect(await cache.getFileFromCache(uri.toString()), isNotNull);
  });

  test('cachedStringRequest returns null for non-200 and does not cache',
      () async {
    final cache = await TestCacheManager.create();
    final client = MockClient((_) async => http.Response('error', 503));
    final services = BaseAPIServices(
        client: client, cacheManager: cache, storage: StorageMock());
    addTearDown(client.close);
    addTearDown(cache.disposeAndDelete);
    final uri = Uri.parse('$baseURL/unavailable');

    expect(await services.cachedStringRequest(uri), isNull);
    expect(await cache.getFileFromCache(uri.toString()), isNull);
  });
}
