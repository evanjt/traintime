package com.evanjt.traintime

import android.app.Application
import com.evanjt.traintime.core.sync.WearSync
import com.evanjt.traintime.data.api.ApiHost

class TrainTimeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Stamp the local version so any versioned handshake we send reports it.
        WearSync.localVersionName = BuildConfig.VERSION_NAME
        ApiHost.bind(this)
    }
}
