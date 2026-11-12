# Mensa plans design

## Goal

Make the official Studentenwerk Dresden menu API useful from Campus Navigator: users can choose a Dresden canteen, save a favorite, see today's dishes and browse dates for which the API publishes data.

## Data source

Use `https://api.studentenwerk-dresden.de/openmensa/v2`, which the Studentenwerk documents as its JSON REST API, mostly compatible with OpenMensa v2. Load canteens from `/canteens`, published dates from `/canteens/{id}/days?start=YYYY-MM-DD`, and a day's dishes from `/canteens/{id}/days/{date}/meals`. Real responses contain canteen coordinates, a boolean `closed` on each published day, and meals with category, notes, optional prices and a `soldout` field. Price roles are localized strings in the live Dresden API.

## User behavior

- Keep the current three main navigation destinations. Add a compact `Mensa heute` entry to the search home and open a dedicated detail screen.
- On first use, require a canteen choice before requesting its menu. Persist the favorite canteen id locally.
- List available dates from the source. Default to today's date; let users select other published dates.
- Distinguish closed days, no published menu, loading and failed requests. Offer retry on failure.
- Persist the last successfully fetched menu by canteen and date, with retrieval time. If refresh fails, show that matching cached menu as stale with its fetch time.
- Show categories, all returned prices, notes and sold-out state. Show vegetarian/vegan filters only when the source explicitly labels a meal (`Menü ist vegetarisch` or `Menü ist vegan`, case-insensitive); do not infer allergen properties.
- Offer directions through the existing map launcher when the API provides valid coordinates.

## Constraints

- No server, background refresh, login, or third-party proxy.
- Inject API client and local-store abstractions so tests use controlled responses and do not require platform plugins.
- Keep all existing home and navigation features and floor plans unchanged.
- Localize the feature in German and English; use the project's existing English fallback strategy for other supported locales.

## Acceptance

Parser and service tests cover live response shape, missing prices, source dietary labels, closed and unavailable days, request failures, and favorite/menu persistence. Widget tests cover initial selection, loading, dishes, filters, cache fallback, closed/no-plan/error states, and retry. Run `flutter analyze`, `flutter test`, build Android APK, and inspect the feature in light and dark emulator themes when available.
