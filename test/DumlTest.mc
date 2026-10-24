// Unit tests for the DUML layer: CRCs and frames byte-for-byte against
// reference frames (from KonradIT/osmosis MEDIA_PROTOCOL.md and
// KonradIT/DJI-ESP32-Remote osmo_duml.h), frame sizes against the 20-byte write limit, the notification
// assembler, and the status decoders.
import Toybox.Lang;
import Toybox.Test;

(:test)
module T {
    // "55 0f 04" -> [0x55, 0x0F, 0x04]b; spaces ignored.
    function unhex(s as String) as ByteArray {
        var chars = s.toCharArray();
        var out = []b;
        var hi = -1;
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i].toNumber();
            var v = c >= 0x30 && c <= 0x39 ? c - 0x30 : c >= 0x61 && c <= 0x66 ? c - 0x61 + 10 : c >= 0x41 && c <= 0x46 ? c - 0x41 + 10 : -1;
            if (v < 0) {
                continue;
            }
            if (hi < 0) {
                hi = v;
            } else {
                out.add((hi << 4) | v);
                hi = -1;
            }
        }
        return out;
    }

    function same(logger as Logger, what as String, got as ByteArray, want as ByteArray) as Boolean {
        if (got.equals(want)) {
            return true;
        }
        logger.error(what + ": got " + Log.hex(got) + ", want " + Log.hex(want));
        return false;
    }

    function ascii(s as String) as ByteArray {
        var b = []b;
        var a = s.toUtf8Array();
        for (var i = 0; i < a.size(); i++) {
            b.add(a[i]);
        }
        return b;
    }
}

// The reference session open and keepalive, from MEDIA_PROTOCOL.md §21.
(:test)
function sessionFramesMatchReference(logger as Logger) as Boolean {
    var open = Duml.build(Duml.ADDR_APP, Duml.ADDR_SESSION, 0x1BCB, Duml.FLAG_REQUEST,
            Nano.SET_SESSION, Nano.ID_PING, Nano.sessionOpen());
    var keep = Duml.build(Duml.ADDR_APP, Duml.ADDR_SESSION, 0x1BCB, Duml.FLAG_REQUEST,
            Nano.SET_SESSION, Nano.ID_PING, Nano.keepalive());
    return T.same(logger, "open", open, T.unhex("550f04a202f01bcb40002b04009ab9"))
            && T.same(logger, "keepalive", keep, T.unhex("550f04a202f01bcb40002b0101abd6"));
}

// Osmosis' SetPairingPIN, §22: a 32-char identifier and the token "osmo".
(:test)
function pairingFrameMatchesOsmosis(logger as Logger) as Boolean {
    var f = Duml.build(Duml.ADDR_APP, Duml.ADDR_WIFI, 0x00A0, Duml.FLAG_REQUEST, Nano.SET_WIFI, Nano.ID_PAIR,
            Nano.pairing("284ae5b8d76b3375a04a6417ad71bea3", "osmo"));
    return T.same(logger, "pairing", f, T.unhex(
            "553304c2020700a0400745203238346165356238643736623333373561303461363431376164373162656133046f736d6f8c02"));
}

// The reference config subscribe (osmo_duml.h): another address and seq.
(:test)
function configFrameMatchesReference(logger as Logger) as Boolean {
    var payload = T.unhex("01000600");
    payload.addAll(T.ascii("camera"));
    var f = Duml.build(Duml.ADDR_APP, 0x28, 0x15C7, Duml.FLAG_REQUEST, 0x00, 0x99, payload);
    return T.same(logger, "config", f, T.unhex("55170438022815c74000990100060063616d657261e5af"));
}

