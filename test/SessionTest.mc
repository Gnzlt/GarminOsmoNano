// Unit tests for NanoSession driven through a fake transport: the order and
// timing of the setup frames, both pairing outcomes, answering the camera's
// requests, status pushes, the buttons, the keepalive, the silence watchdog
// and Disconnect.
import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Records what the session sends, and owns the clock.
(:test)
class FakeTransport extends Transport {
    var sent as Array<ByteArray> = [] as Array<ByteArray>;
    var priority as Array<Boolean> = [] as Array<Boolean>;
    var restarts as Number = 0;
    var pauses as Number = 0;
    var t as Number = 1000;

    function initialize() {
        Transport.initialize();
    }

    function send(frame as ByteArray, first as Boolean) as Boolean {
        sent.add(frame);
        priority.add(first);
        return true;
    }

    function restart() as Void {
        restarts++;
    }

    function pause() as Void {
        pauses++;
    }

    function now() as Number {
        return t;
    }

    function last() as ByteArray {
        return sent[sent.size() - 1];
    }
}

(:test)
module S {
    // A session and its transport, linked up and 150 ms on (pairing sent).
    function start(t as FakeTransport) as NanoSession {
        Application.Properties.setValue("pairing", 0);
        Application.Properties.setValue("infoReply", 0);
        var s = new NanoSession(t);
        s.onLinkUp("OsmoNano-TEST");
        t.t += 150;
        s.tick(t.t);
        return s;
    }

    function cmd(f as ByteArray) as Number {
        return (f[9] << 8) | f[10];
    }

    function seq(f as ByteArray) as Number {
        return (f[6] << 8) | f[7];
    }

    // The camera's reply to the frame we sent.
    function reply(to as ByteArray, payload as ByteArray) as DumlFrame {
        return Duml.parse(Duml.build(to[5], Duml.ADDR_APP, seq(to), Duml.FLAG_RESPONSE, to[9], to[10], payload)) as DumlFrame;
    }

    function push(cmdSet as Number, cmdId as Number, payload as ByteArray) as DumlFrame {
        return Duml.parse(Duml.build(0x01, Duml.ADDR_APP, 0x0500, Duml.FLAG_PUSH, cmdSet, cmdId, payload)) as DumlFrame;
    }

    // A 60-byte status push in video mode, as a watch receives it: cut to 20 bytes.
    function status(recording as Boolean) as DumlFrame {
        var p = new [60]b;
        p[0] = recording ? 0x81 : 0x01;
        p[4] = Nano.WORK_VIDEO;
        var f = Duml.build(0x01, Duml.ADDR_APP, 0x0500, Duml.FLAG_PUSH, Nano.SET_CAMERA, Nano.ID_STATUS, p);
        return new FrameAssembler().feed(f.slice(0, 20))[0];
    }

    function count(t as FakeTransport, c as Number) as Number {
        var n = 0;
        for (var i = 0; i < t.sent.size(); i++) {
            if (cmd(t.sent[i]) == c) {
                n++;
            }
        }
        return n;
    }

    // Find the last frame sent with this command.
    function sentCmd(t as FakeTransport, c as Number) as ByteArray? {
        for (var i = t.sent.size() - 1; i >= 0; i--) {
            if (cmd(t.sent[i]) == c) {
                return t.sent[i];
            }
        }
        return null;
    }

    function live(t as FakeTransport) as NanoSession {
        var s = start(t);
        var pair = t.last();
        s.onFrame(reply(pair, [0x00, Nano.PAIR_PAIRED]b));
        s.tick(t.t);
        s.onFrame(reply(sentCmd(t, 0x5310) as ByteArray, [0x01, 0x00, 0x00, 0x00]b));
        t.t += 125;
        s.tick(t.t);   // session info
        return s;
    }
}

// Session open first, to 0xF0; the pairing 150 ms later, in one 20-byte frame.
(:test)
function setupOrder(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    var open = t.sent[0];
    var pair = t.sent[1];
    return t.sent.size() == 2 && S.cmd(open) == 0x002B && open[5] == Duml.ADDR_SESSION && open[11] == 0x04
            && S.cmd(pair) == 0x0745 && pair[5] == Duml.ADDR_WIFI && pair.size() == 20
            && s.phase == Camera.P_SESSION && s.token.equals("W");
}

