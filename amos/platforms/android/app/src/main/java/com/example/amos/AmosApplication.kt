package com.example.amos

import android.app.Application

class AmosApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Initialize ndk-context before any Rust core code starts
        JffiAndroidInit.initNdkContext(applicationContext)
    }
}
