# Voicenotes

Record and play voice notes on a Garmin watch. Export them to an HTTPS receiver or try the [Android companion beta](docs/android-beta.qmd).

Run `just garmin-build-app` to build `bin/Voicenotes.prg` for the Venu 4 45 mm. See the [setup guide](docs/setup.qmd) for other devices and receiver setup.

- Press START or tap the centre to record. START or BACK stops and saves.
- Press MENU or DOWN, or tap the bottom of the screen, to open **Saved notes**. Select a note, then tap or press START to play. Swipe left to open the delete confirmation, or press MENU or DOWN for note actions.
- Open **Saved notes → Settings** for auto-record, vibration, and recording length. Turn on **Save location** in **Saved notes** to include a usable GPS fix in HTTPS exports.
- Configure the HTTPS receiver in Garmin Connect. Manual and automatic uploads keep the original on the watch.

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
