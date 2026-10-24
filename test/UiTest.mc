// Ui (source/ui/Ui.mc): the flags string scripts/icons.sh writes for each watch.
import Toybox.Lang;
import Toybox.Test;

(:test)
function uiDefaults(logger as Logger) as Boolean {
    Ui.parse("");
    Test.assertEqual(Ui.startAt, 30);
    Test.assert(!Ui.mono);
    Test.assert(!Ui.noGrey);
    Test.assert(!Ui.touch);
    return true;
}

(:test)
function uiFlagsFromTheProducts(logger as Logger) as Boolean {
    Ui.parse("start=21;mono");
    Test.assertEqual(Ui.startAt, 21);
    Test.assert(Ui.mono);
    Test.assert(Ui.noGrey);       // two colours also have no grey
    Test.assert(!Ui.touch);

    Ui.parse("start=29;touch");
    Test.assertEqual(Ui.startAt, 29);
    Test.assert(Ui.touch);
    Test.assert(!Ui.mono);

    Ui.parse("start=30;nogrey");
    Test.assert(Ui.noGrey);
    Test.assert(!Ui.mono);
    Ui.parse("");
    return true;
}

(:test)
function uiIgnoresWhatItDoesNotKnow(logger as Logger) as Boolean {
    Ui.parse("start=abc;;wide;touch;start=");
    Test.assertEqual(Ui.startAt, 30);
    Test.assert(Ui.touch);
    Test.assert(!Ui.mono);
    Ui.parse("");
    return true;
}
