import 'dart:convert';

class MensaCanteen {
  final int id;
  final String name;
  final String city;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? menuUrl;

  const MensaCanteen({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    this.latitude,
    this.longitude,
    this.menuUrl,
  });

  factory MensaCanteen.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid canteen');
    }
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String || name.trim().isEmpty) {
      throw const FormatException('Invalid canteen identity');
    }
    final coordinates = json['coordinates'];
    double? latitude;
    double? longitude;
    if (coordinates is List && coordinates.length == 2) {
      final lat = _number(coordinates[0]);
      final lon = _number(coordinates[1]);
      if (lat != null &&
          lon != null &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180) {
        latitude = lat;
        longitude = lon;
      }
    }
    return MensaCanteen(
      id: id,
      name: name,
      city: json['city'] is String ? json['city'] as String : '',
      address: json['address'] is String ? json['address'] as String : '',
      latitude: latitude,
      longitude: longitude,
      menuUrl: json['menu'] is String ? json['menu'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'address': address,
        if (latitude != null && longitude != null)
          'coordinates': [latitude, longitude],
        if (menuUrl != null) 'menu': menuUrl,
      };

  static double? _number(dynamic value) =>
      value is num && value.toDouble().isFinite ? value.toDouble() : null;
}

class MensaAvailableDay {
  final DateTime date;
  final bool closed;

  const MensaAvailableDay({required this.date, required this.closed});

  factory MensaAvailableDay.fromJson(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['date'] is! String ||
        json['closed'] is! bool) {
      throw const FormatException('Invalid available day');
    }
    final date = DateTime.tryParse(json['date'] as String);
    if (date == null) throw const FormatException('Invalid available date');
    return MensaAvailableDay(
        date: DateTime(date.year, date.month, date.day),
        closed: json['closed'] as bool);
  }

  Map<String, dynamic> toJson() => {
        'date': _dateKey(date),
        'closed': closed,
      };
}

class MensaMeal {
  final int id;
  final String name;
  final List<String> notes;
  final Map<String, double> prices;
  final bool soldOut;
  final String category;

  const MensaMeal({
    required this.id,
    required this.name,
    required this.notes,
    required this.prices,
    required this.soldOut,
    required this.category,
  });

  factory MensaMeal.fromJson(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['id'] is! int ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        json['category'] is! String) {
      throw const FormatException('Invalid meal');
    }
    final rawNotes = json['notes'] ?? const <dynamic>[];
    if (rawNotes is! List || rawNotes.any((note) => note is! String)) {
      throw const FormatException('Invalid meal notes');
    }
    final rawPrices = json['prices'] ?? const <String, dynamic>{};
    if (rawPrices is! Map) throw const FormatException('Invalid meal prices');
    final prices = <String, double>{};
    for (final entry in rawPrices.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! num || !value.toDouble().isFinite) {
        throw const FormatException('Invalid meal price');
      }
      prices[entry.key as String] = value.toDouble();
    }
    final soldOut = json['soldout'] ?? false;
    if (soldOut is! bool) throw const FormatException('Invalid sold-out flag');
    return MensaMeal(
      id: json['id'] as int,
      name: json['name'] as String,
      notes: List.unmodifiable(rawNotes.cast<String>()),
      prices: Map.unmodifiable(prices),
      soldOut: soldOut,
      category: json['category'] as String,
    );
  }

  bool get isVegan =>
      notes.any((note) => note.trim().toLowerCase() == 'menü ist vegan');
  bool get isVegetarian =>
      isVegan ||
      notes.any((note) => note.trim().toLowerCase() == 'menü ist vegetarisch');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'prices': prices,
        'soldout': soldOut,
        'category': category,
      };
}

class MensaMenuPlan {
  final int canteenId;
  final DateTime date;
  final List<MensaMeal> meals;
  final DateTime fetchedAt;

  const MensaMenuPlan({
    required this.canteenId,
    required this.date,
    required this.meals,
    required this.fetchedAt,
  });

  factory MensaMenuPlan.fromJson(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['canteenId'] is! int ||
        json['date'] is! String ||
        json['fetchedAt'] is! String ||
        json['meals'] is! List) {
      throw const FormatException('Invalid menu snapshot');
    }
    final date = DateTime.tryParse(json['date'] as String);
    final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String);
    if (date == null || fetchedAt == null) {
      throw const FormatException('Invalid menu snapshot date');
    }
    return MensaMenuPlan(
      canteenId: json['canteenId'] as int,
      date: DateTime(date.year, date.month, date.day),
      fetchedAt: fetchedAt,
      meals: List.unmodifiable((json['meals'] as List).map(MensaMeal.fromJson)),
    );
  }

  Map<String, dynamic> toJson() => {
        'canteenId': canteenId,
        'date': _dateKey(date),
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'meals': meals.map((meal) => meal.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
