#include "gatewayController.h"

#include <algorithm>
#include <functional>
#include <random>

#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPromise>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QUrl>

#include "QBlockCipher.h"
#include "QRsa.h"

#include "dopamine_application.h"
#include "core/api/apiUtils.h"
#include "core/networkUtilities.h"
#include "utilities.h"

#ifdef AMNEZIA_DESKTOP
    #include "core/ipcclient.h"
#endif

namespace
{
    // The gateway's own certificate authority (client/gateway_ca.pem, a build
    // input like its key): HTTPS to a relay is trusted by it alone, so a
    // relay's TLS ends at the gateway and nobody in between can stand in for
    // it. Empty in a build without one: the system's authorities then.
    const QList<QSslCertificate> &gatewayAuthority()
    {
        static const QList<QSslCertificate> authority = [] {
            QFile file(QStringLiteral(":/gateway_ca.pem"));
            return file.open(QIODevice::ReadOnly) ? QSslCertificate::fromData(file.readAll(), QSsl::Pem)
                                                  : QList<QSslCertificate>();
        }();
        return authority;
    }

    QByteArray loadAgwPublicKey()
    {
        QFile keyFile(QStringLiteral(":/agw_public.pem"));
        if (!keyFile.open(QIODevice::ReadOnly)) {
            qCritical() << "Cannot open AGW public key resource";
            return {};
        }
        return keyFile.readAll();
    }

    namespace configKey
    {
        constexpr char aesKey[] = "aes_key";
        constexpr char aesIv[] = "aes_iv";
        constexpr char aesSalt[] = "aes_salt";

        constexpr char apiPayload[] = "apiPayload";
        constexpr char keyPayload[] = "keyPayload";
    }

    constexpr QLatin1String errorResponsePattern1("No active configuration found for");
    constexpr QLatin1String errorResponsePattern2("No non-revoked public key found for");
    constexpr QLatin1String errorResponsePattern3("Account not found.");

    constexpr QLatin1String updateRequestResponsePattern("client version update is required");

    constexpr int httpStatusCodeNotFound = 404;
    constexpr int httpStatusCodeConflict = 409;

    constexpr int httpStatusCodeNotImplemented = 501;

    // an address that gave no answer goes after the others for this long: a
    // relay this network cannot reach does not cost every request its timeout
    constexpr qint64 failedAddressPauseMs = 10 * 60 * 1000;

    // the gateway itself gave no answer there (no connection, a timeout, a
    // relay whose tunnel is down): worth the next address. Its own refusal is not
    bool unanswered(ErrorCode errorCode, bool answeredByGateway)
    {
        return !answeredByGateway && (errorCode == ErrorCode::ApiConfigTimeoutError || errorCode == ErrorCode::ApiConfigDownloadError);
    }

