package org.amnezia.vpn

import android.content.Intent
import android.content.Intent.ACTION_SEND
import android.content.Intent.ACTION_VIEW
import android.content.Intent.CATEGORY_DEFAULT
import android.content.Intent.EXTRA_TEXT
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.os.Bundle
import androidx.activity.ComponentActivity
import org.amnezia.vpn.util.Log

private const val TAG = "ImportConfigActivity"

const val ACTION_IMPORT_CONFIG = "org.lodestar.vpn.IMPORT_CONFIG"
const val EXTRA_CONFIG = "CONFIG"

class ImportConfigActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.v(TAG, "Create Import Config Activity: $intent")
        intent?.let(::readConfig)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.v(TAG, "onNewIntent: $intent")
        intent.let(::readConfig)
    }

    // our own links only: a subscription (lodestar://sub/<key>) or a shared connection
    // (lodestar://conn/<token>), opened or shared as text. Configs and files are not taken
    // from other apps — the app asks before adding a subscription (CoreController)
    private fun readConfig(intent: Intent) {
        val link = when (intent.action) {
            ACTION_SEND -> intent.getStringExtra(EXTRA_TEXT)?.trim()
            ACTION_VIEW -> intent.data?.toString()?.trim()
            else -> null
        }
        if (link != null && isOurLink(link)) {
            startMainActivity(link)
        } else {
            Log.w(TAG, "Not our link: ignored")
        }
        finish()
    }

    private fun isOurLink(link: String) =
        (link.startsWith("lodestar://sub/") || link.startsWith("lodestar://conn/")) && link.none { it.isWhitespace() }

    private fun startMainActivity(config: String) {
        if (config.isNotBlank()) {
            Log.d(TAG, "startMainActivity")
            Intent(applicationContext, AmneziaActivity::class.java).apply {
                action = ACTION_IMPORT_CONFIG
                addCategory(CATEGORY_DEFAULT)
                putExtra(EXTRA_CONFIG, config)
                flags = FLAG_ACTIVITY_NEW_TASK
            }.also {
                startActivity(it)
            }
        }
    }
}
