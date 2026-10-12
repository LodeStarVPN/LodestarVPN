#ifndef LIVEPINGPROBE_H
#define LIVEPINGPROBE_H

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QTimer>

#include <array>
#include <memory>

class QTcpSocket;
class TunnelHttpProbe;

// The live ping of a connected tunnel (the server card's figure).
//
// Every round sends a few probes a moment apart and takes the quickest
// answer; a probe that has no answer in time is a lost packet, not a ping:
//  - one probe in three seconds used to be the whole measurement, and a
//    single lost packet then showed as 1000 or 3000 ms (the handshake's SYN
//    is sent again after a second, then after two more);
//  - a phone's Wi-Fi goes to sleep between lone packets and holds an answer
//    back until its next wake-up, tens of ms later: the round's later probes
//    find it awake.
//
// It lives in a thread of its own: timed in the window's thread, an answer
// waited for the frame being drawn.
//
// WireGuard / AmneziaWG: TCP handshakes through the tunnel to public
// anycast addresses. Xray: its tunnel device answers handshakes by itself
// (tun2socks), so the round trip is that of small HTTP requests over
// connections kept open through xray's local SOCKS inbound.
class LivePingProbe : public QObject
{
    Q_OBJECT

public:
    explicit LivePingProbe(QObject *parent = nullptr);
    ~LivePingProbe() override;

public slots:
    // A round now, then one every few seconds. socksPort 0: handshakes
    // through the tunnel; otherwise xray's SOCKS inbound on this port.
    // `run` comes back with every result (the controller tells the results
    // of a connection that is gone by it).
    void start(int socksPort, quint64 run);
    void stop();

signals:
    // a round's result: the quickest answer, or -1 when none came in time
    void measured(int ms, quint64 run);

private:
    static constexpr int kShots = 3;

    void beginRound();
    void shoot();
    void closeRound();
    void take(int ms);

    void shootHandshake(int index);
    void finishHandshake(QTcpSocket *socket, bool ok);
    void shootHttp(int index);
    void onHttpAnswer(TunnelHttpProbe *probe, qint64 elapsedMs, bool first);

    QTimer m_roundTimer;
    QTimer m_shotTimer;
    QTimer m_closeTimer;
    QElapsedTimer m_clock;

    bool m_running = false;
    int m_socksPort = 0;
    quint64 m_run = 0;
    quint64 m_round = 0;
    bool m_warmUp = false; // xray: the first round only opens the connections
    int m_shot = 0;        // the round's probes sent
    int m_open = 0;        // ... and still waited for
    int m_best = -1;
    int m_hostShift = 0;

    QHash<QTcpSocket *, qint64> m_handshakes; // started at, ns
    std::array<std::unique_ptr<TunnelHttpProbe>, kShots> m_channels;
    std::array<quint64, kShots> m_channelRound {}; // the round its request belongs to, 0: none
};

#endif // LIVEPINGPROBE_H
