// The one screen. Each fact is shown once:
//   - the top line: the link, a dot and one word (blue "Connected" once live,
//     with four bars for how well the link carries);
//   - the centre: what the rider needs now: the camera picker, the camera
//     being found or approved, the mode (its name above its glyph, as on the
//     camera), or while recording REC, the elapsed time and the mode's glyph;
//   - by START (upper right), when it does something: a line on the bezel
//     and an icon beside it: record or photo (a red dot), stop, choose, reconnect;
//   - when UP and DOWN pick a mode or move the picker's selection: an up and
//     a down arrow, left of the mode's glyph or of the selected row;
//   - under the top line: the camera's last answer, for a moment.
// Proportional layout for round screens: every size comes from the screen's
// (the fixed pixel sizes were set on a 454 px reference screen; `px` scales
// them), and the mode art comes in one size per screen (scripts/mode-icons.py).
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class MainView extends WatchUi.View {

    // What START does, for its cue.
    enum {
        CUE_NONE,
        CUE_RECORD,
        CUE_STOP,
        CUE_CHOOSE,
        CUE_RECONNECT
    }

    // Where START sits on the 5-button watches, in degrees counter-clockwise
    // from 3 o'clock (scripts/devices.py prints it for each product).
    private const START_AT = 30;
    private const CUE_SPAN = 12;      // degrees each side of the button

    private const PICKER_ROWS = 2;   // rows shown above and below the selected one
    private const BASE = 454;        // the screen the pixel sizes below were set on
    private const BAR_W = 4;         // the link's bars, by "Connected"
    private const BAR_GAP = 3;
    private const BAR_H = 18;

    private var _camera as Camera;
    private var _art as Dictionary<Number, WatchUi.BitmapResource> = {} as Dictionary<Number, WatchUi.BitmapResource>;
    private var _selected as String? = null;   // the picker's selection, by name: the list reorders
    private var _size as Number = BASE;        // the screen's, for px()

    function initialize(camera as Camera) {
        View.initialize();
        _camera = camera;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var size = w < h ? w : h;
        var cx = w / 2;
        var now = System.getTimer();
        var c = _camera;
        _size = size;
        // Smooth edges on the arcs, dots and triangles (off by default).
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var rec = c.phase == Camera.P_LIVE && c.capturing();

        drawPhase(dc, cx, h * 14 / 100);

        if (c.phase == Camera.P_CHOOSE) {
            drawPicker(dc, cx, h);
        } else if (c.phase != Camera.P_LIVE) {
            drawWaiting(dc, cx, h);
        } else if (rec) {
            var s = c.elapsed(now);
            var time = s >= 3600
                    ? (s / 3600).format("%d") + ":" + (s / 60 % 60).format("%02d") + ":" + (s % 60).format("%02d")
                    : (s / 60).format("%d") + ":" + (s % 60).format("%02d");
            // An hour or more is too wide for the big digits on a round screen.
            var font = dc.getTextWidthInPixels(time, Graphics.FONT_NUMBER_HOT) > w * 62 / 100
                    ? Graphics.FONT_NUMBER_MEDIUM : Graphics.FONT_NUMBER_HOT;
            // REC and the time as one block on the screen's centre, the mode's
            // glyph at the bottom. Placed by fractions of the height, not font
            // boxes: the number fonts' boxes carry so much padding that a
            // stack of boxes runs into the top line.
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 38 / 100, Graphics.FONT_SMALL, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 57 / 100, font, time, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var art = modeArt(c.mode, true);
            if (art != null) {
                dc.drawBitmap(cx - art.getWidth() / 2, h * 87 / 100 - art.getHeight() / 2, art);
            }
        } else {
            // The mode's name above its glyph, as on the camera's own screen:
            // the name just under the link line, the glyph at the bottom as
            // while recording, so the two never crowd each other. The UP/DOWN
            // hint sits left of the glyph.
            var art = modeArt(c.mode, false);
            if (art != null) {
                var name = Nano.modeName(c.mode);
                // The largest font whose name stays clear of START's cue at
                // the right edge: a long name in the big font ran into it.
                var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY];
                var font = fonts[fonts.size() - 1];
                for (var i = 0; i < fonts.size(); i++) {
                    if (dc.getTextWidthInPixels(name, fonts[i]) <= w * 56 / 100) {
                        font = fonts[i];
                        break;
                    }
                }
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 40 / 100, font, name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                var gy = h * 74 / 100 - art.getHeight() / 2;
                dc.drawBitmap(cx - art.getWidth() / 2, gy, art);
                if (!c.modeLocked()) {
                    drawSteps(dc, cx - art.getWidth() / 2 - size * 6 / 100, gy + art.getHeight() / 2, size);
                }
            } else {
                // Not known yet (it is set on connect), or changed on the
                // camera to a mode the watch can't read back.
                var tw = dc.getTextWidthInPixels("Pick a mode", Graphics.FONT_MEDIUM);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h / 2, Graphics.FONT_MEDIUM, "Pick a mode",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                if (!c.modeLocked()) {
                    drawSteps(dc, cx - tw / 2 - size * 5 / 100, h / 2, size);
                }
            }
        }

        drawCue(dc, cx, h / 2, size, START_AT, cue());
        // The glyph holds the bottom, recording or not: the message goes above.
        drawMessage(dc, cx, h * 26 / 100, now);
    }

    // ---- For MainDelegate: the picker ------------------------------------

    function moveSelection(step as Number) as Void {
        var list = _camera.candidates();
        if (list.size() == 0) {
            return;
        }
        var i = selectedIndex(list) + step;
        i = i < 0 ? 0 : i >= list.size() ? list.size() - 1 : i;
        _selected = list[i].name;
    }

    function selectedName() as String? {
        var list = _camera.candidates();
        return list.size() > 0 ? list[selectedIndex(list)].name : null;
    }

    private function selectedIndex(list as Array<Candidate>) as Number {
        var sel = _selected;
        if (sel != null) {
            for (var i = 0; i < list.size(); i++) {
                if (sel.equals(list[i].name)) {
                    return i;
                }
            }
        }
        return 0;
    }

    // ---- Parts ---------------------------------------------------------------

    // A coloured dot and the phase word: blue once the camera answers.
    private function drawPhase(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var color = Graphics.COLOR_LT_GRAY;
        var text = "Searching";
        var hollow = false;
        switch (_camera.phase) {
            case Camera.P_NO_BLE: color = Graphics.COLOR_RED; text = "No Bluetooth"; break;
            case Camera.P_CHOOSE: text = "Choose camera"; break;
            case Camera.P_CONNECT: color = Graphics.COLOR_YELLOW; text = "Connecting"; break;
            case Camera.P_SESSION: color = Graphics.COLOR_YELLOW; text = "Connecting"; break;
            case Camera.P_APPROVE: color = Graphics.COLOR_ORANGE; text = "Pairing"; break;
            case Camera.P_LIVE: color = Graphics.COLOR_BLUE; text = "Connected"; break;
            case Camera.P_OFF: hollow = true; text = "Disconnected"; break;
        }
        // The dot, the word and, once live, the link's bars: one centred group.
        var tw = dc.getTextWidthInPixels(text, Graphics.FONT_XTINY);
        var live = _camera.phase == Camera.P_LIVE;
        var bw = px(BAR_W) * 4 + px(BAR_GAP) * 3;
        var dot = px(5);
        var gap = px(6);     // between the dot and the word
        var gap2 = px(10);   // between the word and the bars
        var left = x - (dot * 2 + gap + tw + (live ? gap2 + bw : 0)) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (hollow) {
            dc.setPenWidth(px(2));
            dc.drawCircle(left + dot, y, dot - 1);
            dc.setPenWidth(1);
        } else {
            dc.fillCircle(left + dot, y, dot);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + dot * 2 + gap, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (live) {
            drawBars(dc, left + dot * 2 + gap + tw + gap2, y, _camera.linkBars);
        }
    }

    // Four rising bars, the first `n` lit, bottoms on one line, centred on y.
    private function drawBars(dc as Graphics.Dc, x as Number, y as Number, n as Number) as Void {
        var bw = px(BAR_W);
        var bar = px(BAR_H);
        var bottom = y + bar / 2;
        for (var i = 0; i < 4; i++) {
            var bh = bar * (i + 1) / 4;
            dc.setColor(i < n ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + i * (bw + px(BAR_GAP)), bottom - bh, bw, bh, 1);
        }
    }

    // A size set in pixels on the 454 px reference screen, at this screen's, at least 1.
    private function px(n as Number) as Number {
        var v = n * _size / BASE;
        return v > 0 ? v : 1;
    }

    // Before the camera answers, and after Disconnect: the camera and what
    // the rider should do. Never the phase word again.
    private function drawWaiting(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var c = _camera;
        var camera = c.name.length() > 0 ? c.name : "Osmo Nano";
        var title = camera;
        var detail = "";
        switch (c.phase) {
            case Camera.P_NO_BLE: title = "Not available\nto apps"; break;
            case Camera.P_SCAN: detail = "Turn it on, keep it close"; break;
            case Camera.P_CONNECT: detail = c.asleep ? "Waking it up" : ""; break;
            case Camera.P_SESSION: detail = c.asleep ? "Waking it up" : ""; break;
            case Camera.P_APPROVE: title = "Approve on the\nVision Dock"; detail = "it shows \"" + c.token + "\""; break;
            case Camera.P_OFF: detail = "It can sleep now"; break;
        }
        // The title and the detail below it, as one block centred on the
        // screen, however many lines the title has.
        var titleH = dc.getTextDimensions(title, Graphics.FONT_MEDIUM)[1];
        var detailH = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = detail.length() > 0 ? h / 2 - detailH : h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (detail.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + titleH / 2 + detailH / 2 + px(4), Graphics.FONT_XTINY, detail, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // The devices the scan has seen, the selected one in the middle on a
    // highlight; a camera glyph marks the likely Nanos. Below, the selected
    // one's signal and its place in the list.
    private function drawPicker(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var list = _camera.candidates();
        var cy = h / 2;
        if (list.size() == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 45 / 100, Graphics.FONT_MEDIUM, "Turn on the Nano",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 57 / 100, Graphics.FONT_XTINY,
                    "keep it close  -  " + _camera.seen.format("%d") + " devices seen",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var sel = selectedIndex(list);
        var rowH = dc.getFontHeight(Graphics.FONT_SMALL) + px(8);
        var glyph = h * 2 / 100;
        var hw = h * 31 / 100;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - hw, cy - rowH / 2 + px(2), hw * 2, rowH - px(4), (rowH - px(4)) / 2);
        if (list.size() > 1) {
            drawSteps(dc, cx - hw - h * 4 / 100, cy, h);
        }
        for (var d = -PICKER_ROWS; d <= PICKER_ROWS; d++) {
            var i = sel + d;
            if (i < 0 || i >= list.size()) {
                continue;
            }
            var y = cy + d * rowH;
            var name = list[i].name;
            var tw = dc.getTextWidthInPixels(name, Graphics.FONT_SMALL);
            var shift = list[i].nano ? glyph * 2 : 0;
            dc.setColor(d == 0 ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + shift, y, Graphics.FONT_SMALL, name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (list[i].nano) {
                drawCamera(dc, cx + shift - tw / 2 - glyph * 2, y, glyph,
                        d == 0 ? Graphics.COLOR_RED : Graphics.COLOR_DK_GRAY);
            }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (PICKER_ROWS + 1) * rowH - rowH / 4, Graphics.FONT_XTINY,
                list[sel].rssi.format("%d") + " dBm  -  " + (sel + 1).format("%d") + " of " + list.size().format("%d"),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The camera's last answer, for a moment: a photo it confirmed is a small
    // orange camera, anything else a few words.
    private function drawMessage(dc as Graphics.Dc, cx as Number, y as Number, now as Number) as Void {
        if (_camera.photoJustTaken(now)) {
            drawCamera(dc, cx, y, dc.getHeight() * 35 / 1000, Graphics.COLOR_ORANGE);
            return;
        }
        var msg = _camera.currentMessage(now);
        if (msg.length() > 0) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_TINY, msg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ---- The mode art --------------------------------------------------------

    // The mode's glyph, large for the mode screen or `small` under the
    // record time; null for a mode without art. Loaded once and kept: onUpdate
    // runs 4 times a second.
    private function modeArt(m as Number?, small as Boolean) as WatchUi.BitmapResource? {
        if (m == null) {
            return null;
        }
        var key = small ? m + 0x1000 : m;
        var art = _art[key];
        if (art != null) {
            return art;
        }
        var id = null;
        switch (m) {
            case Nano.MODE_VIDEO: id = small ? Rez.Drawables.ModeVideoSmall : Rez.Drawables.ModeVideo; break;
            case Nano.MODE_PHOTO: id = small ? Rez.Drawables.ModePhotoSmall : Rez.Drawables.ModePhoto; break;
            case Nano.MODE_TIMELAPSE: id = small ? Rez.Drawables.ModeTimelapseSmall : Rez.Drawables.ModeTimelapse; break;
            case Nano.MODE_HYPERLAPSE: id = small ? Rez.Drawables.ModeHyperlapseSmall : Rez.Drawables.ModeHyperlapse; break;
            case Nano.MODE_SUPERNIGHT: id = small ? Rez.Drawables.ModeSuperNightSmall : Rez.Drawables.ModeSuperNight; break;
            case Nano.MODE_SLOWMO: id = small ? Rez.Drawables.ModeSloMoSmall : Rez.Drawables.ModeSloMo; break;
        }
        if (id == null) {
            return null;
        }
        var loaded = WatchUi.loadResource(id) as WatchUi.BitmapResource;
        _art[key] = loaded;
        return loaded;
    }

    // ---- The button cues ---------------------------------------------------

    private function cue() as Number {
        var c = _camera;
        switch (c.phase) {
            case Camera.P_LIVE:
                // The shutter is always the red dot, for a photo too; a square stops a recording.
                return c.capturing() && !c.photoNext() ? CUE_STOP : CUE_RECORD;
            case Camera.P_CHOOSE:
                return c.candidates().size() > 0 ? CUE_CHOOSE : CUE_NONE;
            case Camera.P_OFF:
                return CUE_RECONNECT;
        }
        return CUE_NONE;
    }

    // A line on the bezel at a button, `at` degrees counter-clockwise from 3
    // o'clock, and an icon beside it: red for the camera's shutter, white for
    // the app's own actions.
    private function drawCue(dc as Graphics.Dc, cx as Number, cy as Number, size as Number, at as Number, kind as Number) as Void {
        if (kind == CUE_NONE) {
            return;
        }
        var color = kind == CUE_CHOOSE || kind == CUE_RECONNECT ? Graphics.COLOR_WHITE : Graphics.COLOR_RED;
        // As the watch draws its own: a thin arc a little inside the edge,
        // with rounded ends, and a large icon just inside it.
        var pen = size * 15 / 1000;
        var rr = size / 2 - size * 25 / 1000 - pen / 2;
        dc.setPenWidth(pen);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, rr, Graphics.ARC_COUNTER_CLOCKWISE, at - CUE_SPAN, at + CUE_SPAN);
        dc.setPenWidth(1);
        arcEnd(dc, cx, cy, rr, at - CUE_SPAN, pen);
        arcEnd(dc, cx, cy, rr, at + CUE_SPAN, pen);

        var s = size * 55 / 1000;
        var r = rr - pen / 2 - size * 2 / 100 - s;
        var rad = at * Math.PI / 180;
        var x = cx + (r * Math.cos(rad)).toNumber();
        var y = cy - (r * Math.sin(rad)).toNumber();
        switch (kind) {
            case CUE_RECORD:
                dc.fillCircle(x, y, s * 8 / 10);
                break;
            case CUE_STOP:
                dc.fillRoundedRectangle(x - s * 7 / 10, y - s * 7 / 10, s * 14 / 10, s * 14 / 10, s / 4);
                break;
            case CUE_CHOOSE:
                dc.fillPolygon([[x - s / 3, y - s * 7 / 10], [x + s / 2, y], [x - s / 3, y + s * 7 / 10],
                        [x - s * 2 / 3, y + s * 7 / 10 - s / 3], [x, y], [x - s * 2 / 3, y - s * 7 / 10 + s / 3]]);
                break;
            case CUE_RECONNECT:
                dc.setPenWidth(s / 4 > 2 ? s / 4 : 2);
                dc.drawArc(x, y, s * 6 / 10, Graphics.ARC_COUNTER_CLOCKWISE, 60, 330);
                dc.setPenWidth(1);
                // The arrowhead at the arc's 60-degree end, pointing back along it.
                var ax = x + s * 3 / 10;
                var ay = y - s * 52 / 100;
                dc.fillPolygon([[ax - s * 4 / 10, ay - s * 3 / 10], [ax + s / 3, ay], [ax - s * 2 / 10, ay + s * 4 / 10]]);
                break;
        }
    }

    // UP and DOWN step through something: an up and a down triangle, filled
    // and close together, around (x, y). Which button is which, the rider
    // knows.
    private function drawSteps(dc as Graphics.Dc, x as Number, y as Number, size as Number) as Void {
        var w = size * 3 / 100;     // half a triangle's width
        var t = size * 25 / 1000;   // its height
        var g = size * 12 / 1000;   // half the gap between the two
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x - w, y - g], [x, y - g - t], [x + w, y - g]]);
        dc.fillPolygon([[x - w, y + g], [x, y + g + t], [x + w, y + g]]);
    }

    // A round end for an arc of radius `r`, at `deg` counter-clockwise from 3 o'clock.
    private function arcEnd(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, deg as Number, pen as Number) as Void {
        var rad = deg * Math.PI / 180;
        dc.fillCircle(cx + (r * Math.cos(rad)).toNumber(), cy - (r * Math.sin(rad)).toNumber(), pen / 2);
    }

    // A small camera: a body, a viewfinder bump and a black lens.
    private function drawCamera(dc as Graphics.Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - s, y - s * 6 / 10, s * 2, s * 13 / 10, s / 4);
        dc.fillRectangle(x - s / 3, y - s * 9 / 10, s * 2 / 3, s / 3 + 1);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + s / 20, s * 4 / 10);
    }
}
