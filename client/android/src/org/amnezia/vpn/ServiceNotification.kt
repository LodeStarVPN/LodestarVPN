package org.amnezia.vpn

import android.Manifest.permission
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat.Builder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationCompat.Action
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.amnezia.vpn.protocol.ProtocolState
import org.amnezia.vpn.protocol.ProtocolState.CONNECTED
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTED
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.net.TrafficStats.TrafficData

private const val TAG = "ServiceNotification"

private const val OLD_NOTIFICATION_CHANNEL_ID: String = "org.amnezia.vpn.notification"
private const val NOTIFICATION_CHANNEL_ID: String = "org.amnezia.vpn.notifications"
const val NOTIFICATION_ID = 1337

private const val GET_ACTIVITY_REQUEST_CODE = 0
private const val CONNECT_REQUEST_CODE = 1
private const val DISCONNECT_REQUEST_CODE = 2

class ServiceNotification(private val context: Context) {

    private val upDownSymbols = when (Build.BRAND) {
        "Infinix" -> '˅' to '˄'
        else -> '↓' to '↑'
    }

    private val notificationManager = NotificationManagerCompat.from(context)

    private val notificationBuilder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
        .setShowWhen(false)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setContentIntent(
            PendingIntent.getActivity(
                context,
                GET_ACTIVITY_REQUEST_CODE,
                Intent(context, AmneziaActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

    private val zeroSpeed: String = formatSpeed(TrafficData.ZERO)

    // the speed line as it stands in the shade: the same line is not posted again
    private var shownSpeed: String? = null

    fun buildNotification(serverName: String?, protocol: String?, state: ProtocolState): Notification {
        val speedString = if (state == CONNECTED) zeroSpeed else null

        Log.v(TAG, "Build notification: $serverName, $state")

        return notificationBuilder
            .setSmallIcon(R.drawable.ic_lodestar)
            // "LodestarVPN · Германия", "Подключено · AmneziaWG"
            .setContentTitle("LodestarVPN" + (serverName?.let { " · $it" } ?: ""))
            .setContentText(context.getString(state) + (protocol?.let { " · $it" } ?: ""))
            .setSubText(speedString)
            // The notification's place in the shade goes by this time. It is set when the
            // state changes and left alone by the speed's updates: stamped anew every
            // second, the notification kept jumping above another app's that is updated
            // as often (a download in Google Play), and the two swapped places for ever.
            .setWhen(System.currentTimeMillis())
            .clearActions()
            .apply {
                getAction(state)?.let {
                    addAction(it)
                }
            }
            .build()
            .also { shownSpeed = speedString }
    }

    // the builder keeps the time of the last change of state (see above)
    private fun buildNotification(speedString: String): Notification =
        notificationBuilder
            .setSubText(speedString)
            .build()

    fun isNotificationEnabled(): Boolean {
        if (!context.isNotificationPermissionGranted()) return false
        if (!notificationManager.areNotificationsEnabled()) return false
        return notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)?.let {
            it.importance != NotificationManager.IMPORTANCE_NONE
        } ?: true
    }

    @SuppressLint("MissingPermission")
    fun updateNotification(serverName: String?, protocol: String?, state: ProtocolState) {
        if (context.isNotificationPermissionGranted()) {
            Log.v(TAG, "Update notification: $serverName, $state")
            notificationManager.notify(NOTIFICATION_ID, buildNotification(serverName, protocol, state))
        }
    }

    @SuppressLint("MissingPermission")
    fun updateSpeed(speed: TrafficData) {
        val speedString = getSpeedString(speed)
        if (speedString == shownSpeed) return
        if (context.isNotificationPermissionGranted()) {
            notificationManager.notify(NOTIFICATION_ID, buildNotification(speedString))
            shownSpeed = speedString
        }
    }

    private fun getSpeedString(traffic: TrafficData) =
        if (traffic == TrafficData.ZERO) zeroSpeed
        else formatSpeed(traffic)

    // The app's server card shows the same (connectionController.cpp): bytes a second, decimal kilo,
    // mega, giga (1 MB = 1,000,000 bytes, a speed test's Mbit/s divided by 8), each figure with its own
    // unit, a decimal only below 10
    private fun formatSpeed(traffic: TrafficData): String {
        val locale = context.resources.configuration.locales[0]
        fun figure(bytesPerSecond: Long): String {
            val bytes = bytesPerSecond.toDouble()
            val (divider, unit) = when {
                bytes >= 1e9 -> 1e9 to R.string.speedGB
                bytes >= 1e6 -> 1e6 to R.string.speedMB
                bytes >= 1e3 -> 1e3 to R.string.speedKB
                else -> 1.0 to R.string.speedB
            }
            val value = bytes / divider
            val number = String.format(locale, if (divider > 1.0 && value < 10) "%.1f" else "%.0f", value)
            return "$number ${context.getString(unit)}"
        }
        return with(upDownSymbols) { "$first ${figure(traffic.rx)}  $second ${figure(traffic.tx)}" }
    }

    private fun getAction(state: ProtocolState): Action? {
        return when (state) {
            CONNECTED -> {
                Action(
                    0, context.getString(R.string.disconnect),
                    PendingIntent.getBroadcast(
                        context,
                        DISCONNECT_REQUEST_CODE,
                        Intent(ACTION_DISCONNECT).apply {
                            setPackage(context.packageName)
                        },
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }

            DISCONNECTED -> {
                Action(
                    0, context.getString(R.string.connect),
                    PendingIntent.getBroadcast(
                        context,
                        CONNECT_REQUEST_CODE,
                        Intent(ACTION_CONNECT).apply {
                            setPackage(context.packageName)
                        },
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }

            else -> null
        }
    }

    companion object {
        fun createNotificationChannel(context: Context) {
            with(NotificationManagerCompat.from(context)) {
                deleteNotificationChannel(OLD_NOTIFICATION_CHANNEL_ID)
                createNotificationChannel(
                    Builder(NOTIFICATION_CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                        .setShowBadge(false)
                        .setSound(null, null)
                        .setVibrationEnabled(false)
                        .setLightsEnabled(false)
                        .setName("LodestarVPN")
                        .setDescription(context.resources.getString(R.string.notificationChannelDescription))
                        .build()
                )
            }
        }
    }
}

fun Context.isNotificationPermissionGranted(): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(this, permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED
