using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;

module Renderer {

    function render(dc, view) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        view.mMaxVisibleTrains = (height < 240) ? 3 : 4;

        // GPS quality indicator. Tracking draws its own next to the clock,
        // centred, so the two never collide in the top-right arc
        if (view.mAppState != 2) {
            drawGpsIndicator(dc, view, width, height);
        }

        // State 3: inactive
        if (view.mAppState == 3) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 40 / 100, Graphics.FONT_MEDIUM,
                "Inactive", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height * 55 / 100, Graphics.FONT_TINY,
                "Press to resume", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // State 2: focused tracking
        if (view.mAppState == 2 && view.mFocusedTrain != null) {
            drawFocusedMode(dc, view, width, height);
            return;
        }

        if (view.mStationName != null) {
            // Mode indicators (above walk info)
            drawModeIndicators(dc, view, width, height);

            // Walking info line / station indicator. Just after a mode change the
            // line announces the new mode instead, so cycling is self-explanatory
            var walkY = height * 13 / 100;
            var modeLabel = null;
            if (view.mAppState == 0 && view.mModeChangedTime != null
                    && Time.now().value() - view.mModeChangedTime < 3) {
                if (view.mCurrentMode == 0) { modeLabel = "Trains"; }
                else if (view.mCurrentMode == 1) { modeLabel = "Buses"; }
                else if (view.mCurrentMode == 2) { modeLabel = "Trams"; }
                else { modeLabel = "Boats & lifts"; }
            }
            if (modeLabel != null) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    modeLabel, Graphics.TEXT_JUSTIFY_CENTER);
            } else if (view.mWalkInfo != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                var walkMaxW = DrawUtils.getUsableWidth(walkY + 8, width, height) - 10;
                var walkText = DrawUtils.truncateToFit(dc, view.mWalkInfo, Graphics.FONT_XTINY, walkMaxW);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    walkText, Graphics.TEXT_JUSTIFY_CENTER);
            }

            // Station name. With the cursor on the header it becomes a carousel:
            // chevrons + counter show that START cycles the nearby stations
            var stationY = height * 22 / 100;
            var stationMaxW = DrawUtils.getUsableWidth(stationY + 12, width, height) - 10;
            var onHeader = (view.mAppState == 1 && view.mCursorIndex == -1);
            var counter = null;
            if (onHeader && view.mStations != null && view.mStations.size() > 1) {
                counter = (view.mStationIndex + 1) + "/" + view.mStations.size();
            }
            var stationText = view.mStationName.toUpper();
            var stationFont = Graphics.FONT_MEDIUM;
            var nameMaxW = stationMaxW;
            var triW = 0;
            var triH = 0;
            var gap = 0;
            var counterW = 0;
            if (onHeader) {
                triH = dc.getFontHeight(Graphics.FONT_MEDIUM) / 2;
                triW = 2 * triH / 3;
                gap = DrawUtils.px(6, width);
                if (counter != null) {
                    counterW = dc.getTextDimensions(counter, Graphics.FONT_XTINY)[0] + gap;
                }
                nameMaxW = stationMaxW - 2 * (triW + gap) - counterW;
            }
            var dims = dc.getTextDimensions(stationText, stationFont);
            if (dims[0] > nameMaxW) {
                stationFont = Graphics.FONT_SMALL;
                dims = dc.getTextDimensions(stationText, stationFont);
                if (dims[0] > nameMaxW) {
                    stationFont = Graphics.FONT_TINY;
                    stationText = DrawUtils.truncateToFit(dc, stationText, stationFont, nameMaxW);
                    dims = dc.getTextDimensions(stationText, stationFont);
                }
            }
            if (onHeader) {
                var fontH = dc.getFontHeight(stationFont);
                var midY = stationY + fontH / 2;
                var assemblyW = triW + gap + dims[0] + gap + triW + counterW;
                var ax = centerX - assemblyW / 2;
                var bgPad = DrawUtils.px(4, width);
                dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(ax - bgPad, stationY, assemblyW + 2 * bgPad,
                    fontH, fontH / 4);
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon([[ax + triW, midY - triH / 2], [ax, midY],
                    [ax + triW, midY + triH / 2]]);
                var rx = ax + triW + gap + dims[0] + gap;
                dc.fillPolygon([[rx, midY - triH / 2], [rx + triW, midY],
                    [rx, midY + triH / 2]]);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(ax + triW + gap, stationY, stationFont,
                    stationText, Graphics.TEXT_JUSTIFY_LEFT);
                if (counter != null) {
                    var xtH = dc.getFontHeight(Graphics.FONT_XTINY);
                    dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(rx + triW + gap, stationY + (fontH - xtH) / 2,
                        Graphics.FONT_XTINY, counter, Graphics.TEXT_JUSTIFY_LEFT);
                }
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, stationY, stationFont,
                    stationText, Graphics.TEXT_JUSTIFY_CENTER);
            }

            if (view.mTrainData != null && view.mTrainData.size() > 0) {
                // Train rows (favourites first, then regular)
                var maxTrains = 4;
                if (height < 240) {
                    maxTrains = 3;
                }
                var startY = height * 36 / 100;
                var rowSpacing = height * 14 / 100;

                // Build combined list: favourites + separator marker + regular departures
                var favCount = 0;
                if (view.mFavouriteData != null) {
                    favCount = view.mFavouriteData.size();
                }

                if (view.mAppState == 1) {
                    // Selection mode: favourites first, then regular departures
                    var selectTotal = view.getSelectableCount();
                    var startIdx = view.mScrollOffset;
                    var endIdx = selectTotal;
                    if (endIdx > startIdx + maxTrains) {
                        endIdx = startIdx + maxTrains;
                    }
                    for (var i = startIdx; i < endIdx; i++) {
                        var row = i - startIdx;
                        var highlighted = (i == view.mCursorIndex);
                        var item = view.getSelectableItem(i);
                        var isFav = false;
                        if (view.mStationId != null) {
                            isFav = FavouritesManager.isFavourite(view.mStationId,
                                item["line"], item["dest"]);
                        }
                        drawTrainRow(dc, item,
                            startY + row * rowSpacing, width, height, highlighted, isFav);
                    }
                    // Draw separator line after favourites section (if visible)
                    if (favCount > 0 && selectTotal > favCount) {
                        var sepIdx = favCount - 1;  // last favourite index
                        if (sepIdx >= startIdx && sepIdx < endIdx) {
                            var sepRow = sepIdx - startIdx;
                            var tinyH = dc.getFontHeight(Graphics.FONT_TINY);
                            var sepY2 = startY + sepRow * rowSpacing + tinyH + 1;
                            var sepUsable2 = DrawUtils.getUsableWidth(sepY2, width, height) - 20;
                            var sepX2 = (width - sepUsable2) / 2;
                            dc.setColor(0x998800, Graphics.COLOR_TRANSPARENT);
                            dc.fillRectangle(sepX2, sepY2, sepUsable2, 2);
                        }
                    }
                } else {
                    // Station view: favourites first, then separator, then regular
                    var rowIdx = 0;

                    // Draw favourite rows
                    for (var f = 0; f < favCount && rowIdx < maxTrains; f++) {
                        drawTrainRow(dc, view.mFavouriteData[f],
                            startY + rowIdx * rowSpacing, width, height, false, true);
                        rowIdx = rowIdx + 1;
                    }

                    // Horizontal line under favourites section
                    if (favCount > 0 && rowIdx < maxTrains && view.mTrainData.size() > 0) {
                        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);
                        var sepY = startY + (rowIdx - 1) * rowSpacing + tinyH + 1;
                        var sepUsable = DrawUtils.getUsableWidth(sepY, width, height) - 20;
                        var sepX = (width - sepUsable) / 2;
                        dc.setColor(0x998800, Graphics.COLOR_TRANSPARENT);
                        dc.fillRectangle(sepX, sepY, sepUsable, 2);
                    }

                    // Draw regular departure rows (favourites in list get gold bg too)
                    for (var t = 0; t < view.mTrainData.size() && rowIdx < maxTrains; t++) {
                        var regFav = false;
                        if (view.mStationId != null) {
                            regFav = FavouritesManager.isFavourite(view.mStationId,
                                view.mTrainData[t]["line"], view.mTrainData[t]["dest"]);
                        }
                        drawTrainRow(dc, view.mTrainData[t],
                            startY + rowIdx * rowSpacing, width, height, false, regFav);
                        rowIdx = rowIdx + 1;
                    }
                }
            } else if (view.mTrainData != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                    "No departures", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                var bodyMsg = "Loading...";
                if (!view.mRequestInFlight) {
                    bodyMsg = view.mStatus;
                }
                dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                    bodyMsg, Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else {
            // No station yet, show status or loading indicator
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var loadMsg = view.mRequestInFlight ? "Loading..." : view.mStatus;
            dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                loadMsg, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Primary action label at the bottom; the accent arc marks the button
        if (view.mStationName != null && (view.mAppState == 1 || (view.mTrainData != null && view.mTrainData.size() > 0))) {
            var hintY = height * 92 / 100;
            var hintMaxW = DrawUtils.getUsableWidth(hintY + 6, width, height) - 10;
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            var hint;
            if (view.mAppState == 0) {
                hint = "Select";
            } else if (view.mCursorIndex == -1) {
                hint = "Next station";
            } else {
                hint = "Track";
            }
            dc.drawText(centerX, hintY, Graphics.FONT_XTINY,
                DrawUtils.truncateToFit(dc, hint, Graphics.FONT_XTINY, hintMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        drawButtonHints(dc, view, width, height);
    }

    // Arc ticks on the bezel at each physical button that does something in the
    // current state. Gated per button via inputButtons, so two-button touch
    // watches only show the buttons they actually have
    function drawButtonHints(dc, view, width, height) {
        if (!DrawUtils.isRound() || view.mAppState == 3) { return; }
        var ib = System.getDeviceSettings().inputButtons;
        var hasUpDown = (ib & System.BUTTON_INPUT_UP) != 0
            && (ib & System.BUTTON_INPUT_DOWN) != 0;
        var hasStart = (ib & (System.BUTTON_INPUT_START | System.BUTTON_INPUT_SELECT)) != 0;
        var hasBack = (ib & (System.BUTTON_INPUT_ESC | System.BUTTON_INPUT_LAP)) != 0;

        if (view.mAppState == 2) {
            var canNav = view.mStationLat != null && view.mStationLon != null;
            if (hasStart && canNav) { drawButtonHint(dc, width, height, 30, true); }
            if (hasBack) { drawButtonHint(dc, width, height, 330, false); }
            return;
        }
        // Up/Down cycle modes in the station view; with one mode that's a no-op,
        // so the arcs only appear when the buttons actually do something
        var upDownActive = (view.mAppState == 1) || view.mAvailableModes.size() > 1;
        if (hasStart) { drawButtonHint(dc, width, height, 30, true); }
        if (hasUpDown && upDownActive) {
            drawButtonHint(dc, width, height, 180, false);
            drawButtonHint(dc, width, height, 210, false);
        }
        if (view.mAppState == 1 && hasBack) {
            drawButtonHint(dc, width, height, 330, false);
        }

        // Just after launch or a mode change, name the buttons next to their arcs
        if (view.mAppState == 0 && view.mHintTime != null
                && Time.now().value() - view.mHintTime < 3) {
            if (hasStart) { drawHintLabel(dc, width, height, 30, "Select"); }
            if (hasUpDown && upDownActive) {
                drawHintLabel(dc, width, height, 195, "Mode");
            }
        }
    }

    function drawHintLabel(dc, width, height, centreDeg, text) {
        var r = width / 2 - DrawUtils.px(14, width);
        var rad = centreDeg * Math.PI / 180.0;
        var x = width / 2 + r * Math.cos(rad);
        var y = height / 2 - r * Math.sin(rad) - dc.getFontHeight(Graphics.FONT_XTINY) / 2;
        var just = (centreDeg < 90 || centreDeg > 270)
            ? Graphics.TEXT_JUSTIFY_RIGHT : Graphics.TEXT_JUSTIFY_LEFT;
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, text, just);
    }

    function drawButtonHint(dc, width, height, centreDeg, accent) {
        var r = width / 2 - DrawUtils.px(4, width);
        dc.setPenWidth(DrawUtils.px(3, width));
        dc.setColor(accent ? 0x55AAFF : 0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(width / 2, height / 2, r, Graphics.ARC_COUNTER_CLOCKWISE,
            centreDeg - 8, centreDeg + 8);
        dc.setPenWidth(1);
    }

    function isModeAvailable(view, mode) {
        for (var i = 0; i < view.mAvailableModes.size(); i++) {
            if (view.mAvailableModes[i] == mode) {
                return true;
            }
        }
        return false;
    }

    function drawModeIndicators(dc, view, width, height) {
        var cy = height * 7 / 100;
        var iconSpacing = width * 14 / 100;
        var totalWidth = 3 * iconSpacing;  // 4 icons, 3 gaps
        var startX = width / 2 - totalWidth / 2;

        // Shared glyph metrics: s is the icon half-width, everything derives from it
        var s = DrawUtils.px(5, width);
        var wr = (2 * s + 2) / 5;               // wheel radius
        var pen = DrawUtils.px(1, width);
        var inset = (s + 2) / 4;                // window inset from body edge
        var winH = s * 3 / 5;                   // window band height
        var wheelCy = cy + s + wr / 2;
        var underY = cy + s + 2 * wr + DrawUtils.px(2, width);

        for (var i = 0; i < 4; i++) {
            var cx = startX + i * iconSpacing;
            var isActive = (i == view.mCurrentMode);
            var available = isModeAvailable(view, i);

            // Carousel-style pill behind the active icon: same treatment as the
            // station header, marking the row as changeable
            if (isActive && available) {
                var pillPad = DrawUtils.px(3, width);
                var pillTop = cy - s - 3 * s / 5 - DrawUtils.px(2, width);
                var pillBot = underY + DrawUtils.px(2, width);
                dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(cx - s - pillPad, pillTop,
                    2 * (s + pillPad), pillBot - pillTop, DrawUtils.px(3, width));
            }

            var tint;
            if (isActive && available) {
                tint = Graphics.COLOR_WHITE;
            } else if (available) {
                tint = 0xAAAAAA;
            } else {
                tint = 0x333333;
            }
            dc.setColor(tint, Graphics.COLOR_TRANSPARENT);

            if (i == 0) {
                // Train: peaked cab, tall body, split windscreen, wheels
                dc.fillPolygon([[cx - s, cy - s + 1], [cx, cy - s - 3 * s / 5], [cx + s, cy - s + 1]]);
                dc.fillRectangle(cx - s, cy - s, 2 * s, 2 * s);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - s + inset, cy - s + inset, 2 * s - 2 * inset, winH);
                dc.setColor(tint, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - pen / 2, cy - s + inset, pen, winH);
                dc.fillCircle(cx - s / 2, wheelCy, wr);
                dc.fillCircle(cx + s / 2, wheelCy, wr);
            } else if (i == 1) {
                // Bus: wider and lower body, single windscreen band, wide-set wheels
                dc.fillRectangle(cx - s - s / 4, cy - s / 2, 2 * s + s / 2, s + s / 2);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - s - s / 4 + inset, cy - s / 2 + inset,
                    2 * s + s / 2 - 2 * inset, winH);
                dc.setColor(tint, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx - 3 * s / 4, wheelCy, wr);
                dc.fillCircle(cx + 3 * s / 4, wheelCy, wr);
            } else if (i == 2) {
                // Tram: pantograph over a flat-topped body, tucked wheels
                dc.setPenWidth(pen);
                dc.drawLine(cx - s / 2, cy - s, cx + s / 2, cy - s - s / 2);
                dc.drawLine(cx - s / 2, cy - s - s / 2, cx + s / 2, cy - s - s / 2);
                dc.setPenWidth(1);
                dc.fillRectangle(cx - s, cy - s + s / 4, 2 * s, 2 * s - s / 4);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - s + inset, cy - s + s / 4 + inset, 2 * s - 2 * inset, winH);
                dc.setColor(tint, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx - s / 2, cy + s, wr);
                dc.fillCircle(cx + s / 2, cy + s, wr);
            } else {
                // Special (boats, funiculars, cable cars): boat hull, cabin, wave
                dc.fillRectangle(cx - s / 3, cy - s / 2, 2 * s / 3, s / 2);
                dc.fillPolygon([[cx - s, cy], [cx + s, cy],
                    [cx + 3 * s / 5, cy + 3 * s / 5], [cx - 3 * s / 5, cy + 3 * s / 5]]);
                dc.setPenWidth(pen);
                var wy = cy + s;
                dc.drawLine(cx - s, wy, cx - s / 2, wy - s / 4);
                dc.drawLine(cx - s / 2, wy - s / 4, cx, wy);
                dc.drawLine(cx, wy, cx + s / 2, wy - s / 4);
                dc.drawLine(cx + s / 2, wy - s / 4, cx + s, wy);
                dc.setPenWidth(1);
            }

            // Active + available: underline indicator
            if (isActive && available) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - s, underY, 2 * s, DrawUtils.px(2, width));
            }
        }
    }

    function drawGpsIndicator(dc, view, width, height) {
        var maxH = DrawUtils.px(13, width);

        // Position: top-right (same area as former dot)
        var midY = height * 14 / 100;
        var usable = DrawUtils.getUsableWidth(midY, width, height);
        var rightEdge = (width + usable) / 2 - DrawUtils.px(4, width);
        var startX = rightEdge - gpsBarsWidth(width);
        var baseY = midY + maxH / 2;  // bottom of tallest bar
        drawGpsBars(dc, view, startX, baseY, width);
    }

    function gpsBarsWidth(width) {
        return 3 * DrawUtils.px(3, width) + 2 * DrawUtils.px(2, width);
    }

    function drawGpsBars(dc, view, startX, baseY, width) {
        var barW = DrawUtils.px(3, width);
        var gap = DrawUtils.px(2, width);
        var maxH = DrawUtils.px(13, width);

        // Determine fill level and color
        var fillCount;
        var fillColor;
        if (view.mLoadedFromCache || view.mGpsQuality == Position.QUALITY_LAST_KNOWN) {
            fillCount = 3;
            fillColor = 0x888888;
        } else if (view.mGpsQuality == Position.QUALITY_NOT_AVAILABLE) {
            fillCount = 1;
            fillColor = 0xFF0000;
        } else if (view.mGpsQuality == Position.QUALITY_POOR) {
            fillCount = 2;
            fillColor = 0xFFAA00;
        } else {
            fillCount = 3;
            fillColor = 0x00FF00;
        }

        // Draw 3 ascending bars
        for (var i = 0; i < 3; i++) {
            var bx = startX + i * (barW + gap);
            var bh;
            if (i == 0) { bh = DrawUtils.px(5, width); }
            else if (i == 1) { bh = DrawUtils.px(9, width); }
            else { bh = maxH; }
            var by = baseY - bh;

            if (i < fillCount) {
                dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            }
            dc.fillRectangle(bx, by, barW, bh);
        }
    }

    function drawTrainRow(dc, train, y, width, height, highlighted, isFav) {
        var minutesUntil = train["min"];
        var delay = train["delay"];
        var platform = train["plat"];
        var platformChanged = train["platChg"];
        var destination = train["dest"];
        var lineNumber = train["line"];
        var isGone = (minutesUntil < 0);

        // Vertical alignment: FONT_TINY for minutes, FONT_XTINY for rest
        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);
        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var xtinyY = y + (tinyH - xtinyH) / 2;

        // Favourite background tint (subtle gold)
        if (isFav && !highlighted) {
            var rowCenterForBg = y + tinyH / 2;
            var usableBg = DrawUtils.getUsableWidth(rowCenterForBg, width, height);
            var bgX = (width - usableBg) / 2 + 2;
            dc.setColor(0x332800, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, usableBg - 4, tinyH);
        }

        // Highlight background for cursor in selection mode
        if (highlighted) {
            var rowCenterForBg = y + tinyH / 2;
            var usableBg = DrawUtils.getUsableWidth(rowCenterForBg, width, height);
            var bgX = (width - usableBg) / 2 + 2;
            dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, usableBg - 4, tinyH);
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, DrawUtils.px(3, width), tinyH);
        }

        // Fixed column X positions (absolute, so columns align across rows)
        var minRightX = width * 20 / 100;
        var delayX = width * 21 / 100;
        var platX = width * 32 / 100;
        var destX = width * 44 / 100;

        // Right edge for this row on round display (for destination truncation)
        var rowCenterY = y + tinyH / 2;
        var usable = DrawUtils.getUsableWidth(rowCenterY, width, height);
        var rightEdge = (width + usable) / 2 - 4;

        // Departed rows dim to dark grey, but on the highlight fill that becomes
        // unreadable, so the cursor lifts them to light grey
        var goneTint = highlighted ? 0xAAAAAA : 0x666666;

        // Minutes column (right-aligned, FONT_TINY)
        var minText;
        if (isGone) {
            dc.setColor(goneTint, Graphics.COLOR_TRANSPARENT);
            minText = "gone";
        } else if (minutesUntil == 0) {
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            minText = "now";
        } else if (minutesUntil <= 2) {
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            minText = minutesUntil + "'";
        } else {
            dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            minText = minutesUntil + "'";
        }
        dc.drawText(minRightX, y, Graphics.FONT_TINY,
            minText, Graphics.TEXT_JUSTIFY_RIGHT);

        // Delay column (superscript, orange)
        if (delay > 0 && !isGone) {
            dc.setColor(0xFF7700, Graphics.COLOR_TRANSPARENT);
            dc.drawText(delayX, y - 2, Graphics.FONT_XTINY,
                "+" + delay, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Connection ID column (FONT_XTINY)
        if (lineNumber != null && lineNumber.length() > 0) {
            dc.setColor(isGone ? goneTint : 0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(platX, xtinyY, Graphics.FONT_XTINY,
                lineNumber, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Destination column (FONT_XTINY, truncated to fit round edge)
        if (isGone) {
            dc.setColor(goneTint, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        var maxDestW = rightEdge - destX;
        var destText = DrawUtils.truncateToFit(dc, destination, Graphics.FONT_XTINY, maxDestW);
        dc.drawText(destX, xtinyY, Graphics.FONT_XTINY,
            destText, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Focused Mode (State 2) ---

    function drawFocusedMode(dc, view, width, height) {
        var centerX = width / 2;

        if (view.mStationName == null) { return; }

        // Status row centred in the top arc: [GPS bars] HH:MM. Centred placement
        // keeps it clear of the round-display chord on every diameter
        var yTop = height * 3 / 100;
        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var clockInfo = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var timeStr = clockInfo.hour.format("%02d") + ":" + clockInfo.min.format("%02d");
        var clockW = dc.getTextDimensions(timeStr, Graphics.FONT_XTINY)[0];
        var gpsW = gpsBarsWidth(width);
        var groupGap = DrawUtils.px(6, width);
        var groupX = centerX - (gpsW + groupGap + clockW) / 2;
        drawGpsBars(dc, view, groupX, yTop + xtinyH * 3 / 4, width);
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(groupX + gpsW + groupGap, yTop, Graphics.FONT_XTINY,
            timeStr, Graphics.TEXT_JUSTIFY_LEFT);

        // Station name below the status row
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var stationY = yTop + xtinyH;
        var stationMaxW = DrawUtils.getUsableWidth(stationY + 4, width, height) - 10;
        dc.drawText(centerX, stationY, Graphics.FONT_XTINY,
            DrawUtils.truncateToFit(dc, view.mStationName, Graphics.FONT_XTINY, stationMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Destination gets the whole line; the line ID rides on the platform row
        var destY = stationY + xtinyH + DrawUtils.px(2, width);
        var dest = view.mFocusedTrain["dest"];
        var destMaxW = DrawUtils.getUsableWidth(destY, width, height) - 10;
        var destFont = Graphics.FONT_SMALL;
        if (dc.getTextDimensions(dest, destFont)[0] > destMaxW) {
            destFont = Graphics.FONT_TINY;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, destY, destFont,
            DrawUtils.truncateToFit(dc, dest, destFont, destMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Line ID (blue) + platform + departure time on one row, centred as drawn
        var platY = destY + dc.getFontHeight(destFont) + 1;
        var line = view.mFocusedTrain["line"];
        var plat = view.mFocusedTrain["plat"];
        var platChg = view.mFocusedTrain["platChg"];
        var platStr = "";
        if (plat != null && !plat.equals("")) {
            platStr = "Pl. " + plat;
        }
        var depTs = view.mFocusedTrain["depTs"];
        if (depTs != null) {
            var depMoment = new Time.Moment(depTs);
            var depInfo = Time.Gregorian.info(depMoment, Time.FORMAT_SHORT);
            var timeStr2 = depInfo.hour.format("%02d") + ":" + depInfo.min.format("%02d");
            if (platStr.length() > 0) {
                platStr = platStr + "  " + timeStr2;
            } else {
                platStr = timeStr2;
            }
        }
        var lineStr = (line != null && !line.equals("")) ? line : "";
        if (lineStr.length() > 0 && platStr.length() > 0) {
            lineStr = lineStr + "  ";
        }
        if (lineStr.length() > 0 || platStr.length() > 0) {
            var rowMaxW = DrawUtils.getUsableWidth(platY, width, height) - 10;
            var lineW = 0;
            if (lineStr.length() > 0) {
                lineW = dc.getTextDimensions(lineStr, Graphics.FONT_XTINY)[0];
            }
            if (platStr.length() > 0) {
                platStr = DrawUtils.truncateToFit(dc, platStr, Graphics.FONT_XTINY,
                    rowMaxW - lineW);
            }
            var platW = 0;
            if (platStr.length() > 0) {
                platW = dc.getTextDimensions(platStr, Graphics.FONT_XTINY)[0];
            }
            var rowX = centerX - (lineW + platW) / 2;
            if (lineStr.length() > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.drawText(rowX, platY, Graphics.FONT_XTINY,
                    lineStr, Graphics.TEXT_JUSTIFY_LEFT);
            }
            if (platStr.length() > 0) {
                if (platChg) {
                    dc.setColor(0xFF4400, Graphics.COLOR_TRANSPARENT);
                } else {
                    dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                }
                dc.drawText(rowX + lineW, platY, Graphics.FONT_XTINY,
                    platStr, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        // Countdown + delay
        var minY = platY + dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        var minutesUntil = view.getFocusedMinutesUntil();
        var delay = view.mFocusedTrain["delay"];
        if (delay == null) { delay = 0; }

        var minStr;
        if (minutesUntil < -0.5) {
            minStr = "Departed";
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        } else if (minutesUntil < 0.083) {
            minStr = "now";
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
        } else if (minutesUntil < 3.0) {
            var totalSec = (minutesUntil * 60.0).toNumber();
            var m = totalSec / 60;
            var s = totalSec % 60;
            minStr = m + ":" + (s < 10 ? "0" + s : s.toString());
            if (minutesUntil <= 2.0) {
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            }
        } else {
            minStr = minutesUntil.toNumber() + " min";
            dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(centerX, minY, Graphics.FONT_MEDIUM,
            minStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Delay indicator next to departure time
        if (delay > 0 && minutesUntil >= -0.5) {
            var minDims = dc.getTextDimensions(minStr, Graphics.FONT_MEDIUM);
            dc.setColor(0xFF7700, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX + minDims[0] / 2 + 4, minY,
                Graphics.FONT_XTINY, "+" + delay, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Tracking bar
        var barY = minY + dc.getFontHeight(Graphics.FONT_MEDIUM) + DrawUtils.px(2, width);
        drawTrackingBar(dc, view, width, height, barY);

        // Status text
        var statusY = barY + DrawUtils.px(14, width) + DrawUtils.px(4, width);
        var walkMin = view.getWalkMinutes();
        if (walkMin == null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, statusY, Graphics.FONT_TINY,
                "No GPS", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var schedBuf = minutesUntil - walkMin;
            var effectBuf = schedBuf + delay;

            var statusStr;
            if (effectBuf > 0.5) {
                if (effectBuf < 1.5) {
                    var sec = (effectBuf * 60.0).toNumber();
                    statusStr = sec + "s ahead";
                } else {
                    statusStr = effectBuf.toNumber() + " min ahead";
                }
                dc.setColor(0x00FF00, Graphics.COLOR_TRANSPARENT);
            } else if (effectBuf < -0.5) {
                if (effectBuf > -1.5) {
                    var sec = ((-effectBuf) * 60.0).toNumber();
                    statusStr = sec + "s behind";
                } else {
                    statusStr = (-effectBuf).toNumber() + " min behind";
                }
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            } else {
                statusStr = "On time";
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            }

            var statusMaxW = DrawUtils.getUsableWidth(statusY + 8, width, height) - 10;
            var statusFont = Graphics.FONT_TINY;
            dc.drawText(centerX, statusY, statusFont,
                DrawUtils.truncateToFit(dc, statusStr, statusFont, statusMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Walk info at bottom. On short screens the formation needs the room,
        // so the walk line is the first thing to go
        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);
        var walkY = statusY + tinyH + DrawUtils.px(2, width);
        var hasFormation = view.mFormationClasses != null
            && view.mFormationClasses.size() > 0;
        var showWalk = view.mWalkInfo != null;
        if (showWalk && hasFormation) {
            var formTop = height - xtinyH - (xtinyH + 3) - DrawUtils.px(4, width);
            if (walkY + xtinyH > formTop) { showWalk = false; }
        }
        if (showWalk) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var walkMaxW = DrawUtils.getUsableWidth(walkY + 8, width, height) - 10;
            dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                DrawUtils.truncateToFit(dc, view.mWalkInfo, Graphics.FONT_XTINY, walkMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Visual formation diagram, anchored to the bottom edge
        if (hasFormation) {
            var minTop = showWalk ? walkY + xtinyH : statusY + tinyH;
            drawFormation(dc, view, width, height, minTop);
        }

        // Direction arrow (only visible when walking)
        drawDirectionArrow(dc, view, width, height, minY);

        drawButtonHints(dc, view, width, height);

        // Toast overlay (map errors, reminder delivery)
        if (view.mToast != null && view.mToastTick != null) {
            var elapsed = Time.now().value() - view.mToastTick;
            if (elapsed < 3) {
                var toastPad = DrawUtils.px(4, width);
                var toastH = dc.getFontHeight(Graphics.FONT_SMALL) + 2 * toastPad;
                var toastY = height / 2 - toastH / 2;
                var toastW = width * 60 / 100;
                dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(centerX - toastW / 2, toastY, toastW, toastH);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, toastY + toastPad, Graphics.FONT_SMALL,
                    view.mToast, Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                view.mToast = null;
                view.mToastTick = null;
            }
        }
    }

    function drawTrackingBar(dc, view, width, height, passedBarY) {
        var barWidth = width * 60 / 100;
        var halfBar = barWidth / 2;
        var barX = width / 2 - halfBar;
        var barY = passedBarY;
        var barH = DrawUtils.px(14, width);
        var midX = width / 2;

        // Background
        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, barWidth, barH);

        var walkMin = view.getWalkMinutes();
        if (walkMin == null) {
            // No GPS: fully gray bar
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barWidth, barH);
            // Midpoint marker
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            drawBarMidpoint(dc, midX, barY, barH, width);
            return;
        }

        var minutesUntil = view.getFocusedMinutesUntil();
        var delay = view.mFocusedTrain["delay"];
        if (delay == null) { delay = 0; }

        var schedBuf = minutesUntil - walkMin;
        var effectBuf = schedBuf + delay;

        var barScale = 3.0;

        // Clamp to [-1, 1] then scale to pixels
        var schedFrac = GeoMath.clampFloat(schedBuf / barScale, -1.0, 1.0);
        var effectFrac = GeoMath.clampFloat(effectBuf / barScale, -1.0, 1.0);
        var schedPx = (schedFrac * halfBar).toNumber();
        var effectPx = (effectFrac * halfBar).toNumber();

        // MIP-optimized colors: distinct on 64-color palette
        var darkGreen = 0x00FF00;
        var lightGreen = 0x55FF55;
        var darkRed = 0xFF0000;
        var amber = 0xFFAA00;

        // Case 1: Both positive or zero (fully ahead)
        if (schedPx >= 0 && effectPx >= 0) {
            // Dark green: guaranteed buffer (0 to scheduledPx)
            if (schedPx > 0) {
                dc.setColor(darkGreen, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX, barY, schedPx, barH);
            }
            // Light green: delay bonus (scheduledPx to effectivePx)
            if (effectPx > schedPx) {
                dc.setColor(lightGreen, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + schedPx, barY, effectPx - schedPx, barH);
            }
        }
        // Case 3: Both negative (fully behind)
        else if (schedPx <= 0 && effectPx <= 0) {
            // Dark red: irrecoverable deficit (scheduledPx to effectivePx)
            if (schedPx < effectPx) {
                dc.setColor(darkRed, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + schedPx, barY, effectPx - schedPx, barH);
            }
            // Amber: delay recovery zone (effectivePx to 0)
            if (effectPx < 0) {
                dc.setColor(amber, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(midX + effectPx, barY, -effectPx, barH);
            }
        }
        // Case 2: Behind on schedule but saved by delay (schedPx < 0, effectPx > 0)
        else if (schedPx < 0 && effectPx > 0) {
            // Amber: schedule deficit covered by delay
            dc.setColor(amber, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX + schedPx, barY, -schedPx, barH);
            // Light green: delay surplus right of midpoint
            dc.setColor(lightGreen, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX, barY, effectPx, barH);
        }

        // Midpoint marker
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        drawBarMidpoint(dc, midX, barY, barH, width);
    }

    function drawBarMidpoint(dc, midX, barY, barH, width) {
        var w = DrawUtils.px(2, width);
        var over = DrawUtils.px(2, width);
        dc.fillRectangle(midX - w / 2, barY - over, w, barH + 2 * over);
    }

    function drawFormation(dc, view, width, height, minTop) {
        var count = view.mFormationClasses.size();
        if (count == 0) { return; }

        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
        var wagonH = fontH;
        var wagonW = DrawUtils.px(8, width);
        var gap = DrawUtils.px(1, width);
        var locoW = DrawUtils.px(6, width);
        var margin = DrawUtils.px(4, width);

        // Anchor to the bottom edge; reclaim the sector-label row, then give
        // up entirely, before overlapping whatever sits above
        var drawLabels = true;
        var formY = height - wagonH - (fontH + 3) - margin;
        if (formY < minTop + DrawUtils.px(2, width)) {
            drawLabels = false;
            formY = height - wagonH - margin;
            if (formY < minTop + DrawUtils.px(2, width)) { return; }
        }

        // Total width needed
        var totalW = locoW + gap + count * wagonW + (count - 1) * gap;

        // Available width at the formation Y position
        var usable = DrawUtils.getUsableWidth(formY + wagonH / 2, width, height) - 10;

        // Scale down wagon width if formation doesn't fit
        if (totalW > usable) {
            wagonW = (usable - locoW - gap - (count - 1) * gap) / count;
            if (wagonW < DrawUtils.px(4, width)) {
                // Too many wagons even at min size, drop locomotive
                locoW = 0;
                wagonW = (usable - (count - 1) * gap) / count;
                var minW = DrawUtils.px(3, width);
                if (wagonW < minW) { wagonW = minW; }
            }
            totalW = locoW + (locoW > 0 ? gap : 0) + count * wagonW + (count - 1) * gap;
        }

        var startX = (width - totalW) / 2;
        var x = startX;

        // Loco space
        if (locoW > 0) {
            x = x + locoW + gap;
        }

        // Vertical center for text inside wagon
        var textY = formY + (wagonH - fontH) / 2;
        var wagonStartX = x;

        // Draw wagon contents (yellow stripes + numbers)
        for (var i = 0; i < count; i++) {
            var cls = view.mFormationClasses[i];
            var num = view.mFormationNumbers[i];

            // 1st class: yellow stripe at top
            if (cls == 1) {
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, formY + 1, wagonW, 3);
            }

            // Wagon number inside box (only if wide enough)
            if (wagonW >= 7 && num > 0) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + wagonW / 2, textY, Graphics.FONT_XTINY,
                    num.toString(), Graphics.TEXT_JUSTIFY_CENTER);
            }

            x = x + wagonW + gap;
        }

        // Single outline around entire train (loco + wagons)
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        var trainEndX = x - gap;
        // Loco tapered nose on the left
        if (locoW > 0) {
            var noseW = locoW / 3;
            dc.drawLine(startX, formY + wagonH, startX + noseW, formY);
            dc.drawLine(startX + noseW, formY, trainEndX, formY);
        } else {
            dc.drawLine(startX, formY, trainEndX, formY);
        }
        // Right side, bottom, left bottom
        dc.drawLine(trainEndX, formY, trainEndX, formY + wagonH);
        dc.drawLine(trainEndX, formY + wagonH, startX, formY + wagonH);

        // Direction arrow below locomotive
        if (!drawLabels) { return; }
        var lineY = formY + wagonH + 2;
        var sectorTextY = lineY + 1;
        if (locoW > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var arrowX = startX + locoW / 2;
            dc.drawText(arrowX, sectorTextY, Graphics.FONT_XTINY,
                "<", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Sector labels below wagons
        if (view.mFormationSectors == null) { return; }

        // Group consecutive wagons by sector
        var sectorStart = 0;
        while (sectorStart < count) {
            var sector = view.mFormationSectors[sectorStart];
            var sectorEnd = sectorStart + 1;
            while (sectorEnd < count && view.mFormationSectors[sectorEnd].equals(sector)) {
                sectorEnd = sectorEnd + 1;
            }

            if (!sector.equals("")) {
                var gx1 = wagonStartX + sectorStart * (wagonW + gap);
                var gx2 = wagonStartX + sectorEnd * (wagonW + gap) - gap;
                var gmid = (gx1 + gx2) / 2;

                // Horizontal line spanning sector group
                dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx1, lineY, gx2, lineY);

                // Sector letter centered below line
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(gmid, sectorTextY, Graphics.FONT_XTINY,
                    sector, Graphics.TEXT_JUSTIFY_CENTER);
            }

            sectorStart = sectorEnd;
        }
    }

    function drawDirectionArrow(dc, view, width, height, countdownY) {
        // Position to the left of the countdown text, vertically centered
        var minFontH = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var arrowCx = width * 3 / 14;
        var arrowCy = countdownY + minFontH / 2;
        var r = DrawUtils.pxF(14, width);

        var hasGps = view.mHeading != null && view.mStationLat != null
            && view.mStationLon != null && view.mLocationInfo != null
            && view.mLocationInfo.position != null;

        var angle = 0.0;  // default: pointing up (north)
        if (hasGps) {
            var coords = view.mLocationInfo.position.toDegrees();
            var bearing = GeoMath.calculateBearing(coords[0], coords[1], view.mStationLat, view.mStationLon);
            angle = bearing - view.mHeading;
        }

        var cosA = Math.cos(angle).toFloat();
        var sinA = Math.sin(angle).toFloat();

        // Kite points: tip (0,-r), leftWing (-0.4r, 0.3r), rightWing (0.4r, 0.3r), tail (0, 0.15r)
        var tipX = (arrowCx + r * sinA).toNumber();
        var tipY = (arrowCy - r * cosA).toNumber();
        var lwX = (arrowCx - 0.4 * r * cosA - 0.3 * r * sinA).toNumber();
        var lwY = (arrowCy - 0.4 * r * sinA + 0.3 * r * cosA).toNumber();
        var rwX = (arrowCx + 0.4 * r * cosA - 0.3 * r * sinA).toNumber();
        var rwY = (arrowCy + 0.4 * r * sinA + 0.3 * r * cosA).toNumber();
        var tailX = (arrowCx - 0.15 * r * sinA).toNumber();
        var tailY = (arrowCy + 0.15 * r * cosA).toNumber();

        // Upper triangle (tip)
        dc.setColor(hasGps ? 0x55AAFF : 0x555555, Graphics.COLOR_TRANSPARENT);
        var tipPts = new [3];
        tipPts[0] = [tipX, tipY];
        tipPts[1] = [lwX, lwY];
        tipPts[2] = [rwX, rwY];
        dc.fillPolygon(tipPts);

        // Lower triangle (body)
        dc.setColor(hasGps ? Graphics.COLOR_WHITE : 0x444444, Graphics.COLOR_TRANSPARENT);
        var bodyPts = new [3];
        bodyPts[0] = [lwX, lwY];
        bodyPts[1] = [tailX, tailY];
        bodyPts[2] = [rwX, rwY];
        dc.fillPolygon(bodyPts);
    }
}
