package com.example.mdm_client_base

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log

object NotificationChannel {
    private val TAG = "NotificationChannel"
    private const val CHANNEL_ID = "mdm_channel"
    private const val CHANNEL_NAME = "MDM Notifications"
    private const val CHANNEL_DESCRIPTION = "Notificações do sistema MDM"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = CHANNEL_DESCRIPTION
                enableLights(true)
                enableVibration(true)
            }
            
            val notificationManager: NotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            
            Log.d(TAG, "Canal de notificação criado: $CHANNEL_ID")
        }
    }

    fun getChannelId(): String = CHANNEL_ID
}