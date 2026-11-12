import 'package:campus_navigator/api/api_services.dart';
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/freeroom_search/search.dart';
import 'package:campus_navigator/api/freeroom_search/search_options.dart';
import 'package:campus_navigator/api/freeroom_search/search_result.dart';
import 'package:campus_navigator/api/networking.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:week_number/iso.dart';

import 'building_screen.dart';

typedef FreeRoomSearch = Future<FreeroomSearchResult> Function(
    int week, int minCapacity);
typedef RecurringFreeRoomSearch = Future<FreeroomSearchResult> Function(
    int startWeek, int endWeek, Repetition repetition, int minCapacity);

class FreeroomSearchScreen extends StatefulWidget {
  final DateTime? now;
  final FreeRoomSearch? search;
  final RecurringFreeRoomSearch? recurringSearch;
  const FreeroomSearchScreen(
      {super.key, this.now, this.search, this.recurringSearch});

  @override
  State<FreeroomSearchScreen> createState() => _FreeroomSearchScreenState();
}

class _FreeroomSearchScreenState extends State<FreeroomSearchScreen> {
  late DateTime _date;
  late int _isoYear;
  late DateTime _endDate;
  Repetition _repetition = Repetition.once;
  int _period = 0;
  final _capacity = TextEditingController();
  Future<FreeroomSearchResult>? _result;
  bool _invalidCapacity = false;

