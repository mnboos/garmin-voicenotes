# Voicenotes

A Garmin Connect IQ watch app for microphone recordings, local playback, and server export.

Build with `just garmin-build-app`. The app is named **Voicenotes** and the output is `bin/Voicenotes.prg`. Run `just --list` for build, packaging, and simulator commands.

- Record using START or the central touch target. START or BACK stops and saves.
- Open saved notes with MENU, DOWN, or the bottom touch target.
- Select a note to open it: tap or START plays, **swipe left** deletes, MENU or DOWN shows Play / Resync / Delete. Deletion requires confirmation.
- Saved notes menu → **Settings** (last item): start recording automatically when the app opens, vibrate when recording starts, set the maximum recording length (10 s to 30 min, or no limit), and vibrate 10 seconds before that limit. Both are also in Garmin Connect's app settings.
- The list shows each note's sync status. Recordings stay on the watch after sync.
- Configure up to three Voicenotes-compatible HTTPS receivers and their access tokens in Garmin Connect's app settings. Enable automatic upload to send saved recordings to all configured targets.
- Offline recordings and manual resync requests stay queued. The watch checks for connectivity while the app is open and uses Garmin's scheduled background jobs after closing. Manual resync works with automatic upload disabled.
- The receiver can email recordings as attachments, copy them to a mounted network share, or do both.

[Build and run](docs/setup.md) · [Limits and compatibility](docs/compatibility.md) · [Verification](docs/validation.md)

This is a prototype. Device compilation and receiver tests do not establish microphone quality or reliability on physical watches.
