#include "xrayprotocol.h"

#include "core/ipcclient.h"
#include "ipc.h"
#include "utilities.h"
#include "core/networkUtilities.h"

#include <QCryptographicHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QJsonDocument>
#include <QElapsedTimer>
#include <QPointer>
#include <QTcpSocket>
#include <QTimer>

#include <functional>

#ifdef Q_OS_WIN
    // WS2tcpip (ws2ipdef) first, as in the daemon: netioapi.h declares the
    // MIB_IF_ROW2 counters only when it is already in
    #include <WS2tcpip.h>
    #include <iphlpapi.h>
#endif
#include <QtCore/qlogging.h>
#include <QtCore/qobjectdefs.h>
#include <QtCore/qprocess.h>

#ifdef Q_OS_MACOS
static const QString tunName = "utun22";
#elif defined(Q_OS_WIN)
// not "tun2": AmneziaVPN and Dopamine name theirs so (and use 10.33.0.2), and
// one of them may be running next to us
static const QString tunName = "LodestarTun";
#else
static const QString tunName = "tun2";
#endif

// HTTP/1.1 through xray's SOCKS inbound: SOCKS5 CONNECT host:80, then HEAD
// requests on that one kept-alive connection. xray answers the CONNECT
// itself before dialing out, so only an HTTP answer proves the tunnel; the
// time to later answers is the tunnel's round trip (the first one also pays
// for opening the connection to the server).
class TunnelHttpProbe
{
public:
    using AnswerHandler = std::function<void(TunnelHttpProbe *probe, qint64 elapsedMs, qint64 bytes, bool first)>;

    TunnelHttpProbe(int socksPort, const QByteArray &host, AnswerHandler onAnswer)
        : m_host(host),
          m_request("HEAD /generate_204 HTTP/1.1\r\nHost: " + host + "\r\n\r\n"),
          m_onAnswer(std::move(onAnswer))
    {
        QObject::connect(&m_socket, &QTcpSocket::connected, [this]() {
            m_socket.write(QByteArray("\x05\x01\x00", 3)); // SOCKS5, one method: no auth
        });
        QObject::connect(&m_socket, &QTcpSocket::readyRead, [this]() { onReadyRead(); });
        m_socket.connectToHost(QHostAddress::LocalHost, socksPort);
    }

    ~TunnelHttpProbe()
    {
        m_socket.disconnect(); // abort() must not call back into a dying object
        m_socket.abort();
    }

    bool isAlive() const { return m_socket.state() != QAbstractSocket::UnconnectedState; }
    qint64 requestSize() const { return m_request.size(); }
    // how long the current request has been waiting, -1 when none is
    qint64 pendingMs() const { return m_inFlight && m_elapsed.isValid() ? m_elapsed.elapsed() : -1; }

    // one request at a time; one made during the SOCKS setup goes out after it
    void request()
    {
        if (m_inFlight) {
            return;
        }
        m_inFlight = true;
        if (m_stage == Stage::Ready) {
            send();
        }
    }

private:
    enum class Stage { Method, ConnectReply, Ready };

    void send()
    {
        m_elapsed.start();
        m_socket.write(m_request);
    }

    void onReadyRead()
    {
        m_buffer.append(m_socket.readAll());
        if (m_stage == Stage::Method) {
            if (m_buffer.size() < 2) {
                return;
            }
            if (m_buffer.at(0) != 0x05 || m_buffer.at(1) != 0x00) {
                return m_socket.abort();
            }
            m_buffer.remove(0, 2);
            QByteArray connectRequest("\x05\x01\x00\x03", 4); // CONNECT, domain name
            connectRequest.append(static_cast<char>(m_host.size())).append(m_host).append("\x00\x50", 2); // :80
            m_socket.write(connectRequest);
            m_stage = Stage::ConnectReply;
        }
        if (m_stage == Stage::ConnectReply) {
            // VER REP RSV ATYP BND.ADDR BND.PORT
            if (m_buffer.size() < 5) {
                return;
            }
            if (m_buffer.at(1) != 0x00) {
                return m_socket.abort();
            }
            const int atyp = m_buffer.at(3);
            const int replySize = atyp == 0x01 ? 10 : atyp == 0x04 ? 22 : 7 + static_cast<quint8>(m_buffer.at(4));
            if (m_buffer.size() < replySize) {
                return;
            }
            m_buffer.remove(0, replySize);
            m_stage = Stage::Ready;
            if (m_inFlight) {
                send();
            }
            return;
        }
        // the answer to HEAD is just the header block
        const qsizetype end = m_buffer.indexOf("\r\n\r\n");
        if (!m_inFlight || end < 0) {
            return;
        }
        if (!m_buffer.startsWith("HTTP/1.")) {
            return m_socket.abort();
        }
        const qint64 bytes = end + 4;
        m_buffer.remove(0, bytes);
        m_inFlight = false;
        const bool first = !m_answered;
        m_answered = true;
        // the handler may delete other probes, never this one
        m_onAnswer(this, m_elapsed.elapsed(), bytes, first);
    }

