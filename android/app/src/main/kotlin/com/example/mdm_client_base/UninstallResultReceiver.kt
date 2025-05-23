package com.example.mdm_client_base

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

class UninstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.example.mdm_client_base.UNINSTALL_RESULT") {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
            val packageName = intent.getStringExtra("packageName")
            when (status) {
                PackageInstaller.STATUS_SUCCESS -> {
                    Log.d("UninstallResultReceiver", "Successfully uninstalled $packageName")
                }
                PackageInstaller.STATUS_FAILURE -> {
                    Log.e("UninstallResultReceiver", "Failed to uninstall $packageName")
                }
                else -> {
                    Log.e("UninstallResultReceiver", "Uninstall $packageName status: $status")
                }
            }
        }
    }
}