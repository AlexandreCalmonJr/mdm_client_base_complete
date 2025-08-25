package com.example.mdm_client_base

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AppBlockerService : AccessibilityService() {
    companion object {
        val blockList = mutableSetOf<String>()
        private const val TAG = "AppBlockerService"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && event.packageName != null) {
            val packageName = event.packageName.toString()
            Log.d(TAG, "Evento de janela detectado para: $packageName")
            if (blockList.contains(packageName) && packageName != packageName) {
                Log.d(TAG, "Bloqueando aplicativo: $packageName")
                performGlobalAction(GLOBAL_ACTION_HOME)
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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