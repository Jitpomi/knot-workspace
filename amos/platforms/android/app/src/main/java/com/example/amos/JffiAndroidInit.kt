package com.example.amos

import android.content.Context

/**
 * JFFI Android initialization helper.
 * 
 * Auto-generated to handle ndk-context initialization for Rust dependencies
 * that need Android context (e.g., hickory-resolver for DNS).
 * 
 * This is necessary because UniFFI uses JNA which doesn't call JNI_OnLoad,
 * so we need explicit initialization before any Rust code runs.
 */
object JffiAndroidInit {
    init {
        System.loadLibrary("amos_core")
    }

    /**
     * Initialize Android context for Rust code.
     * 
     * MUST be called before creating any Rust objects that use ndk-context.
     * Typically called in Application.onCreate() or Activity.onCreate().
     * 
     * @param context The Android application or activity context
     */
    @JvmStatic
    external fun initNdkContext(context: Context)
}
