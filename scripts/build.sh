#!/usr/bin/env bash
# Build OsmoNano with strict type checking:
#   bin/OsmoNano-<device>.prg    release, to sideload: every product in manifest.xml,
#                                or only $DEVICE when it is set (DEVICE=fenix847mm)
#   bin/OsmoNano-test.prg        with the (:test) functions, for the simulator
#                                (on $DEVICE, fenix847mm by default)
#   bin/OsmoNano-demo.prg        a fake camera that walks every screen (only with --demo)
#   bin/OsmoNano.iq              the Store package, every product
#   bin/OsmoNano-beta.iq         the same under the Store beta's app id
#                                (--iq or --beta: always both, so the release and
#                                the beta never ship different versions)
# Any compiler warning fails the build: that is the project's gate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-}"
TEST_DEVICE="${DEVICE:-fenix847mm}"
# The maintainer's private Store beta's app id; set BETA_ID for your own. A beta
# must not share the production id in manifest.xml; keep it fixed so every
# upload updates the same beta.
BETA_ID="${BETA_ID:-2ef719bfee4a45679d5b87ae5e8e15ac}"
KEY="${CIQ_KEY:-$HOME/.config/connectiq/developer_key.der}"
cd "$ROOT"
mkdir -p bin

# VERSION is the one place the version lives; About shows it.
VERSION="$(tr -d '[:space:]' <VERSION)"
cat >resources/strings/version.xml <<XML
<!-- Written by scripts/build.sh from VERSION; edit VERSION instead. -->
<strings>
    <string id="AppVersion">$VERSION</string>
</strings>
XML

build() {   # build <jungle> <out> <device> [extra monkeyc args...]
    local jungle="$1" out="$2" device="$3"; shift 3
    local log
    log="$(monkeyc -f "$jungle" -d "$device" -y "$KEY" -l 3 -w -o "$out" "$@" 2>&1)" || {
        echo "$log"; echo "FAIL: $out"; exit 1; }
    if grep -q "WARNING" <<<"$log"; then
        echo "$log"; echo "FAIL: warnings in $out"; exit 1
    fi
    echo "ok  $out ($(wc -c <"$out" | tr -d " ") bytes)"
}

export_iq() {   # export_iq <jungle> <out>: a Store package for every product in the manifest
    local log
    log="$(monkeyc -f "$1" -e -y "$KEY" -l 3 -w -r -o "$2" 2>&1)" || {
        echo "$log"; echo "FAIL: $2"; exit 1; }
    if grep -q "WARNING" <<<"$log"; then
        echo "$log"; echo "FAIL: warnings in $2"; exit 1
    fi
    echo "ok  $2 ($(wc -c <"$2" | tr -d " ") bytes)"
}

if [[ -n "$DEVICE" ]]; then
    devices=("$DEVICE")
else
    devices=($(sed -n 's/.*<iq:product id="\([^"]*\)".*/\1/p' manifest.xml))
fi
for d in "${devices[@]}"; do
    build monkey.jungle "bin/OsmoNano-$d.prg" "$d" -r
done
build monkey.jungle "bin/OsmoNano-test.prg" "$TEST_DEVICE" --unit-test
packages=0
for arg in "$@"; do
    case "$arg" in
        --demo) build "monkey.jungle;demo.jungle" "bin/OsmoNano-demo.prg" "$TEST_DEVICE" ;;
        --iq | --beta) packages=1 ;;
    esac
done
if [[ "$packages" == 1 ]]; then
    export_iq monkey.jungle bin/OsmoNano.iq
    prod_id="$(sed -n 's/.*iq:application id="\([0-9a-f]*\)".*/\1/p' manifest.xml)"
    sed "s/$prod_id/$BETA_ID/" manifest.xml >manifest-beta.xml
    export_iq beta.jungle bin/OsmoNano-beta.iq
    echo "    upload both as App Version $VERSION (the beta with Beta App ticked), then: git tag v$VERSION && git push --tags"
fi
