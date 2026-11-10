using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.WatchUi;

// The formation drawn as a thin band against the bezel of a round screen, below the
// status and walk lines. Cars run front first from the left, as the feed lists them.
module FormationArc {

    const AMEN_RESTAURANT = 1;
    const AMEN_WHEELCHAIR = 2;
    const AMEN_FAMILY = 4;
    const AMEN_BIKE = 8;

    // Four hues from the 64-colour MIP palette, distinct for normal, deutan and protan vision
    const AMEN_BITS = [1, 2, 4, 8];
    const AMEN_COLOURS = [0xFF5555, 0x00AAFF, 0xFFFFFF, 0x55FF00];
    const AMEN_GLYPHS = ["r", "w", "f", "b"];

    const COLOUR_BODY = 0x555555;
    // A closed car keeps only a dim outline: no number, roof band or amenity line
    const COLOUR_CLOSED = 0x555555;
    // Cars are outlined, not filled, so the roof band, lines and numbers keep their contrast
    const COLOUR_OUTLINE = 0xAAAAAA;
    const COLOUR_FIRST = 0xFFFF00;
    const COLOUR_BREAK = 0xFF0000;
    const COLOUR_TICK = 0xAAAAAA;

    // The car readout stays this long after the last Up/Down press
    const READOUT_SECONDS = 5;

    // End angle of the readout ring for the share of time left, drawn clockwise from
    // 12 o'clock. Kept within 0..359: the device draws nothing for a negative angle.
    function ringEndDegree(left) {
        var end = (90 - 360 * left).toNumber() % 360;
        return end < 0 ? end + 360 : end;
    }

    // Share of the readout time left, 1.0 just after a press, 0.0 once it has gone
    function readoutLeft(elapsed) {
        var left = 1.0 - elapsed.toFloat() / READOUT_SECONDS;
        if (left < 0.0) { return 0.0; }
        return left > 1.0 ? 1.0 : left;
    }

    var mFont1 = null;

    var mFont2 = null;

    function font(k) {
        if (k >= 2) {
            if (mFont2 == null) { mFont2 = WatchUi.loadResource(Rez.Fonts.Formation2); }
            return mFont2;
        }
        if (mFont1 == null) { mFont1 = WatchUi.loadResource(Rez.Fonts.Formation1); }
        return mFont1;
    }

    // Glyph scale: 2x on the large AMOLED screens, 1x below
    function scale(width) {
        return width >= 390 ? 2 : 1;
    }

    function px(base, width) {
        var v = Math.round(base * width / 260.0).toNumber();
        return v < 1 ? 1 : v;
    }

    // Band geometry for a screen, given the y the band must stay below at its ends.
    // Returns radii, the arc span and the per-car width at the mid radius.
    function layout(width, topY, count, breaks) {
        var k = scale(width);
        var c = width / 2.0;
        var lineW = px(3, width);
        if (lineW < 3) { lineW = 3; }
        var rl2 = c - 1;
        var rl1 = rl2 - lineW;
        var ro = rl1 - 1;
        var ri = ro - (10 * k + 3);
        var rm = (ri + ro) / 2.0;
        var letterR = ri - px(3, width) - 3.5 * k;
        var sin1 = (topY + px(2, width) - c) / rl2;
        if (sin1 > 1.0) { sin1 = 1.0; }
        if (sin1 < -1.0) { sin1 = -1.0; }
        var a1 = Math.asin(sin1);
        var span = Math.PI - 2 * a1;
        var nosePx = px(14, width);
        var gapPx = px(2, width);
        var slotPx = px(8, width);
        var carPx = (span * rm - nosePx - gapPx - (count - 1 - breaks) * gapPx - breaks * slotPx) / count;
        if (carPx > px(30, width)) { carPx = px(30, width).toFloat(); }
        var used = nosePx + gapPx + count * carPx + (count - 1 - breaks) * gapPx + breaks * slotPx;
        return {
            :k => k, :c => c, :rl1 => rl1, :rl2 => rl2, :ro => ro, :ri => ri, :rm => rm,
            :letterR => letterR, :front => Math.PI / 2 + used / rm / 2,
            :nosePx => nosePx, :gapPx => gapPx, :slotPx => slotPx, :carPx => carPx
        };
    }

    // Car spans as [startAngle, endAngle] pairs, front first (angles decrease to the right)
    function spans(g, breaks) {
        var rm = g[:rm];
        var a = g[:front] - (g[:nosePx] + g[:gapPx]) / rm;
        var out = new [breaks.size()];
        for (var i = 0; i < breaks.size(); i++) {
            var a2 = a - g[:carPx] / rm;
            out[i] = [a, a2];
            a = a2 - (breaks[i] ? g[:slotPx] : g[:gapPx]) / rm;
        }
        return out;
    }

