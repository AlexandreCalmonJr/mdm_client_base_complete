package com.example.mdm_client_base

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AppBlockerService : AccessibilityService() {
    companion object {
        val blockList = mutableSetOf<String>()
        private const val TAG = "AppBlockerService"
        private const val MDM_PACKAGE_NAME = "com.example.mdm_client_base"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && event.packageName != null) {
            val packageName = event.packageName.toString()
            Log.d(TAG, "Evento de janela detectado para: $packageName")
            
            // Corrigir a lógica: bloquear se estiver na lista E não for o próprio app MDM
            if (blockList.contains(packageName) && packageName != MDM_PACKAGE_NAME) {
                Log.d(TAG, "Bloqueando aplicativo: $packageName")
                
                // Enviar para home
                performGlobalAction(GLOBAL_ACTION_HOME)
                
                // Mostrar tela de bloqueio
                val intent = Intent(this, BlockActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("blocked_app", packageName)
                }
                startActivity(intent)
            }
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Serviço de acessibilidade interrompido")
    }

    override fun onServiceConnected() {
        Log.d(TAG, "Serviço de acessibilidade conectado")
    }
}