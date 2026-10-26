using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

// Full-screen view that shows the progress of the current operation. It doubles
// as the controller's "sink": the controller pushes status/result text into it.
class StatusView extends WatchUi.View {

    hidden var mTitle;
    hidden var mMessage;
    hidden var mDone;
    hidden var mSuccess;

    function initialize(title) {
        View.initialize();
        mTitle = title;
        mMessage = "Starting...";
        mDone = false;
        mSuccess = false;
    }

    // --- Controller sink interface -----------------------------------------

    function onStatus(msg) {
        mMessage = msg;
        mDone = false;
        WatchUi.requestUpdate();
    }

    function onResult(ok, msg) {
        mMessage = msg;
        mDone = true;
        mSuccess = ok;
        WatchUi.requestUpdate();
    }

    function isDone() {
        return mDone;
    }

    // --- Drawing ------------------------------------------------------------

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var accent = mDone ? Layout.resultColor(mSuccess) : Graphics.COLOR_WHITE;
        var top = Layout.drawTitle(dc, mTitle, accent);

        // The "BACK to return" hint gives way when a long message needs the room.
        var bottom = h * 0.92;
        if (mDone && Layout.bodyFits(dc, mMessage, top, h * 0.80)) {
            bottom = h * 0.80;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Layout.drawLine(dc, "BACK to return", bottom + 2,
                [Graphics.FONT_TINY, Graphics.FONT_XTINY]);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Layout.drawBody(dc, mMessage, top, bottom);
    }
}
