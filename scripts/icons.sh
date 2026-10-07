#!/usr/bin/env bash
# Every icon. The shooting modes' art from assets/modes-source/, at each screen
# size the products have (scripts/mode-icons.py). From assets/icon-source.jpg
# (scripts/icons.py): the launcher icon's master assets/launcher_icon.png (512
# px, transparent), scaled to each product's size (from its profile, through
# scripts/devices.py; a size mismatch is a compiler warning, which fails
# scripts/build.sh); the Store icon store/icon-500.png; and the Store hero
# image from store/hero.svg when it is there (store/ is kept out of git). Uses
# Pillow through uv, and rsvg-convert for the hero.
#
# Everything in gen/ is generated here, and rebuilt from scratch.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BASE_ICON=65    # resources/drawables/launcher_icon.png; other sizes get gen/resources-<product>
py() { uv run --quiet --no-project --with pillow python "$@"; }

rm -rf gen
py scripts/icons.py
mkdir -p assets/modes
py scripts/mode-icons.py

launcher() {   # launcher <size> <out png>
    py -c "
from PIL import Image
Image.open('assets/launcher_icon.png').resize(($1, $1), Image.LANCZOS).save('$2')"
}
launcher "$BASE_ICON" resources/drawables/launcher_icon.png
echo "ok  resources/drawables/launcher_icon.png (${BASE_ICON}px)"
while read -r product width size kind; do
    [[ "$size" == "$BASE_ICON" ]] && continue
    dir="gen/resources-$product/drawables"
    mkdir -p "$dir"
    launcher "$size" "$dir/launcher_icon.png"
    cat >"$dir/drawables.xml" <<XML
<!-- Written by scripts/icons.sh: the launcher icon at this product's size. -->
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
</drawables>
XML
    echo "ok  $dir/launcher_icon.png (${size}px)"
done < <(python3 scripts/devices.py --list)
python3 scripts/jungles.py
if [[ -f store/hero.svg ]]; then
    rsvg-convert -w 1440 -h 720 store/hero.svg -o store/hero.png
    echo "ok  store/hero.png (1440x720)"
fi
