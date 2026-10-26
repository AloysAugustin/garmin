using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;

// Four-digit PIN entry for Drive (see DriveGuard). A custom view rather than
// WatchUi.Picker: the system picker follows the watch theme (white on
// fēnix, black on Instinct) and cannot be given a background, so fixed
// colours were invisible on one or the other.
//
// Buttons: UP digit + 1, DOWN digit - 1, SELECT next digit (the 4th
// submits), BACK previous digit (or cancel on the first). Touch: tap the top
// third + 1, bottom third - 1, middle next; swipes also work.
// Digits already entered are shown as dots.
class PinView extends WatchUi.View {

    hidden var mDigits;
    hidden var mPos;

    function initialize() {
        View.initialize();
        mDigits = [0, 0, 0, 0];
        mPos = 0;
    }

    function change(delta) {
        mDigits[mPos] = (mDigits[mPos] + delta + 10) % 10;
        WatchUi.requestUpdate();
    }

    // Moves to the next digit; returns the PIN once all four are set.
    function next() {
        if (mPos < 3) {
            mPos++;
            WatchUi.requestUpdate();
            return null;
        }
        var pin = "";
        for (var i = 0; i < 4; i++) {
            pin += mDigits[i].toString();
        }
        return pin;
    }

    // Steps back one digit; false when already on the first.
    function back() {
        if (mPos == 0) {
            return false;
        }
        mDigits[mPos] = 0;
        mPos--;
        WatchUi.requestUpdate();
        return true;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var top = Layout.drawTitle(dc, Layout.subscreen() != null ? "PIN" : "Drive PIN",
            Graphics.COLOR_WHITE);

        var font = Layout.fitFont(dc, "0 0 0 0", w * 0.7,
            [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM]);
        var cell = dc.getTextWidthInPixels("0", font) * 2;
        var fh = dc.getFontHeight(font);
        var y = (top + h * 0.85) / 2 - fh / 2;
        var x0 = w / 2 - cell * 2 + cell / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 4; i++) {
            var x = x0 + i * cell;
            // Shapes, not "*"/"-": number fonts have no such glyphs.
            if (i < mPos) {
                dc.fillCircle(x, y + fh / 2, fh / 8 + 2);
            } else if (i == mPos) {
                dc.drawText(x, y, font, mDigits[i].toString(), Graphics.TEXT_JUSTIFY_CENTER);
                dc.fillRectangle(x - cell / 3, y + fh, cell * 2 / 3, 3);
            } else {
                dc.fillRectangle(x - cell / 4, y + fh / 2, cell / 2, 3);
            }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (System.getDeviceSettings().isTouchScreen) {
            Layout.drawBody(dc, "Tap top or bottom to change, middle for next", y + fh + 6, h * 0.9);
        } else {
            Layout.drawLine(dc, "SELECT = next", y + fh + 8, [Graphics.FONT_XTINY]);
        }
    }
}

// A plain InputDelegate: on a BehaviorDelegate a tap only arrives as
// onSelect (seen in the simulator), so the tap zones need raw input.
class PinDelegate extends WatchUi.InputDelegate {

    hidden var mView;
    hidden var mMenuDelegate;

    function initialize(view, menuDelegate) {
        InputDelegate.initialize();
        mView = view;
        mMenuDelegate = menuDelegate;
    }

    function onKey(evt) {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            mView.change(1);
        } else if (key == WatchUi.KEY_DOWN) {
            mView.change(-1);
        } else if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            next();
        } else if (key == WatchUi.KEY_ESC) {
            back();
        } else {
            return false;
        }
        return true;
    }

    function onSwipe(evt) {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_DOWN) {
            mView.change(1);
        } else if (dir == WatchUi.SWIPE_UP) {
            mView.change(-1);
        } else if (dir == WatchUi.SWIPE_RIGHT) {
            back();
        } else {
            return false;
        }
        return true;
    }

    function onTap(evt) {
        var h = System.getDeviceSettings().screenHeight;
        var y = evt.getCoordinates()[1];
        if (y < h / 3) {
            mView.change(1);
        } else if (y > h * 2 / 3) {
            mView.change(-1);
        } else {
            next();
        }
        return true;
    }

    hidden function next() {
        var pin = mView.next();
        if (pin == null) {
            return;
        }
        var code = DriveGuard.verify(pin);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (code == DriveGuard.PIN_OK) {
            mMenuDelegate.startDrive();
        } else {
            mMenuDelegate.showMessage("Drive", DriveGuard.message(code));
        }
    }

    hidden function back() {
        if (!mView.back()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