    QTcpSocket m_socket;
    QByteArray m_host;
    QByteArray m_request;
    AnswerHandler m_onAnswer;
    QByteArray m_buffer;
    QElapsedTimer m_elapsed;
    Stage m_stage = Stage::Method;
    bool m_inFlight = false;
    bool m_answered = false;
};

XrayProtocol::XrayProtocol(const QJsonObject &configuration, QObject *parent) : VpnProtocol(configuration, parent)
{
    m_vpnGateway = amnezia::protocols::xray::defaultLocalAddr;
    m_vpnLocalAddress = amnezia::protocols::xray::defaultLocalAddr;
    m_routeGateway = NetworkUtilities::getGatewayAndIface().first;

    m_routeMode = static_cast<Settings::RouteMode>(configuration.value(amnezia::config_key::splitTunnelType).toInt());
    m_remoteAddress = NetworkUtilities::getIPAddress(m_rawConfig.value(amnezia::config_key::hostName).toString());

    const QString primaryDns = configuration.value(amnezia::config_key::dns1).toString();
    m_dnsServers.push_back(QHostAddress(primaryDns));
    if (primaryDns != amnezia::protocols::dns::amneziaDnsIp) {
        const QString secondaryDns = configuration.value(amnezia::config_key::dns2).toString();
        m_dnsServers.push_back(QHostAddress(secondaryDns));
    }

    QJsonObject xrayConfiguration = configuration.value(ProtocolProps::key_proto_config_data(Proto::Xray)).toObject();
    if (xrayConfiguration.isEmpty()) {
        xrayConfiguration = configuration.value(ProtocolProps::key_proto_config_data(Proto::SSXray)).toObject();
    }
    m_xrayConfig = xrayConfiguration;
}

XrayProtocol::~XrayProtocol()
{
    qDebug() << "XrayProtocol::~XrayProtocol()";
    XrayProtocol::stop();
}

ErrorCode XrayProtocol::start()
{
    qDebug() << "XrayProtocol::start()";

    const QPointer<XrayProtocol> self(this);
    const quint64 generation = m_stopGeneration;

    return IpcClient::withInterface([&](QSharedPointer<IpcInterfaceReplica> iface) {
        auto xrayStart = iface->xrayStart(QJsonDocument(m_xrayConfig).toJson());
        const bool started = xrayStart.waitForFinished() && xrayStart.returnValue();
        if (!self || m_stopGeneration != generation) {
            // cancelled while xray was starting; the teardown already reported
            // Disconnected, so there is no error to raise on top of it
            return ErrorCode::NoError;
        }
        if (!started) {
            qCritical() << "Failed to start xray";
            return ErrorCode::XrayExecutableCrashed;
        }
        return startTun2Socks();
    }, [] () {
        return ErrorCode::DopamineServiceConnectionFailed;
    });
}

