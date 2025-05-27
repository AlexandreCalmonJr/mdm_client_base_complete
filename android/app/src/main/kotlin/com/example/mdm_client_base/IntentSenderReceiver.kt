package com.example.mdm_client_base

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.util.Log

class IntentSenderReceiver : BroadcastReceiver() {
    companion object {
        fun createIntentSender(context: Context, sessionId: Int): IntentSender {
            val intent = Intent(context, IntentSenderReceiver::class.java).apply {
                action = "com.example.mdm_client_base.INSTALL_RESULT"
                putExtra("sessionId", sessionId)
            }
            val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            return pendingIntent.intentSender
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val sessionId = intent?.getIntExtra("sessionId", -1) ?: -1
        Log.d("IntentSenderReceiver", "Resultado da instalação recebido para sessão: $sessionId")
        
        // Aqui você pode processar o resultado da instalação
        // Por exemplo, notificar o Flutter sobre o resultado
    }
}