import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../api/building/building_page_data.dart';
import '../../api/campus/campus_building.dart';
import '../../api/campus/campus_catalog.dart';
import '../../api/place_navigation.dart';
import '../../api/saved_places.dart';
import '../../api/search.dart';
import '../../api/timetable/ics_parser.dart';
import '../../api/timetable/ics_time.dart';
import '../../api/timetable/recurrence_expander.dart';
import '../../api/timetable/room_resolver.dart';
import '../../api/timetable/timetable_model.dart';
import '../../api/timetable/timetable_store.dart';
import 'building_screen.dart';

const int maxIcsBytes = 5 * 1024 * 1024;

class _IcsFileTooLarge implements Exception {
  const _IcsFileTooLarge();
}

class TimetableScreen extends StatefulWidget {
  final TimetableStore store;
  final CampusCatalog? catalog;
  final Future<Uint8List?> Function()? pickIcsBytes;
  final Future<BuildingPageData> Function(SavedPlace)? loadPlace;
  final Future<bool> Function(Uri)? launchRoute;
  final RoomResolver? resolver;
  final DateTime Function()? clock;

  const TimetableScreen({
    super.key,
    required this.store,
    this.catalog,
    this.pickIcsBytes,
    this.loadPlace,
    this.launchRoute,
    this.resolver,
    this.clock,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  late final CampusCatalog _catalog = widget.catalog ?? CampusCatalog();
  late final RoomResolver _resolver =
      widget.resolver ?? RoomResolver(search: SearchResult.searchAll);
  final Map<String, Future<RoomResolution>> _resolutions = {};
  late DateTime _selectedDate;
  bool _importing = false;
  bool _openingRoom = false;
  bool _routing = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  AppLocalizations get _l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    initializeTimetableTimeZones();
    final now = tz.TZDateTime.from(
      _now.toUtc(),
      tz.getLocation(campusTimeZoneId),
    );
    _selectedDate = DateTime.utc(now.year, now.month, now.day);
    widget.store.addListener(_changed);
    _catalog.addListener(_changed);
    if (!widget.store.ready) {
      unawaited(Future<void>.microtask(widget.store.load));
    }
    unawaited(_catalog.load());
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    _catalog.removeListener(_changed);
    if (widget.catalog == null) _catalog.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _pickIcsBytes() async {
    if (widget.pickIcsBytes != null) return widget.pickIcsBytes!();
    const type = XTypeGroup(label: 'iCalendar', extensions: ['ics']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return null;
    if (await file.length() > maxIcsBytes) {
      throw const _IcsFileTooLarge();
    }
    return file.readAsBytes();
  }

  Future<void> _importCalendar() async {
    if (_importing || widget.store.saving) return;
    setState(() => _importing = true);
    try {
      final bytes = await _pickIcsBytes();
      if (bytes == null || !mounted) return;
      if (bytes.length > maxIcsBytes) {
        _message(_l.timetableImportTooLarge);
        return;
      }
      final input = utf8.decode(bytes, allowMalformed: false);
      final parsed = parseIcsCalendar(input);
      if (!mounted) return;
      final mode = await showDialog<TimetableImportMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_l.timetableImport),
          content: Text(_l.timetableImportUpdateDescription),
          actions: [
            TextButton(
              key: const ValueKey('timetable-import-update'),
              onPressed: () =>
                  Navigator.pop(context, TimetableImportMode.update),
              child: Text(_l.timetableImportUpdate),
            ),
            FilledButton(
              key: const ValueKey('timetable-import-replace'),
              onPressed: () =>
                  Navigator.pop(context, TimetableImportMode.replace),
              child: Text(_l.timetableImportReplace),
            ),
          ],
        ),
      );
      if (mode == null || !mounted) return;
      final saved = await widget.store.importCalendar(parsed, mode);
      if (!mounted) return;
      if (saved) {
        _resolutions.clear();
        _message(_l.timetableImportSaved);
      } else {
        _message(_l.timetableImportSaveFailed);
      }
    } on _IcsFileTooLarge {
      if (mounted) _message(_l.timetableImportTooLarge);
    } on IcsImportException catch (error) {
      if (!mounted) return;
      if (error.code == IcsImportErrorCode.unsupportedFeature) {
        _message(_l.timetableUnsupportedCalendar);
      } else if (error.code == IcsImportErrorCode.invalidTimezone ||
          error.code == IcsImportErrorCode.unknownTimezone) {
        _message(_l.timetableUnsupportedCalendar);
      } else {
        _message(_l.timetableImportFailed);
      }
    } on FormatException {
      if (mounted) _message(_l.timetableImportFailed);
    } catch (_) {
      if (mounted) _message(_l.timetableImportFailed);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l.timetableClear),
        content: Text(_l.timetableClearDescription),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_l.settingsCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_l.settingsConfirm)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cleared = await widget.store.clear();
    if (mounted) {
      _resolutions.clear();
      _message(cleared ? _l.timetableClearSuccess : _l.timetableClearFailure);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  DateTime _weekStart(DateTime value) => _dateOnly(value)
      .subtract(Duration(days: value.weekday - DateTime.monday));

  List<DateTime> get _daysOfWeek {
    final monday = _weekStart(_selectedDate);
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  String _weekday(int weekday) => switch (weekday) {
        DateTime.monday => _l.weekdayOne,
        DateTime.tuesday => _l.weekdayTwo,
        DateTime.wednesday => _l.weekdayThree,
        DateTime.thursday => _l.weekdayFour,
        DateTime.friday => _l.weekdayFive,
        DateTime.saturday => _l.weekdaySix,
        _ => _l.weekdaySeven,
      };

  List<TimetableOccurrence> _occurrencesFor(DateTime day) {
    final zone = tz.getLocation(campusTimeZoneId);
    final start = tz.TZDateTime(zone, day.year, day.month, day.day);
    final end = tz.TZDateTime(zone, day.year, day.month, day.day + 1);
    return expandTimetable(
      widget.store.events,
      start,
      end,
    );
  }

  DateTime get _today {
    final now = tz.TZDateTime.from(
      _now.toUtc(),
      tz.getLocation(campusTimeZoneId),
    );
    return DateTime.utc(now.year, now.month, now.day);
  }

  Future<RoomResolution> _resolve(String location) {
    final key = normalizeRoomLocation(location);
    return _resolutions.putIfAbsent(key, () => _resolver.resolve(location));
  }

  Widget _daySelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            for (final day in _daysOfWeek)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('timetable-day-${_dateKey(day)}'),
                  selected: _dateOnly(_selectedDate) == day,
                  label: Text(
                      '${_weekday(day.weekday).substring(0, 2)} ${day.day}'),
                  onSelected: (_) => setState(() => _selectedDate = day),
                ),
              ),
          ],
        ),
      );

  Widget _eventCard(TimetableOccurrence occurrence) {
    final time = occurrence.allDay
        ? _l.timetableAllDay
        : '${TimeOfDay.fromDateTime(occurrence.start).format(context)} – '
            '${TimeOfDay.fromDateTime(occurrence.end).format(context)}';
    final location = occurrence.location?.trim();
    return Card(
      key: ValueKey(
          'timetable-event-${occurrence.uid}-${occurrence.recurrenceId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(occurrence.title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(time, style: Theme.of(context).textTheme.bodyMedium),
            if (location != null && location.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(location, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              FutureBuilder<RoomResolution>(
                future: _resolve(location),
                builder: (context, snapshot) => _venueActions(
                  occurrence,
                  snapshot.data,
                  loading: snapshot.connectionState != ConnectionState.done,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(_l.timetableNoLocation,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _venueActions(
    TimetableOccurrence occurrence,
    RoomResolution? resolution, {
    required bool loading,
  }) {
    final location = occurrence.location ?? '';
    final room = widget.store.roomFor(occurrence.uid, location) ??
        (resolution?.status == RoomResolutionStatus.uniqueRoom
            ? resolution!.room
            : null);
    final placeForRoute = room ??
        (resolution?.status == RoomResolutionStatus.buildingOnly
            ? resolution!.building
            : null);
    final feature =
        placeForRoute == null ? null : _buildingFor(placeForRoute.buildingCode);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (room != null)
          OutlinedButton.icon(
            key: ValueKey('timetable-room-${occurrence.uid}'),
            onPressed: _openingRoom ? null : () => _openRoom(room),
            icon: const Icon(Icons.meeting_room_outlined),
            label: Text(_l.timetableRoomAction),
          )
        else
          TextButton.icon(
            key: ValueKey('timetable-assign-${occurrence.uid}'),
            onPressed:
                loading ? null : () => _chooseRoom(occurrence, resolution),
            icon: const Icon(Icons.room_preferences_outlined),
            label: Text(_l.timetableAssignRoom),
          ),
        if (feature?.routeUri != null)
          OutlinedButton.icon(
            key: ValueKey('timetable-navigate-${occurrence.uid}'),
            onPressed: _routing ? null : () => _navigate(feature!.routeUri!),
            icon: const Icon(Icons.directions_walk_outlined),
            label: Text(_l.timetableNavigateAction),
          ),
      ],
    );
  }

  CampusFeature? _buildingFor(String code) {
    for (final building in _catalog.buildings) {
      if (building.floorCode.toLowerCase() == code.toLowerCase()) {
        return building;
      }
    }
    return null;
  }

  Future<void> _openRoom(SavedPlace place) async {
    if (place.kind != PlaceKind.room || _openingRoom) return;
    setState(() => _openingRoom = true);
    try {
      final data = await (widget.loadPlace ?? loadSavedPlace)(place);
      if (!mounted) {
        data.backgroundImageData?.dispose();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => BuildingScreen(
            room: Future.value(data),
            name: place.name,
          ),
        ),
      );
    } catch (_) {
      if (mounted) _message(_l.floorUnavailable);
    } finally {
      if (mounted) setState(() => _openingRoom = false);
    }
  }

  Future<void> _navigate(Uri uri) async {
    if (_routing) return;
    setState(() => _routing = true);
    try {
      final opened = await (widget.launchRoute ??
          ((value) =>
              launchUrl(value, mode: LaunchMode.externalApplication)))(uri);
      if (!opened && mounted) _message(_l.mapRouteAppMissing);
    } catch (_) {
      if (mounted) _message(_l.mapRouteFailed);
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _chooseRoom(
    TimetableOccurrence occurrence,
    RoomResolution? resolution,
  ) async {
    final candidates = (resolution?.candidates ?? const <SavedPlace>[])
        .where((candidate) => candidate.kind == PlaceKind.room)
        .toList();
    if (candidates.isEmpty) {
      _message(_l.timetableRoomUnavailable);
      return;
    }
    final selected = await showModalBottomSheet<SavedPlace>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_l.timetableRoomCandidates,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final candidate in candidates)
              ListTile(
                key: ValueKey('timetable-candidate-${candidate.identifier}'),
                leading: const Icon(Icons.meeting_room_outlined),
                title: Text(candidate.name),
                subtitle: Text(candidate.subName ??
                    '${candidate.buildingCode.toUpperCase()} · ${candidate.floor}'),
                onTap: () => Navigator.pop(context, candidate),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final saved = await widget.store.assignRoom(
      occurrence.uid,
      normalizeRoomLocation(occurrence.location ?? ''),
      selected,
    );
    if (mounted && !saved) _message(_l.timetableImportSaveFailed);
  }

  Widget _body() {
    if (widget.store.loading) {
      return Center(child: Text(_l.timetableLoading));
    }
    if (widget.store.loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_l.timetableLoadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    if (widget.store.events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined,
                  size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(_l.timetableEmptyTitle,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_l.timetableEmptyDescription, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final occurrences = _occurrencesFor(_selectedDate);
    return ListView(
      key: const ValueKey('timetable-events-list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(_l.timetableWeek, style: Theme.of(context).textTheme.titleSmall),
        _daySelector(),
        Text(
          _dateOnly(_selectedDate) == _today
              ? _l.timetableToday
              : MaterialLocalizations.of(context)
                  .formatMediumDate(_selectedDate),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(_l.timetableNoEvents),
          ),
        ...occurrences.map(_eventCard),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_l.timetableTitle),
          actions: [
            IconButton(
              key: const ValueKey('timetable-import'),
              tooltip: _l.timetableImport,
              onPressed:
                  _importing || widget.store.saving ? null : _importCalendar,
              icon: _importing
                  ? const Icon(Icons.hourglass_top)
                  : const Icon(Icons.file_open_outlined),
            ),
            if (widget.store.events.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: _l.timetableClear,
                onSelected: (_) => _clear(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'clear',
                    child: Text(_l.timetableClear),
                  ),
                ],
              ),
          ],
        ),
        body: _body(),
      );
}
