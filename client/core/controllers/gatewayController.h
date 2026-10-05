#ifndef GATEWAYCONTROLLER_H
#define GATEWAYCONTROLLER_H

#include <functional>
#include <memory>

#include <QFuture>
#include <QMutex>
#include <QNetworkReply>
#include <QObject>
#include <QPair>
#include <QPromise>
#include <QSharedPointer>
#include <QStringList>

#include "core/defs.h"

#ifdef Q_OS_IOS
    #include "platforms/ios/ios_controller.h"
#endif

class GatewayController : public QObject
{
    Q_OBJECT

public:
    explicit GatewayController(const QString &gatewayEndpoint, const bool isDevEnvironment, const int requestTimeoutMsecs,
                               const bool isStrictKillSwitchEnabled, QObject *parent = nullptr,
                               const QString &fallbackEndpoint = QString());

    amnezia::ErrorCode post(const QString &endpoint, const QJsonObject apiPayload, QByteArray &responseBody);
    QFuture<QPair<amnezia::ErrorCode, QByteArray>> postAsync(const QString &endpoint, const QJsonObject apiPayload);

    // The gateway's addresses besides the ones the app was built with: the
    // relays the gateway names in its answers (gateway_endpoints) - never its
    // own server, which stays hidden behind them. A request goes to the address
    // that answered last and, when the gateway gives no answer there, on to the
    // next one. Settings keeps the list between runs (the listener).
    static void restoreEndpoints(const QStringList &known, const QString &current);
    static void setEndpointsListener(std::function<void(const QStringList &known, const QString &current)> listener);
    // the address the gateway answered at last (fallback while none has)
    static QString currentEndpoint(const QString &fallback);

private:
    struct EncryptedRequestData
    {
        QNetworkRequest request;
        QByteArray requestBody;
        QByteArray key;
        QByteArray iv;
        QByteArray salt;
        amnezia::ErrorCode errorCode;
    };

    struct DecryptionResult
    {
        QByteArray decryptedBody;
        bool isDecryptionSuccessful;
    };

    EncryptedRequestData prepareRequest(const QString &endpoint, const QJsonObject &apiPayload);
    // answered: the gateway itself answered (its encrypted reply came), whatever it said
    amnezia::ErrorCode doPost(const QString &endpoint, const QJsonObject &apiPayload, QByteArray &responseBody, bool &answered);
    QFuture<QPair<amnezia::ErrorCode, QByteArray>> postAsyncOnce(const QString &endpoint, const QJsonObject apiPayload,
                                                                 std::shared_ptr<bool> answered);
    void postAsyncFrom(const QString &endpoint, const QJsonObject &apiPayload, const QStringList &tries, int index,
                       QSharedPointer<QPromise<QPair<amnezia::ErrorCode, QByteArray>>> promise);
    QStringList candidateEndpoints() const;
    static void noteAnswered(const QString &gatewayEndpoint, const QByteArray &responseBody);
    DecryptionResult tryDecryptResponseBody(const QByteArray &encryptedResponseBody, QNetworkReply::NetworkError replyError,
                                            const QByteArray &key, const QByteArray &iv, const QByteArray &salt);

    QStringList getProxyUrls(const QString &serviceType, const QString &userCountryCode);
    bool shouldBypassProxy(const QNetworkReply::NetworkError &replyError, const QByteArray &decryptedResponseBody, bool isDecryptionSuccessful);
    void bypassProxy(const QString &endpoint, const QString &serviceType, const QString &userCountryCode,
                     std::function<QNetworkReply *(const QString &url)> requestFunction,
                     std::function<bool(QNetworkReply *reply, const QList<QSslError> &sslErrors)> replyProcessingFunction);

    void getProxyUrlsAsync(const QStringList proxyStorageUrls, const int currentProxyStorageIndex,
                           std::function<void(const QStringList &)> onComplete);
    void getProxyUrlAsync(const QStringList proxyUrls, const int currentProxyIndex, std::function<void(const QString &)> onComplete);
    void bypassProxyAsync(
            const QString &endpoint, const QString &proxyUrl, EncryptedRequestData encRequestData,
            std::function<void(const QByteArray &, bool, const QList<QSslError> &, QNetworkReply::NetworkError, const QString &, int)> onComplete);

    int m_requestTimeoutMsecs;
    QString m_gatewayEndpoint;
    QString m_fallbackEndpoint;
    bool m_isDevEnvironment = false;
    bool m_isStrictKillSwitchEnabled = false;

    inline static QString m_proxyUrl;

    inline static QMutex s_endpointsMutex;
    inline static QStringList s_knownEndpoints;
    inline static QString s_currentEndpoint;
    inline static std::function<void(const QStringList &, const QString &)> s_endpointsListener;
};

#endif // GATEWAYCONTROLLER_H
