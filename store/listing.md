# Connect IQ Store listing: OsmoNano

Everything the Store's upload form asks for, at <https://apps.garmin.com/developer/upload>.
The live app: <https://apps.garmin.com/apps/67b74d57-fa8e-4da5-a073-7beffff693c6>.

## Upload

1. Bump `VERSION` and add its entry to `CHANGELOG.md`.
2. `scripts/build.sh --iq` builds both packages at that version:
   - `bin/OsmoNano.iq`: the app, as **App Version** `VERSION`;
   - `bin/OsmoNano-beta.iq`: the same under the beta app id, with **Beta App** ticked.
3. Paste the fields below. Images: `store/icon-500.png` (500 × 500), `store/hero.png`
   (1440 × 720) and `store/screens/*.jpg`, in order.
4. After the upload: `git tag v<VERSION> && git push --tags`.

Never upload without the owner's go-ahead (`AGENTS.md`).

## Name

OsmoNano

## Type and category

Watch app. Category: Tools. No activity types (it is not a data field).

## Description

Paste `store/description.txt`: the Store shows plain text only (no Markdown) and rejects some
non-ASCII characters. This section is the readable source; keep both in sync.

Control your DJI Osmo Nano from your wrist, over the watch's own Bluetooth: no phone needed.

- **START** records or stops; in Photo mode it takes a photo.
- **UP / DOWN** pick the shooting mode: Video, Photo, Timelapse, Hyperlapse, SuperNight, Slow-mo.
- The screen shows whether the camera is connected and how well, the mode, and while recording,
  REC and the elapsed time. A mark on the bezel shows what START will do.
- Touches are ignored, so a stray tap can't fire the camera.

**First connection:** close the camera's phone app (the camera takes one controller at a time),
put the Nano in its Vision Dock, open OsmoNano and pick the camera, then approve the watch on the
dock. After that it connects by itself.

**Watches:** 5-button round watches with Connect IQ 5.0 or later: fēnix 7, 8, 9 and E, epix
(Gen 2) / epix Pro, Enduro 3, Forerunner 165, 255 Music, 265, 570, 955, 965 and 970, MARQ (Gen 2),
D2 Mach and Instinct 3 AMOLED.

Independent project, not affiliated with or endorsed by DJI. Open source (MIT):
https://github.com/Gnzlt/GarminOsmoNano

## What's new

The version's entry in `CHANGELOG.md`, in plain text.
