using Toybox.Test;
using Toybox.WatchUi;

// The mode list a tap on the mode band opens. Built only with `monkeyc -t`.

(:test)
class ModeMenuBoard {
    var mAvailableModes;
    var mCurrentMode;

    function initialize(available, current) {
        mAvailableModes = available;
        mCurrentMode = current;
    }
}

(:test)
class FocusRecordingMenu extends WatchUi.Menu2 {
    var mFocusCalls = 0;

    function initialize() {
        Menu2.initialize(null);
    }

    function setFocus(index) {
        mFocusCalls++;
        Menu2.setFocus(index);
    }
}

(:test)
function testModeMenuListsOnlyAvailableModes(logger) {
    var menu = ModeMenu.build(new ModeMenuBoard([0, 2], 0));
    return menu.findItemById(0) >= 0
        && menu.findItemById(1) < 0
        && menu.findItemById(2) >= 0
        && menu.findItemById(3) < 0;
}

(:test)
function testModeMenuMarksCurrentMode(logger) {
    var menu = ModeMenu.build(new ModeMenuBoard([0, 1, 2, 3], 2));
    var current = menu.getItem(menu.findItemById(2)) as WatchUi.MenuItem;
    var other = menu.getItem(menu.findItemById(1)) as WatchUi.MenuItem;
    return Txt.t(Rez.Strings.ModeCurrent).equals(current.getSubLabel())
        && other.getSubLabel() == null
        && Txt.t(Rez.Strings.ModeTrams).equals(current.getLabel());
}

// Scenario: the last of four modes is current.
// Expected behaviour: the list opens at its top with the title in view, so
// nothing moves the focus off the first item.
(:test)
function testModeMenuOpensAtTop(logger) {
    var menu = new FocusRecordingMenu();
    ModeMenu.fill(menu, new ModeMenuBoard([0, 1, 2, 3], 3));
    return menu.mFocusCalls == 0;
}
