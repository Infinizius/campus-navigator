import 'dart:async';

import 'package:campus_navigator/api/freeroom_search/search_result.dart';
import 'package:campus_navigator/ui/screens/freeroom_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:campus_navigator/api/freeroom_search/search.dart';
import 'package:campus_navigator/api/freeroom_search/search_options.dart';

void main() {
  Widget app(Widget child, {ThemeData? theme}) => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        theme: theme,
        home: child,
      );

  testWidgets('late response cannot replace results for a newer week',
      (tester) async {
    final requests = <int, Completer<FreeroomSearchResult>>{};
    FreeroomSearchResult rooms(String name) => FreeroomSearchResult.fromJson({
          'rooms': [name],
          'taken': List.generate(63, (_) => <int>[]),
          'roominfo': <String, dynamic>{},
        });
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2026, 11, 9),
      search: (week, _) => (requests[week] = Completer()).future,
    )));
    await tester.pump();
    expect(requests.keys, [46]);
    await tester.tap(find.textContaining('9.11.2026'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('16').last);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests.keys, [46, 47]);
    requests[47]!.complete(rooms('APB/NEW/U'));
    await tester.pump();
    await tester.pump();
    expect(find.text('APB/NEW/U'), findsOneWidget);
    requests[46]!.complete(rooms('APB/OLD/U'));
    await tester.pump();
    expect(find.text('APB/NEW/U'), findsOneWidget);
    expect(find.text('APB/OLD/U'), findsNothing);
  });

  testWidgets('weekly search uses an explicit inclusive end week',
      (tester) async {
    final calls = <(int, int, Repetition)>[];
    final result = FreeroomSearchResult.fromJson({
      'rooms': <String>[],
      'taken': <dynamic>[],
      'roominfo': <String, dynamic>{},
    });
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2026, 11, 9),
      search: (_, __) async => result,
      recurringSearch: (start, end, repetition, capacity) async {
        calls.add((start, end, repetition));
        return result;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einmalig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wöchentlich').last);
    await tester.pumpAndSettle();
    expect(calls.last, (46, 50, Repetition.weekly));
    expect(find.textContaining('7.12.2026'), findsOneWidget);
    await tester.tap(find.textContaining('7.12.2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.text('23').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(calls.last, (46, 48, Repetition.weekly));
  });

  testWidgets('biweekly search ends on an occurrence in ISO week 53 years',
      (tester) async {
    final calls = <(int, int, Repetition)>[];
    final result = FreeroomSearchResult.fromJson({
      'rooms': <String>[],
      'taken': <dynamic>[],
      'roominfo': <String, dynamic>{},
    });
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2020, 12, 7),
      search: (_, __) async => result,
      recurringSearch: (start, end, repeat, _) async {
        calls.add((start, end, repeat));
        return result;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einmalig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zweiwöchentlich').last);
    await tester.pumpAndSettle();
    expect(calls.last, (50, 52, Repetition.biWeekly));
    expect(find.textContaining('21.12.2020'), findsOneWidget);
  });

  testWidgets('initial ISO week 53 is requested and empty results are clear',
      (tester) async {
    int? requestedWeek;
    await tester.pumpWidget(app(
        FreeroomSearchScreen(
          now: DateTime(2021, 1, 1),
          search: (week, capacity) async {
            requestedWeek = week;
            return FreeroomSearchResult.fromJson({
              'rooms': <String>[],
              'taken': <dynamic>[],
              'roominfo': <String, dynamic>{},
              'htw_rooms': <String>[],
              'htw_taken': <dynamic>[],
              'htw_roominfo': <String, dynamic>{},
            });
          },
        ),
        theme: ThemeData.dark()));
    await tester.pumpAndSettle();
    expect(requestedWeek, 53);
    expect(find.text('Für diese Zeit wurden keine freien Räume gemeldet.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login requirement is distinct from a network error',
      (tester) async {
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2026, 11, 9),
      search: (_, __) async => throw const FreeRoomLoginRequired(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Für diese Suche ist eine Anmeldung erforderlich.'),
        findsOneWidget);
  });

  testWidgets('network errors allow a successful retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2026, 11, 9),
      search: (_, __) async {
        if (++calls == 1) throw StateError('offline');
        return FreeroomSearchResult.fromJson({
          'rooms': <String>[],
          'taken': <dynamic>[],
          'roominfo': <String, dynamic>{},
        });
      },
    )));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Freie Räume konnten nicht geladen werden. Verbindung prüfen und erneut versuchen.'),
        findsOneWidget);
    await tester.tap(find.text('Suchen'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Für diese Zeit wurden keine freien Räume gemeldet.'),
        findsOneWidget);
  });
  testWidgets('shows TU results and does not claim unverified HTW availability',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: FreeroomSearchScreen(
          now: DateTime(2026, 11, 9),
          search: (week, minCapacity) async => FreeroomSearchResult.fromJson({
                'rooms': ['APB/E001/U'],
                'taken': List.generate(63, (_) => <int>[]),
                'roominfo': <String, dynamic>{},
                'htw_rooms': ['S 221'],
                'htw_taken': List.generate(63, (_) => <int>[]),
                'htw_roominfo': <String, dynamic>{},
              })),
    ));
    await tester.pumpAndSettle();
    expect(find.text('APB/E001/U'), findsOneWidget);
    expect(find.text('S 221'), findsNothing);
    expect(find.textContaining('9.11.2026'), findsWidgets);
    expect(
        find.textContaining('TU-Belegungsdaten können unvollständig oder veraltet sein'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Die Jahreszuordnung der TU-Daten ist nicht bestätigt.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekend never treats unverified slots as available',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(FreeroomSearchScreen(
      now: DateTime(2026, 11, 14),
      search: (_, __) async {
        calls++;
        throw StateError('No weekend request expected');
      },
    )));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
        find.text(
            'Für Wochenenden sind die Belegungsdaten noch nicht geprüft.'),
        findsOneWidget);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('small screen with large text fits in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(
        MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 640), textScaler: TextScaler.linear(2)),
          child: FreeroomSearchScreen(
            now: DateTime(2026, 11, 9),
            search: (_, __) async => FreeroomSearchResult.fromJson({
              'rooms': <String>[],
              'taken': <dynamic>[],
              'roominfo': <String, dynamic>{},
            }),
          ),
        ),
        theme: ThemeData(brightness: brightness),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -380));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
