using Toybox.WatchUi;

// The native list of transport modes a tap on the mode band opens. Buttons
// keep cycling with Up and Down.
module ModeMenu {

    function label(mode) {
        if (mode == 0) { return Txt.t(Rez.Strings.ModeTrains); }
        if (mode == 1) { return Txt.t(Rez.Strings.ModeBuses); }
        if (mode == 2) { return Txt.t(Rez.Strings.ModeTrams); }
        return Txt.t(Rez.Strings.ModeSpecials);
    }

    (:touch)
    function open(view) {
        WatchUi.pushView(build(view), new ModeMenuDelegate(view), WatchUi.SLIDE_UP);
    }

    (:touch)
    function build(view) {
        return fill(new WatchUi.Menu2({:title => Txt.t(Rez.Strings.HintMode)}), view);
    }

    // Only the modes the board can show, the current one marked. The focus
    // stays on the first item: moving it scrolls the title out of view.
    (:touch)
    function fill(menu, view) {
        for (var mode = 0; mode < 4; mode++) {
            if (!Renderer.isModeAvailable(view, mode)) { continue; }
            menu.addItem(new WatchUi.MenuItem(label(mode),
                mode == view.mCurrentMode ? Txt.t(Rez.Strings.ModeCurrent) : null, mode, {}));
        }
        return menu;
    }
}

(:touch)
class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var mView;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        mView = view;
    }

    function onSelect(item) {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        mView.selectMode(item.getId());
        WatchUi.requestUpdate();
    }
}
