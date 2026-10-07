// The DUML session with an Osmo Nano, in the order and with the timings of
// KonradIT/DJI-ESP32-Remote (logic/connect_logic.c):
//
//   1. session open   0x00/0x2b [04 00]  -> 0xF0
//   2. SetPairingPIN  0x07/0x45          -> 0x07   150 ms later
//      reply 00 01: paired before; 00 02: the camera shows Approve, and a
//      0x07/0x46 request follows when the rider presses it
//   3. wake           0x53/0x10          -> 0x1C   on the reply, or 800 ms
//   4. session info   0x00/0x32 "11"     -> 0x88   125 ms after the wake
//   then a keepalive 0x00/0x2b [01 01] every second, or the Nano drops the
//   link after 5-6 s. Live once the wake is answered or a status push arrives.
//   Once live, the status is also polled (0x02/0x70) every 2.5 s, as Action
//   Multicam Remote does, which keeps the recording state current even if
//   pushes stop.
//
// Disconnect drops the link and stops reconnecting, so the camera can go to
// sleep on its own timer: no command is known to put a Nano to sleep (the R
// SDK's 0x00/0x1A [03], tried in 0.5-0.6, did nothing).
//
// Stopping a recording is reinforced: 0x02/0x02 [00] is sent again while the
// status still says recording, up to three times (Action Multicam sends three
// bursts; its extra 0x02/0x7C [00] is left out: the Nano answers it E3).
//
// The watch's log file is small, and the camera repeats some frames every
// second (status pushes, its 0x00/0x81 who-are-you, 0x00/0x74), so each kind
// of frame is logged the first time only, plus every change of state.
//
// The camera's own requests are answered at once (flags 0xC0, addresses
// swapped, same seq): unanswered, it drops the link. Two choices nobody has
// tested at the watch's 20-byte MTU are settings (Menu > Protocol):
//   "pairing"   0: 4-char id + 1-char token, a 20-byte frame that fits one write
//               1: 32-char id + "WATCH", the length DJI uses, 52 bytes in 3 writes
//   "infoReply" how to answer requests that arrived cut short, and 0x00/0x81:
//               0: empty payload, 1: echo what arrived, 2: the 64-byte identity
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;

class NanoSession extends Camera {

    enum {
        S_DOWN,
        S_OPEN,    // session open sent
        S_PAIR,    // pairing sent
        S_WAKE     // wake sent; keepalives from here on
    }

    // What a sent request was, to read its reply.
    enum {
        K_OTHER,
        K_PAIR,
        K_WAKE,
        K_RECORD,
        K_PHOTO,
        K_MODE,
        K_POLL,
        K_TIMELAPSE
    }

    private const OPEN_TO_PAIR = 150;
    private const PAIR_WAIT = 800;
    private const WAKE_TO_INFO = 125;
    private const KEEPALIVE = 1000;
    private const SILENCE = 10000;      // nothing from the camera: drop and reconnect
    private const POLL = 2500;
    private const STOP_RETRY = 1500;    // still recording this long after a stop: send it again
    private const STOP_BURSTS = 3;
    private const STORE_SHORT_ID = "idShort";
    private const STORE_LONG_ID = "idLong";
    private const STORE_MODE = "lastMode";   // the last mode the camera accepted from the watch

    private var _t as Transport;
    private var _step as Number = S_DOWN;
    private var _stepAt as Number = 0;
    private var _seq as Number;
    private var _pairReplied as Boolean = false;
    private var _infoSent as Boolean = false;
    private var _lastKeepalive as Number = 0;
    private var _lastRx as Number = 0;
    private var _lastPoll as Number = 0;
    private var _stopBursts as Number = 0;   // stop bursts sent for the stop in progress
    private var _stopAt as Number = 0;
    private var _modeSet as Boolean = false; // the mode was set (restored or picked) this session
    private var _startedHere as Boolean = false; // a record start the camera OKed, no stop since
    private var _loggedPhase as Number = -1;
    private var _loggedBars as Number = 4;
    private var _rawPush as Number = -1;     // flags @0 << 8 | work @4, as last logged
    private var _rawPoll as Number = -1;     // the same from the 02/70 poll: logged apart, its bytes differ
    private var _pending as Dictionary<Number, Array<Number> > = {} as Dictionary<Number, Array<Number> >;
    private var _acked as Array<Number> = [] as Array<Number>;
    private var _logged as Array<Number> = [] as Array<Number>;   // frame kinds logged once

    function initialize(transport as Transport) {
        Camera.initialize();
        _t = transport;
        _seq = 0x1000 + (Math.rand().abs() % 0x6000);
    }