    // a gateway address as requests use it: http(s), a host, ending in "/"
    QString normalizedEndpoint(const QString &raw)
    {
        const QUrl url(raw.trimmed(), QUrl::StrictMode);
        if (!url.isValid() || (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https"))
            || url.host().isEmpty() || !url.userInfo().isEmpty() || url.hasQuery() || url.hasFragment()) {
            return {};
        }
        QString endpoint = url.toString(QUrl::FullyEncoded);
        if (!endpoint.endsWith(QLatin1Char('/'))) {
            endpoint += QLatin1Char('/');
        }
        return endpoint;
    }
}

GatewayController::GatewayController(const QString &gatewayEndpoint, const bool isDevEnvironment, const int requestTimeoutMsecs,
                                     const bool isStrictKillSwitchEnabled, QObject *parent, const QString &fallbackEndpoint)
    : QObject(parent),
      m_gatewayEndpoint(gatewayEndpoint),
      m_fallbackEndpoint(fallbackEndpoint),
      m_isDevEnvironment(isDevEnvironment),
      m_requestTimeoutMsecs(requestTimeoutMsecs),
      m_isStrictKillSwitchEnabled(isStrictKillSwitchEnabled)
{
}

GatewayController::EncryptedRequestData GatewayController::prepareRequest(const QString &endpoint, const QJsonObject &apiPayload)
{
    EncryptedRequestData encRequestData;
    encRequestData.errorCode = ErrorCode::NoError;

#ifdef Q_OS_IOS
    IosController::Instance()->requestInetAccess();
    QThread::msleep(10);
#endif

    encRequestData.request.setTransferTimeout(m_requestTimeoutMsecs);
    encRequestData.request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    encRequestData.request.setRawHeader(QString("X-Client-Request-ID").toUtf8(), QUuid::createUuid().toString(QUuid::WithoutBraces).toUtf8());
    encRequestData.request.setUrl(endpoint.arg(m_proxyUrl.isEmpty() ? m_gatewayEndpoint : m_proxyUrl));
    if (encRequestData.request.url().scheme() == QLatin1String("https") && !gatewayAuthority().isEmpty()) {
        QSslConfiguration ssl = encRequestData.request.sslConfiguration();
        ssl.setCaCertificates(gatewayAuthority());
        encRequestData.request.setSslConfiguration(ssl);
    }

    // bypass killSwitch exceptions for API-gateway
#ifdef AMNEZIA_DESKTOP
    if (m_isStrictKillSwitchEnabled) {
        QString host = QUrl(encRequestData.request.url()).host();
        QString ip = NetworkUtilities::getIPAddress(host);
        if (!ip.isEmpty()) {
            IpcClient::withInterface([&](QSharedPointer<IpcInterfaceReplica> iface) {
                QRemoteObjectPendingReply<bool> reply = iface->addKillSwitchAllowedRange(QStringList { ip });
                if (!reply.waitForFinished(1000) || !reply.returnValue())
                    qWarning() << "GatewayController::prepareRequest(): Failed to execute remote addKillSwitchAllowedRange call";
            });
        }
    }
#endif

    QSimpleCrypto::QBlockCipher blockCipher;
    encRequestData.key = blockCipher.generatePrivateSalt(32);
    encRequestData.iv = blockCipher.generatePrivateSalt(32);
    encRequestData.salt = blockCipher.generatePrivateSalt(8);

    QJsonObject keyPayload;
    keyPayload[configKey::aesKey] = QString(encRequestData.key.toBase64());
    keyPayload[configKey::aesIv] = QString(encRequestData.iv.toBase64());
    keyPayload[configKey::aesSalt] = QString(encRequestData.salt.toBase64());

    QByteArray encryptedKeyPayload;
    QByteArray encryptedApiPayload;
    try {
        QSimpleCrypto::QRsa rsa;

        QByteArray rsaKey;
        {
            QFile keyFile(QStringLiteral(":/agw_public.pem"));
            if (!keyFile.open(QIODevice::ReadOnly)) {
                qCritical() << "Cannot open AGW public key resource";
                encRequestData.errorCode = ErrorCode::ApiMissingAgwPublicKey;
                return encRequestData;
            }
            rsaKey = keyFile.readAll();
        }

        EVP_PKEY *publicKey = nullptr;
        try {
            QSimpleCrypto::QRsa rsa;
            publicKey = rsa.getPublicKeyFromByteArray(rsaKey);
        } catch (...) {
            Utils::logException();
            qCritical() << "error loading public key from AGW resource";
            encRequestData.errorCode = ErrorCode::ApiMissingAgwPublicKey;
            return encRequestData;
        }

        encryptedKeyPayload = rsa.encrypt(QJsonDocument(keyPayload).toJson(), publicKey, RSA_PKCS1_PADDING);
        EVP_PKEY_free(publicKey);

        encryptedApiPayload = blockCipher.encryptAesBlockCipher(QJsonDocument(apiPayload).toJson(), encRequestData.key, encRequestData.iv,
                                                                "", encRequestData.salt);
    } catch (...) {
        Utils::logException();
        qCritical() << "error when encrypting the request body";
        encRequestData.errorCode = ErrorCode::ApiConfigDecryptionError;
        return encRequestData;
    }

    QJsonObject requestBody;
    requestBody[configKey::keyPayload] = QString(encryptedKeyPayload.toBase64());
    requestBody[configKey::apiPayload] = QString(encryptedApiPayload.toBase64());

    encRequestData.requestBody = QJsonDocument(requestBody).toJson();

    // the key, iv and body would let anyone with the log read the request
    // (the subscription key is in it) and the response: sizes only
    qDebug().noquote() << "[AGW REQUEST] encrypted," << encRequestData.requestBody.size() << "bytes";

    return encRequestData;
}

GatewayController::DecryptionResult GatewayController::tryDecryptResponseBody(const QByteArray &encryptedResponseBody,
                                                                              QNetworkReply::NetworkError replyError, const QByteArray &key,
                                                                              const QByteArray &iv, const QByteArray &salt)
{
    DecryptionResult result;
    result.decryptedBody = encryptedResponseBody;
    result.isDecryptionSuccessful = false;

    try {
        QSimpleCrypto::QBlockCipher blockCipher;
        result.decryptedBody = blockCipher.decryptAesBlockCipher(encryptedResponseBody, key, iv, "", salt);
        result.isDecryptionSuccessful = true;
        // the body holds keys and configs: not in the log
        qDebug().noquote() << "[AGW RESPONSE] decrypted," << result.decryptedBody.size() << "bytes";
    } catch (...) {
        result.decryptedBody = encryptedResponseBody;
        result.isDecryptionSuccessful = false;
        qDebug().noquote() << "[AGW RESPONSE] failed to decrypt," << encryptedResponseBody.size() << "bytes";
    }

    return result;
}

void GatewayController::restoreEndpoints(const QStringList &known, const QString &current)
{
    QMutexLocker lock(&s_endpointsMutex);
    s_knownEndpoints.clear();
    for (const QString &raw : known) {
        const QString endpoint = normalizedEndpoint(raw);
        if (!endpoint.isEmpty() && !s_knownEndpoints.contains(endpoint)) {
            s_knownEndpoints.append(endpoint);
        }
    }
    s_currentEndpoint = normalizedEndpoint(current);
}

void GatewayController::setEndpointsListener(std::function<void(const QStringList &, const QString &)> listener)
{
    QMutexLocker lock(&s_endpointsMutex);
    s_endpointsListener = std::move(listener);
}

QString GatewayController::currentEndpoint(const QString &fallback)
{
    QMutexLocker lock(&s_endpointsMutex);
    return s_currentEndpoint.isEmpty() ? fallback : s_currentEndpoint;
}

// the order a request tries the gateway's addresses in: the one that answered
// last, the ones the app was built with, then the relays the gateway named
QStringList GatewayController::candidateEndpoints() const
{
    QStringList list;
    const auto add = [&list](const QString &endpoint) {
        if (!endpoint.isEmpty() && !list.contains(endpoint)) {
            list.append(endpoint);
        }
    };
    if (m_isDevEnvironment) {
        add(m_gatewayEndpoint);
        return list;
    }
    QMutexLocker lock(&s_endpointsMutex);
    add(s_currentEndpoint);
    add(m_gatewayEndpoint);
    // the built-in fallbacks: one address, or several separated by commas
    // (the main relay's plain HTTP, then backup relays)
    for (const QString &endpoint : m_fallbackEndpoint.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        add(normalizedEndpoint(endpoint));
    }
    for (const QString &endpoint : std::as_const(s_knownEndpoints)) {
        add(endpoint);
    }
    // the ones that gave no answer lately last, in the same order among themselves
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    std::stable_partition(list.begin(), list.end(), [now](const QString &endpoint) {
        const auto failed = s_failedAt.constFind(endpoint);
        return failed == s_failedAt.constEnd() || now - failed.value() > failedAddressPauseMs;
    });
    return list;
}

void GatewayController::noteUnanswered(const QString &gatewayEndpoint)
{
    QMutexLocker lock(&s_endpointsMutex);
    s_failedAt.insert(normalizedEndpoint(gatewayEndpoint), QDateTime::currentMSecsSinceEpoch());
}

// The gateway answered at this address: it becomes the one tried first, and the
// relays the answer names replace the ones known (an address it no longer names
// is left for one it does)
void GatewayController::noteAnswered(const QString &gatewayEndpoint, const QByteArray &responseBody)
{
    QStringList named;
    const QJsonValue listed = QJsonDocument::fromJson(responseBody).object().value(QStringLiteral("gateway_endpoints"));
    for (const QJsonValue &value : listed.toArray()) {
        const QString endpoint = normalizedEndpoint(value.toString());
        if (!endpoint.isEmpty() && !named.contains(endpoint) && named.size() < 16) {
            named.append(endpoint);
        }
    }

    std::function<void(const QStringList &, const QString &)> listener;
    QStringList known;
    QString current;
    {
        QMutexLocker lock(&s_endpointsMutex);
        const QString currentBefore = s_currentEndpoint;
        const QStringList knownBefore = s_knownEndpoints;
        s_currentEndpoint = normalizedEndpoint(gatewayEndpoint);
        s_failedAt.remove(s_currentEndpoint);
        if (!named.isEmpty()) {
            s_knownEndpoints = named;
            if (!named.contains(s_currentEndpoint)) {
                s_currentEndpoint = named.first();
            }
        }
        if (s_currentEndpoint == currentBefore && s_knownEndpoints == knownBefore) {
            return;
        }
        listener = s_endpointsListener;
        known = s_knownEndpoints;
        current = s_currentEndpoint;
    }
    qInfo() << "[AGW] gateway addresses now:" << known.size() << "named by the gateway";
    if (listener) {
        listener(known, current);
    }
}

ErrorCode GatewayController::post(const QString &endpoint, const QJsonObject apiPayload, QByteArray &responseBody)
{
    // The gateway gave no answer at an address (timed out, unreachable, a relay
    // whose tunnel is down) - the next one is tried. Its own answers, refusals
    // included, are not retried: every address leads to the same gateway.
    const QStringList tries = candidateEndpoints();
    ErrorCode errorCode = ErrorCode::ApiConfigDownloadError;
    for (int i = 0; i < tries.size(); ++i) {
        if (i > 0) {
            qWarning() << "[AGW] no answer from gateway address" << i << "of" << tries.size() << "(" << static_cast<int>(errorCode)
                       << "), trying the next";
            m_proxyUrl.clear();
        }
        m_gatewayEndpoint = tries.at(i);
        bool answered = false;
        errorCode = doPost(endpoint, apiPayload, responseBody, answered);
        if (unanswered(errorCode, answered)) {
            noteUnanswered(tries.at(i));
        } else {
            if (answered && !m_isDevEnvironment) {
                noteAnswered(tries.at(i), errorCode == ErrorCode::NoError ? responseBody : QByteArray());
            }
            break;
        }
    }
    return errorCode;
}

ErrorCode GatewayController::doPost(const QString &endpoint, const QJsonObject &apiPayload, QByteArray &responseBody, bool &answered)
{
    EncryptedRequestData encRequestData = prepareRequest(endpoint, apiPayload);
    if (encRequestData.errorCode != ErrorCode::NoError) {
        return encRequestData.errorCode;
    }

    QNetworkReply *reply = amnApp->networkManager()->post(encRequestData.request, encRequestData.requestBody);

    QEventLoop wait;
    connect(reply, &QNetworkReply::finished, &wait, &QEventLoop::quit);

    QList<QSslError> sslErrors;
    connect(reply, &QNetworkReply::sslErrors, [this, &sslErrors](const QList<QSslError> &errors) { sslErrors = errors; });
    wait.exec(QEventLoop::ExcludeUserInputEvents);

    QByteArray encryptedResponseBody = reply->readAll();
    QString replyErrorString = reply->errorString();
    auto replyError = reply->error();
    int httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    reply->deleteLater();

    auto decryptionResult =
            tryDecryptResponseBody(encryptedResponseBody, replyError, encRequestData.key, encRequestData.iv, encRequestData.salt);

    if (sslErrors.isEmpty() && shouldBypassProxy(replyError, decryptionResult.decryptedBody, decryptionResult.isDecryptionSuccessful)) {
        auto requestFunction = [&encRequestData, &encryptedResponseBody](const QString &url) {
            encRequestData.request.setUrl(url);
            // a proxy is not one of our relays: the system's authorities
            encRequestData.request.setSslConfiguration(QSslConfiguration::defaultConfiguration());
            return amnApp->networkManager()->post(encRequestData.request, encRequestData.requestBody);
        };

        auto replyProcessingFunction = [&encryptedResponseBody, &replyErrorString, &replyError, &httpStatusCode, &sslErrors, &encRequestData,
                                        &decryptionResult, this](QNetworkReply *reply, const QList<QSslError> &nestedSslErrors) {
            encryptedResponseBody = reply->readAll();
            replyErrorString = reply->errorString();
            replyError = reply->error();
            httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

            decryptionResult =
                    tryDecryptResponseBody(encryptedResponseBody, replyError, encRequestData.key, encRequestData.iv, encRequestData.salt);

            if (!sslErrors.isEmpty()
                || shouldBypassProxy(replyError, decryptionResult.decryptedBody, decryptionResult.isDecryptionSuccessful)) {
                sslErrors = nestedSslErrors;
                return false;
            }
            return true;
        };

        auto serviceType = apiPayload.value(apiDefs::key::serviceType).toString("");
        auto userCountryCode = apiPayload.value(apiDefs::key::userCountryCode).toString("");
        bypassProxy(endpoint, serviceType, userCountryCode, requestFunction, replyProcessingFunction);
    }

    answered = decryptionResult.isDecryptionSuccessful;
    auto errorCode =
            apiUtils::checkNetworkReplyErrors(sslErrors, replyErrorString, replyError, httpStatusCode, decryptionResult.decryptedBody,
                                              decryptionResult.isDecryptionSuccessful);
    if (errorCode) {
        return errorCode;
    }

    if (!decryptionResult.isDecryptionSuccessful) {
        qCritical() << "error when decrypting the request body";
        return ErrorCode::ApiConfigDecryptionError;
    }

    responseBody = decryptionResult.decryptedBody;
    return ErrorCode::NoError;
}

QFuture<QPair<ErrorCode, QByteArray>> GatewayController::postAsync(const QString &endpoint, const QJsonObject apiPayload)
{
    auto promise = QSharedPointer<QPromise<QPair<ErrorCode, QByteArray>>>::create();
    promise->start();
    const QStringList tries = candidateEndpoints();
    if (tries.isEmpty()) {
        promise->addResult(qMakePair(ErrorCode::ApiConfigDownloadError, QByteArray()));
        promise->finish();
        return promise->future();
    }
    postAsyncFrom(endpoint, apiPayload, tries, 0, promise);
    return promise->future();
}

// one address after another, as post() does
void GatewayController::postAsyncFrom(const QString &endpoint, const QJsonObject &apiPayload, const QStringList &tries, int index,
                                      QSharedPointer<QPromise<QPair<ErrorCode, QByteArray>>> promise)
{
    m_gatewayEndpoint = tries.at(index);
    auto answered = std::make_shared<bool>(false);
    postAsyncOnce(endpoint, apiPayload, answered)
            .then(this, [this, endpoint, apiPayload, tries, index, promise, answered](QPair<ErrorCode, QByteArray> result) {
                if (unanswered(result.first, *answered)) {
                    noteUnanswered(tries.at(index));
                }
                if (unanswered(result.first, *answered) && index + 1 < tries.size()) {
                    qWarning() << "[AGW] no answer from gateway address" << index + 1 << "of" << tries.size() << "("
                               << static_cast<int>(result.first) << "), trying the next";
                    m_proxyUrl.clear();
                    postAsyncFrom(endpoint, apiPayload, tries, index + 1, promise);
                    return;
                }
                if (*answered && !m_isDevEnvironment) {
                    noteAnswered(tries.at(index), result.first == ErrorCode::NoError ? result.second : QByteArray());
                }
                promise->addResult(result);
                promise->finish();
            });
}

QFuture<QPair<ErrorCode, QByteArray>> GatewayController::postAsyncOnce(const QString &endpoint, const QJsonObject apiPayload,
                                                                       std::shared_ptr<bool> answered)
{
    auto promise = QSharedPointer<QPromise<QPair<ErrorCode, QByteArray>>>::create();
    promise->start();

    EncryptedRequestData encRequestData = prepareRequest(endpoint, apiPayload);
    if (encRequestData.errorCode != ErrorCode::NoError) {
        promise->addResult(qMakePair(encRequestData.errorCode, QByteArray()));
        promise->finish();
        return promise->future();
    }

    QNetworkReply *reply = amnApp->networkManager()->post(encRequestData.request, encRequestData.requestBody);

    auto sslErrors = QSharedPointer<QList<QSslError>>::create();

    connect(reply, &QNetworkReply::sslErrors, [sslErrors](const QList<QSslError> &errors) { *sslErrors = errors; });

    connect(reply, &QNetworkReply::finished, reply, [promise, sslErrors, encRequestData, endpoint, apiPayload, reply, answered, this]() mutable {
        QByteArray encryptedResponseBody = reply->readAll();
        QString replyErrorString = reply->errorString();
        auto replyError = reply->error();
        int httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        reply->deleteLater();

        auto decryptionResult =
                tryDecryptResponseBody(encryptedResponseBody, replyError, encRequestData.key, encRequestData.iv, encRequestData.salt);

        auto processResponse = [promise, encRequestData, answered](const GatewayController::DecryptionResult &decryptionResult,
                                                                   const QList<QSslError> &sslErrors, QNetworkReply::NetworkError replyError,
                                                                   const QString &replyErrorString, int httpStatusCode) {
            *answered = decryptionResult.isDecryptionSuccessful;
            auto errorCode = apiUtils::checkNetworkReplyErrors(sslErrors, replyErrorString, replyError, httpStatusCode,
                                                               decryptionResult.decryptedBody, decryptionResult.isDecryptionSuccessful);
            if (errorCode) {
                promise->addResult(qMakePair(errorCode, QByteArray()));
                promise->finish();
                return;
            }

            if (!decryptionResult.isDecryptionSuccessful) {
                Utils::logException();
                qCritical() << "error when decrypting the request body";
                promise->addResult(qMakePair(ErrorCode::ApiConfigDecryptionError, QByteArray()));
                promise->finish();
                return;
            }

            promise->addResult(qMakePair(ErrorCode::NoError, decryptionResult.decryptedBody));
            promise->finish();
        };

        if (sslErrors->isEmpty() && shouldBypassProxy(replyError, decryptionResult.decryptedBody, decryptionResult.isDecryptionSuccessful)) {
            auto serviceType = apiPayload.value(apiDefs::key::serviceType).toString("");
            auto userCountryCode = apiPayload.value(apiDefs::key::userCountryCode).toString("");

            QStringList baseUrls;
            if (m_isDevEnvironment) {
                baseUrls = QString(DEV_S3_ENDPOINT).split(", ");
            } else {
                baseUrls = QString(PROD_S3_ENDPOINT).split(", ");
            }

            QStringList proxyStorageUrls;
            if (!serviceType.isEmpty()) {
                for (const auto &baseUrl : baseUrls) {
                    QByteArray path = ("endpoints-" + serviceType + "-" + userCountryCode).toUtf8();
                    proxyStorageUrls.push_back(baseUrl + path.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals)
                                               + ".json");
                }
            }
            for (const auto &baseUrl : baseUrls)
                proxyStorageUrls.push_back(baseUrl + "endpoints.json");

            getProxyUrlsAsync(proxyStorageUrls, 0, [this, encRequestData, endpoint, processResponse](const QStringList &proxyUrls) {
                getProxyUrlAsync(proxyUrls, 0, [this, encRequestData, endpoint, processResponse](const QString &proxyUrl) {
                    bypassProxyAsync(endpoint, proxyUrl, encRequestData,
                                     [processResponse, this](const QByteArray &decryptedBody, bool isDecryptionSuccessful,
                                                             const QList<QSslError> &sslErrors, QNetworkReply::NetworkError replyError,
                                                             const QString &replyErrorString, int httpStatusCode) {
                                         GatewayController::DecryptionResult result;
                                         result.decryptedBody = decryptedBody;
                                         result.isDecryptionSuccessful = isDecryptionSuccessful;
                                         processResponse(result, sslErrors, replyError, replyErrorString, httpStatusCode);
                                     });
                });
            });

        } else {
            processResponse(decryptionResult, *sslErrors, replyError, replyErrorString, httpStatusCode);
        }
    });

