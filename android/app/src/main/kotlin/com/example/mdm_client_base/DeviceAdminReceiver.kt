package com.example.mdm_client_base

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

class DeviceAdminReceiver : DeviceAdminReceiver() {
    private val TAG = "DeviceAdminReceiver"

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Device admin enabled")
    }
    
    /**
     * Chamado quando o provisionamento de um dispositivo ou perfil é concluído.
     * Este é o melhor lugar para finalizar a configuração inicial.
     */
    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.d(TAG, "Profile provisioning complete.")

        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(context.applicationContext, DeviceAdminReceiver::class.java)

        // Habilita a atividade principal do aplicativo, que pode ter sido desabilitada
        // durante o provisionamento.
        val packageManager = context.packageManager
        packageManager.setComponentEnabledSetting(
            ComponentName(context, MainActivity::class.java),
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            android.content.pm.PackageManager.DONT_KILL_APP
        )

        // Define este aplicativo como o Afiliado, permitindo acesso a logs e outras APIs
        val affiliateId = "HapvidaMDM" // Escolha um ID único
        dpm.setAffiliationIds(adminComponent, setOf(affiliateId))

        // Inicia a MainActivity, que irá ler os extras e se comunicar com o Flutter
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Você pode passar os dados do provisionamento para a MainActivity se necessário,
            // mas o ideal é que ela mesma leia da Intent original.
        }
        context.startActivity(launchIntent)
        Log.d(TAG, "MainActivity launched after provisioning.")
    }
}