// Already paired: the wake follows the reply at once, session info 125 ms
// later, and the wake's answer makes it live.
(:test)
function pairedPathGoesLive(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    s.onFrame(S.reply(t.last(), [0x00, Nano.PAIR_PAIRED]b));
    s.tick(t.t);
    var wake = t.last();
    t.t += 125;
    s.tick(t.t);
    var info = t.last();
    s.onFrame(S.reply(wake, [0x01, 0x00, 0x00, 0x00]b));
    return S.cmd(wake) == 0x5310 && wake[5] == Duml.ADDR_SYSTEM
            && S.cmd(info) == 0x0032 && info[5] == Duml.ADDR_DM368_4
            && s.phase == Camera.P_LIVE;
}

// No pairing reply: the wake goes anyway after 800 ms, as the reference
// implementations do.
(:test)
function wakeWithoutPairingReply(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    t.t += 700;
    s.tick(t.t);
    var before = S.sentCmd(t, 0x5310);
    t.t += 100;
    s.tick(t.t);
    return before == null && S.sentCmd(t, 0x5310) != null;
}

// A new pairing: Approve on the camera, then the camera's 0x07/0x46 request
// is answered (same seq, addresses swapped, 0xC0) and the wake is sent again.
(:test)
function approvalPath(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    s.onFrame(S.reply(t.last(), [0x00, Nano.PAIR_APPROVE]b));
    s.tick(t.t);
    var waiting = s.phase == Camera.P_APPROVE;
    var wakes = 0;
    var req = Duml.parse(Duml.build(Duml.ADDR_WIFI, Duml.ADDR_APP, 0x2233, Duml.FLAG_REQUEST,
            Nano.SET_WIFI, Nano.ID_PAIR_APPROVED, [0x01]b)) as DumlFrame;
    s.onFrame(req);
    var ack = S.sentCmd(t, 0x0746) as ByteArray;
    for (var i = 0; i < t.sent.size(); i++) {
        if (S.cmd(t.sent[i]) == 0x5310) {
            wakes++;
        }
    }
    s.onFrame(S.reply(S.sentCmd(t, 0x5310) as ByteArray, [0x01, 0x00, 0x00, 0x00]b));
    var first = t.priority[t.sent.indexOf(ack)];
    return waiting && ack[4] == Duml.ADDR_APP && ack[5] == Duml.ADDR_WIFI && S.seq(ack) == 0x2233
            && ack[8] == Duml.FLAG_RESPONSE && ack[11] == 0x00 && first && wakes == 2 && s.phase == Camera.P_LIVE;
}

// The camera's device-info request, cut short: answered once, with an empty
// payload by default and the 64-byte identity when chosen.
(:test)
function deviceInfoReplies(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    var full = Duml.build(0x48, Duml.ADDR_APP, 0x0909, Duml.FLAG_REQUEST, Nano.SET_SESSION, Nano.ID_DEVICE_INFO, new [30]b);
    var a = new FrameAssembler();
    var cut = a.feed(full.slice(0, 20))[0];
    s.onFrame(cut);
    s.onFrame(cut);
    var empty = t.last();
    var n = t.sent.size();
    Application.Properties.setValue("infoReply", 2);
    var cut2 = new FrameAssembler().feed(Duml.build(0x48, Duml.ADDR_APP, 0x0A0A, Duml.FLAG_REQUEST,
            Nano.SET_SESSION, Nano.ID_DEVICE_INFO, new [30]b).slice(0, 20))[0];
    s.onFrame(cut2);
    var blob = t.last();
    Application.Properties.setValue("infoReply", 0);
    return !cut.whole && empty.size() == 13 && empty[5] == 0x48 && S.seq(empty) == 0x0909
            && t.sent.size() == n + 1 && blob.size() == 77 && blob[12] == 0x41;
}

// Status pushes set recording; START stops when recording (02/02 [00]),
// starts when not.
(:test)
function shutterFollowsStatus(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(true));
    s.shutter();
    var stop = t.last();
    s.onFrame(S.status(false));
    s.shutter();
    var start = t.last();
    return S.cmd(stop) == 0x0202 && stop[11] == 0x00 && stop[5] == Duml.ADDR_CAMERA
            && S.count(t, 0x027C) == 0
            && S.cmd(start) == 0x0202 && start[11] == 0x01 && s.recording == false;
}

