#include "directNetworks.h"

#include <QDateTime>
#include <QFile>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QList>
#include <QOperatingSystemVersion>
#include <QPair>
#include <QSaveFile>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>

#include <algorithm>

#include "core/api/apiDefs.h"
#include "core/controllers/gatewayController.h"
#include "core/networkUtilities.h"
#include "settings.h"

namespace
{
    // What a system carries next to its VPN's other routes, measured on 2026-10-15:
    // Windows' connection manager (WcmSvc) spends processor time with the square of the routes -
    // 500 routes half a second at a connect, 2,000 some nine (a Ryzen 5 7500F) - and the service
    // pauses that manager past 500 routes of its own (router_win.cpp), which this stays below
    constexpr int kWindowsRoutes = 450;
    // Android hands every route of a VPN to each app that follows the network, at each change of
    // it: from some 600 routes on, Google's services stopped receiving them (Android 14), and an
    // app the system holds frozen in the background keeps them unread until its queue is full -
    // with 200 routes a notice was 29 KB (a VPN without them: 1.5) and a frozen app's queue filled
    // a few reconnects sooner. 150 hold every big Russian service (the last, Yandex Market, is
    // 145th) at a quarter less; Android 15 keeps such notices back for a frozen app by itself
    constexpr int kAndroidRoutes = 150;
    // the most a fetched order may hold (the gateway gives at most 1,000)
    constexpr int kMaxOrder = 2000;
    // a fetched whole list is believed when it is the size of the country's (as the gateway checks it)
    constexpr int kWholeMin = 3000;
    constexpr int kWholeMax = 30000;
    // the order changes slowly: asked for at the app's start, then at most twice a day
    constexpr qint64 kFetchEverySecs = 12 * 3600;

    // an IPv4 address or network as its first and last address; false for anything else
    bool span(const QString &entry, quint64 &first, quint64 &last)
    {
        const QString text = entry.trimmed();
        if (!NetworkUtilities::checkIpSubnetFormat(text)) {
            return false;
        }
        const QStringList parts = text.split('/');
        const QHostAddress address(parts.at(0));
        if (address.protocol() != QAbstractSocket::IPv4Protocol) {
            return false;
        }
        const int bits = parts.size() > 1 ? parts.at(1).toInt() : 32;
        const quint64 size = quint64(1) << (32 - bits);
        first = quint64(address.toIPv4Address()) & ~(size - 1);
        last = first + size - 1;
        return true;
    }

    // the networks in [from, to) as few CIDR blocks as cover them
    int blocks(quint64 from, quint64 to)
    {
        int n = 0;
        while (from < to) {
            // the largest block that starts at `from`, cut down until it ends by `to`
            quint64 size = from ? (from & (~from + 1)) : (quint64(1) << 32);
            while (from + size > to) {
                size >>= 1;
            }
            from += size;
            ++n;
        }
        return n;
    }

    // a list file: a network a line, "#" comments
    QStringList readList(const QString &path)
    {
        QStringList out;
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            return out;
        }
        for (const QByteArray &raw : file.readAll().split('\n')) {
            const QString line = QString::fromLatin1(raw).section('#', 0, 0).trimmed();
            if (!line.isEmpty() && NetworkUtilities::checkIpSubnetFormat(line)) {
                out.append(line);
            }
        }
        return out;
    }

    QStringList builtIn()
    {
        const QStringList out = readList(QStringLiteral(":/ru_direct.txt"));
        if (out.isEmpty()) {
            qWarning() << "[DIRECT] the built-in order of the Russian networks is missing";
        }
        return out;
    }

    // where the whole list fetched from the gateway is kept (it is too large for the settings)
    QString wholeFile()
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/ru_networks.txt");
    }
}

DirectNetworks::DirectNetworks(std::shared_ptr<Settings> settings, QObject *parent) : QObject(parent), m_settings(settings)
{
}

QStringList DirectNetworks::ordered(const Settings &settings)
{
    const QStringList fetched = settings.ruDirectNetworks();
    if (!fetched.isEmpty()) {
        return fetched;
    }
    static const QStringList shipped = builtIn();
    return shipped;
}

QStringList DirectNetworks::whole(const Settings &settings)
{
    // read once per version: the file holds some 8,700 lines
    static QString cachedVersion;
    static QStringList cached;
    const QString version = settings.ruDirectFullVersion();
    if (!version.isEmpty()) {
        if (version != cachedVersion) {
            cached = readList(wholeFile());
            cachedVersion = version;
        }
        if (cached.size() >= kWholeMin) {
            return cached;
        }
    }
    static const QStringList shipped = readList(QStringLiteral(":/ru_networks.txt"));
    return shipped;
}

QString DirectNetworks::saveForService(const QStringList &networks)
{
    // written in one go: the service never reads half a list
    const QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/ru_direct_xray.txt");
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (file.open(QIODevice::WriteOnly) && file.write(networks.join('\n').toLatin1() + '\n') > 0 && file.commit()) {
        return path;
    }
    qWarning() << "[DIRECT] the list for the VPN service could not be written:" << file.errorString();
    return {};
}

int DirectNetworks::routesAround(const QStringList &excluded)
{
    QList<QPair<quint64, quint64>> spans;
    for (const QString &entry : excluded) {
        quint64 first = 0;
        quint64 last = 0;
        if (span(entry, first, last)) {
            spans.append({ first, last });
        }
    }
    // loopback is never given to the VPN (ProtocolConfig.processRoutes)
    spans.append({ quint64(127) << 24, (quint64(128) << 24) - 1 });
    std::sort(spans.begin(), spans.end());

    int routes = 0;
    quint64 next = 0; // the first address not looked at yet
    for (const auto &s : spans) {
        if (s.first > next) {
            routes += blocks(next, s.first);
        }
        next = qMax(next, s.second + 1);
    }
    routes += blocks(next, quint64(1) << 32);
    return routes;
}

