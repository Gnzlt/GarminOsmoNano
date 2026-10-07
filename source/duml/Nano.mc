// The Osmo Nano's DUML commands and status fields: the subset this app uses.
// Ids, payloads and offsets come from KonradIT/DJI-ESP32-Remote
// (mediaprotocol/osmo_duml.h) and dstrat28/action-multicam-remote
// (DJINanoProtocol.swift, DJIExperimentalBLEClient.swift), both tested on a Nano,
// and KonradIT/osmosis (see THIRD_PARTY_NOTICES.md). Every control frame the
// app sends is 13-18 bytes, so it fits one 20-byte write; only the long pairing
// frame (52 bytes) and the identity reply (77 bytes) take several.
import Toybox.Lang;

module Nano {

    const SET_SESSION = 0x00;
    const ID_PING = 0x2B;          // session open [04 00], keepalive [01 01]
    const ID_SESSION_INFO = 0x32;
    const ID_DEVICE_INFO = 0x81;   // the camera asks us who we are
    const SET_SYSTEM = 0x53;
    const ID_WAKE = 0x10;
    const SET_WIFI = 0x07;
    const ID_PAIR = 0x45;          // SetPairingPIN
    const ID_PAIR_APPROVED = 0x46; // a request from the camera once the rider approves
    const SET_CAMERA = 0x02;
    const ID_PHOTO = 0x01;         // [01]; only in Photo mode, else 0xD9
    const ID_RECORD = 0x02;        // [01] start, [00] stop; not a toggle
    const ID_STATE_GET = 0x70;     // empty; the reply is a result byte, then the status summary
    const ID_STATUS = 0x80;        // push, 60 bytes
    const ID_SHOOT_MODE = 0xE1;    // [mode]

    // SetPairingPIN replies.
    const PAIR_PAIRED = 0x01;
    const PAIR_APPROVE = 0x02;

    // Shooting modes, as 0x02/0xE1 takes them and status byte 57 reports them.
    // Never send any other value: sweeping unknown ones froze a Nano solid.
    const MODE_SLOWMO = 0x00;
    const MODE_VIDEO = 0x01;
    const MODE_TIMELAPSE = 0x02;
    const MODE_PHOTO = 0x05;
    const MODE_HYPERLAPSE = 0x0A;
    const MODE_SUPERNIGHT = 0x28;

    // The camera's own carousel order.
    const MODES = [MODE_VIDEO, MODE_PHOTO, MODE_TIMELAPSE, MODE_HYPERLAPSE, MODE_SUPERNIGHT, MODE_SLOWMO];

    // The status summary (0x02/0x80 push, 60 bytes; also the 0x02/0x70 reply
    // after its result byte). Only the full form, 37 bytes or more, says
    // whether the camera records: in the compact form (34-36 bytes) bit 0x40
    // means the Vision Dock or external power is attached.
    const STATUS_FLAGS = 0;          // u32-LE; bits 6-7 (0xC0): recording
    const STATUS_WORK_MODE = 4;      // 0x00 photo, 0x01 video; others (playback...) say nothing
    const STATUS_RECORD_TIME = 29;   // u16-LE seconds
    const STATUS_MODE = 57;          // the shooting mode, as 0x02/0xE1 sets it
    const STATUS_FULL = 37;
    const WORK_PHOTO = 0x00;
    const WORK_VIDEO = 0x01;

    // Advertisement (Connect IQ's getManufacturerSpecificData(0x08AA), the
    // company id already stripped).
    const DJI_COMPANY = 0x08AA;
    const NANO_MODEL = 0x0019;       // classic: 19 00 00 <MAC, 6 bytes> <state>
    const NANO_PRODUCT = 222;        // newer format (OsmoNanoPreview): "OW001"
    const ADV_NOT_NANO = 0;
    const ADV_AWAKE = 1;
    const ADV_ASLEEP = 2;
    const ADV_NANO = 3;              // a Nano, state not in the advert

    function sessionOpen() as ByteArray { return [0x04, 0x00]b; }
    function keepalive() as ByteArray { return [0x01, 0x01]b; }
    function wake() as ByteArray { return [0x00, 0x00, 0x00, 0x00]b; }
    function sessionInfo() as ByteArray { return [0x31, 0x31, 0x00, 0x00, 0x00]b; }   // "11"

