# MOBIbike integration

Worktree: `F:\apps\Codex\campus-alltag`, branch `feature/campus-alltag`.

## Requirements and steps

- [x] Verify Dresden discovery, actual station/vehicle fields, timestamps, update interval, license and rental links live.
- [x] Implement injected GBFS client, validated station and bike parsing, availability filtering and station/bike deduplication; add controlled parser and network tests.
- [x] Add initially disabled MOBIbike map layer with zoom-dependent clustering, selectable details, source timestamp and provided rental links.
- [x] Refresh only while layer, map and application are active; respect feed TTL. Preserve old data visibly as stale after failure, support retry.
- [x] Add meaningful state/widget tests. Full suite: 262 passed, 26 skipped. Analyzer: 36 pre-existing info-only diagnostics, no errors/warnings or MOBIbike diagnostics. Android debug APK built.
- [x] Verify map interactions, light/dark themes and error states with ADB and screenshots, without Computer Use. See `docs/qa/mobibike/README.md`.

## Live evidence (2026-11-11)

Discovery: https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_dx/gbfs.json

The German discovered feeds return version 2.3 and TTL 60 seconds. System information names MOBIbike and declares `license_id: CC0-1.0`. Sample response contained 547 station records/statuses and 1794 bike records. Stations have boolean `is_installed`/`is_renting`, integer counts and `last_reported`. Bikes have boolean `is_reserved`/`is_disabled`; station-bound bikes additionally have `station_id` and must not be counted as free-standing markers. Station rental URIs include `https://app.nextbike.net/station?id=...` and `https://nxtb.it/p/...`.

Preserve existing search, timetable, Mensa, map buildings and floorplans. No automatic location request or background refresh.
