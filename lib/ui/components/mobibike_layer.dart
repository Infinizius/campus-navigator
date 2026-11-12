import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/mobibike/mobibike.dart';
import '../../api/mobibike/bike_groups.dart';

class MobibikeLayer extends StatefulWidget {
  final bool active;
  final Future<BikeSnapshot> Function()? load;
  final DateTime Function()? now;
  const MobibikeLayer({super.key, required this.active, this.load, this.now});
  @override
  State<MobibikeLayer> createState() => _MobibikeLayerState();
}

class _MobibikeLayerState extends State<MobibikeLayer>
    with WidgetsBindingObserver {
  late final BikeGbfsService _service = BikeGbfsService();
  BikeSnapshot? _snapshot;
  Timer? _timer;
  DateTime? _nextRefresh;
  bool _enabled = false;
  bool _busy = false;
  bool _failed = false;
  bool _foreground = true;
  bool get _active => _enabled && widget.active && _foreground;
  DateTime get _now => (widget.now ?? DateTime.now)();
  AppLocalizations get _l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MobibikeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_active || _busy) return;
    final delay = _nextRefresh?.difference(_now) ?? Duration.zero;
    _timer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
  }

  Future<void> _refresh() async {
    if (!_active || _busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final snapshot = await (widget.load?.call() ?? _service.load());
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _failed = false;
      });
      _nextRefresh = _now.add(snapshot.refreshAfter);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      _nextRefresh =
          _now.add(_snapshot?.refreshAfter ?? const Duration(seconds: 60));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _service.close();
    super.dispose();
  }

  String _timestamp(BikeSnapshot snapshot) =>
      DateFormat('dd.MM.yyyy HH:mm:ss').format(snapshot.updatedAt.toLocal());
  bool get _stale => _failed || (_snapshot?.isStale(_now) ?? false);

  void _details(BikePlace place) {
    final snapshot = _snapshot!;
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text('${place.available} ${_l.mobibikeAvailable}'),
                      Text('${_l.mobibikeUpdated}: ${_timestamp(snapshot)}'),
                      if (_stale) Text(_l.mobibikeStale),
                      Text(_l.mobibikeSource,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (place.rentalUri != null)
                        FilledButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: Text(_l.mobibikeRental),
                            onPressed: () async {
                              var opened = false;
                              try {
                                opened = await launchUrl(place.rentalUri!,
                                    mode: LaunchMode.externalApplication);
                              } catch (_) {/* Display failure below. */}
                              if (!opened && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(_l.mobibikeLinkFailed)));
                              }
                            }),
                    ]))));
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final markerColor = _stale
        ? colors.surfaceContainerHighest
        : dark
            ? const Color(0xff8ddde6)
            : colors.primaryContainer;
    final markerInk = _stale
        ? colors.onSurface
        : dark
            ? const Color(0xff102d32)
            : colors.onPrimaryContainer;
    return Stack(children: [
      if (_enabled && _snapshot != null)
        MarkerLayer(markers: [
          for (final group in groupBikePlaces(_snapshot!.places, camera.zoom))
            Marker(
              point: group.first.point,
              width: 44,
              height: 44,
              child: Tooltip(
                  message: group.length == 1 ? group.first.name : 'MOBIbike',
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (group.length == 1) {
                          _details(group.first);
                        } else if (camera.zoom >= 18) {
                          showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (sheetContext) => SafeArea(
                                      child:
                                          ListView(shrinkWrap: true, children: [
                                    for (final place in group)
                                      ListTile(
                                        leading: const Icon(Icons.pedal_bike),
                                        title: Text(place.name),
                                        subtitle: Text(
                                            '${place.available} ${_l.mobibikeAvailable}'),
                                        onTap: () {
                                          Navigator.pop(sheetContext);
                                          _details(place);
                                        },
                                      ),
                                  ])));
                        } else {
                          MapController.of(context).fitCamera(CameraFit.bounds(
                              bounds: LatLngBounds.fromPoints(
                                  group.map((p) => p.point).toList()),
                              padding: const EdgeInsets.all(64),
                              maxZoom: 18));
                        }
                      },
                      child: Center(
                          child: SizedBox(
                              width: camera.zoom < 15 ? 28 : 36,
                              height: camera.zoom < 15 ? 20 : 24,
                              child: Material(
                                  color: markerColor,
                                  borderRadius: BorderRadius.circular(8),
                                  elevation: 1,
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                            group.length > 1
                                                ? Icons.layers_outlined
                                                : Icons.pedal_bike,
                                            size: camera.zoom < 15 ? 10 : 12,
                                            color: markerInk),
                                        const SizedBox(width: 2),
                                        Text(
                                            '${group.fold<int>(0, (sum, p) => sum + p.available)}',
                                            style: TextStyle(
                                                fontSize:
                                                    camera.zoom < 15 ? 9 : 10,
                                                color: markerInk,
                                                fontWeight: FontWeight.w600)),
                                      ])))))),
            )
        ]),
      Positioned(
          left: 12,
          top: 12,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FilterChip(
                showCheckmark: false,
                key: const ValueKey('mobibike-toggle'),
                label: const Text('MOBIbike'),
                avatar: const Icon(Icons.pedal_bike, size: 18),
                selected: _enabled,
                onSelected: (value) {
                  setState(() => _enabled = value);
                  _schedule();
                }),
            if (_enabled)
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_busy) Text(_l.mobibikeLoading),
                                if (_failed)
                                  Text(_snapshot == null
                                      ? _l.mobibikeFailed
                                      : _l.mobibikeStale),
                                if (!_failed && _stale) Text(_l.mobibikeStale),
                                if (_snapshot != null)
                                  Text(
                                      '${_l.mobibikeUpdated}: ${_timestamp(_snapshot!)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                if (_snapshot != null &&
                                    _snapshot!.places.isEmpty)
                                  Text(_l.mobibikeEmpty),
                                if (_failed)
                                  TextButton(
                                      onPressed: _busy ? null : _refresh,
                                      child: Text(_l.tryAgain)),
                              ])))),
          ])),
    ]);
  }
}
