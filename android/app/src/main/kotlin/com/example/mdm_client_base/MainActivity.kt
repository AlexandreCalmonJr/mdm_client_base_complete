package com.example.mdm_client_base

import android.app.admin.DevicePolicyManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mdm_client_base/device_policy"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private val TAG = "MDM_MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationChannel.createNotificationChannel(this)
        Log.d(TAG, "MainActivity onCreate")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configurando MethodChannel: $CHANNEL")
        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Método chamado: ${call.method}")
            when (call.method) {
                "isDeviceOwnerOrProfileOwner" -> {
                    try {
                        val isAdmin = devicePolicyManager.isDeviceOwnerApp(packageName) ||
                                devicePolicyManager.isProfileOwnerApp(packageName)
                        Log.d(TAG, "isDeviceOwnerOrProfileOwner: $isAdmin")
                        result.success(isAdmin)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro em isDeviceOwnerOrProfileOwner: ${e.message}")
                        result.error("ADMIN_CHECK_ERROR", e.message, null)
                    }
                }
                "lockDevice" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.lockNow()
                            Log.d(TAG, "Dispositivo bloqueado")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Não é device owner")
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao bloquear: ${e.message}")
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "wipeData" -> {
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.wipeData(0)
                            Log.d(TAG, "Dados apagados")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Não é device owner")
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao apagar dados: ${e.message}")
                        result.error("WIPE_ERROR", e.message, null)
                    }
                }
                "installSystemApp" -> {
                    try {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath == null) {
                            Log.w(TAG, "Caminho do APK nulo")
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
                                Log.d(TAG, "Instalação iniciada: $apkPath")
                                result.success(true)
                            } else {
                                Log.w(TAG, "Arquivo APK não encontrado: $apkPath")
                                result.error("FILE_NOT_FOUND", "APK file not found", null)
                            }
                        } else {
                            Log.w(TAG, "Não é device owner")
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao instalar: ${e.message}")
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "uninstallPackage" -> {
                    try {
                        val packageNameArg = call.argument<String>("packageName")
                        if (packageNameArg == null) {
                            Log.w(TAG, "Nome do pacote nulo")
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName)) {
                            val packageInstaller = packageManager.packageInstaller
                            val intent = Intent(this, UninstallResultReceiver::class.java).apply {
                                action = "com.example.mdm_client_base.UNINSTALL_RESULT"
                                putExtra("packageName", packageNameArg)
                            }
                            val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
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
                            Log.d(TAG, "Desinstalação iniciada: $packageNameArg")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Não é device owner")
                            result.error("NOT_ADMIN", "App is not device owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao desinstalar: ${e.message}")
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
                        Log.d(TAG, "Solicitação de admin iniciada")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao solicitar admin: ${e.message}")
                        result.error("REQUEST_ADMIN_ERROR", e.message, null)
                    }
                }
                else -> {
                    Log.w(TAG, "Método não implementado: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }
}