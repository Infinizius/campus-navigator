import 'dart:async';

// Define a custom Form widget.
import 'package:campus_navigator/api/building/building_page_data.dart';
import 'package:campus_navigator/api/search.dart';
import 'package:campus_navigator/api/storage.dart';
import 'package:campus_navigator/ui/screens/building_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../api/api_services.dart';
import 'freeroom_search_screen.dart';
import 'location_screen.dart';
import 'settings_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<SearchResult>? searchResult;
  Timer? _debounce;
  int _queryRevision = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String hintText = "";

  Widget searchResultList(SearchResult result) => Column(children: [
        ...result.resultsRooms.map(roomResultButton),
        if (result.moreRooms)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(Localizations.localeOf(context).languageCode == 'de'
                  ? 'Suche eingrenzen, um weitere Räume zu finden.'
                  : 'Refine your search to find more rooms.')),
      ]);

  Widget roomResultButton(SearchResultObject entry) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(entry.name),
        subtitle: entry.subName == null ? null : Text(entry.subName!),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          FocusScope.of(context).unfocus();
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => BuildingScreen(
                      room: BuildingPageData.fetchQuery(entry.identifier),
                      name: entry.name)));
        },
      );

  void onSearchChanged(String query) {
    _debounce?.cancel();
    final revision = ++_queryRevision;
    setState(() {
      searchResult = null;
      hintText = '';
    });
    if (query.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _search(query.trim(), revision));
  }

  Future<void> _search(String query, int revision) async {
    final future = SearchResult.searchRoom(query);
    setState(() {
      searchResult = future;
    });
    try {
      final results = await future;
      if (!mounted || revision != _queryRevision) return;
      setState(() => hintText = results.assist);
      final prefetch = await APIServices.Shared.storage.getPrefetchingLevel();
      if (!mounted || revision != _queryRevision) return;
      final count = prefetch == PrefetchingLevel.allResults
          ? 8
          : prefetch == PrefetchingLevel.firstResult
              ? 1
              : 0;
      // Prefetch only HTML, serially; errors must not escape the search handler.
      for (final entry in results.resultsRooms.take(count)) {
        if (!mounted || revision != _queryRevision) break;
        await BuildingPageData.preFetchQuery(entry.identifier);
      }
    } catch (_) {
      // FutureBuilder displays the search error. A prefetch failure is optional.
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.searchScreen_Title),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Einstellungen',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsScreen()),
                );
              },
            ),
            IconButton(
              icon: const Badge(
                  child: Icon(Icons.meeting_room), label: Text("WIP")),
              tooltip: 'Freiraumsuche',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const FreeroomSearchScreen()),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.location_on),
              tooltip: 'Open Location',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const LocationScreen(name: "Location")),
                );
              },
            ),
          ],
        ),
        body: Container(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    enableInteractiveSelection: true,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: localizations.searchScreen_SearchHint),
                    onChanged: onSearchChanged,
                    onSubmitted: (query) {
                      _debounce?.cancel();
                      if (query.trim().isNotEmpty)
                        _search(query.trim(), ++_queryRevision);
                    },
                  ),
                  if (hintText.isNotEmpty)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(hintText))),

                  // Spacing
                  const SizedBox(
                    height: 20,
                  ),
                  FutureBuilder(
                    key: ValueKey(_queryRevision),
                    future: searchResult,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('${snapshot.error}');
                      } else if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      return searchResultList(snapshot.data!);
                    },
                  )
                ],
              ),
            )));
  }
}
