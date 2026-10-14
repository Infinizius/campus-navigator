# Performance Report — Campus Navigator 1.4

- **Date:** 2026-10-15
- **Base:** v1.4.0-rc1, commit 02217fe2710a02345721b0d96f5b36a0a1a0c934
- **Experiment:** branch optimization/performance, isolated worktree

## Assessment

The only retained runtime change is in the large search-results list. On a deterministic 648-room local workload, repeated SearchScreen rebuilds used substantially less UI-thread time after the change. This is an emulator Profile-mode result for a synthetic workload; it does not establish general app, network, physical-device, or Release performance.

A separate floor-painter cache candidate did not show a stable improvement and was reverted. The floor-plan renderer and campus-map implementation remain unchanged.

## Device and build modes

- Available devices: two online Android emulators (emulator-5558 and emulator-5560) and two offline emulator instances; no physical Android device was attached.
- Measurements used emulator-5560: Android 14, sdk_gphone64_x86_64, 1080 × 1920 at 420 dpi.
- Toolchain: Flutter 3.24.5, Dart 3.5.4, DevTools 2.37.3.
- Frame benchmarks ran in Flutter Profile mode. The installable artifact and launch comparison used Debug mode.
- No Release-mode performance result or DevTools timeline/CPU trace was collected. Real-device Profile-mode analysis remains open.

## Findings and retained change

The previous search results branch converted every room/building into a SavedPlace and built a Widget for every row on each screen build. The result data is unchanged between repeated screen rebuilds, so this work repeated presentation conversion and created off-screen rows on the UI isolate.

The experiment now retains the converted presentation models for only the current SearchResult object and SearchScreen lifetime, and uses ListView.builder to build visible rows lazily. Ordering, identifiers, details, invalid-ID filtering, headings, loading/error states, retry, and load-all behavior are preserved. Regression coverage checks cache identity/invalidation, invalid identifiers, the builder delegate, explicit assistant/room/building section order, and opening the last result in the existing 648-result flow.

Code inspection found existing reuse for campus-map polygon data. No measured map bottleneck justified changing that cache. The floor painter reconstructs geometry and label objects during paint, but the measured synthetic workload did not justify retaining a cache.

## Search benchmark

The benchmark renders the real SearchScreen with the same synthetic local SearchResult containing 648 valid room identifiers. It repeats the same query every 16 ms, discards 20 warm-up frames, then records 240 FrameTiming samples per run. Three runs were collected before and after on the same emulator. The workload excludes API/network latency and does not model every user interaction.

Values below are medians across the three runs. Frame durations are milliseconds; a frame is counted over budget if either UI build or raster duration reaches 16.667 ms.

| Metric | Before | After | Change |
|---|---:|---:|---:|
| UI build mean | 5.274 | 2.134 | −59.5% |
| UI build P90 | 6.293 | 3.097 | −50.8% |
| UI build P99 | 15.194 | 4.053 | −73.3% |
| Raster mean | 2.509 | 2.748 | +0.239 ms |
| Raster P90 | 3.002 | 3.354 | +0.352 ms |
| Raster P99 | 4.901 | 4.554 | −0.347 ms |
| Frames at/over budget | 3 / 720 | 0 / 720 | 3 fewer |

The baseline-to-after run ranges did not overlap for UI mean, P90, or P99. Raster mean and P90 rose slightly in absolute terms but stayed below 3.4 ms at the median. No after-run frame exceeded the 16.667 ms budget. The measured change is limited to this repeated large-results workload.

After the benchmark recorder was changed to unregister its timing callback when the 240 samples finish, one separate Profile-mode smoke run recorded UI mean/P90/P99 of 2.276/3.347/4.751 ms and raster mean/P90/P99 of 2.762/3.326/7.061 ms, with 0/240 frames over budget. This lifecycle check is not included in the three-run comparison above.

Individual run summaries (all durations in ms):

| Version | Run | UI mean / P90 / P99 | Raster mean / P90 / P99 | Frames at/over budget |
|---|---:|---:|---:|---:|
| Baseline | 1 | 5.274 / 6.338 / 15.194 | 2.669 / 3.314 / 13.158 | 0 / 240 |
| Baseline | 2 | 5.390 / 6.293 / 23.398 | 2.370 / 2.789 / 4.901 | 3 / 240 |
| Baseline | 3 | 4.959 / 6.264 / 7.438 | 2.509 / 3.002 / 3.997 | 0 / 240 |
| After | 1 | 2.134 / 3.097 / 4.065 | 2.751 / 3.354 / 4.554 | 0 / 240 |
| After | 2 | 2.065 / 2.962 / 3.771 | 2.748 / 3.303 / 7.057 | 0 / 240 |
| After | 3 | 2.155 / 3.156 / 4.053 | 2.716 / 3.354 / 4.191 | 0 / 240 |

