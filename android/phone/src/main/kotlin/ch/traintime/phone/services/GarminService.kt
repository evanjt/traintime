package ch.traintime.phone.services

import android.content.Context
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class GarminService(private val context: Context) {

    companion object {
        private const val TAG = "GarminService"
        private const val APP_ID = "7df2c0d5e539413a962c96147dad27f0"
    }

    private var connectIQ: ConnectIQ? = null
    private var initialized = false

    fun initialize() {
        try {
            connectIQ = ConnectIQ.getInstance(context, ConnectIQ.IQConnectType.WIRELESS)
            connectIQ?.initialize(context, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    initialized = true
                }

                override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                    Log.w(TAG, "ConnectIQ init error: $status")
                    initialized = false
                }

                override fun onSdkShutDown() {
                    initialized = false
                }
            })
        } catch (e: Exception) {
            Log.w(TAG, "ConnectIQ not available", e)
        }
    }

    fun shutdown() {
        try {
            connectIQ?.shutdown(context)
        } catch (_: Exception) {}
        initialized = false
    }

    fun getConnectedDevices(): List<Pair<String, IQDevice>> {
        if (!initialized) return emptyList()
        return try {
            val devices = connectIQ?.connectedDevices ?: emptyList()
            devices.map { (it.friendlyName ?: "Garmin Watch") to it }
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun sendMessage(device: IQDevice, data: Map<String, Any>): Boolean {
        if (!initialized) return false
        val ciq = connectIQ ?: return false
        val app = IQApp(APP_ID)

        return suspendCancellableCoroutine { cont ->
            try {
                // Open the app first to ensure it's running
                ciq.openApplication(device, app, object : ConnectIQ.IQOpenApplicationListener {
                    override fun onOpenApplicationResponse(
                        device: IQDevice?,
                        app: IQApp?,
                        status: ConnectIQ.IQOpenApplicationStatus?
                    ) {
                        if (status == ConnectIQ.IQOpenApplicationStatus.APP_IS_ALREADY_RUNNING ||
                            status == ConnectIQ.IQOpenApplicationStatus.PROMPT_SHOWN_ON_DEVICE
                        ) {
                            // Now send the message
                            try {
                                ciq.sendMessage(device, app, data,
                                    object : ConnectIQ.IQSendMessageListener {
                                        override fun onMessageStatus(
                                            device: IQDevice?,
                                            app: IQApp?,
                                            status: ConnectIQ.IQMessageStatus?
                                        ) {
                                            if (cont.isActive) {
                                                cont.resume(status == ConnectIQ.IQMessageStatus.SUCCESS)
                                            }
                                        }
                                    })
                            } catch (e: Exception) {
                                if (cont.isActive) cont.resume(false)
                            }
                        } else {
                            if (cont.isActive) cont.resume(false)
                        }
                    }
                })
            } catch (e: Exception) {
                if (cont.isActive) cont.resume(false)
            }
        }
    }
}
