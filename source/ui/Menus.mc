// The menu (hold UP): pick a mode, disconnect (or reconnect), change camera
// (back to the picker), the protocol choices for testing on the camera, the
// frame log, and About (the version and who made it).
//
// Protocol choices step to their next option on each select and apply from
// the next connection (Reconnect applies them now). See NanoSession for what
// each one does.
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module Menus {

    // [property, title, values, labels]
    function protocolItems() as Array<Array> {
        return [
            ["pairing", "Pairing frame", [0, 1], ["Short, 20 B", "Long, 52 B"]],
            ["infoReply", "Request replies", [0, 1, 2], ["Empty", "Echo", "Identity"]],
            ["chunkGap", "Chunk gap", [0, 30, 100], ["None", "30 ms", "100 ms"]]
        ] as Array<Array>;
    }

    function openMain(camera as Camera) as Void {
        var menu = new WatchUi.Menu2({ :title => "OsmoNano" });
        var m = Nano.modeName(camera.mode);
        menu.addItem(new WatchUi.MenuItem("Mode",
                camera.modeLocked() ? "locked while recording" : m.length() > 0 ? m : "unknown", :mode, null));
        if (camera.phase == Camera.P_OFF) {
            menu.addItem(new WatchUi.MenuItem("Reconnect", camera.name, :reconnect, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Disconnect", "lets the camera sleep", :disconnect, null));
        }
        menu.addItem(new WatchUi.MenuItem("Change camera", camera.name.length() > 0 ? camera.name : null, :change, null));
        menu.addItem(new WatchUi.MenuItem("Protocol", "for testing", :protocol, null));
        menu.addItem(new WatchUi.MenuItem("Diagnostics", "frame log", :log, null));
        menu.addItem(new WatchUi.MenuItem("About",
                "v" + (WatchUi.loadResource(Rez.Strings.AppVersion) as String), :about, null));
        WatchUi.pushView(menu, new MainMenuDelegate(camera), WatchUi.SLIDE_UP);
    }

    function openModes(camera as Camera) as Void {
        var menu = new WatchUi.Menu2({ :title => "Mode" });
        for (var i = 0; i < Nano.MODES.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(Nano.modeName(Nano.MODES[i]), null, Nano.MODES[i], null));
        }
        WatchUi.pushView(menu, new ModeMenuDelegate(camera), WatchUi.SLIDE_LEFT);
    }

    function openProtocol() as Void {
        var menu = new WatchUi.Menu2({ :title => "Protocol" });
        var items = protocolItems();
        for (var i = 0; i < items.size(); i++) {
            var key = items[i][0] as String;
            menu.addItem(new WatchUi.MenuItem(items[i][1] as String, label(items[i], Settings.number(key, 0)), key, null));
        }
        WatchUi.pushView(menu, new ProtocolMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    function label(item as Array, value as Number) as String {
        var values = item[2] as Array<Number>;
        var labels = item[3] as Array<String>;
        var i = values.indexOf(value);
        return labels[i >= 0 ? i : 0];
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _camera as Camera;

    function initialize(camera as Camera) {
        Menu2InputDelegate.initialize();
        _camera = camera;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        Log.add("menu " + item.getLabel());
        if (id == :mode) {
            if (!_camera.modeLocked()) {
                Menus.openModes(_camera);
            }
        } else if (id == :protocol) {
            Menus.openProtocol();
        } else if (id == :log) {
            WatchUi.pushView(new LogView(), new LogDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :disconnect) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _camera.disconnect();
        } else if (id == :reconnect) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _camera.reconnect();
        } else if (id == :change) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _camera.forget();
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _camera as Camera;

    function initialize(camera as Camera) {
        Menu2InputDelegate.initialize();
        _camera = camera;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Log.add("menu mode " + item.getLabel());
        _camera.setMode(item.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ProtocolMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var key = item.getId() as String;
        var items = Menus.protocolItems();
        for (var i = 0; i < items.size(); i++) {
            if (key.equals(items[i][0] as String)) {
                var values = items[i][2] as Array<Number>;
                var at = values.indexOf(Settings.number(key, 0));
                var next = values[(at + 1) % values.size()];
                Application.Properties.setValue(key, next);
                Log.add("setting " + key + " = " + next.format("%d"));
                item.setSubLabel(Menus.label(items[i], next));
            }
        }
    }
}

// About: the app's name, its version and who made it. BACK closes it.
class AboutView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(cx, h * 38 / 100, Graphics.FONT_MEDIUM, WatchUi.loadResource(Rez.Strings.AppName) as String, center);
        dc.drawText(cx, h * 52 / 100, Graphics.FONT_SMALL, "v" + (WatchUi.loadResource(Rez.Strings.AppVersion) as String), center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 66 / 100, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.MadeBy) as String, center);
    }
}