    // SetPairingPIN: PackString(identifier) + PackString(token), each a length
    // byte then the ASCII. The camera remembers the identifier and shows the
    // token beside its Approve button.
    function pairing(identifier as String, token as String) as ByteArray {
        var b = []b;
        packString(b, identifier);
        packString(b, token);
        return b;
    }

    function packString(b as ByteArray, s as String) as Void {
        var bytes = s.toUtf8Array();
        b.add(bytes.size());
        for (var i = 0; i < bytes.size(); i++) {
            b.add(bytes[i]);
        }
    }

    // The 64-byte "APP" identity the reference implementations answer 0x00/0x81 with: 00 "APP",
    // 0x02 at [34], 02 08 at [42..43], zeros elsewhere.
    function deviceInfo() as ByteArray {
        var b = new [64]b;
        b[1] = 0x41;
        b[2] = 0x50;
        b[3] = 0x50;
        b[34] = 0x02;
        b[42] = 0x02;
        b[43] = 0x08;
        return b;
    }

    function isMode(m as Number) as Boolean {
        return MODES.indexOf(m) >= 0;
    }

    function modeName(m as Number?) as String {
        if (m == null) {
            return "";
        }
        switch (m) {
            case MODE_VIDEO: return "Video";
            case MODE_PHOTO: return "Photo";
            case MODE_TIMELAPSE: return "Timelapse";
            case MODE_HYPERLAPSE: return "Hyperlapse";
            case MODE_SUPERNIGHT: return "SuperNight";
            case MODE_SLOWMO: return "Slow-mo";
        }
        return "";
    }

    // The mode `step` places after m in the carousel (-1 for before); the
    // first one if m is unknown.
    function stepMode(m as Number?, step as Number) as Number {
        var i = m != null ? MODES.indexOf(m) : -1;
        if (i < 0) {
            return MODES[0];
        }
        var n = MODES.size();
        return MODES[((i + step) % n + n) % n];
    }

    // A command reply's first payload byte.
    function resultText(code as Number) as String {
        switch (code) {
            case 0x00: return "OK";
            case 0xD9: return "Not now";          // wrong state, e.g. a photo in a video mode
            case 0xDF: return "Not in this mode"; // e.g. record in Photo mode, or start while recording
            case 0xE0: return "Unsupported";
            case 0xE3: return "Bad parameter";
        }
        return "Error " + code.format("%02X");
    }

    // ---- Decoders: null when the field's bytes did not arrive -----------

    // Whether the camera records, from a status push whose declared length
    // (it can be more than arrived) is `declared`. Null when it doesn't say.
    function recording(status as ByteArray, declared as Number) as Boolean? {
        return declared >= STATUS_FULL ? summaryRecording(status) : null;
    }

    // The work mode (WORK_PHOTO or WORK_VIDEO) from a status push, or null.
    function workMode(status as ByteArray, declared as Number) as Number? {
        return declared >= STATUS_FULL ? summaryWork(status) : null;
    }

    // The same from a 0x02/0x70 reply: a result byte, then a short summary.
    // On the Nano it is 5 bytes (01 02 80 00 00 idle in Photo, 81 .. 01
    // recording in Video: field test 2026-10-06), laid out like the start of
    // the full push, so both rules apply to it.
    function polledRecording(reply as ByteArray) as Boolean? {
        return reply.size() > 1 && reply[0] == 0x00 ? summaryRecording(reply.slice(1, null)) : null;
    }

    function polledWork(reply as ByteArray) as Number? {
        return reply.size() > 1 && reply[0] == 0x00 ? summaryWork(reply.slice(1, null)) : null;
    }

    // Video work mode and flags & 0xC0: recording; Photo work mode: not.
    function summaryRecording(s as ByteArray) as Boolean? {
        var work = summaryWork(s);
        if (work == null) {
            return null;
        }
        return work == WORK_VIDEO && (s[STATUS_FLAGS] & 0xC0) != 0;
    }

