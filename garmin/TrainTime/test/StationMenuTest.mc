using Toybox.Test;
using Toybox.WatchUi;

// The station list a tap on the station name opens. Built only with `monkeyc -t`.

// Helpers sit in a test module so they stay out of the app build and off the runner
(:test)
module StationMenuBoard {

    function stationMenuBoard(current) {
        var view = new TrainTimeView();
        view.mStations = [
            { "id" => "9100001", "label" => "Larkspur Quay", "lat" => null, "lon" => null, "dist" => 120 },
            { "id" => "9100002", "label" => "Thistle Row", "lat" => null, "lon" => null, "dist" => 340 },
            { "id" => "9100003", "label" => "Marigold Yard", "lat" => null, "lon" => null, "dist" => 610 }
        ];
        view.mStationIndex = current;
        return view;
    }
}

(:test)
function testStationMenuListsLoadedStationsInOrder(logger) {
    var view = StationMenuBoard.stationMenuBoard(0);
    var menu = StationMenu.build(view);
    for (var i = 0; i < view.mStations.size(); i++) {
        var item = menu.getItem(i) as WatchUi.MenuItem;
        if (item == null || item.getId() != i || !view.mStations[i]["label"].equals(item.getLabel())) {
            return false;
        }
    }
    return menu.getItem(view.mStations.size()) == null;
}

(:test)
function testStationMenuMarksCurrentStationWithWalk(logger) {
    var menu = StationMenu.build(StationMenuBoard.stationMenuBoard(1));
    var current = menu.getItem(1) as WatchUi.MenuItem;
    var other = menu.getItem(2) as WatchUi.MenuItem;
    var walk = WalkInfo.brief(610);
    return current.getSubLabel().find(Txt.t(Rez.Strings.ModeCurrent)) != null
        && other.getSubLabel().equals(walk)
        && other.getSubLabel().find(Txt.t(Rez.Strings.ModeCurrent)) == null;
}

(:test)
function testStationMenuOpensAtTop(logger) {
    var menu = new FocusRecordingMenu();
    StationMenu.fill(menu, StationMenuBoard.stationMenuBoard(2));
    return menu.mFocusCalls == 0;
}

// Scenario: the cursor is on the station name, the second of three is picked.
// Expected behaviour: the board shows that station, scrolled to the top, with
// the cursor still on the name.
(:test)
function testPickingStationLeavesBoardOnIt(logger) {
    var view = StationMenuBoard.stationMenuBoard(0);
    view.mAppState = 1;
    view.mCursorIndex = 2;
    view.mScrollOffset = 3;
    view.pickStation(1);
    return view.mStationIndex == 1
        && "9100002".equals(view.mStationId)
        && "Thistle Row".equals(view.mStationName)
        && view.mScrollOffset == 0
        && view.mCursorIndex == -1;
}
