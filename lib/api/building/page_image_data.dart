import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/networking.dart';
import 'package:flutter/foundation.dart';
import 'parsing/layer_data.dart';

class PageImageData with ChangeNotifier {
  final Map<String, ui.Image> imageMap;
  final int qualiStep;
  int height = 0;
  int width = 0;
  int failedImages = 0;
  bool _disposed = false;
  Future<void> loaded = Future.value();

  PageImageData({required this.qualiStep, required this.imageMap});

  ui.Image? getLayerSymbol(String name) => imageMap[name];
  ui.Image? getBackgroundImage(int x, int y) => imageMap['${x}_$y'];

  PageImageData.fetchLevelImages(String pngFileName, List<LayerData> layers,
      List<({int h, int v})> subpics,
      {int qualiIndex = 3})
      : qualiStep = [1, 2, 4, 8][qualiIndex],
        imageMap = {} {
    width = subpics[qualiIndex].h;
    height = subpics[qualiIndex].v;
    final tasks = <String, Uri>{};
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        tasks['${x}_$y'] = Uri.parse(
            '$baseURL/images/etplan_cache/${pngFileName}_$qualiStep/${x}_$y.png/nobase64');
      }
    }
    for (final layer in layers.where((l) => l.symbol.isNotEmpty)) {
      tasks[layer.symbolPNG] = layer.getSymbolUri();
    }
    loaded = _load(tasks.entries.toList());
  }

  Future<void> _load(List<MapEntry<String, Uri>> tasks) async {
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && next < tasks.length) {
        final task = tasks[next++];
        ui.Image? image;
        try {
          image = await APIServices.Shared.fetchImage(task.value);
        } catch (_) {
          // A missing tile must not break the other workers or leak an error.
        }
        if (_disposed) {
          image?.dispose();
          return;
        }
        if (image == null) {
          failedImages++;
        } else {
          imageMap[task.key] = image;
        }
        notifyListeners();
      }
    }

    // Bound downloads/decode work per floor; switching disposes old loaders.
    await Future.wait(List.generate(min(4, tasks.length), (_) => worker()));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in imageMap.values) {
      image.dispose();
    }
    imageMap.clear();
    super.dispose();
  }
}
