# Room details emulator captures

These are direct ADB screenshots of the installed debug APK, using the live TU
Dresden search and room-detail endpoints.

- `room-details-phone.png`: room 151 on the phone viewport, light theme.
- `room-details-phone-favorite.png`: same detail view after saving the room as
  a favorite.
- `connected-room-phone.png`: floorplan after opening the connected room ID
  `325301.0032` from the room-details chip.
- `room-tablet-landscape.png`: tablet-width layout, light theme.
- `room-tablet-dark.png`: tablet-width layout, dark theme.

The emulator ran Android 14 (API 34), x86_64. The phone viewport was
1080x1920 at 420 dpi. For tablet-width coverage, the Pixel 2 AVD used an
overridden 1920x1080 resolution at 240 dpi (1280x720 logical pixels). This
checks the responsive layout at tablet width; it is not a physical tablet
capture.
