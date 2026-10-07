// Diagnostics: the frame log, newest at the bottom, wrapped to the screen.
// UP/DOWN scroll a line at a time. The same lines go to the log file
// (Log.mc), which has room for all of them.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class LogView extends WatchUi.View {

    static var scroll as Number = 0;   // lines up from the newest

    function initialize() {
        View.initialize();
        scroll = 0;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var maxW = w * 78 / 100;
        var rows = wrap(dc, font, maxW);
        if (rows.size() == 0) {
            dc.drawText(w / 2, h / 2, font, "No frames yet", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var visible = (h * 76 / 100) / lh;
        if (scroll > rows.size() - visible) {
            scroll = rows.size() > visible ? rows.size() - visible : 0;
        }
        var last = rows.size() - 1 - scroll;
        var y = h * 88 / 100 - lh;
        for (var i = last; i >= 0 && y > h * 12 / 100; i--) {
            var r = rows[i];
            dc.setColor(r.find(" TX ") != null ? Graphics.COLOR_ORANGE
                    : r.find(" RX ") != null ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_TRANSPARENT);
            dc.drawText((w - maxW) / 2, y, font, r, Graphics.TEXT_JUSTIFY_LEFT);
            y -= lh;
        }
    }

    // Every log line split into rows no wider than maxW. Hex has no spaces,
    // so this breaks anywhere.
    private function wrap(dc as Graphics.Dc, font as Graphics.FontType, maxW as Number) as Array<String> {
        var charW = dc.getTextWidthInPixels("0", font);
        var per = charW > 0 ? maxW / charW : 30;
        var rows = [] as Array<String>;
        for (var i = 0; i < Log.lines.size(); i++) {
            var s = Log.lines[i];
            var first = true;
            while (s.length() > 0) {
                var room = first ? per : per - 2;   // continuations are indented
                var n = s.length() <= room ? s.length() : breakAt(s, room);
                rows.add((first ? "" : "  ") + (s.substring(0, n) as String));
                s = s.substring(n, s.length()) as String;
                if (s.length() > 0 && (s.substring(0, 1) as String).equals(" ")) {
                    s = s.substring(1, s.length()) as String;
                }
                first = false;
            }
        }
        return rows;
    }

    // Where to cut s to fit room characters: the last space in reach, or
    // room itself inside a long word (hex).
    private function breakAt(s as String, room as Number) as Number {
        var chars = s.toCharArray();
        for (var i = room; i > room / 2; i--) {
            if (chars[i] == ' ') {
                return i;
            }
        }
        return room;
    }
}

class LogDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onPreviousPage() as Boolean {
        LogView.scroll++;
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        if (LogView.scroll > 0) {
            LogView.scroll--;
        }
        WatchUi.requestUpdate();
        return true;
    }
}
