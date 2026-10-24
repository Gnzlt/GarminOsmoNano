// What the screen shows and what the buttons ask for, whatever talks to the
// camera: NanoSession over the watch's own BLE today, possibly a bridge later.
// Values the camera has not reported are null, never guessed.
import Toybox.Lang;

class Camera {

    const MESSAGE_MS = 2500;
    const PHOTO_MS = 1500;

    enum {
        P_NO_BLE,      // the watch has no BLE for apps, or registration failed
        P_SCAN,        // looking for the camera
        P_CONNECT,     // found, waiting for the GATT link
        P_SESSION,     // linked, opening the DUML session
        P_APPROVE,     // the camera shows an Approve prompt
        P_LIVE,        // the camera answers
        P_CHOOSE,      // no camera saved yet: the rider picks one from the scan
        P_OFF          // disconnected by the rider; START reconnects
    }

    var phase as Number = P_SCAN;
    var name as String = "";
    var asleep as Boolean = false;       // the advert said asleep; connecting wakes it
    var seen as Number = 0;              // BLE devices the scan has seen, for the Searching screen
    var token as String = "";            // what the camera shows beside Approve
    var recording as Boolean? = null;
    var recordStart as Number = -1;     // System.getTimer() when recording was first seen
    var recordSeconds as Number? = null; // as the camera reports it, when that arrives whole
    var mode as Number? = null;
    var work as Number? = null;          // Nano.WORK_PHOTO or WORK_VIDEO, from the status
    // How well the link carries, 0-4, while live: from how long since the
    // camera last sent anything. Connect IQ gives no RSSI for a connected
    // device (only for scan results), so this is not distance, but a camera
    // drifting out of range shows here first.
    var linkBars as Number = 0;
    var message as String = "";          // a short line under the main display
    var messageAt as Number = -1000000;
    var photoAt as Number = -1000000;    // the camera confirmed a photo: a brief camera icon, no words
    var lastError as String = "";

    function initialize() {
    }

    function shutter() as Void {
    }

    function setMode(m as Number) as Void {
    }

    function reconnect() as Void {
    }

    // Change camera: drop the saved one and show the picker.
    function forget() as Void {
    }

    // Drop the link and stop looking, so the camera can go to sleep.
    function disconnect() as Void {
    }

    // Named devices the scan has seen, likely Nanos first, then nearest
    // first, for the picker: the camera can be renamed, and a Nano's DJI
    // advert record may not reach the watch, so the rider points at it.
    function candidates() as Array<Candidate> {
        return [] as Array<Candidate>;
    }

    // UP/DOWN and the Mode menu change nothing while the camera records:
    // a mode change mid-recording makes the Nano show an error.
    function modeLocked() as Boolean {
        return recording == true;
    }

    // REC on the screen.
    function capturing() as Boolean {
        return recording == true;
    }

    // For the log.
    function phaseName(p as Number) as String {
        switch (p) {
            case P_NO_BLE: return "no-ble";
            case P_SCAN: return "scan";
            case P_CONNECT: return "connect";
            case P_SESSION: return "session";
            case P_APPROVE: return "approve";
            case P_LIVE: return "live";
            case P_CHOOSE: return "choose";
            case P_OFF: return "off";
        }
        return p.format("%d");
    }

    // The state a button press acts on, for the log.
    function state() as String {
        return phaseName(phase) + " mode " + (mode != null ? Nano.modeName(mode) : "?")
                + " rec " + (recording == null ? "?" : recording ? "yes" : "no")
                + (modeLocked() ? " locked" : "");
    }

    function choose(name as String) as Void {
    }

    // Every 50 ms from the app's timer.
    function tick(now as Number) as Void {
    }

    function stop() as Void {
    }

    function say(text as String, now as Number) as Void {
        Log.add("say: " + text);
        message = text;
        messageAt = now;
    }

    // A photo the camera confirmed a moment ago.
    function photoJustTaken(now as Number) as Boolean {
        return now - photoAt < PHOTO_MS;
    }

    // The message, while it is recent.
    function currentMessage(now as Number) as String {
        return now - messageAt < MESSAGE_MS ? message : "";
    }

    // The recording time to show: the camera's if it arrived, else counted
    // here from when recording was first seen.
    function elapsed(now as Number) as Number {
        var s = recordSeconds;
        if (s != null) {
            return s;
        }
        return recordStart >= 0 ? (now - recordStart) / 1000 : 0;
    }

    // START takes a photo: the mode is Photo, or unknown but the camera's work
    // mode is photo.
    function photoNext() as Boolean {
        return mode == Nano.MODE_PHOTO || (mode == null && work == Nano.WORK_PHOTO);
    }

    function setRecording(r as Boolean, now as Number) as Void {
        if (r && recording != true) {
            recordStart = now;
        }
        if (!r) {
            recordStart = -1;
            recordSeconds = null;
        }
        recording = r;
    }
}

// A device in the picker.
class Candidate {
    var name as String;
    var rssi as Number;
    var nano as Boolean;   // its advert or name says Osmo Nano

    function initialize(n as String, r as Number, isNano as Boolean) {
        name = n;
        rssi = r;
        nano = isNano;
    }
}
