// What NanoSession needs from the layer below: send a frame, drop the link or
// pause it, forget the remembered camera, the scan's candidates, and the time.
// BleLink provides it through BleTransport; the unit tests drive the session
// through a fake one, which is also why the clock lives here.
import Toybox.Lang;
import Toybox.System;

class Transport {
    function initialize() {
    }

    // Queue a whole frame; the link splits it into 20-byte writes. A priority
    // frame (an answer to the camera) goes ahead of the queue. False if the
    // link is down.
    function send(frame as ByteArray, priority as Boolean) as Boolean {
        return false;
    }

    // Frames queued and not yet written.
    function queued() as Number {
        return 0;
    }

    function restart() as Void {
    }

    function forget() as Void {
    }

    // Drop the link and stay down until restart().
    function pause() as Void {
    }

    function candidates() as Array<Candidate> {
        return [] as Array<Candidate>;
    }

    function choose(name as String) as Void {
    }

    function now() as Number {
        return System.getTimer();
    }
}

class BleTransport extends Transport {
    private var _link as BleLink;

    function initialize(link as BleLink) {
        Transport.initialize();
        _link = link;
    }

    function send(frame as ByteArray, priority as Boolean) as Boolean {
        return _link.sendFrame(frame, priority);
    }

    function queued() as Number {
        return _link.queued();
    }

    function restart() as Void {
        _link.restart();
    }

    function forget() as Void {
        _link.forget();
    }

    function pause() as Void {
        _link.pause();
    }

    function candidates() as Array<Candidate> {
        return _link.candidates();
    }

    function choose(name as String) as Void {
        _link.choose(name);
    }
}
