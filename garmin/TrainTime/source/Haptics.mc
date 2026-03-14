using Toybox.Attention;

module Haptics {

    function vibrateShort() {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 50)]);
        }
    }

    function vibrateDouble() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 50)
            ]);
        }
    }

    function vibrateHeartbeat() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(50, 50),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(50, 50)
            ]);
        }
    }
}
