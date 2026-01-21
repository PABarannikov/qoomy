package com.qoomy.qoomy

import android.app.NotificationManager
import android.content.Context
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class QoomyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
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
}
