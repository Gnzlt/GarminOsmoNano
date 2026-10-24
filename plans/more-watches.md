# Plan: more watches, proven with real builds

Done in 0.8.0 (83 products, up from 44). This file records how the list was widened and what is
still unproven.

## What limits a watch

OsmoNano's old floors in `scripts/devices.py` (Connect IQ 5.0, 768 KB, round screen, five
buttons) were project choices. What really limits a watch is:

1. the `BluetoothLowEnergy` module on the device (Garmin's list of supported devices for that module);
2. the watch-app memory limit in its profile;
3. a way to press shutter and open a menu.

The source uses only `BluetoothLowEnergy` (API 3.1), `Menu2` (3.0), Storage, Timer and plain `Dc`
drawing, and `setAntiAlias` is guarded with `has`, so `minApiLevel="3.2.7"` compiles with the
strict check (`-l 3`) on every product.

**Scope: watches only.** Bike computers (Edge) are out; the repo is MIT, so a fork can add one.

**Hard "no":** the original fēnix 5 (Garmin's BLE list leaves it out), the Venu Sq 2 without Music
(no BLE for apps in its profile), and the DJI Neo (a different camera; the app speaks the Nano's
DUML subset).

## Classes

| Class | Watches | What it needed |
|---|---|---|
| A: round, five buttons, colour | fēnix 5 Plus and 6, Forerunner 55 / 245 / 255 / 745 / 945, Descent Mk2 | Only the API and memory floors changed. |
| B: round, touch-first | Venu, Venu 2 / 3 / 4, vívoactive 4 / 5 / 6 | A swipe stands in for UP and DOWN, and a long press for MENU (Venu 4 and vívoactive 6 have none). |
| C: two colours, semi-octagon, subscreen | Instinct 2 / 3 Solar / E / Crossover, Descent G1 | White on black, START's mark inside the subscreen window, the top line beside it. |
| D: rectangular touch | Venu Sq 2 Music | Not done: it needs its own layout. |

## How it was proven

- The device profiles were downloaded with `connect-iq-sdk-manager device download -F -d <ids>`.
- A scratch copy of the repo (every id in the manifest, the floors lowered, art from
  `scripts/icons.sh`) built every new id with `monkeyc -d <id> -l 3 -w -r`: no errors, no warnings.
- The demo's 60-second loop ran in `ciq-sim` on the tightest devices. Peak memory: about 61 of
  91.8 kB on the Instinct 2 (96 KB limit), and about 61 of 123.8 kB on the fēnix 6 and Forerunner
  55 (128 KB limit). No out-of-memory and no crash.

## Still unproven

- A real watch of each class, above all an Instinct 2 (96 KB on a real watch, with Menu2 and the
  real BLE queues, neither of which the simulator measures).
- The touch controls: `ciq-sim` sends clicks and swipes straight to the START, UP and DOWN
  behaviours and never calls `onTap` or `onSwipe`, so a Venu or vívoactive is needed to confirm
  that a tap does nothing and a swipe changes the mode.
- BLE with a real camera on any of the new watches.
