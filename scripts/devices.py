# The products OsmoNano ships for, checked against the SDK's device profiles
# (~/.Garmin/ConnectIQ/Devices, downloaded with Garmin's SDK Manager).
# OsmoNano is a watch app that draws plain shapes, so its rules are wide.
# A candidate ships only if its profile shows:
#   - a round or semi-octagon screen (Instinct); rectangles are not drawn for;
#   - BLE for apps (the app talks BLE);
#   - Connect IQ 3.2.7 or later (manifest minApiLevel: some part numbers of the Instinct 2, the
#     Descent G1 and the fenix 5 Plus run 3.2.7 or 3.2.8, and the Store package drops what it doesn't cover);
#   - at least 96 KB for a watch app (the Instinct 2's limit; the demo fits it);
#   - START and BACK. UP, DOWN and MENU are optional: a touch-first watch (Venu,
#     vivoactive) lacks UP and DOWN, so the app takes swipes and a long press there.
#
#   uv run --no-project python scripts/devices.py              the table, with why a candidate is out
#   uv run --no-project python scripts/devices.py --manifest   also writes the list into manifest.xml
#   uv run --no-project python scripts/devices.py --list       "<product> <width> <launcher px> <amoled|mip> <ui flags>"
#                                                              per shipping product, for scripts/icons.sh
import json
import math
import re
import sys
from pathlib import Path

PROFILES = Path.home() / ".Garmin/ConnectIQ/Devices"
MANIFEST = Path(__file__).resolve().parent.parent / "manifest.xml"
MIN_CIQ = (3, 2, 7)
MIN_MEMORY = {"watchApp": 96 * 1024}
KEYS = {"enter", "esc"}
SHAPES = {"round", "semi-octagon"}

# The watches the app ships for. Quatix, tactix
# and other editions share these products (their part numbers are in the profiles).
CANDIDATES = [
    # Fenix 9
    "fenix943mm", "fenix947mm", "fenix9pro43mm", "fenix9pro47mm", "fenix9pro51mm",
    "fenix9prosolar47mm", "fenix9prosolar51mm",
    # Fenix 8
    "fenix843mm", "fenix847mm", "fenix8solar47mm", "fenix8solar51mm", "fenix8pro47mm",
    # Fenix 5 Plus, Fenix 6
    "fenix5plus", "fenix5splus", "fenix5xplus",
    "fenix6", "fenix6s", "fenix6pro", "fenix6spro", "fenix6xpro",
    # Fenix 7, Fenix E
    "fenix7", "fenix7s", "fenix7x", "fenix7pro", "fenix7spro", "fenix7xpro",
    "fenix7pronowifi", "fenix7xpronowifi", "fenixe",
    # Epix
    "epix2", "epix2pro42mm", "epix2pro47mm", "epix2pro51mm",
    # Enduro
    "enduro3",
    # Forerunner
    "fr165", "fr165m", "fr255", "fr255m", "fr255s", "fr255sm", "fr265", "fr265s",
    "fr57042mm", "fr57047mm", "fr955", "fr965", "fr970",
    "fr55", "fr245", "fr245m", "fr745", "fr945", "fr945lte",
    # MARQ, D2, Instinct AMOLED
    "marq2", "marq2aviator", "d2mach1", "d2mach2", "d2mach2pro",
    "instinct3amoled45mm", "instinct3amoled50mm", "instinctcrossoveramoled",
    # Descent
    "descentmk2", "descentmk2s", "descentg1",
    # Instinct (two colours, a subscreen)
    "instinct2", "instinct2s", "instinct2x", "instinctcrossover",
    "instincte40mm", "instincte45mm", "instinct3solar45mm",
    # Touch-first: Venu and vivoactive
    "venu", "venu2", "venu2s", "venu2plus", "venu3", "venu3s", "venu441mm", "venu445mm",
    "vivoactive4", "vivoactive4s", "vivoactive5", "vivoactive6",
]


