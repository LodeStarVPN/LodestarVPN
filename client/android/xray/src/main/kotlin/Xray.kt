package org.amnezia.vpn.protocol.xray

import android.content.Context
import android.net.TrafficStats
import android.net.VpnService.Builder
import android.os.SystemClock
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import go.Seq
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.amnezia.vpn.protocol.BadConfigException
import org.amnezia.vpn.protocol.Protocol
import org.amnezia.vpn.protocol.ProtocolState.CONNECTED
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTED
import org.amnezia.vpn.protocol.Statistics
import org.amnezia.vpn.protocol.VpnStartException
import org.amnezia.vpn.protocol.xray.libXray.DialerController
import org.amnezia.vpn.protocol.xray.libXray.LibXray
import org.amnezia.vpn.protocol.xray.libXray.Logger
import org.amnezia.vpn.protocol.xray.libXray.Tun2SocksConfig
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.net.InetNetwork
import org.amnezia.vpn.util.net.ip
import org.amnezia.vpn.util.net.parseInetAddress
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "Xray"
private const val LIBXRAY_TAG = "libXray"

// two independent targets: one of them being unreachable from the exit must not fail a
// working server (the same pair as the desktop's TunnelHttpProbe)
private val PROBE_HOSTS = listOf("cp.cloudflare.com", "www.gstatic.com")
// inside the app's 12 s window for one address (ConnectionController::kPoolAttemptTimeoutMs)
private const val PROBE_TIMEOUT_MS = 7000L

class Xray : Protocol() {

    private var isRunning: Boolean = false

    // libXray exposes no byte counters, so read the VpnService tun interface
    // stats instead — Android allows only one active VPN, "tun0" is ours while
    // connected
    private val counts = InterfaceCounts("tun0")

    override val statistics: Statistics
        get() {
            if (!isRunning) return Statistics.EMPTY_STATISTICS
            val reading = counts.latest() ?: return Statistics.EMPTY_STATISTICS
            return Statistics.build {
                setRxBytes(reading.rx)
                setTxBytes(reading.tx)
                setSampleNanos(reading.nanos)
            }
        }

    override fun internalInit() {
        Seq.setContext(context)
        if (!isInitialized) {
            LibXray.initLogger(object : Logger {
                override fun warning(s: String) = Log.w(LIBXRAY_TAG, s)

                override fun error(s: String) = Log.e(LIBXRAY_TAG, s)

                override fun write(msg: ByteArray): Long {
                    Log.w(LIBXRAY_TAG, String(msg))
                    return msg.size.toLong()
                }
            }).isNotNullOrBlank { err ->
                Log.w(TAG, "Failed to initialize logger: $err")
            }
        }
    }

    override suspend fun startVpn(config: JSONObject, vpnBuilder: Builder, protect: (Int) -> Boolean) {
        if (isRunning) {
            Log.w(TAG, "XRay already running")
            return
        }

        val xrayJsonConfig = config.optJSONObject("xray_config_data")
            ?: config.optJSONObject("ssxray_config_data")
            ?: throw BadConfigException("config_data not found")
        val xrayConfig = parseConfig(config, xrayJsonConfig)

        (xrayJsonConfig.optJSONObject("log") ?: JSONObject().also { xrayJsonConfig.put("log", it) })
            .put("loglevel", "warning")
            .put("access", "none") // disable access log
        putFileNetworks(xrayJsonConfig)

        var xrayJsonConfigString = xrayJsonConfig.toString()
        config.getString("hostName").let { hostName ->
            val ipAddress = parseInetAddress(hostName).ip
            if (hostName != ipAddress) {
                xrayJsonConfigString = xrayJsonConfigString.replace(hostName, ipAddress)
            }
        }

        start(xrayConfig, xrayJsonConfigString, vpnBuilder, protect)
        // xray starts without reaching its server, and tun2socks answers TCP handshakes by
        // itself, so a blocked server would look connected with nothing loading. An HTTP
        // answer through xray's own SOCKS inbound is the proof; without it the app goes on
        // to the server's next address (the desktop does the same in XrayProtocol)
        if (!proveTraffic(xrayConfig.socksPort)) {
            LibXray.stopXray()
            LibXray.stopTun2Socks()
            throw VpnStartException("No answer through the server")
        }
        state.value = CONNECTED
        isRunning = true
    }

