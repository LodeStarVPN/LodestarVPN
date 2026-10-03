#ifndef IPC_H
#define IPC_H

#include <QObject>
#include <QRegularExpression>
#include <QString>

#include "../client/utilities.h"

#define IPC_SERVICE_URL "local:LodestarIpcInterface"

namespace amnezia {

enum PermittedProcess {
    Invalid,
    Wireguard,
    Tun2Socks,
    CertUtil
};

// Anyone on the computer can reach the service's socket, and what it starts
// runs as SYSTEM: only what the app needs (tun2socks for VLESS), never a
// general-purpose tool like certutil.
inline QString permittedProcessPath(PermittedProcess pid)
{
    switch (pid) {
        case PermittedProcess::Tun2Socks:
            return Utils::tun2socksPath();
        default:
            return "";
    }
}


inline QString getIpcServiceUrl() {
#ifdef Q_OS_WIN
    return IPC_SERVICE_URL;
#else
    return QString("/tmp/%1").arg(IPC_SERVICE_URL);
#endif
}

inline QString getIpcProcessUrl(int pid) {
#ifdef Q_OS_WIN
    return QString("%1_%2").arg(IPC_SERVICE_URL).arg(pid);
#else
    return QString("/tmp/%1_%2").arg(IPC_SERVICE_URL).arg(pid);
#endif
}

inline QStringList sanitizeArguments(PermittedProcess proc, const QStringList &args) {
    using Validator = std::function<bool(const QString&)>;
    QMap<QString, Validator> namedArgs;
    QList<Validator> positionalArgs;

    switch (proc) {
    case Tun2Socks:
        namedArgs["-device"] = [](const QString& v) { return v.startsWith("tun://"); };
        // the app's own Xray on this computer, never a proxy elsewhere: a
        // SYSTEM tun2socks pointed at someone's server would carry the
        // computer's traffic there
        namedArgs["-proxy"] = [](const QString& v) {
            static const QRegularExpression local(QStringLiteral("^socks5://127\\.0\\.0\\.1:\\d{1,5}$"));
            return local.match(v).hasMatch();
        };
        break;
    default:
        // no other program is started (see permittedProcessPath)
        return {};
    }


    QStringList sanitized;

    for (int i = 0, pos = 0; i < args.size(); i++) {
        const auto& key = args[i];

        if (const auto found = namedArgs.find(key); found != namedArgs.end()) {
            const auto validator = found.value();

            if (validator) {
                if (i + 1 < args.size()) {
                    const auto& value = args[i+1];
                    if (validator(value)) {
                        sanitized << key << value;
                        i++;
                    }
                }
            } else {
                sanitized << key;
            }
        } else if (pos < positionalArgs.size()) {
            if (const auto validator = positionalArgs[pos]; validator && validator(key)) {
                sanitized << key;
                pos++;
            }
        }
    }

    return sanitized;
}

} // namespace amnezia

#endif // IPC_H
