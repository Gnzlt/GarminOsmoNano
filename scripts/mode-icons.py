# The shooting-mode art, from assets/modes-source/<mode>.jpg (white glyphs on
# a near-black JPEG, at different sizes and scales):
#   assets/modes/<mode>.png       512 px master: the glyph alone
#   mode_<mode>.png               the glyph for the main screen (the app draws
#                                 the name above it)
#   mode_<mode>_s.png             the glyph, small: under the record time
# The screen-sized ones are written once per screen width the products have
# (scripts/devices.py): the 454 px reference set in resources/main/drawables, the base every
# product falls back to, and every other width in resources/gen/round-WxH/drawables
# with its own drawables.xml, which overrides the same ids.
# The background is pure black, so on an AMOLED screen those pixels stay
# off; the glyph is white with anti-aliased grey edges, drawn from a 4x
# supersample, so its curves don't step. On a MIP screen the bitmaps carry a
# palette of its four greys, so the edges map to them instead of dithering.
# Each glyph is cropped to its bounding box and scaled by its longer side, so
# wide and round glyphs read at the same size. Run by scripts/icons.sh.
import os
import sys
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import devices  # noqa: E402

MODES = ["video", "photo", "timelapse", "hyperlapse", "supernight", "slomo"]
IDS = {"video": "ModeVideo", "photo": "ModePhoto", "timelapse": "ModeTimelapse",
       "hyperlapse": "ModeHyperlapse", "supernight": "ModeSuperNight", "slomo": "ModeSloMo"}
SS = 4             # supersampling before the final threshold
MASTER = 512
BASE = 454         # the reference screen the sizes below were set on
GLYPH = 140        # the main screen's glyph box at 454 px
SMALL = 72
MIP_GREYS = ["000000", "555555", "AAAAAA", "FFFFFF"]


def glyph(name: str) -> Image.Image:
    """The source glyph, white on black ("L"), cropped to its bounding box."""
    img = Image.open(f"assets/modes-source/{name}.jpg").convert("L")
    img = img.filter(ImageFilter.GaussianBlur(1)).point(lambda v: 255 if v > 128 else 0)
    return img.crop(img.getbbox())


def fit(g: Image.Image, box: int) -> Image.Image:
    """The glyph scaled so its longer side is `box`, still greyscale."""
    w, h = g.size
    k = box / max(w, h)
    return g.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)


def square(g: Image.Image, side: int, box: int) -> Image.Image:
    """The glyph centred on a black square, at `box` of `side`."""
    big = Image.new("L", (side * SS, side * SS), 0)
    # Sharp at 4x (thresholded), then averaged down: the edge pixels' greys
    # are the glyph's coverage, and nothing outside it is lit.
    s = fit(g, box * SS).point(lambda v: 255 if v >= 128 else 0)
    big.paste(s, ((big.width - s.width) // 2, (big.height - s.height) // 2))
    return big.resize((side, side), Image.BOX)


def drawables_xml(mip: bool) -> str:
    palette = ("".join(f"<color>{c}</color>" for c in MIP_GREYS))
    lines = ["<!-- Written by scripts/mode-icons.py: the mode art at this screen size. -->",
             "<drawables>"]
    for name in MODES:
        for suffix, rid in (("", IDS[name]), ("_s", IDS[name] + "Small")):
            if mip:
                lines.append(f'    <bitmap id="{rid}" filename="mode_{name}{suffix}.png">'
                             f'<palette disableTransparency="true">{palette}</palette></bitmap>')
            else:
                lines.append(f'    <bitmap id="{rid}" filename="mode_{name}{suffix}.png"/>')
    lines.append("</drawables>")
    return "\n".join(lines) + "\n"


# Every screen width the products have; MIP if any product at it is.
widths: dict[int, bool] = {BASE: False}
for d in devices.shipping():
    widths[d.width] = widths.get(d.width, False) or not d.amoled

sources = {name: glyph(name) for name in MODES}
for name, g in sources.items():
    square(g, MASTER, MASTER * 80 // 100).save(f"assets/modes/{name}.png")
for width, mip in sorted(widths.items()):
    if width == BASE:
        out = "resources/main/drawables"
    else:
        out = f"resources/gen/round-{width}x{width}/drawables"
        os.makedirs(out, exist_ok=True)
        with open(f"{out}/drawables.xml", "w") as f:
            f.write(drawables_xml(mip))
    big, small = round(GLYPH * width / BASE), round(SMALL * width / BASE)
    for name, g in sources.items():
        square(g, big, big).save(f"{out}/mode_{name}.png")
        square(g, small, small).save(f"{out}/mode_{name}_s.png")
    print(f"ok  mode art {width} px ({big}/{small}{', MIP palette' if mip else ''}) in {out}")
