#ifndef VPNPROTOCOL_H
#define VPNPROTOCOL_H

#include <QObject>
#include <QString>
#include <QJsonObject>

#include "core/defs.h"
#include "containers/containers_defs.h"

using namespace amnezia;

class QTimer;

//todo change name
namespace Vpn
{
    Q_NAMESPACE
    enum ConnectionState {
        Unknown,
        Disconnected,
        Preparing,
        Connecting,
        Connected,
        Disconnecting,
        Reconnecting,
        Error
    };
    Q_ENUM_NS(ConnectionState)

    static void declareQmlVpnConnectionStateEnum() {
        qmlRegisterUncreatableMetaObject(
            Vpn::staticMetaObject,
            "ConnectionState",
            1, 0,
            "ConnectionState",
            "Error: only enums"
            );
    }
}

class VpnProtocol : public QObject
{
    Q_OBJECT

public:
    explicit VpnProtocol(const QJsonObject& configuration, QObject* parent = nullptr);
    virtual ~VpnProtocol() override = default;

    static QString textConnectionState(Vpn::ConnectionState connectionState);

    virtual ErrorCode prepare() { return ErrorCode::NoError; }

    virtual bool isConnected() const;
    virtual bool isDisconnected() const;
    virtual ErrorCode start() = 0;
    virtual void stop() = 0;

    Vpn::ConnectionState connectionState() const;
    ErrorCode lastError() const;
    QString textConnectionState() const;
    void setLastError(ErrorCode lastError);

    QString routeGateway() const;
    QString vpnGateway() const;
    QString vpnLocalAddress() const;

    static VpnProtocol* factory(amnezia::DockerContainer container, const QJsonObject &configuration);


signals:
    // when the counts of the bytesChanged right after were read, by the reporting service's own clock
    // (ns): the speed shown goes by it (ConnectionController::addSpeedSample); counts without one are
    // timed on arrival
    void sampleTimed(qint64 sampleNs);
    void bytesChanged(quint64 receivedBytes, quint64 sentBytes);
    // what the apps got and sent since the one before, by the tunnel's count of their data, both ways
    // it went (through the VPN and past it: AmneziaWG's sorter) - for the speed shown only: bytesChanged
    // alone says whether the VPN works. Right before the bytesChanged of the same reading.
    void dataBytesChanged(quint64 receivedBytes, quint64 sentBytes);
    void connectionStateChanged(Vpn::ConnectionState state);
    void timeoutTimerEvent();
    void protocolError(amnezia::ErrorCode e);
    void tunnelAddressesUpdated(const QString& gateway, const QString& localAddress);

public slots:
    virtual void onTimeout(); // todo: remove?

    void setBytesChanged(quint64 receivedBytes, quint64 sentBytes);
    // the totals of the apps' data so far: the difference goes out as dataBytesChanged
    void setDataBytesChanged(quint64 receivedBytes, quint64 sentBytes);
    void setConnectionState(Vpn::ConnectionState state);

protected:
    void startTimeoutTimer();
    void stopTimeoutTimer();
    // the totals the next ones are counted from, nothing reported for them
    void setBytesBaseline(quint64 receivedBytes, quint64 sentBytes);
    void setDataBytesBaseline(quint64 receivedBytes, quint64 sentBytes);
    void setSampleNs(qint64 ns) { m_sampleNs = ns; }
    // sampleTimed for the counts about to go out, when their moment is known
    void emitSampleTimed();

    Vpn::ConnectionState m_connectionState;

    QString m_routeGateway;
    QString m_vpnLocalAddress;
    QString m_vpnGateway;

    QJsonObject m_rawConfig;

private:
    QTimer* m_timeoutTimer;
    ErrorCode m_lastError = ErrorCode::NoError;
    quint64 m_receivedBytes;
    quint64 m_sentBytes;
    quint64 m_dataReceivedBytes = 0;
    quint64 m_dataSentBytes = 0;
    qint64 m_sampleNs = 0;
};

#endif // VPNPROTOCOL_H
