# A Store screenshot from a simulator capture: the watch without the
# simulator's menu and status bars, 540 px wide, as a JPEG. The same file in
# GarminOBD, GarminOsmoNano and GarminTPMS.
#
#   ciq-sim run bin/<App>-demo.prg fenix847mm
#   ciq-sim shot store/screens/raw/<name>.png          (raw captures are gitignored)
#   uv run --no-project --with pillow python scripts/screens.py \
#       store/screens/raw/<name>.png store/screens/<n>-<name>.jpg
#
# The bars, and the 1 px grey frame around the watch, are at the same place
# in the simulator window for every device: only the watch changes size.
import sys

from PIL import Image

WIDTH = 540
MENU_BAR = 26     # with the frame's top line
STATUS_BAR = 24   # with the frame's bottom line


def crop(src: str, out: str) -> None:
    img = Image.open(src).convert("RGB")
    w, h = img.size
    shot = img.crop((1, MENU_BAR, w - 1, h - STATUS_BAR))
    shot = shot.resize((WIDTH, round(shot.height * WIDTH / shot.width)), Image.LANCZOS)
    shot.save(out, quality=90)
    print(f"ok  {out} ({shot.width}x{shot.height})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: screens.py <capture.png> <out.jpg>")
    crop(sys.argv[1], sys.argv[2])
