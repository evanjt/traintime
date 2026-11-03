using Toybox.Attention;
using Toybox.Application.Storage;
using Toybox.System;

module Haptics {

    const STORAGE_KEY = "haptics";

    // An absent setting means on. The watch's own vibration switch always wins.
    function isEnabled(stored, deviceVibrateOn) {
        return stored != false && deviceVibrateOn != false;
    }

    function enabled() {
        if (!(Attention has :vibrate)) { return false; }
        return isEnabled(Storage.getValue(STORAGE_KEY), System.getDeviceSettings().vibrateOn);
    }

    function vibrateShort() {
        if (enabled()) {
            Attention.vibrate([new Attention.VibeProfile(50, 50)]);
        }
    }

    function vibrateDouble() {
        if (enabled()) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 50)
            ]);
        }
    }

    function vibrateHeartbeat() {
        if (enabled()) {
            Attention.vibrate([
                new Attention.VibeProfile(50, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(50, 50)
            ]);
        }
    }
}