    return promise->future();
}

QStringList GatewayController::getProxyUrls(const QString &serviceType, const QString &userCountryCode)
{
    QNetworkRequest request;
    request.setTransferTimeout(m_requestTimeoutMsecs);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QEventLoop wait;
    QList<QSslError> sslErrors;
    QNetworkReply *reply;

    QStringList baseUrls;
    if (m_isDevEnvironment) {
        baseUrls = QString(DEV_S3_ENDPOINT).split(", ");
    } else {
        baseUrls = QString(PROD_S3_ENDPOINT).split(", ");
    }
    std::random_device randomDevice;
    std::mt19937 generator(randomDevice());
    std::shuffle(baseUrls.begin(), baseUrls.end(), generator);

    QByteArray key = loadAgwPublicKey();

    QStringList proxyStorageUrls;
    if (!serviceType.isEmpty()) {
        for (const auto &baseUrl : baseUrls) {
            QByteArray path = ("endpoints-" + serviceType + "-" + userCountryCode).toUtf8();
            proxyStorageUrls.push_back(baseUrl + path.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals) + ".json");
        }
    }
    for (const auto &baseUrl : baseUrls) {
        proxyStorageUrls.push_back(baseUrl + "endpoints.json");
    }

    for (const auto &proxyStorageUrl : proxyStorageUrls) {
        request.setUrl(proxyStorageUrl);
        reply = amnApp->networkManager()->get(request);

        connect(reply, &QNetworkReply::finished, &wait, &QEventLoop::quit);
        connect(reply, &QNetworkReply::sslErrors, [this, &sslErrors](const QList<QSslError> &errors) { sslErrors = errors; });
        wait.exec(QEventLoop::ExcludeUserInputEvents);

        if (reply->error() == QNetworkReply::NetworkError::NoError) {
            auto encryptedResponseBody = reply->readAll();
            reply->deleteLater();

            EVP_PKEY *privateKey = nullptr;
            QByteArray responseBody;
            try {
                if (!m_isDevEnvironment) {
                    QCryptographicHash hash(QCryptographicHash::Sha512);
                    hash.addData(key);
                    QByteArray hashResult = hash.result().toHex();

                    QByteArray key = QByteArray::fromHex(hashResult.left(64));
                    QByteArray iv = QByteArray::fromHex(hashResult.mid(64, 32));

                    QByteArray ba = QByteArray::fromBase64(encryptedResponseBody);

                    QSimpleCrypto::QBlockCipher blockCipher;
                    responseBody = blockCipher.decryptAesBlockCipher(ba, key, iv);
                } else {
                    responseBody = encryptedResponseBody;
                }
            } catch (...) {
                Utils::logException();
                qCritical() << "error loading private key from environment variables or decrypting payload" << encryptedResponseBody;
                continue;
            }

            auto endpointsArray = QJsonDocument::fromJson(responseBody).array();

            QStringList endpoints;
            for (const auto &endpoint : endpointsArray) {
                endpoints.push_back(endpoint.toString());
            }
            return endpoints;
        } else {
            auto replyError = reply->error();
            int httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            qDebug() << replyError;
            qDebug() << httpStatusCode;
            qDebug() << "go to the next storage endpoint";

            reply->deleteLater();
        }
    }
    return {};
}

