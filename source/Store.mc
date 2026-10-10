// Writes to Application.Storage that cannot throw. Storage refuses a write when
// the filesystem is full or the value is not storable, and most of the app's
// writes happen inside a BLE callback or a camera reply: an exception there
// ends the app mid-use. Everything stored here is a convenience (the saved
// camera, the last mode), so a refused write is dropped, not raised.
import Toybox.Application;
import Toybox.Lang;

module Store {

    function put(key as String, value as Application.Storage.ValueType) as Void {
        try {
            Application.Storage.setValue(key, value);
        } catch (e) {
        }
    }

    function remove(key as String) as Void {
        try {
            Application.Storage.deleteValue(key);
        } catch (e) {
        }
    }

    function get(key as String) as Application.Storage.ValueType {
        try {
            return Application.Storage.getValue(key);
        } catch (e) {
            return null;
        }
    }
}
