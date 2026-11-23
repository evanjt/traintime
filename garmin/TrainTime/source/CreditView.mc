using Toybox.Communications;
using Toybox.Graphics;
using Toybox.WatchUi;

// A data credit too long for a menu sublabel, wrapped to fit the inner square of the
// screen. Select opens the licence on the paired phone, back returns to the menu.
class CreditView extends WatchUi.View {

    private var mText;

    function initialize(text) {
        View.initialize();
        mText = text;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var boxW = (w * 0.72).toNumber();
        var boxH = (h * 0.72).toNumber();
        var font = Graphics.FONT_XTINY;
        var text = mText;
        if (dc has :fitTextToArea) {
            text = dc.fitTextToArea(mText, font, boxW, boxH, true);
        }
        dc.drawText(w / 2, h / 2, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class CreditDelegate extends WatchUi.BehaviorDelegate {

    private var mUrl;

    function initialize(url) {
        BehaviorDelegate.initialize();
        mUrl = url;
    }

    function onSelect() {
        if (Communications has :openWebPage) {
            Communications.openWebPage(mUrl, null, null);
        }
        return true;
    }
}
