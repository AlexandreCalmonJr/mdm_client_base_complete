package com.example.mdm_client_base

import android.app.admin.DevicePolicyManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.UserManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

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
                "disableApp" -> {
                    val packageName = call.argument<String>("packageName")
                    try {
                        if (packageName == null) {
                            result.error("INVALID_PACKAGE", "Nome do pacote é nulo", null)
                            return@setMethodCallHandler
                        }
                        
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName) || 
                            devicePolicyManager.isProfileOwnerApp(this.packageName)) {
                            
                            // Desabilita o aplicativo
                            devicePolicyManager.setApplicationHidden(adminComponent, packageName, true)
                            Log.d(TAG, "Aplicativo $packageName desabilitado")
                            result.success("Aplicativo desabilitado com sucesso")
                        } else {
                            Log.w(TAG, "Não é device owner ou profile owner")
                            result.error("NOT_ADMIN", "Permissões de administrador necessárias", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao desabilitar aplicativo: ${e.message}")
                        result.error("DISABLE_ERROR", "Erro ao desabilitar aplicativo: ${e.message}", null)
                    }
                }
                
                "installSystemApp" -> {
                    val apkPath = call.argument<String>("apkPath")
                    try {
                        if (apkPath == null) {
                            Log.w(TAG, "Caminho do APK nulo")
                            result.error("INVALID_PATH", "Caminho do APK é nulo", null)
                            return@setMethodCallHandler
                        }
                        
                        if (devicePolicyManager.isDeviceOwnerApp(packageName) || 
                            devicePolicyManager.isProfileOwnerApp(packageName)) {
                            
                            val apkFile = File(apkPath)
                            if (!apkFile.exists()) {
                                Log.w(TAG, "Arquivo APK não encontrado: $apkPath")
                                result.error("FILE_NOT_FOUND", "Arquivo APK não encontrado", null)
                                return@setMethodCallHandler
                            }

                            // Usar PackageInstaller para instalação silenciosa
                            val packageInstaller = packageManager.packageInstaller
                            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                            val sessionId = packageInstaller.createSession(params)
                            val session = packageInstaller.openSession(sessionId)

                            // Copiar o APK para a sessão
                            val inputStream = FileInputStream(apkFile)
                            val outputStream = session.openWrite("package", 0, apkFile.length())
                            inputStream.copyTo(outputStream)
                            session.fsync(outputStream)
                            inputStream.close()
                            outputStream.close()

                            // Confirmar a instalação usando IntentSenderReceiver
                            session.commit(IntentSenderReceiver.createIntentSender(this, sessionId))
                            session.close()

                            Log.d(TAG, "Instalação iniciada: $apkPath")
                            result.success("Instalação iniciada com sucesso")
                        } else {
                            result.error("ADMIN_ERROR", "Aplicativo não é administrador de dispositivo", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao instalar APK: ${e.message}")
                        result.error("INSTALL_ERROR", "Erro ao instalar APK: ${e.message}", null)
                    }
                }
                
                "restrictSettings" -> {
                    val restrict = call.argument<Boolean>("restrict") ?: false
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName) || 
                            devicePolicyManager.isProfileOwnerApp(packageName)) {
                            
                            if (restrict) {
                                // Bloquear configurações
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_BLUETOOTH)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                                Log.d(TAG, "Configurações restritas")
                            } else {
                                // Desbloquear configurações
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_BLUETOOTH)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                                Log.d(TAG, "Configurações liberadas")
                            }
                            result.success("Configurações atualizadas com sucesso")
                        } else {
                            result.error("ADMIN_ERROR", "Aplicativo não é administrador de dispositivo", null)
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
                        val bssid = wifiInfo.bssid ?: "N/A"
                        val result_map = mapOf(
                            "ssid" to ssid,
                            "bssid" to bssid,
                            "frequency" to wifiInfo.frequency,
                            "rssi" to wifiInfo.rssi
                        )
                        Log.d(TAG, "Informações Wi-Fi obtidas: $result_map")
                        result.success(result_map)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter informações de Wi-Fi: ${e.message}")
                        result.error("WIFI_INFO_ERROR", "Erro ao obter informações de Wi-Fi: ${e.message}", null)
                    }
                }
                
                "getMacAddress" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val wifiInfo = wifiManager.connectionInfo
                        val macAddress = wifiInfo.macAddress ?: "02:00:00:00:00:00"
                        Log.d(TAG, "MAC Address obtido: $macAddress")
                        result.success(macAddress)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter MAC Address: ${e.message}")
                        result.error("MAC_ADDRESS_ERROR", "Erro ao obter MAC Address: ${e.message}", null)
                    }
                }
                
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
                        if (devicePolicyManager.isDeviceOwnerApp(packageName) ||
                            devicePolicyManager.isProfileOwnerApp(packageName)) {
                            devicePolicyManager.lockNow()
                            Log.d(TAG, "Dispositivo bloqueado")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Não é device owner ou profile owner")
                            result.error("NOT_ADMIN", "App não é administrador do dispositivo", null)
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
                            result.error("NOT_ADMIN", "App não é device owner", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao apagar dados: ${e.message}")
                        result.error("WIPE_ERROR", e.message, null)
                    }
                }
                
                "uninstallPackage" -> {
                    try {
                        val packageNameArg = call.argument<String>("packageName")
                        if (packageNameArg == null) {
                            Log.w(TAG, "Nome do pacote nulo")
                            result.error("INVALID_PACKAGE", "Nome do pacote é nulo", null)
                            return@setMethodCallHandler
                        }
                        
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName) ||
                            devicePolicyManager.isProfileOwnerApp(this.packageName)) {
                            
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
                            Log.w(TAG, "Não é device owner ou profile owner")
                            result.error("NOT_ADMIN", "App não é administrador do dispositivo", null)
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
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, 
                                call.argument<String>("explanation") ?: "Este aplicativo precisa de permissões de administrador para funcionar corretamente.")
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