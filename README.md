# Voicenotes

A Garmin Connect IQ watch app for microphone recordings, local playback, and server export.

Build with `just garmin-build-app`. The app is named **Voicenotes** and the output is `bin/Voicenotes.prg`. Run `just --list` for build, packaging, and simulator commands.

- Record using START or the central touch target. START or BACK stops and saves.
- Open saved notes with MENU, DOWN, or the bottom touch target.
- Play, upload, or delete a note. Deletion requires confirmation.
- Recordings stay on the watch after upload.
- Saved notes menu → **Settings** (last item): start recording automatically when the app opens, vibrate when recording starts, set the maximum recording length (30 s to 30 min, or no limit), and vibrate 10 seconds before that limit. Both are also in Garmin Connect's app settings.
- Configure an HTTPS receiver, access token, and optional automatic upload in Garmin Connect's app settings.
- Offline notes remain stored. Automatic upload retries while Voicenotes is open and through scheduled background jobs after closing it. Manual upload works with automatic upload disabled.

[Build and run](docs/setup.md) · [Limits and compatibility](docs/compatibility.md) · [Verification](docs/validation.md)

This is a prototype. Device compilation and receiver tests do not establish microphone quality or reliability on physical watches.
