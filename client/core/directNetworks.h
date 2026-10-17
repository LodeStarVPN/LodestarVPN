#ifndef DIRECTNETWORKS_H
#define DIRECTNETWORKS_H

#include <QObject>
#include <QStringList>

#include <memory>

class Settings;

// The Russian networks the app sends past the VPN itself (the switch «Российские сайты
// напрямую»). VLESS takes the whole country's list (whole): its Xray sorts each connection
// itself, as an entry's Xray did, and no system route is needed. AmneziaWG has no such
// sorter yet and goes by system routes, of which a system carries only so many: it takes
// them from the head of the gateway's order (v1/direct_networks, gateway/src/directRank.js,
// the most needed first), as many as this system carries (forThisSystem); the rest of Russia
// goes through the VPN. Both lists come from the gateway and are kept (the order in the
// settings, the whole list in a file beside them), with copies built in (ru_direct.txt,
// ru_networks.txt) until they came.
class DirectNetworks : public QObject
{
    Q_OBJECT

public:
    explicit DirectNetworks(std::shared_ptr<Settings> settings, QObject *parent = nullptr);

    // the order as the app has it now
    static QStringList ordered(const Settings &settings);
    // the whole country's list as the app has it now
    static QStringList whole(const Settings &settings);
    // as many networks from the head of `ordered` as this system carries next to `taken` (what
    // the other lists already send past the VPN: addresses and networks)
    static QStringList forThisSystem(const QStringList &ordered, const QStringList &taken);
    // the routes a VPN needs on a system that cannot leave an address out (Android before 13):
    // all of IPv4 but `excluded` and 127.0.0.0/8, as networks
    static int routesAround(const QStringList &excluded);
    // `networks` as a file of the app, a network a line, for the app's VPN service to read itself
    // (Android: the config reaches the service in one system message, too small for the whole
    // list, vpnconnection.cpp); its path, or nothing when it could not be written
    static QString saveForService(const QStringList &networks);

public slots:
    // asks the gateway for its order; force: even if it was asked for a short while ago
    void fetch(bool force = false);

private:
    std::shared_ptr<Settings> m_settings;
    bool m_fetching = false;
};

#endif // DIRECTNETWORKS_H
