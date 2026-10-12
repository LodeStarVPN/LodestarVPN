#include "livePingProbe.h"

#include <QHostAddress>
#include <QNetworkProxy>
#include <QTcpSocket>

#include "protocols/tunnelHttpProbe.h"

namespace
{
    constexpr int kRoundMs = 3000;  // the server card gets a new figure this often
    constexpr int kSpacingMs = 30;  // between a round's probes
    // A handshake's SYN is sent again after a second: an answer later than
    // this is one to the second SYN, a lost packet and not a slow one
    constexpr int kHandshakeDeadlineMs = 900;
    // an HTTP answer waits out a lost packet of its own connection (200 ms
    // and more): the round's other connections answer meanwhile
    constexpr int kHttpDeadlineMs = 2000;
    constexpr int kWarmUpMs = 1200;

    const char *const kHandshakeHosts[] = { "1.1.1.1", "8.8.8.8", "1.0.0.1", "9.9.9.9" };
    constexpr int kHandshakeHostCount = int(sizeof(kHandshakeHosts) / sizeof(kHandshakeHosts[0]));
    // asked for by name: xray resolves them on the far side, so no address
    // rule on the way sends a probe out before the country's server
    const char *const kHttpHosts[] = { "cp.cloudflare.com", "www.gstatic.com", "connectivitycheck.gstatic.com" };
}

LivePingProbe::LivePingProbe(QObject *parent) : QObject(parent)
{
    // children: they follow this object into its thread
    m_roundTimer.setParent(this);
    m_shotTimer.setParent(this);
    m_closeTimer.setParent(this);
    m_roundTimer.setSingleShot(true);
    m_closeTimer.setSingleShot(true);
    m_shotTimer.setInterval(kSpacingMs);
    m_shotTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_roundTimer, &QTimer::timeout, this, &LivePingProbe::beginRound);
    connect(&m_shotTimer, &QTimer::timeout, this, &LivePingProbe::shoot);
    connect(&m_closeTimer, &QTimer::timeout, this, &LivePingProbe::closeRound);
}

LivePingProbe::~LivePingProbe()
{
    stop();
}

void LivePingProbe::start(int socksPort, quint64 run)
{
    stop();
    m_socksPort = socksPort;
    m_run = run;
    m_running = true;
    m_warmUp = socksPort > 0;
    if (!m_clock.isValid()) {
        m_clock.start();
    }
    beginRound();
}

void LivePingProbe::stop()
{
    m_running = false;
    m_roundTimer.stop();
    m_shotTimer.stop();
    m_closeTimer.stop();
    const auto sockets = m_handshakes.keys();
    m_handshakes.clear();
    for (QTcpSocket *socket : sockets) {
        socket->disconnect(this);
        socket->abort();
        socket->deleteLater();
    }
    for (int i = 0; i < kShots; ++i) {
        m_channels[i].reset();
        m_channelRound[i] = 0;
    }
    m_open = 0;
}

void LivePingProbe::beginRound()
{
    if (!m_running) {
        return;
    }
    ++m_round;
    m_shot = 0;
    m_open = 0;
    m_best = -1;
    m_closeTimer.start((kShots - 1) * kSpacingMs + (m_socksPort > 0 ? kHttpDeadlineMs : kHandshakeDeadlineMs));
    m_shotTimer.start();
    shoot();
}

void LivePingProbe::shoot()
{
    if (!m_running || m_shot >= kShots) {
        m_shotTimer.stop();
        return;
    }
    const int index = m_shot++;
    if (m_shot >= kShots) {
        m_shotTimer.stop();
    }
    ++m_open;
    if (m_socksPort > 0) {
        shootHttp(index);
    } else {
        shootHandshake(index);
    }
}

void LivePingProbe::take(int ms)
{
    if (ms >= 0 && (m_best < 0 || ms < m_best)) {
        m_best = ms;
    }
    if (--m_open <= 0 && m_shot >= kShots) {
        closeRound();
    }
}

void LivePingProbe::closeRound()
{
    if (!m_running) {
        return;
    }
    m_closeTimer.stop();
    m_shotTimer.stop();
    // what has no answer by now is lost: its late answer must not pass for a ping
    const auto sockets = m_handshakes.keys();
    m_handshakes.clear();
    for (QTcpSocket *socket : sockets) {
        socket->disconnect(this);
        socket->abort();
        socket->deleteLater();
    }
    for (int i = 0; i < kShots; ++i) {
        if (m_channels[i] && m_channelRound[i] != 0) {
            m_channels[i].reset(); // stuck: a fresh connection next round
        }
        m_channelRound[i] = 0;
    }
    m_open = 0;
    ++m_hostShift;

    const bool warmUp = m_warmUp;
    m_warmUp = false;
    if (!warmUp) {
        emit measured(m_best, m_run);
    }
    m_roundTimer.start(warmUp ? kWarmUpMs : kRoundMs);
}

void LivePingProbe::shootHandshake(int index)
{
    auto *socket = new QTcpSocket(this);
    // straight into the tunnel: no system proxy asked for (a call into Java
    // on Android), none used
    socket->setProxy(QNetworkProxy::NoProxy);
    m_handshakes.insert(socket, m_clock.nsecsElapsed());
    connect(socket, &QTcpSocket::connected, this, [this, socket]() { finishHandshake(socket, true); });
    connect(socket, &QTcpSocket::errorOccurred, this, [this, socket](QAbstractSocket::SocketError) { finishHandshake(socket, false); });
    socket->connectToHost(QHostAddress(QLatin1String(kHandshakeHosts[(m_hostShift + index) % kHandshakeHostCount])), 443);
}

void LivePingProbe::finishHandshake(QTcpSocket *socket, bool ok)
{
    const auto it = m_handshakes.constFind(socket);
    if (it == m_handshakes.constEnd()) {
        return;
    }
    const qint64 elapsedNs = m_clock.nsecsElapsed() - it.value();
    m_handshakes.erase(it);
    socket->disconnect(this);
    socket->abort();
    socket->deleteLater();

    const int ms = static_cast<int>((elapsedNs + 500000) / 1000000);
    take(ok && ms <= kHandshakeDeadlineMs ? qMax(ms, 1) : -1);
}

void LivePingProbe::shootHttp(int index)
{
    std::unique_ptr<TunnelHttpProbe> &channel = m_channels[index];
    if (!channel || !channel->isAlive()) {
        channel = std::make_unique<TunnelHttpProbe>(m_socksPort, kHttpHosts[index],
                [this](TunnelHttpProbe *answered, qint64 elapsedMs, qint64, bool first) { onHttpAnswer(answered, elapsedMs, first); });
    }
    m_channelRound[index] = m_round;
    channel->request();
}

void LivePingProbe::onHttpAnswer(TunnelHttpProbe *probe, qint64 elapsedMs, bool first)
{
    for (int i = 0; i < kShots; ++i) {
        if (m_channels[i].get() != probe) {
            continue;
        }
        if (m_channelRound[i] != m_round) {
            return; // an answer to a round that is closed
        }
        m_channelRound[i] = 0;
        // the first answer on a connection also pays for opening the way to the server
        take(!first && elapsedMs <= kHttpDeadlineMs ? qMax(static_cast<int>(elapsedMs), 1) : -1);
        return;
    }
}
