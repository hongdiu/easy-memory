package com.easymemory.easy_memory

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.easymemory.easy_memory/multicast_lock"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    val wifi = getSystemService(Context.WIFI_SERVICE) as WifiManager
                    if (multicastLock == null) {
                        multicastLock = wifi.createMulticastLock("easy_memory_discovery")
                        multicastLock?.setReferenceCounted(false)
                    }
                    multicastLock?.acquire()
                    result.success(true)
                }
                "release" -> {
                    multicastLock?.release()
                    multicastLock = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}