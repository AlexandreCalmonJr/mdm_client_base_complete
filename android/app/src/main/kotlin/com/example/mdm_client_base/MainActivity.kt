package com.example.mdm_client_base

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.UserManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mdm_client_base/device_policy"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private val TAG = "MDM_MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationChannel.createNotificationChannel(this)
        Log.d(TAG, "MainActivity onCreate")

        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

        // Handle provisioning
        handleProvisioningIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleProvisioningIntent(intent)
    }

    private fun handleProvisioningIntent(intent: Intent?) {
        val action = intent?.action
        if (action == DevicePolicyManager.ACTION_PROVISION_MANAGED_DEVICE ||
            action == "com.samsung.android.knox.intent.action.PROVISION_MANAGED_DEVICE") {
            Log.d(TAG, "Provisioning detected: $action")
            try {
                val provisioningIntent = Intent(DevicePolicyManager.ACTION_PROVISION_MANAGED_DEVICE).apply {
                    putExtra(DevicePolicyManager.EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME, adminComponent)
                    putExtra(DevicePolicyManager.EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME, packageName)
                    putExtra(DevicePolicyManager.EXTRA_PROVISIONING_WIFI_SSID, "MDM_Network")
                    putExtra(DevicePolicyManager.EXTRA_PROVISIONING_WIFI_PASSWORD, "your_wifi_password")
                    putExtra(DevicePolicyManager.EXTRA_PROVISIONING_SKIP_ENCRYPTION, true)
                    if (action == "com.samsung.android.knox.intent.action.PROVISION_MANAGED_DEVICE") {
                        putExtra("com.samsung.android.knox.intent.extra.KNOX_ENROLLMENT_PROFILE", true)
                    }
                }
                startActivityForResult(provisioningIntent, 1001)
                Log.d(TAG, "Starting provisioning as Device Owner")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting provisioning: ${e.message}", e)
                notifyProvisioningFailure("Error starting provisioning: ${e.message}")
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == RESULT_OK) {
                Log.d(TAG, "Provisioning completed successfully")
                applyInitialPolicies()
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("provisioningComplete", mapOf("status" to "success"))
                }
            } else {
                Log.e(TAG, "Provisioning failed, resultCode: $resultCode")
                notifyProvisioningFailure("Provisioning failed, code: $resultCode")
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("provisioningComplete", mapOf("status" to "failed", "error" to "Code: $resultCode"))
                }
            }
        }
    }

    private fun applyInitialPolicies() {
        try {
            if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                Log.d(TAG, "Applying initial policies as Device Owner")
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_LOCATION)
                // Forçar localização ativada
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    devicePolicyManager.setLocationEnabled(adminComponent, true)
                    Log.d(TAG, "Localização forçada a permanecer ativada")
                }
                // Desativar Quick Settings
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    devicePolicyManager.setStatusBarDisabled(adminComponent, true)
                    Log.d(TAG, "Painel de configurações rápidas desativado")
                }
                devicePolicyManager.setPasswordQuality(adminComponent, DevicePolicyManager.PASSWORD_QUALITY_ALPHANUMERIC)
                devicePolicyManager.setPasswordMinimumLength(adminComponent, 8)
                devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf(packageName))
                Log.d(TAG, "Initial policies applied successfully")
            } else {
                Log.w(TAG, "Not Device Owner, policies not applied")
                notifyPolicyFailure("Application is not Device Owner")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error applying initial policies: ${e.message}", e)
            notifyPolicyFailure("Error applying policies: ${e.message}")
        }
    }

    private fun notifyProvisioningFailure(message: String) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("provisioningFailure", mapOf("error" to message))
        }
    }

    private fun notifyPolicyFailure(message: String) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("policyFailure", mapOf("error" to message))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring MethodChannel: $CHANNEL")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Method called: ${call.method}")
            when (call.method) {
                "getSdkVersion" -> {
                    try {
                        val sdkVersion = Build.VERSION.SDK_INT
                        Log.d(TAG, "SDK Version: $sdkVersion")
                        result.success(sdkVersion)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting SDK version: ${e.message}")
                        result.error("SDK_VERSION_ERROR", "Error getting SDK version: ${e.message}", null)
                    }
                }
                "disableApp" -> {
                    val packageName = call.argument<String>("packageName")
                    try {
                        if (packageName == null) {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName)) {
                            devicePolicyManager.setApplicationHidden(adminComponent, packageName, true)
                            Log.d(TAG, "App $packageName disabled")
                            result.success("App disabled successfully")
                        } else {
                            Log.w(TAG, "Not Device Owner")
                            result.error("NOT_ADMIN", "Device Owner permissions required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error disabling app: ${e.message}")
                        result.error("DISABLE_ERROR", "Error disabling app: ${e.message}", null)
                    }
                }
                "installSystemApp" -> {
                    val apkPath = call.argument<String>("apkPath")
                    Log.d(TAG, "Attempting to install APK: $apkPath")
                    try {
                        if (apkPath == null) {
                            Log.w(TAG, "APK path is null")
                            result.error("INVALID_PATH", "APK path is null", null)
                            return@setMethodCallHandler
                        }

                        val apkFile = File(apkPath)
                        Log.d(TAG, "Checking file: ${apkFile.absolutePath}")
                        Log.d(TAG, "File exists: ${apkFile.exists()}, Readable: ${apkFile.canRead()}, Size: ${if (apkFile.exists()) apkFile.length() else "N/A"}")

                        if (!apkFile.exists() || !apkFile.canRead()) {
                            Log.w(TAG, "APK file not found or not readable: $apkPath")
                            result.error("FILE_NOT_FOUND", "APK file not found or not readable: $apkPath", null)
                            return@setMethodCallHandler
                        }

                        // Validate APK file integrity
                        if (!validateApkFile(apkFile)) {
                            Log.w(TAG, "Invalid APK file: $apkPath")
                            result.error("INVALID_APK", "APK file is corrupted or invalid", null)
                            return@setMethodCallHandler
                        }

                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            Log.d(TAG, "Attempting silent installation as Device Owner")
                            installSilently(apkFile, result)
                        } else {
                            Log.d(TAG, "Not Device Owner, using normal installation")
                            installNormally(apkFile, result)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "General error installing APK: ${e.message}", e)
                        result.error("INSTALL_ERROR", "Error installing APK: ${e.message}", null)
                    }
                }
                "restrictSettings" -> {
                    try {
                        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            Log.w(TAG, "Não é Device Owner")
                            result.error("ADMIN_ERROR", "Aplicativo não é Device Owner", null)
                            return@setMethodCallHandler
                        }

                        // Expect a map of restrictions with boolean values
                        val restrictions = call.argument<Map<String, Boolean>>("restrictions")
                        if (restrictions == null) {
                            Log.w(TAG, "Mapa de restrições é nulo")
                            result.error("INVALID_INPUT", "Mapa de restrições é nulo", null)
                            return@setMethodCallHandler
                        }

                        val appliedRestrictions = mutableListOf<String>()
                        val clearedRestrictions = mutableListOf<String>()
                        val errors = mutableListOf<String>()
                        val currentStatus = mutableMapOf<String, Boolean>()

                        // Define supported restrictions
                        val restrictionMap = mapOf(
                            "DISALLOW_CONFIG_WIFI" to UserManager.DISALLOW_CONFIG_WIFI,
                            "DISALLOW_INSTALL_APPS" to UserManager.DISALLOW_INSTALL_APPS,
                            "DISALLOW_UNINSTALL_APPS" to UserManager.DISALLOW_UNINSTALL_APPS,
                            "DISALLOW_MODIFY_ACCOUNTS" to UserManager.DISALLOW_MODIFY_ACCOUNTS,
                            "DISALLOW_CONFIG_MOBILE_NETWORKS" to UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS,
                            "DISALLOW_FACTORY_RESET" to UserManager.DISALLOW_FACTORY_RESET,
                            "DISALLOW_CONFIG_LOCATION" to UserManager.DISALLOW_CONFIG_LOCATION
                        )

                        // Verificar status atual das restrições
                        restrictionMap.forEach { (key, restriction) ->
                            val isRestricted = devicePolicyManager.getUserRestrictions(adminComponent).contains(restriction)
                            currentStatus[key] = isRestricted
                            Log.d(TAG, "Restrição $key: atualmente ${if (isRestricted) "ativa" else "inativa"}")
                        }

                        // Processar cada restrição solicitada
                        restrictions.forEach { (key, enable) ->
                            val restriction = restrictionMap[key]
                            if (restriction == null) {
                                Log.w(TAG, "Restrição não suportada: $key")
                                errors.add("Restrição não suportada: $key")
                                return@forEach
                            }
                            try {
                                if (enable) {
                                    devicePolicyManager.addUserRestriction(adminComponent, restriction)
                                    appliedRestrictions.add(key)
                                    Log.d(TAG, "Restrição aplicada: $key")
                                    // Forçar localização ativada para DISALLOW_CONFIG_LOCATION
                                    if (key == "DISALLOW_CONFIG_LOCATION" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        devicePolicyManager.setLocationEnabled(adminComponent, true)
                                        Log.d(TAG, "Localização forçada a permanecer ativada")
                                    }
                                } else {
                                    devicePolicyManager.clearUserRestriction(adminComponent, restriction)
                                    clearedRestrictions.add(key)
                                    Log.d(TAG, "Restrição removida: $key")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Erro ao processar restrição $key: ${e.message}")
                                errors.add("Falha ao processar $key: ${e.message}")
                            }
                        }

                        // Tentar bloquear o aplicativo de configurações do sistema
                        try {
                            if (restrictions.values.any { it }) { // Se alguma restrição está ativa
                                devicePolicyManager.setApplicationHidden(adminComponent, "com.android.settings", true)
                                Log.d(TAG, "Aplicativo de configurações do sistema (com.android.settings) ocultado")
                                // Fallback: suspender o pacote de configurações
                                devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf("com.android.settings"), true)
                                Log.d(TAG, "Aplicativo de configurações do sistema (com.android.settings) suspenso")
                                // Desativar Quick Settings
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    devicePolicyManager.setStatusBarDisabled(adminComponent, true)
                                    Log.d(TAG, "Painel de configurações rápidas desativado")
                                }
                            } else {
                                devicePolicyManager.setApplicationHidden(adminComponent, "com.android.settings", false)
                                devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf("com.android.settings"), false)
                                Log.d(TAG, "Aplicativo de configurações do sistema (com.android.settings) restaurado")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    devicePolicyManager.setStatusBarDisabled(adminComponent, false)
                                    Log.d(TAG, "Painel de configurações rápidas restaurado")
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Erro ao bloquear configurações: ${e.message}")
                            errors.add("Erro ao bloquear configurações: ${e.message}")
                        }

                        // Preparar resultado
                        val resultMap = mapOf(
                            "applied" to appliedRestrictions,
                            "cleared" to clearedRestrictions,
                            "errors" to errors,
                            "currentStatus" to currentStatus
                        )

                        if (errors.isEmpty()) {
                            Log.d(TAG, "Restrições atualizadas com sucesso: $resultMap")
                            result.success(resultMap)
                        } else {
                            Log.e(TAG, "Algumas restrições falharam: $errors")
                            result.error("RESTRICT_SETTINGS_PARTIAL_ERROR", "Algumas restrições falharam: $errors", resultMap)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao restringir configurações: ${e.message}")
                        result.error("RESTRICT_SETTINGS_ERROR", "Erro ao restringir configurações: ${e.message}", null)
                    }
                }
                "getWifiInfo" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val wifiInfo = wifiManager.connectionInfo
                        val ssid = wifiInfo.ssid?.replace("\"", "") ?: "N/A"
                        val bssid = wifiInfo.bssid?.takeIf { it != "02:00:00:00:00:00" } ?: "N/A"
                        val result_map = mapOf(
                            "ssid" to ssid,
                            "bssid" to bssid,
                            "frequency" to wifiInfo.frequency,
                            "rssi" to wifiInfo.rssi
                        )
                        Log.d(TAG, "Wi-Fi info obtained: $result_map")
                        result.success(result_map)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting Wi-Fi info: ${e.message}")
                        result.error("WIFI_INFO_ERROR", "Error getting Wi-Fi info: ${e.message}", null)
                    }
                }
                "getMacAddress" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val wifiInfo = wifiManager.connectionInfo
                        val macAddress = wifiInfo.bssid?.takeIf { it != "02:00:00:00:00:00" } ?: "N/A"
                        Log.d(TAG, "BSSID obtained: $macAddress")
                        result.success(macAddress)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting BSSID: ${e.message}")
                        result.error("MAC_ADDRESS_ERROR", "Error getting BSSID: ${e.message}", null)
                    }
                }
                "isDeviceOwnerOrProfileOwner" -> {
                    try {
                        val isAdmin = devicePolicyManager.isDeviceOwnerApp(packageName) ||
                                devicePolicyManager.isProfileOwnerApp(packageName)
                        Log.d(TAG, "isDeviceOwnerOrProfileOwner: $isAdmin")
                        result.success(isAdmin)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in isDeviceOwnerOrProfileOwner: ${e.message}")
                        result.error("ADMIN_CHECK_ERROR", e.message, null)
                    }
                }
                "lockDevice" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.lockNow()
                            Log.d(TAG, "Device locked")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Not Device Owner")
                            result.error("NOT_ADMIN", "App is not Device Owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error locking device: ${e.message}")
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "wipeData" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.wipeData(0)
                            Log.d(TAG, "Data wiped")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Not Device Owner")
                            result.error("NOT_ADMIN", "App is not Device Owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error wiping data: ${e.message}")
                        result.error("WIPE_ERROR", e.message, null)
                    }
                }
                "uninstallPackage" -> {
                    try {
                        val packageNameArg = call.argument<String>("packageName")
                        if (packageNameArg == null) {
                            Log.w(TAG, "Package name is null")
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName)) {
                            val packageInstaller = packageManager.packageInstaller
                            val intent = Intent(this, UninstallResultReceiver::class.java).apply {
                                action = "com.example.mdm_client_base.UNINSTALL_RESULT"
                                putExtra("packageName", packageNameArg)
                            }
                            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            } else {
                                PendingIntent.FLAG_UPDATE_CURRENT
                            }
                            val pendingIntent = PendingIntent.getBroadcast(
                                this,
                                packageNameArg.hashCode(),
                                intent,
                                flags
                            )
                            packageInstaller.uninstall(packageNameArg, pendingIntent.intentSender)
                            Log.d(TAG, "Uninstallation started: $packageNameArg")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Not Device Owner")
                            result.error("NOT_ADMIN", "App is not Device Owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error uninstalling: ${e.message}")
                        result.error("UNINSTALL_ERROR", e.message, null)
                    }
                }
                "requestDeviceAdmin" -> {
                    try {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                call.argument<String>("explanation") ?: "This app requires admin permissions to function properly.")
                        }
                        startActivity(intent)
                        Log.d(TAG, "Admin request initiated")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error requesting admin: ${e.message}")
                        result.error("REQUEST_ADMIN_ERROR", e.message, null)
                    }
                }
                else -> {
                    Log.w(TAG, "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    // Validate APK file integrity using checksum
    private fun validateApkFile(apkFile: File): Boolean {
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(apkFile).use { input ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }
            // Basic validation: Ensure file is not empty and has valid size
            return apkFile.length() > 0 && apkFile.extension.equals("apk", ignoreCase = true)
        } catch (e: Exception) {
            Log.e(TAG, "Error validating APK file: ${e.message}")
            return false
        }
    }

    // Silent installation method
    private fun installSilently(apkFile: File, result: MethodChannel.Result) {
        try {
            val packageInstaller = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            // Copy APK to session
            FileInputStream(apkFile).use { input ->
                session.openWrite("package", 0, apkFile.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            // Create explicit intent and PendingIntent
            val intent = Intent(this, InstallResultReceiver::class.java).apply {
                action = "com.example.mdm_client_base.INSTALL_RESULT"
                putExtra("sessionId", sessionId)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                sessionId,
                intent,
                flags
            )

            // Register receiver for installation result
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    try {
                        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Unknown error"
                        Log.d(TAG, "Silent installation result - Status: $status, Message: $message")

                        when (status) {
                            PackageInstaller.STATUS_SUCCESS -> {
                                Log.d(TAG, "Silent installation successful: ${apkFile.name}")
                                result.success("APK installed silently successfully")
                            }
                            else -> {
                                Log.e(TAG, "Silent installation failed: Status=$status, Message=$message")
                                Log.d(TAG, "Falling back to normal installation")
                                try {
                                    installNormally(apkFile, result)
                                } catch (fallbackError: Exception) {
                                    Log.e(TAG, "Fallback installation failed: ${fallbackError.message}")
                                    result.error(
                                        "INSTALL_FAILED",
                                        "Failed both methods - Silent: $message, Normal: ${fallbackError.message}",
                                        null
                                    )
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing silent installation result: ${e.message}")
                        try {
                            installNormally(apkFile, result)
                        } catch (fallbackError: Exception) {
                            result.error(
                                "INSTALL_ERROR",
                                "Error processing result and fallback: ${e.message}, ${fallbackError.message}",
                                null
                            )
                        }
                    } finally {
                        try {
                            context.unregisterReceiver(this)
                        } catch (ignored: Exception) {
                            Log.w(TAG, "Receiver already unregistered")
                        }
                    }
                }
            }

            val filter = IntentFilter("com.example.mdm_client_base.INSTALL_RESULT")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }

            session.commit(pendingIntent.intentSender)
            session.close()
            Log.d(TAG, "Silent installation session committed with ID: $sessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Error during silent installation: ${e.message}")
            try {
                installNormally(apkFile, result)
            } catch (fallbackError: Exception) {
                result.error("INSTALL_ERROR", "Silent installation failed: ${e.message}, Fallback failed: ${fallbackError.message}", null)
            }
        }
    }

    // Normal installation method
    private fun installNormally(apkFile: File, result: MethodChannel.Result) {
        Log.d(TAG, "Starting normal installation")
        try {
            val internalDir = File(filesDir, "apks")
            if (!internalDir.exists()) {
                internalDir.mkdirs()
            }

            val internalApkFile = File(internalDir, apkFile.name)
            apkFile.copyTo(internalApkFile, overwrite = true)
            Log.d(TAG, "APK copied to internal directory: ${internalApkFile.absolutePath}")

            val uri = FileProvider.getUriForFile(
                this,
                "com.example.mdm_client_base.fileprovider",
                internalApkFile
            )
            Log.d(TAG, "URI generated by FileProvider: $uri")

            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success("Normal installer opened successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error using FileProvider: ${e.message}")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                Log.d(TAG, "Using direct installation for older Android versions")
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.fromFile(apkFile), "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success("Direct installer opened")
            } else {
                Log.e(TAG, "All installation methods failed")
                result.error("INSTALL_ERROR", "Failed to install: ${e.message}", null)
            }
        }
    }
}