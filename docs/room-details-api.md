# Room details data contract

The room detail panel combines two public data sources for a numeric room ID
already present as the final segment of the selected `BuildingPageData` route:

- `GET https://navigator.tu-dresden.de/raum/{roomId}?language={locale}` for
  human-readable room and building fields.
- `GET https://navigator.tu-dresden.de/api/0.1/roominfo/{roomId}` for the
  structured room name and adjacent door/room identifiers.

The service validates room IDs as six digits, a dot, and four digits before it
makes a request. It serves fresh cached responses according to the existing
configured cache duration, refreshes expired entries, and falls back to an
existing non-empty cached response if the refresh encounters a network error,
HTTP 5xx, or malformed JSON. A cache miss requires a successful HTTP 200
response. Other failures are surfaced to the UI, which offers retry.

## Field handling

The localized room page uses German or English labels; the parser and fixture
set cover both label sets. The sampled room `325301.0010` has API name `151`,
one door connecting it to `325301.0032`, and page fields for building part,
building number `3253`, floor `floor 1`/`Etage 1`, 128 places, remark
`mobile Liege`, and a room usage description.
Room `325301.0032` is named `151C` and has an empty `doors` array. Room details
fixtures live in `test/fixtures/room_details/`.

The JSON API's `accessibility` and `doorplate` parameters returned Java object
identity strings in the sampled response. Those values are represented as
unknown and are not shown. API `type`, `routing`, `empty`, and door location
values are not presented as user-facing claims; the integer type code has no
verified user-facing meaning. The sampled room page's accessibility section
had no accessible room-specific text. Optional HTML values retain three states
in the model: absent, explicit `NO_INFO`/unknown, and a value. Only non-empty
known values are displayed.

The JSON fixtures are captured response payloads. The German and English HTML
fixtures are representative parser fixtures assembled from fields visible on
the official room page; they are not captured full page responses. If the site's markup
changes, update that fixture from a reviewed public page sample and extend the
parser tests before changing field extraction.

## Occupancy and authentication

The detail service does not load or infer occupancy. The existing occupancy
flow remains separate and uses the app's TU Dresden/ZIH login path. The public
room page indicates room schedules are behind institutional authentication;
the app must not bypass that access control or label a room available without
current authenticated schedule data.

For later schedule work, keep the public `RoomDetailsService` independent from
occupancy. An authenticated schedule provider can wrap the existing
`postLogin`/`getRoomPlan` flow and return schedule rows with their room ID and
time range. The UI should distinguish login-required, no schedule returned,
and a schedule with a stated retrieval time; it should never infer current
availability from room type, `empty`, or a stale schedule cache.

## Favorites and integration

Favorite room IDs are stored as a JSON string list in secure storage under
`FavoriteRooms`. Only canonical numeric IDs are retained; malformed storage
loads as an empty set. The existing `BuildingScreen` remains the only detail
surface: phone layouts use its draggable sheet, while wider layouts show the
same detail content in a side panel. Connected-room actions reuse the existing
floorplan route prefix with the destination numeric ID. The floorplan renderer
is unchanged; its canvas receives the width available beside the tablet panel.

## Verification and screenshots

`flutter analyze`, `flutter test`, and an Android debug APK build were run for
this feature. The full analyzer still reports pre-existing repository issues:
the Android and iOS widget-test entry points import missing platform packages,
plus existing diagnostics outside the room-details files. The feature tests
passed.

Phone interaction was tested in an Android 14 API 34 emulator: the live search
opened room `325301.0010`, the details rendered from the public page/API, the
favorite control toggled, and the connected-room chip opened `325301.0032`.
Light mode was captured on the phone; light and dark modes were captured in a
tablet-width landscape viewport. The tablet viewport was configured at
1920x1080 and 240 dpi on the Pixel 2 AVD, so it verifies the responsive tablet
layout but is not a physical tablet test. The screenshots and capture details
are in `docs/screenshots/`.
