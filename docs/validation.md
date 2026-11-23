# Verification — 23 November 2026

Passed:

- Garmin SDK 9.3.0 device build for Venu 4 45 mm.
- Release export for all 29 manifest profiles, covering 33 compiler device variants.
- Six receiver integration tests: authentication and path validation; interrupted upload and idempotent retry; receiver restart; conflicting chunks; request limits and metadata; incomplete or invalid audio rejection.
- Source type checking with warnings enabled. Launcher icons match the sizes in the device profiles.
- NoRain-style PowerShell build and `just garmin-build-app`, with and without private settings.
- Existing development signing key preserved when copied to `private/developer_key.der`; public properties remain unchanged by personal builds.
- Packaging with private settings and unknown device IDs rejected before compilation.
- Bash build-script syntax checked; native Linux/macOS compilation was not run.

Not verified:

- D2 Mach 2: excluded from the release manifest because the installed SDK lacks its device profile. The D2 Mach 2 Pro remains a release target.
- Simulator UI and audio: the simulator process did not expose a usable window during this run.
- Physical microphone capture, playback, firmware-dependent formats, and recording duration.
- Garmin phone/Wi-Fi/LTE transport and background scheduler behavior on physical hardware.
- Live HTTPS deployment: the receiver is implemented and locally tested, but no server was deployed.

Artifacts:

- `bin/Voicenotes.prg`: latest sideload build (Venu 4 45 mm by default).
- `bin/Voicenotes.iq`: release package.
- `bin/Voicenotes-installed-profiles.iq`: verification package for installed profiles.

Deferred upload implementation:

- Local chunks and note metadata persist independently of connectivity.
- Automatic uploads are opt-in; manual upload remains available.
- Open-app retries back off from 30 seconds to five minutes.
- On closing the app with automatic upload enabled, it registers a five-minute background interval. Garmin controls actual execution.
- Background jobs persist each acknowledged chunk position and resume after interruptions.
- Only the server's successful completion response marks a note uploaded.
- Upload never removes the local recording.