void XrayProtocol::stop()
{
    qDebug() << "XrayProtocol::stop()";

    ++m_stopGeneration;
    const QPointer<XrayProtocol> self(this);
    stopLiveStats();

    IpcClient::withInterface([](QSharedPointer<IpcInterfaceReplica> iface) {
        auto disableKillSwitch = iface->disableKillSwitch();
        if (!disableKillSwitch.waitForFinished() || !disableKillSwitch.returnValue())
            qWarning() << "Failed to disable killswitch";

        auto StartRoutingIpv6 = iface->StartRoutingIpv6();
        if (!StartRoutingIpv6.waitForFinished() || !StartRoutingIpv6.returnValue())
            qWarning() << "Failed to start routing ipv6";

        auto restoreResolvers = iface->restoreResolvers();
        if (!restoreResolvers.waitForFinished() || !restoreResolvers.returnValue())
            qWarning() << "Failed to restore resolvers";

        auto deleteTun = iface->deleteTun(tunName);
        if (!deleteTun.waitForFinished() || !deleteTun.returnValue())
            qWarning() << "Failed to delete tun";

        auto xrayStop = iface->xrayStop();
        if (!xrayStop.waitForFinished() || !xrayStop.returnValue())
            qWarning() << "Failed to stop xray";
    });

    if (!self) {
        return;
    }

    if (m_tun2socksProcess) {
        // detach first: a re-entrant stop() during the wait below must not tear
        // the same process down twice, and queued output handlers must see none
        QSharedPointer<IpcProcessInterfaceReplica> tun2socksProcess;
        tun2socksProcess.swap(m_tun2socksProcess);
        tun2socksProcess->blockSignals(true);

#ifndef Q_OS_WIN
        tun2socksProcess->terminate();
        auto waitForFinished = tun2socksProcess->waitForFinished(1000);
        if (!waitForFinished.waitForFinished() || !waitForFinished.returnValue()) {
            qWarning() << "Failed to terminate tun2socks. Killing the process...";
            tun2socksProcess->kill();
        }
#else
        // terminate does not do anything useful on Windows
        // so just kill the process
        tun2socksProcess->kill();
#endif

        tun2socksProcess->close();
    }

    if (!self) {
        return;
    }
    setConnectionState(Vpn::ConnectionState::Disconnected);
}

