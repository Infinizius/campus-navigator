import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../api/timetable/recurrence_expander.dart';
import '../../api/timetable/timetable_model.dart';
import '../../api/timetable/timetable_store.dart';

class NextEventPreview extends StatelessWidget {
  final TimetableStore store;
  final ValueChanged<TimetableOccurrence> onTap;
  final DateTime Function() clock;

  const NextEventPreview({
    super.key,
    required this.store,
    required this.onTap,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final occurrence = _nextEvent();
          if (occurrence == null) return const SizedBox.shrink();
          final l = AppLocalizations.of(context)!;
          final time = occurrence.allDay
              ? l.timetableAllDay
              : TimeOfDay.fromDateTime(occurrence.start).format(context);
          return Card(
            key: const ValueKey('next-event-preview'),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(occurrence),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.event_available,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.timetableNextEvent,
                              style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 2),
                          Text(occurrence.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(
                              [
                                time,
                                if (occurrence.location?.isNotEmpty == true)
                                  occurrence.location!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          );
        },
      );

  TimetableOccurrence? _nextEvent() {
    if (!store.ready || store.events.isEmpty) return null;
    final now = clock();
    try {
      final occurrences = expandTimetable(
        store.events,
        now.subtract(const Duration(days: 1)),
        now.add(const Duration(days: 30)),
      );
      for (final occurrence in occurrences) {
        if (occurrence.end.isAfter(now)) return occurrence;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
