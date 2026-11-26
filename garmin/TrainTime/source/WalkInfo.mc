using Toybox.Lang;

// The walk to a station as the board writes it: time at 83 m a minute, then
// the distance in metres.
module WalkInfo {

    function time(distanceMeters) {
        var walkMinutes = (distanceMeters.toNumber() / 83.0).toNumber();
        if (walkMinutes < 1) {
            return Txt.t(Rez.Strings.WalkUnder1);
        }
        return Lang.format(Txt.t(Rez.Strings.MinutesFmt), [walkMinutes]);
    }

    function full(distanceMeters) {
        return Lang.format(Txt.t(Rez.Strings.WalkInfoFmt), [time(distanceMeters), distanceMeters.toNumber()]);
    }

    // Without the word, for narrow places
    function brief(distanceMeters) {
        return Lang.format(Txt.t(Rez.Strings.WalkInfoShortFmt), [time(distanceMeters), distanceMeters.toNumber()]);
    }
}