  DateTime _mondayOfIsoYear(int year) {
    final jan4 = DateTime(year, 1, 4);
    return jan4.subtract(Duration(days: jan4.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _isoYear = _date.add(Duration(days: 4 - _date.weekday)).year;
    _endDate = _defaultEndDate(_date);
    _search();
  }

  DateTime _defaultEndDate(DateTime start) {
    final lastDay =
        _mondayOfIsoYear(_isoYear + 1).subtract(const Duration(days: 1));
    var end = DateTime(start.year, start.month, start.day + 28);
    while (end.isAfter(lastDay)) {
      end = DateTime(end.year, end.month, end.day - 7);
    }
    if (_repetition == Repetition.biWeekly &&
        (end.weekNumber - start.weekNumber).isOdd) {
      end = DateTime(end.year, end.month, end.day - 7);
    }
    return end;
  }

  void _search() {
    if (_date.weekday > DateTime.friday) {
      setState(() => _result = null);
      return;
    }
    final text = _capacity.text.trim();
    final value = int.tryParse(text);
    if (text.isNotEmpty && (value == null || value < 1)) {
      setState(() {
        _invalidCapacity = true;
        _result = null;
      });
      return;
    }
    final week = _date.weekNumber;
    setState(() {
      _invalidCapacity = false;
      _result = (_repetition == Repetition.once
              ? widget.search?.call(week, value ?? -1)
              : widget.recurringSearch?.call(
                  week, _endDate.weekNumber, _repetition, value ?? -1)) ??
          APIServices.Shared.searchFreeRooms(
              startWeek: week,
              endWeek:
                  _repetition == Repetition.once ? week : _endDate.weekNumber,
              repetition: _repetition,
              universities: {UserUniversity.TUD},
              minCapacity: value ?? -1);
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: _mondayOfIsoYear(_isoYear),
        lastDate:
            _mondayOfIsoYear(_isoYear + 1).subtract(const Duration(days: 1)));
    if (date != null && mounted) {
      final oldWeek = _date.weekNumber;
      final oldDay = _date.weekday;
      setState(() {
        _date = date;
        _endDate = _defaultEndDate(date);
      });
      if (oldWeek != date.weekNumber ||
          _repetition != Repetition.once ||
          oldDay > DateTime.friday ||
          date.weekday > DateTime.friday) {
        _search();
      }
    }
  }

  Future<void> _pickEndDate() async {
    final end = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _date,
      lastDate:
          _mondayOfIsoYear(_isoYear + 1).subtract(const Duration(days: 1)),
      selectableDayPredicate: (day) =>
          day.weekday == _date.weekday &&
          (_repetition != Repetition.biWeekly ||
              (day.weekNumber - _date.weekNumber).isEven),
    );
    if (end != null && mounted) {
      setState(() => _endDate = end);
      _search();
    }
  }

  Future<void> _openRoom(String name) async {
    try {
      final links =
          await APIServices.Shared.fetchRoomLink(name.split('/').first, name);
      if (links.isEmpty) throw const FormatException('No room link');
      final uri = Uri.parse(links.first);
      if (uri.host != Uri.parse(baseURL).host ||
          !uri.path.startsWith('/etplan/')) {
        throw const FormatException('Invalid room link');
      }
      final query = uri.path.substring('/etplan/'.length);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BuildingScreen(
                  room: BuildingPageData.fetchQuery(query), name: name)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.freeRoomOpenFailed)));
      }
    }
  }

  Widget _results(FreeroomSearchResult data, AppLocalizations l) {
    try {
      final tu = data.freeRoomsFor(_date.weekday - 1, _period);
      if (tu.isEmpty) return Text(l.freeRoomEmpty);
      final groups = <String, List<String>>{};
      for (final room in tu) {
        groups.putIfAbsent(room.split('/').first, () => []).add(room);
      }
      final buildings = groups.keys.toList()..sort();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final building in buildings) ...[
          Text(building, style: Theme.of(context).textTheme.titleMedium),
          for (final room in groups[building]!)
            ListTile(
                dense: true,
                title: Text(room),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openRoom(room)),
        ],
      ]);
    } on FormatException {
      return Text(l.freeRoomFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.freeroomsearchScreen_Title)),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(l.freeRoomHint),
        Text(l.freeRoomHtwNote),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(
                '${l.freeRoomDate}: ${DateFormat.yMd(Localizations.localeOf(context).toString()).format(_date)}')),
        Text(l.freeRoomYearNote, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<Repetition>(
          value: _repetition,
          decoration: InputDecoration(labelText: l.freeRoomRecurrence),
          items: [
            DropdownMenuItem(
                value: Repetition.once,
                child: Text(l.freeroomsearchScreen_Once)),
            DropdownMenuItem(
                value: Repetition.weekly,
                child: Text(l.freeroomsearchScreen_Weekly)),
            DropdownMenuItem(
                value: Repetition.biWeekly,
                child: Text(l.freeroomsearchScreen_BiWeekly)),
          ],
          onChanged: (value) {
            if (value != null && value != _repetition) {
              setState(() {
                _repetition = value;
                if (value == Repetition.biWeekly &&
                    (_endDate.weekNumber - _date.weekNumber).isOdd) {
                  _endDate =
                      DateTime(_endDate.year, _endDate.month, _endDate.day - 7);
                }
              });
              _search();
            }
          },
        ),
        if (_repetition != Repetition.once) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickEndDate,
            icon: const Icon(Icons.event),
            label: Text(
                '${l.freeRoomRepeatUntil}: ${DateFormat.yMd(Localizations.localeOf(context).toString()).format(_endDate)}'),
          ),
          Text(l.freeRoomRepeatingHint,
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
            value: _period,
            decoration: InputDecoration(labelText: l.freeRoomPeriod),
            items: List.generate(
                7,
                (i) => DropdownMenuItem(
                    value: i,
                    child: Text('${i + 1}. ${l.doublePeriod} · ${const [
                      "07:30–09:00",
                      "09:20–10:50",
                      "11:10–12:40",
                      "13:00–14:30",
                      "14:50–16:20",
                      "16:40–18:10",
                      "18:30–20:00"
                    ][i]}'))),
            onChanged: (v) {
              if (v != null) setState(() => _period = v);
            }),
        const SizedBox(height: 12),
        TextField(
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: l.freeRoomCapacity,
                errorText:
                    _invalidCapacity ? l.freeRoomInvalidCapacity : null)),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.search),
            label: Text(l.search)),
        const SizedBox(height: 16),
        if (_date.weekday > DateTime.friday) Text(l.freeRoomWeekend),
        if (_result != null)
          FutureBuilder<FreeroomSearchResult>(
              future: _result,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text(snapshot.error is FreeRoomLoginRequired
                      ? l.freeRoomLogin
                      : l.freeRoomFailed);
                }
                return snapshot.hasData
                    ? _results(snapshot.data!, l)
                    : Text(l.freeRoomFailed);
              }),
      ])),
    );
  }

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }
}
