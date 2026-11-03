package com.evanjt.traintime.domain

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

// Port of PhoneHapticService.swift / Haptics.mc. `enabled` is read at every
// buzz, so a settings change applies without rebuilding the service.
class HapticService(
    private val sink: ((VibrationEffect) -> Unit)?,
    private val enabled: () -> Boolean,
) {
    constructor(context: Context, enabled: () -> Boolean) :
        this(systemVibrator(context)?.let { v -> { effect: VibrationEffect -> v.vibrate(effect) } }, enabled)

    // Selection feedback (iOS medium impact).
    fun shortPulse() {
        vibrate(VibrationEffect.createOneShot(30, 160))
    }

    // Warning, e.g. platform change in the list (iOS .warning notification).
    fun doublePulse() {
        vibrate(VibrationEffect.createWaveform(longArrayOf(0, 40, 80, 40), intArrayOf(0, 200, 0, 200), -1))
    }

    // Running-late nudge while tracking (iOS heavy impact per beat).
    fun heartbeat() {
        vibrate(VibrationEffect.createOneShot(60, 255))
    }

    // Platform change while tracking (iOS .error notification).
    fun platformChange() {
        vibrate(
            VibrationEffect.createWaveform(
                longArrayOf(0, 60, 90, 60, 90, 60),
                intArrayOf(0, 255, 0, 255, 0, 255),
                -1,
            ),
        )
    }

    private fun vibrate(effect: VibrationEffect) {
        if (!enabled()) return
        sink?.invoke(effect)
    }
}

private fun systemVibrator(context: Context): Vibrator? {
    val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
        manager.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    return v.takeIf { it.hasVibrator() }
}
