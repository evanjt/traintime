using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Position;
using Toybox.Time;

module Renderer {

    function render(dc, view) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        view.mMaxVisibleTrains = (height < 240) ? 3 : 4;

        // GPS quality indicator
        drawGpsIndicator(dc, view, width, height);

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

            // Walking info line / station indicator
            var walkY = height * 13 / 100;
            if (view.mAppState == 1 && view.mCursorIndex == -1) {
                // Highlighted station indicator (shows walk info + counter)
                var walkTextH = dc.getFontHeight(Graphics.FONT_XTINY);
                var rowCenterForBg = walkY + walkTextH / 2;
                var usableBg = DrawUtils.getUsableWidth(rowCenterForBg, width, height);
                var bgX = (width - usableBg) / 2 + 2;
                dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bgX, walkY, usableBg - 4, walkTextH);
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bgX, walkY, 3, walkTextH);
                var siText = view.mWalkInfo != null ? view.mWalkInfo : ((view.mStationIndex + 1) + "/" + ((view.mStations != null) ? view.mStations.size() : 1));
                var walkMaxW = usableBg - 10;
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    DrawUtils.truncateToFit(dc, siText, Graphics.FONT_XTINY, walkMaxW),
                    Graphics.TEXT_JUSTIFY_CENTER);
            } else if (view.mWalkInfo != null) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                var walkMaxW = DrawUtils.getUsableWidth(walkY + 8, width, height) - 10;
                var walkText = DrawUtils.truncateToFit(dc, view.mWalkInfo, Graphics.FONT_XTINY, walkMaxW);
                dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                    walkText, Graphics.TEXT_JUSTIFY_CENTER);
            }

            // Station name
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var stationY = height * 22 / 100;
            var stationMaxW = DrawUtils.getUsableWidth(stationY + 12, width, height) - 10;
            var stationText = view.mStationName.toUpper();
            var stationFont = Graphics.FONT_MEDIUM;
            var dims = dc.getTextDimensions(stationText, stationFont);
            if (dims[0] > stationMaxW) {
                stationFont = Graphics.FONT_SMALL;
                dims = dc.getTextDimensions(stationText, stationFont);
                if (dims[0] > stationMaxW) {
                    stationFont = Graphics.FONT_TINY;
                    stationText = DrawUtils.truncateToFit(dc, stationText, stationFont, stationMaxW);
                }
            }
            dc.drawText(centerX, stationY, stationFont,
                stationText, Graphics.TEXT_JUSTIFY_CENTER);

            if (view.mTrainData != null && view.mTrainData.size() > 0) {
                // Train rows
                var maxTrains = 4;
                if (height < 240) {
                    maxTrains = 3;
                }
                var startY = height * 36 / 100;
                var rowSpacing = height * 14 / 100;

                var startIdx = (view.mAppState == 1) ? view.mScrollOffset : 0;
                var endIdx = view.mTrainData.size();
                if (endIdx > startIdx + maxTrains) {
                    endIdx = startIdx + maxTrains;
                }
                for (var i = startIdx; i < endIdx; i++) {
                    var row = i - startIdx;
                    var highlighted = (view.mAppState == 1 && i == view.mCursorIndex);
                    drawTrainRow(dc, view.mTrainData[i],
                        startY + row * rowSpacing, width, height, highlighted);
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
            // No station yet — show status or loading indicator
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var loadMsg = view.mRequestInFlight ? "Loading..." : view.mStatus;
            dc.drawText(centerX, height * 45 / 100, Graphics.FONT_SMALL,
                loadMsg, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Contextual button hint at bottom
        if (view.mStationName != null && (view.mAppState == 1 || (view.mTrainData != null && view.mTrainData.size() > 0))) {
            var hintY = height * 92 / 100;
            var hintMaxW = DrawUtils.getUsableWidth(hintY + 6, width, height) - 10;
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            var hint;
            if (view.mAppState == 0) {
                hint = "Press START";
            } else if (view.mAppState == 1) {
                if (view.mCursorIndex == -1) {
                    hint = "START=Next  DOWN";
                } else {
                    hint = "START=OK  BACK";
                }
            } else {
                hint = (WatchUi has :MapTrackView && view.mStationLat != null && view.mStationLon != null) ? "START=Map" : "";
            }
            if (!hint.equals("")) {
                dc.drawText(centerX, hintY, Graphics.FONT_XTINY,
                    DrawUtils.truncateToFit(dc, hint, Graphics.FONT_XTINY, hintMaxW),
                    Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
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
        var iconSpacing = 36;
        var totalWidth = 3 * iconSpacing;  // 4 icons, 3 gaps
        var startX = width / 2 - totalWidth / 2;

        for (var i = 0; i < 4; i++) {
            var cx = startX + i * iconSpacing;
            var isActive = (i == view.mCurrentMode);
            var available = isModeAvailable(view, i);

            if (isActive && available) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            } else if (available) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            }

            if (i == 0) {
                // Train: rectangle body + peaked roof + 2 wheels
                dc.fillRectangle(cx - 4, cy - 1, 8, 7);
                dc.fillPolygon([[cx - 4, cy - 1], [cx, cy - 4], [cx + 4, cy - 1]]);
                dc.fillCircle(cx - 3, cy + 8, 2);
                dc.fillCircle(cx + 3, cy + 8, 2);
            } else if (i == 1) {
                // Bus: wider rectangle body + 2 wheels
                dc.fillRectangle(cx - 5, cy, 10, 6);
                dc.fillCircle(cx - 3, cy + 8, 2);
                dc.fillCircle(cx + 3, cy + 8, 2);
            } else if (i == 2) {
                // Tram: rectangle body + pantograph + 2 wheels
                dc.fillRectangle(cx - 4, cy - 1, 8, 7);
                dc.setPenWidth(1);
                dc.drawLine(cx, cy - 1, cx, cy - 6);
                dc.drawLine(cx - 3, cy - 6, cx + 3, cy - 6);
                dc.fillCircle(cx - 3, cy + 8, 2);
                dc.fillCircle(cx + 3, cy + 8, 2);
            } else if (i == 3) {
                // Special (boats/funiculars/cable cars): wave icon
                dc.setPenWidth(2);
                dc.drawLine(cx - 5, cy, cx - 3, cy - 4);
                dc.drawLine(cx - 3, cy - 4, cx, cy);
                dc.drawLine(cx, cy, cx + 3, cy + 4);
                dc.drawLine(cx + 3, cy + 4, cx + 5, cy);
                dc.drawLine(cx - 5, cy + 5, cx - 3, cy + 1);
                dc.drawLine(cx - 3, cy + 1, cx, cy + 5);
                dc.drawLine(cx, cy + 5, cx + 3, cy + 9);
                dc.drawLine(cx + 3, cy + 9, cx + 5, cy + 5);
            }

            // Active + available: underline indicator
            if (isActive && available) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - 5, cy + 12, 10, 2);
            }
        }
    }

    function drawGpsIndicator(dc, view, width, height) {
        var barW = 3;
        var gap = 2;
        var maxH = 13;
        var totalW = 3 * barW + 2 * gap;  // 15px

        // Position: top-right (same area as former dot)
        var midY = height * 14 / 100;
        var usable = DrawUtils.getUsableWidth(midY, width, height);
        var rightEdge = (width + usable) / 2 - 4;
        var startX = rightEdge - totalW;
        var baseY = midY + maxH / 2;  // bottom of tallest bar

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
            if (i == 0) { bh = 5; }
            else if (i == 1) { bh = 9; }
            else { bh = 13; }
            var by = baseY - bh;

            if (i < fillCount) {
                dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            }
            dc.fillRectangle(bx, by, barW, bh);
        }
    }

    function drawTrainRow(dc, train, y, width, height, highlighted) {
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

        // Highlight background for cursor in selection mode
        if (highlighted) {
            var rowCenterForBg = y + tinyH / 2;
            var usableBg = DrawUtils.getUsableWidth(rowCenterForBg, width, height);
            var bgX = (width - usableBg) / 2 + 2;
            dc.setColor(0x004488, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, usableBg - 4, tinyH);
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bgX, y, 3, tinyH);
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

        // Minutes column (right-aligned, FONT_TINY)
        var minText;
        if (isGone) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
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
            dc.setColor(isGone ? 0x666666 : 0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(platX, xtinyY, Graphics.FONT_XTINY,
                lineNumber, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Destination column (FONT_XTINY, truncated to fit round edge)
        if (isGone) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
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

        // Station name (small, secondary)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var stationY = height * 15 / 100;
        var stationMaxW = DrawUtils.getUsableWidth(stationY + 8, width, height) - 10;
        dc.drawText(centerX, stationY, Graphics.FONT_XTINY,
            DrawUtils.truncateToFit(dc, view.mStationName, Graphics.FONT_XTINY, stationMaxW),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Current wall-clock time (positioned within usable width on round display)
        var clockInfo = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var timeStr = clockInfo.hour.format("%02d") + ":" + clockInfo.min.format("%02d");
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        var clockUsable = DrawUtils.getUsableWidth(stationY + 4, width, height);
        var clockRightEdge = (width + clockUsable) / 2 - 4;
        dc.drawText(clockRightEdge, stationY, Graphics.FONT_XTINY,
            timeStr, Graphics.TEXT_JUSTIFY_RIGHT);

        // Line + Destination + platform (auto-downsize, highlight platform change)
        var destY = height * 26 / 100;
        var line = view.mFocusedTrain["line"];
        var destStr = "";
        if (line != null && !line.equals("")) {
            destStr = line + " ";
        }
        destStr = destStr + view.mFocusedTrain["dest"];
        var plat = view.mFocusedTrain["plat"];
        var platChg = view.mFocusedTrain["platChg"];
        var destMaxW = DrawUtils.getUsableWidth(destY + 10, width, height) - 10;
        var destFont = Graphics.FONT_SMALL;
        if (plat != null && !plat.equals("")) {
            destStr = destStr + "  P" + plat;
        }
        var destDims = dc.getTextDimensions(destStr, destFont);
        if (destDims[0] > destMaxW) {
            destFont = Graphics.FONT_TINY;
            destStr = DrawUtils.truncateToFit(dc, destStr, destFont, destMaxW);
        }
        if (platChg) {
            dc.setColor(0xFF4400, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(centerX, destY, destFont,
            destStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Departure time + delay
        var minY = height * 40 / 100;
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
        drawTrackingBar(dc, view, width, height);

        // Status text
        var statusY = height * 63 / 100;
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

        // Walk info at bottom
        if (view.mWalkInfo != null) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var walkY = height * 76 / 100;
            var walkMaxW = DrawUtils.getUsableWidth(walkY + 8, width, height) - 10;
            dc.drawText(centerX, walkY, Graphics.FONT_XTINY,
                DrawUtils.truncateToFit(dc, view.mWalkInfo, Graphics.FONT_XTINY, walkMaxW),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Visual formation diagram
        if (view.mFormationClasses != null) {
            drawFormation(dc, view, width, height);
        }

        // Direction arrow (only visible when walking)
        drawDirectionArrow(dc, view, width, height);
    }

    function drawTrackingBar(dc, view, width, height) {
        var barWidth = width * 60 / 100;
        var halfBar = barWidth / 2;
        var barX = width / 2 - halfBar;
        var barY = height * 54 / 100;
        var barH = 14;
        var midX = width / 2;

        // Background
        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, barY, barWidth, barH);

        var walkMin = view.getWalkMinutes();
        if (walkMin == null) {
            // No GPS — fully gray bar
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barWidth, barH);
            // Midpoint marker
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
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

        // MIP-optimized colors — distinct on 64-color palette
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
        dc.fillRectangle(midX - 1, barY - 2, 2, barH + 4);
    }

    function drawFormation(dc, view, width, height) {
        var count = view.mFormationClasses.size();
        if (count == 0) { return; }

        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
        var wagonH = fontH - 2;  // tall enough to contain FONT_XTINY
        var wagonW = 10;
        var gap = 1;
        var locoW = 12;

        // Total width needed
        var totalW = locoW + gap + count * wagonW + (count - 1) * gap;

        // Available width at the formation Y position
        var formY = height * 82 / 100;
        var usable = DrawUtils.getUsableWidth(formY + wagonH / 2, width, height) - 10;

        // Scale down wagon width if formation doesn't fit
        if (totalW > usable) {
            wagonW = (usable - locoW - gap - (count - 1) * gap) / count;
            if (wagonW < 4) {
                // Too many wagons even at min size — drop locomotive
                locoW = 0;
                wagonW = (usable - (count - 1) * gap) / count;
                if (wagonW < 3) { wagonW = 3; }
            }
            totalW = locoW + (locoW > 0 ? gap : 0) + count * wagonW + (count - 1) * gap;
        }

        var startX = (width - totalW) / 2;
        var x = startX;

        // Draw locomotive
        if (locoW > 0) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            var locoPts = new [4];
            locoPts[0] = [x, formY + wagonH];
            locoPts[1] = [x + 2, formY];
            locoPts[2] = [x + locoW, formY];
            locoPts[3] = [x + locoW, formY + wagonH];
            dc.fillPolygon(locoPts);
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, formY + wagonH, x + 2, formY);
            dc.drawLine(x + 2, formY, x + locoW, formY);
            x = x + locoW + gap;
        }

        // Vertical center for text inside wagon
        var textY = formY + (wagonH - fontH) / 2;

        // Draw wagons
        for (var i = 0; i < count; i++) {
            var cls = view.mFormationClasses[i];
            var num = view.mFormationNumbers[i];

            // Wagon fill
            dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, formY, wagonW, wagonH);

            // Border
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(x, formY, wagonW, wagonH);

            // 1st class: yellow stripe at top
            if (cls == 1) {
                dc.setColor(0xFFBB00, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + 1, formY, wagonW - 2, 2);
            }

            // Wagon number inside box (only if wide enough)
            if (wagonW >= 8 && num > 0) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + wagonW / 2, textY, Graphics.FONT_XTINY,
                    num.toString(), Graphics.TEXT_JUSTIFY_CENTER);
            }

            x = x + wagonW + gap;
        }

        // Sector labels below wagons
        var lineY = formY + wagonH + 2;
        var sectorTextY = lineY + 1;
        var wagonStartX = startX + (locoW > 0 ? locoW + gap : 0);

        // Group consecutive wagons by sector
        var groupStart = 0;
        while (groupStart < count) {
            var sector = view.mFormationSectors[groupStart];
            var groupEnd = groupStart + 1;
            while (groupEnd < count && view.mFormationSectors[groupEnd].equals(sector)) {
                groupEnd = groupEnd + 1;
            }

            if (!sector.equals("")) {
                var gx1 = wagonStartX + groupStart * (wagonW + gap);
                var gx2 = wagonStartX + groupEnd * (wagonW + gap) - gap;
                var gmid = (gx1 + gx2) / 2;

                // Horizontal line spanning sector group
                dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx1, lineY, gx2, lineY);

                // Sector letter centered below line
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(gmid, sectorTextY, Graphics.FONT_XTINY,
                    sector, Graphics.TEXT_JUSTIFY_CENTER);
            }

            groupStart = groupEnd;
        }
    }

    function drawDirectionArrow(dc, view, width, height) {
        if (view.mHeading == null || view.mStationLat == null || view.mStationLon == null) {
            return;
        }
        if (view.mLocationInfo == null || view.mLocationInfo.position == null) {
            return;
        }

        var coords = view.mLocationInfo.position.toDegrees();
        var bearing = GeoMath.calculateBearing(coords[0], coords[1], view.mStationLat, view.mStationLon);
        var angle = bearing - view.mHeading;

        var arrowCx = width / 2;
        var arrowCy = height * 89 / 100;
        var r = 16.0;

        var cosA = Math.cos(angle).toFloat();
        var sinA = Math.sin(angle).toFloat();

        // Kite points: tip (0,-r), leftWing (-0.4r, 0.3r), rightWing (0.4r, 0.3r), tail (0, 0.15r)
        // Rotation: x' = px*cosA - py*sinA, y' = px*sinA + py*cosA
        var tipX = (arrowCx + r * sinA).toNumber();
        var tipY = (arrowCy - r * cosA).toNumber();
        var lwX = (arrowCx - 0.4 * r * cosA - 0.3 * r * sinA).toNumber();
        var lwY = (arrowCy - 0.4 * r * sinA + 0.3 * r * cosA).toNumber();
        var rwX = (arrowCx + 0.4 * r * cosA - 0.3 * r * sinA).toNumber();
        var rwY = (arrowCy + 0.4 * r * sinA + 0.3 * r * cosA).toNumber();
        var tailX = (arrowCx - 0.15 * r * sinA).toNumber();
        var tailY = (arrowCy + 0.15 * r * cosA).toNumber();

        // Upper triangle (tip) — blue
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        var tipPts = new [3];
        tipPts[0] = [tipX, tipY];
        tipPts[1] = [lwX, lwY];
        tipPts[2] = [rwX, rwY];
        dc.fillPolygon(tipPts);

        // Lower triangle (body) — white
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var bodyPts = new [3];
        bodyPts[0] = [lwX, lwY];
        bodyPts[1] = [tailX, tailY];
        bodyPts[2] = [rwX, rwY];
        dc.fillPolygon(bodyPts);
    }
}
