#include "xray.h"
#include "core/networkUtilities.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QCoreApplication>
#include <amnezia_xray.h>
#include <qdebug.h>

#ifdef Q_OS_DARWIN
    #include <arpa/inet.h>
    #include <cerrno>
    #include <cstddef>
    #include <cstdint>
    #include <cstring>
    #include <ifaddrs.h>
    #include <net/if.h>
    #include <netinet/in.h>
    #include <netinet/ip.h>
    #include <sys/socket.h>
#endif
#ifdef Q_OS_WIN
    #include <winsock2.h>
    #include <ws2tcpip.h>
#endif
#ifdef Q_OS_LINUX
    #include <sys/socket.h>
#endif

namespace
{
    // The config comes over the service's socket, which anyone on the computer
    // can reach, and Xray runs inside this SYSTEM process: nothing in it may
    // name files to write or read (logs, certificate files), open the control
    // API, or offer the proxy beyond this computer. No access log either: the
    // sites a user visits are not for the log.
    QByteArray sanitizedConfig(const QString &cfg)
    {
        QJsonObject root = QJsonDocument::fromJson(cfg.toUtf8()).object();

        QJsonObject log = root.value("log").toObject();
        log.remove("error");
        log["access"] = "none";
        log["dnsLog"] = false;
        root["log"] = log;
        root.remove("api");

        QJsonArray inbounds;
        for (const QJsonValue &value : root.value("inbounds").toArray()) {
            QJsonObject inbound = value.toObject();
            inbound["listen"] = "127.0.0.1";
            inbounds.append(inbound);
        }
        root["inbounds"] = inbounds;

        QJsonArray outbounds;
        for (const QJsonValue &value : root.value("outbounds").toArray()) {
            QJsonObject outbound = value.toObject();
            QJsonObject stream = outbound.value("streamSettings").toObject();
            for (const QString &key : { QStringLiteral("tlsSettings"), QStringLiteral("xtlsSettings") }) {
                if (stream.contains(key)) {
                    QJsonObject tls = stream.value(key).toObject();
                    tls.remove("certificates");
                    stream[key] = tls;
                }
            }
            if (outbound.contains("streamSettings")) {
                outbound["streamSettings"] = stream;
            }
            outbounds.append(outbound);
        }
        root["outbounds"] = outbounds;

        return QJsonDocument(root).toJson(QJsonDocument::Compact);
    }
}

bool Xray::startXray(const QString &cfg)
{
    qDebug() << "Xray::startXray()";

    // still up from a session the client never stopped (it crashed or was
    // killed): the new start would fail on it
    if (m_running) {
        stopXray();
    }

    auto defaultIface = NetworkUtilities::getGatewayAndIface().second;
#ifdef Q_OS_LINUX
    m_defaultIfaceName = defaultIface.name().toUtf8();
#else
    m_defaultIfaceIdx = defaultIface.index();
#endif

    if (auto err = amnezia_xray_setsockcallback(ctxSockCallback, this); err != nullptr) {
        qDebug() << "[xray] sockopt failed: " << err;
        amnezia_xray_free(err);
        return false;
    }

    amnezia_xray_setloghandler(ctxLogHandler, this);

    QByteArray bytes = sanitizedConfig(cfg);
    if (auto err = amnezia_xray_configure(bytes.data()); err != nullptr) {
        qDebug() << "[xray] configuration failed: " << err;
        amnezia_xray_free(err);
        return false;
    }

    if (auto err = amnezia_xray_start(); err != nullptr) {
        qDebug() << "[xray] failed to start: " << err;
        amnezia_xray_free(err);
        return false;
    }

    m_running = true;
    return true;
}

bool Xray::stopXray()
{
    qDebug() << "Xray::stopXray()";
    m_running = false;
    if (auto err = amnezia_xray_stop(); err != nullptr) {
        qDebug() << "[xray] failed to stop: " << err;
        amnezia_xray_free(err);
        return false;
    }

    return true;
}

void Xray::logHandler(char* str)
{
    QMetaObject::invokeMethod(qApp, [str = QString::fromUtf8(str)] {
        qDebug() << "[xray]" << str;
    }, Qt::QueuedConnection);
}

void Xray::sockCallback(uintptr_t fd)
{
#ifdef Q_OS_MAC
    if (m_defaultIfaceIdx > 0) {
        setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &m_defaultIfaceIdx, sizeof(m_defaultIfaceIdx));
        setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &m_defaultIfaceIdx, sizeof(m_defaultIfaceIdx));
    }
#endif
#ifdef Q_OS_WIN
    if (DWORD idx = m_defaultIfaceIdx; idx > 0) {
        setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_IF, reinterpret_cast<char *>(&idx), sizeof(idx));
        idx = htonl(idx); // IP_UNICAST_IF expects index in network byte order
        setsockopt(fd, IPPROTO_IP, IP_UNICAST_IF, reinterpret_cast<char *>(&idx), sizeof(idx));
    }
#endif
#ifdef Q_OS_LINUX
    if (!m_defaultIfaceName.isEmpty()) {
        setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, m_defaultIfaceName.data(), m_defaultIfaceName.size());
    }
#endif
}
