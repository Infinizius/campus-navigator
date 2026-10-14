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

enum _TimetableViewMode { calendar, upcoming }

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
  final PlaceStore? places;

  const TimetableScreen({
    super.key,
    required this.store,
    this.catalog,
    this.pickIcsBytes,
    this.loadPlace,
    this.launchRoute,
    this.resolver,
    this.clock,
    this.places,
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
  _TimetableViewMode _viewMode = _TimetableViewMode.calendar;
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

  DateTime _monthGridStart(DateTime month) {
    final firstDay = DateTime.utc(month.year, month.month);
    return firstDay
        .subtract(Duration(days: firstDay.weekday - DateTime.monday));
  }

  void _changeMonth(int amount) {
    final month = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month + amount,
    );
    final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
    setState(() {
      _selectedDate = DateTime.utc(
        month.year,
        month.month,
        _selectedDate.day.clamp(1, lastDay),
      );
    });
  }

  void _goToToday() => setState(() => _selectedDate = _today);

  List<TimetableOccurrence> _occurrencesInCampusRange(
    DateTime firstDay,
    int dayCount,
  ) {
    final zone = tz.getLocation(campusTimeZoneId);
    final lastExclusive = firstDay.add(Duration(days: dayCount));
    final start =
        tz.TZDateTime(zone, firstDay.year, firstDay.month, firstDay.day);
    final end = tz.TZDateTime(
      zone,
      lastExclusive.year,
      lastExclusive.month,
      lastExclusive.day,
    );
    return expandTimetable(
      widget.store.events,
      start,
      end,
    );
  }

  DateTime get _today {
    final now = _nowInCampus;
    return DateTime.utc(now.year, now.month, now.day);
  }

  tz.TZDateTime get _nowInCampus => tz.TZDateTime.from(
        _now.toUtc(),
        tz.getLocation(campusTimeZoneId),
      );

  Map<String, List<TimetableOccurrence>> _groupByCampusDay(
    Iterable<TimetableOccurrence> occurrences,
  ) {
    final zone = tz.getLocation(campusTimeZoneId);
    final grouped = <String, List<TimetableOccurrence>>{};
    for (final occurrence in occurrences) {
      final campusStart = occurrence.allDay
          ? occurrence.start
          : tz.TZDateTime.from(occurrence.start.toUtc(), zone);
      final key = _dateKey(_dateOnly(campusStart));
      grouped.putIfAbsent(key, () => []).add(occurrence);
    }
    return grouped;
  }

  Future<RoomResolution> _resolve(String location) {
    final key = normalizeRoomLocation(location);
    return _resolutions.putIfAbsent(key, () => _resolver.resolve(location));
  }

  Widget _viewSelector() => Center(
        child: SegmentedButton<_TimetableViewMode>(
          segments: [
            ButtonSegment(
              value: _TimetableViewMode.calendar,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_l.timetableCalendar),
            ),
            ButtonSegment(
              value: _TimetableViewMode.upcoming,
              icon: const Icon(Icons.view_agenda_outlined),
              label: Text(_l.timetableUpcoming),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (selection) =>
              setState(() => _viewMode = selection.first),
        ),
      );

  Widget _monthCalendarHeader() {
    final localizations = MaterialLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          key: const ValueKey('timetable-month-previous'),
          tooltip: localizations.previousMonthTooltip,
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            localizations.formatMonthYear(_selectedDate),
            key: const ValueKey('timetable-month-heading'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          key: const ValueKey('timetable-go-today'),
          onPressed: _goToToday,
          child: Text(_l.timetableToday),
        ),
        IconButton(
          key: const ValueKey('timetable-month-next'),
          tooltip: localizations.nextMonthTooltip,
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _calendarDayCell(
    DateTime day,
    Map<String, List<TimetableOccurrence>> eventsByDay,
  ) {
    final colors = Theme.of(context).colorScheme;
    final key = _dateKey(day);
    final events = eventsByDay[key] ?? const <TimetableOccurrence>[];
    final selected = _dateOnly(_selectedDate) == day;
    final today = _today == day;
    final inMonth = day.month == _selectedDate.month;
    final foreground = inMonth ? colors.onSurface : colors.onSurfaceVariant;
    final markers = <Widget>[
      for (var index = 0; index < events.length.clamp(0, 3); index++)
        Container(
          key: index == 0 ? ValueKey('timetable-day-mark-$key') : null,
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: selected ? colors.onPrimaryContainer : colors.primary,
            shape: BoxShape.circle,
          ),
        ),
      if (events.length > 3)
        Text(
          '+${events.length - 3}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: selected ? colors.onPrimaryContainer : colors.primary,
              ),
        ),
    ];
    return Semantics(
      button: true,
      selected: selected,
      label: '${MaterialLocalizations.of(context).formatFullDate(day)}, '
          '${_l.timetableEventCount(events.length)}',
      child: InkWell(
        key: ValueKey('timetable-day-$key'),
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _selectedDate = day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 3),
          decoration: BoxDecoration(
            color:
                selected ? colors.primaryContainer : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : today
                      ? colors.primary.withOpacity(0.6)
                      : colors.outlineVariant.withOpacity(0.65),
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${day.day}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : foreground.withOpacity(inMonth ? 1 : 0.5),
                      fontWeight: selected || today ? FontWeight.w700 : null,
                    ),
              ),
              if (markers.isNotEmpty)
                Row(children: markers)
              else
                const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthCalendarPanel(
    List<DateTime> days,
    Map<String, List<TimetableOccurrence>> eventsByDay,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('timetable-calendar-grid'),
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: Column(
          children: [
            _monthCalendarHeader(),
            Row(
              children: [
                for (var weekday = DateTime.monday;
                    weekday <= DateTime.sunday;
                    weekday++)
                  Expanded(
                    child: Center(
                      child: Text(
                        _weekday(weekday).substring(0, 2),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var row = 0; row < 6; row++)
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    for (var column = 0; column < 7; column++)
                      Expanded(
                        child: _calendarDayCell(
                          days[row * 7 + column],
                          eventsByDay,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _agendaPanel(
    DateTime day,
    Map<String, List<TimetableOccurrence>> eventsByDay,
  ) {
    final events = eventsByDay[_dateKey(day)] ?? const <TimetableOccurrence>[];
    return Column(
      key: const ValueKey('timetable-selected-day-agenda'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            _dateOnly(day) == _today
                ? _l.timetableToday
                : MaterialLocalizations.of(context).formatMediumDate(day),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_l.timetableNoEvents),
          )
        else
          for (final occurrence in events) _eventCard(occurrence),
      ],
    );
  }

  Widget _calendarContent(bool wide) {
    final firstDay = _monthGridStart(_selectedDate);
    final days =
        List.generate(42, (index) => firstDay.add(Duration(days: index)));
    final eventsByDay = _groupByCampusDay(
      _occurrencesInCampusRange(firstDay, days.length),
    );
    final calendar = _monthCalendarPanel(days, eventsByDay);
    final agenda = _agendaPanel(_selectedDate, eventsByDay);
    if (wide) {
      return Row(
        key: const ValueKey('timetable-wide-layout'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: calendar),
          const SizedBox(width: 20),
          Expanded(flex: 6, child: agenda),
        ],
      );
    }
    return Column(
      key: const ValueKey('timetable-phone-layout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        calendar,
        const SizedBox(height: 14),
        agenda,
      ],
    );
  }

  Widget _upcomingContent() {
    final occurrences = _occurrencesInCampusRange(_today, 30)
        .where((occurrence) => occurrence.end.isAfter(_nowInCampus))
        .toList();
    final eventsByDay = _groupByCampusDay(occurrences);
    final days =
        List.generate(30, (index) => _today.add(Duration(days: index)));
    return Column(
      key: const ValueKey('timetable-upcoming-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days)
          if ((eventsByDay[_dateKey(day)] ?? const <TimetableOccurrence>[])
              .isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(
                _dateOnly(day) == _today
                    ? _l.timetableToday
                    : MaterialLocalizations.of(context).formatMediumDate(day),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final occurrence in eventsByDay[_dateKey(day)]!)
              _eventCard(occurrence),
          ],
        if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(_l.timetableNoEvents),
          ),
      ],
    );
  }

  Widget _eventCard(TimetableOccurrence occurrence) {
    final time = occurrence.allDay
        ? _l.timetableAllDay
        : '${TimeOfDay.fromDateTime(occurrence.start).format(context)} – '
            '${TimeOfDay.fromDateTime(occurrence.end).format(context)}';
    final location = occurrence.location?.trim();
    final description = occurrence.description?.trim();
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey(
          'timetable-event-${occurrence.uid}-${occurrence.recurrenceId}'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      occurrence.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          location == null || location.isEmpty
                              ? Icons.location_off_outlined
                              : Icons.location_on_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            location == null || location.isEmpty
                                ? _l.timetableNoLocation
                                : location,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (location != null && location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      FutureBuilder<RoomResolution>(
                        future: _resolve(location),
                        builder: (context, snapshot) => _venueActions(
                          occurrence,
                          snapshot.data,
                          loading:
                              snapshot.connectionState != ConnectionState.done,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
            places: widget.places,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              key: const ValueKey('timetable-events-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _viewSelector(),
                const SizedBox(height: 14),
                if (_viewMode == _TimetableViewMode.calendar)
                  _calendarContent(wide)
                else
                  _upcomingContent(),
              ],
            ),
          ),
        );
      },
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
