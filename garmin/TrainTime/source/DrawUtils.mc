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
}
