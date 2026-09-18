using Toybox.Test;
using Toybox.Communications;

// Host failover rules for the API handler. Built only with `monkeyc -t`.

(:test)
function testFailoverOnDeadHostCodes(logger) {
    return ApiHandler.shouldFailover(500)
        && ApiHandler.shouldFailover(502)
        && ApiHandler.shouldFailover(503)
        && ApiHandler.shouldFailover(429)
        && ApiHandler.shouldFailover(Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE)
        && ApiHandler.shouldFailover(Communications.NETWORK_REQUEST_TIMED_OUT)
        && ApiHandler.shouldFailover(Communications.REQUEST_CONNECTION_DROPPED)
        && ApiHandler.shouldFailover(Communications.BLE_ERROR)
        && ApiHandler.shouldFailover(Communications.BLE_HOST_TIMEOUT)
        && ApiHandler.shouldFailover(Communications.BLE_SERVER_TIMEOUT);
}

(:test)
function testNoFailoverOnOwnErrorsOrCancel(logger) {
    return !ApiHandler.shouldFailover(200)
        && !ApiHandler.shouldFailover(400)
        && !ApiHandler.shouldFailover(401)
        && !ApiHandler.shouldFailover(404)
        && !ApiHandler.shouldFailover(Communications.BLE_CONNECTION_UNAVAILABLE)
        && !ApiHandler.shouldFailover(Communications.NETWORK_RESPONSE_TOO_LARGE)
        && !ApiHandler.shouldFailover(Communications.NETWORK_RESPONSE_OUT_OF_MEMORY)
        && !ApiHandler.shouldFailover(Communications.INVALID_HTTP_HEADER_FIELDS_IN_REQUEST)
        && !ApiHandler.shouldFailover(Communications.INVALID_HTTP_BODY_IN_REQUEST)
        && !ApiHandler.shouldFailover(Communications.INVALID_HTTP_METHOD_IN_REQUEST)
        && !ApiHandler.shouldFailover(Communications.REQUEST_CANCELLED)
        && !ApiHandler.shouldFailover(Communications.BLE_REQUEST_CANCELLED);
}

(:test)
function testFailedPrimaryIsSkippedUntilReprobe(logger) {
    ApiHandler.resetHostState();
    var ok = ApiHandler.preferredHost(1000) == 0;
    ApiHandler.recordHostFailure(0, 1000);
    ok = ok && ApiHandler.preferredHost(1001) == 1;
    ok = ok && ApiHandler.preferredHost(1299) == 1;
    ok = ok && ApiHandler.preferredHost(1300) == 0;
    ok = ok && ApiHandler.preferredHost(1301) == 0;
    ApiHandler.resetHostState();
    return ok;
}

(:test)
function testSecondaryFailureMovesToThirdHost(logger) {
    ApiHandler.resetHostState();
    ApiHandler.recordHostFailure(0, 1000);
    ApiHandler.recordHostFailure(1, 1005);
    var ok = ApiHandler.preferredHost(1010) == 2;
    ApiHandler.recordHostSuccess(2);
    ok = ok && ApiHandler.preferredHost(1020) == 2;
    ApiHandler.recordHostSuccess(0);
    ok = ok && ApiHandler.preferredHost(1030) == 0;
    ApiHandler.resetHostState();
    return ok;
}

(:test)
function testHostOrderAndUrl(logger) {
    return ApiHandler.HOSTS.size() == 3
        && ApiHandler.HOSTS[0].equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.urlFor(ApiHandler.HOSTS, 0, "/v1/nearby?lat=1").equals("https://api.traintime.ch/v1/nearby?lat=1")
        && ApiHandler.urlFor(ApiHandler.HOSTS, 1, "/v1/nearby").equals("https://api1.traintime.ch/v1/nearby")
        && ApiHandler.urlFor(ApiHandler.HOSTS, 2, "/v1/nearby").equals("https://api2.traintime.ch/v1/nearby");
}

(:test)
function testCustomHostIsSingleHostList(logger) {
    var custom = ApiHandler.hostsFor("https://example.com/");
    var builtin = ApiHandler.hostsFor(null);
    return custom.size() == 1 && custom[0].equals("https://example.com")
        && builtin.size() == 3 && builtin[1].equals("https://api1.traintime.ch")
        && ApiHandler.hostsFor("http://example.com").size() == 3;
}

(:test)
function testAttemptWalksHostsThenStops(logger) {
    var a = new ApiAttempt(null, ApiHandler.KIND_STATIONS, "/v1/nearby", ApiHandler.HOSTS, 1);
    var ok = a.url().equals("https://api1.traintime.ch/v1/nearby") && !a.isLast();
    a.advance();
    ok = ok && a.hostIdx == 2 && !a.isLast();
    a.advance();
    ok = ok && a.hostIdx == 0 && a.isLast();
    var single = new ApiAttempt(null, ApiHandler.KIND_STATIONS, "/x", ["https://example.com"], 0);
    return ok && single.isLast();
}
