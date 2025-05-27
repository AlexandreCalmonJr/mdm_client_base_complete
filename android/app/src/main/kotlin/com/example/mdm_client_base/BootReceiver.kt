package com.example.mdm_client_base // Pacote está correto

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log // É bom adicionar Log para depuração

class BootReceiver : BroadcastReceiver() { // Sintaxe Kotlin para declaração de classe e herança

    override fun onReceive(context: Context, intent: Intent?) { // Sintaxe Kotlin para sobrescrever método, 'intent' pode ser nulo
        // É uma boa prática verificar se o intent e a action não são nulos
        if (intent?.action != null) {
            Log.d("BootReceiver", "Ação recebida: ${intent.action}") // Log para depurar

            if (Intent.ACTION_BOOT_COMPLETED == intent.action ||
                "android.intent.action.QUICKBOOT_POWERON" == intent.action) {

                Log.d("BootReceiver", "Boot completed ou Quickboot poweron recebido. Iniciando MainActivity.")

                // Intenção para iniciar a MainActivity
                val activityIntent = Intent(context, MainActivity::class.java) // Use ::class.java em Kotlin
                activityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                
                try {
                    context.startActivity(activityIntent)
                } catch (e: Exception) {
                    // Logar qualquer exceção ao tentar iniciar a Activity
                    Log.e("BootReceiver", "Erro ao iniciar MainActivity: ${e.message}", e)
                }
            }
        } else {
            Log.w("BootReceiver", "Intent ou action nulo recebido.")
        }
    }
}
