using Toybox.Communications;
using Toybox.Test;

// The date a formation lookup asks for, and what a 503 on that call does to
// the host list. Built only with `monkeyc -t`.

// Scenario: a train leaving at 00:20 Swiss time is tracked at 23:50 the evening before.
// Expected behaviour: the lookup asks for the departure's date, not the evening's.
(:test)
function testFormationDateIsTheDeparturesDate(logger) {
    var lookedUpAt = 1795647000;
    var departsAt = 1795648800;
    return ApiHandler.formationDate(departsAt, lookedUpAt).equals("2026-11-26");
}

(:test)
function testFormationDateWithoutDepartureIsToday(logger) {
    return ApiHandler.formationDate(null, 1795647000).equals("2026-11-25");
}

// 22:30 UTC is 23:30 in winter and 00:30 the next day in summer.
(:test)
function testSwissDateFollowsSummerTime(logger) {
    return SwissTime.date(1768516200).equals("2026-01-15")
        && SwissTime.date(1782945000).equals("2026-07-02");
}

// Summer time starts on 29 March 2026 and ends on 25 October 2026, at 01:00 UTC.
(:test)
function testSwissOffsetChangesOnLastSundays(logger) {
    return SwissTime.utcOffset(1774745999) == 3600
        && SwissTime.utcOffset(1774746000) == 7200
        && SwissTime.utcOffset(1792889999) == 7200
        && SwissTime.utcOffset(1792890000) == 3600
        && SwissTime.date(1774737000).equals("2026-03-28")
        && SwissTime.date(1774823400).equals("2026-03-30")
        && SwissTime.date(1792881000).equals("2026-10-25")
        && SwissTime.date(1792967400).equals("2026-10-25");
}

(:test)
function testSwissDateCrossesLeapDayAndNewYear(logger) {
    return SwissTime.date(1835393400).equals("2028-02-29")
        && SwissTime.date(1835479800).equals("2028-03-01")
        && SwissTime.date(1798759800).equals("2027-01-01");
}

(:test)
class FormationViewStub {
    var cleared = 0;

    function clearFormation() {
        cleared = cleared + 1;
    }
}

(:test)
function testFormation503IsNotAHostFailure(logger) {
    return !ApiHandler.shouldFailoverFor(ApiHandler.KIND_FORMATION, 503, null)
        && ApiHandler.shouldFailoverFor(ApiHandler.KIND_FORMATION, 500, null)
        && ApiHandler.shouldFailoverFor(ApiHandler.KIND_FORMATION, 429, null)
        && ApiHandler.shouldFailoverFor(ApiHandler.KIND_FORMATION, Communications.NETWORK_REQUEST_TIMED_OUT, null)
        && ApiHandler.shouldFailoverFor(ApiHandler.KIND_DEPARTURES, 503, null)
        && ApiHandler.shouldFailoverFor(ApiHandler.KIND_STATIONS, 503, null);
}

// Scenario: the formation call answers 503 on the primary host.
// Expected behaviour: the reply is taken as no car data, on the first attempt,
// and the primary stays the preferred host.
(:test)
function testFormation503LeavesHostHealthy(logger) {
    ApiHandler.resetHostState();
    var view = new FormationViewStub();
    var a = new ApiAttempt(view, ApiHandler.KIND_FORMATION, "/v1/formation?train=1", ApiHandler.HOSTS, 0);
    ApiHandler.mPendingFormation = a;
    ApiHandler.onResponse(a, 503, null);
    var ok = ApiHandler.mPrimaryFailedAt == null
        && ApiHandler.mActiveHost == 0
        && ApiHandler.mPendingFormation == null
        && a.attempt == 0
        && view.cleared == 1;
    ApiHandler.mPendingFormation = null;
    ApiHandler.resetHostState();
    return ok;
}