// What has to fit one 20-byte write, and what cannot.
(:test)
function frameSizes(logger as Logger) as Boolean {
    var a = Duml.ADDR_APP;
    var r = Duml.FLAG_REQUEST;
    var sizes = [
        [Duml.build(a, Duml.ADDR_SESSION, 1, r, 0x00, 0x2B, Nano.sessionOpen()).size(), 15],
        [Duml.build(a, Duml.ADDR_SESSION, 1, r, 0x00, 0x2B, Nano.keepalive()).size(), 15],
        [Duml.build(a, Duml.ADDR_SYSTEM, 1, r, 0x53, 0x10, Nano.wake()).size(), 17],
        [Duml.build(a, Duml.ADDR_DM368_4, 1, r, 0x00, 0x32, Nano.sessionInfo()).size(), 18],
        [Duml.build(a, Duml.ADDR_WIFI, 1, r, 0x07, 0x45, Nano.pairing("ab12", "W")).size(), 20],
        [Duml.build(a, Duml.ADDR_CAMERA, 1, r, 0x02, 0x02, [0x01]b).size(), 14],
        [Duml.build(a, Duml.ADDR_CAMERA, 1, r, 0x02, 0x01, [0x01]b).size(), 14],
        [Duml.build(a, Duml.ADDR_CAMERA, 1, r, 0x02, 0xE1, [0x05]b).size(), 14],
        [Duml.build(a, Duml.ADDR_WIFI, 1, r, 0x07, 0x45,
                Nano.pairing("0123456789abcdef0123456789abcdef", "WATCH")).size(), 52],
        [Duml.build(0x02, 0x48, 1, Duml.FLAG_RESPONSE, 0x00, 0x81, Nano.deviceInfo()).size(), 77]
    ] as Array<Array<Number> >;
    var ok = true;
    for (var i = 0; i < sizes.size(); i++) {
        if (sizes[i][0] != sizes[i][1]) {
            logger.error("frame " + i + ": " + sizes[i][0] + " bytes, want " + sizes[i][1]);
            ok = false;
        }
    }
    return ok;
}

// The 47-byte battery push (0x0D/0x02) an Osmo Action 5 Pro sent a watch, cut to 20
// bytes (dji-sdk/Osmo-GPS-Controller-Demo issue #14): a valid header, a partial frame.
(:test)
function truncatedNotificationIsPartial(logger as Logger) as Boolean {
    var chunk = T.unhex("552F046305251721000D02004E11000000000000");
    var a = new FrameAssembler();
    var frames = a.feed(chunk);
    if (frames.size() != 1) {
        logger.error("frames: " + frames.size());
        return false;
    }
    var f = frames[0];
    return !f.whole && f.length == 47 && f.src == 0x05 && f.seq == 0x1721
            && f.is(0x0D, 0x02) && f.payload.size() == 9;
}

// A frame in three notifications: partial at once, whole when the rest comes.
(:test)
function continuationsAreJoined(logger as Logger) as Boolean {
    var status = new [60]b;
    status[0] = 0x81;
    status[4] = Nano.WORK_VIDEO;
    status[29] = 0x3C;
    status[57] = Nano.MODE_TIMELAPSE;
    var frame = Duml.build(0x01, 0x02, 0x0102, Duml.FLAG_PUSH, Nano.SET_CAMERA, Nano.ID_STATUS, status);
    var a = new FrameAssembler();
    var first = a.feed(frame.slice(0, 20));
    var second = a.feed(frame.slice(20, 40));
    var third = a.feed(frame.slice(40, null));
    if (first.size() != 1 || second.size() != 0 || third.size() != 1) {
        logger.error("counts " + first.size() + "/" + second.size() + "/" + third.size());
        return false;
    }
    var p = first[0];
    var w = third[0];
    return !p.whole && Nano.recording(p.payload, p.length - Duml.OVERHEAD) == true
            && Nano.statusMode(p.payload) == null
            && w.whole && Nano.statusMode(w.payload) == Nano.MODE_TIMELAPSE
            && Nano.statusRecordTime(w.payload) == 60;
}

// Bytes with no header and nothing pending are dropped; a frame with a bad
// CRC16 is not delivered.
(:test)
function noiseAndBadFramesAreDropped(logger as Logger) as Boolean {
    var a = new FrameAssembler();
    var none = a.feed(T.unhex("aa330002000000"));
    var good = Duml.build(0x01, 0x02, 7, Duml.FLAG_RESPONSE, 0x02, 0x02, [0x00]b);
    var bad = good.slice(0, null);
    bad[bad.size() - 1] ^= 0xFF;
    var badOut = a.feed(bad);
    var goodOut = a.feed(good);
    return none.size() == 0 && a.noise == 7 && badOut.size() == 0
            && goodOut.size() == 1 && goodOut[0].whole && goodOut[0].isResponse();
}

