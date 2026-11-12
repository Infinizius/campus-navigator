import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const mobibikeDiscovery =
    'https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_dx/gbfs.json';

class BikePlace {
  final String id;
  final String name;
  final LatLng point;
  final int available;
  final bool station;
  final Uri? rentalUri;
  const BikePlace(this.id, this.name, this.point, this.available, this.station,
      this.rentalUri);
}

class BikeSnapshot {
  final List<BikePlace> places;
  final DateTime updatedAt;
  final Duration refreshAfter;
  const BikeSnapshot(this.places, this.updatedAt, this.refreshAfter);

  bool isStale(DateTime now) =>
      now.difference(updatedAt).inSeconds >
      math.max(300, refreshAfter.inSeconds * 2);

  factory BikeSnapshot.parse(
      Map<String, dynamic> information,
      Map<String, dynamic> status,
      Map<String, dynamic> vehicles,
      DateTime now) {
    final feeds = [information, status, vehicles];
    final timestamps = feeds.map((f) {
      final value = f['last_updated'];
      if (value is! int ||
          value <= 0 ||
          value > now.millisecondsSinceEpoch ~/ 1000 + 60) {
        throw const FormatException('Invalid GBFS timestamp');
      }
      return value;
    }).toList();
    final ttl = feeds.map((f) => f['ttl']).map((v) {
      if (v is! int || v < 0) throw const FormatException('Invalid GBFS TTL');
      return v;
    }).reduce(math.max);
    List<dynamic> rows(Map<String, dynamic> f, String key) {
      final data = f['data'];
      if (data is! Map || data[key] is! List) {
        throw const FormatException('Invalid GBFS data');
      }
      return data[key] as List;
    }

    final states = <String, Map>{};
    for (final row in rows(status, 'stations')) {
      if (row is Map && row['station_id'] is String) {
        states[row['station_id'] as String] = row;
      }
    }
    final places = <String, BikePlace>{};
    for (final row in rows(information, 'stations')) {
      if (row is! Map || row['station_id'] is! String) continue;
      final id = row['station_id'] as String;
      final state = states[id];
      final point = _point(row);
      final count = state?['num_bikes_available'];
      final report = state?['last_reported'];
      if (point == null ||
          state?['is_installed'] != true ||
          state?['is_renting'] != true ||
          count is! int ||
          count < 0 ||
          report is! int ||
          report <= 0 ||
          timestamps[1] - report > 300 ||
          report - timestamps[1] > 60 ||
          row['name'] is! String) continue;
      places['station:$id'] = BikePlace('station:$id', row['name'] as String,
          point, count, true, _rental(row));
    }
    for (final row in rows(vehicles, 'bikes')) {
      if (row is! Map ||
          row['bike_id'] is! String ||
          row['is_reserved'] != false ||
          row['is_disabled'] != false ||
          (row['station_id'] != null && row['station_id'] != '')) continue;
      final point = _point(row);
      if (point == null) continue;
      final id = row['bike_id'] as String;
      places['bike:$id'] =
          BikePlace('bike:$id', 'MOBIbike', point, 1, false, _rental(row));
    }
    return BikeSnapshot(
        List.unmodifiable(places.values),
        DateTime.fromMillisecondsSinceEpoch(timestamps.reduce(math.min) * 1000,
            isUtc: true),
        Duration(seconds: math.max(30, ttl)));
  }
}

LatLng? _point(Map row) {
  final lat = row['lat'];
  final lon = row['lon'];
  if (lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) return null;
  return LatLng(lat.toDouble(), lon.toDouble());
}

Uri? _rental(Map row) {
  final links = row['rental_uris'];
  if (links is! Map) return null;
  for (final key in ['android', 'web']) {
    final value = links[key];
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri != null &&
        uri.scheme == 'https' &&
        ['app.nextbike.net', 'nxtb.it'].contains(uri.host) &&
        uri.userInfo.isEmpty) return uri;
  }
  return null;
}

class BikeGbfsService {
  final http.Client _client;
  final DateTime Function() now;
  BikeGbfsService({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        now = now ?? DateTime.now;

  Future<Map<String, dynamic>> _get(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'gbfs.nextbike.net') {
      throw const FormatException('Invalid GBFS URL');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('GBFS HTTP ${response.statusCode}', uri);
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid GBFS envelope');
    }
    return data;
  }

  Future<BikeSnapshot> load() async {
    final discovery = await _get(Uri.parse(mobibikeDiscovery));
    final data = discovery['data'];
    if (data is! Map) throw const FormatException('Invalid discovery');
    final language = data['de'] ?? data['en'];
    if (language is! Map || language['feeds'] is! List) {
      throw const FormatException('Missing discovery feeds');
    }
    final urls = <String, Uri>{};
    for (final feed in language['feeds'] as List) {
      if (feed is Map && feed['name'] is String && feed['url'] is String) {
        urls[feed['name'] as String] = Uri.parse(feed['url'] as String);
      }
    }
    final names = ['station_information', 'station_status', 'free_bike_status'];
    if (names.any((name) => !urls.containsKey(name))) {
      throw const FormatException('Missing availability feeds');
    }
    final feeds = await Future.wait(names.map((name) => _get(urls[name]!)));
    return BikeSnapshot.parse(feeds[0], feeds[1], feeds[2], now());
  }

  void close() => _client.close();
}