    function summaryWork(s as ByteArray) as Number? {
        if (s.size() <= STATUS_WORK_MODE) {
            return null;
        }
        var w = s[STATUS_WORK_MODE];
        return w == WORK_PHOTO || w == WORK_VIDEO ? w : null;
    }

    // What the advert says about a Nano: ADV_NOT_NANO, ADV_AWAKE, ADV_ASLEEP or ADV_NANO.
    // The newer format is told by bit 2 of byte 5 and a product type at [10..11];
    // the classic Nano advert is 10 bytes, too short for that test to misfire.
    function advert(mfg as ByteArray?) as Number {
        if (mfg == null || mfg.size() < 2) {
            return ADV_NOT_NANO;
        }
        if (mfg.size() >= 12 && (mfg[5] & 0x04) != 0 && u16(mfg, 10) == NANO_PRODUCT) {
            return ADV_NANO;
        }
        if (u16(mfg, 0) != NANO_MODEL) {
            return ADV_NOT_NANO;
        }
        if (mfg.size() >= 10) {
            if (mfg[9] == 0x02) {
                return ADV_AWAKE;
            }
            if (mfg[9] == 0x03) {
                return ADV_ASLEEP;
            }
        }
        return ADV_NANO;
    }

    function statusRecordTime(status as ByteArray) as Number? {
        return u16(status, STATUS_RECORD_TIME);
    }

    function statusMode(status as ByteArray) as Number? {
        if (status.size() <= STATUS_MODE) {
            return null;
        }
        var m = status[STATUS_MODE];
        return isMode(m) ? m : null;
    }

    // The same from the raw advertising bytes, walking its AD structures
    // ([len][type][data]): manufacturer data (0xFF) under DJI's company id, or a
    // name (0x08/0x09) starting "OsmoNano". A fallback for when Connect IQ's own
    // manufacturer-data lookup gives nothing.
    function rawAdvert(raw as ByteArray) as Number {
        var i = 0;
        var found = ADV_NOT_NANO;
        while (i + 1 < raw.size()) {
            var len = raw[i];
            if (len == 0 || i + 1 + len > raw.size()) {
                break;
            }
            var type = raw[i + 1];
            if (type == 0xFF && len >= 3 && (raw[i + 2] | (raw[i + 3] << 8)) == DJI_COMPANY) {
                var a = advert(raw.slice(i + 4, i + 1 + len));
                if (a != ADV_NOT_NANO) {
                    return a;
                }
            } else if ((type == 0x08 || type == 0x09) && len >= 9) {
                var name = raw.slice(i + 2, i + 10);
                if (name.equals([0x4F, 0x73, 0x6D, 0x6F, 0x4E, 0x61, 0x6E, 0x6F]b)) {   // "OsmoNano"
                    found = ADV_NANO;
                }
            }
            i += 1 + len;
        }
        return found;
    }

    // Whether the raw advert lists the 16-bit service FFF0 (AD types 0x02/0x03),
    // which the Nano's GATT has; for the scan log.
    function rawHasFff0(raw as ByteArray) as Boolean {
        var i = 0;
        while (i + 1 < raw.size()) {
            var len = raw[i];
            if (len == 0 || i + 1 + len > raw.size()) {
                break;
            }
            var type = raw[i + 1];
            if (type == 0x02 || type == 0x03) {
                for (var j = i + 2; j + 1 <= i + len; j += 2) {
                    if (raw[j] == 0xF0 && raw[j + 1] == 0xFF) {
                        return true;
                    }
                }
            }
            i += 1 + len;
        }
        return false;
    }

    // Whether the raw advert carries DJI's company id at all, for the scan log.
    function rawIsDji(raw as ByteArray) as Boolean {
        for (var i = 0; i + 2 < raw.size(); i++) {
            if (raw[i] == 0xFF && raw[i + 1] == 0xAA && raw[i + 2] == 0x08) {
                return true;
            }
        }
        return false;
    }

    // SetPairingPIN's reply: PAIR_PAIRED, PAIR_APPROVE, or null.
    function pairStatus(reply as ByteArray) as Number? {
        return reply.size() >= 2 ? reply[1] : null;
    }

    function u16(b as ByteArray, at as Number) as Number? {
        return b.size() >= at + 2 ? b[at] | (b[at + 1] << 8) : null;
    }
}