bool GatewayController::shouldBypassProxy(const QNetworkReply::NetworkError &replyError, const QByteArray &decryptedResponseBody,
                                          bool isDecryptionSuccessful)
{
    const QByteArray &responseBody = decryptedResponseBody;

    // no proxy storage in this build (PROD_S3_ENDPOINT / DEV_S3_ENDPOINT
    // unset): there is nothing to route around with, the answer stands
    if (QString(m_isDevEnvironment ? DEV_S3_ENDPOINT : PROD_S3_ENDPOINT).trimmed().isEmpty()) {
        return false;
    }

    int httpStatus = -1;
    if (isDecryptionSuccessful) {
        QJsonDocument jsonDoc = QJsonDocument::fromJson(responseBody);
        if (jsonDoc.isObject()) {
            QJsonObject jsonObj = jsonDoc.object();
            httpStatus = jsonObj.value("http_status").toInt(-1);
            // our gateway's word on this device or subscription: encrypted
            // with this request's key, so it is the gateway's own answer
            const QString error = jsonObj.value("error").toString();
            if (error == QLatin1String("device_unlinked") || error == QLatin1String("device_limit")
                || error == QLatin1String("subscription_expired") || error == QLatin1String("subscription_not_found")
                || error == QLatin1String("unlink_limit")) {
                return false;
            }
        }
    } else {
        qDebug() << "failed to decrypt the data";
        return true;
    }

    if (replyError == QNetworkReply::NetworkError::OperationCanceledError || replyError == QNetworkReply::NetworkError::TimeoutError) {
        qDebug() << "timeout occurred";
        qDebug() << replyError;
        return true;
    } else if (responseBody.contains("html")) {
        qDebug() << "the response contains an html tag";
        return true;
    } else if (httpStatus == httpStatusCodeNotFound) {
        if (responseBody.contains(errorResponsePattern1) || responseBody.contains(errorResponsePattern2)
            || responseBody.contains(errorResponsePattern3)) {
            return false;
        } else {
            qDebug() << replyError;
            return true;
        }
    } else if (httpStatus == httpStatusCodeNotImplemented) {
        if (responseBody.contains(updateRequestResponsePattern)) {
            return false;
        } else {
            qDebug() << replyError;
            return true;
        }
    } else if (httpStatus == httpStatusCodeConflict) {
        return false;
    } else if (replyError != QNetworkReply::NetworkError::NoError) {
        qDebug() << replyError;
        return true;
    }
    return false;
}

