import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'mobibike.dart';

/// Group overlapping marker footprints, capped at a 100 m pairwise distance.
/// Empty stations are useful close up but add noise to the overview.
List<List<BikePlace>> groupBikePlaces(List<BikePlace> places, double zoom) {
  final ordered = places.where((p) => p.available > 0 || zoom >= 16).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  const latitudeStep = 100 / 111320;
  final longitudeStep = latitudeStep / math.cos(51 * math.pi / 180);
  const distance = Distance(roundResult: false);
  final worldSize = 256 * math.pow(2, zoom);
  double projectedY(double latitude) {
    final radians = latitude.clamp(-85.0, 85.0) * math.pi / 180;
    return (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2 *
        worldSize;
  }

  bool overlaps(BikePlace a, BikePlace b) =>
      distance(a.point, b.point) <= 100 &&
      (a.point.longitude - b.point.longitude).abs() / 360 * worldSize <= 40 &&
      (projectedY(a.point.latitude) - projectedY(b.point.latitude)).abs() <= 28;
  final buckets = <String, List<List<BikePlace>>>{};
  final groups = <List<BikePlace>>[];
  for (final place in ordered) {
    final x = (place.point.longitude / longitudeStep).floor();
    final y = (place.point.latitude / latitudeStep).floor();
    List<BikePlace>? match;
    for (var dx = -1; dx <= 1 && match == null; dx++) {
      for (var dy = -1; dy <= 1 && match == null; dy++) {
        for (final group
            in buckets['${x + dx}:${y + dy}'] ?? <List<BikePlace>>[]) {
          if (group.every((p) => overlaps(p, place))) {
            match = group;
            break;
          }
        }
      }
    }
    if (match != null) {
      match.add(place);
    } else {
      final group = [place];
      groups.add(group);
      buckets.putIfAbsent('$x:$y', () => []).add(group);
    }
  }
  return groups;
}
