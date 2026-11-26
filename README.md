# Voicenotes

A Garmin Connect IQ watch app for microphone recordings, local playback, and server export.

Build with `just garmin-build-app`. The app is named **Voicenotes** and the output is `bin/Voicenotes.prg`. Run `just --list` for build, packaging, and simulator commands.

- Record using START or the central touch target. START or BACK stops and saves.
- Open saved notes with MENU, DOWN, or the bottom touch target.
- Turn on **Save location** in **Saved notes** to attach a GPS fix to new recordings when the watch gets a usable fix before recording stops. The setting defaults to off. GPS coordinates are included in HTTPS uploads as `[latitude, longitude]` in `metadata.json`.
- Select a note to open it: tap or START plays, **swipe left** deletes, MENU or DOWN shows Play / Upload / Delete. Deletion requires confirmation.
- Recordings stay on the watch after upload.
- Saved notes menu → **Settings** (last item): start recording automatically when the app opens, vibrate when recording starts, set the maximum recording length (10 s to 30 min, or no limit), and vibrate shortly before that limit. These options are also in Garmin Connect's app settings.
- Configure an HTTPS receiver, access token, and optional automatic upload in Garmin Connect's app settings.
- Offline notes remain stored. Automatic upload retries while Voicenotes is open and through scheduled background jobs after closing it. Manual upload works with automatic upload disabled.

This is a prototype. Device compilation and receiver tests do not establish microphone quality or reliability on physical watches.

## Documentation

Start at the [documentation index](docs/index.qmd), [build and run the app](docs/setup.qmd), or [set up Home Assistant notifications](docs/how-to/home-assistant-notifications.qmd).

To preview the Quarto site locally, run `quarto preview docs` from the repository root. `quarto render docs` writes the static site to `docs/_site`.

To build and serve the site with Docker, run these commands from the repository root and open `http://localhost:8080`.

```sh
docker build -t voicenotes-docs docs
docker run --rm -p 127.0.0.1:8080:8080 voicenotes-docs
```

The Quarto build stage uses Linux amd64. On an ARM host, Docker can run that stage with amd64 emulation and build a native runtime image.

## License

The Garmin watch app, Python receiver, and the rest of this repository's original work are licensed under the [GNU Affero General Public License, version 3 only](LICENSE) (`AGPL-3.0-only`). Third-party materials retain their own licenses.
