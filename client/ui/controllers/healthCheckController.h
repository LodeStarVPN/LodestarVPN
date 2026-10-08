#ifndef HEALTHCHECKCONTROLLER_H
#define HEALTHCHECKCONTROLLER_H

#include <functional>

#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QSet>
#include <QSharedPointer>
#include <QTcpSocket>

#include "ui/models/servers_model.h"

// Server health probe (see frkn-docs/server-healthcheck-research.md):
// TCP connect + RTT for TCP-based servers (VLESS). WG/AWG servers are
// probed with a real handshake on worker threads - via WgProbeRTT (libwg-go)
// on Apple platforms, via core/wgHandshakeProbe (OpenSSL Noise_IK) on Android
// and Windows. Hysteria2 gets a full-path probe via libxray (LibXrayPing on
// Apple, JNI LibXray.ping on Android); not available on Windows.
class HealthCheckController : public QObject
{
    Q_OBJECT
public:
    explicit HealthCheckController(const QSharedPointer<ServersModel> &serversModel, QObject *parent = nullptr);

    Q_INVOKABLE void startProbe(bool force = false);
    Q_INVOKABLE void stopProbe();

    // With the VPN on, every probe would go through the tunnel and show the
    // way via the connected server (Germany "117 ms" through the Netherlands):
    // no run starts then, and the figures from before the connect stay.
    void setVpnActive(bool active);

    // true while a probe run has unfinished targets; probingFinished fires once
    // when the last target of the run resolves (also on an external stopProbe)
    bool isProbing() const { return m_probeActive; }
    qint64 lastProbeMsecs() const { return m_lastRunMsecs; }

    // Our subscription's rows: the server of a row the app has a config of is
    // probed as any server (its address is in this device's traffic whenever
    // it connects anyway); a row without one, or whose server does not answer,
    // shows the ping from here to its landmarks - public hosts next to our
    // servers of that country (landmarks: "ip:port" list) - so no other
    // address of ours shows in the traffic. When no landmark answers either:
    // the way to the gateway's relay (gatewayEndpoint) plus the gateway's own
    // time to the servers (serverLeg: ms, -1 none answers, -2 unknown).
    void setGatewayProbe(std::function<QString()> gatewayEndpoint,
                         std::function<int(const QString &country, const QString &protocol)> serverLeg,
                         std::function<QStringList(const QString &country, const QString &protocol)> landmarks);

public slots:
    // the gateway's figures came (again): landmarks not probed yet are, and
    // the estimates are made with the new legs
    void onServerLegsUpdated();

signals:
    void probingFinished();

private:
    struct Target
    {
        QList<int> rows; // server indices sharing this endpoint
        QString host;
        quint16 port;

        // xhttp+tls (CDN) servers get a real HTTPS probe instead of a bare TCP
        // connect: the CDN edge is almost always up, so TCP says nothing about
        // the origin behind it
        QString sni;
        QString path;
        bool httpsProbe = false;
        bool gatewayRelay = false; // the way to the gateway's relay: feeds the estimates
        QStringList landmarkKeys;  // a landmark: the "country|protocol" groups it stands for
    };

    struct WgTarget
    {
        QList<int> rows; // server indices sharing this endpoint
        QString host;
        quint16 port;
        QString clientPrivKey;
        QString serverPubKey;
        QString psk;
        QString junkParamsJson;
        int attempts = 1; // lives on the target, not the watcher - retries requeue the target
    };

    struct H2Target
    {
        QList<int> rows; // server indices sharing this endpoint
        QString host;
        quint16 port;
        QJsonObject outbound; // legacy hysteria2 outbound from the stored config
    };

    void startNext();
    void finishSocket(QTcpSocket *socket, int latencyMs);

    void startNextWg();
    void finishWatcher(QFutureWatcher<int> *watcher);

    // hysteria2: full-path probe via LibXrayPing (real handshake+auth+HTTP through
    // the server) - a bare QUIC version-negotiation probe is unreliable (some live
    // servers ignore it). Runs strictly one at a time: libxray holds global state.
    void startNextH2();
    void finishH2Watcher(QFutureWatcher<int> *watcher);

    // emits probingFinished once every queue and in-flight probe of the run is done
    void maybeFinishProbe();
    // our subscription's rows: what a row shows, from its own server's probe,
    // its landmarks' and the relay estimate, in that order (see setGatewayProbe)
    void applyGatewayRow(int row);
    void applyGatewayRows();
    // a result for rows of a target: our subscription's rows go through
    // applyGatewayRow, the others are set as they come
    void applyRowsResult(const QList<int> &rows, int latencyMs);
    // queues a TCP probe of each landmark of the run's groups not probed yet
    void queueLandmarks();

    std::function<QString()> m_gatewayEndpoint;
    std::function<int(const QString &, const QString &)> m_serverLeg;
    std::function<QStringList(const QString &, const QString &)> m_landmarks;
    int m_relayMs = -2;
    qint64 m_relayAt = 0;

    // this run's state of our subscription's rows; ms >= 0, -1 none answered,
    // -2 still probing; a row or group missing has no probe of that kind
    QHash<int, QString> m_gatewayKey;      // row -> "COUNTRY|protocol"
    QHash<int, int> m_ownPending;          // row -> its own server's probes left
    QHash<int, int> m_ownResult;           // row -> its own server's best
    QHash<QString, int> m_landmarkPending; // group -> landmark probes left
    QHash<QString, int> m_landmarkResult;  // group -> its landmarks' best

    QSharedPointer<ServersModel> m_serversModel;

    QList<Target> m_queue;
    QHash<QTcpSocket *, Target> m_socketTargets;
    QHash<QTcpSocket *, QElapsedTimer> m_timers;
    QHash<QTcpSocket *, int> m_attempts;
    QHash<QString, int> m_seenTcpEndpoints; // endpoint -> position in m_queue

    QList<WgTarget> m_wgQueue;
    QHash<QFutureWatcher<int> *, WgTarget> m_wgWatchers;
    QHash<QString, int> m_seenWgEndpoints; // endpoint -> position in m_wgQueue

    QList<H2Target> m_h2Queue;
    QHash<QFutureWatcher<int> *, H2Target> m_h2Watchers;
    QHash<QString, int> m_seenH2Endpoints; // endpoint -> position in m_h2Queue

    qint64 m_lastRunMsecs = 0;
    bool m_probeActive = false;
    bool m_runOpen = false; // a run started and not stopped (the VPN off)
    bool m_vpnActive = false;

    static constexpr int kMaxParallel = 8;
    static constexpr int kWgMaxParallel = 3;
    static constexpr int kTimeoutMs = 2500;
    static constexpr int kHttpsTimeoutMs = 4000;
    static constexpr int kWgTimeoutMs = 4000;
    static constexpr int kH2TimeoutSec = 6;
    static constexpr qint64 kThrottleMs = 30000;
};

#endif // HEALTHCHECKCONTROLLER_H
