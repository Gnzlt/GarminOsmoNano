// The buttons, as Connect IQ behaviours: START shutter, UP/DOWN the previous/
// next shooting mode, hold UP the app's menu, BACK leaves the app. A behaviour
// delegate is what makes the watch hand hold-UP to the app: with raw key
// events the watch opens its own menu instead.
//
// In the camera picker (no camera saved yet), UP/DOWN move the selection and
// START chooses it; after Disconnect, START reconnects. Taps and swipes are
// swallowed, so a stray touch can't fire the camera.
import Toybox.Lang;
import Toybox.WatchUi;

class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _camera as Camera;
    private var _view as MainView;

    function initialize(camera as Camera, view as MainView) {
        BehaviorDelegate.initialize();
        _camera = camera;
        _view = view;
    }

    function onSelect() as Boolean {
        Log.add("button START (" + _camera.state() + ")");
        if (_camera.phase == Camera.P_CHOOSE) {
            var name = _view.selectedName();
            if (name != null) {
                _camera.choose(name);
            }
        } else if (_camera.phase == Camera.P_OFF) {
            _camera.reconnect();
        } else {
            _camera.shutter();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        return step(-1);
    }

    function onNextPage() as Boolean {
        return step(1);
    }

    private function step(by as Number) as Boolean {
        Log.add("button " + (by < 0 ? "UP" : "DOWN") + " (" + _camera.state() + ")");
        if (_camera.phase == Camera.P_CHOOSE) {
            _view.moveSelection(by);
        } else if (!_camera.modeLocked()) {
            _camera.setMode(Nano.stepMode(_camera.mode, by));
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        Log.add("button MENU (" + _camera.state() + ")");
        Menus.openMain(_camera);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        return true;
    }
}
