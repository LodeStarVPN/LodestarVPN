#include "localserver.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFileInfo>
#include <QLocalServer>
#include <QLocalSocket>
#include <QObject>
#include <QSharedPointer>
#include <QString>
#include <QTimer>

#include "ipc.h"
#include "peercheck.h"
#include "killswitch.h"
#include "logger.h"

namespace {
Logger logger("WgDaemonServer");
}

LocalServer::LocalServer(QObject *parent) : QObject(parent),
    m_ipcServer(this)
{
    // Create the server and listen outside of QtRO
    m_server = QSharedPointer<QLocalServer>(new QLocalServer(this));
    m_server->setSocketOptions(QLocalServer::WorldAccessOption);

    if (!m_server->listen(amnezia::getIpcServiceUrl())) {
        qDebug() << QString("Unable to start the server: %1.").arg(m_server->errorString());
        return;
    }

    QObject::connect(m_server.data(), &QLocalServer::newConnection, this, [this]() {
        qDebug() << "LocalServer new connection";
        QLocalSocket *socket = m_server->nextPendingConnection();
        if (!amnezia::isTrustedClient(socket)) {
            socket->abort();
            socket->deleteLater();
            return;
        }
        m_serverNode.addHostSideConnection(socket);

        if (!m_isRemotingEnabled) {
            m_isRemotingEnabled = true;
            m_serverNode.enableRemoting(&m_ipcServer);
        }
    });

    // Init Mozilla Wireguard Daemon
#ifdef Q_OS_WIN
    startDaemonServer();
#else
    if (!server.initialize()) {
        logger.error() << "Failed to initialize the server";
        return;
    }
#endif

    m_networkWatcher.initialize();
    connect(&m_networkWatcher, &NetworkWatcher::networkChanged, &m_ipcServer, &IpcServer::networkChanged);
    connect(&m_networkWatcher, &NetworkWatcher::wakeup, &m_ipcServer, &IpcServer::wakeup);
    KillSwitch::instance()->init();

#ifdef Q_OS_LINUX
    // Signal handling for a proper shutdown.
    QObject::connect(qApp, &QCoreApplication::aboutToQuit,
                     []() { LinuxDaemon::instance()->deactivate(); });
#endif

#ifdef Q_OS_MAC
    // Signal handling for a proper shutdown.
    QObject::connect(qApp, &QCoreApplication::aboutToQuit,
                     []() { MacOSDaemon::instance()->deactivate(); });
#endif

#ifdef Q_OS_WIN
    // Signal handling for a proper shutdown. Bound to this server: the service's stop deletes
    // it before the quit, and the daemon with it (SystemService::stop takes the tunnel down
    // first) - a call on the dead daemon crashed every stop, an upgrade's too
    QObject::connect(qApp, &QCoreApplication::aboutToQuit, this,
                     []() { WindowsDaemon::instance()->deactivate(); });
#endif
}

LocalServer::~LocalServer()
{
    qDebug() << "Local server stopped";
}

#ifdef Q_OS_WIN
// The system keeps the process that made the first instance of a pipe as the server of every
// instance of it, for as long as any instance lives. A pipe of the old service still held
// on when this one made its own (the old process finishing, an old tunnel's) left the app
// refusing this service for good ("the pipe is not served by lodestar-service") - after an
// upgrade the VPN did not work until the service was restarted. So the daemon's pipe is
// made once nothing is left of the old one, waited for a minute at most; the service
// starts meanwhile.
void LocalServer::startDaemonServer()
{
    constexpr int kWaitMs = 500;
    constexpr int kMaxWaits = 120;
    if (server.pipeLeftOver() && m_daemonPipeWaits < kMaxWaits) {
        if (m_daemonPipeWaits++ == 0) {
            logger.warning() << "The daemon pipe of an old service is still there: waiting for it to go";
        }
        QTimer::singleShot(kWaitMs, this, &LocalServer::startDaemonServer);
        return;
    }
    if (m_daemonPipeWaits > 0) {
        logger.warning() << "Waited" << m_daemonPipeWaits * kWaitMs << "ms for the old daemon pipe,"
                         << (m_daemonPipeWaits < kMaxWaits ? "it is gone" : "it is still there");
    }
    if (!server.initialize()) {
        logger.error() << "Failed to initialize the server";
    }
}
#endif

