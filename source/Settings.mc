// Typed reads of the app properties (resources/main/settings). A missing or
// mistyped value gives the fallback: getValue() throws for a key an older
// install does not have yet.
import Toybox.Application;
import Toybox.Lang;

module Settings {

    function raw(key as String) as Application.Properties.ValueType or Null {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    function number(key as String, fallback as Number) as Number {
        var v = raw(key);
        if (v instanceof Number || v instanceof Float) {
            return v.toNumber();
        }
        return fallback;
    }
}
