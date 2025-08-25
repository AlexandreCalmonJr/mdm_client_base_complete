package com.example.mdm_client_base

import android.Manifest
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import android.os.UserManager
import android.content.pm.ApplicationInfo


class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mdm_client_base/device_policy"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private val TAG = "MDM_MainActivity"
    private val REQUEST_LOCATION_PERMISSION = 1002
    private val REQUEST_NOTIFICATION_PERMISSION = 1003
    private var locationPermissionResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationChannel.createNotificationChannel(this)
        Log.d(TAG, "MainActivity onCreate")

        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_LOCATION_PERMISSION -> {
                val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                Log.d(TAG, "Resultado da permissão de localização: $granted")
                locationPermissionResult?.success(granted)
                locationPermissionResult = null
            }
            REQUEST_NOTIFICATION_PERMISSION -> {
                val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                Log.d(TAG, "Resultado da permissão de notificação: $granted")
                notificationPermissionResult?.success(granted)
                notificationPermissionResult = null
            }
        }
    }

    private fun applyInitialPolicies() {
        try {
            if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                Log.d(TAG, "Applying initial policies as Device Owner")
                val restrictions = listOf(
                    UserManager.DISALLOW_CONFIG_WIFI,
                    UserManager.DISALLOW_INSTALL_APPS,
                    UserManager.DISALLOW_UNINSTALL_APPS,
                    UserManager.DISALLOW_MODIFY_ACCOUNTS,
                    UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS,
                    UserManager.DISALLOW_FACTORY_RESET,
                    UserManager.DISALLOW_CONFIG_LOCATION
                )
                restrictions.forEach { restriction ->
                    devicePolicyManager.addUserRestriction(adminComponent, restriction)
                    Log.d(TAG, "Applied restriction: $restriction")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    devicePolicyManager.setLocationEnabled(adminComponent, true)
                    Log.d(TAG, "Location forced enabled")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    devicePolicyManager.setStatusBarDisabled(adminComponent, true)
                    Log.d(TAG, "Quick Settings panel disabled")
                }
                devicePolicyManager.setPasswordQuality(adminComponent, DevicePolicyManager.PASSWORD_QUALITY_ALPHANUMERIC)
                devicePolicyManager.setPasswordMinimumLength(adminComponent, 8)
                devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf(packageName))
                devicePolicyManager.setApplicationHidden(adminComponent, "com.android.settings", true)
                devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf("com.android.settings"), true)
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

    private fun isAccessibilityServiceEnabled(context: Context, service: Class<*>): Boolean {
        val expectedComponentName = ComponentName(context, service)
        val enabledServicesSetting = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return enabledServicesSetting?.contains(expectedComponentName.flattenToString()) ?: false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring MethodChannel: $CHANNEL")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Method called: ${call.method}")
            when (call.method) {
                "isAccessibilityServiceEnabled" -> {
                    val isEnabled = isAccessibilityServiceEnabled(this, AppBlockerService::class.java)
                    result.success(isEnabled)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "updateBlockList" -> {
                val appsToBlock = call.argument<List<String>>("packages")
                if (appsToBlock != null) {
                    try {
                        // Atualizar a lista de bloqueio no AppBlockerService
                        Log.d(TAG, "Atualizando lista de bloqueio no AppBlockerService: $appsToBlock")
                        AppBlockerService.blockList.clear()
                        AppBlockerService.blockList.addAll(appsToBlock)
                        Log.d(TAG, "Lista de bloqueio de acessibilidade atualizada: ${AppBlockerService.blockList}")

                        // Bloqueio via DevicePolicyManager para aplicativos do sistema, se for Device Owner
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            Log.d(TAG, "Aplicando bloqueio via DevicePolicyManager para aplicativos do sistema")
                            appsToBlock.forEach { packageName ->
                                try {
                                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                                    val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                                    if (isSystemApp) {
                                        devicePolicyManager.setApplicationHidden(adminComponent, packageName, true)
                                        devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf(packageName), true)
                                        Log.d(TAG, "Aplicativo do sistema bloqueado via DevicePolicyManager: $packageName")
                                    } else {
                                        Log.d(TAG, "Aplicativo não-sistema $packageName será bloqueado via serviço de acessibilidade")
                                    }
                                } catch (e: PackageManager.NameNotFoundException) {
                                    Log.e(TAG, "Pacote $packageName não encontrado: ${e.message}")
                                } catch (e: Exception) {
                                    Log.e(TAG, "Erro ao bloquear $packageName via DevicePolicyManager: ${e.message}")
                                }
                            }
                            // Desbloquear aplicativos que não estão na lista
                            val previouslyBlockedApps = AppBlockerService.blockList - appsToBlock.toSet()
                            Log.d(TAG, "Desbloqueando aplicativos via DevicePolicyManager: $previouslyBlockedApps")
                            previouslyBlockedApps.forEach { packageName ->
                                try {
                                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                                    val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                                    if (isSystemApp) {
                                        devicePolicyManager.setApplicationHidden(adminComponent, packageName, false)
                                        devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf(packageName), false)
                                        Log.d(TAG, "Aplicativo do sistema desbloqueado via DevicePolicyManager: $packageName")
                                    }
                                } catch (e: PackageManager.NameNotFoundException) {
                                    Log.e(TAG, "Pacote $packageName não encontrado: ${e.message}")
                                } catch (e: Exception) {
                                    Log.e(TAG, "Erro ao desbloquear $packageName via DevicePolicyManager: ${e.message}")
                                }
                            }
                        } else if (appsToBlock.contains("com.android.settings")) {
                            Log.w(TAG, "Não é possível bloquear com.android.settings sem Device Owner")
                            result.error(
                                "NOT_DEVICE_OWNER_SYSTEM_APP",
                                "O aplicativo precisa ser Device Owner para bloquear aplicativos do sistema como com.android.settings",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao atualizar lista de bloqueio: ${e.message}")
                        result.error("BLOCK_LIST_ERROR", "Erro ao atualizar lista de bloqueio: ${e.message}", null)
                    }
                } else {
                    Log.e(TAG, "Lista de pacotes é nula")
                    result.error("INVALID_ARGUMENT", "Lista de pacotes é nula", null)
                }
            }
                "isDeviceAdmin" -> {
                    val isAdminActive = devicePolicyManager.isAdminActive(adminComponent)
                    result.success(isAdminActive)
                }
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
                        Log.d(TAG, "Checking file: ${apkFile.absolutePath}, Exists: ${apkFile.exists()}, Readable: ${apkFile.canRead()}, Size: ${apkFile.length()}")
                        if (!apkFile.exists() || !apkFile.canRead()) {
                            Log.w(TAG, "APK file not found or not readable: $apkPath")
                            result.error("FILE_NOT_FOUND", "APK file not found or not readable", null)
                            return@setMethodCallHandler
                        }
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
                        Log.e(TAG, "Error installing APK: ${e.message}")
                        result.error("INSTALL_ERROR", "Error installing APK: ${e.message}", null)
                    }
                }
                 "restrictSettings" -> {
                    try {
                        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            Log.w(TAG, "Not Device Owner")
                            result.error("ADMIN_ERROR", "Application is not Device Owner", null)
                            return@setMethodCallHandler
                        }
                        // Garantir que restrictions seja um Map<String, Boolean>
                        val restrictions = call.argument<Map<String, Boolean>>("restrictions") ?: call.argument<Boolean>("restrict")?.let { restrict ->
                            mapOf(
                                "DISALLOW_CONFIG_WIFI" to restrict,
                                "DISALLOW_INSTALL_APPS" to restrict,
                                "DISALLOW_UNINSTALL_APPS" to restrict,
                                "DISALLOW_MODIFY_ACCOUNTS" to restrict,
                                "DISALLOW_CONFIG_MOBILE_NETWORKS" to restrict,
                                "DISALLOW_FACTORY_RESET" to restrict,
                                "DISALLOW_CONFIG_LOCATION" to restrict
                            )
                        }
                        if (restrictions == null) {
                            Log.w(TAG, "Restrictions map is null")
                            result.error("INVALID_INPUT", "Restrictions map is null", null)
                            return@setMethodCallHandler
                        }
                        val appliedRestrictions = mutableListOf<String>()
                        val clearedRestrictions = mutableListOf<String>()
                        val errors = mutableListOf<String>()
                        val currentStatus = mutableMapOf<String, Boolean>()
                        val restrictionMap = mapOf(
                            "DISALLOW_CONFIG_WIFI" to UserManager.DISALLOW_CONFIG_WIFI,
                            "DISALLOW_INSTALL_APPS" to UserManager.DISALLOW_INSTALL_APPS,
                            "DISALLOW_UNINSTALL_APPS" to UserManager.DISALLOW_UNINSTALL_APPS,
                            "DISALLOW_MODIFY_ACCOUNTS" to UserManager.DISALLOW_MODIFY_ACCOUNTS,
                            "DISALLOW_CONFIG_MOBILE_NETWORKS" to UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS,
                            "DISALLOW_FACTORY_RESET" to UserManager.DISALLOW_FACTORY_RESET,
                            "DISALLOW_CONFIG_LOCATION" to UserManager.DISALLOW_CONFIG_LOCATION
                        )
                        restrictionMap.forEach { (key, restriction) ->
                            val userRestrictions = devicePolicyManager.getUserRestrictions(adminComponent)
                            val isRestricted = userRestrictions.getBoolean(restriction, false)
                            currentStatus[key] = isRestricted
                            Log.d(TAG, "Restriction $key: currently ${if (isRestricted) "active" else "inactive"}")
                        }
                        // Iterar explicitamente sobre as entradas do mapa
                        restrictions.entries.forEach { (key, enable) ->
                            val restriction = restrictionMap[key]
                            if (restriction == null) {
                                Log.w(TAG, "Unsupported restriction: $key")
                                errors.add("Unsupported restriction: $key")
                                return@forEach
                            }
                            try {
                                if (enable) {
                                    devicePolicyManager.addUserRestriction(adminComponent, restriction)
                                    appliedRestrictions.add(key)
                                    Log.d(TAG, "Restriction applied: $key")
                                    if (key == "DISALLOW_CONFIG_LOCATION" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        devicePolicyManager.setLocationEnabled(adminComponent, true)
                                        Log.d(TAG, "Location forced enabled")
                                    }
                                } else {
                                    devicePolicyManager.clearUserRestriction(adminComponent, restriction)
                                    clearedRestrictions.add(key)
                                    Log.d(TAG, "Restriction cleared: $key")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error processing restriction $key: ${e.message}")
                                errors.add("Failed to process $key: ${e.message}")
                            }
                        }
                        try {
                            if (restrictions.values.any { it }) {
                                devicePolicyManager.setApplicationHidden(adminComponent, "com.android.settings", true)
                                devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf("com.android.settings"), true)
                                Log.d(TAG, "System settings app (com.android.settings) hidden and suspended")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    devicePolicyManager.setStatusBarDisabled(adminComponent, true)
                                    Log.d(TAG, "Quick Settings panel disabled")
                                }
                            } else {
                                devicePolicyManager.setApplicationHidden(adminComponent, "com.android.settings", false)
                                devicePolicyManager.setPackagesSuspended(adminComponent, arrayOf("com.android.settings"), false)
                                Log.d(TAG, "System settings app (com.android.settings) restored")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    devicePolicyManager.setStatusBarDisabled(adminComponent, false)
                                    Log.d(TAG, "Quick Settings panel restored")
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error managing settings app: ${e.message}")
                            errors.add("Error managing settings app: ${e.message}")
                        }
                        val resultMap = mapOf(
                            "applied" to appliedRestrictions,
                            "cleared" to clearedRestrictions,
                            "errors" to errors,
                            "currentStatus" to currentStatus
                        )
                        if (errors.isEmpty()) {
                            Log.d(TAG, "Restrictions updated successfully: $resultMap")
                            result.success(resultMap)
                        } else {
                            Log.e(TAG, "Some restrictions failed: $errors")
                            result.error("RESTRICT_SETTINGS_PARTIAL_ERROR", "Some restrictions failed: $errors", resultMap)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error restricting settings: ${e.message}")
                        result.error("RESTRICT_SETTINGS_ERROR", "Error restricting settings: ${e.message}", null)
                    }
                }
                "isDeviceOwnerOrProfileOwner" -> {
                    try {
                        val isAdmin = devicePolicyManager.isDeviceOwnerApp(packageName) || devicePolicyManager.isProfileOwnerApp(packageName)
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
                                call.argument<String>("explanation") ?: "Este aplicativo precisa de permissões de administrador para gerenciar o dispositivo.")
                        }
                        startActivity(intent)
                        Log.d(TAG, "Solicitação de administrador do dispositivo iniciada")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao solicitar permissão de administrador: ${e.message}")
                        result.error("REQUEST_ADMIN_ERROR", e.message, null)
                    }
                }
                "hasLocationPermission" -> {
                    try {
                        val fineLocation = ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        val coarseLocation = ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        val granted = fineLocation && coarseLocation
                        Log.d(TAG, "Permissão de localização verificada: $granted")
                        result.success(granted)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao verificar permissão de localização: ${e.message}")
                        result.error("LOCATION_PERMISSION_ERROR", e.message, null)
                    }
                }
                "requestLocationPermission" -> {
                    try {
                        locationPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            REQUEST_LOCATION_PERMISSION
                        )
                        Log.d(TAG, "Solicitação de permissão de localização iniciada")
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao solicitar permissão de localização: ${e.message}")
                        result.error("REQUEST_LOCATION_ERROR", e.message, null)
                    }
                }
                "hasNotificationPermission" -> {
                    try {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true // Notificações não requerem permissão explícita antes do Android 13
                        }
                        Log.d(TAG, "Permissão de notificação verificada: $granted")
                        result.success(granted)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao verificar permissão de notificação: ${e.message}")
                        result.error("NOTIFICATION_PERMISSION_ERROR", e.message, null)
                    }
                }
                "requestNotificationPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            notificationPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQUEST_NOTIFICATION_PERMISSION
                            )
                            Log.d(TAG, "Solicitação de permissão de notificação iniciada")
                        } else {
                            Log.d(TAG, "Permissão de notificação não necessária (pré-Android 13)")
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao solicitar permissão de notificação: ${e.message}")
                        result.error("REQUEST_NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "getWifiInfo" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val wifiInfo = wifiManager.connectionInfo
                        val ssid = wifiInfo.ssid?.replace("\"", "") ?: "N/A"
                        val bssid = wifiInfo.bssid?.takeIf { it != "02:00:00:00:00:00" } ?: "N/A"
                        val resultMap = mapOf(
                            "ssid" to ssid,
                            "bssid" to bssid,
                            "frequency" to wifiInfo.frequency,
                            "rssi" to wifiInfo.rssi
                        )
                        Log.d(TAG, "Wi-Fi info obtained: $resultMap")
                        result.success(resultMap)
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
                else -> {
                    Log.w(TAG, "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

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
            return apkFile.length() > 0 && apkFile.extension.equals("apk", ignoreCase = true)
        } catch (e: Exception) {
            Log.e(TAG, "Error validating APK file: ${e.message}")
            return false
        }
    }

    private fun installSilently(apkFile: File, result: MethodChannel.Result) {
        try {
            val packageInstaller = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            FileInputStream(apkFile).use { input ->
                session.openWrite("package", 0, apkFile.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            val intent = Intent(this, InstallResultReceiver::class.java).apply {
                action = "com.example.mdm_client_base.INSTALL_RESULT"
                putExtra("sessionId", sessionId)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(this, sessionId, intent, flags)

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
                                installNormally(apkFile, result)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing silent installation result: ${e.message}")
                        installNormally(apkFile, result)
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
            installNormally(apkFile, result)
        }
    }

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

            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", internalApkFile)
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