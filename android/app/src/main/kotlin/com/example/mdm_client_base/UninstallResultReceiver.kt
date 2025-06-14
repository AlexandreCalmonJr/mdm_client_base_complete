package com.example.mdm_client_base

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

class UninstallResultReceiver : BroadcastReceiver() {
    private val TAG = "UninstallResultReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        val status = intent?.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent?.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val packageName = intent?.getStringExtra("packageName")
        
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                Log.d(TAG, "Desinstalação bem-sucedida para: $packageName")
                // Notificar sucesso
            }
            PackageInstaller.STATUS_FAILURE -> {
                Log.e(TAG, "Falha na desinstalação de $packageName: $message")
                // Notificar falha
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                Log.e(TAG, "Desinstalação abortada para $packageName: $message")
                // Notificar aborto
            }
            PackageInstaller.STATUS_FAILURE_BLOCKED -> {
                Log.e(TAG, "Desinstalação bloqueada para $packageName: $message")
                // Notificar bloqueio
            }
            PackageInstaller.STATUS_FAILURE_CONFLICT -> {
                Log.e(TAG, "Conflito na desinstalação de $packageName: $message")
                // Notificar conflito
            }
            else -> {
                Log.w(TAG, "Status desconhecido para $packageName: $status, mensagem: $message")
            }
        }
    }
}