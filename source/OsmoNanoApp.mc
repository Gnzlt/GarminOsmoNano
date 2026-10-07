// Entry point: builds the camera (the real Nano session over BLE, or the demo
// camera in the demo build), and drives it from one 50 ms timer, which also
// paces the BLE writes.
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class OsmoNanoApp extends Application.AppBase {

    private const TICK_MS = 50;
    private const DRAW_EVERY = 5;   // ticks between screen updates: 4 a second

    private var _camera as Camera;
    private var _link as BleLink? = null;
    private var _timer as Timer.Timer? = null;
    private var _ticks as Number = 0;

    function initialize() {
        AppBase.initialize();
        _camera = makeCamera();
    }

    (:nodemo)
    private function makeCamera() as Camera {
        var link = new BleLink();
        var session = new NanoSession(new BleTransport(link));
        link.setSession(session);
        _link = link;
        return session;
    }

    (:demo)
    private function makeCamera() as Camera {
        return new DemoCamera();
    }

    function onStart(state as Dictionary?) as Void {
        var v = WatchUi.loadResource(Rez.Strings.AppVersion) as String;
        Log.start(v);
        logBanner(v);
        if (_link != null) {
            (_link as BleLink).start();
        }
        var t = new Timer.Timer();
        t.start(method(:onTick), TICK_MS, true);
        _timer = t;
    }

    // What a log reader needs first: which build, on what, when, with which
    // settings and saved state.
    private function logBanner(v as String) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var ds = System.getDeviceSettings();
        var fw = ds.firmwareVersion;
        Log.add("OsmoNano " + v + (_link == null ? " DEMO" : "") + " start "
                + now.year.format("%04d") + "-" + (now.month as Number).format("%02d") + "-" + now.day.format("%02d")
                + " " + now.hour.format("%02d") + ":" + now.min.format("%02d") + ":" + now.sec.format("%02d"));
        Log.add("device " + ds.partNumber + " fw " + fw[0].format("%d") + "." + fw[1].format("%02d")
                + " ciq " + ds.monkeyVersion[0].format("%d") + "." + ds.monkeyVersion[1].format("%d") + "." + ds.monkeyVersion[2].format("%d"));
        Log.add("settings pairing " + Settings.number("pairing", 0).format("%d")
                + " infoReply " + Settings.number("infoReply", 0).format("%d")
                + " chunkGap " + Settings.number("chunkGap", 0).format("%d"));
        var saved = null;
        var last = null;
        try {
            saved = Application.Storage.getValue("cameraName");
            last = Application.Storage.getValue("lastMode");
        } catch (e) {
        }
        Log.add("stored camera " + (saved != null ? saved.toString() : "-") + " lastMode " + (last != null ? last.toString() : "-"));
    }

    function onStop(state as Dictionary?) as Void {
        Log.add("stop");
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
        }
        if (_link != null) {
            (_link as BleLink).stop();
        }
        _camera.stop();
    }

    function onTick() as Void {
        var now = System.getTimer();
        if (_link != null) {
            (_link as BleLink).tick(now);
        }
        _camera.tick(now);
        _ticks++;
        if (_ticks % DRAW_EVERY == 0) {
            WatchUi.requestUpdate();
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new MainView(_camera);
        return [view, new MainDelegate(_camera, view)];
    }
}