    // A rule may name its networks by a file of the app ("ipFile"): the whole Russian list, too
    // big for the one system message that brings the config here (vpnconnection.cpp). The
    // networks go into the rule; a file that cannot be read takes its rule away, and those
    // connections go through the server, as with the switch off.
    private fun putFileNetworks(xrayJsonConfig: JSONObject) {
        val rules = xrayJsonConfig.optJSONObject("routing")?.optJSONArray("rules") ?: return
        for (i in rules.length() - 1 downTo 0) {
            val rule = rules.optJSONObject(i) ?: continue
            val path = rule.optString("ipFile").ifBlank { null } ?: continue
            rule.remove("ipFile")
            val networks = try {
                File(path).readLines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }
            } catch (e: IOException) {
                Log.w(TAG, "The networks of a rule are not read: ${e.message}")
                emptyList()
            }
            if (networks.isEmpty()) {
                rules.remove(i)
                Log.w(TAG, "A rule without its networks is left out")
            } else {
                rule.put("ip", JSONArray(networks))
                Log.i(TAG, "A rule takes ${networks.size} networks from its file")
            }
        }
    }

    private suspend fun proveTraffic(socksPort: Int): Boolean = withContext(Dispatchers.IO) {
        val sockets = CopyOnWriteArrayList<Socket>()
        val answers = Channel<Boolean>(Channel.UNLIMITED)
        for (host in PROBE_HOSTS) {
            launch { answers.send(probeHost(socksPort, host, sockets)) }
        }
        // the deadline closes whatever still waits: a closed socket ends its probe at once
        val deadline = launch {
            delay(PROBE_TIMEOUT_MS)
            sockets.forEach { runCatching { it.close() } }
        }
        var proven = false
        for (i in PROBE_HOSTS.indices) {
            if (answers.receive()) {
                proven = true
                break
            }
        }
        deadline.cancel()
        sockets.forEach { runCatching { it.close() } }
        Log.i(TAG, if (proven) "Traffic proven: an HTTP answer through the server" else "No HTTP answer through the server")
        proven
    }

    private fun probeHost(socksPort: Int, host: String, sockets: MutableList<Socket>): Boolean =
        try {
            Socket(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))).use { socket ->
                sockets.add(socket)
                socket.soTimeout = PROBE_TIMEOUT_MS.toInt()
                // unresolved: the name goes to xray, which resolves it on the far side
                socket.connect(InetSocketAddress.createUnresolved(host, 80), PROBE_TIMEOUT_MS.toInt())
                socket.getOutputStream().apply {
                    write("HEAD /generate_204 HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n".toByteArray())
                    flush()
                }
                val status = socket.getInputStream().bufferedReader().readLine()
                status != null && status.startsWith("HTTP/")
            }
        } catch (e: IOException) {
            Log.w(TAG, "Probe $host: ${e.message}")
            false
        }

    private fun parseConfig(config: JSONObject, xrayJsonConfig: JSONObject): XrayConfig {
        return XrayConfig.build {
            addAddress(XrayConfig.DEFAULT_IPV4_ADDRESS)

            config.optString("dns1").let {
                if (it.isNotBlank()) addDnsServer(parseInetAddress(it))
            }

            config.optString("dns2").let {
                if (it.isNotBlank()) addDnsServer(parseInetAddress(it))
            }

            addRoute(InetNetwork("0.0.0.0", 0))
            // no 2000::/3: our nodes are IPv4-only — a v6 default route into
            // the tunnel blackholes IPv6-preferred apps (YouTube on Android)
            config.getString("hostName").let {
                excludeRoute(InetNetwork(it, 32))
            }

            config.optString("mtu").let {
                if (it.isNotBlank()) setMtu(it.toInt())
            }

            val socksConfig = xrayJsonConfig.getJSONArray("inbounds")[0] as JSONObject
            socksConfig.getInt("port").let { setSocksPort(it) }

            configSplitTunneling(config)
            configAppSplitTunneling(config)
        }
    }

    private fun start(config: XrayConfig, configJson: String, vpnBuilder: Builder, protect: (Int) -> Boolean) {
        buildVpnInterface(config, vpnBuilder)

        DialerController { protect(it.toInt()) }.also {
            LibXray.registerDialerController(it).isNotNullOrBlank { err ->
                throw VpnStartException("Failed to register dialer controller: $err")
            }
            LibXray.registerListenerController(it).isNotNullOrBlank { err ->
                throw VpnStartException("Failed to register listener controller: $err")
            }
        }

        vpnBuilder.establish().use { tunFd ->
            if (tunFd == null) {
                throw VpnStartException("Create VPN interface: permission not granted or revoked")
            }
            Log.d(TAG, "Run tun2Socks")
            runTun2Socks(config, tunFd.detachFd())

            Log.d(TAG, "Run XRay")
            Log.i(TAG, "xray ${LibXray.xrayVersion()}")
            val assetsPath = context.getDir("assets", Context.MODE_PRIVATE).absolutePath
            LibXray.initXray(assetsPath)
            val geoDir = File(assetsPath, "geo").absolutePath
            val configPath = File(context.cacheDir, "config.json")
            Log.v(TAG, "xray.location.asset: $geoDir")
            Log.v(TAG, "config: $configPath")
            try {
                configPath.writeText(configJson)
            } catch (e: IOException) {
                LibXray.stopTun2Socks()
                throw VpnStartException("Failed to write xray config: ${e.message}")
            }
            LibXray.runXray(geoDir, configPath.absolutePath, config.maxMemory).isNotNullOrBlank { err ->
                LibXray.stopTun2Socks()
                throw VpnStartException("Failed to start xray: $err")
            }
        }
    }

    override fun stopVpn() {
        LibXray.stopXray().isNotNullOrBlank { err ->
            Log.e(TAG, "Failed to stop XRay: $err")
        }
        LibXray.stopTun2Socks().isNotNullOrBlank { err ->
            Log.e(TAG, "Failed to stop tun2Socks: $err")
        }

        isRunning = false
        counts.stop()
        state.value = DISCONNECTED
    }

    override fun reconnectVpn(vpnBuilder: Builder, protect: (Int) -> Boolean) {
        state.value = CONNECTED
    }

    private fun runTun2Socks(config: XrayConfig, fd: Int) {
        val tun2SocksConfig = Tun2SocksConfig().apply {
            mtu = config.mtu.toLong()
            proxy = "socks5://127.0.0.1:${config.socksPort}"
            device = "fd://$fd"
            logLevel = "warn"
        }
        LibXray.startTun2Socks(tun2SocksConfig, fd.toLong()).isNotNullOrBlank { err ->
            throw VpnStartException("Failed to start tun2socks: $err")
        }
    }

    companion object {
        val instance: Xray by lazy { Xray() }
    }
}

