# MOBIbike acceptance — 2026-11-11

## Grouping refinement

Groups follow marker overlap in screen space (40 × 28 logical pixels including spacing), with a maximum pairwise geographic distance of 100 m. They separate as soon as enough screen space is available. Empty stations are hidden below zoom 16. A group uses the layers icon and an actual member position instead of a synthetic midpoint; selecting it fits all its locations into the viewport (maximum zoom 18). At zoom 18 and above, remaining overlapping locations can be selected from a list.

Below zoom 15, visible markers use 28 × 20 logical pixels; closer views use 36 × 24. The 44 × 44 input target remains. Final ADB screenshots confirm less clutter in the overview and readable individual markers on campus. A headless instance of the existing test AVD was started because the original emulator had been closed; it was stopped again after the screenshots.

Regression tests cover distant bikes, chained neighbors, screen-space separation, empty station filtering and order stability. Full suite after this refinement: 266 passed, 26 skipped; analyzer remains at 36 existing info diagnostics, no warnings/errors; APK rebuilt and installed. Earlier ADB screenshots show the previous 60 m policy; the balanced policy is recorded in `balanced-overview.png` and `balanced-campus.png`.

Implemented in the isolated `feature/campus-alltag` worktree. Source: the official Dresden nextbike GBFS discovery and its discovered feeds, license CC0-1.0.

## Automated evidence

- Full Flutter suite: 262 passed, 26 skipped.
- Seven focused MOBIbike tests cover valid/invalid/stale records, station/bike deduplication, discovery-provided URLs, HTTP failure, opt-in, TTL, inactive map, app background, retained stale data and recovery.
- Existing floor navigation regression additionally verifies that the underlying bicycle layer is inactive while a floorplan covers it and active again after return. This failed before the visibility correction and passed afterward.
- `flutter analyze --no-pub`: 36 existing info-level lints; no warnings/errors and no MOBIbike diagnostics.
- `flutter build apk --debug --no-pub`: Android debug APK built.
- Independent read-only review identified the covered-map lifecycle gap; correction was independently checked. No remaining material findings.

## Live emulator evidence

All interaction used ADB commands and direct emulator screenshots. Computer Use was not used.

- [Initially disabled](map-off.png): no bicycle layer until explicitly enabled.
- [Dark map](map-dark.png) and [light map](map-light.png): real nextbike availability and source timestamp.
- [Details](details-dark.png): available count, timestamp, source and rental action. Only a supplied, validated nextbike HTTPS link is offered; no rental was completed.
- [Lower zoom](clusters-light.png): nearby markers grouped with summed availability; selection zooms in.
- [Offline](offline.png): emulator Wi-Fi/mobile data disabled, existing markers retained with explicit stale-data warning, timestamp and retry.
- [Small display](small-light.png): 320 × 568 dp, network restored and retry successfully loads a newer timestamp.

Emulator network switches (both originally enabled), physical resolution (1080 × 1920 at density 420) and dark map preference were restored after the checks. Public availability is advisory and may change before reaching a bicycle. No new location action or permission is introduced.
