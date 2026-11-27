set dotenv-load
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

default:
    @just --list

[doc("Build bin/Voicenotes.prg for a device, optionally with private settings.")]
[group('garmin')]
[windows]
garmin-build-app settings="" device="fenix847mm" channel="release":
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 {{ if settings == "" { "" } else { "-SettingsFile " + quote(settings) } }} -Device {{ quote(device) }} -Channel {{ quote(channel) }}

[doc("Build bin/Voicenotes.prg for a device, optionally with private settings.")]
[group('garmin')]
[unix]
garmin-build-app settings="" device="fenix847mm" channel="release":
    bash build.sh --device {{ quote(device) }} --channel {{ quote(channel) }} {{ quote(settings) }}

[doc("Build a release or beta store package without private settings.")]
[group('garmin')]
[windows]
garmin-package channel="release":
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Package -Channel {{ quote(channel) }}

[doc("Build a release or beta store package without private settings.")]
[group('garmin')]
[unix]
garmin-package channel="release":
    bash build.sh --package --channel {{ quote(channel) }}

[doc("Build the public Voicenotes package; does not publish it.")]
[group('garmin')]
garmin-release: garmin-package

[doc("Build and run Voicenotes. Start the simulator first.")]
[group('garmin')]
[windows]
garmin-run settings="" device="fenix847mm" channel="release":
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 {{ if settings == "" { "" } else { "-SettingsFile " + quote(settings) } }} -Device {{ quote(device) }} -Channel {{ quote(channel) }} -Run

[doc("Build and run Voicenotes. Start the simulator first.")]
[group('garmin')]
[unix]
garmin-run settings="" device="fenix847mm" channel="release":
    bash build.sh --device {{ quote(device) }} --channel {{ quote(channel) }} --run {{ quote(settings) }}

[doc("Start the selected Connect IQ SDK's simulator.")]
[group('garmin')]
[windows]
garmin-simulator:
    $sdk = powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 -PrintSdk; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; Start-Process -FilePath (Join-Path $sdk 'bin/simulator.exe') -WindowStyle Normal

[doc("Start the selected Connect IQ SDK's simulator.")]
[group('garmin')]
[unix]
garmin-simulator:
    "$(bash build.sh --sdk)/bin/connectiq" &

[doc("Compile installed device profiles into a verification package.")]
[group('garmin')]
[windows]
garmin-check:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-devices.ps1

[doc("Build and run the watch demo with the sample WAV fixture.")]
[group('garmin')]
[private]
[unix]
garmin-run-fixture:
    bash build.sh --simulator --companion --run

[doc("Build bin/Voicenotes.prg with the unreleased Android companion sync enabled.")]
[group('garmin')]
[private]
[unix]
garmin-build-companion settings="" device="fenix847mm":
    bash build.sh --companion --device {{ quote(device) }} {{ quote(settings) }}

[doc("Build the Android debug inbox APK.")]
[group('android')]
[private]
[unix]
android-build:
    VOICENOTES_ANDROID_OUTPUT_DIR="$PWD/bin/android" just --justfile "${VOICENOTES_COMPANION_DIR:-$HOME/src/garmin-voicenotes-companion}/.justfile" android-build

[doc("Build a signed APK for the physical Android companion.")]
[group('android')]
[private]
[unix]
android-beta:
    VOICENOTES_ANDROID_OUTPUT_DIR="$PWD/bin/android" just --justfile "${VOICENOTES_COMPANION_DIR:-$HOME/src/garmin-voicenotes-companion}/.justfile" android-beta

[doc("Install and open the beta or tethered demo on a running emulator.")]
[group('android')]
[private]
[unix]
android-preview mode="beta" serial="":
    VOICENOTES_ANDROID_OUTPUT_DIR="$PWD/bin/android" just --justfile "${VOICENOTES_COMPANION_DIR:-$HOME/src/garmin-voicenotes-companion}/.justfile" android-preview {{ quote(mode) }} {{ quote(serial) }}

[doc("Verify Android inbox storage, interrupted writes, and receipt retries.")]
[group('test')]
[private]
[unix]
test-android-storage:
    just --justfile "${VOICENOTES_COMPANION_DIR:-$HOME/src/garmin-voicenotes-companion}/.justfile" test-android-storage

[doc("Run the server-off fēnix 8 to Android emulator acceptance suite on macOS.")]
[group('test')]
[private]
[macos]
test-simulator serial="":
    python3 tests/simulator/run.py {{ if serial == "" { "" } else { "--serial " + quote(serial) } }}

[doc("Run the simulator suite and require delivery while the watch app is exited.")]
[group('test')]
[private]
[macos]
test-simulator-background serial="":
    python3 tests/simulator/run.py --require-background {{ if serial == "" { "" } else { "--serial " + quote(serial) } }}

[doc("Boot the Android virtual phone. Run in a separate terminal.")]
[group('android')]
[private]
[macos]
android-emulator avd="Medium_Phone_API_37.0":
    "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/emulator/emulator" -avd {{ quote(avd) }}

[doc("Render the docs and preview them in the browser with live reload.")]
[group('docs')]
docs-preview:
    quarto preview docs

[doc("Format the Monkey C source with Prettier. Run `npm install` once first.")]
[group('lint')]
format:
    npm run format

[doc("Check Monkey C formatting without changing files.")]
[group('lint')]
lint:
    npm run lint
