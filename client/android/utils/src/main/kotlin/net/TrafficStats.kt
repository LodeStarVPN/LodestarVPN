package org.amnezia.vpn.util.net

import kotlin.math.roundToLong

private const val WINDOW_NANOS = 2_100_000_000L
private const val MIN_SPAN_NANOS = 900_000_000L
private const val GAP_NANOS = 5_000_000_000L

/**
 * The apps' speed for the service's notification, from the same counts as the app's server card
 * (connectionController.cpp, addSpeedSample): what the VPN carried and what its tunnel opened past it,
 * each total timed where it was read, over about two seconds of them. (The VPN interface's counts
 * served before: Android renews them about once a second whenever they are asked, and a figure from
 * them read each second jumped between half and double.)
 */
class TrafficStats {

    private class Sample(val nanos: Long, val rx: Long, val tx: Long)

    private val samples = ArrayDeque<Sample>()
    private var speed = TrafficData.ZERO

    fun reset() {
        samples.clear()
        speed = TrafficData.ZERO
    }

    /**
     * Totals read at [nanos] (SystemClock.elapsedRealtimeNanos, 0 when not known): the speed over the
     * last two seconds or so of them, in bytes a second.
     */
    fun add(rx: Long, tx: Long, nanos: Long): TrafficData {
        val last = samples.lastOrNull()
        // the same reading again: nothing new
        if (last != null && nanos == last.nanos) return speed
        if (nanos <= 0L ||
            last != null && (nanos < last.nanos || rx < last.rx || tx < last.tx || nanos - last.nanos > GAP_NANOS)
        ) {
            // a moment not known, counts begun anew (the VPN made again) or a gap: afresh from the next
            samples.clear()
            if (nanos <= 0L) return speed
        }
        samples.addLast(Sample(nanos, rx, tx))
        while (samples.size > 2 && nanos - samples.first().nanos > WINDOW_NANOS) samples.removeFirst()
        val first = samples.first()
        val span = nanos - first.nanos
        if (span >= MIN_SPAN_NANOS) {
            speed = TrafficData.of((rx - first.rx) * 1e9 / span, (tx - first.tx) * 1e9 / span)
        }
        return speed
    }

    /** Bytes a second. */
    class TrafficData(val rx: Long, val tx: Long) {

        companion object {
            val ZERO: TrafficData = TrafficData(0L, 0L)

            fun of(rx: Double, tx: Double): TrafficData {
                val rxRounded = rx.roundToLong()
                val txRounded = tx.roundToLong()
                return if (rxRounded == 0L && txRounded == 0L) ZERO else TrafficData(rxRounded, txRounded)
            }
        }
    }
}
