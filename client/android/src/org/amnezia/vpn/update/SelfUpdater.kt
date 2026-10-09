package org.amnezia.vpn.update

import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import org.amnezia.vpn.AmneziaVpnService
import org.amnezia.vpn.VpnStateStore
import org.amnezia.vpn.protocol.ProtocolState.CONNECTED
import org.amnezia.vpn.protocol.ProtocolState.CONNECTING
import org.amnezia.vpn.protocol.ProtocolState.RECONNECTING
import org.amnezia.vpn.qt.QtAndroidController
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.Prefs

private const val TAG = "SelfUpdater"

// whether the VPN was on when an update was committed: PackageReplacedReceiver brings it back
const val PREFS_UPDATE_RECONNECT = "UPDATE_RECONNECT"
// the install session the app waits for: one abandoned for a newer attempt still sends its
// result. In the prefs, as a result may come to a process started just for it
private const val PREFS_UPDATE_SESSION = "UPDATE_SESSION"
// where UpdateController downloads to: QStandardPaths::AppDataLocation is filesDir on Android
const val UPDATES_DIR = "updates"

/**
 * In-app update: UpdateController (Qt) downloads and checks the APK, this installs it.
 * Only our own package, signed with the installed app's key, with a higher versionCode —
 * and always through the system's own confirmation (Play Protect included), never silently
 */
object SelfUpdater {
    // install results for Qt: UpdateController maps these numbers, keep them
    const val SUCCESS = 0
    const val CONFIRMING = 1
    const val PLAY_PROTECT = 2
    const val CANCELLED = 3
    const val PERMISSION_NEEDED = 4
    const val FAILED_OTHER = 5
    const val BLOCKED_BY_SYSTEM = 6

    // verifyApk() below zero
    const val APK_UNREADABLE = -1L
    const val APK_OTHER_PACKAGE = -2L
    const val APK_NOT_NEWER = -3L
    const val APK_OTHER_SIGNER = -4L
    const val APK_OTHER_ERROR = -5L

    // true once the Qt side has registered its natives (AmneziaActivity): a result that
    // arrives in a process started just for the broadcast has no Qt to go to
    @Volatile
    var qtAlive = false

    // AmneziaActivity is in front (onResume..onPause): only then is the system's confirmation
    // started — from the background Android drops such a start silently
    @Volatile
    var activityResumed = false

    // the current session's confirmation, kept until its result: shown when the user comes back
    // if it could not open before, or was left open behind (it lives in the installer's own task)
    @Volatile
    private var pendingConfirm: Intent? = null
    @Volatile
    private var pendingConfirmSession = -1
    // it is on screen (or was answered) as opposed to waiting for the app to come back
    @Volatile
    private var confirmShown = false

    private val executor by lazy { Executors.newSingleThreadExecutor() }
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    fun supportedAbis(): String = Build.SUPPORTED_ABIS.joinToString(",")

    fun installedVersionCode(ctx: Context): Long = try {
        packageInfo(ctx.packageManager, ctx.packageName, 0).longVersionCode
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read the installed version: $e")
        0L
    }

    fun isXiaomiFamily(): Boolean =
        listOf(Build.MANUFACTURER, Build.BRAND).any { name ->
            listOf("xiaomi", "redmi", "poco").any { it.equals(name, ignoreCase = true) }
        }