    // Labels are set along the curve: each character upright, stepped along the band.
    // Toward the steep ends the step widens just enough that neighbours never overlap.
    function stepAt(mid, k) {
        var sx = Math.sin(mid).abs();
        var cy = Math.cos(mid).abs();
        var byX = sx > 0.05 ? (5 * k + 1) / sx : 1000.0;
        var byY = cy > 0.05 ? (7 * k + 1) / cy : 1000.0;
        return byX < byY ? byX : byY;
    }

    // Whether label fits over cars a..b
    function labelFits(label, sp, rm, k, a, b) {
        var mid = (sp[a][0] + sp[b][1]) / 2;
        return label.length() * stepAt(mid, k) - 1 <= (sp[a][0] - sp[b][1]) * rm - 2;
    }

    // Car numbers to label, null for a closed car so no label covers it
    function shownNumbers(numbers, closed) {
        if (closed == null) { return numbers; }
        var out = new [numbers.size()];
        for (var i = 0; i < out.size(); i++) { out[i] = closed[i] ? null : numbers[i]; }
        return out;
    }

    function isClosed(view, i) {
        return view.mFormationClosed != null && view.mFormationClosed[i];
    }

    function rangeLabel(numbers, a, b) {
        return b > a ? numbers[a] + "-" + numbers[b] : numbers[a].toString();
    }

    // Number labels as [i, j, label] triples: every numbered car's own number when all fit,
    // otherwise a range per run of same-class cars, extended over the next run until it fits,
    // so every numbered car is covered. No label crosses a break or an unnumbered car.
    function numberLabels(numbers, classes, breaks, sp, rm, k) {
        var n = numbers.size();
        var out = [];
        var perCar = true;
        for (var i = 0; i < n && perCar; i++) {
            if (numbers[i] != null) {
                perCar = labelFits(numbers[i].toString(), sp, rm, k, i, i);
                out.add([i, i, numbers[i].toString()]);
            }
        }
        if (perCar) { return out; }
        out = [];
        var i = 0;
        while (i < n) {
            if (numbers[i] == null) {
                i++;
                continue;
            }
            var u = i;
            while (u < n - 1 && !breaks[u] && numbers[u + 1] != null) { u++; }
            var a = i;
            while (a <= u) {
                var b = a;
                while (b < u && classes[b + 1] == classes[a]) { b++; }
                var label = rangeLabel(numbers, a, b);
                while (!labelFits(label, sp, rm, k, a, b) && b < u) {
                    b++;
                    while (b < u && classes[b + 1] == classes[b]) { b++; }
                    label = rangeLabel(numbers, a, b);
                }
                // A tail that still does not fit joins the label before it in the same run
                if (!labelFits(label, sp, rm, k, a, b) && out.size() > 0) {
                    var prev = out[out.size() - 1];
                    if (prev[1] == a - 1 && prev[0] >= i) {
                        a = prev[0];
                        label = rangeLabel(numbers, a, b);
                        out = out.slice(0, out.size() - 1);
                    }
                }
                if (!labelFits(label, sp, rm, k, a, b)) { label = numbers[a].toString(); }
                out.add([a, b, label]);
                a = b + 1;
            }
            i = u + 1;
        }
        return out;
    }

