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

[Build and run](docs/setup.qmd) · [Limits and compatibility](docs/compatibility.qmd) · [Verification](docs/validation.qmd)

This is a prototype. Device compilation and receiver tests do not establish microphone quality or reliability on physical watches.

## Documentation

See the [documentation index](docs/index.qmd) and [verification results](docs/validation.qmd). Run `quarto preview docs` to preview the site or `quarto render docs` to build `docs/_site`.

To serve the site at `http://localhost:8080` with Docker, run:

```sh
docker build -t voicenotes-docs docs
docker run --rm -p 127.0.0.1:8080:8080 voicenotes-docs
```

The Docker build uses Linux amd64 for Quarto and a native runtime image.

## License

[GNU Affero General Public License, version 3 only](LICENSE) (`AGPL-3.0-only`). Third-party materials retain their licenses.