ErrorCode XrayProtocol::startTun2Socks()
{
    const QPointer<XrayProtocol> self(this);
    const quint64 generation = m_stopGeneration;

    // hold our own reference: a stop() running inside waitForSource()'s nested
    // loop detaches and releases m_tun2socksProcess while we still wait on it
    const auto tun2socksProcess = IpcClient::CreatePrivilegedProcess();
    if (!tun2socksProcess) {
        return ErrorCode::DopamineServiceConnectionFailed;
    }
    m_tun2socksProcess = tun2socksProcess;
    const bool sourceReady = tun2socksProcess->waitForSource();
    if (!self || m_stopGeneration != generation) {
        return ErrorCode::NoError; // cancelled, see start()
    }
    if (!sourceReady) {
        return ErrorCode::DopamineServiceConnectionFailed;
    }

    m_tun2socksProcess->setProgram(PermittedProcess::Tun2Socks);
    // the socks inbound port is chosen per-connect (random, see
    // vpnConfigurationController) - read it back from the config
    int localProxyPort = QString(amnezia::protocols::xray::defaultLocalProxyPort).toInt();
    const QJsonArray inbounds = m_xrayConfig.value(QStringLiteral("inbounds")).toArray();
    if (!inbounds.isEmpty()) {
        const int port = inbounds.first().toObject().value(QStringLiteral("port")).toInt();
        if (port > 0) {
            localProxyPort = port;
        }
    }
    m_localProxyPort = localProxyPort;
    m_tun2socksProcess->setArguments({"-device", QString("tun://%1").arg(tunName), "-proxy",
                                      QString("socks5://127.0.0.1:%1").arg(localProxyPort) });

    // Both handlers are queued, so they may run after stop() already detached
    // this process (or a reconnect replaced it) - ignore those stale calls.
    connect(m_tun2socksProcess.data(), &IpcProcessInterfaceReplica::readyReadStandardOutput, this,
            [this, process = m_tun2socksProcess.data()]() {
        if (m_tun2socksProcess.data() != process) {
            return;
        }
        const QPointer<XrayProtocol> self(this);
        const quint64 generation = m_stopGeneration;
        const auto stillRunning = [&] { return self && m_stopGeneration == generation; };
        const auto tun2socksProcess = m_tun2socksProcess;

        auto readAllStandardOutput = tun2socksProcess->readAllStandardOutput();
        const bool read = readAllStandardOutput.waitForFinished();
        if (!stillRunning()) {
            return;
        }
        if (!read) {
            qWarning() << "Failed to read output from tun2socks";
            return;
        }

        const QString line = readAllStandardOutput.returnValue();

        if (!line.contains("[TCP]") && !line.contains("[UDP]"))
            qDebug() << "[tun2socks]:" << line;
        
        if (line.contains("[STACK] tun://") && line.contains("<-> socks5://127.0.0.1")) {
            disconnect(tun2socksProcess.data(), &IpcProcessInterfaceReplica::readyReadStandardOutput, this, nullptr);

            const ErrorCode res = setupRouting();
            if (!stillRunning()) {
                // cancelled mid-setup: stop() already tore the tunnel down and
                // setupRouting() skipped its remaining steps
                return;
            }
            if (res != ErrorCode::NoError) {
                stop();
                if (self) {
                    setLastError(res);
                }
            } else {
                setConnectionState(Vpn::ConnectionState::Connected);
                if (stillRunning()) {
                    startTrafficProbe();
                }
            }
        }
    }, Qt::QueuedConnection);

    connect(m_tun2socksProcess.data(), &IpcProcessInterfaceReplica::finished, this,
            [this, process = m_tun2socksProcess.data()](int exitCode, QProcess::ExitStatus exitStatus) {
        if (m_tun2socksProcess.data() != process) {
            return;
        }
        if (exitStatus == QProcess::ExitStatus::CrashExit) {
            qCritical() << "Tun2socks process crashed!";
        } else {
            qCritical() << QString("Tun2socks process was closed with %1 exit code").arg(exitCode);
        }
        const QPointer<XrayProtocol> self(this);
        stop();
        if (self) {
            setLastError(ErrorCode::Tun2SockExecutableCrashed);
        }
    }, Qt::QueuedConnection);

    // The service went away (stopped, crashed): tun2socks, xray, the routes and
    // the kill switch went with it, and no "finished" ever comes - without this
    // the app would go on showing Connected over an open connection.
    connect(m_tun2socksProcess.data(), &QRemoteObjectReplica::stateChanged, this,
            [this, process = m_tun2socksProcess.data()](QRemoteObjectReplica::State state, QRemoteObjectReplica::State) {
        if (m_tun2socksProcess.data() != process || state != QRemoteObjectReplica::Suspect) {
            return;
        }
        qCritical() << "Lost the service while connected";
        const QPointer<XrayProtocol> self(this);
        stop();
        if (self) {
            setLastError(ErrorCode::DopamineServiceNotRunning);
        }
    }, Qt::QueuedConnection);

    m_tun2socksProcess->start();
    return ErrorCode::NoError;
}

void XrayProtocol::startTrafficProbe()
{
    // two independent targets: one of them being unreachable from the exit
    // must not fail a working tunnel
    static const QByteArray kProbeHosts[] = { "cp.cloudflare.com", "www.gstatic.com" };
    constexpr int kProofTimeoutMs = 7000; // inside the controller's 8 s traffic window

    stopLiveStats();
    for (const QByteArray &host : kProbeHosts) {
        auto probe = std::make_unique<TunnelHttpProbe>(m_localProxyPort, host,
                [this](TunnelHttpProbe *answered, qint64 elapsedMs, qint64 bytes, bool first) {
            onProbeAnswer(answered, elapsedMs, bytes, first);
        });
        probe->request();
        m_proofProbes.push_back(std::move(probe));
    }
    const quint64 generation = m_stopGeneration;
    QTimer::singleShot(kProofTimeoutMs, this, [this, generation]() {
        if (m_stopGeneration == generation && !m_trafficProven) {
            // no answer: the controller's traffic check fails this attempt
            m_proofProbes.clear();
        }
    });
}

void XrayProtocol::onProbeAnswer(TunnelHttpProbe *probe, qint64 elapsedMs, qint64 bytes, bool first)
{
    if (!m_trafficProven) {
        onTrafficProven(probe, bytes);
    } else if (!first && probe == m_latencyProbe.get()) {
        // the first answer on a connection also pays for reaching the server
        emit latencyChanged(static_cast<int>(elapsedMs));
    }
}

