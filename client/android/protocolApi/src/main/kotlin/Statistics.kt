package org.amnezia.vpn.protocol

import android.os.Bundle

private const val RX_BYTES_KEY = "rxBytes"
private const val TX_BYTES_KEY = "txBytes"
private const val DATA_RX_BYTES_KEY = "dataRxBytes"
private const val DATA_TX_BYTES_KEY = "dataTxBytes"
private const val SAMPLE_NANOS_KEY = "sampleNanos"

// rx/tx: the VPN's own - the app's traffic checks go by them; dataRx/dataTx: the apps' data by the
// tunnel's count, both ways it went (through the VPN and past it: AmneziaWG's sorter), -1 where the
// tunnel keeps none (Xray) - the speed shown goes by them. sampleNanos: when they were read
// (SystemClock.elapsedRealtimeNanos), 0 when not known - the speed goes by it, not by when they reach
// the app (connectionController.cpp, addSpeedSample)
@Suppress("DataClassPrivateConstructor")
data class Statistics private constructor(
    val rxBytes: Long = 0L,
    val txBytes: Long = 0L,
    val dataRxBytes: Long = -1L,
    val dataTxBytes: Long = -1L,
    val sampleNanos: Long = 0L
) {

    private constructor(builder: Builder) :
        this(builder.rxBytes, builder.txBytes, builder.dataRxBytes, builder.dataTxBytes, builder.sampleNanos)

    /** What the speed counts: the apps' data where the tunnel keeps it, the VPN's bytes otherwise. */
    val shownRxBytes: Long
        get() = if (dataRxBytes >= 0 && dataTxBytes >= 0) dataRxBytes else rxBytes

    val shownTxBytes: Long
        get() = if (dataRxBytes >= 0 && dataTxBytes >= 0) dataTxBytes else txBytes

    @Suppress("SuspiciousEqualsCombination")
    fun isEmpty(): Boolean = this === EMPTY_STATISTICS || this == EMPTY_STATISTICS

    class Builder {
        var rxBytes: Long = 0L
            private set

        var txBytes: Long = 0L
            private set

        var dataRxBytes: Long = -1L
            private set

        var dataTxBytes: Long = -1L
            private set

        var sampleNanos: Long = 0L
            private set

        fun setRxBytes(rxBytes: Long) = apply { this.rxBytes = rxBytes }
        fun setTxBytes(txBytes: Long) = apply { this.txBytes = txBytes }
        fun setDataRxBytes(dataRxBytes: Long) = apply { this.dataRxBytes = dataRxBytes }
        fun setDataTxBytes(dataTxBytes: Long) = apply { this.dataTxBytes = dataTxBytes }
        fun setSampleNanos(sampleNanos: Long) = apply { this.sampleNanos = sampleNanos }

        fun build(): Statistics =
            if (rxBytes == 0L && txBytes == 0L && dataRxBytes <= 0L && dataTxBytes <= 0L) EMPTY_STATISTICS
            else Statistics(this)
    }

    companion object {
        val EMPTY_STATISTICS: Statistics = Statistics()

        inline fun build(block: Builder.() -> Unit): Statistics = Builder().apply(block).build()
    }
}

fun Bundle.putStatistics(statistics: Statistics) {
    putLong(RX_BYTES_KEY, statistics.rxBytes)
    putLong(TX_BYTES_KEY, statistics.txBytes)
    putLong(DATA_RX_BYTES_KEY, statistics.dataRxBytes)
    putLong(DATA_TX_BYTES_KEY, statistics.dataTxBytes)
    putLong(SAMPLE_NANOS_KEY, statistics.sampleNanos)
}

fun Bundle.getStatistics(): Statistics =
    Statistics.build {
        setRxBytes(getLong(RX_BYTES_KEY))
        setTxBytes(getLong(TX_BYTES_KEY))
        setDataRxBytes(getLong(DATA_RX_BYTES_KEY, -1L))
        setDataTxBytes(getLong(DATA_TX_BYTES_KEY, -1L))
        setSampleNanos(getLong(SAMPLE_NANOS_KEY))
    }
