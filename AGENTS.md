# GarminOsmoNano: agent rules

This repo (GarminOsmoNano) holds **OsmoNano**, a Garmin Connect IQ **watch app** in Monkey C, for
Garmin's 5-button round watches. The app keeps the name OsmoNano: on the watch, in the build outputs
(`bin/OsmoNano-*.prg`) and in the log file (`OSMONANO.TXT`). It controls a **DJI Osmo Nano** over
the watch's own BLE: start/stop recording, take a photo, pick the shooting mode, and show the link
state, the recording state and its time.

The Nano speaks the **DUML** protocol over BLE, as documented by the open-source projects credited
in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md); the subset used here is described in the
headers of `source/duml/` and `source/camera/NanoSession.mc`. It works on a Nano at the watch's
20-byte BLE limit (field test, 2026-10-06). The Protocol menu's choices stay for other firmware, and
every frame is logged.

For anything about the Connect IQ platform, look it up in Garmin's developer docs
(<https://developer.garmin.com/connect-iq/>).

## Hard rules

- **Never sideload to the watch, upload to the Connect IQ Store, or publish anything without
  asking first.** Building locally is always fine.
- **The developer key never enters the repo.** Each developer uses their own, at
  `~/.config/connectiq/developer_key.der` or `$CIQ_KEY`; `*.der` and `*.pem` are gitignored.
- No `.prg`, `.iq` or `bin/` output is committed. Field-test logs hold the camera's MAC and serial:
  they stay in the gitignored `logs/`.
- **Never send a shooting-mode value outside `Nano.MODES`**: sweeping unknown values froze a Nano.
- Commit and push only when the user asks.
- **A new version always gets both packages**, release and beta, at the same version
  (`scripts/build.sh --iq` builds both). Each release is tagged `v<VERSION>` on GitHub.

## Build

```sh
scripts/build.sh            # release .prg per product, and the test .prg, in bin/
scripts/build.sh --demo     # also bin/OsmoNano-demo.prg: a fake camera that walks every screen
scripts/build.sh --iq       # also bin/OsmoNano.iq and bin/OsmoNano-beta.iq (never upload without asking)
scripts/build.sh --beta     # the same: the Store package and the beta ($BETA_ID) always build together
scripts/test.sh             # every unit test, in the SDK simulator (or ciq-sim, if installed)
scripts/icons.sh            # launcher icon per product and the mode art per screen size (white, anti-aliased, on pure black); the Store images when store/ is there
scripts/devices.py          # which candidate products ship, and why the others don't; --manifest writes the list into manifest.xml
```

**The gate, for every change:**
1. `scripts/build.sh` compiles with strict type checking (`-l 3`) and **no warnings**.
2. `scripts/test.sh` passes every test.
3. After a UI change, run the demo build in the simulator and look at every screen:
   `connectiq`, then `monkeydo bin/OsmoNano-demo.prg fenix847mm` (or `ciq-sim run …` and
   `ciq-sim shot`, if installed). Check at least one small screen too (`DEVICE=fr165`). On
   fenix847mm, the default device, the simulator's buttons are at fixed window positions: hold UP
   (30,445) for the menu, DOWN (55,605), START (685,300). The simulator has no BLE: the real app
   stays on "Choose camera", with an empty list.

**Products:** the 5-button round watches with BLE for apps, Connect IQ 5.0+ and 768 KB for a
watch app: Fenix 7/8/9, Epix 2, Enduro 3, Forerunner 165-970, MARQ 2, D2, Instinct 3 AMOLED.
`scripts/devices.py` holds the candidates and checks each against its profile (download the
profiles in Garmin's SDK Manager first; a missing one is reported, never assumed). To add one, add
it to `CANDIDATES`, run `python3 scripts/devices.py --manifest`, then `scripts/icons.sh`: a new
screen size gets its own mode art, a new launcher size its own icon. Then look at the demo on it
(`DEVICE=<id> scripts/build.sh --demo`). The layout is proportional; pixel sizes go through
`MainView.px()`. Touch-first watches (no UP/DOWN) and the monochrome Instinct are out of scope.

## BLE and DUML rules

These come from the Nano's behaviour, as recorded by KonradIT. Breaking one fails on the camera, not
in the compiler.

- **One GATT operation in flight;** writes are split into 20-byte chunks (the Connect IQ maximum).
- **The GATT setup has three steps:** the CCCDs of both `FFF4` and `FFF5`, then `01 00` written to
  the `FFF4` value with response, then about 200 ms of settling. Without them, the camera ACKs
  writes at the ATT level and answers nothing.
- **Frames are at least 120 ms apart.** `FFF5` is write-without-response, and back-to-back writes
  are dropped. Answers to the camera's requests go ahead of the queue.
- **Answer every camera request** (flags `0x40`) once: flags `0xC0`, same seq, source and
  destination swapped. Unanswered, the camera drops the link.
- **A keepalive every second,** or the Nano drops the link after 5–6 s.
- **Notifications arrive cut to 20 bytes:** frames longer than that are delivered as partial (the
  header is checked, the payload is what arrived). A decoder returns null for a field whose bytes
  did not arrive. Never guess.
- **Recording state comes only from the camera's status** (push or `02/70` poll), never from a
  command's reply. It is read only from the full status form (37+ bytes) in video work mode
  (`flags & 0xC0`); the compact form's bit `0x40` is the dock.
  `0x02/0x02` is not a toggle.

## Style

- Monkey C with explicit types on every member, parameter and return (strict type check).
- Indentation of 4 spaces. Classes are `PascalCase`; members and functions are `camelCase`, with a
  leading `_` for private members.
- Comments say *why*. Each file starts with a short header saying what it owns.
- Ad-hoc experiments go in `scratch/`, which is gitignored.

## Layout

| Path | Contents |
|---|---|
| `manifest.xml`, `monkey.jungle`, `demo.jungle`, `beta.jungle` | App id, products, permission, source paths |
| `source/duml/` | `Crc`, `Frame` (build, parse, `FrameAssembler`), `Nano` (commands, decoders) |
| `source/camera/` | `Camera` (what the UI sees), `NanoSession` (the DUML session), `Transport` |
| `source/ble/BleLink.mc` | Scan, pair, GATT setup, paced chunked writes, notifications |
| `source/ui/` | `MainView`, `MainDelegate` (buttons), `Menus`, `LogView` (Diagnostics) |
| `source/Log.mc` | Frame log: the screen and `System.println` (the log file on the watch) |
| `demo/` | `DemoCamera`, only in the demo build |
| `test/` | `DumlTest` (frames against the reference frames), `SessionTest` (fake transport) |
| `assets/` | `icon-source.jpg`, the icon's source; `launcher_icon.png`, its 512 px cut-out; `modes-source/`, the mode glyphs' sources; `modes/`, their 512 px normalised masters |
| `gen/` | Generated by `scripts/icons.sh`, never edited: `resources-round-WxH/` (mode art per screen size) and `resources-<product>/` (launcher icon). `scripts/jungles.py` lists them in the jungles |
| `store/`, `docs/` | The maintainer's Store listing and working notes: gitignored, absent in a clone |
