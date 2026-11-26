# Build and run Voicenotes

## Build the watch app

1. Install Java, Garmin Connect IQ SDK 9.3.0 or newer, and `just`. Unix builds also need Bash, Python 3, and OpenSSL.
2. Use Garmin SDK Manager to update device profiles. The profiles must advertise API 6.0.3 or newer.
3. Run from this folder:

   ```powershell
   just garmin-build-app
   ```

   This builds `bin/Voicenotes.prg` for Venu 4 45 mm. To choose another device, run `just garmin-build-app "" fr970`.

   SDK selection: `CONNECTIQ_SDK`, then Garmin's selected SDK, then `.tools/sdk`. PowerShell also accepts `-SdkPath`. Unix builds need the SDK for the host platform.

   Signing keys live in `private/developer_key.der`. The existing `.tools/developer.der` key is copied there on the first build, preserving app signing identity. Set `DEVELOPER_KEY` or PowerShell's `-DeveloperKey` to choose another key. Keep it private and back it up before publishing.

4. For the simulator, open the matching SDK's simulator and run:

   ```powershell
   just garmin-simulator
   just garmin-run
   ```

5. To sideload, copy `bin/Voicenotes.prg` into the watch's `GARMIN/APPS` folder over USB. Each build replaces this file; use the device selected for that build.
6. To create `bin/Voicenotes.iq` for all manifest targets, use `just garmin-package` or `just garmin-release`. These commands do not publish the app.

The app name is exactly **Voicenotes**. Both build scripts validate it.

Direct script equivalents:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Device fr970
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Package
```

```bash
bash build.sh --device fr970
bash build.sh --package
```

The earlier PowerShell options `-Sdk`, `-Key`, and `-Export` remain accepted aliases.

## Build with private settings

1. Copy `settings.example.json` to `private/settings.json`.
2. Replace `serverUrl` and `serverToken` with your receiver settings. Set `autoUpload` to `true` or `false`.
3. Run `just garmin-build-app private/settings.json fr970`, choosing your device.

Private settings are written into a separate resource copy under `private/`. Public resources stay unchanged. The scripts reject combining private settings with store packaging. The `private/` directory and `.env` are ignored by Git. The resulting personal PRG contains your token; keep it private.

Direct equivalents: `build.ps1 -SettingsFile private/settings.json -Device fr970` or `bash build.sh --device fr970 private/settings.json`.

On Windows, run `just garmin-check` after the first build to check the installed device profiles. Use `just garmin-package` to export the release package. See [verification results](validation.md).

## Run the export receiver

The receiver uses Python 3.11 or newer and only the standard library. It supports one owner/token. No cloud service is deployed by this project.

1. Set a randomly generated token in `VOICENOTES_TOKEN` (at least 32 ASCII characters). Keep the same token across restarts; do not commit it.
2. Run:

   ```powershell
   python server/receiver.py --data data
   ```

   On this workspace, the downloaded runtime can also be used:

   ```powershell
   .\.tools\python\cpython-3.13.18-windows-x86_64-none\python.exe server/receiver.py --data data
   ```

3. Put an HTTPS reverse proxy with a publicly trusted certificate in front of `127.0.0.1:8787`. Configure its hostname and TLS for your server. The watch's URL must be reachable from the phone or the watch's available network.
4. In Garmin Connect, open Voicenotes settings and enter the HTTPS base URL and the same token.
5. Enable **Automatically upload queued notes (also in background)** if wanted.
6. Record a short note. After reconnecting, leave the app open to retry or let Garmin run the scheduled background job. Background scheduling is approximate; it requests five-minute intervals.
7. Find the original audio in `data/NOTE_ID/note.ogg` or `note.wav`. `metadata.json` contains the checksum and recording status. Back up this directory.

The receiver preserves source bytes without transcoding. It validates the container signature, byte count, and complete chunk set; it does not prove the recording contains audible speech.

## Verify changes

Format the watch source with Prettier and its Monkey C plugin (Node.js needed; run `npm install` once):

```bash
just format   # rewrite source/*.mc
just lint     # check only
```


```powershell
python -m unittest discover -s server -v
```

Before release, test on real hardware:

- Record, stop, play, and delete with buttons and touch.
- Restart the app and check saved notes.
- Record offline with automatic upload enabled. Close the app, reconnect, and verify a scheduled upload without reopening it. Also test retries with the app open.
- Disconnect halfway through an upload. Retry and compare the receiver checksum.
- Disable automatic upload and confirm notes remain local until manual upload.
- Fill storage and confirm previous notes remain intact.
- Test interruption, empty capture, short capture, and speaker/headphone playback.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`. It checks formatting, runs the receiver tests and compiles the app for every device in `manifest.xml`. The compiled `Voicenotes.iq` is attached to the run for seven days. It is signed with a throwaway key, so don't publish it.

The build job needs no secrets. It runs `build.sh --package` inside `ghcr.io/blackshadev/garmin-connectiq-tools`, the image behind the [Garmin ConnectIQ Build](https://github.com/marketplace/actions/garmin-connectiq-build) action, which already contains the Connect IQ SDK and device profiles. The workflow pins the image by digest. To move to a newer SDK, take the digest of a newer tag and update `CONNECTIQ_IMAGE` in `.github/workflows/ci.yml`.

- The image is maintained by a third party, not Garmin. Garmin's SDK licence forbids hosting SDK files on other servers, so the image may be taken down. If it disappears, CI fails at the compile step.
- If the image lacks a profile for a device in `manifest.xml`, compilation fails for that device.

To block merging until CI passes, add a branch ruleset for `main` (Settings → Rules → Rulesets) that requires a pull request and the status checks **Format check**, **Receiver tests** and **Compile watch app**.
