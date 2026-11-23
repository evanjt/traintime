using Toybox.Test;

// The settings menu doubles as the watch's attribution screen. Built only with `monkeyc -t`.

(:test)
function testSettingsMenuCreditsVictoria(logger) {
    var menu = SettingsMenu.build(null);
    if (menu.findItemById(:ptvSource) < 0) { return false; }
    return SettingsMenu.PTV_CREDIT.equals(
        "Source: Licensed from Public Transport Victoria under a Creative Commons Attribution 4.0 International Licence.");
}

(:test)
function testSettingsMenuStillCreditsSwissSources(logger) {
    var menu = SettingsMenu.build(null);
    return menu.findItemById(:dataSource) >= 0 && menu.findItemById(:stationsSource) >= 0;
}
