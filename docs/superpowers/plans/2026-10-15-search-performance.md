# Large Search Results Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reduce measured work when a large room-search result set is rendered or the existing screen rebuilds, while preserving every valid result and its navigation identity.

**Architecture:** A profile-mode app entry point repeatedly renders a deterministic 648-room result using the actual `SearchScreen` and records UI/raster `FrameTiming`. The implementation uses a one-result presentation cache and a builder-backed list so the screen does not recreate all result models and row widgets on each rebuild. The earlier floor-painter path-cache experiment remains rejected and is documented as a measured no-go.

**Tech Stack:** Flutter 3.24.5 / Dart 3.5.4, Flutter `ListView.builder`, Android 14 emulator.

**Spec:** User request in this thread, “Campus Navigator – Systematische Performance-Optimierung von version 1.4”; repository constraints in `AGENTS.md`.

## Global Constraints

- Preserve existing search results, order, room IDs, favorites, and navigation behavior.
- Do not alter floorplan rendering, global app configuration, or unrelated navigation.
- Do not touch other worktrees; work on `optimization/performance` from `v1.4.0-rc1`.
- Keep caches bounded to the current `SearchResult` object and screen lifetime.
- Do not report emulator results as physical-device or release performance.
- Keep the change only if the same benchmark improves beyond run-to-run variation and functional/visual checks pass.

## Review Focus

- Invalid room/building identifiers remain omitted; test mixed valid/invalid results.
- A 648-room set remains scrollable and opens the last room ID; reuse the existing regression fixture.
- Rebuilding the same `SearchResult` reuses presentation models; replacing it invalidates the one-entry cache.
- Loading, failure/retry, empty, assistant text, rooms/buildings headings, and “load all” retain their current order.
- Search list rows stay lazy and do not change their visible theme or Campus Identity styling.

---

### Task 1: Reproducible search-list benchmark

**Files:**
- Create: `tool/performance/search_results_benchmark.dart`

**Interfaces:**
- Produces profile-mode UI/raster mean, P90, P99, and count of frames at or above 16.7 ms for repeated result rendering.

- [x] Build a deterministic 648-room `SearchResult`, inject it into the real `SearchScreen`, and avoid network requests.
- [x] Record three 240-frame baseline runs on `emulator-5560`, dropping 20 warm-up frames per run.
- [x] Record emulator process PSS once after the same benchmark state and document that this synthetic search workload excludes backend latency.

### Task 2: Bounded result presentation and lazy rows

**Files:**
- Create: `lib/ui/search_result_presentation.dart`
- Modify: `lib/ui/screens/search_screen.dart`
- Create: `test/regression/search_result_presentation_test.dart`
- Modify: `test/regression/search_favorites_widget_test.dart`

**Interfaces:**
- `SearchResultPresentationCache.forResult(SearchResult) -> SearchResultPresentation`; it keeps only the most recent result identity and its valid room/building view models.

- [x] Write failing tests for same-result memoization, new-result invalidation, invalid-ID filtering, and a `SliverChildBuilderDelegate` for the 648-row search list.
- [x] Convert the results branch to `ListView.builder`, calculating section offsets without creating one row widget per result during `build`.
- [x] Run the focused tests and existing search/list regression cases.
- [x] Run the exact same profile benchmark for three after-change repetitions and compare medians plus ranges with baseline; revert this change if the improvement is not separated from run-to-run variation.

### Task 3: Verification, APK, and report

**Files:**
- Create: `docs/performance-optimization-v1.4.md`

**Interfaces:**
- The report records device class, OS, Flutter version/build mode, floor-renderer candidate rejection, search benchmark results, memory observations, APK size/hash, tests, and limitations.

- [x] Run `flutter analyze --no-pub`, `flutter test --no-pub`, existing floor-plan goldens, and `flutter build apk --debug --no-pub`.
- [x] Verify the final APK exists and record its SHA-256 and size.
- [x] Inspect `git diff --check`, confirm only the plan, report, benchmark, search presentation, and focused tests changed, then commit on `optimization/performance`.
- [x] Leave physical-device Profile/DevTools, real-plan visual comparison, and real-device memory profiling open because no physical Android device or private APB/BEY fixtures are available.

## Decisions and deferred minor concerns

- Reject the floor-path cache: the three-run UI timing ranges overlapped, the candidate did not reduce over-budget frames, and one PSS sample rose by 2.2 MB. Real APB/BEY data could change this conclusion, so physical profiling remains open.
- Retain the one-result search presentation cache and lazy list: the 648-result Profile benchmark showed separated UI mean/P90/P99 run ranges while the functional test still opens the last room by ID.
- Keep the standalone Profile benchmark entry point because no physical device was connected; its explicit limits are documented in docs/performance-optimization-v1.4.md.
- Map gestures, real campus tile loading, JSON/API latency, and native end-to-end timings were not measured. There is no integration_test directory; these remain follow-up validation rather than evidence for additional changes.