// A stop is sent again while the status still says recording, three times at
// most; a stopped status ends it.
(:test)
function stopBurstRepeats(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(true));
    s.shutter();
    for (var i = 0; i < 4; i++) {
        t.t += 1500;
        s.tick(t.t);
        s.onFrame(S.status(true));
    }
    var stubborn = S.count(t, 0x0202) == 3 && s.message.equals("Stop not confirmed");

    var t2 = new FakeTransport();
    var s2 = S.live(t2);
    s2.onFrame(S.status(true));
    s2.shutter();
    s2.onFrame(S.status(false));
    t2.t += 1500;
    s2.tick(t2.t);
    return stubborn && S.count(t2, 0x0202) == 1;
}

// The camera in Photo mode (work mode 00), mode never set from the watch:
// START takes a photo instead of a record the camera would refuse (DF), as in
// the first field test.
(:test)
function photoWorkModeTakesPhoto(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    var p = new [60]b;
    p[0] = 0x01;
    p[4] = Nano.WORK_PHOTO;
    s.onFrame(new FrameAssembler().feed(Duml.build(0x01, Duml.ADDR_APP, 0x0500, Duml.FLAG_PUSH,
            Nano.SET_CAMERA, Nano.ID_STATUS, p).slice(0, 20))[0]);
    s.shutter();
    var photo = t.last();
    s.onFrame(S.status(false));   // the rider picks a video mode on the camera
    var unknown = s.mode == null && s.work == Nano.WORK_VIDEO;
    s.shutter();
    return S.cmd(photo) == 0x0201 && s.mode == null && unknown && S.cmd(t.last()) == 0x0202;
}

// Once live, the status is polled every 2.5 s; a 20-byte cut of the reply
// still gives the recording state.
(:test)
function statusPoll(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    t.t += 2500;
    s.tick(t.t);
    var poll = S.sentCmd(t, 0x0270);
    if (poll == null) {
        logger.error("no poll");
        return false;
    }
    var p = new [61]b;
    p[1] = 0x81;
    p[5] = Nano.WORK_VIDEO;
    var reply = Duml.build(0x01, Duml.ADDR_APP, S.seq(poll), Duml.FLAG_RESPONSE, 0x02, 0x70, p);
    s.onFrame(new FrameAssembler().feed(reply.slice(0, 20))[0]);
    return poll.size() == 13 && poll[5] == Duml.ADDR_CAMERA && s.recording == true;
}

// A mode is only believed once the camera says OK; Photo makes START a photo.
(:test)
function modeThenPhoto(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.setMode(Nano.MODE_PHOTO);
    var set = t.last();
    var before = s.mode;
    s.onFrame(S.reply(set, [0x00]b));
    s.shutter();
    var photo = t.last();
    s.onFrame(S.reply(photo, [0xD9]b));
    return S.cmd(set) == 0x02E1 && set[11] == Nano.MODE_PHOTO && before == null
            && s.mode == Nano.MODE_PHOTO && S.cmd(photo) == 0x0201 && photo[11] == 0x01
            && s.message.equals("Not now");
}

// Buttons do nothing but say so before the camera is live.
(:test)
function notLiveIgnoresButtons(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.start(t);
    var n = t.sent.size();
    s.shutter();
    s.setMode(Nano.MODE_VIDEO);
    return t.sent.size() == n && s.message.equals("Not connected");
}

// A keepalive every second once nothing else is queued; ten silent seconds
// drop the link.
(:test)
function keepaliveAndSilence(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    var n = t.sent.size();
    t.t += 1000;
    s.tick(t.t);
    var ping = t.last();
    var pinged = t.sent.size() == n + 1 && S.cmd(ping) == 0x002B && ping[11] == 0x01 && ping[12] == 0x01;
    t.t += 9500;
    s.tick(t.t);
    return pinged && t.restarts == 1 && s.lastError.equals("camera silent");
}

// A mode the camera accepts shows as the mode label only: no message repeats it.
(:test)
function modeChangeNoMessage(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.setMode(Nano.MODE_VIDEO);
    s.onFrame(S.reply(t.last(), [0x00]b));
    return s.mode == Nano.MODE_VIDEO && s.message.equals("");
}

// On connect, once the camera says it isn't recording: the last mode it
// accepted from the watch is set again, once; Video when there is none.
(:test)
function restoreModeOnConnect(logger as Logger) as Boolean {
    Application.Storage.deleteValue("lastMode");
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(false));
    s.tick(t.t);
    var f = S.sentCmd(t, 0x02E1);
    var first = f != null && f[11] == Nano.MODE_VIDEO;
    s.onFrame(S.reply(f as ByteArray, [0x00]b));
    t.t += 3000;
    s.onFrame(S.status(false));
    s.tick(t.t);
    return first && S.count(t, 0x02E1) == 1 && s.mode == Nano.MODE_VIDEO;
}

