package com.example.mdm_client_base

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

class InstallResultReceiver : BroadcastReceiver() {
    private val TAG = "InstallResultReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        val status = intent?.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent?.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                Log.d(TAG, "Instalação bem-sucedida")
                // Notificar sucesso
            }
            PackageInstaller.STATUS_FAILURE -> {
                Log.e(TAG, "Falha na instalação: $message")
                // Notificar falha
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                Log.e(TAG, "Instalação abortada: $message")
                // Notificar aborto
            }
            PackageInstaller.STATUS_FAILURE_BLOCKED -> {
                Log.e(TAG, "Instalação bloqueada: $message")
                // Notificar bloqueio
            }
            PackageInstaller.STATUS_FAILURE_CONFLICT -> {
                Log.e(TAG, "Conflito na instalação: $message")
                // Notificar conflito
            }
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> {
                Log.e(TAG, "Instalação incompatível: $message")
                // Notificar incompatibilidade
            }
            PackageInstaller.STATUS_FAILURE_INVALID -> {
                Log.e(TAG, "Instalação inválida: $message")
                // Notificar invalidez
            }
            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                Log.e(TAG, "Falha de armazenamento na instalação: $message")
                // Notificar problema de armazenamento
            }
            else -> {
                Log.w(TAG, "Status desconhecido: $status, mensagem: $message")
            }
        }
    }
}