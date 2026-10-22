#ifndef NAMERESOLVER_H
#define NAMERESOLVER_H

#include <QByteArray>
#include <QHash>
#include <QString>
#include <QStringList>

// Names to IPv4 addresses for the split-tunneling lists (the user's own sites, the names of the services).
//
// A list of names is turned into addresses once, when the VPN connects, and the program that is later asked to open one may be
// given any address the name has: so every address is wanted, from every resolver that can be asked. The computer's own
// resolver is the provider's, which answers falsely for what is blocked (no such name, an address of its own, 127.0.0.1) - just
// what such lists hold - so Cloudflare's resolver is asked too, over HTTPS (1.1.1.1, the one the tunnel hands out as DNS), and
// the answers are put together.
namespace NameResolver
{
// Waits in an event loop (the window goes on) for all the answers, or timeoutMs. Up to maxPerName addresses of a name (never
// a stub one, NetworkUtilities::isStubAddress); a name nobody has an answer for is not in the result.
QHash<QString, QStringList> resolve(const QStringList &names, int timeoutMs, int maxPerName = 8);

// The addresses in a DNS-over-HTTPS answer (the JSON form): its A records that are not stub addresses. Public for the harness.
QStringList addressesInAnswer(const QByteArray &json);
}

#endif // NAMERESOLVER_H