void XrayProtocol::onTrafficProven(TunnelHttpProbe *probe, qint64 answerBytes)
{
    m_trafficProven = true;
    qDebug() << "[xray] traffic proven: HTTP answer through the tunnel";
    emit bytesChanged(static_cast<quint64>(answerBytes), static_cast<quint64>(probe->requestSize()));

    // keep the answering connection for the ping, close the other one
    for (auto &proofProbe : m_proofProbes) {
        if (proofProbe.get() == probe) {
            m_latencyProbe = std::move(proofProbe);
        }
    }
    m_proofProbes.clear();

    m_tunBaseReceived = 0;
    m_tunBaseSent = 0;
    readTunCounters(m_tunBaseReceived, m_tunBaseSent);
    m_liveStatsTicks = 0;
    if (!m_liveStatsTimer) {
        m_liveStatsTimer = new QTimer(this);
        m_liveStatsTimer->setInterval(1000);
        connect(m_liveStatsTimer, &QTimer::timeout, this, [this]() { onLiveStatsTick(); });
    }
    m_liveStatsTimer->start();
}

void XrayProtocol::onLiveStatsTick()
{
    constexpr int kLatencyEveryTicks = 3; // the UI refreshes its ping every 3 s
    constexpr qint64 kLatencyTimeoutMs = 6000;

    quint64 received = 0;
    quint64 sent = 0;
    if (readTunCounters(received, sent) && received >= m_tunBaseReceived && sent >= m_tunBaseSent) {
        // cumulative since the proof; VpnProtocol turns it into per-tick deltas
        setBytesChanged(received - m_tunBaseReceived, sent - m_tunBaseSent);
    }

    if (++m_liveStatsTicks % kLatencyEveryTicks != 0) {
        return;
    }
    if (m_latencyProbe && m_latencyProbe->pendingMs() > kLatencyTimeoutMs) {
        // no answer: the tunnel stalled - don't leave the last good ping on
        // screen, and retry on a fresh connection
        emit latencyChanged(-1);
        m_latencyProbe.reset();
    }
    if (!m_latencyProbe || !m_latencyProbe->isAlive()) {
        m_latencyProbe = std::make_unique<TunnelHttpProbe>(m_localProxyPort, "cp.cloudflare.com",
                [this](TunnelHttpProbe *answered, qint64 elapsedMs, qint64 bytes, bool first) {
            onProbeAnswer(answered, elapsedMs, bytes, first);
        });
    }
    m_latencyProbe->request();
}

void XrayProtocol::stopLiveStats()
{
    if (m_liveStatsTimer) {
        m_liveStatsTimer->stop();
    }
    m_proofProbes.clear();
    m_latencyProbe.reset();
    m_trafficProven = false;
}

bool XrayProtocol::readTunCounters(quint64 &received, quint64 &sent) const
{
#ifdef Q_OS_WIN
    if (m_vpnAdapterIndex < 0) {
        return false;
    }
    MIB_IF_ROW2 row = {};
    row.InterfaceIndex = static_cast<NET_IFINDEX>(m_vpnAdapterIndex);
    if (GetIfEntry2(&row) != NO_ERROR) {
        return false;
    }
    // In = delivered to the system from the tunnel (download)
    received = row.InOctets;
    sent = row.OutOctets;
    return true;
#else
    // no tun counters here yet: the speed meter stays empty, the ping works
    Q_UNUSED(received);
    Q_UNUSED(sent);
    return false;
#endif
}

