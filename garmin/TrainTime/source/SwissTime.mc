// Swiss civil time from a Unix timestamp. Monkey C has no timezone database
// and the watch's own zone is whatever its owner set, so a feed keyed by the
// Swiss calendar date gets its date from the rule here. Pure integer maths,
// good from 1970 to the end of 32-bit time.
module SwissTime {

    const DAY = 86400;

    // Seconds east of UTC. Summer time runs from 01:00 UTC on the last Sunday
    // of March to 01:00 UTC on the last Sunday of October.
    function utcOffset(ts) {
        var year = civil(ts / DAY)[0];
        var start = lastSunday(year, 3) * DAY + 3600;
        var end = lastSunday(year, 10) * DAY + 3600;
        return (ts >= start && ts < end) ? 7200 : 3600;
    }

    // "YYYY-MM-DD" on the Swiss calendar
    function date(ts) {
        var c = civil((ts + utcOffset(ts)) / DAY);
        return c[0].format("%04d") + "-" + c[1].format("%02d") + "-" + c[2].format("%02d");
    }

    // Day number of the last Sunday of a 31-day month. Day 0 was a Thursday.
    function lastSunday(year, month) {
        var last = dayNumber(year, month, 31);
        return last - (last + 4) % 7;
    }

    // Days since 1970-01-01 of a calendar date, counting years from 1 March
    // so the leap day falls at the end.
    function dayNumber(year, month, day) {
        var y = month <= 2 ? year - 1 : year;
        var era = y / 400;
        var yoe = y - era * 400;
        var doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
        var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    // [year, month, day] of a day number, the inverse of dayNumber
    function civil(days) {
        var z = days + 719468;
        var era = z / 146097;
        var doe = z - era * 146097;
        var yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        var doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        var mp = (5 * doy + 2) / 153;
        var day = doy - (153 * mp + 2) / 5 + 1;
        var month = mp < 10 ? mp + 3 : mp - 9;
        var year = yoe + era * 400;
        return [month <= 2 ? year + 1 : year, month, day];
    }
}
