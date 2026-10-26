using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;
using Toybox.Math;

// Screen-shape-aware drawing helpers shared by the full-screen views, so the
// same code works on round, rectangular and Instinct (subscreen) displays.
module Layout {

    // Fonts tried, largest first, when fitting body text.
    const BODY_FONTS = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];

    // The Instinct-style round subscreen in the top-right corner, or null.
    function subscreen() {
        if (WatchUi has :getSubscreen) {
            return WatchUi.getSubscreen();
        }
        return null;
    }

    // Colour for a finished operation's title. Monochrome displays (Instinct)
    // map red/green to black, which would hide the text, so stay white there.
    (:color)
    function resultColor(ok) {
        return ok ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
    }

    (:mono)
    function resultColor(ok) {
        return Graphics.COLOR_WHITE;
    }

    // Draws a screen title and returns the y where content may start.
    // With a subscreen the title sits in the strip to its left; otherwise it
    // is centred near the top.
    function drawTitle(dc, text, color) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sub = subscreen();
        if (sub != null) {
            var font = fitFont(dc, text, sub.x - 8,
                [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]);
            dc.drawText(sub.x / 2 + 4, sub.y + sub.height / 2, font, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            // The physical ring around the subscreen overlaps a few pixels below it.
            return sub.y + sub.height + 8;
        }
        var y = h * 0.12;
        var font = fitFont(dc, text, usableWidth(w, h, y, y + 30),
            [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL]);
        dc.drawText(w / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font) + 4;
    }

    // Draws `text` word-wrapped and centred between `top` and `bottom`, using
    // the largest body font that fits. If even the smallest font overflows,
    // the text starts at `top` and runs past `bottom`.
    function drawBody(dc, text, top, bottom) {
        var w = dc.getWidth();
        var fit = fitBody(dc, text, top, bottom);
        var font = fit[0];
        var lines = fit[1];
        var fh = dc.getFontHeight(font);
        var y = (top + bottom) / 2 - (lines.size() * fh) / 2;
        if (y < top) {
            y = top;
        }
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, y + i * fh, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Whether `text` fits between `top` and `bottom` in some body font.
    function bodyFits(dc, text, top, bottom) {
        var fit = fitBody(dc, text, top, bottom);
        return fit[1].size() * dc.getFontHeight(fit[0]) <= bottom - top;
    }

    // [font, lines] for the largest body font that fits, else the smallest.
    function fitBody(dc, text, top, bottom) {
        var maxWidth = usableWidth(dc.getWidth(), dc.getHeight(), top, bottom) - 6;
        var font = null;
        var lines = null;
        for (var i = 0; i < BODY_FONTS.size(); i++) {
            font = BODY_FONTS[i];
            lines = wrap(dc, text, font, maxWidth);
            if (lines.size() * dc.getFontHeight(font) <= bottom - top) {
                break;
            }
        }
        return [font, lines];
    }

    // Draws one line centred at y in the largest of `fonts` that fits.
    function drawLine(dc, text, y, fonts) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var font = fitFont(dc, text, usableWidth(w, h, y, y + dc.getFontHeight(fonts[0])) - 6, fonts);
        dc.drawText(w / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font);
    }

    function fitFont(dc, text, maxWidth, fonts) {
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return fonts[fonts.size() - 1];
    }

    // Horizontal space available for a band of text between y0 and y1. On a
    // round screen this is the chord at whichever edge is furthest from the
    // centre; other shapes use the full width less a margin (the bezel
    // overlaps the edge pixels on semi-octagon screens).
    function usableWidth(w, h, y0, y1) {
        if (System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_ROUND) {
            return w - 10;
        }
        var r = w / 2.0;
        var d0 = (y0 - h / 2.0).abs();
        var d1 = (y1 - h / 2.0).abs();
        var d = d0 > d1 ? d0 : d1;
        if (d >= r) {
            return 0;
        }
        return (2 * Math.sqrt(r * r - d * d)).toNumber();
    }

    // Greedy word wrap by pixel width. Words wider than the line are kept whole.
    function wrap(dc, text, font, maxWidth) {
        var lines = [];
        var line = "";
        var words = splitWords(text);
        for (var i = 0; i < words.size(); i++) {
            var candidate = line.equals("") ? words[i] : line + " " + words[i];
            if (!line.equals("") && dc.getTextWidthInPixels(candidate, font) > maxWidth) {
                lines.add(line);
                line = words[i];
            } else {
                line = candidate;
            }
        }
        if (!line.equals("")) {
            lines.add(line);
        }
        return lines;
    }

    function splitWords(text) {
        var words = [];
        var current = "";
        for (var i = 0; i < text.length(); i++) {
            var c = text.substring(i, i + 1);
            if (c.equals(" ") || c.equals("\n")) {
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
