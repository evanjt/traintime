using Toybox.Math;

// Where the tracking screen draws its rows, top to bottom, and what a tap lands on.
// The renderer draws with it and the tap handler reads it, so a tap always lands on
// what is drawn under the finger.
module TrackLayout {

    // A round screen starts below the top of its arc
    function top(height, round) {
        return round ? height * 3 / 100 : 0;
    }

    // What each row gives up on a rectangular screen, where the fonts carry more leading
    // than the rows need and the formation strip takes a band of its own at the bottom
    function trim(width, round) {
        return round ? 0 : DrawUtils.px(4, width);
    }

    function stationY(width, height, round, xtinyH) {
        return top(height, round) + xtinyH - trim(width, round);
    }

    function destY(width, height, round, xtinyH) {
        return stationY(width, height, round, xtinyH) + xtinyH + DrawUtils.px(2, width) - trim(width, round);
    }

    // Row tops for the given font heights. The route row pushes everything under it
    // down by its own height, so it is null where that leaves the formation no room.
    function rows(width, height, round, xtinyH, tinyH, destH, mediumH, route) {
        var t = trim(width, round);
        var px2 = DrawUtils.px(2, width);
        var barH = DrawUtils.px(14, width) + DrawUtils.px(4, width);
        var plat = destY(width, height, round, xtinyH) + destH + 1 - t;
        var routeY = null;
        var lower = xtinyH + 2 - t + mediumH + px2 + barH - t + tinyH;
        var limit = round ? height - xtinyH - (xtinyH + 3) - DrawUtils.px(4, width)
            : FormationStrip.top(width, height) - px2 + t - xtinyH;
        if (route && plat + xtinyH + lower <= limit) {
            routeY = plat;
            plat += xtinyH;
        }
        var countdown = plat + xtinyH + 2 - t;
        var bar = countdown + mediumH + px2;
        var status = bar + barH - t;
        return {
            :route => routeY, :plat => plat, :countdown => countdown, :bar => bar,
            :status => status, :walk => status + tinyH + px2 - t
        };
    }

    // The back chevron's tap target, a square at the left edge centred half way down.
    // Three tenths of the width keep it at least 7 mm on every touch screen.
    (:touch)
    function backSize(width) {
        return width * 30 / 100;
    }

    (:touch)
    function backX(width) {
        return DrawUtils.px(12, width);
    }

    // A round band as the tap test reads it: its centre, the inner edge of its sector
    // letters, the angles it runs between and each car's middle angle
    (:touch)
    function roundStrip(g, sp) {
        var n = sp.size();
        var mids = new [n];
        for (var i = 0; i < n; i++) { mids[i] = (sp[i][0] + sp[i][1]) / 2; }
        return {
            :c => g[:c], :inner => g[:letterR] - 3.5 * g[:k] - 1,
            :from => g[:front], :to => sp[n - 1][1], :mids => mids
        };
    }

    // The straight strip: the top of its sector letters and each car's middle x
    (:touch)
    function rectStrip(r, sp) {
        var n = sp.size();
        var mids = new [n];
        for (var i = 0; i < n; i++) { mids[i] = (sp[i][0] + sp[i][1]) / 2; }
        return {:top => r[:letters], :mids => mids};
    }

    // The car under (x, y) on the strip, the nearest one when the tap falls between
    // cars or on the nose, null off the strip
    (:touch)
    function carAt(x, y, strip) {
        var v = x;
        if (strip.hasKey(:inner)) {
            var dx = x - strip[:c];
            var dy = y - strip[:c];
            if (Math.sqrt(dx * dx + dy * dy) < strip[:inner]) { return null; }
            v = Math.atan2(dy, dx);
            if (v < -Math.PI / 2) { v += 2 * Math.PI; }
            if (v > strip[:from] + 0.1 || v < strip[:to] - 0.1) { return null; }
        } else if (y < strip[:top]) {
            return null;
        }
        var mids = strip[:mids];
        var best = 0;
        for (var i = 1; i < mids.size(); i++) {
            if ((v - mids[i]).abs() < (v - mids[best]).abs()) { best = i; }
        }
        return best;
    }

    // What a tap at (x, y) lands on, as [BoardLayout.HIT_*, index]. walkTop is where
    // the walk line's target starts, under the status line, or null while the walk
    // line is not drawn. strip is roundStrip or rectStrip, or null with no formation.
    // The target reaches down to the strip, and anything above it is no target.
    (:touch)
    function hit(x, y, width, height, walkTop, strip) {
        var s = backSize(width);
        var dy = y - height / 2;
        if (x < s && dy.abs() <= s / 2) { return [BoardLayout.HIT_BACK, 0]; }
        if (strip != null) {
            var car = carAt(x, y, strip);
            if (car != null) { return [BoardLayout.HIT_CAR, car]; }
        }
        if (walkTop != null && y >= walkTop) { return [BoardLayout.HIT_WALK, 0]; }
        return [BoardLayout.HIT_NONE, 0];
    }
}