// A mode the camera accepted is the one restored on the next connect.
(:test)
function restoreSavedMode(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.setMode(Nano.MODE_HYPERLAPSE);
    s.onFrame(S.reply(t.last(), [0x00]b));
    var t2 = new FakeTransport();
    var s2 = S.live(t2);
    s2.onFrame(S.status(false));
    s2.tick(t2.t);
    var f = S.sentCmd(t2, 0x02E1);
    Application.Storage.deleteValue("lastMode");
    return f != null && f[11] == Nano.MODE_HYPERLAPSE;
}

// Never while the camera records: the mode waits until it stops.
(:test)
function noRestoreWhileRecording(logger as Logger) as Boolean {
    Application.Storage.deleteValue("lastMode");
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(true));
    s.tick(t.t);
    var during = S.count(t, 0x02E1);
    s.onFrame(S.status(false));
    s.tick(t.t);
    return during == 0 && S.count(t, 0x02E1) == 1;
}

// Timelapse: the shutter command starts it (the record command is answered
// DF there), the OKed start shows as recording and locks the mode, and START
// stops it with the record stop, then the shutter when that is refused.
(:test)
function timelapseStartStop(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.setMode(Nano.MODE_TIMELAPSE);
    s.onFrame(S.reply(t.last(), [0x00]b));
    s.shutter();
    var start = t.last();
    s.onFrame(S.reply(start, [0x00]b));
    var on = s.capturing() && s.modeLocked();
    s.shutter();
    var stop = t.last();
    s.onFrame(S.reply(stop, [0xDF]b));
    var again = t.last();
    s.onFrame(S.reply(again, [0x00]b));
    return S.cmd(start) == 0x0201 && start[11] == 0x01 && on
            && S.cmd(stop) == 0x0202 && stop[11] == 0x00
            && S.cmd(again) == 0x0201 && !s.capturing() && s.mode == Nano.MODE_TIMELAPSE;
}

// No mode change while the camera records: the Nano shows an error.
(:test)
function noModeWhileRecording(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(true));
    s.tick(t.t);
    var n = S.count(t, 0x02E1);
    s.setMode(Nano.MODE_PHOTO);
    return S.count(t, 0x02E1) == n && s.modeLocked();
}

// Locked from a start the camera OKed, even with no status saying so, until
// its stop is OKed.
(:test)
function noModeAfterStartOk(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.shutter();
    s.onFrame(S.reply(t.last(), [0x00]b));
    s.setMode(Nano.MODE_PHOTO);
    var locked = S.count(t, 0x02E1) == 0;
    s.shutter();   // no status says recording: the OKed start still means stop
    var stop = t.last();
    s.onFrame(S.reply(stop, [0x00]b));
    s.setMode(Nano.MODE_PHOTO);
    return locked && S.cmd(stop) == 0x0202 && stop[11] == 0x00 && S.count(t, 0x02E1) == 1 && !s.modeLocked();
}

// The link's bars fall with the camera's silence and come back with its next frame.
(:test)
function linkBarsFollowSilence(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.onFrame(S.status(false));
    s.tick(t.t);
    var full = s.linkBars;
    t.t += 2000;
    s.tick(t.t);
    var weak = s.linkBars;
    s.onFrame(S.status(false));
    s.tick(t.t);
    return full == 4 && weak == 2 && s.linkBars == 4;
}

// A photo the camera confirms shows as a brief camera icon, not as words.
(:test)
function photoTakenIcon(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.setMode(Nano.MODE_PHOTO);
    s.onFrame(S.reply(t.last(), [0x00]b));
    s.shutter();
    s.onFrame(S.reply(t.last(), [0x00]b));
    var shown = s.photoJustTaken(t.t);
    return shown && s.message.equals("") && !s.photoJustTaken(t.t + 2000);
}

// Disconnect: the link pauses, and nothing more is sent, not even a keepalive.
(:test)
function disconnectPauses(logger as Logger) as Boolean {
    var t = new FakeTransport();
    var s = S.live(t);
    s.disconnect();
    var n = t.sent.size();
    t.t += 3000;
    s.tick(t.t);
    return t.pauses == 1 && t.sent.size() == n;
}
