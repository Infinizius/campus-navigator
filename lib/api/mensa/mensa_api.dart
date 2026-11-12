import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mensa_models.dart';

const mensaApiBaseUrl = 'https://api.studentenwerk-dresden.de/openmensa/v2';
const mensaRequestTimeout = Duration(seconds: 20);

class MensaApiException implements Exception {
  final int statusCode;
  final Uri uri;

  const MensaApiException(this.statusCode, this.uri);

  @override
  String toString() => 'Mensa API returned HTTP $statusCode for $uri';
}

/// Read-only client for the official Studentenwerk Dresden OpenMensa API.
class MensaApi {
  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  MensaApi({
    http.Client? client,
    this.baseUrl = mensaApiBaseUrl,
    this.timeout = mensaRequestTimeout,
  }) : _client = client ?? http.Client();

  Future<List<MensaCanteen>> fetchCanteens() async {
    final response = await _get(_uri('canteens'));
    return _decodeList(response, MensaCanteen.fromJson);
  }

  Future<List<MensaAvailableDay>> fetchDays(
      int canteenId, DateTime start) async {
    final response = await _get(_uri('canteens/$canteenId/days', {
      'start': _dateKey(start),
    }));
    return _decodeList(response, MensaAvailableDay.fromJson);
  }

  Future<List<MensaMeal>> fetchMeals(int canteenId, DateTime date) async {
    final response =
        await _get(_uri('canteens/$canteenId/days/${_dateKey(date)}/meals'));
    return _decodeList(response, MensaMeal.fromJson);
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _client.get(uri,
        headers: const {'Accept': 'application/json'}).timeout(timeout);
    if (response.statusCode != 200) {
      throw MensaApiException(response.statusCode, uri);
    }
    return response;
  }

  List<T> _decodeList<T>(http.Response response, T Function(dynamic) parse) {
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('Expected JSON list');
    return List<T>.unmodifiable(decoded.map(parse));
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(root).resolve(path).replace(queryParameters: query);
  }

  void close() => _client.close();
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
