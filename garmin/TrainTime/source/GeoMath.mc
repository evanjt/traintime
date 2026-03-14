using Toybox.Math;

module GeoMath {

    function calculateDistance(lat1, lon1, lat2, lon2) {
        var dLat = (lat2 - lat1) * 111000;
        var dLon = (lon2 - lon1) * 75700; // ~111000 * cos(47°)
        return Math.sqrt(dLat * dLat + dLon * dLon).toNumber();
    }

    // Bearing from point 1 to point 2 in radians (clockwise from north)
    function calculateBearing(lat1, lon1, lat2, lon2) {
        var dLon = (lon2 - lon1) * Math.PI / 180.0;
        var lat1R = lat1 * Math.PI / 180.0;
        var lat2R = lat2 * Math.PI / 180.0;
        var y = Math.sin(dLon) * Math.cos(lat2R);
        var x = Math.cos(lat1R) * Math.sin(lat2R)
              - Math.sin(lat1R) * Math.cos(lat2R) * Math.cos(dLon);
        return Math.atan2(y, x);
    }

    function clampFloat(val, minVal, maxVal) {
        if (val < minVal) { return minVal; }
        if (val > maxVal) { return maxVal; }
        return val;
    }
}
