// RunTrail and RunRecord (source/RunTrail.mc): the record a run leaves for the
// next launch, and how an unclean ending is told from a clean one. The tests
// use their own Storage key, so they never touch the app's record.
import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
function runRecordRoundTrip(logger as Logger) as Boolean {
    var r = new RunRecord();
    r.launches = 14;
    r.clean = false;
    r.uptimeS = 725;
    r.phase = 5;
    r.noteMemory(71, 128, 20);
    r.noteMemory(60, 128, 9);
    r.noteMemory(65, 128, 30);

    var back = RunRecord.unpack(r.pack());
    Test.assert(back != null);
    var b = back as RunRecord;
    Test.assertEqual(b.launches, 14);
    Test.assert(!b.clean);
    Test.assertEqual(b.uptimeS, 725);
    Test.assertEqual(b.phase, 5);
    Test.assertEqual(b.peakKb, 71);       // the most used, not the last
    Test.assertEqual(b.totalKb, 128);
    Test.assertEqual(b.freeMinKb, 9);     // the least free, not the last
    return true;
}

(:test)
function runRecordRefusesAnythingUnrecognised(logger as Logger) as Boolean {
    var blob = new RunRecord().pack();
    Test.assert(RunRecord.unpack(null) == null);
    Test.assert(RunRecord.unpack("nope") == null);
    Test.assert(RunRecord.unpack([1, 2, 3] as Array<Number>) == null);
    var wrong = blob.slice(0, null);
    wrong[0] = RunRecord.FORMAT + 1;
    Test.assert(RunRecord.unpack(wrong) == null);
    var mixed = [] as Array<Object>;
    for (var i = 0; i < blob.size(); i++) {
        mixed.add(blob[i]);
    }
    mixed[4] = "x";
    Test.assert(RunRecord.unpack(mixed) == null);
    return true;
}

(:test)
function runRecordDescribesItself(logger as Logger) as Boolean {
    var r = new RunRecord();
    r.uptimeS = 725;
    r.phase = 5;
    r.noteMemory(71, 128, 9);
    Test.assert(r.describe().equals("up 12 min, link live, memory peak 71 of 128 KB, least free 9 KB"));
    // No sample yet, and a phase that is not one: nothing invented.
    var none = new RunRecord();
    none.phase = 99;
    Test.assert(none.describe().equals("up 0 min, link ?"));
    return true;
}

(:test)
function runTrailTellsACrashFromACleanStop(logger as Logger) as Boolean {
    var key = "runTrailTest";
    Store.remove(key);

    // The first launch has no earlier run.
    var first = new RunTrail(key);
    Test.assert(first.begin(1000) == null);
    first.tick(31000, 5);
    // ...and it never calls end(): it crashed, or the watch restarted.

    var second = new RunTrail(key);
    var before = second.begin(2000);
    Test.assert(before != null);
    Test.assert(!(before as RunRecord).clean);
    Test.assertEqual((before as RunRecord).launches, 1);
    second.end(62000, 5);

    // This one ended through onStop.
    var third = new RunTrail(key);
    var again = third.begin(3000);
    Test.assert(again != null);
    Test.assert((again as RunRecord).clean);
    Test.assertEqual((again as RunRecord).launches, 2);
    Test.assertEqual((again as RunRecord).uptimeS, 60);
    Test.assertEqual((again as RunRecord).phase, 5);
    third.end(4000, 5);

    Store.remove(key);
    return true;
}

(:test)
function storeNeverThrows(logger as Logger) as Boolean {
    var key = "storeTest";
    Store.put(key, [1, 2] as Array<Application.Storage.ValueType>);
    Test.assertEqual((Store.get(key) as Array).size(), 2);
    Store.remove(key);
    Test.assert(Store.get(key) == null);
    Store.remove(key);   // removing what is not there is not an error
    return true;
}
