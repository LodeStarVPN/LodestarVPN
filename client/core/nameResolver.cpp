#include "nameResolver.h"

#include <QEventLoop>
#include <QHostAddress>
#include <QHostInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

#include "core/networkUtilities.h"

namespace
{
// an answer from Cloudflare comes in well under a second; one that does not is not waited for
constexpr int kDohTimeoutMs = 4000;
// when one side has answered for every name, the other gets this long and no more: the computer's own resolver sometimes never
// answers for a name that is not there (a connect must not wait for it), and Cloudflare may be unreachable from a network
constexpr int kSystemGraceMs = 2500;
constexpr int kDohGraceMs = 1500;
}

QStringList NameResolver::addressesInAnswer(const QByteArray &json)
{
    QStringList out;
    const QJsonArray answers = QJsonDocument::fromJson(json).object().value(QStringLiteral("Answer")).toArray();
    for (const QJsonValue &value : answers) {
        const QJsonObject answer = value.toObject();
        if (answer.value(QStringLiteral("type")).toInt() != 1) { // 1: an A record (the chain of CNAMEs before it is not one)
            continue;
        }
        const QHostAddress address(answer.value(QStringLiteral("data")).toString());
        if (address.protocol() == QAbstractSocket::IPv4Protocol && !NetworkUtilities::isStubAddress(address)) {
            out.append(address.toString());
        }
    }
    return out;
}

QHash<QString, QStringList> NameResolver::resolve(const QStringList &names, int timeoutMs, int maxPerName)
{
    QHash<QString, QStringList> found;
    QStringList unique = names;
    unique.removeAll(QString());
    unique.removeDuplicates();
    if (unique.isEmpty()) {
        return found;
    }

    QEventLoop loop;
    int systemPending = 0;
    int dohPending = 0;
    QTimer grace;
    grace.setSingleShot(true);
    QObject::connect(&grace, &QTimer::timeout, &loop, &QEventLoop::quit);
    const auto add = [&found, maxPerName](const QString &name, const QStringList &addresses) {
        if (addresses.isEmpty()) {
            return;
        }
        QStringList &list = found[name];
        for (const QString &address : addresses) {
            if (list.size() >= maxPerName) {
                break;
            }
            if (!list.contains(address)) {
                list.append(address);
            }
        }
    };
    // all answered: done; one side answered, the other has its grace
    const auto settle = [&]() {
        if (systemPending == 0 && dohPending == 0) {
            loop.quit();
        } else if ((systemPending == 0 || dohPending == 0) && !grace.isActive()) {
            grace.start(systemPending == 0 ? kDohGraceMs : kSystemGraceMs);
        }
    };

    // the computer's own resolver
    for (const QString &name : unique) {
        ++systemPending;
        QHostInfo::lookupHost(name, &loop, [&add, &systemPending, &settle, name](const QHostInfo &info) {
            QStringList addresses;
            for (const QHostAddress &address : info.addresses()) {
                if (address.protocol() == QAbstractSocket::IPv4Protocol && !NetworkUtilities::isStubAddress(address)) {
                    addresses.append(address.toString());
                }
            }
            add(name, addresses);
            --systemPending;
            settle();
        });
    }

    // Cloudflare's, over HTTPS: what the provider's resolver does not say truly
    QNetworkAccessManager manager;
    QList<QPointer<QNetworkReply>> replies;
    for (const QString &name : unique) {
        QUrl url(QStringLiteral("https://1.1.1.1/dns-query"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("name"), name);
        query.addQueryItem(QStringLiteral("type"), QStringLiteral("A"));
        url.setQuery(query);
        QNetworkRequest request(url);
        request.setRawHeader("Accept", "application/dns-json");
        request.setTransferTimeout(kDohTimeoutMs);
        ++dohPending;
        QNetworkReply *reply = manager.get(request);
        replies.append(reply);
        QObject::connect(reply, &QNetworkReply::finished, &loop, [&add, &dohPending, &settle, name, reply]() {
            if (reply->error() == QNetworkReply::NoError) {
                add(name, NameResolver::addressesInAnswer(reply->readAll()));
            }
            reply->deleteLater();
            --dohPending;
            settle();
        });
    }

    QTimer::singleShot(timeoutMs, &loop, &QEventLoop::quit);
    loop.exec();
    // what has not answered by now is not waited for (its answers, if any come, find no one: the loop is gone)
    for (const QPointer<QNetworkReply> &reply : replies) {
        if (reply && !reply->isFinished()) {
            reply->abort();
        }
    }
    return found;
}