### Memory observations

Two emulator process-PSS snapshots were taken in the benchmark state per version:

- Before: 109,378 KB and 114,002 KB.
- After: 105,760 KB and 110,566 KB.

Both paired observations were lower after the change by about 3.4–3.6 MB. The sample is small and emulator PSS is noisy, so this is directional evidence only. A separate single Debug-home snapshot was 263,022 KB and is not a before/after comparison.

## Rejected floor-painter candidate

A bounded Path reuse experiment was measured on a synthetic 320-room-and-label plan with the existing MapPainter. Three Profile-mode runs per version used the same 20 warm-up and 240 measured frames.

| Metric | Baseline median | Candidate median | Result |
|---|---:|---:|---|
| UI build mean | 7.144 ms | 6.910 ms | −3.3%; run ranges overlap |
| UI build P90 | 8.266 ms | 8.018 ms | −3.0%; run ranges overlap |
| UI build P99 | 9.883 ms | 9.367 ms | −5.2%; run ranges overlap |
| Raster mean | 2.521 ms | 2.504 ms | No material change |
| Frames at/over budget | 0 / 720 | 1 / 720 | No improvement |
| One PSS sample | 86,799 KB | 89,043 KB | Candidate +2.2 MB |

The performance ranges overlapped, the candidate did not reduce over-budget frames, and its one memory sample was higher. The Path cache and its test were removed; painter.dart has no final diff.

The individual UI ranges also overlap: mean 7.045–7.402 ms baseline versus 6.868–7.095 ms candidate; P90 7.997–8.893 versus 7.923–8.239 ms; P99 9.605–12.000 versus 9.182–10.678 ms.

## Startup observations

RC and optimized Debug APKs were installed alternately on the same emulator. Each process-cold sample used force-stop followed by am start -W; app data was retained and the OS file cache was warm. Each version was measured three times:

- RC total launch times: 1,666 / 1,290 / 1,338 ms; median 1,338 ms.
- Optimized total launch times: 1,637 / 1,274 / 1,265 ms; median 1,274 ms.
- Warm re-open: 0 ms TotalTime for both versions.

The small difference is within the variability of these Debug-mode emulator samples and is not attributed to the search-list optimization.

## Verification and regression checks

- Full Flutter test suite after review fixes: 255 passed, 26 skipped, 0 failed. The suite includes search/favorites/history, room details, timetable, campus-map widgets, settings persistence, network/cache and offline-error coverage, plus floor-plan golden tests.
- Floor-plan goldens passed for the existing synthetic phone and tablet light/dark samples. The renderer source is unchanged.
- flutter analyze --no-pub reported 36 info-level lints and no warnings or errors. Its exit code is non-zero because the analyzer reports these info diagnostics.
- flutter build apk --debug --no-pub succeeded.
- The final APK passed apksigner verification (v1 and v2) and zipalign verification, installed and launched on emulator-5560.
- The first incremental APK was 220,457,333 bytes because its ZIP contained 21.5 MB of generated padding. A clean build in this isolated worktree removed the excess; this was a generated-artifact issue, not an application resource increase.

## APK

- File: F:/apps/Codex/campus-navigator-performance/build/app/outputs/flutter-apk/app-debug.apk
- Size: 198,918,648 bytes
- SHA-256: 7A4AC09745E78296AEFEA340FFCB996A42A04D5D50A42A7A0A131C62666119DA
- RC APK size for comparison: 198,912,212 bytes

This is a signed Debug APK using the Android debug certificate. It is installable for evaluation and is not a production Release APK.

## Open work and recommendation

- Repeat Profile-mode measurements on a physical Android device and collect DevTools UI/raster timelines, CPU use, and memory while opening APB E069 and BEY 318, zooming/panning, changing floors, selecting rooms, using the campus map, and searching.
- Compare actual APB/BEY views before and after on phone light/dark and tablet landscape. No private APB/BEY plan fixtures were available in this worktree, so this visual comparison was not run here.
- The full Flutter widget/API suite exists; there is no integration_test directory. Native end-to-end interaction timing was not collected.
- Exercise cold data/cache launch and real network search separately from the synthetic screen benchmark; the current startup measurements retained app data and had warm OS file cache.
- Continue looking for measured map-tile, JSON parsing, and API latency costs before changing those paths.

**Recommendation:** Keep the narrowly scoped search-list optimization in the experimental branch. It has a repeatable UI-thread improvement on the measured large-result workload with existing functional and golden tests passing. Treat it as a targeted optimization, not evidence that all Android navigation is smooth. Physical-device Profile/DevTools validation and real-plan visual comparison remain necessary before making broader performance claims.
