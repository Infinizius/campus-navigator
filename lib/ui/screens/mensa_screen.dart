import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:maps_launcher/maps_launcher.dart';

import '../../api/mensa/mensa_api.dart';
import '../../api/mensa/mensa_models.dart';
import '../../api/mensa/mensa_repository.dart';

typedef MensaDirections = Future<bool> Function(
    double latitude, double longitude, String label);

class MensaScreen extends StatefulWidget {
  final MensaRepository? repository;
  final MensaApi? api;
  final MensaLocalStore? store;
  final DateTime? today;
  final MensaDirections? launchDirections;

  const MensaScreen({
    super.key,
    this.repository,
    this.api,
    this.store,
    this.today,
    this.launchDirections,
  });

  @override
  State<MensaScreen> createState() => _MensaScreenState();
}

class _MensaScreenState extends State<MensaScreen> {
  late final MensaApi _api = widget.api ?? MensaApi();
  late final MensaRepository _repository = widget.repository ??
      MensaRepository(_api, widget.store ?? const MensaSecureLocalStore());
  late final DateTime _today = _day(widget.today ?? DateTime.now());

  bool _canteensLoading = true;
  bool _canteensFailed = false;
  bool _canteensStale = false;
  List<MensaCanteen> _canteens = const [];
  int? _favoriteId;
  int? _selectedCanteenId;
  List<MensaAvailableDay> _days = const [];
  bool _daysLoading = false;
  bool _daysFailed = false;
  bool _daysStale = false;
  DateTime? _selectedDate;
  bool _menuLoading = false;
  bool _menuFailed = false;
  bool _menuStale = false;
  MensaMenuPlan? _plan;
  bool _vegetarianOnly = false;
  bool _veganOnly = false;
  int _requestVersion = 0;