    // ---- From the link -------------------------------------------------

    function onLinkPhase(p as Number) as Void {
        phase = p;
    }

    function onLinkUp(cameraName as String) as Void {
        var now = _t.now();
        name = cameraName;
        phase = P_SESSION;
        _pending = {} as Dictionary<Number, Array<Number> >;
        _acked = [] as Array<Number>;
        _logged = [] as Array<Number>;
        work = null;
        _pairReplied = false;
        _infoSent = false;
        _lastRx = now;
        _lastKeepalive = now;
        _lastPoll = now;
        _stopBursts = 0;
        _modeSet = false;
        _startedHere = false;
        _rawPush = -1;
        _rawPoll = -1;
        mode = null;
        lastError = "";
        request(Duml.ADDR_SESSION, Nano.SET_SESSION, Nano.ID_PING, Nano.sessionOpen(), K_OTHER, 0, "open");
        to(S_OPEN, now);
    }

    function onLinkDown() as Void {
        _step = S_DOWN;
        _startedHere = false;
        recording = null;
        recordStart = -1;
        recordSeconds = null;
    }

    function onFrame(f as DumlFrame) as Void {
        var now = _t.now();
        _lastRx = now;
        logOnce(f);
        if (f.isRequest()) {
            answer(f);
            if (f.is(Nano.SET_WIFI, Nano.ID_PAIR_APPROVED)) {
                say("Approved", now);
                if (phase == P_APPROVE) {
                    phase = P_SESSION;
                    request(Duml.ADDR_SYSTEM, Nano.SET_SYSTEM, Nano.ID_WAKE, Nano.wake(), K_WAKE, 0, "wake");
                }
            }
        } else if (f.isResponse()) {
            onReply(f, now);
        } else if (f.is(Nano.SET_CAMERA, Nano.ID_STATUS)) {
            var declared = f.length - Duml.OVERHEAD;
            logRawStatus("push", f.payload, declared);
            onStatus(Nano.recording(f.payload, declared), Nano.workMode(f.payload, declared), now);
            var m = Nano.statusMode(f.payload);
            if (m != null) {
                mode = m;
            }
            var s = Nano.statusRecordTime(f.payload);
            if (s != null && recording == true) {
                recordSeconds = s;
            }
            live();
        }
    }

    // ---- Timing --------------------------------------------------------

