package com.example.mdm_client_base

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mdm_client_base/device_policy"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private val TAG = "MDM_MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity onCreate")

        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)

        // O ponto de entrada principal para o provisionamento.
        // A lógica agora é extrair os dados, não iniciar um novo fluxo.
        handleProvisioningIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring MethodChannel: $CHANNEL")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Novo método para o Flutter solicitar os dados do provisionamento
                "getProvisioningExtras" -> {
                    try {
                        val extras = getProvisioningDataFromIntent(intent)
                        if (extras != null) {
                            Log.d(TAG, "Enviando dados de provisionamento para o Flutter: $extras")
                            result.success(extras)
                        } else {
                            Log.w(TAG, "Nenhum dado de provisionamento encontrado na Intent.")
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao obter dados de provisionamento: ${e.message}")
                        result.error("EXTRAS_ERROR", "Erro ao obter dados de provisionamento", null)
                    }
                }
                // Seus outros métodos do MethodChannel continuam aqui...
                "isDeviceOwnerOrProfileOwner" -> {
                    val isAdmin = devicePolicyManager.isDeviceOwnerApp(packageName)
                    result.success(isAdmin)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    /**
     * Esta função é chamada quando a Activity é iniciada ou quando uma nova Intent
     * é entregue a uma instância existente (launchMode="singleTop").
     */
    private fun handleProvisioningIntent(intent: Intent?) {
        if (intent?.action != DevicePolicyManager.ACTION_PROVISION_MANAGED_DEVICE) {
            Log.d(TAG, "Intent não é de provisionamento. Ação: ${intent?.action}")
            return
        }

        Log.d(TAG, "Intent de provisionamento recebida!")
        
        // Após o provisionamento, o sistema define o app como Device Owner.
        // Verificamos se isso aconteceu.
        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
            Log.i(TAG, "Aplicativo confirmado como Device Owner.")
            applyInitialPolicies()
            
            // Os dados do QR Code estão no ADMIN_EXTRAS_BUNDLE.
            // O Flutter irá solicitar esses dados através do MethodChannel `getProvisioningExtras`.
            // Não precisamos fazer nada aqui, pois a UI do Flutter cuidará disso.

        } else {
            Log.e(TAG, "Provisionamento iniciado, mas o aplicativo não é o Device Owner.")
            // Notificar o Flutter sobre a falha.
             flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("provisioningFailure", mapOf("error" to "App is not device owner after provisioning"))
            }
        }
    }

    /**
     * Extrai o bundle de extras do QR Code da Intent de provisionamento.
     */
    private fun getProvisioningDataFromIntent(intent: Intent?): Map<String, String>? {
        val extrasBundle = intent?.getParcelableExtra<Bundle>(DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE)
        if (extrasBundle == null) {
            Log.w(TAG, "ADMIN_EXTRAS_BUNDLE não encontrado na Intent.")
            return null
        }
        
        // Converte o Bundle do Android para um Map<String, String> para o Flutter
        val extrasMap = mutableMapOf<String, String>()
        for (key in extrasBundle.keySet()) {
            extrasBundle.getString(key)?.let { value ->
                extrasMap[key] = value
            }
        }
        return extrasMap.ifEmpty { null }
    }
    
    /**
     * Aplica as políticas iniciais logo após o provisionamento ser bem-sucedido.
     */
    private fun applyInitialPolicies() {
        try {
            Log.d(TAG, "Aplicando políticas iniciais...")
            // Exemplo: desabilitar a câmera
            devicePolicyManager.setCameraDisabled(adminComponent, true)
            // Exemplo: definir uma política de senha
            devicePolicyManager.setPasswordQuality(adminComponent, DevicePolicyManager.PASSWORD_QUALITY_ALPHANUMERIC)
            
            Log.i(TAG, "Políticas iniciais aplicadas com sucesso.")
        } catch (e: SecurityException) {
            Log.e(TAG, "Falha de segurança ao aplicar políticas", e)
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao aplicar políticas iniciais", e)
        }
    }
}
