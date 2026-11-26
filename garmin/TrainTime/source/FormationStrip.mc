using Toybox.Graphics;

// The formation drawn as a straight strip along the bottom of a rectangular screen,
// with the parts of the bezel band. Cars run front first from the left, as the feed lists them.
module FormationStrip {

    // Glyph scale: 2x where the widest car readout still fits across the screen
    function scale(width) {
        return width >= 290 ? 2 : 1;
    }

    function lineH(width) {
        var h = DrawUtils.px(3, width);
        return h < 3 ? 3 : h;
    }

    // Top of the sector letters, the highest part of the strip
    function top(width, height) {
        return height - DrawUtils.px(2, width) - lineH(width) - 1 - (10 * scale(width) + 3)
            - DrawUtils.px(3, width) - 7 * scale(width);
    }

    // Row tops from the sector letters down to the amenity line at the bottom edge, and the
    // walk or readout row above them: under the status line, or against the strip where
    // the two would overlap
    function rows(width, height, walkY, rowH) {
        var k = scale(width);
        var letters = top(width, height);
        var car = letters + 7 * k + DrawUtils.px(3, width);
        var carH = 10 * k + 3;
        return {
            :row => (walkY + rowH > letters) ? letters - rowH : walkY,
            :letters => letters, :car => car, :carH => carH, :line => car + carH + 1
        };
    }

    // Nose, gap, slot and car widths for count cars across usable pixels, and the x the
    // nose starts at. A slot is the wider gap after a car with no passage to the next.
    function layout(width, usable, count, nBreaks) {
        var noseW = DrawUtils.px(14, width);
        var gapW = DrawUtils.px(2, width);
        var slotW = DrawUtils.px(8, width);
        var between = (count - 1 - nBreaks) * gapW + nBreaks * slotW;
        var carW = (usable - noseW - gapW - between) / count;
        if (carW > DrawUtils.px(30, width)) { carW = DrawUtils.px(30, width); }
        if (carW < 3) { carW = 3; }
        var used = noseW + gapW + count * carW + between;
        return {
            :k => scale(width), :c => width / 2.0, :x => (width - used) / 2,
            :noseW => noseW, :gapW => gapW, :slotW => slotW, :carW => carW
        };
    }

    // Car spans as [left, right] pairs, front first
    function spans(g, breaks) {
        var x = g[:x] + g[:noseW] + g[:gapW];
        var out = new [breaks.size()];
        for (var i = 0; i < breaks.size(); i++) {
            out[i] = [x, x + g[:carW]];
            x += g[:carW] + (breaks[i] ? g[:slotW] : g[:gapW]);
        }
        return out;
    }

    // Draws the strip. cursor is the highlighted car index or null.
    (:rect)
    function draw(dc, g, r, view, cursor, sp, labels) {
        var k = g[:k];
        var f = FormationArc.font(k);
        var n = sp.size();
        var y = r[:car];
        var h = r[:carH];
        var tickH = y - r[:letters] - 7 * k;
        var bottom = r[:line] + lineH(dc.getWidth());

        drawNose(dc, g, y, h);
        for (var i = 0; i < n; i++) {
            var x = sp[i][0];
            var w = g[:carW];
            var closed = FormationArc.isClosed(view, i);
            if (cursor != null && cursor == i) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawRectangle(x + 1, y + 1, w - 2, h - 2);
            } else {
                dc.setColor(closed ? FormationArc.COLOUR_CLOSED : FormationArc.COLOUR_OUTLINE,
                    Graphics.COLOR_TRANSPARENT);
            }
            dc.drawRectangle(x, y, w, h);
            if (view.mFormationClasses[i] == 1 && !closed) {
                var mixed = view.mFormationMixed != null && view.mFormationMixed[i];
                dc.setColor(FormationArc.COLOUR_FIRST, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + 1, y + 1, (mixed ? w / 2 : w) - 2, 3 * k - 1);
            }
            // Amenity line on black just under the car, one segment per amenity
            var bits = (view.mFormationAmenities != null && !closed) ? view.mFormationAmenities[i] : 0;
            var count = 0;
            for (var b = 0; b < FormationArc.AMEN_BITS.size(); b++) {
                if ((bits & FormationArc.AMEN_BITS[b]) != 0) { count++; }
            }
            if (count > 0) {
                var seg = (w - 2 * (count - 1)) / count;
                var q = 0;
                for (var b = 0; b < FormationArc.AMEN_BITS.size(); b++) {
                    if ((bits & FormationArc.AMEN_BITS[b]) == 0) { continue; }
                    dc.setColor(FormationArc.AMEN_COLOURS[b], Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(x + q * (seg + 2), r[:line], seg, bottom - r[:line]);
                    q++;
                }
            }
            if (view.mFormationBreaks[i] && i < n - 1) {
                dc.setColor(FormationArc.COLOUR_BREAK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(sp[i][1] + (g[:slotW] - 3 * k) / 2, y - tickH, 3 * k, bottom - y + tickH);
            }
        }

        // Numbers sit under the roof band. A range clears the car edges it crosses, and
        // gives way while the highlight is on one of its cars: the readout has the number.
        for (var q = 0; q < labels.size(); q++) {
            var a = labels[q][0];
            var b = labels[q][1];
            var mid = (sp[a][0] + sp[b][1]) / 2;
            if (b > a) {
                if (cursor != null && cursor >= a && cursor <= b) { continue; }
                var half = labels[q][2].length() * 3 * k;
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(mid - half - k, y + 3 * k, 2 * half + 2 * k, h - 3 * k - 2);
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mid, y + (13 * k + 1) / 2, f, labels[q][2],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Sector letters over each run of cars, ticks at sector boundaries
        var sectors = view.mFormationSectors;
        var i = 0;
        while (i < n) {
            var j = i + 1;
            while (j < n && sectors[j].equals(sectors[i])) { j++; }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText((sp[i][0] + sp[j - 1][1]) / 2, r[:letters] + (7 * k) / 2, f, sectors[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (j < n) {
                dc.setColor(FormationArc.COLOUR_TICK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle((sp[j - 1][1] + sp[j][0]) / 2, y - tickH, k, tickH - 1);
            }
            i = j;
        }
    }

    // Nose at the front with a chevron for the direction of travel
    (:rect)
    function drawNose(dc, g, y, h) {
        var x = g[:x];
        var right = x + g[:noseW];
        dc.setColor(FormationArc.COLOUR_OUTLINE, Graphics.COLOR_TRANSPARENT);
        FormationArc.outline(dc, [
            [right - 1, y], [x + g[:noseW] / 2, y], [x, y + h * 2 / 3], [x, y + h - 1], [right - 1, y + h - 1]
        ]);
        var z = 3 * g[:k];
        var cx = x + g[:noseW] * 6 / 10;
        var cy = y + h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - z, cy], [cx + z * 6 / 10, cy - z], [cx + z * 6 / 10, cy + z]]);
    }
}
