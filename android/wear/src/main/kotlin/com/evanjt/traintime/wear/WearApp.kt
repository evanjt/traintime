package com.evanjt.traintime.wear

import android.app.Application
import com.evanjt.traintime.data.api.ApiHost

class WearApp : Application() {
    override fun onCreate() {
        super.onCreate()
        ApiHost.bind(this)
    }
}
