# Third-party notices

OsmoNano's DUML frame layout, CRC parameters, Osmo Nano command ids, payloads, status offsets and
session timings come from the three MIT-licensed open-source projects below. No code was copied:
the Monkey C here is a new implementation of what they document. The test vectors in
`test/DumlTest.mc` are reference frames quoted in them.

## DJI-ESP32-Remote

<https://github.com/KonradIT/DJI-ESP32-Remote>, branch `side-by-side`:
- `mediaprotocol/duml.{c,h}`
- `mediaprotocol/osmo_duml.{c,h}`
- `logic/connect_logic.c`
- `data/data.c`
- `docs/osmo-nano-protocol.md`

```
MIT License

Copyright (c) 2025–2026 Rhönschrat
```

## Osmosis

<https://github.com/KonradIT/osmosis>: `MEDIA_PROTOCOL.md`.

```
MIT License

Copyright (c) 2026 Konrad Iturbe
```

## Action Multicam Remote

<https://github.com/dstrat28/action-multicam-remote> (iOS):
- `ActionCamRemote/Bluetooth/DJINanoProtocol.swift`;
- `ActionCamRemote/Bluetooth/DJIExperimentalBLEClient.swift`;
- `ActionCamRemote/Bluetooth/BLECameraScanner.swift`.

It is the source of the status decoding, the status poll, the stop burst, the write gap, and the
advert's awake byte.

```
MIT License

Copyright (c) 2026 Multicam contributors
```

## MIT license text (all three)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Artwork

The launcher icon (`assets/icon-source.jpg` and everything `scripts/icons.sh` makes from it) and
the shooting-mode glyphs (`assets/modes-source/`, `assets/modes/`, the `mode_*.png` drawables) were
made for this project and are covered by its MIT license (`LICENSE`).

## Trademarks

DJI, Osmo and Osmo Nano are trademarks of SZ DJI Technology Co., Ltd. Garmin, fēnix, epix,
Forerunner, Enduro, MARQ, D2, Instinct and Connect IQ are trademarks of Garmin Ltd. or its
subsidiaries. They are used here only to say which devices the app works with. OsmoNano is an
independent project, not affiliated with, endorsed or sponsored by DJI or Garmin.
