package com.example.mdm_client_base

import android.app.admin.DevicePolicyManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mdm_client_base/device_policy"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceOwnerOrProfileOwner" -> {
                    val isAdmin = devicePolicyManager.isDeviceOwnerApp(packageName) ||
                            devicePolicyManager.isProfileOwnerApp(packageName)
                    result.success(isAdmin)
                }
                "lockDevice" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.lockNow()
                            result.success(true)
                        } else {
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "wipeData" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.wipeData(0)
                            result.success(true)
                        } else {
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        result.error("WIPE_ERROR", e.message, null)
                    }
                }
                "installSystemApp" -> {
                    try {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath == null) {
                            result.error("INVALID_PATH", "APK path is null", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            val file = File(apkPath)
                            if (file.exists()) {
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )
                                val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                    setData(uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("FILE_NOT_FOUND", "APK file not found", null)
                            }
                        } else {
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "uninstallPackage" -> {
                    try {
                        val packageName = call.argument<String>("packageName")
                        if (packageName == null) {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName)) {
                            val packageInstaller = packageManager.packageInstaller
                            val intent = Intent(this, UninstallResultReceiver::class.java).apply {
                                action = "com.example.mdm_client_base.UNINSTALL_RESULT"
                                putExtra("packageName", packageName)
                            }
                            val pendingIntent = PendingIntent.getBroadcast(
                                this,
                                packageName.hashCode(),
                                intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            )
                            packageInstaller.uninstall(packageName, pendingIntent.intentSender)
                            result.success(true)
                        } else {
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        result.error("UNINSTALL_ERROR", e.message, null)
                    }
                }
                "requestDeviceAdmin" -> {
                    try {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, call.argument<String>("explanation"))
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REQUEST_ADMIN_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}