void GatewayController::bypassProxy(const QString &endpoint, const QString &serviceType, const QString &userCountryCode,
                                    std::function<QNetworkReply *(const QString &url)> requestFunction,
                                    std::function<bool(QNetworkReply *reply, const QList<QSslError> &sslErrors)> replyProcessingFunction)
{
    QStringList proxyUrls = getProxyUrls(serviceType, userCountryCode);
    std::random_device randomDevice;
    std::mt19937 generator(randomDevice());
    std::shuffle(proxyUrls.begin(), proxyUrls.end(), generator);

    QByteArray responseBody;

    auto bypassFunction = [this](const QString &endpoint, const QString &proxyUrl,
                                 std::function<QNetworkReply *(const QString &url)> requestFunction,
                                 std::function<bool(QNetworkReply * reply, const QList<QSslError> &sslErrors)> replyProcessingFunction) {
        QEventLoop wait;
        QList<QSslError> sslErrors;

        qDebug() << "go to the next proxy endpoint";
        QNetworkReply *reply = requestFunction(endpoint.arg(proxyUrl));

        QObject::connect(reply, &QNetworkReply::finished, &wait, &QEventLoop::quit);
        connect(reply, &QNetworkReply::sslErrors, [this, &sslErrors](const QList<QSslError> &errors) { sslErrors = errors; });
        wait.exec(QEventLoop::ExcludeUserInputEvents);

        auto result = replyProcessingFunction(reply, sslErrors);
        reply->deleteLater();
        return result;
    };

    if (m_proxyUrl.isEmpty()) {
        QNetworkRequest request;
        request.setTransferTimeout(1000);
        request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

        QEventLoop wait;
        QList<QSslError> sslErrors;
        QNetworkReply *reply;

        for (const QString &proxyUrl : proxyUrls) {
            request.setUrl(proxyUrl + "lmbd-health");
            reply = amnApp->networkManager()->get(request);

            connect(reply, &QNetworkReply::finished, &wait, &QEventLoop::quit);
            connect(reply, &QNetworkReply::sslErrors, [this, &sslErrors](const QList<QSslError> &errors) { sslErrors = errors; });
            wait.exec(QEventLoop::ExcludeUserInputEvents);

            if (reply->error() == QNetworkReply::NetworkError::NoError) {
                reply->deleteLater();

                m_proxyUrl = proxyUrl;
                if (!m_proxyUrl.isEmpty()) {
                    break;
                }
            } else {
                reply->deleteLater();
            }
        }
    }

    if (!m_proxyUrl.isEmpty()) {
        if (bypassFunction(endpoint, m_proxyUrl, requestFunction, replyProcessingFunction)) {
            return;
        }
    }

    for (const QString &proxyUrl : proxyUrls) {
        if (bypassFunction(endpoint, proxyUrl, requestFunction, replyProcessingFunction)) {
            m_proxyUrl = proxyUrl;
            break;
        }
    }
}

