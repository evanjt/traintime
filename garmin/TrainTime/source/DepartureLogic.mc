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
