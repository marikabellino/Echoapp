package com.example.echo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel("echo_notifications") == null) {
                val channel = NotificationChannel(
                    "echo_notifications",
                    "Notifiche Echo",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Like, messaggi e aggiornamenti della cerchia"
                    enableVibration(true)
                    enableLights(true)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }
}