class Device:
    def __init__(self, pid: str):
        self.id = pid
        self.reason = ""
        d = PROFILES / pid
        if not (d / "compiler.json").exists():
            self.reason = "no profile: download it in the SDK Manager"
            return
        c = json.loads((d / "compiler.json").read_text())
        s = json.loads((d / "simulator.json").read_text())
        api = (d / f"{pid}.api.debug.xml").read_text(errors="replace")
        self.name = c.get("displayName", pid)
        self.width = c["resolution"]["width"]
        self.height = c["resolution"]["height"]
        self.launcher = c["launcherIcon"]["width"]
        self.amoled = c.get("displayType") == "amoled"
        self.shape = s["display"].get("shape")
        self.round = self.shape == "round"
        # A palette lists the colours of a watch with few: black and white only (the Instinct),
        # or eight with no grey. An empty one means full colour.
        pal = {x.upper() for x in c.get("palette", {}).get("colors", [])} - {"TRANSPARENT"}
        self.mono = bool(pal) and pal <= {"000000", "FFFFFF"}
        self.nogrey = bool(pal) and not self.mono and not {"AAAAAA", "555555"} & pal
        self.memory = {a["type"]: a["memoryLimit"] for a in c["appTypes"]}
        versions = [p.get("connectIQVersion", "0") for p in c.get("partNumbers", [])]
        self.ciq = max((tuple(int(x) for x in v.split(".")) for v in versions), default=(0,))
        self.ble = 'parent="Toybox_BluetoothLowEnergy_ScanResult"' in api
        keys = {k["id"]: k["location"] for k in s.get("keys", [])}
        self.keys = set(keys)
        # START's angle on the screen, counter-clockwise from 3 o'clock: an app
        # can draw its cue there.
        self.start = None
        if "enter" in keys:
            k, disp = keys["enter"], s["display"]["location"]
            dx = k["x"] + k["width"] / 2 - (disp["x"] + disp["width"] / 2)
            dy = (disp["y"] + disp["height"] / 2) - (k["y"] + k["height"] / 2)
            self.start = round(math.degrees(math.atan2(dy, dx)))
        self.touch = not {"up", "down"} <= self.keys   # no UP and DOWN: swipes stand in
        short = [f"{self.memory.get(t, 0) // 1024} KB for a {t}"
                 for t, need in MIN_MEMORY.items() if self.memory.get(t, 0) < need]
        if self.shape not in SHAPES:
            self.reason = f"a {self.shape} screen"
        elif not self.ble:
            self.reason = "no BLE for apps"
        elif self.ciq < MIN_CIQ:
            self.reason = "Connect IQ " + ".".join(map(str, self.ciq))
        elif short:
            self.reason = ", ".join(short)
        elif not KEYS <= self.keys:
            self.reason = "no " + "/".join(sorted(KEYS - self.keys)) + " button"

    @property
    def ui(self) -> str:
        """What MainView needs to know about this watch (read by source/ui/Ui.mc), e.g. start=21;mono."""
        flags = [f"start={self.start}"] if self.start is not None else []
        return ";".join(flags + (["mono"] if self.mono else ["nogrey"] if self.nogrey else []) + (["touch"] if self.touch else []))

    @property
    def ok(self) -> bool:
        return not self.reason


def shipping() -> list[Device]:
    return [d for d in map(Device, CANDIDATES) if d.ok]


def write_manifest(devices: list[Device]) -> None:
    text = MANIFEST.read_text()
    products = "".join(f'            <iq:product id="{d.id}"/>\n' for d in devices)
    text = re.sub(r'minApiLevel="[\d.]+"', 'minApiLevel="%d.%d.%d"' % MIN_CIQ, text)
    text = re.sub(r"(<iq:products>\n).*?(\s*</iq:products>)",
                  lambda m: m.group(1) + products.rstrip("\n") + m.group(2), text, flags=re.S)
    MANIFEST.write_text(text)


def main() -> None:
    devices = [Device(p) for p in CANDIDATES]
    if "--list" in sys.argv:
        for d in devices:
            if d.ok:
                print(d.id, d.width, d.launcher, "amoled" if d.amoled else "mip", d.ui)
        return
    for d in devices:
        if d.ok:
            print(f"ok   {d.id:22} {d.width}x{d.height} {'amoled' if d.amoled else 'mip   '} "
                  f"icon {d.launcher:3} CIQ {'.'.join(map(str, d.ciq)):6} "
                  f"app {d.memory['watchApp'] // 1024} KB  "
                  f"{d.shape:12} {d.ui}")
        else:
            print(f"out  {d.id:22} {d.reason}")
    ok = [d for d in devices if d.ok]
    print(f"{len(ok)} of {len(devices)} ship")
    if "--manifest" in sys.argv:
        write_manifest(ok)
        print(f"wrote {len(ok)} products into manifest.xml")


if __name__ == "__main__":
    main()
