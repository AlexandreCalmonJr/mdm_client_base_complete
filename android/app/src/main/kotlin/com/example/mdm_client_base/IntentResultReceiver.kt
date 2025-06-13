package com.example.mdm_client_base

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

class InstallResultReceiver : BroadcastReceiver() {
    private val TAG = "InstallResultReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Recebido resultado da instalação")
        
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val sessionId = intent.getIntExtra("sessionId", -1)
        
        Log.d(TAG, "Status: $status, Message: $message, SessionId: $sessionId")
        
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "Instalação bem-sucedida")
                NotificationChannel.showNotification(
                    context, 
                    "Instalação Concluída", 
                    "APK instalado com sucesso"
                )
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> {
                Log.w(TAG, "Instalação cancelada pelo usuário")
                NotificationChannel.showNotification(
                    context, 
                    "Instalação Cancelada", 
                    "A instalação foi cancelada"
                )
            }
            PackageInstaller.STATUS_FAILURE_BLOCKED -> {
                Log.e(TAG, "Instalação bloqueada pelo sistema")
                NotificationChannel.showNotification(
                    context, 
                    "Instalação Bloqueada", 
                    "A instalação foi bloqueada pelo sistema"
                )
            }
            PackageInstaller.STATUS_FAILURE_CONFLICT -> {
                Log.e(TAG, "Conflito na instalação")
                NotificationChannel.showNotification(
                    context, 
                    "Erro de Instalação", 
                    "Conflito com versão existente"
                )
            }
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> {
                Log.e(TAG, "APK incompatível")
                NotificationChannel.showNotification(
                    context, 
                    "APK Incompatível", 
                    "O APK não é compatível com este dispositivo"
                )
            }
            PackageInstaller.STATUS_FAILURE_INVALID -> {
                Log.e(TAG, "APK inválido")
                NotificationChannel.showNotification(
                    context, 
                    "APK Inválido", 
                    "O arquivo APK está corrompido ou inválido"
                )
            }
            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                Log.e(TAG, "Espaço insuficiente")
                NotificationChannel.showNotification(
                    context, 
                    "Espaço Insuficiente", 
                    "Não há espaço suficiente para instalar o APK"
                )
            }
            else -> {
                Log.e(TAG, "Falha desconhecida na instalação: Status=$status, Message=$message")
                NotificationChannel.showNotification(
                    context, 
                    "Erro na Instalação", 
                    message ?: "Erro desconhecido na instalação"
                )
            }
        }
    }
}