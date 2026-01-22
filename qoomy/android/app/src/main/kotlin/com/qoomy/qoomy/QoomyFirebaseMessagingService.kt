package com.qoomy.qoomy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class QoomyFirebaseMessagingService : FirebaseMessagingService() {

    private val NOTIFICATION_CHANNEL_ID = "qoomy_messages"

    override fun onMessageReceived(message: RemoteMessage) {
        // Ensure notification channel exists before any notification is shown
        createNotificationChannel()

        super.onMessageReceived(message)

        val messageType = message.data["type"]

        // Handle badge_update messages - clear all notifications when user reads messages
        if (messageType == "badge_update") {
            val unreadCount = message.data["unreadCount"]?.toIntOrNull() ?: 0

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (unreadCount == 0) {
                // No unread messages - clear all notifications
                notificationManager.cancelAll()
            }
            // If unreadCount > 0, don't clear - the user might have other rooms with unread
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Messages",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for new messages"
                setShowBadge(true)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
