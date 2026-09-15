package com.cubiclm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlin.concurrent.thread

/**
 * Foreground keep-alive for long runtime/toolchain installs.
 *
 * The Dart [RuntimeInstaller] does the real work (HTTP resume, SHA-256,
 * tar extract) and calls `setKeepAlive(true)` on the
 * `com.cubiclm.app/runtime` channel first: this service then holds a
 * foreground notification + partial wakelock so Android does not kill the
 * install. `updateProgress` refreshes the notification (throttled);
 * `setKeepAlive(false)` releases everything.
 */
class RuntimeSetupService : Service() {

    companion object {
        const val ACTION_KEEPALIVE = "com.cubiclm.app.runtime.KEEPALIVE"
        const val ACTION_RELEASE = "com.cubiclm.app.runtime.RELEASE"
        const val EXTRA_ACTIVE = "active"
        private const val CHANNEL_ID = "cubiclm_runtime_setup"
        private const val NOTIF_ID = 4220

        @Volatile private var instance: RuntimeSetupService? = null
        @Volatile private var lastTitle = "Installing runtime…"
        @Volatile private var lastFraction = 0.0
        @Volatile private var lastLine = ""
        @Volatile private var lastPushMs = 0L

        fun setKeepAlive(context: Context, active: Boolean) {
            val action = if (active) ACTION_KEEPALIVE else ACTION_RELEASE
            val intent = Intent(context, RuntimeSetupService::class.java)
                .setAction(action)
            try {
                if (active && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
            }
        }

        fun updateProgress(title: String, fraction: Double, line: String) {
            lastTitle = title.ifBlank { "Installing runtime…" }
            lastFraction = fraction.coerceIn(0.0, 1.0)
            lastLine = line
            val now = System.currentTimeMillis()
            if (now - lastPushMs < 750) return
            lastPushMs = now
            thread(name = "runtime-notify") {
                try {
                    instance?.refreshNotification()
                } catch (_: Exception) {
                }
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RELEASE -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                releaseLock()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                instance = this
                lastPushMs = 0L
                ensureChannel()
                acquireLock()
                startForegroundCompat()
                refreshNotification()
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        releaseLock()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Runtime setup",
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
        } catch (_: Exception) {
        }
    }

    private fun acquireLock() {
        try {
            if (wakeLock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CubicLM:runtime-setup",
            ).apply {
                // 90 minutes is plenty for the largest (Android) stack.
                acquire(90 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (_: Exception) {
        }
    }

    private fun refreshNotification() {
        try {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            mgr.notify(NOTIF_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    private fun buildNotification(): android.app.Notification {
        val pct = (lastFraction * 100).toInt().coerceIn(0, 100)
        val text = if (lastLine.isNotBlank()) lastLine else "Working…"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("$lastTitle · $pct%")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, pct, lastFraction <= 0.0)
            .build()
    }
}
