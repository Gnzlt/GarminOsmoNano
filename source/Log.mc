// The frame log for testing on the camera: the last lines for the Diagnostics
// screen, and every line to System.println, which a sideloaded app writes to
// GARMIN/APPS/LOGS/OSMONANO.TXT on the watch when that file exists (only for
// a sideloaded app: a Store or beta install writes no file). Each file line
// carries the version and the wall-clock time, so a stale log shows at once:
//   OSN 0.7.1 20:15:03 +12.345 <message>
// The clock has no milliseconds: the seconds since the start (from the
// timer) keep the lines in order.
import Toybox.Lang;
import Toybox.System;

module Log {

    const KEEP = 40;

    var lines as Array<String> = [] as Array<String>;
    var version as String = "?";
    var started as Number = System.getTimer();

    // The version for every line, from the app's start.
    function start(v as String) as Void {
        version = v;
    }

    function add(line as String) as Void {
        var c = System.getClockTime();
        var t = System.getTimer() - started;
        var stamped = c.hour.format("%02d") + ":" + c.min.format("%02d") + ":" + c.sec.format("%02d")
                + " +" + (t / 1000).format("%d") + "." + (t % 1000).format("%03d") + " " + line;
        System.println("OSN " + version + " " + stamped);
        lines.add(stamped);
        if (lines.size() > KEEP) {
            lines = lines.slice(lines.size() - KEEP, null);
        }
    }

    // "TX 07/45 >07 s0012 20B" plus the bytes, for a frame we send.
    function tx(f as ByteArray, note as String) as Void {
        add("TX " + describe(f) + " " + hex(f) + (note.length() > 0 ? " " + note : ""));
    }

    // A frame from the camera, decoded: "RX 02/02 <01 s3dfd 14B c0 df".
    function rxFrame(f as DumlFrame) as Void {
        add("RX " + byteHex(f.cmdSet) + "/" + byteHex(f.cmdId) + " <" + byteHex(f.src)
                + " s" + byteHex(f.seq >> 8) + byteHex(f.seq) + " " + f.length.format("%d") + "B "
                + byteHex(f.flags) + (f.payload.size() > 0 ? " " + hex(f.payload) : "")
                + (f.whole ? "" : " (cut)"));
    }

    // A notification as it arrived.
    function rx(chunk as ByteArray) as Void {
        add("RX " + chunk.size().format("%d") + "B " + hex(chunk));
    }

    function describe(f as ByteArray) as String {
        if (f.size() < Duml.HEADER) {
            return "?";
        }
        return byteHex(f[9]) + "/" + byteHex(f[10]) + " >" + byteHex(f[5])
                + " s" + byteHex(f[6]) + byteHex(f[7]) + " " + f.size().format("%d") + "B";
    }

    function hex(b as ByteArray) as String {
        var s = "";
        for (var i = 0; i < b.size(); i++) {
            s += byteHex(b[i]);
        }
        return s;
    }

    function byteHex(v as Number) as String {
        return (v & 0xFF).format("%02x");
    }
}
