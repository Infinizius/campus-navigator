import 'package:campus_navigator/api/timetable/timetable_model.dart';
import 'package:campus_navigator/api/timetable/timetable_store.dart';
import 'package:campus_navigator/ui/components/next_event_preview.dart';
import 'package:campus_navigator/ui/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableSeries event(String uid, String title, String dateTime) =>
    TimetableSeries(
      uid: uid,
      summary: title,
      start: IcsTemporal(value: dateTime, kind: IcsTemporalKind.floating),
      end: IcsTemporal(
        value:
            '${dateTime.substring(0, 9)}${(int.parse(dateTime.substring(9, 11)) + 1).toString().padLeft(2, '0')}${dateTime.substring(11)}',
        kind: IcsTemporalKind.floating,
      ),
    );

Future<TimetableStore> storeWith(List<TimetableSeries> events) async {
  String? document;
  final store = TimetableStore(
    read: () async => document,
    write: (value) async => document = value,
  );
  await store.load();
  await store.importCalendar(
    ParsedTimetable(series: events),
    TimetableImportMode.replace,
  );
  return store;
}

Widget app(Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themeData(AppTheme.lightColorScheme),
      home: home,
    );

void main() {
  testWidgets('preview_hides_when_no_upcoming_event', (tester) async {
    final store = await storeWith([]);
    await tester.pumpWidget(app(Scaffold(
      body: NextEventPreview(
        store: store,
        clock: () => DateTime(2026, 10, 14, 8),
        onTap: (_) {},
      ),
    )));

    expect(find.byKey(const ValueKey('next-event-preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('preview_shows_next_upcoming_event_and_calls_tap',
      (tester) async {
    final store = await storeWith([
      event('next', 'Synthetic lecture', '20261014T090000'),
    ]);
    TimetableOccurrence? selected;
    await tester.pumpWidget(app(Scaffold(
      body: NextEventPreview(
        store: store,
        clock: () => DateTime(2026, 10, 14, 8),
        onTap: (occurrence) => selected = occurrence,
      ),
    )));

    expect(find.byKey(const ValueKey('next-event-preview')), findsOneWidget);
    expect(find.text('Synthetic lecture'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-event-preview')));
    expect(selected?.uid, 'next');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
