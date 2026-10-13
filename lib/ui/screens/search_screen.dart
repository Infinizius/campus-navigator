import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/place_navigation.dart';
import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/ui/search_controller.dart';
import 'package:flutter/material.dart';
import 'building_screen.dart';
import 'freeroom_search_screen.dart';
import 'location_screen.dart';
import 'settings_screen.dart';

class SearchScreen extends StatefulWidget {
  final PlaceStore? places;
  final RoomSearchController? search;
  final Future<BuildingPageData> Function(SavedPlace)? loadPlace;
  const SearchScreen({super.key, this.places, this.search, this.loadPlace});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final PlaceStore _places;
  late final RoomSearchController _search;
  final _textController = TextEditingController();
  String? _opening;

  String _t(String de, String en) =>
      Localizations.localeOf(context).languageCode == 'de' ? de : en;

  @override
  void initState() {
    super.initState();
    _places = widget.places ?? PlaceStore();
    _search = widget.search ?? RoomSearchController();
    _places.addListener(_changed);
    _search.addListener(_changed);
    if (!_places.ready) _places.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _places.removeListener(_changed);
    _search.removeListener(_changed);
    if (widget.places == null) _places.dispose();
    if (widget.search == null) _search.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggle(SavedPlace place) async {
    if (!await _places.toggle(place)) {
      _message(_t(
          'Favoriten konnten nicht gespeichert werden. Bitte erneut versuchen.',
          'Could not save favorites. Please try again.'));
    }
  }

  Future<void> _open(SavedPlace place) async {
    if (_opening != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _opening = place.key);
    try {
      final data = await (widget.loadPlace ?? loadSavedPlace)(place);
      if (!mounted) {
        data.backgroundImageData?.dispose();
        return;
      }
      final saved = await _places.recordVisit(place);
      if (!mounted) {
        data.backgroundImageData?.dispose();
        return;
      }
      if (!saved) {
        _message(_t('Der Verlauf konnte nicht gespeichert werden.',
            'Could not save recent rooms.'));
      }
      setState(() => _opening = null);
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => BuildingScreen(
                  room: Future.value(data),
                  name: place.name,
                  favoriteAction: AnimatedBuilder(
                      animation: _places,
                      builder: (context, _) => _favoriteButton(place)))));
    } catch (_) {
      if (!mounted) return;
      _message(_t(
          'Etagenplan nicht verfügbar. Bitte Verbindung prüfen und erneut versuchen.',
          'Floor plan unavailable. Check your connection and try again.'));
    } finally {
      if (mounted && _opening != null) setState(() => _opening = null);
    }
  }

  Widget _favoriteButton(SavedPlace place) {
    final selected = _places.contains(place);
    final enabled = _places.ready && !_places.saving;
    final label = selected
        ? _t('Favorit entfernen', 'Remove favorite')
        : _t('Als Favorit speichern', 'Save favorite');
    return Semantics(
        label: '$label: ${place.name}',
        button: true,
        toggled: selected,
        enabled: enabled,
        excludeSemantics: true,
        onTap: enabled ? () => _toggle(place) : null,
        child: IconButton(
            key: ValueKey('favorite-${place.key}'),
            tooltip: label,
            icon: Icon(
                selected ? Icons.star_rounded : Icons.star_outline_rounded),
            color: selected ? Theme.of(context).colorScheme.primary : null,
            onPressed: enabled ? () => _toggle(place) : null));
  }

  Widget _entry(SavedPlace place, {String section = 'result'}) => ListTile(
      key: ValueKey('place-$section-${place.key}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
          place.kind == PlaceKind.room
              ? Icons.meeting_room_outlined
              : Icons.business_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(place.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          place.kind == PlaceKind.room
              ? '${place.buildingCode.toUpperCase()} · ${_t('Etage', 'Floor')} ${place.floor}'
                  '${place.subName == null ? '' : ' · ${place.subName}'}'
              : '${place.buildingCode.toUpperCase()} · ${_t('Gebäude', 'Building')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: _opening == place.key
          ? const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))))
          : _favoriteButton(place),
      onTap: _opening == null ? () => _open(place) : null);

  Widget _heading(String text, {Widget? action}) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(children: [
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
        if (action != null) action,
      ]));

  Widget _empty(String text, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]));

  List<Widget> _home() => [
        if (_places.loading) const LinearProgressIndicator(minHeight: 2),
        if (_places.loadFailed) ...[
          _empty(
              _t('Favoriten und Verlauf konnten nicht geladen werden.',
                  'Could not load favorites and recent rooms.'),
              Icons.error_outline),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: _places.loading ? null : _places.load,
                  child: Text(_t('Erneut versuchen', 'Try again')))),
        ],
        _heading(_t('Favoriten', 'Favorites')),
        if (_places.favorites.isEmpty && !_places.loading)
          _empty(
              _t('Mit dem Stern Räume und Gebäude für den schnellen Zugriff speichern.',
                  'Use the star to save rooms and buildings for quick access.'),
              Icons.star_outline_rounded),
        ..._places.favorites.map((p) => _entry(p, section: 'favorite')),
        const Divider(height: 24),
        _heading(_t('Zuletzt aufgerufen', 'Recent rooms'),
            action: _places.recent.isEmpty
                ? null
                : TextButton(
                    onPressed: _places.saving
                        ? null
                        : () async {
                            if (!await _places.clearHistory()) {
                              _message(_t(
                                  'Verlauf konnte nicht gelöscht werden.',
                                  'Could not clear recent rooms.'));
                            }
                          },
                    child: Text(_t('Leeren', 'Clear')))),
        if (_places.recent.isEmpty && !_places.loading)
          _empty(
              _t('Hier erscheinen die zuletzt geöffneten Räume.',
                  'Rooms you open will appear here.'),
              Icons.history),
        ..._places.recent.map((p) => _entry(p, section: 'recent')),
      ];

  List<Widget> _results() {
    final result = _search.result;
    final rooms = result?.resultsRooms
            .map((e) => SavedPlace.tryFromSearch(e, PlaceKind.room))
            .whereType<SavedPlace>()
            .toList() ??
        <SavedPlace>[];
    final buildings = result?.resultsBuildings
            .map((e) => SavedPlace.tryFromSearch(e, PlaceKind.building))
            .whereType<SavedPlace>()
            .toList() ??
        <SavedPlace>[];
    return [
      if (_search.loading) ...[
        const LinearProgressIndicator(minHeight: 2),
        _empty(_t('Suche läuft …', 'Searching …'), Icons.search),
      ],
      if (_search.failed) ...[
        _empty(
            _t('Suche nicht verfügbar. Bitte Verbindung prüfen.',
                'Search unavailable. Check your connection.'),
            Icons.wifi_off),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: _search.retry,
                child: Text(_t('Erneut versuchen', 'Try again')))),
      ],
      if (result != null) ...[
        if (result.assist.isNotEmpty)
          Text(result.assist, style: Theme.of(context).textTheme.bodySmall),
        if (rooms.isNotEmpty) ...[
          _heading(_t('Räume', 'Rooms')),
          ...rooms.map(_entry),
        ],
        if (buildings.isNotEmpty) ...[
          _heading(_t('Gebäude', 'Buildings')),
          ...buildings.map(_entry),
        ],
        if (rooms.isEmpty && buildings.isEmpty)
          _empty(
              _t('Keine Treffer. Gebäude und Raumnummer eingeben, z. B. BEY 318.',
                  'No results. Enter a building and room number, e.g. BEY 318.'),
              Icons.search_off),
        if (result.moreRooms || result.moreBuildings)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_t('Suche eingrenzen, um weitere Treffer zu finden.',
                  'Refine your search to find more results.'))),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Campus Navigator'), actions: [
        IconButton(
            icon: const Icon(Icons.settings),
            tooltip: _t('Einstellungen', 'Settings'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        IconButton(
            icon: const Badge(
                child: Icon(Icons.meeting_room), label: Text('WIP')),
            tooltip: _t('Freiraumsuche', 'Free room search'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FreeroomSearchScreen()))),
        IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: _t('Standort', 'Location'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LocationScreen(name: 'Location')))),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                            controller: _textController,
                            autocorrect: false,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                labelText:
                                    _t('Gebäude oder Raum', 'Building or room'),
                                hintText: _t('z. B. BEY 318', 'e.g. BEY 318'),
                                border: const OutlineInputBorder(),
                                suffixIcon: _textController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip:
                                            _t('Suche leeren', 'Clear search'),
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          _textController.clear();
                                          _search.change('');
                                        })),
                            onChanged: _search.change,
                            onSubmitted: (value) =>
                                _search.change(value, immediately: true))),
                    if (_opening != null)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            children:
                                _search.query.isEmpty ? _home() : _results())),
                  ])))));
}
