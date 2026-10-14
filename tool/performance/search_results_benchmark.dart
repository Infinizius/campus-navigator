import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/ui/screens/search_screen.dart';
import 'package:campus_navigator/ui/search_controller.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

const _roomCount = 648;
const _warmupFrames = 20;
const _measuredFrames = 240;
const _frameBudgetMicros = 16667;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  APIServices.Shared = APIServices.withoutCache();
  final places = PlaceStore(read: () async => null, write: (_) async {});
  await places.load();
  final results = SearchResult(
    assist: '',
    assist2: '',
    resultsBuildings: const [],
    resultsRooms: List.generate(
      _roomCount,
      (index) => SearchResultObject(
        name: 'TEST $index',
        subName: null,
        identifier: 'test/00/raum/room.$index',
      ),
    ),
    moreBuildings: false,
    moreRooms: false,
    trenn: 0,
  );
  final search = RoomSearchController(
      prefetch: false, search: (_) => Future.value(results));
  runApp(_SearchBenchmark(places: places, search: search));
}

class _SearchBenchmark extends StatefulWidget {
  const _SearchBenchmark({required this.places, required this.search});

  final PlaceStore places;
  final RoomSearchController search;

  @override
  State<_SearchBenchmark> createState() => _SearchBenchmarkState();
}

class _SearchBenchmarkState extends State<_SearchBenchmark> {
  final _uiMicros = <int>[];
  final _rasterMicros = <int>[];
  Timer? _timer;
  var _started = false;
  var _finished = false;
  var _timingsCallbackRegistered = false;
  var _warmupRemaining = _warmupFrames;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addTimingsCallback(_recordTimings);
    _timingsCallbackRegistered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.search.change('repeat search', immediately: true);
    });
  }

  void _onSearchChanged() {
    if (_started ||
        _finished ||
        widget.search.result == null ||
        widget.search.loading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        widget.search.change('repeat search', immediately: true);
      });
    });
  }

  void _recordTimings(List<ui.FrameTiming> timings) {
    if (!_started || _finished) return;
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

  void _removeTimingsCallback() {
    if (!_timingsCallbackRegistered) return;
    WidgetsBinding.instance.removeTimingsCallback(_recordTimings);
    _timingsCallbackRegistered = false;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _timer = null;
    _removeTimingsCallback();
    final ui = _summaryFor(_uiMicros);
    final raster = _summaryFor(_rasterMicros);
    final slowFrames = List.generate(
            _uiMicros.length,
            (index) =>
                _uiMicros[index] >= _frameBudgetMicros ||
                _rasterMicros[index] >= _frameBudgetMicros)
        .where((slow) => slow)
        .length;
    debugPrint('SEARCH_RESULTS_BENCHMARK ${jsonEncode({
          'benchmark': 'search-results-rebuild',
          'rooms': _roomCount,
          'warmupFrames': _warmupFrames,
          'sampleFrames': _uiMicros.length,
          'frameBudgetMicros': _frameBudgetMicros,
          'uiMicros': ui,
          'rasterMicros': raster,
          'framesOverBudget': slowFrames,
          'limitation':
              'synthetic local search result; excludes API/network latency',
        })}');
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
    _removeTimingsCallback();
    widget.search.removeListener(_onSearchChanged);
    widget.search.dispose();
    widget.places.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: AppTheme.themeData(AppTheme.lightColorScheme),
        home: SearchScreen(places: widget.places, search: widget.search),
      );
}