void GatewayController::getProxyUrlsAsync(const QStringList proxyStorageUrls, const int currentProxyStorageIndex,
                                          std::function<void(const QStringList &)> onComplete)
{
    if (currentProxyStorageIndex >= proxyStorageUrls.size()) {
        onComplete({});
        return;
    }

    QNetworkRequest request;
    request.setTransferTimeout(m_requestTimeoutMsecs);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setUrl(proxyStorageUrls[currentProxyStorageIndex]);

    QNetworkReply *reply = amnApp->networkManager()->get(request);

    // connect(reply, &QNetworkReply::sslErrors, this, [state](const QList<QSslError> &e) { *(state->sslErrors) = e; });

    connect(reply, &QNetworkReply::finished, this, [this, proxyStorageUrls, currentProxyStorageIndex, onComplete, reply]() {
        if (reply->error() == QNetworkReply::NoError) {
            QByteArray encrypted = reply->readAll();
            reply->deleteLater();

            QByteArray responseBody;
            try {
                QByteArray key = loadAgwPublicKey();
                if (!m_isDevEnvironment) {
                    QCryptographicHash hash(QCryptographicHash::Sha512);
                    hash.addData(key);
                    QByteArray h = hash.result().toHex();

                    QByteArray decKey = QByteArray::fromHex(h.left(64));
                    QByteArray iv = QByteArray::fromHex(h.mid(64, 32));
                    QByteArray ba = QByteArray::fromBase64(encrypted);

                    QSimpleCrypto::QBlockCipher cipher;
                    responseBody = cipher.decryptAesBlockCipher(ba, decKey, iv);
                } else {
                    responseBody = encrypted;
                }
            } catch (...) {
                Utils::logException();
                qCritical() << "error decrypting payload";
                QMetaObject::invokeMethod(
                        this, [=]() { getProxyUrlsAsync(proxyStorageUrls, currentProxyStorageIndex + 1, onComplete); }, Qt::QueuedConnection);
                return;
            }

            QJsonArray endpointsArray = QJsonDocument::fromJson(responseBody).array();
            QStringList endpoints;
            for (const QJsonValue &endpoint : endpointsArray)
                endpoints.push_back(endpoint.toString());

            QStringList shuffled = endpoints;
            std::random_device randomDevice;
            std::mt19937 generator(randomDevice());
            std::shuffle(shuffled.begin(), shuffled.end(), generator);

            onComplete(shuffled);
            return;
        }

        int httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        qDebug() << httpStatusCode;
        qDebug() << "go to the next storage endpoint";
        reply->deleteLater();
        QMetaObject::invokeMethod(
                this, [=]() { getProxyUrlsAsync(proxyStorageUrls, currentProxyStorageIndex + 1, onComplete); }, Qt::QueuedConnection);
    });
}