  AppLocalizations get _l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    unawaited(_initialize());
  }

  @override
  void dispose() {
    if (widget.api == null && widget.repository == null) _api.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _canteensLoading = true;
      _canteensFailed = false;
    });
    try {
      final result = await _repository.loadCanteens();
      final favoriteId = await _repository.favoriteCanteenId();
      if (!mounted) return;
      final selected = result.value.any((canteen) => canteen.id == favoriteId)
          ? favoriteId
          : null;
      setState(() {
        _canteens = result.value;
        _canteensStale = result.isStale;
        _favoriteId = selected == null ? null : favoriteId;
        _selectedCanteenId = selected;
        _canteensLoading = false;
      });
      if (selected != null) await _loadCanteen(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canteensFailed = true;
        _canteensLoading = false;
      });
    }
  }

  Future<void> _chooseCanteen(int? id) async {
    if (id == null || id == _selectedCanteenId) return;
    final isFirstChoice = _favoriteId == null;
    setState(() {
      _selectedCanteenId = id;
      _selectedDate = _today;
      _vegetarianOnly = false;
      _veganOnly = false;
    });
    if (isFirstChoice) {
      try {
        await _repository.setFavoriteCanteen(id);
        if (!mounted) return;
        setState(() => _favoriteId = id);
      } catch (_) {
        _message(_l.mensaFavoriteSaveFailed);
      }
    }
    await _loadCanteen(id);
  }

  Future<void> _saveFavorite() async {
    final id = _selectedCanteenId;
    if (id == null) return;
    try {
      await _repository.setFavoriteCanteen(id);
      if (mounted) {
        setState(() => _favoriteId = id);
        _message(_l.mensaFavoriteSaved);
      }
    } catch (_) {
      _message(_l.mensaFavoriteSaveFailed);
    }
  }

  Future<void> _loadCanteen(int id) async {
    final request = ++_requestVersion;
    setState(() {
      _daysLoading = true;
      _daysFailed = false;
      _days = const [];
      _daysStale = false;
      _menuLoading = false;
      _menuFailed = false;
      _menuStale = false;
      _plan = null;
    });
    try {
      final result = await _repository.loadDays(id, _today);
      if (!mounted || request != _requestVersion) return;
      final days = [...result.value]..sort((a, b) => a.date.compareTo(b.date));
      setState(() {
        _days = days;
        _daysStale = result.isStale;
        _daysLoading = false;
        _selectedDate = _today;
      });
      await _loadMenuFor(_today, request);
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _daysFailed = true;
        _daysLoading = false;
      });
    }
  }

  Future<void> _chooseDate(DateTime? date) async {
    if (date == null || _selectedCanteenId == null) return;
    final request = ++_requestVersion;
    setState(() {
      _selectedDate = _day(date);
      _menuFailed = false;
      _menuStale = false;
      _plan = null;
      _vegetarianOnly = false;
      _veganOnly = false;
    });
    await _loadMenuFor(_day(date), request);
  }

  Future<void> _loadMenuFor(DateTime date, int request) async {
    final id = _selectedCanteenId;
    if (id == null) return;
    final available = _availableDay(date);
    if (available == null || available.closed) {
      setState(() {
        _menuLoading = false;
        _menuFailed = false;
        _plan = null;
      });
      return;
    }
    setState(() {
      _menuLoading = true;
      _menuFailed = false;
      _menuStale = false;
      _plan = null;
    });
    try {
      final result = await _repository.loadMenu(id, date);
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _plan = result.value;
        _menuStale = result.isStale;
        _menuLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _menuFailed = true;
        _menuLoading = false;
      });
    }
  }

  Future<void> _retry() async {
    final id = _selectedCanteenId;
    if (id == null) {
      await _initialize();
    } else if (_daysFailed) {
      await _loadCanteen(id);
    } else {
      final request = ++_requestVersion;
      await _loadMenuFor(_selectedDate ?? _today, request);
    }
  }

  Future<void> _openDirections(MensaCanteen canteen) async {
    final latitude = canteen.latitude;
    final longitude = canteen.longitude;
    if (latitude == null || longitude == null) return;
    try {
      final opened = await (widget.launchDirections
              ?.call(latitude, longitude, canteen.name) ??
          MapsLauncher.launchCoordinates(latitude, longitude, canteen.name));
      if (!opened) _message(_l.mensaDirectionsFailed);
    } catch (_) {
      _message(_l.mensaDirectionsFailed);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  MensaCanteen? get _selectedCanteen {
    for (final canteen in _canteens) {
      if (canteen.id == _selectedCanteenId) return canteen;
    }
    return null;
  }

  MensaAvailableDay? _availableDay(DateTime date) {
    for (final day in _days) {
      if (_sameDate(day.date, date)) return day;
    }
    return null;
  }

  List<DateTime> get _dateOptions {
    final dates = <DateTime>{_today, ..._days.map((day) => _day(day.date))}
        .toList()
      ..sort();
    return dates;
  }

  String _dateLabel(DateTime date) => DateFormat('dd.MM.yyyy').format(date);

  Widget _stateMessage(String text, IconData icon, {bool error = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon,
                size: 20,
                color: error
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ]));

  Widget _retryButton() => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: Text(_l.tryAgain)));

  Widget _canteenSelector() {
    final canteens = [..._canteens]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<int>(
          key: const ValueKey('mensa-canteen-selector'),
          value: _selectedCanteenId,
          isExpanded: true,
          decoration: InputDecoration(labelText: _l.mensaCanteen),
          hint: Text(_l.mensaChooseCanteen),
          items: [
            for (final canteen in canteens)
              DropdownMenuItem(
                value: canteen.id,
                child: Row(children: [
                  Expanded(
                      child: Text(canteen.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(canteen.city,
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
          ],
          onChanged: _canteensLoading ? null : _chooseCanteen,
        ),
      ),
      if (_selectedCanteen != null) ...[
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('mensa-favorite-action'),
          tooltip: _l.mensaFavorite,
          onPressed: _favoriteId == _selectedCanteenId ? null : _saveFavorite,
          icon: Icon(_favoriteId == _selectedCanteenId
              ? Icons.star
              : Icons.star_outline),
        ),
        if (_selectedCanteen!.latitude != null &&
            _selectedCanteen!.longitude != null)
          IconButton(
            key: const ValueKey('mensa-directions-action'),
            tooltip: _l.mensaDirections,
            onPressed: () => _openDirections(_selectedCanteen!),
            icon: const Icon(Icons.directions_outlined),
          ),
      ],
    ]);
  }

  Widget _dateSelector() => DropdownButtonFormField<DateTime>(
        key: const ValueKey('mensa-day-selector'),
        value: _selectedDate ?? _today,
        isExpanded: true,
        decoration: InputDecoration(labelText: _l.mensaDate),
        items: [
          for (final date in _dateOptions)
            DropdownMenuItem(
                value: date,
                child: Text(_dateLabel(date) +
                    (_availableDay(date)?.closed == true
                        ? ' · ${_l.mensaClosed}'
                        : ''))),
        ],
        onChanged: _daysLoading || _daysFailed ? null : _chooseDate,
      );

  Widget _content() {
    if (_canteensLoading) {
      return Column(children: [
        const LinearProgressIndicator(),
        _stateMessage(_l.mensaLoading, Icons.restaurant_outlined),
      ]);
    }
    if (_canteensFailed) {
      return Column(children: [
        _stateMessage(_l.mensaCanteensFailed, Icons.wifi_off, error: true),
        _retryButton(),
      ]);
    }
    if (_canteens.isEmpty) {
      return _stateMessage(_l.mensaCanteensFailed, Icons.error_outline,
          error: true);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_canteensStale) _offlineNotice(_l.mensaOfflineCanteens),
      _canteenSelector(),
      if (_selectedCanteenId == null)
        _stateMessage(_l.mensaChooseFirst, Icons.restaurant_outlined)
      else ...[
        const SizedBox(height: 8),
        _dateSelector(),
        if (_daysLoading)
          Column(children: [
            const LinearProgressIndicator(),
            _stateMessage(_l.mensaLoading, Icons.restaurant_outlined),
          ])
        else if (_daysFailed) ...[
          _stateMessage(_l.mensaDaysFailed, Icons.wifi_off, error: true),
          _retryButton(),
        ] else ...[
          if (_daysStale) _offlineNotice(_l.mensaOfflineDays),
          _menuContent(),
        ],
      ],
    ]);
  }

  Widget _menuContent() {
    final selectedDate = _selectedDate ?? _today;
    final day = _availableDay(selectedDate);
    if (day == null) {
      return _stateMessage(_l.mensaNoPlan, Icons.event_busy_outlined);
    }
    if (day.closed) {
      return _stateMessage(_l.mensaClosed, Icons.event_busy_outlined);
    }
    if (_menuLoading) {
      return Column(children: [
        const LinearProgressIndicator(),
        _stateMessage(_l.mensaLoading, Icons.restaurant_outlined),
      ]);
    }
    if (_menuFailed) {
      return Column(children: [
        _stateMessage(_l.mensaMenuFailed, Icons.wifi_off, error: true),
        _retryButton(),
      ]);
    }
    final plan = _plan;
    if (plan == null || plan.meals.isEmpty) {
      return _stateMessage(_l.mensaNoPlan, Icons.event_busy_outlined);
    }

    final allVegetarian = plan.meals.any((meal) => meal.isVegetarian);
    final allVegan = plan.meals.any((meal) => meal.isVegan);
    final visibleMeals = plan.meals.where((meal) {
      if (_veganOnly) return meal.isVegan;
      if (_vegetarianOnly) return meal.isVegetarian;
      return true;
    }).toList();
    final groups = <String, List<MensaMeal>>{};
    for (final meal in visibleMeals) {
      groups.putIfAbsent(meal.category, () => []).add(meal);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_menuStale)
        _offlineNotice(
            '${_l.mensaOfflineMenu} · ${DateFormat.jm(Localizations.localeOf(context).toString()).format(plan.fetchedAt.toLocal())}'),
      if (allVegetarian || allVegan)
        Wrap(spacing: 8, children: [
          if (allVegetarian)
            FilterChip(
              key: const ValueKey('mensa-filter-vegetarian'),
              label: Text(_l.mensaVegetarian),
              selected: _vegetarianOnly,
              onSelected: (selected) => setState(() {
                _vegetarianOnly = selected;
                if (selected) _veganOnly = false;
              }),
            ),
          if (allVegan)
            FilterChip(
              key: const ValueKey('mensa-filter-vegan'),
              label: Text(_l.mensaVegan),
              selected: _veganOnly,
              onSelected: (selected) => setState(() {
                _veganOnly = selected;
                if (selected) _vegetarianOnly = false;
              }),
            ),
        ]),
      if (visibleMeals.isEmpty)
        _stateMessage(_l.mensaNoMatchingMeals, Icons.filter_alt_off),
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child:
              Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final meal in entry.value) _mealCard(meal),
      ],
    ]);
  }

  Widget _offlineNotice(String message) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              const Icon(Icons.cloud_off_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(message,
                      style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ),
      );

  Widget _mealCard(MensaMeal meal) {
    final locale = Localizations.localeOf(context).toString();
    final currency = NumberFormat.currency(locale: locale, symbol: '€');
    return Card(
      key: ValueKey('mensa-meal-${meal.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(meal.name,
                    style: Theme.of(context).textTheme.titleSmall)),
            if (meal.soldOut) ...[
              const SizedBox(width: 8),
              Text(_l.mensaSoldOut,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
          if (meal.prices.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 4,
                children: meal.prices.entries
                    .map((price) => Text(
                        '${price.key}: ${currency.format(price.value)}',
                        style: Theme.of(context).textTheme.bodyMedium))
                    .toList()),
          ],
          if (meal.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_l.mensaNotes, style: Theme.of(context).textTheme.labelMedium),
            for (final note in meal.notes)
              Text('• $note', style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Scaffold(
      appBar: AppBar(title: Text(l.mensaTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _content(),
          ],
        ),
      ),
    );
  }
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
