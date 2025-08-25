package com.example.mdm_client_base

import android.os.Bundle
import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class BlockActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Garante que a tela de bloqueio apareça mesmo com a tela do celular desligada
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        setContentView(R.layout.activity_block)

        val messageView = findViewById<TextView>(R.id.block_message)
        messageView.text = "Este aplicativo foi bloqueado pelo administrador."
    }

    // Impede o usuário de simplesmente apertar "voltar" para fechar a tela de bloqueio
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Não faz nada, mantendo a tela de bloqueio visível
        // Para versões mais novas do Android, use OnBackPressedDispatcher
    }
    
    // Método alternativo mais moderno (para API 33+)
    private fun setupBackPressedHandler() {
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Não faz nada, mantendo a tela de bloqueio visível
            }
        })
    }
}