(:test)
function modeCarousel(logger as Logger) as Boolean {
    return Nano.stepMode(Nano.MODE_VIDEO, 1) == Nano.MODE_PHOTO
            && Nano.stepMode(Nano.MODE_VIDEO, -1) == Nano.MODE_SLOWMO
            && Nano.stepMode(Nano.MODE_SLOWMO, 1) == Nano.MODE_VIDEO
            && Nano.stepMode(null, 1) == Nano.MODE_VIDEO
            && Nano.stepMode(0x63, -1) == Nano.MODE_VIDEO
            && !Nano.isMode(0x03);
}

// Recording only from the full status (37+ bytes) in a video work mode, as
// Action Multicam Remote reads it on a Nano; the compact form's bit 0x40 is
// the dock, not recording.
(:test)
function recordingNeedsFullStatus(logger as Logger) as Boolean {
    var s = new [9]b;   // what survives a 20-byte notification
    s[4] = Nano.WORK_VIDEO;
    s[0] = 0x81;
    var rec = Nano.recording(s, 60);
    s[0] = 0x41;
    var bit6 = Nano.recording(s, 60);
    s[0] = 0x01;
    var stopped = Nano.recording(s, 60);
    var compact = Nano.recording([0x40, 0, 0, 0, Nano.WORK_VIDEO]b, 34);
    s[4] = Nano.WORK_PHOTO;
    s[0] = 0xC1;
    var photo = Nano.recording(s, 60);
    s[4] = 0x02;   // playback
    var playback = Nano.recording(s, 60);
    // The Nano's 5-byte poll reply, as the field test logged it.
    var poll = Nano.polledRecording([0x00, 0x81, 0x02, 0x80, 0x00, 0x01]b);
    var pollPhoto = Nano.polledRecording([0x00, 0x01, 0x02, 0x80, 0x00, 0x00]b) == false
            && Nano.polledWork([0x00, 0x01, 0x02, 0x80, 0x00, 0x00]b) == Nano.WORK_PHOTO;
    var pollFailed = Nano.polledRecording([0xE0, 0x81, 0, 0, 0, Nano.WORK_VIDEO]b);
    return rec == true && bit6 == true && stopped == false && compact == null && photo == false
            && playback == null && poll == true && pollPhoto && pollFailed == null;
}

// The advert: the classic Nano record with its awake byte, the newer format
// (OsmoNanoPreview), and other cameras.
(:test)
function advertParsing(logger as Logger) as Boolean {
    var awake = T.unhex("190000 a1b2c3d4e5f6 02");
    var asleep = T.unhex("190000 a1b2c3d4e5f6 03");
    var newer = T.unhex("0000 000000 04 00000000 de00");
    var action = T.unhex("150000 a1b2c3d4e5f6 02");
    var otherNewer = T.unhex("0000 000000 04 00000000 df00");
    return Nano.advert(awake) == Nano.ADV_AWAKE && Nano.advert(asleep) == Nano.ADV_ASLEEP
            && Nano.advert(newer) == Nano.ADV_NANO && Nano.advert(action) == Nano.ADV_NOT_NANO
            && Nano.advert(otherNewer) == Nano.ADV_NOT_NANO && Nano.advert(null) == Nano.ADV_NOT_NANO
            && Nano.advert([0x19, 0x00]b) == Nano.ADV_NANO;
}

// The raw advert: DJI manufacturer data inside the AD structures, the name
// record, and an unrelated device.
(:test)
function rawAdvertParsing(logger as Logger) as Boolean {
    var mfg = T.unhex("020106 0DFF AA08 190000 a1b2c3d4e5f6 02");
    var name = T.unhex("020106 0E09 4f736d6f4e616e6f2d31413242");   // "OsmoNano-1A2B"
    var other = T.unhex("020106 0BFF 4C00 0215 0011223344 55");
    return Nano.rawAdvert(mfg) == Nano.ADV_AWAKE && Nano.rawAdvert(name) == Nano.ADV_NANO
            && Nano.rawAdvert(other) == Nano.ADV_NOT_NANO && Nano.rawIsDji(mfg) && !Nano.rawIsDji(other)
            && Nano.rawAdvert([]b) == Nano.ADV_NOT_NANO;
}

(:test)
function rawFff0(logger as Logger) as Boolean {
    return Nano.rawHasFff0(T.unhex("020106 050312 18F0FF")) && !Nano.rawHasFff0(T.unhex("020106 03030F18"))
            && !Nano.rawHasFff0(T.unhex("0716F0FF0101"));
}
