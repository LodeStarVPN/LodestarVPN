#include "android_vpnprotocol.h"

#include "platforms/android/android_controller.h"


AndroidVpnProtocol::AndroidVpnProtocol(const QJsonObject &configuration, QObject* parent)
    : VpnProtocol(configuration, parent)
{ }

ErrorCode AndroidVpnProtocol::start()
{
    qDebug() << "AndroidVpnProtocol::start()";
    return AndroidController::instance()->start(m_rawConfig);
}

void AndroidVpnProtocol::stop()
{
    qDebug() << "AndroidVpnProtocol::stop()";
    setConnectionState(Vpn::ConnectionState::Disconnecting);
    AndroidController::instance()->stop();
}

void AndroidVpnProtocol::onStatistics(quint64 receivedBytes, quint64 sentBytes, qint64 dataReceivedBytes,
                                      qint64 dataSentBytes, qint64 sampleNs)
{
    // read at sampleNs by the VPN service's clock: the speed goes by it, not by when it came
    setSampleNs(sampleNs);
    const bool data = dataReceivedBytes >= 0 && dataSentBytes >= 0;
    if (m_baselinePending) {
        m_baselinePending = false;
        setBytesBaseline(receivedBytes, sentBytes);
        if (data) {
            setDataBytesBaseline(dataReceivedBytes, dataSentBytes);
        }
        return;
    }
    // the apps' data first: the speed shown goes by it
    if (data) {
        setDataBytesChanged(dataReceivedBytes, dataSentBytes);
    }
    setBytesChanged(receivedBytes, sentBytes);
}
