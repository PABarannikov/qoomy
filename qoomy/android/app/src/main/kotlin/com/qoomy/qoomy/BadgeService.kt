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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BadgeService : Service() {

    private val channelId = "qoomy_badge_channel"
    private val notificationId = 1
    private var badgeCount = 0
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // CRITICAL: Must call startForeground immediately after startForegroundService
        // to avoid ForegroundServiceDidNotStartInTimeException crash
        startForeground(notificationId, buildNotification())

        when (intent?.action) {
            ACTION_SET_COUNT -> {
                val count = intent.getIntExtra(EXTRA_COUNT, 0)
                setBadgeCount(count)
            }
            ACTION_RESET -> {
                setBadgeCount(0)
            }
            else -> {
                // Service started, badge already at 0
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

    private fun buildNotification(): android.app.Notification {
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Qoomy")
            .setContentText(if (badgeCount > 0) "Unread messages: $badgeCount" else "No unread messages")
            .setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
            .setOngoing(true)

        // Only set number if > 0, otherwise badge shows incorrectly
        if (badgeCount > 0) {
            builder.setNumber(badgeCount)
        }

        return builder.build()
    }

    private fun setBadgeCount(count: Int) {
        badgeCount = count

        if (badgeCount == 0) {
            // Clear badge and hide notification
            ShortcutBadger.removeCount(applicationContext)
            // Stop foreground but keep service running, remove notification
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            // Update badge and show notification
            ShortcutBadger.applyCount(applicationContext, badgeCount)
            // Re-enter foreground mode with notification
            startForeground(notificationId, buildNotification())
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ShortcutBadger.removeCount(applicationContext)
        notificationManager.cancel(notificationId)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
