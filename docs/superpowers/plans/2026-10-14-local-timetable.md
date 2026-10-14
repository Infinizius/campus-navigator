# Local Timetable Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import a private local ICS timetable, show upcoming events, and navigate only to verified campus rooms/buildings.

**Architecture:** Parse ICS into versioned event-series models, expand bounded occurrences with `teno_rrule`, resolve only LOCATION through existing TU search, and persist one local snapshot. Integrate a third Home destination and independent next-event preview using existing Campus Identity and navigation APIs.

**Tech Stack:** Flutter 3.24.5 / Dart 3.5.4, pinned `icalendar_parser` 2.1.0, `teno_rrule` 0.0.8, `timezone` 0.10.1, `file_selector` 1.0.3, Flutter secure storage, Flutter test.

**Spec:** `docs/superpowers/specs/2026-10-14-local-timetable-design.md`

## Global Constraints

- Work only in the existing `campus-navigator` checkout on `feature/timetable`, based on `v1.3.0`; never modify `master` or sibling worktrees.
- Retain the app's Dart lower bound `>=3.0.0` and the pinned Flutter 3.24.5 / Dart 3.5.4 toolchain.
- Never ask for calendar permission; never persist source ICS bytes or send SUMMARY/DESCRIPTION outside the device.
- Send only LOCATION to room search; use canonical, validated `SavedPlace.identifier` for floor navigation.
- Do not modify floor-plan rendering, room geometry, or room identity rules.
- Validate the complete import before committing; malformed input or failed writes leave the existing snapshot intact.
- Use synthetic event data and synthetic/fake room-search results in all tests.

## Review Focus

- COUNT series queried after their DTSTART must not restart their count — test `count_is_not_restarted_by_late_window` in Task 2.
- UNTIL is inclusive in RFC5545 but `teno_rrule.between` is end-exclusive — test `includes_occurrence_equal_to_until` in Task 2.
- Berlin wall-clock classes must retain their local start time through DST, and embedded VTIMEZONE rules must match IANA data — test `berlin_weekly_series_keeps_wall_time_across_dst` and `rejects_mismatched_iana_vtimezone` in Tasks 1–2.
- Repeated EXDATE properties and detached overrides must not leave a cancelled/moved duplicate — test `combines_repeated_exdate_lines` and `applies_moved_and_cancelled_overrides` in Tasks 1–2.
- Similar room aliases and write failures must never create guessed navigation or lose saved events — test `ambiguous_room_is_never_auto_assigned` in Task 3 and `failed_import_keeps_committed_snapshot` in Task 4.

---

### Task 1: ICS value model and strict calendar parser

**Files:**
- Create: `lib/api/timetable/timetable_model.dart`
- Create: `lib/api/timetable/ics_parser.dart`
- Create: `lib/api/timetable/ics_time.dart`
- Modify: `pubspec.yaml`, `pubspec.lock`
- Test: `test/timetable/ics_parser_test.dart`

**Interfaces:**
- Produce `TimetableSeries`, `TimetableOverride`, `IcsTemporal`, and `ParsedTimetable` with JSON-ready primitive fields.
- Produce `ParsedTimetable parseIcsCalendar(String input)`; throw `IcsImportException` with a localized-safe error code and no source excerpt.
- Preserve UID, summary, optional description/location, DTSTART/DTEND or DURATION, VALUE/TZID, one RRULE, all EXDATE values, and detached RECURRENCE-ID overrides.
- Parse date-only, floating campus-local, UTC, and recognized IANA date-times. Initialize timezone data once. Validate embedded VTIMEZONE observances against the bundled zone for the event's DTSTART through the latest event/query horizon; reject custom or mismatched definitions.

- [ ] **Step 1: Add exact dependencies `file_selector: 1.0.3`, `icalendar_parser: 2.1.0`, `teno_rrule: 0.0.8`, and `timezone: 0.10.1`, retaining the SDK floor at `>=3.0.0`. Run `flutter pub get` and confirm only the intended package/configuration files changed.**
- [ ] **Step 2: Add parser characterization tests** named `parses_single_event_and_unescapes_text`, `parses_all_day_exclusive_end`, `parses_duration_event`, `preserves_tzid_and_recurrence_identity`, `combines_repeated_exdate_lines`, `rejects_duplicate_uid_and_incomplete_event`, `rejects_unknown_tzid`, `rejects_rdate_multiple_rrules_and_range`, and `rejects_mismatched_iana_vtimezone`; run them and confirm the expected missing parser behavior fails.

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/ics_parser_test.dart --no-pub`

Expected: failing parser-behavior assertions for the unimplemented timetable parser; no package-resolution or test-harness errors.

- [ ] **Step 3: Implement bounded content-line/component validation and typed event conversion.** Use `icalendar_parser` for supported iCalendar parsing and a focused adapter for property parameters, RECURRENCE-ID, repeated EXDATE, and exact date semantics.
- [ ] **Step 4: Run the parser tests and confirm all nine named behaviors pass.**
- [ ] **Step 5: Commit** as `feat: parse local timetable calendars`.

### Task 2: Timezone-aware recurrence and exception expansion

**Files:**
- Create: `lib/api/timetable/recurrence_expander.dart`
- Test: `test/timetable/recurrence_expander_test.dart`

**Interfaces:**
- Produce `List<TimetableOccurrence> expandTimetable(Iterable<TimetableSeries> series, DateTime begin, DateTime end)` with `begin` inclusive and `end` exclusive.
- Keep all-day values date-based; return timed occurrences with timezone-aware local values and the original TZID.
- Expand one RRULE via `RecurrenceRule.from` and `.between`; impose a maximum of 20,000 generated instances per series/window and surface overflow as `IcsImportException`.

- [ ] **Step 1: Write tests** named `expands_weekly_series`, `berlin_weekly_series_keeps_wall_time_across_dst`, `all_day_series_preserves_calendar_days`, `exdate_removes_matching_occurrence`, `applies_moved_and_cancelled_overrides`, `includes_dtstart_even_when_byday_excludes_it`, `count_is_not_restarted_by_late_window`, and `includes_occurrence_equal_to_until`.
- [ ] **Step 2: Run the recurrence tests and confirm each fails on the expected absent behavior.**

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/recurrence_expander_test.dart --no-pub`

