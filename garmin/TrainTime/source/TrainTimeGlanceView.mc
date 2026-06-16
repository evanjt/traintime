using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Math;

// Single glance tile: the nearest pinned station, by cached location only.
// Deliberately self-contained (Toybox + inline Storage read + flat-earth
// distance) so it stays well under the ~32 kB glance budget and never makes a
// network request. Tapping it launches the app, which lands on that station
// once GPS resolves (pinned stations are reordered to the front).
(:glance)
class TrainTimeGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Best-available location: cached GPS fix, else the app's last saved
        // coordinate. Garmin returns garbage (0,0 / 180,180) when no fix yet,
        // so reject QUALITY_NOT_AVAILABLE and out-of-range coordinates.
        var lat = null;
        var lon = null;
        var info = Position.getInfo();
        if (info != null && info.position != null
                && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            var c = info.position.toDegrees();
            if (c[0] <= 90.0 && c[0] >= -90.0 && c[1] <= 180.0 && c[1] >= -180.0) {
                lat = c[0];
                lon = c[1];
            }
        }
        if (lat == null) {
            var sLat = Storage.getValue("lastLat");
            var sLon = Storage.getValue("lastLon");
            if (sLat != null && sLon != null) {
                lat = sLat;
                lon = sLon;
            }
        }

        var line = "TrainTime";

        var pinned = Storage.getValue("myStations");
        if (pinned == null || !(pinned instanceof Lang.Array) || pinned.size() == 0) {
            line = "Pin a station";
        } else if (lat != null) {
            var best = null;
            var bestDist = null;
            for (var i = 0; i < pinned.size(); i++) {
                var s = pinned[i] as Lang.Dictionary;
                if (s == null || s["lat"] == null || s["lon"] == null) { continue; }
                var dLat = (s["lat"] - lat) * 111000.0;
                var dLon = (s["lon"] - lon) * 75700.0;
                var d = Math.sqrt(dLat * dLat + dLon * dLon);
                if (bestDist == null || d < bestDist) {
                    bestDist = d;
                    best = s;
                }
            }
            if (best != null) {
                var distStr = "";
                if (bestDist >= 1000) {
                    distStr = " · " + (bestDist / 1000.0).format("%.1f") + " km";
                } else {
                    distStr = " · " + bestDist.toNumber() + " m";
                }
                var nm = (best["name"] != null) ? best["name"] : "Station";
                line = nm + distStr;
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            0,
            dc.getHeight() / 2,
            Graphics.FONT_GLANCE,
            line,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