    /**
     * The APK's versionCode when it may replace this app, otherwise APK_* below zero. Never throws
     */
    fun verifyApk(ctx: Context, path: String): Long = try {
        val pm = ctx.packageManager
        // Android 9 collects an archive's certificates only when GET_SIGNATURES is asked for
        @Suppress("DEPRECATION")
        val legacyFlags = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) PackageManager.GET_SIGNATURES else 0
        val flags = PackageManager.GET_SIGNING_CERTIFICATES or legacyFlags
        val archive = if (File(path).isFile) archiveInfo(pm, path, flags) else null
        val installed = packageInfo(pm, ctx.packageName, flags)
        val result = when {
            archive == null -> APK_UNREADABLE
            archive.packageName != ctx.packageName -> APK_OTHER_PACKAGE
            archive.longVersionCode <= installed.longVersionCode -> APK_NOT_NEWER
            else -> {
                val apkSigners = signerDigests(archive).orEmpty()
                val ourSigners = signerDigests(installed).orEmpty()
                // exactly one signer, and the one this app is signed with now
                if (apkSigners.size == 1 && ourSigners.size == 1 && apkSigners[0] == ourSigners[0]) {
                    archive.longVersionCode
                } else {
                    APK_OTHER_SIGNER
                }
            }
        }
        Log.i(TAG, "Update APK check: ${archive?.versionName} (${archive?.longVersionCode}) " +
            "over ${installed.versionName} (${installed.longVersionCode}): $result")
        result
    } catch (e: Exception) {
        Log.e(TAG, "Update APK check failed: $e")
        APK_OTHER_ERROR
    }

    fun canInstall(ctx: Context): Boolean = try {
        ctx.packageManager.canRequestPackageInstalls()
    } catch (e: Exception) {
        Log.e(TAG, "Failed to check the install permission: $e")
        false
    }

    fun openInstallPermissionSettings(activity: Activity) {
        val uri = Uri.parse("package:${activity.packageName}")
        try {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri))
        } catch (_: ActivityNotFoundException) {
            // some firmwares have no such screen: the app's details page leads there too
            try {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri))
            } catch (e: Exception) {
                Log.e(TAG, "No settings screen for the install permission: $e")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open the install permission settings: $e")
        }
    }

    /**
     * Returns at once: the copy into the session runs on a background thread, the result
     * comes to UpdateInstallReceiver and from there to Qt (report)
     */
    fun install(ctx: Context, path: String) {
        val app = ctx.applicationContext
        if (!canInstall(app)) {
            Log.i(TAG, "Install: no permission to install apps yet")
            report(PERMISSION_NEEDED)
            return
        }
        executor.execute { installNow(app, path) }
    }

    private fun installNow(app: Context, path: String) {
        val installer = app.packageManager.packageInstaller
        var sessionId = -1
        try {
            // the same checks as after the download: the file may have changed since
            val versionCode = verifyApk(app, path)
            if (versionCode <= 0) {
                Log.w(TAG, "Install: the update file did not pass the check ($versionCode)")
                // it would fail the same way on every retry: without it UpdateController downloads anew
                File(path).delete()
                report(FAILED_OTHER)
                return
            }
            // a session left from an earlier attempt only holds a copy of the file; once
            // committed, it reports «aborted» when abandoned — not this attempt's result
            setCurrentSession(-1)
            dropConfirm()
            installer.mySessions.forEach {
                try {
                    installer.abandonSession(it.sessionId)
                } catch (_: Exception) {}
            }
            val file = File(path)
            val size = file.length()
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(app.packageName)
                setSize(size)
                setInstallReason(PackageManager.INSTALL_REASON_USER)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    setPackageSource(PackageInstaller.PACKAGE_SOURCE_OTHER)
                }
                // no setRequireUserAction: the system asks the user, as it must (HyperOS
                // refuses a self-update that tries to skip the question)
            }
            sessionId = installer.createSession(params)
            setCurrentSession(sessionId)
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, size).use { output ->
                        input.copyTo(output, 1 shl 16)
                        session.fsync(output)
                    }
                }
                // commit(), not apply(): the update kills this process soon after
                Prefs.prefs.edit().putBoolean(PREFS_UPDATE_RECONNECT, isVpnOn(app)).commit()
                val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val pendingIntent = PendingIntent.getBroadcast(
                    app,
                    sessionId,
                    Intent(app, UpdateInstallReceiver::class.java).setPackage(app.packageName),
                    mutable or PendingIntent.FLAG_UPDATE_CURRENT
                )
                Log.i(TAG, "Install: committing $versionCode ($size bytes)")
                session.commit(pendingIntent.intentSender)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Install failed: $e")
            if (sessionId != -1) {
                try {
                    installer.abandonSession(sessionId)
                } catch (_: Exception) {}
            }
            // nothing was committed: no reconnect after an update made some other way later
            try {
                Prefs.prefs.edit().remove(PREFS_UPDATE_RECONNECT).remove(PREFS_UPDATE_SESSION).commit()
            } catch (_: Exception) {}
            report(FAILED_OTHER)
        }
    }

    // results of other sessions (abandoned for a newer attempt) are not this attempt's
    fun isCurrentSession(sessionId: Int): Boolean = try {
        sessionId == Prefs.load<Int>(PREFS_UPDATE_SESSION)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read the install session: $e")
        true
    }

    private fun setCurrentSession(sessionId: Int) {
        Prefs.prefs.edit().putInt(PREFS_UPDATE_SESSION, sessionId).commit()
    }

    /**
     * The system's confirmation of the current session (UpdateInstallReceiver): opened now when
     * the app is in front, otherwise when it comes back (resumeConfirm). False when it cannot open
     */
    fun confirm(ctx: Context, sessionId: Int, confirmIntent: Intent): Boolean {
        pendingConfirm = confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        pendingConfirmSession = sessionId
        confirmShown = false
        if (!activityResumed) {
            Log.i(TAG, "The confirmation waits for the app to come back")
            return true
        }
        return startConfirm(ctx)
    }

    // the session has its result (or a new attempt replaces it): nothing to show any more
    fun dropConfirm() {
        pendingConfirm = null
        pendingConfirmSession = -1
        confirmShown = false
    }

    /**
     * AmneziaActivity.onResume. True when the confirmation is due to open again (resumeConfirm,
     * a moment later); a return from the dialog itself means it was answered
     */
    fun onActivityResumed(): Boolean {
        activityResumed = true
        if (pendingConfirm == null) return false
        if (confirmShown) {
            // after «Install» the dialog closes while the system installs on: never ask again
            dropConfirm()
            return false
        }
        return true
    }

    /**
     * AmneziaActivity.onStop. With the screen on the user went elsewhere (Home, another app), and an
     * open confirmation stays behind in its task: show it again on the way back. With the screen
     * off it is still on top when the screen comes back
     */
    fun onActivityStopped(ctx: Context) {
        if (pendingConfirm == null || !confirmShown) return
        if (ctx.getSystemService(PowerManager::class.java)?.isInteractive == true) confirmShown = false
    }

    // a moment after AmneziaActivity.onResume: unless the session has ended meanwhile
    fun resumeConfirm(activity: Activity) {
        val sessionId = pendingConfirmSession
        if (pendingConfirm == null || confirmShown) return
        val waiting = try {
            activity.packageManager.packageInstaller.mySessions.any { it.sessionId == sessionId }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to list the install sessions: $e")
            false
        }
        if (!waiting) {
            dropConfirm()
            return
        }
        Log.i(TAG, "Showing the install confirmation again")
        if (startConfirm(activity)) {
            report(CONFIRMING)
        } else {
            Prefs.save(PREFS_UPDATE_RECONNECT, false)
            report(FAILED_OTHER)
        }
    }

    // the system's own confirmation, as it is: the user decides there
    private fun startConfirm(ctx: Context): Boolean {
        val intent = pendingConfirm ?: return false
        return try {
            ctx.startActivity(intent)
            confirmShown = true
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show the confirmation screen: $e")
            dropConfirm()
            false
        }
    }

    // a VPN session is up (or coming up) right now: worth bringing back after the update
    private fun isVpnOn(ctx: Context): Boolean = try {
        val state = runBlocking { VpnStateStore.getVpnState() }
        val proto = state.vpnProto
        proto != null && state.protocolState in listOf(CONNECTED, CONNECTING, RECONNECTING) &&
            AmneziaVpnService.isRunning(ctx, proto.processName)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read the VPN state: $e")
        false
    }

    /**
     * To UpdateController on the main thread; dropped when there is no Qt in this process
     */
    fun report(code: Int) {
        mainHandler.post {
            if (!qtAlive) {
                Log.i(TAG, "Install result $code: no app window to tell")
                return@post
            }
            try {
                QtAndroidController.onUpdateInstallResult(code)
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Install result $code not delivered: $e")
            }
        }
    }

    // SHA-256 of the certificates the package is signed with now (not its rotation history)
    private fun signerDigests(info: PackageInfo): List<String>? {
        @Suppress("DEPRECATION")
        val signatures: Array<Signature>? = info.signingInfo?.apkContentsSigners ?: info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
    }

    private fun packageInfo(pm: PackageManager, packageName: String, flags: Int): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, flags)
        }

    private fun archiveInfo(pm: PackageManager, path: String, flags: Int): PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, flags)
        }
}
