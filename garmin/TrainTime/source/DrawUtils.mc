using Toybox.Math;
using Toybox.Graphics;

module DrawUtils {

    // Calculate usable width at a given Y on a round display
    function getUsableWidth(y, width, height) {
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
