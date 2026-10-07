# Icons from assets/icon-source.jpg (the camera on a white background, 1024 px):
#   assets/launcher_icon.png   512 px, transparent: the master for the launcher icon
#   store/icon-500.png         the Store icon: 500 px on a solid background with
#                              rounded corners, transparent outside them
#                              (store/ is the maintainer's, kept out of git)
# The Store's brand rules ask for a non-black background and at least 10 px
# of padding. Run by scripts/icons.sh.
import os

from PIL import Image, ImageDraw, ImageFilter

SRC = "assets/icon-source.jpg"
STORE_BG = (236, 240, 243)
STORE_RADIUS = 92   # the corner radius at 500 px, as the hero's icon tile


def cutout(img: Image.Image) -> Image.Image:
    """The camera on a transparent background. The background is flood-filled
    from the corners, so white inside the camera (the logo) stays; the edge is
    softened and its white fringe removed, so it sits cleanly on a black screen."""
    w, h = img.size
    marker = (255, 0, 255)
    probe = img.copy()
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(probe, corner, marker, thresh=40)
    bg = Image.new("L", (w, h), 0)
    bp, pp = bg.load(), probe.load()
    for y in range(h):
        for x in range(w):
            if pp[x, y] == marker:
                bp[x, y] = 255
    alpha = bg.point(lambda v: 255 - v).filter(ImageFilter.GaussianBlur(1.2))
    out = img.convert("RGBA")
    op, ap = out.load(), alpha.load()
    for y in range(h):
        for x in range(w):
            a = ap[x, y]
            r, g, b, _ = op[x, y]
            if 0 < a < 255:
                # Un-mix the white background from the edge pixel.
                f = a / 255
                r, g, b = (max(0, min(255, round((c - (1 - f) * 255) / f))) for c in (r, g, b))
            op[x, y] = (r, g, b, a)
    return out.crop(out.getbbox())


def square(img: Image.Image, size: int, fill: float, bg: tuple) -> Image.Image:
    """img scaled to `fill` of the width, centred on a size x size canvas."""
    scale = size * fill / max(img.size)
    fitted = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), bg)
    canvas.alpha_composite(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))
    return canvas


camera = cutout(Image.open(SRC).convert("RGB"))
square(camera, 512, 0.96, (0, 0, 0, 0)).save("assets/launcher_icon.png")
print("ok  assets/launcher_icon.png (512px)")
os.makedirs("store", exist_ok=True)
store = square(camera, 500, 0.80, STORE_BG + (255,))
# The corners' mask drawn at 4x and scaled down, so the curves are smooth.
corners = Image.new("L", (2000, 2000), 0)
ImageDraw.Draw(corners).rounded_rectangle((0, 0, 1999, 1999), STORE_RADIUS * 4, fill=255)
store.putalpha(corners.resize((500, 500), Image.LANCZOS))
store.save("store/icon-500.png")
print("ok  store/icon-500.png (500px)")
