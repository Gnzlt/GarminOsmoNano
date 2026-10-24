# Changelog

OsmoNano versions as uploaded to the Connect IQ Store, release and beta. Each one is tagged
`v<version>`.

## 0.8.0 (2026-10-24): 39 more watches

OsmoNano now runs on 83 watches, up from 44: the Instinct, the Forerunner 255, the fēnix 5 Plus
and 6, the Descent and the Venu among them. None of those needed the app to change what it does.
They only needed the rules for which watches ship to be wider.

- **More watches:** fēnix 5 Plus and 6, Forerunner 55, 245, 245 Music, 745, 945 and 945 LTE,
  Forerunner 255 and 255S, Descent Mk2, Mk2S and G1, Instinct 2, 2S, 2X, Crossover (both),
  E (both sizes) and 3 Solar, Venu, Venu 2, 2S, 2 Plus, 3, 3S and 4 (both sizes), and vívoactive 4,
  4S, 5 and 6.
- **Instinct and the Forerunner 55:** two colours (the Instinct) means white on black, and eight colours with no grey (the Forerunner 55) means no greys. The picker's
  selection is a white pill, unlit link bars are outlines, and where the watch has a small round
  window at the top right (the Instinct), START's mark sits inside it and the top line stays beside
  it, with shorter words ("Offline", "Choose") so they fit.
- **START's mark** now follows each watch's own START button (21° on the Instinct, 25 to 33°
  elsewhere) instead of one fixed angle.
- **Venu and vívoactive have no UP and DOWN:** swipe up or down to change the mode (or move the
  camera list), and hold the screen for the menu. Taps are still ignored.
- **Memory:** in the simulator the demo peaks at about 61 KB on the Instinct 2 (96 KB for a watch
  app) and on the fēnix 6 and Forerunner 55 (128 KB), but none of these has run on a watch yet.

## 0.7.6 (unreleased): a trail when the app does not stop cleanly

A watch app that ends with nothing to say why is hard to debug on a ride, so the app now leaves a note.

- Each time the app starts it notes in **Diagnostics** how the last run ended. If it did not
  stop cleanly (the app crashed, the watch restarted, or the watch ended it), it says how long
  that run went, how much memory it used and had left, and what the camera link was doing.
- The saved camera, its name and the last mode are written so that a full or refusing watch
  storage can no longer end the app in the middle of a connection.

## 0.7.5 (unreleased): packaging only

- The same watch app as 0.7.4. The sources are reorganised (resources under `resources/`), the
  device list comes from `scripts/devices.py`, and the Store listing is
  kept in the repository.

## 0.7.4 (2026-10-08)

- The current launcher icon in both packages.

## 0.7.3 (2026-10-07)

- Control a DJI Osmo Nano from a Garmin watch over its own Bluetooth: record, stop, take a photo
  and pick the shooting mode, with the link and recording state on screen.
