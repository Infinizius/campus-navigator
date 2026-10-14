import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('documents supported ICS data and timezone behavior', () {
    final document = File('docs/timetable.md').readAsStringSync();
    for (final feature in [
      'DTSTART',
      'DTEND',
      'DURATION',
      'SUMMARY',
      'DESCRIPTION',
      'LOCATION',
      'RRULE',
      'EXDATE',
      'RECURRENCE-ID',
      'VALARM',
      'Europe/Berlin',
    ]) {
      expect(document, contains(feature));
    }
    expect(document, contains('20,000'));
    expect(document, contains('2100'));
    expect(document, contains('regardless of the device timezone'));
    expect(document,
        contains('`UNTIL` boundaries matching the DTSTART value type'));
  });

  test('documents privacy and explicit unsupported recurrence behavior', () {
    final document = File('docs/timetable.md').readAsStringSync();
    expect(document, contains('No calendar permission'));
    expect(document, contains('no cloud service'));
    expect(document, contains('`SUMMARY` and `DESCRIPTION`'));
    expect(document, contains('RDATE'));
    expect(document, contains('THISANDFUTURE'));
    expect(document, contains('unsupported calendar features'));
  });

  test('links real phone-theme and navigation evidence', () {
    final document = File('docs/timetable.md').readAsStringSync();
    for (final file in [
      'phone-light.png',
      'phone-dark.png',
      'home-preview.png',
      'room-floorplan.png',
      'maps-route.png',
      'restart.png',
    ]) {
      expect(document, contains(file));
      expect(File('docs/timetable-evidence/$file').existsSync(), isTrue);
    }
  });
}
