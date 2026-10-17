#ifndef ANDROID_VPNPROTOCOL_H
#define ANDROID_VPNPROTOCOL_H

#include "vpnprotocol.h"

using namespace amnezia;

class AndroidVpnProtocol : public VpnProtocol
{
    Q_OBJECT

public:
    explicit AndroidVpnProtocol(const QJsonObject& configuration, QObject* parent = nullptr);
    ~AndroidVpnProtocol() override = default;

    ErrorCode start() override;
    void stop() override;

    // the service's counters are totals since its tunnel came up. Attached to a tunnel that
    // was up already (started anew over it), or back from the background, the first ones are
    // only where counting starts: their difference was all the traffic since the connect (or of
    // the time away), and the card showed it as one second's speed
    void countFromNextStatistics() { m_baselinePending = true; }
    void onStatistics(quint64 receivedBytes, quint64 sentBytes);

private:
    bool m_baselinePending = false;
};

#endif // ANDROID_VPNPROTOCOL_H
