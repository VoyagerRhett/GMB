package com.crcfrcn.citizenwallet

import android.view.WindowManager
import com.crcfrcn.citizenwallet.security.HardwareSecretvaultPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    // 内部通道使用产品级稳定名称，不再与 Android applicationId 绑定。
    private val channelName = "citizenwallet/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(HardwareSecretvaultPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableScreenshotProtection" -> {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                        result.success(null)
                    }
                    "disableScreenshotProtection" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "beginEmergencyWipe" -> {
                        // 任务退到后台但不销毁 Flutter 引擎，当前进程继续完成不可逆擦除。
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "finishEmergencyWipe" -> {
                        result.success(null)
                        window.decorView.post { finishAndRemoveTask() }
                    }
                    "isDeviceRooted" -> {
                        result.success(checkRoot())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkRoot(): Boolean {
        // 1. 检查常见 su 路径
        val suPaths = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/data/local/xbin/su", "/data/local/bin/su",
            "/system/sd/xbin/su", "/system/bin/failsafe/su",
            "/data/local/su", "/su/bin/su",
            "/system/app/Superuser.apk",
            "/system/app/SuperSU.apk",
        )
        for (path in suPaths) {
            if (File(path).exists()) return true
        }
        // 2. 检查 build tags
        val buildTags = android.os.Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) return true
        // 3. 检查 Magisk
        if (File("/sbin/.magisk").exists()) return true
        if (File("/data/adb/magisk").exists()) return true
        return false
    }
}
