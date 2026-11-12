import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mensa_api.dart';
import 'mensa_models.dart';

abstract interface class MensaLocalStore {
  Future<int?> readFavoriteCanteenId();
  Future<void> saveFavoriteCanteenId(int? id);
  Future<List<MensaCanteen>?> readCanteens();
  Future<void> saveCanteens(List<MensaCanteen> canteens);
  Future<List<MensaAvailableDay>?> readDays(int canteenId);
  Future<void> saveDays(int canteenId, List<MensaAvailableDay> days);
  Future<MensaMenuPlan?> readMenu(int canteenId, DateTime date);
  Future<void> saveMenu(MensaMenuPlan plan);
}

/// Persists a small public API snapshot and preference locally on device.
class MensaSecureLocalStore implements MensaLocalStore {
  static const favoriteKey = 'mensa.favoriteCanteen';
  static const canteensKey = 'mensa.canteens';
  static const _daysPrefix = 'mensa.days.';
  static const _menuPrefix = 'mensa.menu.';

  final FlutterSecureStorage storage;

  const MensaSecureLocalStore({this.storage = const FlutterSecureStorage()});

  @override
  Future<int?> readFavoriteCanteenId() async =>
      int.tryParse((await storage.read(key: favoriteKey)) ?? '');

  @override
  Future<void> saveFavoriteCanteenId(int? id) =>
      storage.write(key: favoriteKey, value: id?.toString());

  @override
  Future<List<MensaCanteen>?> readCanteens() async {
    final raw = await storage.read(key: canteensKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! List) return null;
      return List.unmodifiable(json.map(MensaCanteen.fromJson));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCanteens(List<MensaCanteen> canteens) => storage.write(
      key: canteensKey,
      value: jsonEncode(canteens.map((canteen) => canteen.toJson()).toList()));

  @override
  Future<List<MensaAvailableDay>?> readDays(int canteenId) async {
    final raw = await storage.read(key: '$_daysPrefix$canteenId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! List) return null;
      return List.unmodifiable(json.map(MensaAvailableDay.fromJson));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveDays(int canteenId, List<MensaAvailableDay> days) =>
      storage.write(
          key: '$_daysPrefix$canteenId',
          value: jsonEncode(days.map((day) => day.toJson()).toList()));

  @override
  Future<MensaMenuPlan?> readMenu(int canteenId, DateTime date) async {
    final raw = await storage.read(key: _menuKey(canteenId, date));
    if (raw == null) return null;
    try {
      final plan = MensaMenuPlan.fromJson(jsonDecode(raw));
      if (plan.canteenId != canteenId || !_sameDate(plan.date, date)) {
        return null;
      }
      return plan;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveMenu(MensaMenuPlan plan) => storage.write(
      key: _menuKey(plan.canteenId, plan.date), value: plan.encode());

  static String _menuKey(int id, DateTime date) =>
      '$_menuPrefix$id.${_dateKey(date)}';
}

class MensaLoad<T> {
  final T value;
  final bool isStale;
  const MensaLoad(this.value, {this.isStale = false});
}

class MensaRepository {
  final MensaApi api;
  final MensaLocalStore store;
  final DateTime Function() now;

  MensaRepository(this.api, this.store, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  Future<int?> favoriteCanteenId() => store.readFavoriteCanteenId();

  Future<void> setFavoriteCanteen(int? id) => store.saveFavoriteCanteenId(id);

  Future<MensaLoad<List<MensaCanteen>>> loadCanteens() async {
    try {
      final canteens = await api.fetchCanteens();
      await _saveBestEffort(() => store.saveCanteens(canteens));
      return MensaLoad(canteens);
    } catch (error, stack) {
      final cached = await _readBestEffort(store.readCanteens);
      if (cached != null) return MensaLoad(cached, isStale: true);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<MensaLoad<List<MensaAvailableDay>>> loadDays(
      int canteenId, DateTime start) async {
    try {
      final days = await api.fetchDays(canteenId, start);
      await _saveBestEffort(() => store.saveDays(canteenId, days));
      return MensaLoad(days);
    } catch (error, stack) {
      final cached = await _readBestEffort(() => store.readDays(canteenId));
      if (cached != null) {
        final from = DateTime(start.year, start.month, start.day);
        return MensaLoad(
          cached
              .where((day) => !day.date.isBefore(from))
              .toList(growable: false),
          isStale: true,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<MensaLoad<MensaMenuPlan>> loadMenu(
      int canteenId, DateTime date) async {
    try {
      final meals = await api.fetchMeals(canteenId, date);
      final plan = MensaMenuPlan(
          canteenId: canteenId,
          date: DateTime(date.year, date.month, date.day),
          meals: meals,
          fetchedAt: now());
      await _saveBestEffort(() => store.saveMenu(plan));
      return MensaLoad(plan);
    } catch (error, stack) {
      final cached =
          await _readBestEffort(() => store.readMenu(canteenId, date));
      if (cached != null) return MensaLoad(cached, isStale: true);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _saveBestEffort(Future<void> Function() save) async {
    try {
      await save();
    } catch (_) {
      // Public data can still be shown if device storage is temporarily unavailable.
    }
  }

  Future<T?> _readBestEffort<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
