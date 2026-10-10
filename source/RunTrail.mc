// What the last run left behind, so a crash leaves a trail.
//
// A watch app has no activity file to carry diagnostics (a data field records
// into the FIT file; this has nothing like that), and a Store or beta install
// writes no text log. So the app keeps one small record in Application.Storage:
// each launch reads the record the run before left, says in the Diagnostics
// screen and the log how that run ended, and starts a new one.
//
// A run that ends through onStop marks its record clean. One that does not was
// ended by something else: a crash (the IQ! symbol), the watch restarting, or
// the system killing the app. The record then says how long it ran, the most
// memory it used against the limit, the least it ever had free, and the link
// phase it was in, which is the first thing to ask of a crash report. The
// record is written once a minute, so those figures are up to a minute old.
//
// RunRecord is a value with no Storage in it, so the rules are unit tested.
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

class RunRecord {

    // The packed shape's version. An older or newer record is ignored, not misread.
    static const FORMAT = 1;
    static const PACKED = 8;
    // Camera.P_* in order, for the log.
    static const PHASES = ["no BLE", "scanning", "connecting", "session", "approve", "live", "choosing", "off"];

    var launches as Number = 0;
    var clean as Boolean = true;
    var uptimeS as Number = 0;
    var peakKb as Number = 0;      // the most memory used
    var totalKb as Number = 0;     // the limit it is out of
    var freeMinKb as Number = 0;   // the least free; 0 until a sample is taken
    var phase as Number = -1;      // Camera.P_*; -1 for none

    function noteMemory(usedKb as Number, limitKb as Number, freeKb as Number) as Void {
        if (usedKb > peakKb) {
            peakKb = usedKb;
        }
        totalKb = limitKb;
        if (freeMinKb == 0 || freeKb < freeMinKb) {
            freeMinKb = freeKb;
        }
    }

    function pack() as Array<Number> {
        return [FORMAT, launches, clean ? 1 : 0, uptimeS, peakKb, totalKb, freeMinKb, phase] as Array<Number>;
    }

    // Read a record back, or null if it is not one or is another format.
    static function unpack(blob as Object?) as RunRecord? {
        if (!(blob instanceof Array) || (blob as Array).size() != PACKED) {
            return null;
        }
        var a = blob as Array;
        for (var i = 0; i < PACKED; i++) {
            if (!(a[i] instanceof Number)) {
                return null;
            }
        }
        if ((a[0] as Number) != FORMAT) {
            return null;
        }
        var r = new RunRecord();
        r.launches = a[1] as Number;
        r.clean = (a[2] as Number) != 0;
        r.uptimeS = a[3] as Number;
        r.peakKb = a[4] as Number;
        r.totalKb = a[5] as Number;
        r.freeMinKb = a[6] as Number;
        r.phase = a[7] as Number;
        return r;
    }

    // "up 12 min, link live, memory peak 71 of 128 KB, least free 9 KB".
    function describe() as String {
        var s = "up " + (uptimeS / 60).format("%d") + " min, link "
                + (phase >= 0 && phase < PHASES.size() ? PHASES[phase] : "?");
        if (totalKb > 0) {
            s += ", memory peak " + peakKb.format("%d") + " of " + totalKb.format("%d") + " KB";
            if (freeMinKb > 0) {
                s += ", least free " + freeMinKb.format("%d") + " KB";
            }
        }
        return s;
    }
}

class RunTrail {

    private const SAMPLE_MS = 10000;   // memory: one getSystemStats() every ten seconds
    private const SAVE_MS = 60000;     // one Storage write a minute

    private var _key as String;
    private var _run as RunRecord = new RunRecord();
    private var _startedAt as Number = 0;
    private var _sampledAt as Number = 0;
    private var _savedAt as Number = 0;

    // key: where the record lives. A test passes its own, so it never touches the app's.
    function initialize(key as String) {
        _key = key;
    }

    // Read the run before this one, log how it ended, and start a new record.
    // Returns the earlier run's record, null on the first launch.
    function begin(now as Number) as RunRecord? {
        var before = RunRecord.unpack(Store.get(_key));
        if (before == null) {
            Log.add("run 1, no earlier run on record");
        } else if (before.clean) {
            Log.add("run " + (before.launches + 1).format("%d") + ", the last one stopped cleanly: " + before.describe());
        } else {
            // onStop never ran: a crash, a restart of the watch, or a kill.
            Log.add("run " + (before.launches + 1).format("%d") + ", the LAST ONE DID NOT STOP CLEANLY: " + before.describe());
        }
        _run.launches = before != null ? before.launches + 1 : 1;
        _run.clean = false;
        _startedAt = now;
        _sampledAt = now;
        _savedAt = now;
        sample();
        save();
        return before;
    }

    // Often, from the app's timer; cheap until a sample or a save is due.
    function tick(now as Number, phase as Number) as Void {
        if (now - _sampledAt < SAMPLE_MS) {
            return;
        }
        _sampledAt = now;
        _run.phase = phase;
        _run.uptimeS = (now - _startedAt) / 1000;
        sample();
        if (now - _savedAt >= SAVE_MS) {
            _savedAt = now;
            save();
        }
    }

    // onStop: the run ended the way it should.
    function end(now as Number, phase as Number) as Void {
        _run.clean = true;
        _run.phase = phase;
        _run.uptimeS = (now - _startedAt) / 1000;
        sample();
        save();
    }

    private function sample() as Void {
        var st = System.getSystemStats();
        _run.noteMemory(st.usedMemory / 1024, st.totalMemory / 1024, st.freeMemory / 1024);
    }

    private function save() as Void {
        Store.put(_key, _run.pack() as Array<Application.Storage.ValueType>);
    }
}
