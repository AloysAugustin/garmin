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

        var accent = Graphics.COLOR_WHITE;
        if (mDone) {
            accent = mSuccess ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
        }

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.22, Graphics.FONT_MEDIUM, mTitle,
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, wrap(mMessage),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (mDone) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.86, Graphics.FONT_TINY, "BACK to return",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Very small word-wrap helper so long messages fit the round/square screen.
    hidden function wrap(text) {
        var words = splitWords(text);
        var line = "";
        var out = "";
        var max = 16;
        for (var i = 0; i < words.size(); i++) {
            var candidate = line.equals("") ? words[i] : line + " " + words[i];
            if (candidate.length() > max) {
                out = out.equals("") ? line : out + "\n" + line;
                line = words[i];
            } else {
                line = candidate;
            }
        }
        if (!line.equals("")) {
            out = out.equals("") ? line : out + "\n" + line;
        }
        return out;
    }

    hidden function splitWords(text) {
        var words = [];
        var current = "";
        for (var i = 0; i < text.length(); i++) {
            var c = text.substring(i, i + 1);
            if (c.equals(" ")) {
                if (!current.equals("")) {
                    words.add(current);
                    current = "";
                }
            } else {
                current += c;
            }
        }
        if (!current.equals("")) {
            words.add(current);
        }
        return words;
    }
}
