package org.amnezia.vpn.update

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import java.io.File
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.amnezia.vpn.AmneziaVpnService
import org.amnezia.vpn.VpnStateStore
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTED
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTING
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.Prefs

private const val TAG = "PackageReplacedReceiver"

/**
 * The first start after an update: the downloaded APK is no longer needed, and a VPN that
 * was on when the update began comes back by itself (the update killed its service)
 */
class PackageReplacedReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val app = context.applicationContext
        val pendingResult = goAsync()
        thread(name = "PackageReplaced") {
            try {
                removeDownloads(app)
                reconnect(app)
            } catch (e: Exception) {
                Log.e(TAG, "After the update: $e")
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun removeDownloads(app: Context) {
        try {
            File(app.filesDir, UPDATES_DIR).listFiles()?.forEach { it.deleteRecursively() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove the downloaded update: $e")
        }
    }

    private fun reconnect(app: Context) {
        if (!Prefs.load<Boolean>(PREFS_UPDATE_RECONNECT)) return
        Prefs.prefs.edit().remove(PREFS_UPDATE_RECONNECT).commit()
        if (VpnService.prepare(app) != null) {
            Log.i(TAG, "No VPN permission: not reconnecting")
            return
        }
        val state = runBlocking { VpnStateStore.getVpnState() }
        // the service saves every change and the update kills it without one: an «off» here is the
        // user's own, made while the system's dialogs were open
        if (state.protocolState == DISCONNECTED || state.protocolState == DISCONNECTING) {
            Log.i(TAG, "The VPN was turned off: not reconnecting")
            return
        }
        val proto = state.vpnProto
        // as the quick tile: a saved server and its protocol, the service connects with its saved config
        if (proto == null || state.serverName == null) {
            Log.i(TAG, "No saved server: not reconnecting")
            return
        }
        // always-on VPN may have brought it up already
        if (AmneziaVpnService.isRunning(app, proto.processName)) return
        Log.i(TAG, "Reconnecting after the update: $proto")
        try {
            ContextCompat.startForegroundService(app, Intent(app, proto.serviceClass))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ${proto.serviceClass.simpleName}: $e")
        }
    }
}