Expected: failing occurrence assertions, with no test-harness errors.

- [ ] **Step 3: Implement the recurrence adapter.** Combine EXDATE values before filtering; for COUNT, enumerate from DTSTART then trim before exclusions; extend the query endpoint to include an UNTIL-equal instance then enforce UNTIL inclusively; add DTSTART according to RFC recurrence-set semantics; replace original slots with overrides and include moved overrides whose replacement time is in the requested window.
- [ ] **Step 4: Run both parser and recurrence test files; confirm all pass.**
- [ ] **Step 5: Commit** as `feat: expand timetable recurrence and exceptions`.

### Task 3: Venue resolver backed by existing search results

**Files:**
- Create: `lib/api/timetable/room_resolver.dart`
- Test: `test/timetable/room_resolver_test.dart`

**Interfaces:**
- Produce `RoomResolution` with status `uniqueRoom`, `ambiguous`, `buildingOnly`, or `unresolved`, plus validated candidates.
- Produce `RoomResolver({required Future<SearchResult> Function(String) search})` and `Future<RoomResolution> resolve(String location)`.
- Search with LOCATION only. Normalize Unicode, case, punctuation and separators; auto-assign only one exact alias match across validated result name, subName and detail. Never auto-assign a building-only or fuzzy match.

- [ ] **Step 1: Write tests** named `matches_apb_separator_variants`, `matches_full_building_name_and_room`, `matches_bey_and_bar_examples`, `ambiguous_room_is_never_auto_assigned`, `returns_building_only_without_room`, `returns_unresolved_for_unknown_room`, and `sends_location_only_to_search`.
- [ ] **Step 2: Run the resolver tests and confirm the expected absent resolution behavior.**

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/room_resolver_test.dart --no-pub`

Expected: failing resolution assertions, with no test-harness errors.

- [ ] **Step 3: Implement resolver using `SearchResult.searchAll` through the injected search, `SavedPlace.tryFromSearch`, and canonical result identifiers.**
- [ ] **Step 4: Run the resolver test file and confirm all seven behaviors pass.**
- [ ] **Step 5: Commit** as `feat: resolve timetable venues to campus places`.

### Task 4: Transactional local storage and import management

**Files:**
- Create: `lib/api/timetable/timetable_store.dart`
- Test: `test/timetable/timetable_store_test.dart`

**Interfaces:**
- Produce `enum TimetableImportMode { update, replace }` and `TimetableStore({Future<String?> Function()? read, Future<void> Function(String)? write})`.
- `load()`, `importCalendar(ParsedTimetable calendar, TimetableImportMode mode)`, `assignRoom(String uid, String normalizedLocation, SavedPlace room)`, and `clear()` return success booleans; expose immutable event/mapping state and loading/saving/failure state.
- Persist a version-1 JSON snapshot at `Timetable.v1` using injected functions and `Storage.Shared.storage` by default.
- Update merges by UID and retains absent series. It preserves a manual mapping only when normalized LOCATION is unchanged. Replace atomically drops previous events/mappings; clear drops all. Repeated update is idempotent.

- [ ] **Step 1: Write tests** named `round_trips_after_new_store_instance`, `update_upserts_without_duplicates_and_keeps_absent_events`, `replace_discards_old_events_and_mappings`, `preserves_mapping_only_for_unchanged_location`, `clear_removes_all_events_and_mappings`, `failed_import_keeps_committed_snapshot`, and `corrupt_document_is_not_overwritten`.
- [ ] **Step 2: Run the store tests and confirm expected absent persistence/import behavior.**

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/timetable_store_test.dart --no-pub`

Expected: failing persistence assertions, with no test-harness errors.

