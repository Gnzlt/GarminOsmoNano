// What the watch's profile says about its screen and keys, which the drawing and
// the input need to know. scripts/devices.py works it out for each product and
// scripts/icons.sh writes it into resources/gen/<product>/strings/ui.xml as the
// UiFlags string (the default is in strings.xml), e.g. "start=21;mono":
//   start=N   where START sits, degrees counter-clockwise from 3 o'clock
//   mono      two colours (black and white): everything draws white
//   nogrey    a few colours but no grey: dim things draw as outlines or white
//   touch     no UP and DOWN keys: swipes step, and a long press opens the menu
// Read once at start-up, never per frame.
import Toybox.Lang;
import Toybox.WatchUi;

module Ui {

    var startAt as Number = 30;
    var mono as Boolean = false;
    var noGrey as Boolean = false;
    var touch as Boolean = false;

    function load() as Void {
        parse(WatchUi.loadResource(Rez.Strings.UiFlags) as String);
    }

    // Anything not recognised is ignored, so an odd string leaves the defaults.
    function parse(flags as String) as Void {
        startAt = 30;
        mono = false;
        noGrey = false;
        touch = false;
        var rest = flags;
        while (rest.length() > 0) {
            var cut = rest.find(";");
            var item = rest;
            if (cut != null) {
                item = rest.substring(0, cut) as String;
                rest = rest.substring(cut + 1, rest.length()) as String;
            } else {
                rest = "";
            }
            if (item.equals("mono")) {
                mono = true;
                noGrey = true;
            } else if (item.equals("nogrey")) {
                noGrey = true;
            } else if (item.equals("touch")) {
                touch = true;
            } else if (item.find("start=") == 0) {
                var n = (item.substring(6, item.length()) as String).toNumber();
                if (n != null) {
                    startAt = n;
                }
            }
        }
    }
}
