import 'package:campus_navigator/api/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum CampusMapThemeMode { automatic, light, dark }

enum AppLanguage {
  german('de', 'Deutsch'),
  english('en', 'English'),
  french('fr', 'Français'),
  spanish('es', 'Español'),
  italian('it', 'Italiano'),
  portuguese('pt', 'Português'),
  polish('pl', 'Polski'),
  russian('ru', 'Русский'),
  turkish('tr', 'Türkçe'),
  arabic('ar', 'العربية'),
  hindi('hi', 'हिन्दी'),
  simplifiedChinese('zh-Hans', '简体中文'),
  japanese('ja', '日本語'),
  korean('ko', '한국어');

  const AppLanguage(this.storageTag, this.nativeName);

  final String storageTag;
  final String nativeName;

  Locale get locale {
    final parts = storageTag.split('-');
    return parts.length == 1
        ? Locale(parts.single)
        : Locale.fromSubtags(languageCode: parts.first, scriptCode: parts.last);
  }

  static List<AppLanguage> get all => values;

  static AppLanguage? fromLocale(Locale locale) {
    for (final language in values) {
      final candidate = language.locale;
      if (candidate.languageCode != locale.languageCode) continue;
      if (candidate.scriptCode == locale.scriptCode) return language;
      // A device may report only `zh`; the one supported Chinese catalog is
      // simplified Chinese, so resolve that locale to zh-Hans.
      if (locale.languageCode == 'zh' &&
          locale.scriptCode == null &&
          candidate.scriptCode == 'Hans') {
        return language;
      }
    }
    return null;
  }
}

/// Minimal persistence surface for the settings controller.
///
/// Production uses the app's existing encrypted local storage. Tests can use
/// an in-memory implementation without platform-channel dependencies.
abstract interface class AppSettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SecureAppSettingsStore implements AppSettingsStore {
  SecureAppSettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? Storage.Shared.storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

/// Owns persistent appearance preferences shared by the settings screen,
/// MaterialApp and the campus basemap.
class AppSettingsController extends ChangeNotifier {
  static const themeModeKey = 'AppThemeMode';
  static const mapThemeModeKey = 'CampusMapThemeMode';
  static const localeKey = 'AppLocale';
  static const fallbackLocale = Locale('en');

  static List<Locale> get supportedLocales =>
      AppLanguage.values.map((language) => language.locale).toList();

  /// Canonicalizes supported device locales and uses English otherwise.
  static Locale resolveLocale(Locale? locale) =>
      AppLanguage.fromLocale(locale ?? fallbackLocale)?.locale ??
      fallbackLocale;

  AppSettingsController({AppSettingsStore? store})
      : _store = store ?? SecureAppSettingsStore();

  final AppSettingsStore _store;
  ThemeMode _themeMode = ThemeMode.system;
  CampusMapThemeMode _campusMapThemeMode = CampusMapThemeMode.automatic;
  Locale? _locale;
  Future<void>? _loadFuture;
  Future<void> _writes = Future<void>.value();
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  CampusMapThemeMode get campusMapThemeMode => _campusMapThemeMode;

  /// `null` follows the device locale; the app's locale resolver supplies the
  /// English fallback for unsupported device languages.
  Locale? get locale => _locale;
  bool get loaded => _loaded;

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() => _reloadFromStore();

  Future<void> _reloadFromStore() async {
    final values = await Future.wait([
      _readSafely(themeModeKey),
      _readSafely(mapThemeModeKey),
      _readSafely(localeKey),
    ]);
    _themeMode = _parseThemeMode(values[0]) ?? ThemeMode.system;
    _campusMapThemeMode =
        _parseMapThemeMode(values[1]) ?? CampusMapThemeMode.automatic;
    _locale = _parseLocale(values[2]);
    _loaded = true;
    notifyListeners();
  }

  Future<String?> _readSafely(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      // Preferences are optional. A broken key must not hide other settings
      // or prevent the app from starting with safe defaults.
      return null;
    }
  }

  ThemeMode? _parseThemeMode(String? value) {
    if (value == null) return null;
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  CampusMapThemeMode? _parseMapThemeMode(String? value) {
    if (value == null) return null;
    for (final mode in CampusMapThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  Locale? _parseLocale(String? value) {
    if (value == null || value == 'system') return null;
    for (final language in AppLanguage.values) {
      if (language.storageTag == value) return language.locale;
    }
    return null;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await load();
    await _enqueueWrite(() => _store.write(themeModeKey, mode.name));
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setCampusMapThemeMode(CampusMapThemeMode mode) async {
    await load();
    await _enqueueWrite(() => _store.write(mapThemeModeKey, mode.name));
    _campusMapThemeMode = mode;
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    final language = locale == null ? null : AppLanguage.fromLocale(locale);
    if (locale != null && language == null) {
      throw ArgumentError.value(locale, 'locale', 'Unsupported app language');
    }
    await load();
    await _enqueueWrite(() => language == null
        ? _store.remove(localeKey)
        : _store.write(localeKey, language.storageTag));
    _locale = language?.locale;
    notifyListeners();
  }

  Future<void> restoreAppearanceDefaults() async {
    await load();
    try {
      await _enqueueWrite(() async {
        await _store.remove(themeModeKey);
        await _store.remove(mapThemeModeKey);
        await _store.remove(localeKey);
      });
    } catch (_) {
      // Some keys may already have been removed. Reflect the values that
      // actually remain in storage before reporting the failure to the UI.
      await _reloadFromStore();
      rethrow;
    }
    _themeMode = ThemeMode.system;
    _campusMapThemeMode = CampusMapThemeMode.automatic;
    _locale = null;
    notifyListeners();
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final operation = _writes.then((_) => write());
    // Keep the queue usable after a failed write while still reporting that
    // failure to the action that initiated it.
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}
