#!/usr/bin/env bash
# Build native regressions with an isolated simulator application ID.
set -euo pipefail
cd "$(dirname "$0")/../.."
sdk=$(bash build.sh --sdk)
out="$PWD/bin/watch-tests"
mkdir -p "$out"
sed -E 's/(<iq:application id=")[^"]+"/\1a7d1403f75254653bdcb77526d23fa2b"/' manifest.xml > "$out/manifest.xml"
cat > "$out/tests.jungle" <<JUNGLE
project.manifest = manifest.xml
base.sourcePath = $PWD/src;$PWD/tests/watch
base.resourcePath = $PWD/resources
venu445mm.resourcePath = \$(base.resourcePath);$PWD/launcher-icons/65;$PWD/resources-venu445mm
base.excludeAnnotations = companion;simulatorFixture;simulatorTest
JUNGLE
"$sdk/bin/monkeyc" -f "$out/tests.jungle" \
    -t -d venu445mm -y "${DEVELOPER_KEY:-private/developer_key.der}" -o "$out/Regression.prg"
