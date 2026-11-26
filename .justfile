set dotenv-load
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

default:
    @just --list

[doc("Build bin/Voicenotes.prg for a device, optionally with private settings.")]
[group('garmin')]
[windows]
garmin-build-app settings="" device="venu445mm":
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 {{ if settings == "" { "" } else { "-SettingsFile " + quote(settings) } }} -Device {{ quote(device) }}

[doc("Build bin/Voicenotes.prg for a device, optionally with private settings.")]
[group('garmin')]
[unix]
garmin-build-app settings="" device="venu445mm":
    bash build.sh --device {{ quote(device) }} {{ quote(settings) }}

[doc("Build bin/Voicenotes.iq for the store, without private settings.")]
[group('garmin')]
[windows]
garmin-package:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Package

[doc("Build bin/Voicenotes.iq for the store, without private settings.")]
[group('garmin')]
[unix]
garmin-package:
    bash build.sh --package

[doc("Build the public Voicenotes package; does not publish it.")]
[group('garmin')]
garmin-release: garmin-package

[doc("Build and run Voicenotes. Start the simulator first.")]
[group('garmin')]
[windows]
garmin-run settings="" device="venu445mm":
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 {{ if settings == "" { "" } else { "-SettingsFile " + quote(settings) } }} -Device {{ quote(device) }} -Run

[doc("Build and run Voicenotes. Start the simulator first.")]
[group('garmin')]
[unix]
garmin-run settings="" device="venu445mm":
    bash build.sh --device {{ quote(device) }} --run {{ quote(settings) }}

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

[doc("Format the Monkey C source with Prettier. Run `npm install` once first.")]
[group('lint')]
format:
    npm run format

[doc("Check Monkey C formatting without changing files.")]
[group('lint')]
lint:
    npm run lint