ErrorCode XrayProtocol::setupRouting() {
    // A stop() (user cancel) can run inside any of the waits below, even
    // deleting us. Then skip the remaining steps: carrying on would re-apply
    // kill switch / catch-all routes after stop() already removed the tunnel.
    // The caller re-checks too, so the returned code is ignored in that case.
    const QPointer<XrayProtocol> self(this);
    const quint64 generation = m_stopGeneration;
    const auto stillRunning = [&] { return self && m_stopGeneration == generation; };

    return IpcClient::withInterface([this, &stillRunning](QSharedPointer<IpcInterfaceReplica> iface) -> ErrorCode {
#ifdef Q_OS_WIN
        const int inetAdapterIndex = NetworkUtilities::AdapterIndexTo(QHostAddress(m_remoteAddress));
#endif
        auto createTun = iface->createTun(tunName, amnezia::protocols::xray::defaultLocalAddr);
        if (!createTun.waitForFinished() || !createTun.returnValue()) {
            qCritical() << "Failed to assign IP address for TUN";
            return ErrorCode::TunAddressError;
        }
        if (!stillRunning())
            return ErrorCode::NoError;

        auto updateResolvers = iface->updateResolvers(tunName, m_dnsServers);
        if (!updateResolvers.waitForFinished() || !updateResolvers.returnValue()) {
            qCritical() << "Failed to set DNS resolvers for TUN";
            return ErrorCode::TunDnsError;
        }
        if (!stillRunning())
            return ErrorCode::NoError;

#ifdef Q_OS_WIN
        int vpnAdapterIndex = -1;
        QList<QNetworkInterface> netInterfaces = QNetworkInterface::allInterfaces();
        for (auto& netInterface : netInterfaces) {
            for (auto& address : netInterface.addressEntries()) {
                if (m_vpnLocalAddress == address.ip().toString())
                    vpnAdapterIndex = netInterface.index();
            }
        }
        m_vpnAdapterIndex = vpnAdapterIndex; // its byte counters feed the speed meter
#else
        static const int vpnAdapterIndex = 0;
#endif
        const bool killSwitchEnabled = QVariant(m_rawConfig.value(config_key::killSwitchOption).toString()).toBool();
        if (killSwitchEnabled) {
            if (vpnAdapterIndex != -1) {
                QJsonObject config = m_rawConfig;
                config.insert("vpnServer", m_remoteAddress);

                auto enableKillSwitch = iface->enableKillSwitch(config, vpnAdapterIndex);
                if (!enableKillSwitch.waitForFinished() || !enableKillSwitch.returnValue()) {
                    qCritical() << "Failed to enable killswitch";
                    return ErrorCode::KillSwitchError;
                }
                if (!stillRunning())
                    return ErrorCode::NoError;
            } else
                qWarning() << "Failed to get vpnAdapterIndex. Killswitch disabled";
        }

        if (m_routeMode == Settings::RouteMode::VpnAllSites) {
            static const QStringList subnets = { "1.0.0.0/8", "2.0.0.0/7", "4.0.0.0/6", "8.0.0.0/5", "16.0.0.0/4", "32.0.0.0/3", "64.0.0.0/2", "128.0.0.0/1" };

            auto routeAddList =  iface->routeAddList(m_vpnGateway, subnets);
            if (!routeAddList.waitForFinished() || routeAddList.returnValue() != subnets.count()) {
                qCritical() << "Failed to set routes for TUN";
                return ErrorCode::TunRoutesError;
            }
            if (!stillRunning())
                return ErrorCode::NoError;
        }

        auto StopRoutingIpv6 = iface->StopRoutingIpv6();
        if (!StopRoutingIpv6.waitForFinished() || !StopRoutingIpv6.returnValue()) {
            qCritical() << "Failed to disable IPv6 routing";
            return ErrorCode::Ipv6BlockError;
        }
        if (!stillRunning())
            return ErrorCode::NoError;

#ifdef Q_OS_WIN
        if (inetAdapterIndex != -1 && vpnAdapterIndex != -1) {
            QJsonObject config = m_rawConfig;
            config.insert("inetAdapterIndex", inetAdapterIndex);
            config.insert("vpnAdapterIndex", vpnAdapterIndex);
            config.insert("vpnGateway", m_vpnGateway);
            config.insert("vpnServer", m_remoteAddress);

            auto enablePeerTraffic = iface->enablePeerTraffic(config);
            if (!enablePeerTraffic.waitForFinished() || !enablePeerTraffic.returnValue()) {
                qCritical() << "Failed to enable peer traffic";
                return ErrorCode::PeerTrafficError;
            }
        } else
            qWarning() << "Failed to get adapter indexes. Split-tunneling disabled";
#endif
        return ErrorCode::NoError;
    },
    [] () {
        return ErrorCode::DopamineServiceConnectionFailed;
    });
}
