# Local timetable import

Campus Navigator imports a local iCalendar (`.ics`) file and stores a compact
versioned timetable snapshot on the device. The original file is read into
memory and discarded after import. Importing does not request calendar
permission.

## Import and privacy

Open **Timetable** and choose **Import**. The Android file picker filters for
`.ics` files. Files larger than 5 MiB, invalid UTF-8, incomplete calendars,
unsupported calendar features, and invalid event times are rejected before
the saved timetable is changed.

After validation, choose **Update** or **Replace**:

- **Update** upserts imported event series by their ICS `UID`; series absent
  from the file remain. Reimporting the same series does not create duplicates.
- **Replace** saves only the imported series and clears the previous room
  assignments.
- **Clear** removes all imported series and manual room assignments after a
  confirmation.

The active series and room assignments are saved together as one versioned
snapshot through the app's secure storage. A failed write leaves the previous
snapshot available. No calendar permission is requested, and this feature uses
no cloud service. `SUMMARY` and `DESCRIPTION` stay on the device and are never
sent to room search or Maps. To resolve a room, the app sends only the event's
`LOCATION` text to the existing campus search. A Maps handoff contains the
matched building route and does not include event text.

## ICS data support

The importer accepts a `VCALENDAR` version 2.0 containing one or more
`VEVENT` components. It reads:

| Property | Behavior |
| --- | --- |
| `UID` | Required stable series key; duplicate master UIDs are rejected. |
| `DTSTART` | Required date, floating campus-local time (`Europe/Berlin`), UTC time, or recognized IANA `TZID`. |
| `DTEND` / `DURATION` | One is required for a normal event; they cannot both be present. `DTEND` is exclusive for all-day events. |
| `SUMMARY` | Required on a master event. A detached override may inherit it. Text escapes are decoded. |
| `DESCRIPTION` | Optional text stored locally. |
| `LOCATION` | Optional room/building text used by the resolver. |
| `RRULE` | One recurrence rule per master event, parsed by `teno_rrule`. `COUNT` and inclusive `UNTIL` boundaries matching the DTSTART value type are applied by the recurrence adapter. |
| `EXDATE` | One or more properties and comma-separated values exclude matching recurrence IDs. |
| `RECURRENCE-ID` | Detached moved and cancelled instances are applied to the matching master series. |

Standard `VALARM` components are ignored. The import does not create reminders
or notifications. Floating date-times keep their local wall clock in the
campus timezone, `Europe/Berlin`, regardless of the device timezone. Date-only
values are shown as all-day events. The bundled IANA database
provides timezone offsets, including `Europe/Berlin` and its daylight-saving
changes. Unknown `TZID` values are rejected. If a file includes a `VTIMEZONE`
for a recognized zone, its `STANDARD`/`DAYLIGHT` transitions must agree with
that IANA zone for the imported date range and the following ten years.

The parser rejects unsupported or unsafe input instead of guessing:

- `RDATE` additions to event recurrence sets are unsupported.
- More than one `RRULE` on a master event is unsupported.
- `RECURRENCE-ID;RANGE=THISANDFUTURE` and other range overrides are unsupported.
- `UNTIL` values whose DATE or DATE-TIME type does not match `DTSTART` are rejected.
- Unknown/custom timezones, malformed recurrence rules, invalid dates, and
  malformed `VTIMEZONE` definitions are rejected.

Recurrence expansion is bounded to 20,000 generated instances per series and
query window, and the recurrence query horizon stops before years after 2100.
The home preview searches the next 30 days; the timetable expands only the
selected day at a time.

## Room mapping and navigation

The room resolver searches using the event's `LOCATION` only. It compares
normalized aliases in validated campus search results and auto-assigns only a
single exact room match. It does not construct a room identifier from text or
use fuzzy matching. A building-only result can offer building navigation but
does not open a floor plan. Unknown or ambiguous rooms remain unassigned.

When exact resolution cannot choose a room, **Choose room** lets the user pick
from validated room candidates returned by campus search. A manual assignment
is stored against the series `UID` and normalized `LOCATION`. It is retained
on **Update** only while that location stays the same; changing the location
or choosing **Replace** removes the old assignment.

**Show room** validates the canonical saved-place identifier and opens the
existing floor-plan route. **Navigate** is offered only for a verified campus
building with route coordinates and uses the app's existing Google Maps
handoff. The floor-plan renderer and room geometry are unchanged.

## Emulator evidence

These screenshots were captured from the Android API 34 emulator at 1080 ×
1920 using the synthetic calendar in `test/fixtures/timetable_demo.ics`:

- [Timetable in light theme](timetable-evidence/phone-light.png)
- [Timetable in dark theme](timetable-evidence/phone-dark.png)
- [Next-event preview on Search](timetable-evidence/home-preview.png)
- [Verified APB E069 floor plan](timetable-evidence/room-floorplan.png)
- [Google Maps walking destination](timetable-evidence/maps-route.png)
- [Next-event preview after restarting the app](timetable-evidence/restart.png)

The dark-theme phone capture shows the monthly calendar redesign. The light-theme
phone capture is from the previous week-strip layout; a fresh light-mode
emulator capture remains pending.

## Troubleshooting

- If an import fails, check that the file is UTF-8 iCalendar 2.0 and does not
  contain unsupported recurrence constructs listed above.
- If a timezone is rejected, export the calendar with a recognized IANA
  `TZID`; custom timezone definitions are not accepted.
- If a room is unresolved, edit the event location in the calendar export or
  choose a validated room manually. The app does not guess.
- If the saved timetable cannot be read, the app preserves the stored data and
  reports a load error rather than replacing it with an empty schedule.
