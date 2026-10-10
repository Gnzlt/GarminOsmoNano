# Changelog

OsmoNano versions as uploaded to the Connect IQ Store, release and beta. Each one is tagged
`v<version>`.

## 0.7.6 (unreleased): a trail when the app does not stop cleanly

Ported from Moto OBD, whose watch restarted mid-ride with nothing to say why.

- Each time the app starts it notes in **Diagnostics** how the last run ended. If it did not
  stop cleanly (the app crashed, the watch restarted, or the watch ended it), it says how long
  that run went, how much memory it used and had left, and what the camera link was doing.
- The saved camera, its name and the last mode are written so that a full or refusing watch
  storage can no longer end the app in the middle of a connection.

## 0.7.5 (unreleased): packaging only

- The same watch app as 0.7.4. The sources are reorganised (resources under `resources/`), the
  device list comes from the same script as the other Connect IQ apps, and the Store listing is
  kept in the repository.

## 0.7.4 (2026-10-08)

- The current launcher icon in both packages.

## 0.7.3 (2026-10-07)

- Control a DJI Osmo Nano from a Garmin watch over its own Bluetooth: record, stop, take a photo
  and pick the shooting mode, with the link and recording state on screen.
