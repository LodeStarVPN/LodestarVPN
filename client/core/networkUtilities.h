#ifndef NETWORKUTILITIES_H
#define NETWORKUTILITIES_H

#include <QRegularExpression>
#include <QRegExp>
#include <QString>
#include <QHostAddress>
#include <QNetworkReply>
#include <QtNetwork/qnetworkinterface.h>

class NetworkUtilities : public QObject
{
    Q_OBJECT
public:
    static QString getIPAddress(const QString &host);
    static QString getStringBetween(const QString &s, const QString &a, const QString &b);
    static bool checkIPv4Format(const QString &ip);
    static bool checkIpSubnetFormat(const QString &ip);
    // An address no public site has: what a name comes to when an ad blocker or the provider
    // answers for a blocked site (0.0.0.0, 127.0.0.1), a proxy's made-up one (198.18/15),
    // link-local, multicast. A site list never routes or guards it (a route of 127.0.0.1 into
    // the tunnel would take this computer's own connections along); isStubNetwork: a list's
    // entry, an address or a network, that lies wholly in such a range.
    static bool isStubAddress(const QHostAddress &address);
    static bool isStubAddress(const QString &address);
    static bool isStubNetwork(const QString &entry);
    static bool checkIpv6Enabled();
    static QPair<QString, QNetworkInterface> getGatewayAndIface();
    // Returns the Interface Index that could Route to dst
    static int AdapterIndexTo(const QHostAddress& dst);

    static QRegularExpression ipAddressRegExp();
    static QRegularExpression ipAddressPortRegExp();
    static QRegExp ipAddressWithSubnetRegExp();
    static QRegExp ipNetwork24RegExp();
    static QRegExp ipPortRegExp();
    static QRegExp domainRegExp();

    static QString netMaskFromIpWithSubnet(const QString ip);
    static QString ipAddressFromIpWithSubnet(const QString ip);
    static QStringList summarizeRoutes(const QStringList &ips, const QString cidr);
};

#endif // NETWORKUTILITIES_H
