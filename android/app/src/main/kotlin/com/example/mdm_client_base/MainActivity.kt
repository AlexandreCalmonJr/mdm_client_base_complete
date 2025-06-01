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
import android.util.Log
import androidx.core.content.FileProvider
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

        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

        // Lidar com provisionamento
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
            Log.d(TAG, "Provisionamento detectado: $action")
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
                Log.d(TAG, "Iniciando provisionamento como Device Owner")
            } catch (e: Exception) {
                Log.e(TAG, "Erro ao iniciar provisionamento: ${e.message}", e)
                notifyProvisioningFailure("Erro ao iniciar provisionamento: ${e.message}")
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == RESULT_OK) {
                Log.d(TAG, "Provisionamento concluído com sucesso")
                applyInitialPolicies()
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("provisioningComplete", mapOf("status" to "success"))
                }
            } else {
                Log.e(TAG, "Provisionamento falhou, resultCode: $resultCode")
                notifyProvisioningFailure("Provisionamento falhou, código: $resultCode")
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("provisioningComplete", mapOf("status" to "failed", "error" to "Código: $resultCode"))
                }
            }
        }
    }

    private fun applyInitialPolicies() {
        try {
            if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                Log.d(TAG, "Aplicando políticas iniciais como Device Owner")
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_BLUETOOTH)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_USB_FILE_TRANSFER)
                devicePolicyManager.setPasswordQuality(adminComponent, DevicePolicyManager.PASSWORD_QUALITY_ALPHANUMERIC)
                devicePolicyManager.setPasswordMinimumLength(adminComponent, 8)
                devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf(packageName))
                Log.d(TAG, "Políticas iniciais aplicadas com sucesso")
            } else {
                Log.w(TAG, "Não é Device Owner, políticas não aplicadas")
                notifyPolicyFailure("Aplicativo não é Device Owner")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao aplicar políticas iniciais: ${e.message}", e)
            notifyPolicyFailure("Erro ao aplicar políticas: ${e.message}")
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
        Log.d(TAG, "Configurando MethodChannel: $CHANNEL")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Método chamado: ${call.method}")
            when (call.method) {
                "getSdkVersion" -> {
                    try {
                        val sdkVersion = Build.VERSION.SDK_INT
                        Log.d(TAG, "SDK Version: $sdkVersion")
                        result.success(sdkVersion)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter versão do SDK: ${e.message}")
                        result.error("SDK_VERSION_ERROR", "Erro ao obter versão do SDK: ${e.message}", null)
                    }
                }
                "disableApp" -> {
                    val packageName = call.argument<String>("packageName")
                    try {
                        if (packageName == null) {
                            result.error("INVALID_PACKAGE", "Nome do pacote é nulo", null)
                            return@setMethodCallHandler
                        }
                        if (devicePolicyManager.isDeviceOwnerApp(this.packageName)) {
                            devicePolicyManager.setApplicationHidden(adminComponent, packageName, true)
                            Log.d(TAG, "Aplicativo $packageName desabilitado")
                            result.success("Aplicativo desabilitado com sucesso")
                        } else {
                            Log.w(TAG, "Não é Device Owner")
                            result.error("NOT_ADMIN", "Permissões de Device Owner necessárias", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao desabilitar aplicativo: ${e.message}")
                        result.error("DISABLE_ERROR", "Erro ao desabilitar aplicativo: ${e.message}", null)
                    }
                }
                "installSystemApp" -> {
    val apkPath = call.argument<String>("apkPath")
    Log.d(TAG, "Tentando instalar APK: $apkPath")
    try {
        if (apkPath == null) {
            Log.w(TAG, "Caminho do APK nulo")
            result.error("INVALID_PATH", "Caminho do APK é nulo", null)
            return@setMethodCallHandler
        }
        
        val apkFile = File(apkPath)
        Log.d(TAG, "Verificando arquivo: ${apkFile.absolutePath}")
        Log.d(TAG, "Arquivo existe: ${apkFile.exists()}")
        Log.d(TAG, "Tamanho do arquivo: ${if (apkFile.exists()) apkFile.length() else "N/A"}")
        
        if (!apkFile.exists()) {
            Log.w(TAG, "Arquivo APK não encontrado: $apkPath")
            result.error("FILE_NOT_FOUND", "Arquivo APK não encontrado em: $apkPath", null)
            return@setMethodCallHandler
        }
        
        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
            Log.d(TAG, "Instalação silenciosa como Device Owner")
            val packageInstaller = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            // Copiar APK para a sessão
            FileInputStream(apkFile).use { input ->
                session.openWrite("package", 0, apkFile.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            // CORREÇÃO: Intent explícito e PendingIntent com flags corretas para Android 14+
            val intent = Intent(this, InstallResultReceiver::class.java).apply {
                action = "com.example.mdm_client_base.INSTALL_RESULT"
                putExtra("sessionId", sessionId)
            }
            
            // Flags corretas baseadas na versão do Android
            val flags = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> // Android 14+ (API 34+)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> // Android 12+ (API 31+)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                else -> // Android 11 e anteriores
                    PendingIntent.FLAG_UPDATE_CURRENT
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                sessionId,
                intent,
                flags
            )

            // Registrar receiver para capturar o resultado
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    try {
                        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                        Log.d(TAG, "Resultado da instalação - Status: $status, Message: $message")
                        
                        when (status) {
                            PackageInstaller.STATUS_SUCCESS -> {
                                Log.d(TAG, "Instalação bem-sucedida: $apkPath")
                                result.success("APK instalado com sucesso")
                            }
                            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                                Log.e(TAG, "Instalação abortada pelo usuário")
                                result.error("INSTALL_ABORTED", "Instalação cancelada pelo usuário", null)
                            }
                            PackageInstaller.STATUS_FAILURE_BLOCKED -> {
                                Log.e(TAG, "Instalação bloqueada")
                                result.error("INSTALL_BLOCKED", "Instalação bloqueada pelo sistema", null)
                            }
                            PackageInstaller.STATUS_FAILURE_CONFLICT -> {
                                Log.e(TAG, "Conflito na instalação")
                                result.error("INSTALL_CONFLICT", "Conflito com versão existente", null)
                            }
                            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> {
                                Log.e(TAG, "APK incompatível")
                                result.error("INSTALL_INCOMPATIBLE", "APK incompatível com o dispositivo", null)
                            }
                            PackageInstaller.STATUS_FAILURE_INVALID -> {
                                Log.e(TAG, "APK inválido")
                                result.error("INSTALL_INVALID", "APK inválido ou corrompido", null)
                            }
                            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                                Log.e(TAG, "Espaço insuficiente")
                                result.error("INSTALL_STORAGE", "Espaço de armazenamento insuficiente", null)
                            }
                            else -> {
                                Log.e(TAG, "Falha na instalação: Status=$status, Message=$message")
                                result.error("INSTALL_FAILED", "Falha na instalação - Status: $status, Mensagem: $message", null)
                            }
                        }
                        
                        try {
                            context.unregisterReceiver(this)
                        } catch (ignored: Exception) {
                            Log.w(TAG, "Receiver já foi desregistrado")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao processar resultado: ${e.message}")
                        result.error("INSTALL_ERROR", "Erro ao processar resultado: ${e.message}", null)
                        try {
                            context.unregisterReceiver(this)
                        } catch (ignored: Exception) {}
                    }
                }
            }

            val filter = IntentFilter("com.example.mdm_client_base.INSTALL_RESULT")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13+
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
            
            session.commit(pendingIntent.intentSender)
            session.close()
            Log.d(TAG, "Sessão de instalação enviada com ID: $sessionId")
            
        } else {
            Log.d(TAG, "Não é Device Owner, usando instalador padrão")
            
            // Tentar copiar o arquivo para o diretório interno da aplicação primeiro
            try {
                val internalDir = File(filesDir, "apks")
                if (!internalDir.exists()) {
                    internalDir.mkdirs()
                }
                
                val internalApkFile = File(internalDir, apkFile.name)
                apkFile.copyTo(internalApkFile, overwrite = true)
                Log.d(TAG, "APK copiado para diretório interno: ${internalApkFile.absolutePath}")
                
                val uri = FileProvider.getUriForFile(
                    this,
                    "com.example.mdm_client_base.fileprovider",
                    internalApkFile
                )
                Log.d(TAG, "URI gerada pelo FileProvider: $uri")
                
                val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success("Instalador padrão aberto com sucesso")
                
            } catch (e: Exception) {
                Log.e(TAG, "Erro ao usar FileProvider: ${e.message}")
                
                // Fallback para instalação direta (Android < 7.0)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                    Log.d(TAG, "Usando instalação direta para versões antigas do Android")
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(Uri.fromFile(apkFile), "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success("Instalador direto aberto")
                } else {
                    Log.e(TAG, "Falha em todos os métodos de instalação")
                    result.error(
                        "INSTALL_ERROR", 
                        "Falha ao instalar: ${e.message}", 
                        null
                    )
                }
            }
        }
    } catch (e: Exception) {
        Log.e(TAG, "Erro geral ao instalar APK: ${e.message}", e)
        result.error("INSTALL_ERROR", "Erro ao instalar APK: ${e.message}", null)
    }
}
                "restrictSettings" -> {
                    val restrict = call.argument<Boolean>("restrict") ?: false
                    try {
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            if (restrict) {
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_BLUETOOTH)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
                                devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_USB_FILE_TRANSFER)
                                Log.d(TAG, "Configurações restritas")
                            } else {
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_BLUETOOTH)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_INSTALL_APPS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_MODIFY_ACCOUNTS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
                                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_USB_FILE_TRANSFER)
                                Log.d(TAG, "Configurações liberadas")
                            }
                            result.success("Configurações atualizadas com sucesso")
                        } else {
                            result.error("ADMIN_ERROR", "Aplicativo não é Device Owner", null)
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
                        Log.d(TAG, "Informações Wi-Fi obtidas: $result_map")
                        result.success(result_map)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter informação de Wi-Fi: ${e.message}")
                        result.error("WIFI_INFO_ERROR", "Erro ao obter informação de Wi-Fi: ${e.message}", null)
                    }
                }
                "getMacAddress" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val wifiInfo = wifiManager.connectionInfo
                        val macAddress = wifiInfo.bssid?.takeIf { it != "02:00:00:00:00:00" } ?: "N/A"
                        Log.d(TAG, "BSSID obtido: $macAddress")
                        result.success(macAddress)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter BSSID: ${e.message}")
                        result.error("MAC_ADDRESS_ERROR", "Erro ao obter BSSID: ${e.message}", null)
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
                        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
                            devicePolicyManager.lockNow()
                            Log.d(TAG, "Dispositivo bloqueado")
                            result.success(true)
                        } else {
                            Log.w(TAG, "Não é Device Owner")
                            result.error("NOT_ADMIN", "App não é Device Owner", null)
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
                            Log.w(TAG, "Não é Device Owner")
                            result.error("NOT_ADMIN", "App não é Device Owner", null)
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
                            Log.w(TAG, "Não é Device Owner")
                            result.error("NOT_ADMIN", "App não é Device Owner", null)
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