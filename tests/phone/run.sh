#!/usr/bin/env bash
# Run the phone sync protocol tests in the Connect IQ simulator. Starts the simulator if needed.
set -euo pipefail
cd "$(dirname "$0")/../.."
device=${1:-fenix847mm}
sdk=$(bash build.sh --sdk)
out="$PWD/bin/phone-tests"
mkdir -p "$out"
# An isolated application ID keeps the tests away from real notes in the simulator.
sed -E 's/(<iq:application id=")[^"]+"/\13f1c0e7a2b8d4c6e9a5f7b1d3c5e7a90"/' manifest.xml > "$out/manifest.xml"
cat > "$out/tests.jungle" <<JUNGLE
project.manifest = manifest.xml
base.sourcePath = $PWD/src;$PWD/tests/phone
base.resourcePath = $PWD/resources
fenix847mm.resourcePath = \$(base.resourcePath);$PWD/launcher-icons/65;$PWD/resources-fenix8
base.excludeAnnotations = simulatorFixture;simulatorTest
JUNGLE
"$sdk/bin/monkeyc" -f "$out/tests.jungle" -t -w -d "$device" \
    -y "${DEVELOPER_KEY:-private/developer_key.der}" -o "$out/PhoneSync.prg"

listening() { (exec 3<>/dev/tcp/127.0.0.1/1234) 2>/dev/null; }
if ! listening; then
    "$sdk/bin/connectiq" >/dev/null 2>&1 &
    for _ in $(seq 1 60); do listening && break; sleep 1; done
    listening || { echo 'The Connect IQ simulator did not start.' >&2; exit 1; }
    sleep 5
fi
# monkeydo can exit with 1 after passing tests, so read the summary instead.
# A stalled simulator never answers; give up after five minutes.
perl -e 'alarm shift; exec @ARGV' 300 "$sdk/bin/monkeydo" "$out/PhoneSync.prg" "$device" -t |
    tee "$out/results.txt" || true
grep -q '^PASSED' "$out/results.txt" || {
    echo 'Phone sync tests did not pass. If no results appeared, restart the simulator.' >&2
    exit 1
}
