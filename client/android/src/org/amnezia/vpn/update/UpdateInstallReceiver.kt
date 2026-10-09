package org.amnezia.vpn.update

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import androidx.core.content.IntentCompat
import org.amnezia.vpn.update.SelfUpdater.BLOCKED_BY_SYSTEM
import org.amnezia.vpn.update.SelfUpdater.CANCELLED
import org.amnezia.vpn.update.SelfUpdater.CONFIRMING
import org.amnezia.vpn.update.SelfUpdater.FAILED_OTHER
import org.amnezia.vpn.update.SelfUpdater.PLAY_PROTECT
import org.amnezia.vpn.update.SelfUpdater.SUCCESS
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.Prefs

private const val TAG = "UpdateInstallReceiver"

// PackageManager's own codes behind the public status (hidden API, stable for years)
private const val EXTRA_LEGACY_STATUS = "android.content.pm.extra.LEGACY_STATUS"
private const val INSTALL_FAILED_VERIFICATION_FAILURE = -22
private const val INSTALL_FAILED_ABORTED = -115

/**
 * The install session's result (SelfUpdater.install). Not exported: only our own
 * PendingIntent, sent by the system, reaches it
 */
class UpdateInstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val legacy = intent.getIntExtra(EXTRA_LEGACY_STATUS, 0)
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        // the developer-verification failure reason (API 36.1) is not in the compile SDK
        // (android-36): such a block is told apart here once the SDK has the constant
        Log.i(TAG, "Install status $status, legacy $legacy, session $sessionId, message: $message")
        // a session abandoned for a newer attempt still reports «aborted»: not this attempt's
        if (!SelfUpdater.isCurrentSession(sessionId)) {
            Log.i(TAG, "Not the current install session: ignored")
            return
        }

        val code = when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> confirm(context, sessionId, intent)

            PackageInstaller.STATUS_SUCCESS -> SUCCESS

            PackageInstaller.STATUS_FAILURE_BLOCKED -> BLOCKED_BY_SYSTEM

            else -> when {
                // the verifier said no: Play Protect's dialog closed with «OK»
                legacy == INSTALL_FAILED_VERIFICATION_FAILURE ||
                    message?.contains("VERIFICATION_FAILURE") == true -> PLAY_PROTECT

                // aborted is mostly the user saying no in the system's dialog
                status == PackageInstaller.STATUS_FAILURE_ABORTED ||
                    legacy == INSTALL_FAILED_ABORTED -> CANCELLED

                else -> FAILED_OTHER
            }
        }
        // the confirmation is kept only while the session waits for the user
        if (code != CONFIRMING) SelfUpdater.dropConfirm()
        // a failed attempt must not reconnect after an update made some other way later
        if (code != SUCCESS && code != CONFIRMING) Prefs.save(PREFS_UPDATE_RECONNECT, false)
        SelfUpdater.report(code)
    }

    // the system's own confirmation: now when the app is in front, else when the user is back
    private fun confirm(context: Context, sessionId: Int, intent: Intent): Int {
        val confirmIntent = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_INTENT, Intent::class.java)
        if (confirmIntent == null) {
            Log.e(TAG, "No confirmation screen in the pending status")
            return FAILED_OTHER
        }
        return if (SelfUpdater.confirm(context, sessionId, confirmIntent)) CONFIRMING else FAILED_OTHER
    }
}
