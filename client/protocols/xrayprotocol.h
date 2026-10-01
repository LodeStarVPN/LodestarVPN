#ifndef XRAYPROTOCOL_H
#define XRAYPROTOCOL_H

#include "QProcess"

#include "core/ipcclient.h"
#include "vpnprotocol.h"
#include "settings.h"
#include <QtCore/qsharedpointer.h>

#include <memory>
#include <vector>

class QTimer;
class TunnelHttpProbe;

class XrayProtocol : public VpnProtocol
{
public:
    XrayProtocol(const QJsonObject &configuration, QObject *parent = nullptr);
    virtual ~XrayProtocol() override;

    ErrorCode start() override;
    void stop() override;

private:
    ErrorCode setupRouting();
    ErrorCode startTun2Socks();

    // Desktop xray reports no byte counters, and tun-level ones would lie:
    // tun2socks completes every app's TCP handshake itself, so a tunnel whose
    // server is unreachable (DPI-blocked, stale SNI/keys) still "moves bytes".
    // After Connected this fetches a tiny page through xray's own SOCKS
    // inbound; only a real HTTP answer counts, reported as received bytes —
    // the proof ConnectionController's traffic checks wait for.
    void startTrafficProbe();
    // every probe connection reports here: its first answer (from either proof
    // connection) proves the tunnel, later ones on the kept one are the ping
    void onProbeAnswer(TunnelHttpProbe *probe, qint64 elapsedMs, qint64 bytes, bool first);
    void onTrafficProven(TunnelHttpProbe *probe, qint64 answerBytes);
    // Once proven: the tun adapter's byte counters (Windows) feed the speed
    // meter - safe now, before the proof they'd fool the traffic check - and
    // a request every few seconds over the kept-alive probe connection
    // measures the ping (latencyChanged): a TCP-connect ping through the
    // tunnel would time tun2socks' local handshake, ~1 ms.
    void onLiveStatsTick();
    void stopLiveStats();
    bool readTunCounters(quint64 &received, quint64 &sent) const;

    int m_localProxyPort = 0;
    int m_vpnAdapterIndex = -1;
    std::vector<std::unique_ptr<TunnelHttpProbe>> m_proofProbes;
    std::unique_ptr<TunnelHttpProbe> m_latencyProbe;
    QTimer *m_liveStatsTimer = nullptr;
    int m_liveStatsTicks = 0;
    bool m_trafficProven = false;
    quint64 m_tunBaseReceived = 0;
    quint64 m_tunBaseSent = 0;

    QJsonObject m_xrayConfig;
    Settings::RouteMode m_routeMode;
    QList<QHostAddress> m_dnsServers;
    QString m_remoteAddress;

    QSharedPointer<IpcProcessInterfaceReplica> m_tun2socksProcess;

    // Bumped by every stop(). The IPC calls here block in nested event loops,
    // where a queued stop()/disconnect can run and even delete this object
    // (VpnConnection drops it synchronously on desktop), so multi-step
    // sequences re-check this (plus a QPointer) after each wait and abandon
    // their remaining steps instead of acting on a torn-down connection.
    quint64 m_stopGeneration = 0;
};

#endif // XRAYPROTOCOL_H
