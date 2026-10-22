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

#ifdef Q_OS_WIN
#include <windows.h>
#include <tlhelp32.h>
#endif

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
// Ends the processes of this program left from before this start. None of them is needed:
// the daemon, made before this, has stopped any tunnel left running (WindowsTunnelService),
// and the process of a tunnel still running is spared all the same.
static void endLeftoverProcesses()
{
    DWORD tunnelPid = 0;
    if (SC_HANDLE scm = OpenSCManager(nullptr, nullptr, SC_MANAGER_CONNECT)) {
        if (SC_HANDLE tunnel = OpenService(scm, TUNNEL_SERVICE_NAME, SERVICE_QUERY_STATUS)) {
            SERVICE_STATUS_PROCESS status = {};
            DWORD needed = 0;
            if (QueryServiceStatusEx(tunnel, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&status),
                                     sizeof(status), &needed)
                && status.dwCurrentState != SERVICE_STOPPED) {
                tunnelPid = status.dwProcessId;
            }
            CloseServiceHandle(tunnel);
        }
        CloseServiceHandle(scm);
    }
    const QString exe = QFileInfo(QCoreApplication::applicationFilePath()).fileName();
    const DWORD self = GetCurrentProcessId();
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return;
    }
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
        if (entry.th32ProcessID == self || entry.th32ProcessID == tunnelPid
            || QString::fromWCharArray(entry.szExeFile).compare(exe, Qt::CaseInsensitive) != 0) {
            continue;
        }
        HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
        const bool ended = process != nullptr && TerminateProcess(process, 1);
        if (process != nullptr) {
            CloseHandle(process);
        }
        logger.warning() << "A process of this program left from before, pid" << entry.th32ProcessID
                         << (ended ? "ended" : "could not be ended");
    }
    CloseHandle(snapshot);
}

// The system keeps the process that made the first instance of a pipe as the server of every
// instance of it, for as long as any instance lives. A pipe of the old service still held
// on when this one made its own (the old process finishing, an old tunnel's) left the app
// refusing this service for good ("the pipe is not served by lodestar-service") - after an
// upgrade the VPN did not work until the service was restarted. So the daemon's pipe is
// made once nothing is left of the old one, waited for a minute at most; the service
// starts meanwhile. What holds it on is first ended: up to 1.0.23 a tunnel's process went on
// as a second service after its tunnel (main.cpp) with an instance of this pipe - one of the
// old version is there at every upgrade (the VPN is turned off before it) and outlived the
// wait.
void LocalServer::startDaemonServer()
{
    constexpr int kWaitMs = 500;
    constexpr int kMaxWaits = 120;
    if (server.pipeLeftOver() && m_daemonPipeWaits < kMaxWaits) {
        if (m_daemonPipeWaits++ == 0) {
            logger.warning() << "The daemon pipe of an old service is still there: waiting for it to go";
            endLeftoverProcesses();
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

