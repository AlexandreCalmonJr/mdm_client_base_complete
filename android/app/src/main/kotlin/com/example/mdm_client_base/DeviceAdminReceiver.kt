package com.example.mdm_client_base

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class DeviceAdminReceiver : DeviceAdminReceiver() {
    private val TAG = "DeviceAdminReceiver"
    private val CHANNEL = "com.example.mdm_client_base/device_policy"

    override fun onEnabled(@NonNull context: Context, @NonNull intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Administrador de dispositivo habilitado")
    }

    override fun onDisabled(@NonNull context: Context, @NonNull intent: Intent) {
        super.onDisabled(context, intent)
        Log.d(TAG, "Administrador de dispositivo desabilitado")
    }

    override fun onPasswordChanged(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordChanged(context, intent)
        Log.d(TAG, "Senha do dispositivo alterada")
    }

    override fun onPasswordFailed(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordFailed(context, intent)
        Log.d(TAG, "Falha na tentativa de senha")
    }

    override fun onPasswordSucceeded(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordSucceeded(context, intent)
        Log.d(TAG, "Senha inserida com sucesso")
    }

    override fun onLockTaskModeEntering(@NonNull context: Context, @NonNull intent: Intent, pkg: String) {
        super.onLockTaskModeEntering(context, intent, pkg)
        Log.d(TAG, "Entrando no modo de tarefa bloqueada: $pkg")
    }

    override fun onLockTaskModeExiting(@NonNull context: Context, @NonNull intent: Intent) {
        super.onLockTaskModeExiting(context, intent)
        Log.d(TAG, "Saindo do modo de tarefa bloqueada")
    }

    override fun onPasswordExpiring(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordExpiring(context, intent)
        Log.d(TAG, "Senha do dispositivo expirando")
    }

    override fun onProfileProvisioningComplete(@NonNull context: Context, @NonNull intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.d(TAG, "Provisionamento do perfil completo")
        // Notificar Flutter sobre a conclusão do provisionamento
        try {
            val flutterEngine = FlutterEngine(context)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod("provisioningComplete", null)
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao notificar Flutter sobre provisionamento: ${e.message}", e)
        }
    }

    override fun onNetworkLogsAvailable(@NonNull context: Context, @NonNull intent: Intent, batchToken: Long, networkLogsCount: Int) {
        super.onNetworkLogsAvailable(context, intent, batchToken, networkLogsCount)
        Log.d(TAG, "Logs de rede disponíveis - Token: $batchToken, Count: $networkLogsCount")
    }

    override fun onSecurityLogsAvailable(@NonNull context: Context, @NonNull intent: Intent) {
        super.onSecurityLogsAvailable(context, intent)
        Log.d(TAG, "Logs de segurança disponíveis")
    }
}