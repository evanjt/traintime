using Toybox.Math;
using Toybox.Graphics;
using Toybox.System;

module DrawUtils {

    // Design reference width: all px() base values are authored against a
    // 260px round display (fenix 6/7 class)
    const REF_W = 260;

    var mRound = null;
    var mTouch = null;

    // Scale a design-space pixel value to this display, never below 1px
    function px(base, width) {
        var v = (base * width + REF_W / 2) / REF_W;
        return (v < 1) ? 1 : v;
    }

    // Float variant for geometry multiplied by sin/cos
    function pxF(base, width) {
        return base * width / 260.0;
    }

    function isRound() {
        if (mRound == null) {
            mRound = System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_RECTANGLE;
        }
        return mRound;
    }

    function isTouch() {
        if (mTouch == null) {
            mTouch = System.getDeviceSettings().isTouchScreen;
        }
        return mTouch;
    }

    // Touch can be turned off in the watch settings while the app is away
    function refreshTouch() {
        mTouch = System.getDeviceSettings().isTouchScreen;
    }

    // Calculate usable width at a given Y on a round display
    function getUsableWidth(y, width, height) {
        if (!isRound()) { return width; }
        var r = width / 2;
        var dy = y - height / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) { return 0; }
        var hw = Math.sqrt(r * r - dy * dy).toNumber();
        return hw * 2;
    }

    function truncateToFit(dc, text, font, maxWidth) {
        var dims = dc.getTextDimensions(text, font);
        if (dims[0] <= maxWidth) {
            return text;
        }
        // Estimate chars that fit
        var charW = dims[0] / text.length();
        var maxChars = (maxWidth / charW).toNumber();
        if (maxChars < 2) { maxChars = 2; }
        if (maxChars >= text.length()) {
            return text;
        }
        return text.substring(0, maxChars - 1) + ".";
    }

    // Status text fitted to its slot through TextFit: [font, lines], with one
    // or two lines, the last wording cut only when nothing else fits
    (:textfit)
    function fitText(dc, texts, fonts, maxW, maxLines) {
        var oneW = [];
        var twoW = [];
        var halves = [];
        for (var t = 0; t < texts.size(); t++) {
            var h = TextFit.split(texts[t]);
            halves.add(h);
            var one = [];
            var two = [];
            for (var f = 0; f < fonts.size(); f++) {
                one.add(dc.getTextWidthInPixels(texts[t], fonts[f]));
                if (h == null) {
                    two.add(null);
                } else {
                    var a = dc.getTextWidthInPixels(h[0], fonts[f]);
                    var b = dc.getTextWidthInPixels(h[1], fonts[f]);
                    two.add(a > b ? a : b);
                }
            }
            oneW.add(one);
            twoW.add(two);
        }
        var c = TextFit.choose(oneW, twoW, maxW, maxLines);
        var font = fonts[c[1]];
        if (c[2] == 2) { return [font, halves[c[0]]]; }
        if (c[2] == 1) { return [font, [texts[c[0]]]]; }
        return [font, [truncateToFit(dc, texts[c[0]], font, maxW)]];
    }

    // Watches without the memory for TextFit: the first wording that fits on
    // one line in the first font, else the last one cut
    (:plaintext)
    function fitText(dc, texts, fonts, maxW, maxLines) {
        var font = fonts[0];
        var last = texts.size() - 1;
        for (var t = 0; t < last; t++) {
            if (dc.getTextWidthInPixels(texts[t], font) <= maxW) { return [font, [texts[t]]]; }
        }
        return [font, [truncateToFit(dc, texts[last], font, maxW)]];
    }
}
