#!/usr/bin/env bash
# Every image the app and its Store listing use. The shape is the same in
# GarminMotoFields, GarminOBD, GarminOsmoNano and GarminTPMS; only the renderers differ.
#   resources/main/drawables/launcher_icon.png   the launcher icon at BASE_ICON px
#   resources/gen/<product>/                     the launcher icon at each other size
#                                                (from the device profiles, through
#                                                scripts/devices.py: a size mismatch is a
#                                                compiler warning, which fails scripts/build.sh)
#   resources/gen/round-WxH/                     the shooting-mode art per screen size
#                                                (scripts/mode-icons.py)
#   store/icon-500.png, store/hero.png           the Store icon and hero image
# Then scripts/jungles.py names the generated folders in the jungles.
# resources/gen/ is rebuilt from scratch and committed, so a clone builds
# without these tools. Needs uv (Pillow) and rsvg-convert or resvg.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BASE_ICON=65
py() { uv run --quiet --no-project --with pillow python "$@"; }
svg() {   # svg <in> <width> <height> <out>
    if command -v rsvg-convert >/dev/null; then
        rsvg-convert -w "$2" -h "$3" "$1" -o "$4"
    else
        resvg --use-fonts-dir "$HOME/.local/share/fonts" --sans-serif-family "Noto Sans SC" \
            -w "$2" -h "$3" "$1" "$4"
    fi
}

# --- this app's renderers ----------------------------------------------------
# From assets/icon-source.jpg: assets/launcher_icon.png (512 px master) and
# store/icon-500.png; the mode glyphs from assets/modes-source/.
prepare() {
    py scripts/icons.py
    mkdir -p assets/modes
    py scripts/mode-icons.py
}
launcher() {   # launcher <size> <out png>
    py -c "
from PIL import Image
Image.open('assets/launcher_icon.png').resize(($1, $1), Image.LANCZOS).save('$2')"
}
store_images() {
    [[ -f store/hero.svg ]] || return 0
    svg store/hero.svg 1440 720 store/hero.png
    echo "ok  store/hero.png (1440x720)"
}
# -----------------------------------------------------------------------------

rm -rf resources/gen
mkdir -p resources/gen store
prepare
launcher "$BASE_ICON" resources/main/drawables/launcher_icon.png
echo "ok  resources/main/drawables/launcher_icon.png (${BASE_ICON}px)"
while read -r product width size kind; do
    [[ "$size" == "$BASE_ICON" ]] && continue
    dir="resources/gen/$product/drawables"
    mkdir -p "$dir"
    launcher "$size" "$dir/launcher_icon.png"
    cat >"$dir/drawables.xml" <<XML
<!-- Written by scripts/icons.sh: the launcher icon at this product's size. -->
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
</drawables>
XML
    echo "ok  $dir/launcher_icon.png (${size}px)"
done < <(py scripts/devices.py --list)
py scripts/jungles.py
store_images
