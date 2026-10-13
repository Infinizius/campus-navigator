// Emulator-only QA entry point. Original TU fixtures stay outside app assets.
// Serve data/renderer-fixtures on 127.0.0.1:8765, control with scenario.json.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/building/page_image_data.dart';
import 'package:campus_navigator/ui/components/painter.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'akora_painter.dart' as akora;

const host = 'http://10.0.2.2:8765';
void main() {
  APIServices.Shared = APIServices.withoutCache();
  APIServices.Shared.storage.filterSet = layerFilterOptions.values.toSet();
  runApp(const Preview());
}

class Preview extends StatefulWidget {
  const Preview({super.key});
  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> {
  final transform = TransformationController();
  Timer? timer;
  BuildingPageData? floor;
  Map<String, dynamic> config = {};
  String lastConfig = '';
  String message = 'Waiting for scenario.json';
  bool busy = false;
  bool positioned = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) => refresh());
    refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final response = await http.get(Uri.parse('$host/scenario.json'));
      if (response.body == lastConfig) return;
      final next = jsonDecode(response.body) as Map<String, dynamic>;
      if (next['floor'] != config['floor'] || next['room'] != config['room']) {
        final old = floor;
        setState(() {
          floor = null;
          message = 'Loading original tiles';
        });
        await WidgetsBinding.instance.endOfFrame;
        old?.backgroundImageData?.dispose();
        final name = next['floor'] as String;
        final parts = [name.substring(0, 3), name.substring(3)];
        if (next['room'] != null)
          parts.addAll(['raum', next['room'] as String]);
        final body = await http.get(Uri.parse('$host/$name.html'));
        final data = BuildingPageData.fromHTMLText(body.body, parts);
        final images = PageImageData(qualiStep: 8, imageMap: {})
          ..width = data.subpics[3].h
          ..height = data.subpics[3].v;
        final jobs = <String, String>{};
        for (var x = 0; x < images.width; x++) {
          for (var y = 0; y < images.height; y++) {
            jobs['${x}_$y'] = '${data.pngFileName}_8_${x}_$y.png';
          }
        }
        for (final layer in data.layers.where((l) => l.symbol.isNotEmpty)) {
          jobs[layer.symbolPNG] = layer.symbolPNG;
        }
        final entries = jobs.entries.toList();
        var index = 0;
        Future<void> worker() async {
          while (index < entries.length) {
            final entry = entries[index++];
            final bytes =
                (await http.get(Uri.parse('$host/${entry.value}'))).bodyBytes;
            if (bytes.isEmpty) continue; // Server's empty HTTP-200 tiles.
            final codec = await ui.instantiateImageCodec(bytes);
            images.imageMap[entry.key] = (await codec.getNextFrame()).image;
            codec.dispose();
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        data.backgroundImageData = images;
        floor = data;
      }
      setState(() {
        config = next;
        lastConfig = response.body;
        positioned = false;
        message =
            '${next['floor']} ${next['view']} ${next['dark'] == true ? 'dark' : 'light'} ${next['legacy'] == true ? 'AKORA' : 'renderer'}';
      });
    } catch (error) {
      setState(() => message = 'ERROR: $error');
    } finally {
      busy = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    transform.dispose();
    floor?.backgroundImageData?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData(config['dark'] == true
            ? AppTheme.darkColorScheme
            : AppTheme.lightColorScheme),
        home: Scaffold(
          appBar: AppBar(
              title: Text(message, style: const TextStyle(fontSize: 14))),
          body: floor == null
              ? Center(child: Text(message))
              : LayoutBuilder(builder: (context, constraints) {
                  final data = floor!;
                  final size = constraints.biggest;
                  if (!positioned) {
                    positioned = true;
                    final bounds = planBounds(data);
                    final fit = min(
                        size.width / bounds.width, size.height / bounds.height);
                    final center = config['view'] == 'fit' ||
                            data.selectedRoom == null
                        ? Offset.zero
                        : polygonPath(data.selectedRoom!.polygon.points.single)
                            .getBounds()
                            .center;
                    final zoom = config['view'] == 'fit'
                        ? 1.0
                        : (config['zoom'] as num? ?? 3).toDouble();
                    final point = Offset((size.width - bounds.width * fit) / 2,
                            (size.height - bounds.height * fit) / 2) +
                        (center - bounds.topLeft) * fit;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      transform.value = Matrix4.identity()
                        ..translate(size.width / 2 - point.dx * zoom,
                            size.height / 2 - point.dy * zoom)
                        ..scale(zoom);
                    });
                  }
                  return ClipRect(
                      child: InteractiveViewer(
                    transformationController: transform,
                    minScale: 0.8,
                    maxScale: 16,
                    boundaryMargin: const EdgeInsets.all(300),
                    child: RepaintBoundary(
                        child: CustomPaint(
                      size: size,
                      painter: config['legacy'] == true
                          ? AlignedAkoraPainter(
                              roomResult: data, context: context)
                          : MapPainter(
                              roomResult: data,
                              context: context,
                              transformation: transform),
                    )),
                  ));
                }),
        ),
      );
}

// Compare the original drawing logic in the same coordinate extent/camera.
// Only fit bounds differ from AKORA; no paint/filter/label logic is changed.
class AlignedAkoraPainter extends akora.AkoraMapPainter {
  AlignedAkoraPainter({required super.roomResult, required super.context});
  @override
  Rect calculateDrawingArea() => planBounds(roomResult);
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = calculateDrawingArea();
    final fit = min(size.width / bounds.width, size.height / bounds.height);
    canvas.save();
    canvas.translate((size.width - bounds.width * fit) / 2,
        (size.height - bounds.height * fit) / 2);
    super.paint(canvas, size);
    canvas.restore();
  }
}
