#ifndef TUNNELHTTPPROBE_H
#define TUNNELHTTPPROBE_H

#include <QByteArray>
#include <QElapsedTimer>
#include <QHostAddress>
#include <QNetworkProxy>
#include <QTcpSocket>

#include <functional>

// HTTP/1.1 through xray's SOCKS inbound: SOCKS5 CONNECT host:80, then HEAD
// requests on that one kept-alive connection. xray answers the CONNECT
// itself before dialing out, so only an HTTP answer proves the tunnel; the
// time to later answers is the tunnel's round trip (the first one also pays
// for opening the connection to the server). The host goes to xray as a
// name: resolved on the far side, never by an address rule on the way.
// Lives in the thread that made it.
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
        m_socket.setProxy(QNetworkProxy::NoProxy); // xray's own inbound on this machine
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

#endif // TUNNELHTTPPROBE_H
