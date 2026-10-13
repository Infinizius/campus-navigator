import 'dart:math';
import 'package:flutter/material.dart';
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'painter.dart';

class FloorView extends StatefulWidget {
  final BuildingPageData data;
  const FloorView({super.key, required this.data});
  @override
  State<FloorView> createState() => _FloorViewState();
}

class _FloorViewState extends State<FloorView> {
  final _transform = TransformationController();
  bool _positioned = false;
  @override
  void didUpdateWidget(FloorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _transform.value = Matrix4.identity();
      _positioned = false;
    }
  }

  void _reset() {
    _positioned = true;
    _transform.value = Matrix4.identity();
  }

  void _positionTarget(Size size) {
    if (_positioned || !size.isFinite) return;
    _positioned = true;
    final target = widget.data.selectedRoom;
    if (target == null || size.width >= 700) return;
    final bounds = planBounds(widget.data);
    final fit = min(size.width / bounds.width, size.height / bounds.height);
    final room = polygonPath(target.polygon.points.single).getBounds();
    final zoom = (90 / (room.width * fit)).clamp(1.0, 3.0);
    final center = Offset((size.width - bounds.width * fit) / 2,
            (size.height - bounds.height * fit) / 2) +
        (room.center - bounds.topLeft) * fit;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transform.value = Matrix4.identity()
        ..translate(size.width / 2 - center.dx * zoom,
            size.height / 2 - center.dy * zoom)
        ..scale(zoom);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    return LayoutBuilder(builder: (context, constraints) {
      _positionTarget(constraints.biggest);
      return Stack(children: [
        Positioned.fill(
            child: ClipRect(
                child: InteractiveViewer(
          transformationController: _transform,
          boundaryMargin: const EdgeInsets.all(120),
          minScale: 0.8,
          maxScale: 16,
          child: RepaintBoundary(
              child: CustomPaint(
                  painter: MapPainter(
                      roomResult: widget.data,
                      context: context,
                      transformation: _transform),
                  size: constraints.biggest)),
        ))),
        Positioned(
            right: 8,
            bottom: 8,
            child: IconButton.filledTonal(
              tooltip: german ? 'Gesamte Etage' : 'Entire floor',
              onPressed: _reset,
              icon: const Icon(Icons.fit_screen),
            )),
        if (widget.data.backgroundImageData != null)
          Positioned(
              left: 8,
              top: 8,
              child: ListenableBuilder(
                listenable: widget.data.backgroundImageData!,
                builder: (context, _) => widget
                            .data.backgroundImageData!.failedImages >
                        0
                    ? Tooltip(
                        message: german
                            ? 'Einige Plankacheln fehlen. Etage erneut öffnen.'
                            : 'Some plan tiles are missing. Reopen this floor.',
                        child: Icon(Icons.cloud_off_outlined,
                            color: Theme.of(context).colorScheme.error))
                    : const SizedBox.shrink(),
              )),
      ]);
    });
  }
}

Widget interactiveFloorView(BuildingPageData data, BuildContext context,
        {Size size = const Size(300, 300)}) =>
    SizedBox.fromSize(size: size, child: FloorView(data: data));

Widget asyncFloorView(Future<BuildingPageData> result,
        {Size size = const Size(300, 300)}) =>
    FutureBuilder<BuildingPageData>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return FloorView(data: snapshot.data!);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );

extension SmallestSquare on Size {
  Size smallestSquare() => Size(shortestSide, shortestSide);
}