    // Draws label centred on angle mid at radius r, characters stepped along the curve
    function drawAlong(dc, g, f, label, mid, r) {
        var step = stepAt(mid, g[:k]) / r;
        var len = label.length();
        for (var j = 0; j < len; j++) {
            var p = point(g, r, mid + ((len - 1) / 2.0 - j) * step);
            dc.drawText(p[0], p[1], f, label.substring(j, j + 1),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function point(g, r, a) {
        return [(g[:c] + r * Math.cos(a)).toNumber(), (g[:c] + r * Math.sin(a)).toNumber()];
    }

    function annulusPoints(g, r1, r2, a1, a2) {
        var steps = (((a1 - a2).abs() * r2) / 4).toNumber();
        if (steps < 2) { steps = 2; }
        var pts = new [2 * steps + 2];
        for (var s = 0; s <= steps; s++) {
            pts[s] = point(g, r2, a1 + (a2 - a1) * s / steps);
            pts[2 * steps + 1 - s] = point(g, r1, a1 + (a2 - a1) * s / steps);
        }
        return pts;
    }

    function fillAnnulus(dc, g, r1, r2, a1, a2) {
        dc.fillPolygon(annulusPoints(g, r1, r2, a1, a2));
    }

    function outline(dc, pts) {
        var n = pts.size();
        for (var i = 0; i < n; i++) {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

    // True when a centred text box of width w at y sits inside the sector-letter ring
    function clearsBand(g, w, y, h) {
        var limit = g[:letterR] - 3.5 * g[:k] - 1;
        var dx = w / 2.0;
        var dy = y + h - g[:c];
        return Math.sqrt(dx * dx + dy * dy) < limit;
    }

    // Draws the band. cursor is the highlighted car index or null.
    function draw(dc, g, view, cursor, sp, labels) {
        drawNose(dc, g);
        drawCars(dc, g, view, cursor, sp, labels);
        drawSectors(dc, g, view.mFormationSectors, sp, view.mFormationClasses.size(), font(g[:k]));
    }

    function drawNose(dc, g) {
        var rm = g[:rm];
        var k = g[:k];
        // Nose at the front with a chevron for the direction of travel
        var noseEnd = g[:front] - g[:nosePx] / rm;
        dc.setColor(COLOUR_OUTLINE, Graphics.COLOR_TRANSPARENT);
        var nose = new [10];
        for (var s = 0; s <= 6; s++) { nose[s] = point(g, g[:ro], noseEnd + (g[:front] - noseEnd) * s / 6); }
        nose[7] = point(g, g[:ro] - (g[:ro] - g[:ri]) / 2, g[:front] - 1 / rm);
        nose[8] = point(g, g[:ri] + 2, noseEnd + 3 / rm);
        nose[9] = point(g, g[:ri], noseEnd);
        outline(dc, nose);
        var ah = noseEnd + g[:nosePx] * 0.55 / rm;
        var cx = g[:c] + rm * Math.cos(ah);
        var cy = g[:c] + rm * Math.sin(ah);
        var tx = -Math.sin(ah);
        var ty = Math.cos(ah);
        var nx = Math.cos(ah);
        var ny = Math.sin(ah);
        var z = 3 * k;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(cx + tx * z).toNumber(), (cy + ty * z).toNumber()],
            [(cx - tx * z * 0.6 - nx * z).toNumber(), (cy - ty * z * 0.6 - ny * z).toNumber()],
            [(cx - tx * z * 0.6 + nx * z).toNumber(), (cy - ty * z * 0.6 + ny * z).toNumber()]
        ]);
    }

    function drawCars(dc, g, view, cursor, sp, labels) {
        var classes = view.mFormationClasses;
        var breaks = view.mFormationBreaks;
        var amen = view.mFormationAmenities;
        var mixed = view.mFormationMixed;
        var n = classes.size();
        var k = g[:k];
        var rm = g[:rm];
        var f = font(k);

        // Numbers sit just outside the roof band, leaving room for horizontal text where the band tilts
        var numR = g[:ri] + 6.5 * k + 1;

        for (var i = 0; i < n; i++) {
            var a1 = sp[i][0];
            var a2 = sp[i][1];
            var highlighted = cursor != null && cursor == i;
            var closed = isClosed(view, i);
            var edge = closed ? COLOUR_CLOSED : COLOUR_OUTLINE;
            dc.setPenWidth(highlighted ? 2 : 1);
            dc.setColor(highlighted ? Graphics.COLOR_WHITE : edge, Graphics.COLOR_TRANSPARENT);
            outline(dc, annulusPoints(g, g[:ri], g[:ro], a1, a2));
            dc.setPenWidth(1);
            if (classes[i] == 1 && !closed) {
                dc.setColor(COLOUR_FIRST, Graphics.COLOR_TRANSPARENT);
                var end = (mixed != null && mixed[i]) ? (a1 + a2) / 2 : a2 + 1 / rm;
                fillAnnulus(dc, g, g[:ri] + 1, g[:ri] + 1 + 3 * k, a1 - 1 / rm, end);
            }
            // Amenity line on black just outside the car, one segment per amenity
            var bits = (amen != null && !closed) ? amen[i] : 0;
            var count = 0;
            for (var b = 0; b < AMEN_BITS.size(); b++) { if ((bits & AMEN_BITS[b]) != 0) { count++; } }
            if (count > 0) {
                var seg = (g[:carPx] - 2 * (count - 1)) / count;
                var q = 0;
                for (var b = 0; b < AMEN_BITS.size(); b++) {
                    if ((bits & AMEN_BITS[b]) == 0) { continue; }
                    var e1 = a1 - q * (seg + 2) / rm;
                    dc.setColor(AMEN_COLOURS[b], Graphics.COLOR_TRANSPARENT);
                    fillAnnulus(dc, g, g[:rl1], g[:rl2], e1, e1 - seg / rm);
                    q++;
                }
            }
            if (breaks[i] && i < n - 1) {
                var bb = a2 - g[:slotPx] / 2.0 / rm;
                dc.setColor(COLOUR_BREAK, Graphics.COLOR_TRANSPARENT);
                fillAnnulus(dc, g, g[:ri] - px(3, dc.getWidth()), g[:rl2], bb + 1.5 * k / rm, bb - 1.5 * k / rm);
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var q = 0; q < labels.size(); q++) {
            drawAlong(dc, g, f, labels[q][2], (sp[labels[q][0]][0] + sp[labels[q][1]][1]) / 2, numR);
        }

    }

    function drawSectors(dc, g, sectors, sp, n, f) {
        var rm = g[:rm];
        // Sector letters just inside the band, ticks at sector boundaries
        var i = 0;
        while (i < n) {
            var j = i + 1;
            while (j < n && sectors[j].equals(sectors[i])) { j++; }
            var mid = ((sp[i][0] + sp[i][1]) / 2 + (sp[j - 1][0] + sp[j - 1][1]) / 2) / 2;
            var p = point(g, g[:letterR], mid);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(p[0], p[1], f, sectors[i], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (j < n) {
                var bnd = ((sp[j - 1][0] + sp[j - 1][1]) / 2 + (sp[j][0] + sp[j][1]) / 2) / 2;
                dc.setColor(COLOUR_TICK, Graphics.COLOR_TRANSPARENT);
                fillAnnulus(dc, g, g[:ri] - px(3, dc.getWidth()), g[:ri] - 1, bnd + 0.5 / rm, bnd - 0.5 / rm);
            }
            i = j;
        }
    }

    // One line in the walk line's place: number when the feed gives one, sector, and each
    // amenity's colour beside its icon
    function drawReadout(dc, g, view, cursor, y, rowH, elapsed) {
        var k = g[:k];
        var f = font(k);
        var closed = isClosed(view, cursor);
        var num = closed ? null : view.mFormationNumbers[cursor];
        var sector = view.mFormationSectors[cursor];
        var bits = (view.mFormationAmenities != null && !closed) ? view.mFormationAmenities[cursor] : 0;
        var gap = 5 * k;
        var item = 7 * k + 3 + 11 * k + 4 * k;
        var total = dc.getTextWidthInPixels(sector, f) + gap;
        if (num != null) {
            num = num.toString();
            total += dc.getTextWidthInPixels(num, f) + gap;
        }
        // The pixel font has no lower-case letters, so the word is set in the system font
        var word = closed ? Txt.t(Rez.Strings.FormationClosed) : null;
        if (word != null) { total += dc.getTextWidthInPixels(word, Graphics.FONT_XTINY) + gap; }
        for (var b = 0; b < AMEN_BITS.size(); b++) { if ((bits & AMEN_BITS[b]) != 0) { total += item; } }
        var ringR = 4 * k + 1;
        total += 2 * ringR + gap;
        var x = (g[:c] - total / 2).toNumber();
        var cy = y + rowH / 2;
        if (num != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, f, num, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(num, f) + gap;
        }
        dc.setColor(closed ? COLOUR_CLOSED : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, f, sector, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += dc.getTextWidthInPixels(sector, f) + gap;
        if (word != null) {
            dc.drawText(x, cy, Graphics.FONT_XTINY, word, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(word, Graphics.FONT_XTINY) + gap;
        }
        for (var b = 0; b < AMEN_BITS.size(); b++) {
            if ((bits & AMEN_BITS[b]) == 0) { continue; }
            dc.setColor(AMEN_COLOURS[b], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, cy - k, 7 * k, 3 * k);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + 7 * k + 3, cy, f, AMEN_GLYPHS[b], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += item;
        }
        // A ring that drains until the readout clears, so it is clear no button is needed to close it
        var rx = x + ringR;
        dc.setPenWidth(k + 1);
        dc.setColor(COLOUR_BODY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(rx, cy, ringR);
        var left = readoutLeft(elapsed);
        if (left > 0.0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (left >= 1.0) {
                dc.drawCircle(rx, cy, ringR);
            } else {
                dc.drawArc(rx, cy, ringR, Graphics.ARC_CLOCKWISE, 90, ringEndDegree(left));
            }
        }
        dc.setPenWidth(1);
    }
}
