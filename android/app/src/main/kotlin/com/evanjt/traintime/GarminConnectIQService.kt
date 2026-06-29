package com.evanjt.traintime

import android.content.Context
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Cross-ecosystem bridge from the phone to a Garmin watch via the Connect IQ Mobile SDK,
 * relayed by the Garmin Connect Mobile app. The Garmin analog of the Wearable Data Layer
 * used for Wear OS, and the peer of the iOS GarminConnectIQService.
 *
 * Entirely optional and silent. The SDK is initialised with autoUI = false, so a missing
 * Garmin Connect app raises onInitializeError and the service stays unavailable
 * (`isAvailable` false → no Garmin row in the picker) rather than popping a dialog. Users
 * without a Garmin watch are unaffected.
 */
class GarminConnectIQService(private val context: Context) {

    data class GarminDevice(val id: String, val name: String)

    companion object {
        const val APP_UUID = "7df2c0d5-e539-413a-962c-96147dad27f0"
    }

    /** Set by MainViewModel to receive state pushed back from the watch (defaultMode etc.). */
    var onMessageReceived: ((Map<String, Any?>) -> Unit)? = null

    /** Fires whenever a watch connects/disconnects (e.g. Bluetooth toggled), for live status. */
    var onLinkChanged: (() -> Unit)? = null

    private val connectIQ: ConnectIQ = ConnectIQ.getInstance(context, ConnectIQ.IQConnectType.WIRELESS)
    private val app = IQApp(APP_UUID)
    private val registered = mutableSetOf<Long>()

    @Volatile
    var isAvailable = false
        private set

    private val sdkListener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            isAvailable = true
            // Register for ALL paired devices (not just connected) so we hear connect /
            // disconnect events live when Bluetooth toggles.
            knownOrEmpty().forEach { ensureRegistered(it) }
            onLinkChanged?.invoke()
        }

        override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus) {
            isAvailable = false
        }

        override fun onSdkShutDown() {
            isAvailable = false
        }
    }

    fun initialize() {
        runCatching { connectIQ.initialize(context, false, sdkListener) }
    }

    fun shutdown() {
        runCatching {
            connectIQ.unregisterAllForEvents()
            connectIQ.shutdown(context)
        }
        isAvailable = false
        registered.clear()
    }

    // Connected devices that actually have TrainTime installed. This is the SDK-side
    // filter the user wanted: a paired Edge or an old watch without our app drops out
    // automatically, with no main-device setting stored in our app. Suspends because
    // the install check (getApplicationInfo) is a BLE round-trip per device.
    suspend fun eligibleDevices(): List<GarminDevice> {
        if (!isAvailable) return emptyList()
        val connected = devicesOrEmpty().filter {
            runCatching { connectIQ.getDeviceStatus(it) }.getOrNull() == IQDevice.IQDeviceStatus.CONNECTED
        }
        return connected
            .filter { isAppInstalled(it) }
            .map { GarminDevice(it.deviceIdentifier.toString(), it.friendlyName ?: "Garmin Watch") }
    }

    private suspend fun isAppInstalled(device: IQDevice): Boolean = suspendCancellableCoroutine { cont ->
        try {
            connectIQ.getApplicationInfo(APP_UUID, device, object : ConnectIQ.IQApplicationInfoListener {
                override fun onApplicationInfoReceived(app: IQApp) {
                    if (cont.isActive) cont.resume(app.status == IQApp.IQAppStatus.INSTALLED)
                }
                override fun onApplicationNotInstalled(applicationId: String) {
                    if (cont.isActive) cont.resume(false)
                }
            })
        } catch (_: Exception) {
            if (cont.isActive) cont.resume(false)
        }
    }

    // Generic action-dispatched send to the watch (track / mode / station / loc).
    // Every payload carries an "action" key the watch switches on in handlePhoneMessage.
    suspend fun send(deviceId: String, payload: Map<String, Any?>): Boolean {
        if (!isAvailable) return false
        val device = devicesOrEmpty().firstOrNull { it.deviceIdentifier.toString() == deviceId } ?: return false
        ensureRegistered(device)
        return suspendCancellableCoroutine { cont ->
            try {
                connectIQ.sendMessage(device, app, payload) { _, _, status ->
                    if (cont.isActive) cont.resume(status == ConnectIQ.IQMessageStatus.SUCCESS)
                }
            } catch (_: Exception) {
                if (cont.isActive) cont.resume(false)
            }
        }
    }

    suspend fun sendTrack(deviceId: String, payload: Map<String, Any?>): Boolean =
        send(deviceId, payload)

    // Asks the watch to launch the TrainTime app. The watch may show a brief prompt if
    // the app isn't already running; a no-op (APP_IS_ALREADY_RUNNING) when it is.
    fun openApp(deviceId: String) {
        if (!isAvailable) return
        val device = devicesOrEmpty().firstOrNull { it.deviceIdentifier.toString() == deviceId } ?: return
        runCatching { connectIQ.openApplication(device, app) { _, _, _ -> } }
    }

    private fun ensureRegistered(device: IQDevice) {
        if (!registered.add(device.deviceIdentifier)) return
        runCatching {
            // Live status: any connect/disconnect notifies the UI to re-check.
            connectIQ.registerForDeviceEvents(device) { _, _ -> onLinkChanged?.invoke() }
            connectIQ.registerForAppEvents(device, app) { _, _, message, _ ->
                onMessageReceived?.invoke(messageToMap(message))
            }
        }
    }

    private fun devicesOrEmpty(): List<IQDevice> = try {
        connectIQ.connectedDevices ?: emptyList()
    } catch (_: InvalidStateException) {
        emptyList()
    } catch (_: ServiceUnavailableException) {
        emptyList()
    }

    private fun knownOrEmpty(): List<IQDevice> = try {
        connectIQ.knownDevices ?: emptyList()
    } catch (_: InvalidStateException) {
        emptyList()
    } catch (_: ServiceUnavailableException) {
        emptyList()
    }

    // The watch transmits a Dictionary; the SDK delivers it as a single-element message list.
    private fun messageToMap(message: List<Any?>?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return (message?.firstOrNull() as? Map<String, Any?>) ?: emptyMap()
    }
}
