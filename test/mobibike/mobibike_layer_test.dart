import 'package:campus_navigator/api/mobibike/mobibike.dart';
import 'package:campus_navigator/ui/components/mobibike_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../regression/search_favorites_widget_test.dart' show app;

void main() {
  testWidgets('failed refresh keeps markers visibly stale and retry recovers',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    var now = DateTime.now();
    final snapshot = BikeSnapshot([
      const BikePlace(
          'bike:retained', 'MOBIbike', LatLng(51.03, 13.73), 1, false, null)
    ], now, const Duration(seconds: 60));
    await tester.pumpWidget(app(Material(
        child: FlutterMap(
            options: const MapOptions(
                initialCenter: LatLng(51.03, 13.73), initialZoom: 17),
            children: [
          MobibikeLayer(
              active: true,
              now: () => now,
              load: () async {
                calls++;
                if (calls == 2) throw Exception('offline');
                return snapshot;
              })
        ]))));
    await tester.tap(find.byKey(const ValueKey('mobibike-toggle')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('1'), findsOneWidget);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    expect(find.textContaining('Veraltete Daten'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pump();
    expect(calls, 3);
    expect(find.textContaining('Veraltete Daten'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opt-in layer respects TTL and pauses while map is inactive',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    var active = true;
    var now = DateTime.now();
    late StateSetter rebuild;
    final snapshot = BikeSnapshot([
      const BikePlace(
          'bike:1', 'MOBIbike', LatLng(51.03, 13.73), 1, false, null)
    ], DateTime.now(), const Duration(seconds: 60));
    await tester.pumpWidget(app(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return Material(
          child: FlutterMap(
              options: const MapOptions(initialCenter: LatLng(51.03, 13.73)),
              children: [
            MobibikeLayer(
                active: active,
                now: () => now,
                load: () async {
                  calls++;
                  return snapshot;
                })
          ]));
    })));
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('mobibike-toggle')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    rebuild(() => active = false);
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
    now = now.add(const Duration(minutes: 3));
    rebuild(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(minutes: 3));
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox());
  });
}
