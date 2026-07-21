using Toybox.WatchUi;

// Cached access to string resources. loadResource allocates a fresh string on
// every call and the render loop asks several times a second, so answers come
// from this table after the first load. Language never changes mid-session.
module Txt {

    var mCache = {};

    function t(rez) {
        var s = mCache[rez];
        if (s == null) {
            s = WatchUi.loadResource(rez);
            mCache[rez] = s;
        }
        return s;
    }
}
