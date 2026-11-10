using Toybox.Lang;

// Where a departure stands against the clock, measured from its effective time
// (schedule plus delay). A late train is still coming after its scheduled
// minute, and OJP keeps listing it until the estimate passes, so every surface
// must too. Pure, so the rules are testable without a view.
module DepartureLogic {
    // Board row: gone once a full minute past the effective time.
    function isGone(minutesUntil as Lang.Number, delay as Lang.Number?) as Lang.Boolean {
        return minutesUntil + nz(delay) < 0;
    }

    // The API sends the flag only on a cancelled row, and the parsed row keeps
    // the key only when set, to spare memory on small watches.
    function isCancelled(row as Lang.Dictionary) as Lang.Boolean {
        return row["cnc"] == true;
    }

    // A row that can be tracked: still to come and actually running.
    function isSelectable(row as Lang.Dictionary) as Lang.Boolean {
        return !isGone(row["min"] as Lang.Number, row["delay"] as Lang.Number?) && !isCancelled(row);
    }

    // Board row still worth matching against the tracked departure.
    function isMatchable(minutesUntil as Lang.Number, delay as Lang.Number?) as Lang.Boolean {
        return minutesUntil + nz(delay) >= -1;
    }

    // Tracking countdown: "Departed" half a minute past the effective time.
    function hasDeparted(minutesUntil as Lang.Float, delay as Lang.Number?) as Lang.Boolean {
        return minutesUntil + nz(delay) < -0.5;
    }

    function nz(delay as Lang.Number?) as Lang.Number {
        return delay == null ? 0 : delay;
    }
}