    function tick(now as Number) as Void {
        if (phase != _loggedPhase) {
            Log.add("phase " + (_loggedPhase >= 0 ? phaseName(_loggedPhase) : "-") + " -> " + phaseName(phase));
            _loggedPhase = phase;
        }
        if (_step == S_DOWN) {
            return;
        }
        if (_step == S_OPEN && now - _stepAt >= OPEN_TO_PAIR) {
            sendPairing();
            to(S_PAIR, now);
        } else if (_step == S_PAIR && (_pairReplied || now - _stepAt >= PAIR_WAIT)) {
            request(Duml.ADDR_SYSTEM, Nano.SET_SYSTEM, Nano.ID_WAKE, Nano.wake(), K_WAKE, 0, "wake");
            to(S_WAKE, now);
        } else if (_step >= S_WAKE && !_infoSent && now - _stepAt >= WAKE_TO_INFO) {
            _infoSent = true;
            request(Duml.ADDR_DM368_4, Nano.SET_SESSION, Nano.ID_SESSION_INFO, Nano.sessionInfo(), K_OTHER, 0, "info");
        }
        // A keepalive or poll waits behind other frames: any frame keeps the link up.
        if (now - _lastKeepalive >= KEEPALIVE && _t.queued() == 0) {
            _lastKeepalive = now;
            request(Duml.ADDR_SESSION, Nano.SET_SESSION, Nano.ID_PING, Nano.keepalive(), K_OTHER, 0, "");
        }
        // The status that reaches the watch is cut before the mode's byte, so
        // the mode is set rather than read: the last one the camera accepted
        // from the watch, Video at first. Once the camera has said it isn't
        // recording (or is in photo work, where it doesn't say), never while
        // it records.
        if (phase == P_LIVE && !_modeSet && work != null && !modeLocked() && _t.queued() == 0) {
            _modeSet = true;
            var m = savedMode();
            request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_SHOOT_MODE, [m]b, K_MODE, m, "mode (restore)");
        }
        if (phase == P_LIVE && now - _lastPoll >= POLL && _t.queued() == 0) {
            _lastPoll = now;
            request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_STATE_GET, []b, K_POLL, 0, "");
        }
        if (_stopBursts > 0 && now - _stopAt >= STOP_RETRY) {
            if (recording != true) {
                _stopBursts = 0;
            } else if (_stopBursts < STOP_BURSTS) {
                sendStop(now);
            } else {
                _stopBursts = 0;
                say("Stop not confirmed", now);
            }
        }
        linkBars = barsFor(now - _lastRx);
        if (phase == P_LIVE && linkBars != _loggedBars && (linkBars <= 1 || _loggedBars <= 1)) {
            Log.add("link bars " + linkBars.format("%d") + " (silent " + (now - _lastRx).format("%d") + " ms)");
        }
        _loggedBars = linkBars;
        if (now - _lastRx > SILENCE) {
            lastError = "camera silent";
            Log.add("camera silent for " + (SILENCE / 1000).format("%d") + " s: reconnecting");
            _step = S_DOWN;
            _t.restart();
        }
    }

    // ---- Buttons -------------------------------------------------------

    // Photo mode takes a photo; any other mode starts or stops recording, by
    // the state the camera last pushed (the command is not a toggle).
    function shutter() as Void {
        var now = _t.now();
        if (phase != P_LIVE) {
            say("Not connected", now);
            return;
        }
        if (photoNext()) {
            request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_PHOTO, [0x01]b, K_PHOTO, 0, "photo");
            return;
        }
        // Timelapse answers the record command DF: it is a photo work mode
        // (field test 2026-10-06). Its capture is started with the shutter
        // command, as a photo is; untested, the log records the answers.
        if (mode == Nano.MODE_TIMELAPSE) {
            if (_startedHere) {
                request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_RECORD, [0x00]b, K_TIMELAPSE, 0, "timelapse stop (record 00)");
            } else {
                request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_PHOTO, [0x01]b, K_TIMELAPSE, 1, "timelapse start (shutter)");
            }
            return;
        }
        // A start the camera OKed counts as recording when no status says
        // otherwise: some modes' status may not report it.
        if (recording == true || (_startedHere && recording != false)) {
            _stopBursts = 0;
            sendStop(now);
            return;
        }
        request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_RECORD, [0x01]b, K_RECORD, 1, "record");
    }

    private function sendStop(now as Number) as Void {
        _stopBursts++;
        _stopAt = now;
        request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_RECORD, [0x00]b, K_RECORD, 0,
                "stop " + _stopBursts.format("%d"));
    }

    // Recording state and work mode from a push or a poll, each null when
    // not said. A work mode that contradicts the mode set from the watch
    // means it was changed on the camera: Photo is the one photo work mode,
    // so that one is known; a video-type mode is not, so it goes unknown.
    private function onStatus(r as Boolean?, w as Number?, now as Number) as Void {
        // Timelapse runs in the photo work mode (field test 2026-10-06), whose
        // status says nothing about a capture in progress: there it is read
        // from the start the camera OKed instead.
        var timelapse = mode == Nano.MODE_TIMELAPSE && (w == Nano.WORK_PHOTO || (w == null && work == Nano.WORK_PHOTO));
        if (timelapse) {
            r = null;
        }
        if (w != null && w != work) {
            work = w;
            if (w == Nano.WORK_PHOTO && timelapse) {
                // Timelapse, not Photo: both are photo work.
            } else if (w == Nano.WORK_PHOTO) {
                mode = Nano.MODE_PHOTO;
            } else if (mode == Nano.MODE_PHOTO) {
                mode = null;
            }
            Log.add("status: " + (w == Nano.WORK_PHOTO ? "photo" : "video") + " work mode");
        }
        if (r == false) {
            _startedHere = false;
        }
        if (r != null) {
            if (r != recording) {
                Log.add("status: " + (r ? "recording" : "not recording"));
            }
            setRecording(r, now);
            if (!r) {
                _stopBursts = 0;
            }
        }
    }

    // The status bytes the decoders read (flags @0, work mode @4), raw,
    // whenever they change: a work mode other than photo/video is otherwise
    // silently ignored.
    private function logRawStatus(src as String, p as ByteArray, declared as Number) as Void {
        if (p.size() <= Nano.STATUS_WORK_MODE) {
            return;
        }
        var raw = (p[0] << 8) | p[Nano.STATUS_WORK_MODE];
        var poll = src.equals("poll");
        if (raw != (poll ? _rawPoll : _rawPush)) {
            if (poll) {
                _rawPoll = raw;
            } else {
                _rawPush = raw;
            }
            Log.add("status " + src + " flags " + Log.byteHex(p[0]) + " work " + Log.byteHex(p[Nano.STATUS_WORK_MODE])
                    + " len " + declared.format("%d") + " got " + p.size().format("%d"));
        }
    }

    // Each kind of frame from the camera once (command, and whether it is a
    // request, a response or a push), and every reply to a command we sent.
    private function logOnce(f as DumlFrame) as Void {
        var p = f.isResponse() ? _pending.get(f.seq) : null;
        if (p != null && p[0] != K_POLL) {
            Log.rxFrame(f);
            return;
        }
        var key = (f.flags & 0xC0) << 16 | (f.cmdSet << 8) | f.cmdId;
        if (_logged.indexOf(key) < 0 && _logged.size() < 64) {
            _logged.add(key);
            Log.rxFrame(f);
        }
    }

    function setMode(m as Number) as Void {
        var now = _t.now();
        if (!Nano.isMode(m)) {
            return;
        }
        if (phase != P_LIVE) {
            say("Not connected", now);
            return;
        }
        if (modeLocked()) {
            Log.add("mode " + Nano.modeName(m) + " refused: recording");
            return;
        }
        _modeSet = true;
        request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_SHOOT_MODE, [m]b, K_MODE, m, "mode");
    }

    // A live Nano sends about ten frames a second (field test 2026-10-06), so
    // a gap of half a second already means frames lost on the air. Four bars
    // under 0.5 s, then 1.5 s, 3 s and 6 s; none from there until the
    // watchdog reconnects at SILENCE.
    private function barsFor(silent as Number) as Number {
        return silent < 500 ? 4 : silent < 1500 ? 3 : silent < 3000 ? 2 : silent < 6000 ? 1 : 0;
    }

    // Also locked after a start the camera OKed, for modes whose status may
    // not report recording.
    function modeLocked() as Boolean {
        return recording == true || _startedHere;
    }

    // Recording for the screen: the status says so, or (Timelapse, whose
    // status can't) the camera OKed the start.
    function capturing() as Boolean {
        return recording == true || (_startedHere && mode == Nano.MODE_TIMELAPSE);
    }

    private function kindName(k as Number) as String {
        switch (k) {
            case K_PAIR: return "pair";
            case K_WAKE: return "wake";
            case K_RECORD: return "record";
            case K_PHOTO: return "photo";
            case K_MODE: return "mode";
            case K_POLL: return "poll";
            case K_TIMELAPSE: return "timelapse";
        }
        return k.format("%d");
    }

    // Only ever a value from Nano.MODES: an unknown one froze a Nano.
    private function savedMode() as Number {
        var v = null;
        try {
            v = Application.Storage.getValue(STORE_MODE);
        } catch (e) {
        }
        return v instanceof Number && Nano.isMode(v) ? v : Nano.MODE_VIDEO;
    }

    function reconnect() as Void {
        _step = S_DOWN;
        _t.restart();
    }

    function forget() as Void {
        _step = S_DOWN;
        _t.forget();
    }

    function disconnect() as Void {
        _step = S_DOWN;
        _t.pause();
    }

    function candidates() as Array<Candidate> {
        return _t.candidates();
    }

    function choose(name as String) as Void {
        _step = S_DOWN;
        _t.choose(name);
    }

    // ---- Internals -----------------------------------------------------

    private function sendPairing() as Void {
        var long = Settings.number("pairing", 0) == 1;
        var id = identifier(long);
        token = long ? "WATCH" : "W";
        request(Duml.ADDR_WIFI, Nano.SET_WIFI, Nano.ID_PAIR, Nano.pairing(id, token),
                K_PAIR, 0, long ? "pair long" : "pair short");
    }

    // A random identifier per install, kept: the camera remembers approvals
    // under it, and a new one asks for approval again.
    private function identifier(long as Boolean) as String {
        var key = long ? STORE_LONG_ID : STORE_SHORT_ID;
        var v = null;
        try {
            v = Application.Storage.getValue(key);
        } catch (e) {
        }
        if (v instanceof String) {
            return v;
        }
        var chars = "0123456789abcdefghijklmnopqrstuvwxyz".toCharArray();
        var n = long ? 32 : 4;
        var out = [] as Array<Char>;
        for (var i = 0; i < n; i++) {
            out.add(chars[Math.rand().abs() % (long ? 16 : chars.size())]);
        }
        var id = StringUtil.charArrayToString(out);
        Application.Storage.setValue(key, id);
        return id;
    }

    private function request(dst as Number, cmdSet as Number, cmdId as Number, payload as ByteArray,
            kind as Number, value as Number, note as String) as Void {
        _seq = (_seq + 1) & 0xFFFF;
        var frame = Duml.build(Duml.ADDR_APP, dst, _seq, Duml.FLAG_REQUEST, cmdSet, cmdId, payload);
        if (kind != K_OTHER) {
            if (_pending.size() > 16) {
                _pending = {} as Dictionary<Number, Array<Number> >;
            }
            _pending.put(_seq, [kind, value] as Array<Number>);
        }
        if (note.length() > 0) {
            Log.tx(frame, note);
        }
        _t.send(frame, false);
    }

    // Swap the addresses, keep the seq, flags 0xC0, and go ahead of other
    // frames. Each request once: a partial one is answered when it arrives,
    // not again when it completes. The approval (0x07/0x46 [01]) is answered
    // [00], as the reference implementations do.
    private function answer(f as DumlFrame) as Void {
        var key = (f.seq << 16) | (f.cmdSet << 8) | f.cmdId;
        if (_acked.indexOf(key) >= 0) {
            return;
        }
        _acked.add(key);
        if (_acked.size() > 16) {
            _acked = _acked.slice(1, null);
        }
        var variant = Settings.number("infoReply", 0);
        var payload = f.payload;
        if (f.is(Nano.SET_SESSION, Nano.ID_DEVICE_INFO)) {
            payload = variant == 2 ? Nano.deviceInfo() : variant == 1 ? f.payload : []b;
        } else if (f.is(Nano.SET_WIFI, Nano.ID_PAIR_APPROVED)) {
            payload = [0x00]b;
        } else if (!f.whole && variant == 0) {
            payload = []b;
        }
        var frame = Duml.build(f.dst, f.src, f.seq, Duml.FLAG_RESPONSE, f.cmdSet, f.cmdId, payload);
        var kind = (f.cmdSet << 8) | f.cmdId;
        if (_logged.indexOf(-1 - kind) < 0) {
            _logged.add(-1 - kind);   // the first answer of each kind
            Log.tx(frame, "ack");
        }
        _t.send(frame, true);
    }

    private function onReply(f as DumlFrame, now as Number) as Void {
        var p = _pending.get(f.seq);
        if (p == null) {
            return;
        }
        _pending.remove(f.seq);
        var kind = p[0];
        if (kind == K_PAIR) {
            _pairReplied = true;
            var status = Nano.pairStatus(f.payload);
            Log.add("pairing reply " + (status != null ? status.format("%02x") : "?"));
            if (status == Nano.PAIR_APPROVE) {
                phase = P_APPROVE;
                say("Approve on the dock", now);
            }
            return;
        }
        if (kind == K_WAKE) {
            live();
            return;
        }
        if (kind == K_POLL) {
            logRawStatus("poll", f.payload, f.length - Duml.OVERHEAD);
            onStatus(Nano.polledRecording(f.payload), Nano.polledWork(f.payload), now);
            return;
        }
        var code = f.payload.size() > 0 ? f.payload[0] : -1;
        Log.add("reply " + kindName(kind) + (kind == K_MODE ? " " + Nano.modeName(p[1]) : kind == K_RECORD || kind == K_TIMELAPSE ? (p[1] == 1 ? " start" : " stop") : "")
                + ": " + (code < 0 ? "empty" : Log.byteHex(code) + " " + Nano.resultText(code)));
        if (code < 0) {
            return;
        }
        if (code == 0x00 && kind == K_RECORD) {
            _startedHere = p[1] == 1;
            if (p[1] == 0) {
                _stopBursts = 0;   // OKed: a retry while the camera still finishes is answered DF
            }
        }
        if (kind == K_TIMELAPSE) {
            if (code == 0x00) {
                _startedHere = p[1] == 1;
                recordStart = _startedHere ? now : -1;
            } else if (p[1] == 0) {
                // The record stop refused: try the shutter, as the start was.
                request(Duml.ADDR_CAMERA, Nano.SET_CAMERA, Nano.ID_PHOTO, [0x01]b, K_TIMELAPSE, 0, "timelapse stop (shutter)");
            }
        }
        if (code == 0x00 && kind == K_MODE) {
            mode = p[1];   // the screen's mode label is the confirmation
            Application.Storage.setValue(STORE_MODE, p[1]);
            Log.add("mode " + Nano.modeName(p[1]) + " saved as lastMode");
        } else if (code == 0x00 && kind == K_PHOTO) {
            photoAt = now;
        } else if (code != 0x00) {
            say(Nano.resultText(code), now);
        }
    }

    // The camera is in: the wake answered, or a status push. Not while it
    // still shows its Approve prompt.
    private function live() as Void {
        if (phase != P_APPROVE) {
            phase = P_LIVE;
            asleep = false;
        }
    }

    private function to(step as Number, now as Number) as Void {
        _step = step;
        _stepAt = now;
    }
}
