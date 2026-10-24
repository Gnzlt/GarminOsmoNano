// DJI DUML frames, the protocol the Osmo Nano speaks over BLE (FFF5 out, FFF4
// in). Layout, from KonradIT/DJI-ESP32-Remote mediaprotocol/duml.h:
//
//   [0]     0x55
//   [1]     length, low byte (the whole frame, CRC16 included)
//   [2]     version 1 << 2 | length bits 8-9
//   [3]     CRC8 of bytes 0-2
//   [4]     source address, [5] destination address
//   [6:8]   sequence number, big-endian; the camera echoes it in replies
//   [8]     flags: 0x00 push, 0x40 request, 0xC0 response
//   [9]     command set, [10] command id
//   [11:-2] payload
//   [-2:]   CRC16 of everything before it, little-endian
//
// A watch receives at most 20 bytes per notification, so a longer frame from
// the camera can arrive cut short. FrameAssembler delivers such a frame as
// partial: its header is checked (CRC8), its payload is what arrived.
import Toybox.Lang;

module Duml {

    const SOF = 0x55;
    const HEADER = 11;
    const OVERHEAD = 13;   // header + CRC16

    // Addresses: (id << 5) | type.
    const ADDR_CAMERA = 0x01;
    const ADDR_APP = 0x02;
    const ADDR_WIFI = 0x07;      // pairing
    const ADDR_SYSTEM = 0x1C;    // wake
    const ADDR_DM368_4 = 0x88;   // session info
    const ADDR_SESSION = 0xF0;   // session open and keepalive

    const FLAG_PUSH = 0x00;
    const FLAG_REQUEST = 0x40;
    const FLAG_RESPONSE = 0xC0;

    function build(src as Number, dst as Number, seq as Number, flags as Number,
            cmdSet as Number, cmdId as Number, payload as ByteArray) as ByteArray {
        var len = OVERHEAD + payload.size();
        var b = new [len]b;
        b[0] = SOF;
        b[1] = len & 0xFF;
        b[2] = 0x04 | ((len >> 8) & 0x03);
        b[3] = Crc.crc8(b, 0, 3);
        b[4] = src;
        b[5] = dst;
        b[6] = (seq >> 8) & 0xFF;
        b[7] = seq & 0xFF;
        b[8] = flags;
        b[9] = cmdSet;
        b[10] = cmdId;
        for (var i = 0; i < payload.size(); i++) {
            b[HEADER + i] = payload[i];
        }
        var crc = Crc.crc16(b, 0, len - 2);
        b[len - 2] = crc & 0xFF;
        b[len - 1] = (crc >> 8) & 0xFF;
        return b;
    }

    // The length a valid header at b[0] declares, or -1: no 0x55, too few
    // bytes to check, a bad CRC8 or an impossible length.
    function declaredLength(b as ByteArray) as Number {
        if (b.size() < 4 || b[0] != SOF || Crc.crc8(b, 0, 3) != b[3]) {
            return -1;
        }
        var len = b[1] | ((b[2] & 0x03) << 8);
        return len >= OVERHEAD ? len : -1;
    }

    // The frame in b, which starts with a valid header. Whole if b holds the
    // declared length and its CRC16 matches; partial (payload cut short) if b
    // is shorter. Null if b is too short to name a command, or a complete
    // frame fails its CRC16.
    function parse(b as ByteArray) as DumlFrame? {
        var len = declaredLength(b);
        if (len < 0 || b.size() < HEADER) {
            return null;
        }
        var whole = b.size() >= len;
        if (whole) {
            var crc = b[len - 2] | (b[len - 1] << 8);
            if (Crc.crc16(b, 0, len - 2) != crc) {
                return null;
            }
        }
        var end = whole ? len - 2 : b.size();
        if (end > len - 2) {
            end = len - 2;   // the CRC16's first byte arrived, not its second
        }
        return new DumlFrame(b[4], b[5], (b[6] << 8) | b[7], b[8], b[9], b[10],
                b.slice(HEADER, end), whole, len);
    }
}

class DumlFrame {
    var src as Number;
    var dst as Number;
    var seq as Number;
    var flags as Number;
    var cmdSet as Number;
    var cmdId as Number;
    var payload as ByteArray;
    var whole as Boolean;
    var length as Number;   // as declared; more than arrived when partial

    function initialize(src as Number, dst as Number, seq as Number, flags as Number,
            cmdSet as Number, cmdId as Number, payload as ByteArray, whole as Boolean, length as Number) {
        self.src = src;
        self.dst = dst;
        self.seq = seq;
        self.flags = flags;
        self.cmdSet = cmdSet;
        self.cmdId = cmdId;
        self.payload = payload;
        self.whole = whole;
        self.length = length;
    }

    // The camera asks something and drops the link if it gets no answer.
    function isRequest() as Boolean {
        return (flags & 0x80) == 0 && (flags & 0x40) != 0;
    }

    function isResponse() as Boolean {
        return (flags & 0x80) != 0;
    }

    function is(cmdSet as Number, cmdId as Number) as Boolean {
        return self.cmdSet == cmdSet && self.cmdId == cmdId;
    }
}

// Notifications in, frames out. A notification that starts a frame longer
// than itself is delivered at once as partial, because on a watch the rest
// usually never comes (the camera truncates to the 20-byte MTU). If the rest
// does come, in notifications that don't start with a header, it is joined
// and the frame is delivered again, whole.
class FrameAssembler {

    private const MAX = 1024;

    private var _pending as ByteArray? = null;
    private var _need as Number = 0;
    var noise as Number = 0;   // bytes dropped: no header, nothing to join to

    function initialize() {
    }

    function reset() as Void {
        _pending = null;
    }

    function feed(chunk as ByteArray) as Array<DumlFrame> {
        var out = [] as Array<DumlFrame>;
        var len = Duml.declaredLength(chunk);
        if (len < 0) {
            var p = _pending;
            if (p == null) {
                noise += chunk.size();
                return out;
            }
            p.addAll(chunk);
            if (p.size() >= _need) {
                _pending = null;
                var f = Duml.parse(p.slice(0, _need));
                if (f != null) {
                    out.add(f);
                }
                if (p.size() > _need) {
                    out.addAll(feed(p.slice(_need, null)));
                }
            } else if (p.size() > MAX) {
                _pending = null;
            }
            return out;
        }
        // A new frame: anything pending was cut short and is already delivered.
        _pending = null;
        if (chunk.size() >= len) {
            var f = Duml.parse(chunk.slice(0, len));
            if (f != null) {
                out.add(f);
            }
            if (chunk.size() > len) {
                out.addAll(feed(chunk.slice(len, null)));
            }
            return out;
        }
        var partial = Duml.parse(chunk);
        if (partial != null) {
            out.add(partial);
        }
        _pending = chunk.slice(0, null);
        _need = len;
        return out;
    }
}