/**
 * The system's counts of an interface, each with the moment it stood so. Android renews them about
 * once a second, whenever they are asked, and gives the same in between: a speed from them read
 * once a second jumped between half and double. Asked every 50 ms while they are wanted (read in the
 * last 3 s), a reading that changed is the counts at that moment, to within that; one that stays the
 * same is still so a renewal ago (the shortest time between changes seen, at least a second and a
 * half): the speed falls to nothing when the traffic stops.
 */
private class InterfaceCounts(private val iface: String) {

    class Reading(val rx: Long, val tx: Long, val nanos: Long)

    // the newest reading, and since when it stands (0: not known yet); the watcher's own, under the lock
    private var rx = -1L
    private var tx = -1L
    private var changedNanos = 0L
    private var renewalNanos = 0L
    private var watcher: Thread? = null
    @Volatile
    private var askedNanos = 0L

    /** The counts, with the moment they are known to have stood so (0 when not known); null if none. */
    fun latest(): Reading? {
        val now = SystemClock.elapsedRealtimeNanos()
        askedNanos = now
        synchronized(this) {
            if (watcher == null) {
                // after a rest the moment of a change is not known: the watcher sees the next one
                if (!read()) return null
                changedNanos = 0L
                watcher = thread(name = "xray-counts", isDaemon = true) { watch() }
            }
            if (changedNanos == 0L) return Reading(rx, tx, 0L)
            val proof = maxOf(MIN_RENEWAL_PROOF_NANOS, renewalNanos + renewalNanos / 2)
            return Reading(rx, tx, maxOf(changedNanos, now - proof))
        }
    }

    fun stop() {
        synchronized(this) {
            watcher?.interrupt()
            watcher = null
            rx = -1L
            tx = -1L
            changedNanos = 0L
            renewalNanos = 0L
        }
    }

    private fun read(): Boolean {
        val newRx = TrafficStats.getRxBytes(iface)
        val newTx = TrafficStats.getTxBytes(iface)
        if (newRx == TrafficStats.UNSUPPORTED.toLong() || newTx == TrafficStats.UNSUPPORTED.toLong()) return false
        rx = newRx
        tx = newTx
        return true
    }

    private fun watch() {
        val me = Thread.currentThread()
        var lastChange = 0L
        var gaps = 0
        try {
            while (true) {
                Thread.sleep(POLL_MS)
                synchronized(this) {
                    if (watcher !== me) return
                    if (SystemClock.elapsedRealtimeNanos() - askedNanos > WANTED_NANOS) {
                        watcher = null
                        return
                    }
                }
                val (oldRx, oldTx) = synchronized(this) { rx to tx }
                val before = SystemClock.elapsedRealtimeNanos()
                val newRx = TrafficStats.getRxBytes(iface)
                val newTx = TrafficStats.getTxBytes(iface)
                val at = before + (SystemClock.elapsedRealtimeNanos() - before) / 2
                if (newRx == TrafficStats.UNSUPPORTED.toLong() || newTx == TrafficStats.UNSUPPORTED.toLong()) continue
                if (newRx == oldRx && newTx == oldTx) continue
                synchronized(this) {
                    if (watcher !== me) return
                    rx = newRx
                    tx = newTx
                    changedNanos = at
                    if (lastChange > 0L) {
                        // the system's renewal: the shortest time between changes seen
                        val gap = at - lastChange
                        if (renewalNanos == 0L || gap < renewalNanos) renewalNanos = gap
                        if (++gaps == RENEWAL_LOG_AFTER) {
                            Log.i(TAG, "Interface counts renewed every ${renewalNanos / 1_000_000} ms or so")
                        }
                    }
                }
                lastChange = at
            }
        } catch (e: InterruptedException) {
            // stopped
        }
    }

    private companion object {
        const val POLL_MS = 50L
        const val WANTED_NANOS = 3_000_000_000L
        const val MIN_RENEWAL_PROOF_NANOS = 1_500_000_000L
        const val RENEWAL_LOG_AFTER = 20
    }
}

private fun String?.isNotNullOrBlank(block: (String) -> Unit) {
    if (!this.isNullOrBlank()) {
        block(this)
    }
}
