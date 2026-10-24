// Demo build only: a fake camera that walks through every screen on a
// 60-second loop, so layouts can be checked in the simulator (which has no
// BLE) or on the watch without the camera. It shows only what the real watch
// can know. Buttons only show a message.
import Toybox.Lang;
import Toybox.System;

(:demo)
class DemoCamera extends Camera {

    function initialize() {
        Camera.initialize();
        name = "OsmoNano-1A2B";
        token = "W";
    }

    function tick(now as Number) as Void {
        var t = (now / 1000) % 60;
        // Only what reaches the real watch: the camera's record time
        // (0x02/0x80 @29) is cut off by the 20-byte BLE.
        recordSeconds = null;
        if (t < 5) {
            phase = P_CHOOSE;
        } else if (t < 6) {
            phase = P_SCAN;
        } else if (t < 7) {
            phase = P_CONNECT;
            asleep = true;
        } else if (t < 8) {
            phase = P_SESSION;
            asleep = false;
        } else if (t < 11) {
            phase = P_APPROVE;
        } else if (t < 20) {
            live(Nano.MODE_VIDEO, false, now);
        } else if (t < 35) {
            live(Nano.MODE_VIDEO, true, now);
        } else if (t < 42) {
            live(Nano.MODE_PHOTO, false, now);
            if (t == 38) {
                photoAt = now;
            }
        } else if (t < 50) {
            live(null, false, now);
            if (t == 44) {
                say("Not now", now);
            }
        } else if (t < 56) {
            live(Nano.MODE_TIMELAPSE, true, now);
            recordStart = now - (3725 + t - 50) * 1000;   // counted on the watch, as on a real Nano
        } else {
            phase = P_OFF;
            setRecording(false, now);
        }
    }

    private function live(m as Number?, rec as Boolean, now as Number) as Void {
        phase = P_LIVE;
        // The camera drifting away and back while recording.
        var t = (now / 1000) % 60;
        linkBars = t >= 24 && t < 33 ? [3, 2, 1, 1, 0, 1, 2, 3, 3][t - 24] : 4;
        mode = m;
        setRecording(rec, now);
    }

    function candidates() as Array<Candidate> {
        return [
            new Candidate("DroidNano", -31, true),
            new Candidate("Pixel 8", -45, false),
            new Candidate("Galaxy Buds", -62, false),
            new Candidate("Forerunner", -70, false)
        ] as Array<Candidate>;
    }

    function choose(name as String) as Void {
        say("Demo: chose " + name, System.getTimer());
    }

    function disconnect() as Void {
        say("Demo: disconnect", System.getTimer());
    }

    function reconnect() as Void {
        say("Demo: reconnect", System.getTimer());
    }

    function shutter() as Void {
        say("Demo: shutter", System.getTimer());
    }

    function setMode(m as Number) as Void {
        say("Demo: " + Nano.modeName(m), System.getTimer());
    }
}
