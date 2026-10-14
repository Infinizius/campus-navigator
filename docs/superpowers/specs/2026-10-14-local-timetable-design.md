# Local Timetable Integration Design

## Goal and constraints

Add a private, local timetable flow to Campus Navigator: import an `.ics` file, see today's and upcoming classes, open a verified room floor plan, or request walking directions to a verified building. Preserve the existing floor-plan renderer and current Campus Identity navigation patterns. Do not request calendar permissions, upload calendar data, or send event titles/descriptions to the TU service or Google Maps.

Implementation starts from the stable `v1.3.0` tag on the existing checkout's `feature/timetable` branch. The pinned toolchain is Flutter 3.24.5 / Dart 3.5.4. `teno_rrule` 0.0.10 requires Dart 3.5, so the package constraint will be raised to `>=3.5.0`.

## Architecture

### Import and parsing

Use Android's document picker through `file_picker` with the `.ics` extension filter and byte loading. No calendar permission is added and no source file is retained. Reject files over 5 MiB, calendars with no usable VEVENTs, malformed component/property structure, missing UID/DTSTART/DTEND (or supported DURATION), duplicate master UIDs, and unsupported recurrence constructs before changing saved data.

Use `icalendar_parser` 2.1.0 for iCalendar structure and standard VEVENT properties, with a strict adapter that preserves property parameters and raw date values needed for `RECURRENCE-ID`, `TZID`, all-day dates, and repeated `EXDATE` lines. Initialize the bundled IANA timezone database before parsing any timezone-aware value. Use `teno_rrule` 0.0.10 for a single RRULE per series and expand only bounded display windows. The adapter groups detached VEVENT overrides by UID and original recurrence identity; a cancelled override suppresses that slot, and a moved override replaces its original slot at the new time.

Supported recurrence input is one RRULE per UID plus any number of EXDATE values and detached RECURRENCE-ID overrides without `RANGE=THISANDFUTURE`. `RDATE`, multiple RRULEs, custom/unrecognized TZIDs, and recurrence values the adapter cannot validate are rejected with a user-visible explanation. UTC, date-only all-day events, floating campus-local times, and recognized IANA TZIDs including `Europe/Berlin` are supported. The bundled IANA database supplies DST transitions. An embedded VTIMEZONE is accepted only for a recognized IANA TZID when its transition rules match that database for the event range; mismatches and custom zones are rejected. `COUNT` and inclusive `UNTIL` behavior are normalized in the adapter and covered by tests rather than delegated blindly to library window semantics. Recurrence expansion is capped to a bounded query window and a defensive occurrence limit.

Each imported series retains UID, summary, optional description, original location, typed DTSTART/DTEND or duration, TZID/date-kind, one normalized RRULE, EXDATE identities, and detached overrides. Dates are stored in a versioned local document, not as an indefinitely expanded list. Occurrences are generated for today, the selected week, and the next-event preview.

### Room resolution and navigation

An independent `RoomResolver` receives only the VEVENT `LOCATION` value. It may query the existing TU room search service with that value, validates candidates with `SavedPlace.tryFromSearch`, and returns one of `uniqueRoom`, `ambiguous`, `buildingOnly`, or `unresolved`. A unique automatic assignment requires one exact normalized venue match using the search result's room name, sub-name, and detail; fuzzy or room-only matches do not become navigation targets. Manual selection uses existing search results and stores the canonical `SavedPlace.identifier`, never a constructed route.

Persist a manual mapping by `(UID, normalized LOCATION)`. Preserve it on updates only while the normalized LOCATION is unchanged. Room navigation uses `loadSavedPlace` and therefore keeps its exact selected-room identity check. Walking navigation resolves the assigned room's building code against `CampusCatalog` and opens only the building's validated `routeUri`; the URL contains the building coordinate and walking mode, never event text.

### Persistence and import management

Use a dedicated `TimetableStore` and secure-storage key containing one versioned JSON snapshot. Match the existing `PlaceStore` pattern: inject read/write functions for tests, serialize mutations, publish in-memory state only after a successful write, and leave the old document untouched after read/parse/write failure.

Import offers **Update** and **Replace**. Update upserts incoming masters by UID, retains absent masters, replaces their overrides, and keeps a manual room assignment only when the normalized LOCATION is unchanged. Replace atomically swaps the active schedule. Reimport is idempotent. Clear removes all imported events and manual mappings after confirmation. Parsing and validation finish before either import mode commits.

### User interface and integration

Add a third lazy Home destination, **Timetable**, beside Search and Campus in both `NavigationBar` and `NavigationRail`, preserving the current search/map tab state. Add an independent `NextEventPreview` widget to the empty-query Search home. The timetable screen shows today's events, next event, and a date-selectable week list with title, local start/end, all-day state, building/room, room action, and safe walking action. Unresolved venues remain readable and offer manual assignment.

Keep layouts compact, responsive, accessible, localized through ARB, and themed with the existing Campus Identity tokens. The screen accepts injected store, picker, resolver, floor loader, and route launcher seams so widget tests remain deterministic. Do not change floor-plan painting or geometry.

## Failure behavior and privacy

An invalid or unsupported file reports the issue and leaves the active timetable byte-for-byte unchanged. A failed persistence write does not show the import as committed. Unknown or ambiguous rooms never open a guessed floor or route. Search may transmit only the venue string; event summary and description stay local. The source ICS bytes are discarded after parse/commit. No ZIH login, cloud service, or calendar permission is involved.

## Verification and documentation

Use synthetic calendars and fake TU search results only. Unit tests cover single and all-day events, recurring events, multiple EXDATEs, moved/cancelled overrides, Berlin DST, malformed/unsupported input, `COUNT`/`UNTIL`, and import idempotence. Resolver tests cover the documented APB/BEY/BAR forms plus ambiguity/building-only/unknown results. Store tests cover update/replace/clear, manual-mapping retention, failures, and a new store instance loading the saved snapshot. Widget tests cover navigation destinations, preview, timetable actions, unresolved/manual mapping states, and light/dark themes.

Add `docs/timetable.md` with the supported ICS matrix, recurrence limits, location-only resolution policy, manual mapping/update behavior, local storage/privacy behavior, and import troubleshooting. Verify with `flutter analyze`, `flutter test`, an Android debug APK build, and an emulator import/navigation walkthrough when the local emulator is usable. Save phone screenshots in light and dark themes and deliver the APK path, screenshots, documentation, and any environment limitations.
