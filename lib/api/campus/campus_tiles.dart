import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import '../api_services.dart';

/// Settle the gesture before requesting its viewport, cancelling the pending
/// timer when the map leaves the tree, including quick navigation away.
final campusTileUpdates =
    StreamTransformer<TileUpdateEvent, TileUpdateEvent>.fromBind((events) {
  Timer? timer;
  StreamSubscription<TileUpdateEvent>? subscription;
  late StreamController<TileUpdateEvent> output;
  output = StreamController<TileUpdateEvent>(onListen: () {
    subscription = events.listen(
        (event) {
          if (event.wasTriggeredByTap()) return;
          timer?.cancel();
          timer =
              Timer(const Duration(milliseconds: 180), () => output.add(event));
        },
        onError: output.addError,
        onDone: () {
          timer?.cancel();
          output.close();
        });
  }, onCancel: () async {
    timer?.cancel();
    await subscription?.cancel();
  });
  return output.stream;
});

/// Only viewport tiles. CacheManager honors Cache-Control and ETag, defaulting
/// to seven days when absent. No seeding, bulk downloads or offline packs.
class CampusTileProvider extends TileProvider {
  static final _cache = CacheManager(Config('campusOsmTilesV1',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1500,
      fileService: HttpFileService()..concurrentFetches = 4));
  static final _limiter = RequestLimiter(4);
  final VoidCallback onFailure;
  CampusTileProvider({required this.onFailure})
      : super(headers: {
          'User-Agent':
              'CampusNavigator/1.2 (+https://github.com/Infinizius/campus-navigator)',
        });

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(TileCoordinates coordinates,
          TileLayer options, Future<void> cancelLoading) =>
      _CampusTileImage(
          getTileUrl(coordinates, options), headers, cancelLoading, onFailure);
}

class _CampusTileImage extends ImageProvider<_CampusTileImage> {
  final String url;
  final Map<String, String> headers;
  final Future<void> cancelLoading;
  final VoidCallback onFailure;
  _CampusTileImage(this.url, this.headers, this.cancelLoading, this.onFailure);

  @override
  Future<_CampusTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _CampusTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    var cancelled = false;
    unawaited(cancelLoading.then((_) => cancelled = true));
    Uint8List? bytes;
    try {
      bytes = await CampusTileProvider._limiter.run(() async {
        if (cancelled) return null;
        final file = await CampusTileProvider._cache
            .getSingleFile(url, headers: headers)
            .timeout(const Duration(seconds: 12));
        return file.readAsBytes();
      });
      if (bytes != null && !cancelled) {
        return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    } catch (_) {
      if (!cancelled) onFailure();
      // Previously viewed stale tiles can still be useful without a connection.
      try {
        final cached = await CampusTileProvider._cache.getFileFromCache(url);
        if (cached != null && !cancelled) {
          return await decode(await ui.ImmutableBuffer.fromUint8List(
              await cached.file.readAsBytes()));
        }
      } catch (_) {/* Transparent fallback retains polygons and controls. */}
    }
    // A cancelled/failed transparent placeholder must not poison ImageCache:
    // revisiting this viewport or pressing retry must actually try the tile.
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
    return decode(
        await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
  }

  @override
  bool operator ==(Object other) =>
      other is _CampusTileImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
