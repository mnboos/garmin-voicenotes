#!/usr/bin/env bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
CALLER_DIR=$PWD
cd "$(dirname "$0")"
HERE=$(pwd -P)
SETTINGS=""
PACKAGE=""
RUN=""
PRINT_SDK=""
SIMULATOR=""
COMPANION=""
DEVICE=fenix847mm
CHANNEL=release
while [ "$#" -gt 0 ]; do
    case "$1" in
        --device) [ "$#" -ge 2 ] || fail '--device needs a product ID.'; DEVICE=$2; shift ;;
        --channel) [ "$#" -ge 2 ] || fail '--channel needs beta or release.'; CHANNEL=$2; shift ;;
        --package) PACKAGE=1 ;;
        --run) RUN=1 ;;
        --simulator) SIMULATOR=1 ;;
        --companion) COMPANION=1 ;;
        --sdk) PRINT_SDK=1 ;;
        -*) fail "Unknown option: $1" ;;
        *)
            [ -z "$SETTINGS" ] || fail 'Only one settings file is allowed.'
            if [ -n "$1" ]; then
                case "$1" in /*) SETTINGS=$1 ;; *) SETTINGS="$CALLER_DIR/$1" ;; esac
                [ -f "$SETTINGS" ] || fail "No settings file: $1"
            fi ;;
    esac
    shift
done
[ -z "$PACKAGE" ] || { [ -z "$SETTINGS" ] && [ -z "$RUN" ]; } || fail 'Do not combine --package with personal settings or --run.'
[ -z "$COMPANION" ] || [ -z "$PACKAGE" ] || fail 'Do not combine --companion with --package; the store package never includes the Android companion.'
[ -z "$SIMULATOR" ] || { [ -z "$PACKAGE" ] && [ -z "$SETTINGS" ]; } ||
    fail 'Do not combine --simulator with --package or personal settings.'
if [ "$(uname)" = Darwin ]; then SDK_CFG="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
else SDK_CFG="$HOME/.Garmin/ConnectIQ/current-sdk.cfg"
fi
if [ -n "${CONNECTIQ_SDK:-}" ]; then SDK=$CONNECTIQ_SDK
elif [ -f "$SDK_CFG" ]; then SDK=$(tr -d '\r\n' < "$SDK_CFG")
else SDK="$HERE/.tools/sdk"
fi
[ -x "$SDK/bin/monkeyc" ] || fail 'Install a native Connect IQ SDK with SDK Manager, or set CONNECTIQ_SDK.'
if [ -n "$PRINT_SDK" ]; then printf '%s\n' "$SDK"; exit 0; fi

CHANNEL_JUNGLE=$(python3 -I - "$HERE" "$DEVICE" "$PACKAGE" "$SETTINGS" "$CHANNEL" <<'PY'
import json
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit

root, device, package, settings, channel = sys.argv[1:]
root = Path(root)
manifest_path = root / 'manifest.xml'
manifest = manifest_path.read_text(encoding='utf-8-sig')
app = ET.fromstring(manifest).find('{*}application')
if channel not in ('beta', 'release'):
    sys.exit('--channel needs beta or release.')
app_id_key = f'GARMIN_{channel.upper()}_APP_ID'
app_id = os.environ.get(app_id_key) or (app.get('id') if channel == 'release' else '')
if not re.fullmatch(r'[0-9a-fA-F]{32}', app_id):
    sys.exit(f'Set a 32-digit hexadecimal {app_id_key}.')
name = ET.parse(root / 'resources/strings/strings.xml').find("string[@id='Voicenotes']").text
if app.get('name') != '@Strings.Voicenotes' or name != 'Voicenotes':
    sys.exit('The application name must be exactly Voicenotes.')
if not package and device not in {p.get('id') for p in app.findall('{*}products/{*}product')}:
    sys.exit(f"Unsupported device '{device}'. Choose a product ID from manifest.xml.")
if settings:
    config = json.loads(Path(settings).read_text(encoding='utf-8-sig'))
    targets = 0
    for suffix in ('', '2', '3'):
        url_key, token_key = f'serverUrl{suffix}', f'serverToken{suffix}'
        server, token = config.get(url_key), config.get(token_key)
        if server in (None, '') and token in (None, ''):
            continue
        try:
            url = urlsplit(server) if isinstance(server, str) else None
        except ValueError:
            url = None
        if (url is None or url.scheme != 'https' or not url.hostname
                or any(c.isspace() or c in '?#@' for c in server)
                or not isinstance(token, str) or len(token) < 32 or any(not 33 <= ord(c) <= 126 for c in token)):
            sys.exit(f'Settings need an HTTPS {url_key} and a printable ASCII {token_key} of at least 32 characters.')
        targets += 1
    if not targets:
        sys.exit('Settings need at least one sync target.')
    if type(config.get('autoUpload', False)) is not bool:
        sys.exit('autoUpload must be true or false.')
if app_id != app.get('id'):
    private = root / 'private'
    private.mkdir(exist_ok=True)
    ET.register_namespace('iq', 'http://www.garmin.com/xml/connectiq')
    tree = ET.fromstring(manifest)
    tree.find('{*}application').set('id', app_id)
    ET.ElementTree(tree).write(private / f'manifest-{channel}.xml', encoding='utf-8')
    jungle = private / f'manifest-{channel}.jungle'
    jungle.write_text(f'project.manifest = manifest-{channel}.xml\n', encoding='ascii')
    print(jungle)
PY
)

KEY="${DEVELOPER_KEY:-$HERE/private/developer_key.der}"
case "$KEY" in /*) ;; *) KEY="$CALLER_DIR/$KEY" ;; esac
mkdir -p "$HERE/private" "$HERE/bin" "$(dirname "$KEY")"
if [ -z "${DEVELOPER_KEY:-}" ] && [ ! -f "$KEY" ] && [ -f "$HERE/.tools/developer.der" ]; then cp "$HERE/.tools/developer.der" "$KEY"; fi
if [ ! -f "$KEY" ]; then
    (umask 077; openssl genrsa 4096 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -out "$KEY")
fi
JUNGLE="${CHANNEL_JUNGLE:-$HERE/monkey.jungle};$HERE/resources.jungle"
if [ -n "$SETTINGS$SIMULATOR$COMPANION" ]; then
    BUILD_DIR=$(mktemp -d "$HERE/private/build.XXXXXXXX")
    trap 'rm -rf -- "$BUILD_DIR"' EXIT
fi
if [ -n "$SETTINGS" ]; then
    mkdir -p "$BUILD_DIR/resources"
    cp -R "$HERE/resources/." "$BUILD_DIR/resources/"
    python3 -I - "$SETTINGS" "$BUILD_DIR/resources/settings/properties.xml" <<'PY'
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

config = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
tree = ET.parse(sys.argv[2])
values = {'autoUpload': str(config.get('autoUpload', False)).lower()}
for suffix in ('', '2', '3'):
    url_key, token_key = f'serverUrl{suffix}', f'serverToken{suffix}'
    if config.get(url_key):
        values[url_key] = config[url_key].rstrip('/')
        values[token_key] = config[token_key]
for prop in tree.getroot():
    if prop.get('id') in values:
        prop.text = values[prop.get('id')]
tree.write(sys.argv[2], encoding='utf-8')
PY
    cat > "$BUILD_DIR/personal.jungle" <<EOF
base.resourcePath = $BUILD_DIR/resources
EOF
    JUNGLE="$JUNGLE;$BUILD_DIR/personal.jungle"
fi
ARTIFACT_NAME=Voicenotes
if [ "$CHANNEL" = beta ]; then ARTIFACT_NAME=Voicenotes-beta; fi
ARTIFACT="$HERE/bin/$ARTIFACT_NAME.prg"
if [ -n "$SIMULATOR" ]; then
    ARTIFACT="$HERE/bin/Voicenotes-simulator.prg"
    JUNGLE="$JUNGLE;$HERE/simulator/fixture.jungle"
fi
if [ -n "$SIMULATOR$COMPANION" ]; then
    # Override the public exclusions only for explicitly enabled features.
    EXCLUDE=simulatorTest
    [ -n "$COMPANION" ] || EXCLUDE="companion;$EXCLUDE"
    [ -n "$SIMULATOR" ] || EXCLUDE="simulatorFixture;$EXCLUDE"
    printf 'base.excludeAnnotations = %s\n' "$EXCLUDE" > "$BUILD_DIR/features.jungle"
    JUNGLE="$JUNGLE;$BUILD_DIR/features.jungle"
fi
if [ -n "$PACKAGE" ]; then
    ARTIFACT="$HERE/bin/$ARTIFACT_NAME.iq"
    "$SDK/bin/monkeyc" -f "$JUNGLE" -o "$ARTIFACT" -y "$KEY" -w -r -e
else
    "$SDK/bin/monkeyc" -f "$JUNGLE" -o "$ARTIFACT" -y "$KEY" -w -r -d "$DEVICE"
fi
printf '%s\n' "$ARTIFACT"
if [ -n "$RUN" ]; then "$SDK/bin/monkeydo" "$ARTIFACT" "$DEVICE"; fi
