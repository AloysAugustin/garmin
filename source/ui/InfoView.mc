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
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (mMode == MODE_VIN) {
            dc.drawText(w / 2, h * 0.22, Graphics.FONT_MEDIUM, "Vehicle",
                Graphics.TEXT_JUSTIFY_CENTER);
            var vin = mKey.hasVin() ? mKey.vin() : "(not set)";
            dc.drawText(w / 2, h * 0.45, Graphics.FONT_SMALL, vin,
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.70, Graphics.FONT_TINY,
                "Set VIN in the\nGarmin Connect app\n(app settings)",
                Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(w / 2, h * 0.18, Graphics.FONT_MEDIUM, "My key",
                Graphics.TEXT_JUSTIFY_CENTER);
            // Show a short fingerprint; the full key is long. The fingerprint is
            // the first bytes of the public key, which is what the vehicle keychain
            // shows too.
            var hex = mKey.publicKeyHex();
            var fp = hex.substring(0, 16);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.45, Graphics.FONT_SMALL, fp + "...",
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.70, Graphics.FONT_TINY,
                "Pair to enroll\nthis key",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
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
