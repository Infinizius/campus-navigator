import 'package:campus_navigator/api/saved_places.dart';
import 'package:campus_navigator/api/timetable/room_resolver.dart';
import 'package:campus_navigator/api/timetable/timetable_model.dart';
import 'package:campus_navigator/api/timetable/timetable_store.dart';
import 'package:flutter_test/flutter_test.dart';

IcsTemporal start(String value) =>
    IcsTemporal(value: value, kind: IcsTemporalKind.floating);

TimetableSeries event(String uid, String location,
        {String title = 'Lecture'}) =>
    TimetableSeries(
      uid: uid,
      summary: title,
      location: location,
      start: start('20261014T090000'),
      end: start('20261014T100000'),
    );

SavedPlace room(String identifier) => SavedPlace(
      kind: PlaceKind.room,
      identifier: identifier,
      name: 'E069',
    );

void main() {
  test('round_trips_after_new_store_instance', () async {
    String? document;
    final first = TimetableStore(
      read: () async => document,
      write: (value) async => document = value,
    );
    expect(await first.load(), isTrue);
    expect(
      await first.importCalendar(
        ParsedTimetable(series: [event('one', 'APB E069')]),
        TimetableImportMode.replace,
      ),
      isTrue,
    );

    final restored = TimetableStore(read: () async => document);
    expect(await restored.load(), isTrue);
    expect(restored.events.single.uid, 'one');
    expect(restored.events.single.location, 'APB E069');
  });

  test('update_upserts_without_duplicates_and_keeps_absent_events', () async {
    String? document;
    final store = TimetableStore(
      read: () async => document,
      write: (value) async => document = value,
    );
    await store.load();
    await store.importCalendar(
      ParsedTimetable(
          series: [event('one', 'APB E069'), event('two', 'BEY 318')]),
      TimetableImportMode.replace,
    );
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB E069', title: 'Updated')]),
      TimetableImportMode.update,
    );

    expect(store.events.map((value) => value.uid), ['one', 'two']);
    expect(store.events.first.summary, 'Updated');
  });

  test('replace_discards_old_events_and_mappings', () async {
    String? document;
    final store = TimetableStore(
      read: () async => document,
      write: (value) async => document = value,
    );
    await store.load();
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB E069')]),
      TimetableImportMode.replace,
    );
    await store.assignRoom(
        'one', normalizeRoomLocation('APB E069'), room('apb/eg/raum/e069'));
    await store.importCalendar(
      ParsedTimetable(series: [event('two', 'BEY 318')]),
      TimetableImportMode.replace,
    );

    expect(store.events.map((value) => value.uid), ['two']);
    expect(store.mappings, isEmpty);
  });

  test('preserves_mapping_only_for_unchanged_location', () async {
    String? document;
    final store = TimetableStore(
      read: () async => document,
      write: (value) async => document = value,
    );
    await store.load();
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB E069')]),
      TimetableImportMode.replace,
    );
    await store.assignRoom(
        'one', normalizeRoomLocation('APB E069'), room('apb/eg/raum/e069'));
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB/E069', title: 'Updated')]),
      TimetableImportMode.update,
    );
    expect(store.roomFor('one', 'APB E069')?.identifier, 'apb/eg/raum/e069');

    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'BEY 318', title: 'Changed')]),
      TimetableImportMode.update,
    );
    expect(store.roomFor('one', 'BEY 318'), isNull);
  });

  test('clear_removes_all_events_and_mappings', () async {
    String? document;
    final store = TimetableStore(
      read: () async => document,
      write: (value) async => document = value,
    );
    await store.load();
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB E069')]),
      TimetableImportMode.replace,
    );
    await store.assignRoom(
        'one', normalizeRoomLocation('APB E069'), room('apb/eg/raum/e069'));
    expect(await store.clear(), isTrue);
    expect(store.events, isEmpty);
    expect(store.mappings, isEmpty);
  });

  test('failed_import_keeps_committed_snapshot', () async {
    String? document;
    var failWrites = false;
    final store = TimetableStore(
      read: () async => document,
      write: (value) async {
        if (failWrites) throw StateError('synthetic write failure');
        document = value;
      },
    );
    await store.load();
    await store.importCalendar(
      ParsedTimetable(series: [event('one', 'APB E069')]),
      TimetableImportMode.replace,
    );
    final committedDocument = document;
    failWrites = true;
    expect(
      await store.importCalendar(
        ParsedTimetable(series: [event('two', 'BEY 318')]),
        TimetableImportMode.replace,
      ),
      isFalse,
    );
    expect(document, committedDocument);
    expect(store.events.single.uid, 'one');
  });

  test('corrupt_document_is_not_overwritten', () async {
    const corrupt = '{"version":9,"events":[]}';
    var writes = 0;
    final store = TimetableStore(
      read: () async => corrupt,
      write: (_) async => writes++,
    );

    expect(await store.load(), isFalse);
    expect(store.loadFailed, isTrue);
    expect(
      await store.importCalendar(
        ParsedTimetable(series: [event('one', 'APB E069')]),
        TimetableImportMode.replace,
      ),
      isFalse,
    );
    expect(writes, 0);
  });
}
