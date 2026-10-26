using Toybox.WatchUi;
using Toybox.Graphics;

// Shows either the watch's public key (so it can be enrolled from Fleet API /
// the Tesla app if desired) or the current VIN configuration.
class InfoView extends WatchUi.View {

    enum {
        MODE_KEY,
        MODE_VIN
    }

    hidden var mMode;
    hidden var mKey;

    function initialize(mode, key) {
        View.initialize();
        mMode = mode;
        mKey = key;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var fonts = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];

        var title;
        var value;
        var hint;
        if (mMode == MODE_VIN) {
            title = "Vehicle";
            value = mKey.hasVin() ? mKey.vin() : "(not set)";
            hint = "Set the VIN in the Garmin Connect app (app settings)";
        } else {
            title = "My key";
            // Show a short fingerprint; the full key is long. The fingerprint is
            // the first bytes of the public key, which is what the vehicle
            // keychain shows too.
            value = mKey.publicKeyHex().substring(0, 16) + "...";
            hint = "Pair to enroll this key";
        }

        var top = Layout.drawTitle(dc, title, Graphics.COLOR_WHITE);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = Layout.drawLine(dc, value, top + 2, fonts);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Layout.drawBody(dc, hint, y + 4, h * 0.92);
    }
}

// Back returns to the menu.
class InfoDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
