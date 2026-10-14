import 'package:campus_navigator/api/building/room_details.dart';
import 'package:flutter/material.dart';

class RoomDetailsView extends StatelessWidget {
  final RoomDetails details;
  final bool isFavorite;
  final String title;
  final String placesLabel;
  final String floorLabel;
  final String buildingLabel;
  final String buildingPartLabel;
  final String usageLabel;
  final String remarkLabel;
  final String doorplateLabel;
  final String connectedRoomsLabel;
  final String favoriteLabel;
  final String removeFavoriteLabel;
  final ValueChanged<bool>? onFavoriteChanged;
  final ValueChanged<String> onOpenRoom;

  const RoomDetailsView({
    super.key,
    required this.details,
    required this.isFavorite,
    required this.title,
    required this.placesLabel,
    required this.floorLabel,
    required this.buildingLabel,
    required this.buildingPartLabel,
    required this.usageLabel,
    required this.remarkLabel,
    required this.doorplateLabel,
    required this.connectedRoomsLabel,
    required this.favoriteLabel,
    required this.removeFavoriteLabel,
    required this.onFavoriteChanged,
    required this.onOpenRoom,
  });

  @override
  Widget build(BuildContext context) {
    final page = details.pageDetails;
    final fields = <({String label, RoomField<dynamic> field})>[
      if (page != null) ...[
        (label: buildingPartLabel, field: page.buildingPart),
        (label: buildingLabel, field: page.buildingNumber),
        (label: floorLabel, field: page.floor),
        (label: placesLabel, field: page.places),
        (label: usageLabel, field: page.usage),
        (label: remarkLabel, field: page.remark),
        (label: doorplateLabel, field: page.doorplateGerman),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                semanticsLabel: title),
          ),
          if (onFavoriteChanged case final onChanged?)
            IconButton(
              tooltip: isFavorite ? removeFavoriteLabel : favoriteLabel,
              icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              onPressed: () => onChanged(!isFavorite),
            ),
        ]),
        for (final item in fields)
          if (item.field.state == RoomFieldState.value)
            _detailRow(context, item.label, item.field.value.toString()),
        if (details.doors.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(connectedRoomsLabel,
                style: Theme.of(context).textTheme.labelLarge),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final door in details.doors)
                if (door.otherRoomFor(details.roomId)?.id case final id?)
                  ActionChip(
                    label: Text(door.otherRoomFor(details.roomId)?.room ?? id),
                    onPressed: () => onOpenRoom(id),
                  ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ]),
      );
}

class RoomDetailsLoadView extends StatelessWidget {
  final Future<RoomDetails> future;
  final String loadingLabel;
  final String errorLabel;
  final String retryLabel;
  final VoidCallback onRetry;
  final Widget Function(RoomDetails details) builder;

  const RoomDetailsLoadView({
    super.key,
    required this.future,
    required this.loadingLabel,
    required this.errorLabel,
    required this.retryLabel,
    required this.onRetry,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<RoomDetails>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasData) return builder(snapshot.data!);
          if (snapshot.hasError) {
            return Row(children: [
              Expanded(child: Text(errorLabel)),
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ]);
          }
          return Semantics(
            liveRegion: true,
            child: Row(children: [
              const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(loadingLabel),
            ]),
          );
        },
      );
}
