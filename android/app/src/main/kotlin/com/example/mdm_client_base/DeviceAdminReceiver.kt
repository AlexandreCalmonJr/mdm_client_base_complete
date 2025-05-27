package com.example.mdm_client_base

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.annotation.NonNull

class DeviceAdminReceiver : DeviceAdminReceiver() {
    private val TAG = "DeviceAdminReceiver"

    override fun onEnabled(@NonNull context: Context, @NonNull intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Administrador de dispositivo habilitado")
        // Chamado quando o aplicativo é configurado como Device Owner ou Device Admin
        
        // Aqui você pode inicializar configurações específicas do MDM
        // Por exemplo, aplicar políticas padrão
    }

    override fun onDisabled(@NonNull context: Context, @NonNull intent: Intent) {
        super.onDisabled(context, intent)
        Log.d(TAG, "Administrador de dispositivo desabilitado")
        // Chamado quando o Device Owner é desativado
        
        // Aqui você pode limpar configurações ou reverter políticas
    }

    override fun onPasswordChanged(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordChanged(context, intent)
        Log.d(TAG, "Senha do dispositivo alterada")
        // Chamado quando a senha do dispositivo é alterada
    }

    override fun onPasswordFailed(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordFailed(context, intent)
        Log.d(TAG, "Falha na tentativa de senha")
        // Chamado quando há uma tentativa de senha incorreta
        
        // Aqui você pode implementar políticas de segurança, como:
        // - Contar tentativas falhadas
        // - Bloquear dispositivo após X tentativas
        // - Enviar alerta para servidor
    }

    override fun onPasswordSucceeded(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordSucceeded(context, intent)
        Log.d(TAG, "Senha inserida com sucesso")
        // Chamado quando a senha é inserida corretamente
    }

    override fun onLockTaskModeEntering(@NonNull context: Context, @NonNull intent: Intent, pkg: String) {
        super.onLockTaskModeEntering(context, intent, pkg)
        Log.d(TAG, "Entrando no modo de tarefa bloqueada: $pkg")
        // Chamado quando o dispositivo entra no modo kiosk/lock task
    }

    override fun onLockTaskModeExiting(@NonNull context: Context, @NonNull intent: Intent) {
        super.onLockTaskModeExiting(context, intent)
        Log.d(TAG, "Saindo do modo de tarefa bloqueada")
        // Chamado quando o dispositivo sai do modo kiosk/lock task
    }

    override fun onPasswordExpiring(@NonNull context: Context, @NonNull intent: Intent) {
        super.onPasswordExpiring(context, intent)
        Log.d(TAG, "Senha do dispositivo expirando")
        // Chamado quando a senha está prestes a expirar
        
        // Aqui você pode notificar o usuário para alterar a senha
    }

    override fun onProfileProvisioningComplete(@NonNull context: Context, @NonNull intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.d(TAG, "Provisionamento do perfil completo")
        // Chamado quando o provisionamento do perfil de trabalho é concluído
    }

    // Método para Device Owner - disponível a partir do Android 5.0
    override fun onNetworkLogsAvailable(@NonNull context: Context, @NonNull intent: Intent, batchToken: Long, networkLogsCount: Int) {
        super.onNetworkLogsAvailable(context, intent, batchToken, networkLogsCount)
        Log.d(TAG, "Logs de rede disponíveis - Token: $batchToken, Count: $networkLogsCount")
        // Chamado quando logs de rede estão disponíveis para coleta
    }

    // Método para Device Owner - disponível a partir do Android 7.0
    override fun onSecurityLogsAvailable(@NonNull context: Context, @NonNull intent: Intent) {
        super.onSecurityLogsAvailable(context, intent)
        Log.d(TAG, "Logs de segurança disponíveis")
        // Chamado quando logs de segurança estão disponíveis para coleta
    }
}