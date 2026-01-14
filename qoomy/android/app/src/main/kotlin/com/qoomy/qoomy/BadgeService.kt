package com.qoomy.qoomy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import me.leolin.shortcutbadger.ShortcutBadger

class BadgeService : Service() {

    private val channelId = "qoomy_badge_channel"
    private val notificationId = 1
    private var badgeCount = 0

    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SET_COUNT -> {
                val count = intent.getIntExtra(EXTRA_COUNT, 0)
                setBadgeCount(count)
            }
            ACTION_RESET -> {
                setBadgeCount(0)
            }
            else -> {
                // Start as foreground service with initial notification
                setBadgeCount(0)
            }
        }

        return START_STICKY
    }

    companion object {
        const val ACTION_SET_COUNT = "com.qoomy.qoomy.ACTION_SET_COUNT"
        const val ACTION_RESET = "com.qoomy.qoomy.ACTION_RESET"
        const val EXTRA_COUNT = "com.qoomy.qoomy.EXTRA_COUNT"
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            channelId,
            "Qoomy Badge",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Channel for Qoomy badge notifications"
            setShowBadge(true)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification() = NotificationCompat.Builder(this, channelId)
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle("Qoomy")
        .setContentText("Unread messages: $badgeCount")
        .setNumber(badgeCount)
        .setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
        .setOngoing(true)
        .build()

    private fun setBadgeCount(count: Int) {
        badgeCount = count

        if (badgeCount == 0) {
            // Clear badge and stop foreground
            ShortcutBadger.removeCount(applicationContext)
            notificationManager.cancel(notificationId)
        } else {
            // Update badge and notification
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForeground(notificationId, notification)
            } else {
                notificationManager.notify(notificationId, notification)
            }
            ShortcutBadger.applyCount(applicationContext, badgeCount)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ShortcutBadger.removeCount(applicationContext)
        notificationManager.cancel(notificationId)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
