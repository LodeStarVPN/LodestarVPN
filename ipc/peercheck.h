#ifndef PEERCHECK_H
#define PEERCHECK_H

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QLocalSocket>

#ifdef Q_OS_WIN
    #ifndef NOMINMAX
        #define NOMINMAX
    #endif
    #include <windows.h>
#endif

namespace amnezia
{

#ifdef Q_OS_WIN
    // The program of the process with this pid ("C:/.../Lodestar.exe"), or "" if it cannot be told.
    inline QString processImagePath(ULONG pid)
    {
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (!process) {
            return {};
        }
        wchar_t buffer[4 * MAX_PATH];
        DWORD size = sizeof(buffer) / sizeof(buffer[0]);
        const bool ok = QueryFullProcessImageNameW(process, 0, buffer, &size);
        CloseHandle(process);
        return ok ? QDir::cleanPath(QDir::fromNativeSeparators(QString::fromWCharArray(buffer, size))) : QString();
    }

    inline bool isInstalledProgram(const QString &imagePath, const QString &fileName)
    {
        const QString expected = QDir::cleanPath(QCoreApplication::applicationDirPath() + "/" + fileName);
        return !imagePath.isEmpty() && imagePath.compare(expected, Qt::CaseInsensitive) == 0;
    }
#endif

    // Service side. The service's pipes can be opened by anyone on the computer
    // (the app runs as the logged-on user), and what is asked over them runs as
    // SYSTEM: routes, DNS, the kill switch, tunnels. A connection is kept only
    // when the process on the other end is this installation's app, the
    // Lodestar.exe next to the service.
    inline bool isTrustedClient(QLocalSocket *socket)
    {
#ifdef Q_OS_WIN
        ULONG pid = 0;
        HANDLE pipe = reinterpret_cast<HANDLE>(socket->socketDescriptor());
        if (!GetNamedPipeClientProcessId(pipe, &pid)) {
            qWarning() << "IPC: cannot tell which program connected, refused";
            return false;
        }
        const QString image = processImagePath(pid);
        if (!isInstalledProgram(image, QStringLiteral("Lodestar.exe"))) {
            qWarning() << "IPC: connection from another program refused:" << QFileInfo(image).fileName() << "pid" << pid;
            return false;
        }
        return true;
#else
        Q_UNUSED(socket)
        return true;
#endif
    }

    // App side. Anyone may also open another instance of a pipe name and wait
    // for the app: before the app sends a tunnel config (keys) it checks that
    // the other end is the running lodestar-service (its process id as the
    // service manager reports it; a standard user cannot always open a
    // SYSTEM process to read its program path).
    inline bool isTrustedServer(QLocalSocket *socket)
    {
#ifdef Q_OS_WIN
        ULONG pid = 0;
        HANDLE pipe = reinterpret_cast<HANDLE>(socket->socketDescriptor());
        if (!GetNamedPipeServerProcessId(pipe, &pid)) {
            qWarning() << "IPC: cannot tell which program serves the pipe";
            return false;
        }
        DWORD servicePid = 0;
        if (SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT)) {
            if (SC_HANDLE service = OpenServiceW(scm, L"lodestar-service", SERVICE_QUERY_STATUS)) {
                SERVICE_STATUS_PROCESS status {};
                DWORD needed = 0;
                if (QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&status), sizeof(status), &needed)) {
                    servicePid = status.dwProcessId;
                }
                CloseServiceHandle(service);
            }
            CloseServiceHandle(scm);
        }
        if (servicePid == 0 || servicePid != pid) {
            qWarning() << "IPC: the pipe is not served by lodestar-service, pid" << pid << "service pid" << servicePid;
            return false;
        }
        return true;
#else
        Q_UNUSED(socket)
        return true;
#endif
    }

} // namespace amnezia

#endif // PEERCHECK_H
