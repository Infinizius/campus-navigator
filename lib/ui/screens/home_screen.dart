import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../api/campus/campus_catalog.dart';
import '../../api/saved_places.dart';
import '../search_controller.dart';
import 'campus_map_screen.dart';
import 'search_screen.dart';

/// Lazy campus creation preserves the search screen, query, favorites and map
/// camera when switching. Floor screens remain ordinary Navigator routes.
class HomeScreen extends StatefulWidget {
  final CampusCatalog? catalog;
  final TileProvider? tiles;
  final PlaceStore? places;
  final RoomSearchController? search;
  const HomeScreen(
      {super.key, this.catalog, this.tiles, this.places, this.search});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _mapVisited = false;

  @override
  Widget build(BuildContext context) {
    final de = Localizations.localeOf(context).languageCode == 'de';
    return Scaffold(
        // Each tab owns its keyboard resizing; keep the actual inset available
        // to the campus camera until the keyboard has finished closing.
        resizeToAvoidBottomInset: false,
        body: IndexedStack(index: _index, children: [
          SearchScreen(places: widget.places, search: widget.search),
          if (_mapVisited)
            TickerMode(
                enabled: _index == 1,
                child: CampusMapScreen(
                    active: _index == 1,
                    catalog: widget.catalog,
                    tiles: widget.tiles))
          else
            const SizedBox(),
        ]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) {
              FocusScope.of(context).unfocus();
              setState(() {
                _index = index;
                _mapVisited |= index == 1;
              });
            },
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.search),
                  label: de ? 'Raumsuche' : 'Room search'),
              NavigationDestination(
                  icon: const Icon(Icons.map_outlined),
                  selectedIcon: const Icon(Icons.map),
                  label: de ? 'Campuskarte' : 'Campus map'),
            ]));
  }
}
