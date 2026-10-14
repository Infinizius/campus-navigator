import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:campus_navigator/ui/components/painter.dart';
import 'package:flutter/material.dart';

const _warmupFrames = 20;
const _measuredFrames = 240;
const _frameBudgetMicros = 16667;
const _roomCount = 320;

void main() {
  APIServices.Shared = APIServices.withoutCache();
  APIServices.Shared.storage.filterSet = layerFilterOptions.values.toSet();
  runApp(_BenchmarkApp(data: _benchmarkFloor(_roomCount)));
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp({required this.data});

  final BuildingPageData data;

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  final _transformation = ValueNotifier<Matrix4>(Matrix4.identity());
  final _uiMicros = <int>[];
  final _rasterMicros = <int>[];
  Timer? _timer;
  var _running = false;
  var _warmupRemaining = _warmupFrames;
  var _scaleUp = false;
  String _summary = 'Warming up painter benchmark…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _running = true;
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        _scaleUp = !_scaleUp;
        _transformation.value = Matrix4.identity()
          ..scale(_scaleUp ? 1.0001 : 1.0002);
      });
    });
  }

  void _recordTimings(List<ui.FrameTiming> timings) {
    if (!_running) return;
    for (final timing in timings) {
      if (_warmupRemaining > 0) {
        _warmupRemaining--;
        continue;
      }
      _uiMicros.add(timing.buildDuration.inMicroseconds);
      _rasterMicros.add(timing.rasterDuration.inMicroseconds);
      if (_uiMicros.length == _measuredFrames) {
        _finish();
        return;
      }
    }
  }

  void _finish() {
    _running = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_recordTimings);
    final ui = _summaryFor(_uiMicros);
    final raster = _summaryFor(_rasterMicros);
    final slowFrames = List.generate(
            _uiMicros.length,
            (index) =>
                _uiMicros[index] >= _frameBudgetMicros ||
                _rasterMicros[index] >= _frameBudgetMicros)
        .where((slow) => slow)
        .length;
    final result = {
      'benchmark': 'floor-painter-geometry',
      'roomsAndLabels': _roomCount,
      'warmupFrames': _warmupFrames,
      'sampleFrames': _uiMicros.length,
      'frameBudgetMicros': _frameBudgetMicros,
      'uiMicros': ui,
      'rasterMicros': raster,
      'framesOverBudget': slowFrames,
      'limitation': 'synthetic vector workload; no network or tile decoding',
    };
    debugPrint('FLOOR_PAINTER_BENCHMARK ${jsonEncode(result)}');
    setState(
        () => _summary = const JsonEncoder.withIndent('  ').convert(result));
  }

  Map<String, int> _summaryFor(List<int> values) {
    final sorted = List<int>.of(values)..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    int percentile(double fraction) =>
        sorted[((sorted.length - 1) * fraction).ceil()];
    return {
      'mean': (total / sorted.length).round(),
      'p90': percentile(.90),
      'p99': percentile(.99),
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_recordTimings);
    _transformation.dispose();
    widget.data.backgroundImageData?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xff005a8b)),
        home: Scaffold(
          appBar: AppBar(title: const Text('Floor painter benchmark')),
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 380,
                    height: 680,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: MapPainter(
                          roomResult: widget.data,
                          context: context,
                          transformation: _transformation,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_summary,
                    maxLines: 12, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
}

BuildingPageData _benchmarkFloor(int count) {
  const columns = 20;
  const roomWidth = 30;
  const roomHeight = 22;
  final polygons = <List<List<double>>>[];
  final fills = <String>[];
  final labels = <Map<String, Object>>[];

  for (var index = 0; index < count; index++) {
    final column = index % columns;
    final row = index ~/ columns;
    final left = (column * roomWidth).toDouble();
    final top = (row * roomHeight).toDouble();
    polygons.add([
      [left, top, left + 28, top, left + 28, top + 20, left, top + 20]
    ]);
    fills.add(index.isEven ? '#dddddd' : '#d7e2e7');
    labels.add({
      'x': left + 14,
      'y': top + 10,
      'qy': 'R${index + 1}',
      'mx': 27,
      'my': 19,
      'th': .01,
    });
  }

  final rooms = {'points': polygons, 'fills': fills};
  final labelData = {'textFill': '#000000', 'text': labels};
  const width = columns * roomWidth;
  final height = ((count + columns - 1) ~/ columns) * roomHeight;
  final script = '''
var raeumeData = ${jsonEncode(rooms)};
raumbezData = ${jsonEncode(labelData)};
var png_file_name = "PERF00";
var subpics_size = 480;
var data_canv_width = $width;
var data_canv_height = $height;
this.searchhelp = {};
this.raumclick = {};
// ${'synthetic geometry workload ' * 90}
''';
  final body = '''<html><div id="menu_cont"><ul><li>Building</li><li><ul>
<li class="open"><a>00</a><ul><li><a>R1</a></li></ul></li>
</ul></li></ul></div><script type="text/javascript">$script</script></html>''';
  return BuildingPageData.fromHTMLText(body, const ['perf', '00']);
}
