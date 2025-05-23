package com.example.mdm_client_base

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull

class DeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(@NonNull context: Context, @NonNull intent: Intent) {
        // Chamado quando o aplicativo é configurado como Device Owner
    }

    override fun onDisabled(@NonNull context: Context, @NonNull intent: Intent) {
        // Chamado quando o Device Owner é desativado
    }
}