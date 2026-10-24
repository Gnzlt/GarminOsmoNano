# Connect IQ Store listing: OsmoNano

Everything the Store's upload form asks for, at <https://apps.garmin.com/developer/upload>.
The live app: <https://apps.garmin.com/apps/67b74d57-fa8e-4da5-a073-7beffff693c6>.

## Upload

1. Bump `VERSION`, add its entry to `CHANGELOG.md`, and rewrite `store/whatsnew.txt` for the new version
   (and `store/description.txt` if what the app does or the watch list changed).
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

Control your DJI Osmo Nano from your wrist, with no phone.

OsmoNano connects straight to the camera over Bluetooth and lets you:
- start and stop recording
- take a photo
- pick the shooting mode: Video, Photo, Timelapse, Hyperlapse, SuperNight, Slow-mo
- see the link, the mode, and whether the camera records, with the time on the watch

The screen shows what each button will do: a red mark by START (record, stop or photo), and arrows by UP and DOWN when they change the mode.

**Watches**
Works on 83 Garmin watches, from the fenix 5 Plus to the fenix 9, the Forerunner 55 to 970, and the Descent, Instinct, Venu and vivoactive families.
- Instinct: the screen is drawn in white on black, with START's mark in the small round window.
- Venu and vivoactive have no UP and DOWN keys: swipe up or down to change the mode and hold the screen for the menu. START is still the shutter, and taps are ignored so a stray touch can't fire the camera.

**What you need**
- A DJI Osmo Nano camera.
- Its Vision Dock for the first pairing: the camera has no screen, so the Approve prompt appears on the dock.
- The camera's phone app closed or disconnected: the camera accepts one Bluetooth controller at a time.

**How to use**
1. Turn on the camera and keep it close. Open OsmoNano.
2. The first time, the app lists the devices it can see. Pick the camera with UP / DOWN and START. The app remembers it and connects by itself from then on.
3. On the first connection, approve the watch on the Vision Dock.
4. Once it shows Connected: START records or stops (in Photo mode it takes a photo), UP / DOWN change the mode. Hold UP for the menu: Disconnect lets the camera go to sleep, Change camera picks another one.

This is an experimental app.

Support and bug reports: hi@gnzlt.com

## What's new

Paste `store/whatsnew.txt`: plain ASCII text, a few short lines written for this version only (the
Store shows it to users updating the app). It is rewritten, not appended to, for every version;
`CHANGELOG.md` keeps the history.
