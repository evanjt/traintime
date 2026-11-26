// Where the board draws its parts, shared by the renderer and the tap handler
// so a tap always lands on what is drawn under the finger.
module BoardLayout {

    enum {
        HIT_NONE,
        HIT_MODE,
        HIT_HEADER,
        HIT_ROW,
        // The tracking screen's targets, laid out by TrackLayout
        HIT_BACK,
        HIT_WALK,
        HIT_CAR
    }

    enum {
        HINT_ARCS,
        HINT_CHEVRONS
    }

    // Buttons get an arc on the bezel beside them, touch gets a chevron at
    // each tap target. Touch turned off in the watch settings reads as no touch.
    function hintKind(touch) {
        return touch ? HINT_CHEVRONS : HINT_ARCS;
    }

    function resumeHint(touch) {
        return touch ? Rez.Strings.TapResume : Rez.Strings.PressResume;
    }

    function maxRows(height) {
        return (height < 240) ? 3 : 4;
    }

    function modeY(height) {
        return height * 7 / 100;
    }

    function modeSpacing(width) {
        return width * 14 / 100;
    }

    // Four icons, three gaps, centred
    function modeX(i, width) {
        var sp = modeSpacing(width);
        return width / 2 - 3 * sp / 2 + i * sp;
    }

    function walkY(height) {
        return height * 13 / 100;
    }

    function stationY(height) {
        return height * 22 / 100;
    }

    function rowsTop(height) {
        return height * 36 / 100;
    }

    function rowSpacing(height) {
        return height * 14 / 100;
    }

    // Rows drawn from the scroll offset on, capped by the screen
    function visibleRows(total, offset, height) {
        var rows = total - offset;
        if (rows < 0) { return 0; }
        var cap = maxRows(height);
        return (rows > cap) ? cap : rows;
    }

    // The first visible row after the finger travels dy pixels (down is
    // positive) from a board that started at offset. The rows move one per
    // row spacing, snap to the nearest whole row, and stop at the first and
    // the last screenful of total rows.
    (:touch)
    function scrollOffset(offset, dy, height, total) {
        var sp = rowSpacing(height);
        var rows = (dy <= 0) ? (sp / 2 - dy) / sp : -((dy + sp / 2) / sp);
        var next = offset + rows;
        var last = total - maxRows(height);
        if (next > last) { next = last; }
        if (next < 0) { next = 0; }
        return next;
    }

    // The finger travel a flick adds, as scrollOffset reads it, from its
    // speed in pixels a second and its direction in degrees (0 up, 180
    // down): a quarter second's coast at that speed. A sideways flick adds none.
    (:touch)
    function flickTravel(velocity, direction) {
        var dir = direction % 360;
        if (dir < 0) { dir = dir + 360; }
        var carry = (velocity * 0.25f).toNumber();
        if (dir < 45 || dir > 315) { return -carry; }
        if (dir > 135 && dir < 225) { return carry; }
        return 0;
    }

    // Row columns, one set per device so they align across rows:
    // [minutesRight, delayX, slotX, slotW, destX]. Each sits at its share of the
    // width and moves right only as far as the fonts need: the minutes inside
    // the last row's edge, the line slot as wide as a four-character id.
    function columns(width, leftEdge, minW, delayW, idW, gap) {
        var minRight = width * 20 / 100;
        if (leftEdge + minW > minRight) { minRight = leftEdge + minW; }
        var delayX = minRight + width / 100;
        var slotX = width * 32 / 100;
        if (delayX + delayW + gap > slotX) { slotX = delayX + delayW + gap; }
        var slotW = width * 44 / 100 - gap - width * 32 / 100;
        if (idW > slotW) { slotW = idW; }
        var destX = width * 44 / 100;
        if (slotX + slotW + gap > destX) { destX = slotX + slotW + gap; }
        return [minRight, delayX, slotX, slotW, destX];
    }

    // A line id centred in its slot, or from the slot's left edge when wider
    function chipX(slotX, slotW, labelW) {
        return (labelW < slotW) ? slotX + (slotW - labelW) / 2 : slotX;
    }

    // What a tap at (x, y) lands on, as [HIT_*, index]. The mode band ends at
    // the walk line and is one target, since its icons are narrower than a
    // fingertip. The header ends at the first row. Each row band starts an
    // eighth of a spacing above its text, which centres it on the text.
    (:touch)
    function hit(x, y, width, height, rowCount) {
        if (y < walkY(height)) { return [HIT_MODE, 0]; }
        var sp = rowSpacing(height);
        var top = rowsTop(height) - sp / 8;
        if (y < top) { return [HIT_HEADER, 0]; }
        var row = (y - top) / sp;
        if (row < rowCount) { return [HIT_ROW, row]; }
        return [HIT_NONE, 0];
    }
}
