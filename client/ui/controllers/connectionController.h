#ifndef CONNECTIONCONTROLLER_H
#define CONNECTIONCONTROLLER_H

#include <QList>
#include <QStringList>
#include <QTimer>
#include <QElapsedTimer>

#include "protocols/vpnprotocol.h"
#include "ui/models/containers_model.h"
#include "ui/models/servers_model.h"
#include "vpnconnection.h"

class HealthCheckController;
class ApiConfigsController;
class QTcpSocket;
class QSslSocket;

class ConnectionController : public QObject
{
    Q_OBJECT

public:
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY connectionStateChanged)
    Q_PROPERTY(bool isConnectionInProgress READ isConnectionInProgress NOTIFY connectionStateChanged)
    Q_PROPERTY(QString connectionStateText READ connectionStateText NOTIFY connectionStateChanged)
    Q_PROPERTY(QString currentEndpoint READ currentEndpoint NOTIFY connectionStateChanged)
    Q_PROPERTY(QString downloadSpeed READ downloadSpeed NOTIFY speedChanged)
    Q_PROPERTY(QString uploadSpeed READ uploadSpeed NOTIFY speedChanged)
    Q_PROPERTY(QString ping READ ping NOTIFY pingChanged)

    explicit ConnectionController(const QSharedPointer<ServersModel> &serversModel, const QSharedPointer<ContainersModel> &containersModel,
                                  const QSharedPointer<VpnConnection> &vpnConnection, const std::shared_ptr<Settings> &settings,
                                  QObject *parent = nullptr);

    ~ConnectionController() override;

    // needed only for auto server selection; may stay null (auto falls back to default server)
    void setHealthCheckController(HealthCheckController *healthCheckController);
    // used by auto selection to install per-row configs from the gateway (they are
    // otherwise fetched lazily on the first manual connect)
    void setApiConfigsController(ApiConfigsController *apiConfigsController);

    bool isConnected() const;
    bool isConnectionInProgress() const;
    QString connectionStateText() const;
    QString currentEndpoint() const { return m_currentEndpoint; }
    QString downloadSpeed() const { return m_downloadSpeed; }
    QString uploadSpeed() const { return m_uploadSpeed; }
    QString ping() const { return m_ping; }

public slots:
    void toggleConnection();

    void openConnection();
    void closeConnection();

    ErrorCode getLastConnectionError();
    void onConnectionStateChanged(Vpn::ConnectionState state);

    void onTranslationsUpdated();

signals:
    void connectToVpn(int serverIndex, const ServerCredentials &credentials, DockerContainer container, const QJsonObject &vpnConfiguration);
    void disconnectFromVpn();
    void connectionStateChanged();

    void connectionErrorOccurred(ErrorCode errorCode);

    void connectButtonClicked();
    void preparingConfig();
    void prepareConfig();
    void speedChanged();
    void pingChanged();