QStringList DirectNetworks::forThisSystem(const QStringList &ordered, const QStringList &taken)
{
    const auto head = [&ordered](qsizetype n) { return n > 0 ? ordered.mid(0, n) : QStringList(); };
#if defined(Q_OS_ANDROID)
    if (QOperatingSystemVersion::current() >= QOperatingSystemVersion(QOperatingSystemVersion::Android, 13)) {
        return head(kAndroidRoutes - taken.size());
    }
    // before 13 Android cannot leave an address out of a VPN: it is given all the rest of the
    // addresses instead, some eight to ten routes for each network left out - as many networks
    // as keep that within the same bound
    QStringList out;
    QStringList trial = taken;
    for (const QString &net : ordered) {
        trial.append(net);
        if (routesAround(trial) > kAndroidRoutes) {
            break;
        }
        out.append(net);
    }
    return out;
#elif defined(Q_OS_WIN)
    return head(kWindowsRoutes - taken.size());
#else
    return head(kAndroidRoutes - taken.size());
#endif
}

void DirectNetworks::fetch(bool force)
{
    if (m_fetching) {
        return;
    }
    const QDateTime last = m_settings->ruDirectFetchedAt();
    if (!force && last.isValid() && last.secsTo(QDateTime::currentDateTimeUtc()) < kFetchEverySecs
        && !m_settings->ruDirectNetworks().isEmpty()) {
        return;
    }
    m_fetching = true;

    auto gatewayController = QSharedPointer<GatewayController>::create(m_settings->getGatewayEndpoint(), m_settings->isDevGatewayEnv(),
                                                                       apiDefs::requestTimeoutMsecs, m_settings->isStrictKillSwitchEnabled(),
                                                                       nullptr, m_settings->getGatewayEndpointFallback());
    QJsonObject payload;
    // the versions the app has: the gateway answers an empty list for one that is still the current
    if (!m_settings->ruDirectNetworks().isEmpty() && !m_settings->ruDirectVersion().isEmpty()) {
        payload.insert("version", m_settings->ruDirectVersion());
    }
    payload.insert("full", true);
    if (!m_settings->ruDirectFullVersion().isEmpty() && QFile::exists(wholeFile())) {
        payload.insert("full_version", m_settings->ruDirectFullVersion());
    }

    auto future = gatewayController->postAsync(QString("%1v1/direct_networks"), payload);
    future.then(this, [this, gatewayController](QPair<ErrorCode, QByteArray> result) {
        m_fetching = false;
        const auto [errorCode, responseBody] = result;
        if (errorCode != ErrorCode::NoError) {
            qWarning() << "[DIRECT] the order of the Russian networks was not fetched:" << static_cast<int>(errorCode);
            return;
        }
        m_settings->setRuDirectFetchedAt(QDateTime::currentDateTimeUtc());

        const QJsonObject obj = QJsonDocument::fromJson(responseBody).object();
        // networks only, or nothing of the list is taken
        const auto networksOf = [](const QJsonArray &array, QStringList &out) {
            for (const auto &value : array) {
                const QString net = value.toString();
                quint64 first = 0;
                quint64 last = 0;
                if (!net.contains('/') || !span(net, first, last)) {
                    return false;
                }
                out.append(net);
            }
            return true;
        };

        const QJsonArray networks = obj.value("networks").toArray();
        QStringList list;
        if (networks.isEmpty()) {
            qDebug() << "[DIRECT] the order of the Russian networks is the one the app has";
        } else if (networks.size() > kMaxOrder) {
            qWarning() << "[DIRECT] an order of" << networks.size() << "networks is not taken";
        } else if (!networksOf(networks, list)) {
            qWarning() << "[DIRECT] an order with something else than a network in it is not taken";
        } else {
            m_settings->setRuDirectNetworks(list, obj.value("version").toString());
            qInfo() << "[DIRECT] the order of the Russian networks taken:" << list.size() << "networks";
        }

        // the whole country's list, written beside the settings in one go (a half-written file
        // is never read: the version is set only after it is in place)
        const QJsonArray whole = obj.value("full_networks").toArray();
        const QString wholeVersion = obj.value("full_version").toString();
        QStringList all;
        if (whole.isEmpty() || wholeVersion.isEmpty()) {
            qDebug() << "[DIRECT] the whole Russian list is the one the app has";
        } else if (whole.size() < kWholeMin || whole.size() > kWholeMax) {
            qWarning() << "[DIRECT] a whole list of" << whole.size() << "networks is not taken";
        } else if (!networksOf(whole, all)) {
            qWarning() << "[DIRECT] a whole list with something else than a network in it is not taken";
        } else {
            QDir().mkpath(QFileInfo(wholeFile()).absolutePath());
            QSaveFile file(wholeFile());
            if (file.open(QIODevice::WriteOnly) && file.write(all.join('\n').toLatin1() + '\n') > 0 && file.commit()) {
                m_settings->setRuDirectFullVersion(wholeVersion);
                qInfo() << "[DIRECT] the whole Russian list taken:" << all.size() << "networks";
            } else {
                qWarning() << "[DIRECT] the whole Russian list could not be written:" << file.errorString();
            }
        }
    });
}
