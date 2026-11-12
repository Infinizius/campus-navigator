# Studentenwerk menu integration plan

> Execute inline using `superpowers:executing-plans`; tests follow TDD.

**Goal:** Add a useful daily Studentenwerk Dresden menu flow without changing the app's main navigation or existing campus features.

**Spec:** `docs/superpowers/specs/2026-11-11-mensa-design.md`

**Branch/worktree:** `feature/campus-alltag` in `F:\apps\Codex\campus-alltag`, isolated from the pre-existing `feature/timetable` checkout.

## Tasks

### 1. Menu data and official API

- [x] Add typed canteen, available-day and meal models with defensive JSON parsing.
- [x] Add injected client and endpoints for canteens, available dates and meals. Use a dedicated API base URL and timeout.
- [x] Test real field names, localized prices, optional prices, notes, source dietary labels, closed days, empty days, malformed data and HTTP errors first.

### 2. Local persistence and repository behavior

- [x] Add an injected local store for favorite canteen, last canteen list and fetched plans with retrieval timestamp.
- [x] Test favorite persistence and per-date cached plan round-tripping.
- [x] Return matching cached plans only after refresh failure; never disguise no-plan or closed responses as network failure.

### 3. Home entry and menu screen

- [x] Add `Mensa heute` to the search home and open a dedicated details screen.
- [x] Require a canteen selection the first time, persist a favorite, load published dates and default to today.
- [x] Render distinct loading, closed, no-plan, error/retry, cached/stale, and populated states.
- [x] Render categories, all prices, notes, sold-out state; source-confirmed vegetarian/vegan filters; and map directions when coordinates are valid.
- [x] Add localized strings and widget tests for the core states and interactions.

## Final verification

- [x] Run focused tests after each task, then full `flutter test` and `flutter analyze`. Final suite: 255 passed, 26 skipped. `flutter analyze` reports 36 info-only lint messages and no warnings or errors; Mensa files have no diagnostics.
- [x] Build Android debug APK and inspect the interaction in light and dark emulator themes. Live menu data and the vegan filter were verified in the emulator on 2026-11-11.
- [x] Review diff and report live data, verification, and any environment limitation.

## Delivered

- Android debug APK: `F:\apps\Codex\campus-alltag\build\app\outputs\flutter-apk\app-debug.apk`.
- The official Studentenwerk API was queried live. The emulator displayed the Mensa Brühl plan for 11.11.2026, including localized student/staff prices, notes and sold-out status; the vegan filter returned only meals with the source's explicit vegan note.
- A stale saved canteen ID is treated as no current favorite so the next first-use selection can replace it.
