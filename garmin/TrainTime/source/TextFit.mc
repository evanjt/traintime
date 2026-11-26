using Toybox.Lang;

// How a line of status text fits its slot: the first wording that fits on one
// line, largest font first, then on two lines, and only then a cut. Decided from
// measured widths so the choice is testable without a screen.
(:textfit)
module TextFit {

    // Where to break a text into two lines: the space nearest its middle, or
    // null when it has no space
    function split(text) {
        var chars = text.toCharArray();
        var mid = chars.size() / 2.0;
        var best = -1;
        var bestD = 0;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                var d = i - mid;
                if (d < 0) { d = -d; }
                if (best < 0 || d < bestD) {
                    best = i;
                    bestD = d;
                }
            }
        }
        if (best < 0) { return null; }
        return [text.substring(0, best), text.substring(best + 1, chars.size())];
    }

    // oneW[t][f] is wording t in font f on one line, twoW[t][f] the wider of its
    // two halves, or null when it cannot break. Returns [t, f, lines], lines 0
    // meaning nothing fits and the last wording in the last font is cut.
    function choose(oneW, twoW, maxW, maxLines) {
        var r = firstFit(oneW, maxW, 1);
        if (r == null && maxLines >= 2) { r = firstFit(twoW, maxW, 2); }
        if (r == null) {
            var t = oneW.size() - 1;
            r = [t, oneW[t].size() - 1, 0];
        }
        return r;
    }

    function firstFit(widths, maxW, lines) {
        for (var t = 0; t < widths.size(); t++) {
            for (var f = 0; f < widths[t].size(); f++) {
                var w = widths[t][f];
                if (w != null && w <= maxW) { return [t, f, lines]; }
            }
        }
        return null;
    }
}