- [ ] **Step 3: Implement versioned serialization, queued snapshot commits, update/replace merge semantics, mapping retention, clear, and failure preservation.**
- [ ] **Step 4: Run the store test file and confirm all seven behaviors pass.**
- [ ] **Step 5: Commit** as `feat: persist timetable imports locally`.

### Task 5: Picker flow, timetable screen, navigation and preview

**Files:**
- Create: `lib/ui/components/next_event_preview.dart`
- Create: `lib/ui/screens/timetable_screen.dart`
- Modify: `lib/ui/screens/home_screen.dart`, `lib/ui/screens/search_screen.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/timetable/timetable_widget_test.dart`, `test/timetable/next_event_preview_test.dart`, relevant `test/regression/interaction_test.dart`

**Interfaces:**
- `NextEventPreview({required TimetableStore store, required ValueChanged<TimetableOccurrence> onTap})` is an independent empty-query search-home widget.
- `TimetableScreen({required TimetableStore store, CampusCatalog? catalog, Future<Uint8List?> Function()? pickIcsBytes, Future<BuildingPageData> Function(SavedPlace)? loadPlace, Future<bool> Function(Uri)? launchRoute, RoomResolver? resolver})` owns screen-only controllers and releases only dependencies it creates.
- HomeScreen owns or receives one shared `CampusCatalog` for the map and timetable. Add a third lazy `IndexedStack` destination in both existing navigation controls, without resetting Search/Map state.
- Floor actions use `loadSavedPlace` then `BuildingScreen`; walking uses only a matched building's `CampusFeature.routeUri` and existing external URL launcher.
- Use Flutter `file_selector` to filter `.ics`, read `XFile` bytes, reject >5 MiB, parse before asking Update/Replace, and commit only after complete validation. No calendar permission.

- [ ] **Step 1: Write widget tests** named `home_has_timetable_destination_on_phone_and_rail`, `search_home_shows_next_event_preview`, `preview_hides_when_no_upcoming_event`, `today_and_week_views_show_sorted_events`, `import_uses_ics_picker_and_offers_update_or_replace`, `invalid_import_preserves_schedule`, `room_action_opens_verified_place`, `maps_action_uses_verified_building_uri`, `unresolved_room_offers_manual_assignment`, and `timetable_uses_light_and_dark_theme_tokens`.
- [ ] **Step 2: Run both widget test files and confirm expected absent UI behavior.**

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/timetable_widget_test.dart test/timetable/next_event_preview_test.dart --no-pub`

Expected: failing widget assertions, with no test-harness errors.

- [ ] **Step 3: Implement the importer and compact Today/week list, add localized English/German copy, preview, and the minimal Home navigation integration.** Retain the shared catalog lifecycle and keep renderer files unchanged.
- [ ] **Step 4: Run the widget tests plus existing search, navigation, and Campus Identity regression tests; confirm all pass.**
- [ ] **Step 5: Commit** as `feat: add timetable navigation and preview`.

### Task 6: Support documentation, full verification and delivery evidence

**Files:**
- Create: `docs/timetable.md`
- Create: `docs/timetable-evidence/phone-light.png`, `docs/timetable-evidence/phone-dark.png`
- Artifact: `build/app/outputs/flutter-apk/app-debug.apk`

**Interfaces:**
- Document actual supported ICS properties and explicit rejection behavior, IANA/TZID behavior, recurrence limits, room resolver inputs/states, manual assignment, Update/Replace/Clear, privacy and troubleshooting.
- Capture emulator screenshots showing the timetable/next event in light and dark mode; keep synthetic event titles/locations in screenshots.
- No API, manifest, floor renderer, or room geometry changes beyond the previously specified integration.

- [ ] **Step 1: Write documentation assertions in `test/timetable/timetable_docs_test.dart`** for supported-feature names, privacy constraints, and unsupported recurrence errors.
- [ ] **Step 2: Run the docs test and confirm it fails because `docs/timetable.md` is absent.**

Run: `. .\tools\dev-env.ps1; $env:DART_SUPPRESS_ANALYTICS='true'; flutter test test/timetable/timetable_docs_test.dart --no-pub`

Expected: failing documentation assertions only.

- [ ] **Step 3: Write `docs/timetable.md` from implemented behavior and pass the documentation test.**
- [ ] **Step 4: Run `flutter analyze` and the complete `flutter test` suite; record all existing and new failures by name.**
- [ ] **Step 5: Run `flutter build apk --debug`; confirm the APK exists and validate it with `apksigner verify --verbose`.**
- [ ] **Step 6: Launch the available Android emulator, import a synthetic calendar, check today/week, open a synthetic verified room, check Maps handoff, and capture light/dark screenshots. If ADB remains blocked by the sandbox's socketpair restriction, record exact diagnostics and finish all other checks.**
- [ ] **Step 7: Commit** as `docs: document timetable import and support`.

## Execution Choice

Execute this plan inline with `superpowers:executing-plans`. The tasks share model and navigation interfaces and are sequentially dependent, so one implementer can preserve those contracts with per-task TDD and commits. Use the completed read-only parser audits as package evidence and a fresh whole-branch review after all tasks.
