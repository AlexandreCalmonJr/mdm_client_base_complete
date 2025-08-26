package com.example.mdm_client_base

import android.os.Bundle
import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.OnBackPressedCallback

class BlockActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Garante que a tela de bloqueio apareça mesmo com a tela do celular desligada
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN
        )

        setContentView(R.layout.activity_block)

        val messageView = findViewById<TextView>(R.id.block_message)
        val blockedApp = intent.getStringExtra("blocked_app") ?: "aplicativo"
        messageView.text = "O aplicativo '$blockedApp' foi bloqueado pelo administrador."

        // Configurar o callback para o botão voltar (versão moderna)
        setupBackPressedHandler()
    }

    // Impede o usuário de simplesmente apertar "voltar" para fechar a tela de bloqueio
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Não faz nada, mantendo a tela de bloqueio visível
    }
    
    // Método moderno para bloquear o botão voltar
    private fun setupBackPressedHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Não faz nada, mantendo a tela de bloqueio visível
                // Opcional: adicionar um delay e fechar automaticamente
                android.os.Handler(mainLooper).postDelayed({
                    finish()
                }, 2000) // Fecha após 2 segundos
            }
        })
    }

    // Impedir que o usuário minimize a atividade
    override fun onPause() {
        super.onPause()
        // Opcional: reabrir a atividade se ela for pausada
        // finish()
    }
}