void GatewayController::getProxyUrlAsync(const QStringList proxyUrls, const int currentProxyIndex,
                                         std::function<void(const QString &)> onComplete)
{
    if (currentProxyIndex >= proxyUrls.size()) {
        onComplete("");
        return;
    }

    QNetworkRequest request;
    request.setTransferTimeout(1000);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setUrl(proxyUrls[currentProxyIndex] + "lmbd-health");

    QNetworkReply *reply = amnApp->networkManager()->get(request);

    // connect(reply, &QNetworkReply::sslErrors, this, [state](const QList<QSslError> &e) {
    //     *(state->sslErrors) = e;
    // });

    connect(reply, &QNetworkReply::finished, this, [this, proxyUrls, currentProxyIndex, onComplete, reply]() {
        reply->deleteLater();

        if (reply->error() == QNetworkReply::NoError) {
            m_proxyUrl = proxyUrls[currentProxyIndex];
            onComplete(m_proxyUrl);
            return;
        }

        qDebug() << "go to the next proxy endpoint";
        QMetaObject::invokeMethod(this, [=]() { getProxyUrlAsync(proxyUrls, currentProxyIndex + 1, onComplete); }, Qt::QueuedConnection);
    });
}

void GatewayController::bypassProxyAsync(
        const QString &endpoint, const QString &proxyUrl, EncryptedRequestData encRequestData,
        std::function<void(const QByteArray &, bool, const QList<QSslError> &, QNetworkReply::NetworkError, const QString &, int)> onComplete)
{
    auto sslErrors = QSharedPointer<QList<QSslError>>::create();
    if (proxyUrl.isEmpty()) {
        onComplete(QByteArray(), false, *sslErrors, QNetworkReply::InternalServerError, "empty proxy url", 0);
        return;
    }

    QNetworkRequest request = encRequestData.request;
    request.setUrl(endpoint.arg(proxyUrl));
    // a proxy is not one of our relays: the system's authorities
    request.setSslConfiguration(QSslConfiguration::defaultConfiguration());

    QNetworkReply *reply = amnApp->networkManager()->post(request, encRequestData.requestBody);

    connect(reply, &QNetworkReply::sslErrors, this, [sslErrors](const QList<QSslError> &errors) { *sslErrors = errors; });

    connect(reply, &QNetworkReply::finished, this, [sslErrors, onComplete, encRequestData, reply, this]() {
        QByteArray encryptedResponseBody = reply->readAll();
        QString replyErrorString = reply->errorString();
        auto replyError = reply->error();
        int httpStatusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        reply->deleteLater();

        auto decryptionResult =
                tryDecryptResponseBody(encryptedResponseBody, replyError, encRequestData.key, encRequestData.iv, encRequestData.salt);

        onComplete(decryptionResult.decryptedBody, decryptionResult.isDecryptionSuccessful, *sslErrors, replyError, replyErrorString,
                   httpStatusCode);
    });
}