private:
    Vpn::ConnectionState getCurrentConnectionState();

    // asks the gateway first (see checkDevice), then dialServerIndex
    void connectToServerIndex(int serverIndex);
    void dialServerIndex(int serverIndex);
    void connectToServerIndexWithIp(int serverIndex, const QString &ip);

    // --- multi-IP failover (node_ips) ---
    // a server may carry several equivalent entry addresses (node_ips from the API,
    // same node/keys/ports - only the entry address differs). Every connect starts
    // from a random address of a freshly shuffled pool; a hard failure or a
    // traffic-less "Connected" retries the next address from the pool.
    // Single-address xray rows on desktop get a pool of one, so the same
    // traffic check (and the gateway refresh after it) guards them too.
    bool retryWithNextIp();
    void resetIpPool();

    // An address that comes up but carries no traffic is typically blocked for
    // this user (ISP/DPI) while fine for everyone else. Remember it so later
    // connects try it last instead of starting there again; it's only moved to
    // the end of the pool (never dropped) and forgotten after the TTL.
    void markEndpointFailed(const QString &endpoint);
    void markEndpointWorking(const QString &endpoint);
    static constexpr qint64 kFailedEndpointTtlMs = 60 * 60 * 1000;

    // A manual connect that ran out of addresses asks the gateway once for a
    // fresh config (configs are otherwise only refreshed on app start, every
    // 6h) - the operator may have replaced blocked servers or changed their
    // parameters (SNI, keys) meanwhile; it retries if anything that affects
    // the connection changed. The request goes out only after the dead
    // tunnel is down, else it would be routed into it; a cancel or a new
    // connect in between voids the retry.
    void beginPoolRefresh(int row);
    void sendPoolRefresh();
    void onPoolRefreshed(int row, const QByteArray &connectionBefore, bool ok);

    // --- device check ---
    // On every connection and every kDeviceCheckIntervalMs while connected the
    // gateway is asked whether this device is still one of the subscription's.
    // A refusal (unlinked, no free place) disconnects and removes the
    // subscription's servers from the app (an ended subscription only
    // disconnects); a failed request changes nothing, so
    // an unreachable gateway never takes the VPN away. This is what keeps an
    // unlinked device off VLESS, whose servers cannot tell devices apart.
    // Before every connect the check also tells the gateway the country and
    // protocol: only the device's AWG peer of that country stays on the
    // servers, so a config of another country handed to someone else stops
    // working. The connect waits for the answer at most kPreCheckTimeoutMs.
    void checkDevice();
    void refuseDevice(int row, ErrorCode errorCode);
    QTimer *m_deviceCheckTimer = nullptr;
    static constexpr int kDeviceCheckIntervalMs = 15 * 60 * 1000;
    static constexpr int kPreCheckTimeoutMs = 4000;
    bool m_preCheckPending = false;
    int m_tunnelRow = -1; // the entry the current tunnel was started for
    static QByteArray connectionFingerprint(const QJsonObject &serverConfig);
    quint64 m_connectAttempt = 0;
    bool m_poolRefreshAttempted = false; // at most once per user connect
    bool m_poolRefreshInFlight = false;  // keeps the UI in "Connecting..."
    int m_poolRefreshRow = -1;           // set until the teardown finished
    QByteArray m_poolRefreshConnectionBefore;

    QStringList m_ipPool;
    int m_ipPoolPos = 0;
    int m_ipPoolRow = -1;
    QString m_currentEndpoint; // entry address actually used by the running/last attempt
    bool m_connectionSwitching = false; // teardown states between (re)connects are not failures
    QTimer *m_ipTrafficTimer = nullptr;
    bool m_ipAwaitingTraffic = false; // connected to a multi-IP server, waiting for bytes

    // live speed meter (server card): computed from bytesChanged deltas
    QString m_downloadSpeed;
    QString m_uploadSpeed;
    QElapsedTimer m_speedTimer;
    static QString formatSpeed(qint64 bytesPerSec);

    // live ping (server card), TCP handshake RTT through the tunnel
    void startLivePing();
    void stopLivePing();
    void probeLivePing();
    void finishLivePing(QTcpSocket *socket, bool ok);

    QString m_ping;
    // desktop xray measures its own ping (VpnConnection::latencyChanged): our
    // TCP-connect probe would be answered locally by tun2socks (~1 ms)
    bool m_pingFromProtocol = false;
    QTimer *m_pingTimer = nullptr;
    QTcpSocket *m_pingSocket = nullptr;
    QElapsedTimer m_pingElapsed;
    int m_pingHostIndex = 0;
    static constexpr int kLivePingIntervalMs = 3000;
    static constexpr int kLivePingTimeoutMs = 4000;
    static constexpr int kIpTrafficTimeoutMs = 8000;
    // ---

    // --- stalled-tunnel watchdog (WG/AWG on desktop) ---
    // A tunnel can stay up, with a handshake every 2 min, while real traffic
    // no longer gets through: on 2026-10-04 for minutes only small packets
    // came back (the live ping and DNS answered, pages did not load) until
    // the user reconnected, and the new connection worked at once. Every
    // kStallProbeIntervalMs a TLS handshake through the tunnel brings a few
    // full-size packets back. Once a probe has passed on this connection, two
    // failed ones in a row reconnect, as the user's off/on did, but only
    // while some packets still arrive: with nothing arriving at all the
    // network is down and WireGuard resumes by itself once it is back, and a
    // tunnel that moves a lot works (a probe host is slow or unreachable).
    // At most one reconnect per kStallReconnectGapMs.
    void startStallWatch();
    void stopStallWatch();
    void probeStall();
    void finishStallProbe(QSslSocket *socket, bool ok);

    QTimer *m_stallTimer = nullptr;
    QSslSocket *m_stallSocket = nullptr;
    bool m_stallWatching = false;
    bool m_stallArmed = false;        // a probe passed on this connection
    bool m_stallTcpConnected = false; // the running probe got past the TCP connect
    int m_stallFailures = 0;          // failed probes in a row
    int m_stallHostIndex = 0;
    quint64 m_stallRxPrevious = 0;    // bytes received while the previous probe ran
    quint64 m_stallRxCurrent = 0;     // ... and since the current one began
    QElapsedTimer m_stallLastReconnect;
    static constexpr int kStallProbeIntervalMs = 30000;
    static constexpr int kStallRetryMs = 5000;
    static constexpr int kStallProbeTimeoutMs = 10000;
    static constexpr quint64 kStallBusyRxBytes = 256 * 1024;
    static constexpr qint64 kStallReconnectGapMs = 3 * 60 * 1000;
    // ---

    // --- manual-connect watchdog ---
    // a blocked server produces no state events at all (handshake never gets
    // an answer) - without this the UI spins "Connecting..." forever. On
    // expiry: try the next pool address, otherwise fail loudly.
    QTimer *m_manualConnectTimer = nullptr;
    // Android: the attempt's timers paused while the system's permission dialogs are up
    bool m_resumeManualTimer = false;
    bool m_resumeAutoTimer = false;
    static constexpr int kManualConnectTimeoutMs = 20000;
    // per address while the pool has more left: WG/AWG retries its handshake
    // every 5 s, so this is ~3 tries before moving to the next address
    static constexpr int kPoolAttemptTimeoutMs = 12000;
    // ---

    // --- auto server selection (Settings::isAutoServerSelection) ---
    // protocol priority: AmneziaWgMobile -> AmneziaWg/WireGuard -> Hysteria2 ->
    // VLESS -> VlessXhttpCdn (last-resort fallback). A candidate with rtt <=
    // kAutoAcceptLatencyMs in the best available tier is taken immediately.
    // Candidates the probe did NOT confirm get a post-connect traffic check:
    // no bytes flowing within kAutoTrafficTimeoutMs = try the next one.
    struct AutoCandidate
    {
        int row;
        int tier;
        int latency; // >=0 rtt ms, -1 offline, -2 not probed
    };

    enum class AutoPhase { None, Probing, Connecting };

    void startAutoSelection();
    bool tryEarlyAutoDecision();
    void onAutoHealthUpdated();
    void onAutoProbeSettled();
    void beginAutoConnect();
    void connectCurrentAutoCandidate();
    void cancelAutoSelection();
    void finalizeAutoSuccess();

    QList<AutoCandidate> buildAutoCandidates() const;
    void installMissingConfigs();
    int tierForRow(int row) const;
    bool isVlessCdnRow(int row) const;
    // index into the ordered candidate list; 0 when nothing is probe-confirmed
    // (we still try in priority order - an "offline" badge is not a verdict)
    int pickAutoCandidate(const QList<AutoCandidate> &candidates) const;
    // load of the row's country over its protocol (gateway v1/load), -1 unknown
    double rowLoad(int row) const;
    // the addresses in a random order weighted by spare capacity
    QStringList weightedOrder(const QStringList &ips, const QString &protocol, const QJsonObject &storedWeights,
                              const QJsonObject &nodeIds) const;

    HealthCheckController *m_healthCheckController = nullptr;
    ApiConfigsController *m_apiConfigsController = nullptr;
    AutoPhase m_autoPhase = AutoPhase::None;
    QList<AutoCandidate> m_autoCandidates;
    int m_autoCandidatePos = 0;
    bool m_autoAdvancing = false; // teardown states between attempts are not a user cancel
    bool m_autoAwaitingTraffic = false; // connected to an unprobed server, waiting for bytes
    QTimer *m_autoProbeTimer;
    QTimer *m_autoAttemptTimer;

    static constexpr int kAutoAcceptLatencyMs = 80;
    // auto selection spreads over the servers whose ping is within
    // max(kAutoNearbyMs, 30%) of the best one, never to a far country
    static constexpr int kAutoNearbyMs = 25;
    static constexpr qint64 kAutoFreshProbeMs = 60000;
    static constexpr int kAutoProbeTimeoutMs = 10000;
    static constexpr int kAutoAttemptTimeoutMs = 15000;
    static constexpr int kAutoTrafficTimeoutMs = 8000;
    // ---

    void continueConnection();

    QSharedPointer<ServersModel> m_serversModel;
    QSharedPointer<ContainersModel> m_containersModel;

    QSharedPointer<VpnConnection> m_vpnConnection;

    std::shared_ptr<Settings> m_settings;

    bool m_isConnected = false;
    bool m_isConnectionInProgress = false;
    QString m_connectionStateText = tr("Connect");

    Vpn::ConnectionState m_state;
};

#endif // CONNECTIONCONTROLLER_H
