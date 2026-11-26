using Toybox.Test;

// Unit tests for the custom API host guard. Built only with `monkeyc -t`.

(:test)
function testHostDefaultWhenUnset(logger) {
    return ApiHandler.hostOrDefault(null).equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.hostOrDefault("").equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.hostOrDefault("   ").equals(ApiHandler.DEFAULT_HOST);
}

(:test)
function testHostRejectsNonHttps(logger) {
    return ApiHandler.hostOrDefault("http://example.com").equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.hostOrDefault("example.com").equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.hostOrDefault("https://").equals(ApiHandler.DEFAULT_HOST)
        && ApiHandler.hostOrDefault("https:///").equals(ApiHandler.DEFAULT_HOST);
}

(:test)
function testHostTrimsAndStripsSlash(logger) {
    return ApiHandler.hostOrDefault(" https://example.com/ ").equals("https://example.com")
        && ApiHandler.hostOrDefault("https://example.com:8443/api").equals("https://example.com:8443/api");
}
