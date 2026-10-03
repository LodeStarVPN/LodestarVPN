#include "apiUtils.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace
{
    const QByteArray AMNEZIA_CONFIG_SIGNATURE = QByteArray::fromHex("000000ff");

    QString escapeUnicode(const QString &input)
    {
        QString output;
        for (QChar c : input) {
            if (c.unicode() < 0x20 || c.unicode() > 0x7E) {
                output += QString("\\u%1").arg(QString::number(c.unicode(), 16).rightJustified(4, '0'));
            } else {
                output += c;
            }
        }
        return output;
    }
}

bool apiUtils::isSubscriptionExpired(const QString &subscriptionEndDate)
{
    QDateTime now = QDateTime::currentDateTimeUtc();
    QDateTime endDate = QDateTime::fromString(subscriptionEndDate, Qt::ISODateWithMs);
    return endDate < now;
}

bool apiUtils::isServerFromApi(const QJsonObject &serverConfigObject)
{
    auto configVersion = serverConfigObject.value(apiDefs::key::configVersion).toInt();
    switch (configVersion) {
    case apiDefs::ConfigSource::Telegram: return true;
    case apiDefs::ConfigSource::AmneziaGateway: return true;
    default: return false;
    }
}

apiDefs::ConfigType apiUtils::getConfigType(const QJsonObject &serverConfigObject)
{
    auto configVersion = serverConfigObject.value(apiDefs::key::configVersion).toInt();

    switch (configVersion) {
    case apiDefs::ConfigSource::Telegram: {
        constexpr QLatin1String freeV2Endpoint(FREE_V2_ENDPOINT);
        constexpr QLatin1String premiumV1Endpoint(PREM_V1_ENDPOINT);

        auto apiEndpoint = serverConfigObject.value(apiDefs::key::apiEndpoint).toString();

        if (apiEndpoint.contains(premiumV1Endpoint)) {
            return apiDefs::ConfigType::AmneziaPremiumV1;
        } else if (apiEndpoint.contains(freeV2Endpoint)) {
            return apiDefs::ConfigType::AmneziaFreeV2;
        }
    };
    case apiDefs::ConfigSource::AmneziaGateway: {
        constexpr QLatin1String servicePremium("amnezia-premium");
        constexpr QLatin1String serviceFree("amnezia-free");
        constexpr QLatin1String serviceExternalPremium("external-premium");
        // our gateway's subscription: an account with devices, like external premium
        constexpr QLatin1String serviceOurVpn("our-vpn");

        auto apiConfigObject = serverConfigObject.value(apiDefs::key::apiConfig).toObject();
        auto serviceType = apiConfigObject.value(apiDefs::key::serviceType).toString();

        if (serviceType == servicePremium) {
            return apiDefs::ConfigType::AmneziaPremiumV2;
        } else if (serviceType == serviceFree) {
            return apiDefs::ConfigType::AmneziaFreeV3;
        } else if (serviceType == serviceExternalPremium || serviceType == serviceOurVpn) {
            return apiDefs::ConfigType::ExternalPremium;
        }
    }
    default: {
        return apiDefs::ConfigType::SelfHosted;
    }
    };
}

apiDefs::ConfigSource apiUtils::getConfigSource(const QJsonObject &serverConfigObject)
{
    return static_cast<apiDefs::ConfigSource>(serverConfigObject.value(apiDefs::key::configVersion).toInt());
}

amnezia::ErrorCode apiUtils::checkNetworkReplyErrors(const QList<QSslError> &sslErrors, const QString &replyErrorString,
                                                     const QNetworkReply::NetworkError &replyError, const int httpStatusCode,
                                                     const QByteArray &responseBody, bool isDecrypted)
{
    const int httpStatusCodeConflict = 409;
    const int httpStatusCodeNotFound = 404;
    const int httpStatusCodeNotImplemented = 501;

    if (!sslErrors.empty()) {
        qDebug().noquote() << sslErrors;
        return amnezia::ErrorCode::ApiConfigSslError;
    } else if (replyError == QNetworkReply::NoError) {
        return amnezia::ErrorCode::NoError;
    } else if (replyError == QNetworkReply::NetworkError::OperationCanceledError
               || replyError == QNetworkReply::NetworkError::TimeoutError) {
        qDebug() << replyError;
        return amnezia::ErrorCode::ApiConfigTimeoutError;
    } else if (replyError == QNetworkReply::NetworkError::OperationNotImplementedError) {
        qDebug() << replyError;
        return amnezia::ErrorCode::ApiUpdateRequestError;
    } else {
        qDebug() << replyError;
        qDebug() << replyErrorString;
        qDebug() << httpStatusCode << "decrypted:" << isDecrypted;

        // The gateway's word on this device or subscription (unlinked, no
        // place, ended, gone, unlink limit) is acted on: the app disconnects
        // and removes the subscription's servers. It counts only when it came
        // encrypted with this request's key and names itself in "error": the
        // gateway is reached over plain HTTP, and a plain answer or a bare
        // status could be anyone's on the way. Anything else is a failed request.
        int httpStatusFromBody = -1;
        QString messageFromBody;
        QJsonDocument jsonDoc = isDecrypted ? QJsonDocument::fromJson(responseBody) : QJsonDocument();
        if (jsonDoc.isObject()) {
            QJsonObject jsonObj = jsonDoc.object();
            httpStatusFromBody = jsonObj.value("http_status").toInt(-1);
            if (httpStatusFromBody < 0) {
                httpStatusFromBody = jsonObj.value("status").toInt(-1);
            }
            messageFromBody = jsonObj.value("message").toString();
        }
        const int effectiveStatus = httpStatusFromBody > 0 ? httpStatusFromBody : httpStatusCode;
        const QString errorFromBody = jsonDoc.isObject() ? jsonDoc.object().value("error").toString() : QString();

        // our gateway's word on this device or subscription (not a failed request)
        if (effectiveStatus == 403 && errorFromBody == QLatin1String("device_unlinked")) {
            return amnezia::ErrorCode::ApiDeviceUnlinkedError;
        }
        if (effectiveStatus == 402 && errorFromBody == QLatin1String("subscription_expired")) {
            return amnezia::ErrorCode::ApiSubscriptionExpiredError;
        }
        if (effectiveStatus == 429 && errorFromBody == QLatin1String("unlink_limit")) {
            return amnezia::ErrorCode::ApiUnlinkLimitError;
        }
        if (effectiveStatus == httpStatusCodeNotFound && errorFromBody == QLatin1String("subscription_not_found")) {
            return amnezia::ErrorCode::ApiSubscriptionNotFoundError;
        }
        if (effectiveStatus == httpStatusCodeConflict && errorFromBody == QLatin1String("device_limit")) {
            return amnezia::ErrorCode::ApiConfigLimitError;
        } else if (effectiveStatus == httpStatusCodeNotFound || messageFromBody == QLatin1String("node_not_found")) {
            return amnezia::ErrorCode::ApiNotFoundError;
        } else if (effectiveStatus == httpStatusCodeNotImplemented) {
            return amnezia::ErrorCode::ApiUpdateRequestError;
        }
        return amnezia::ErrorCode::ApiConfigDownloadError;
    }

    qDebug() << "something went wrong";
    return amnezia::ErrorCode::InternalError;
}

bool apiUtils::isPremiumServer(const QJsonObject &serverConfigObject)
{
    static const QSet<apiDefs::ConfigType> premiumTypes = { apiDefs::ConfigType::AmneziaPremiumV1, apiDefs::ConfigType::AmneziaPremiumV2,
                                                            apiDefs::ConfigType::ExternalPremium };
    return premiumTypes.contains(getConfigType(serverConfigObject));
}

QString apiUtils::getPremiumV1VpnKey(const QJsonObject &serverConfigObject)
{
    if (apiUtils::getConfigType(serverConfigObject) != apiDefs::ConfigType::AmneziaPremiumV1) {
        return {};
    }

    QList<QPair<QString, QVariant>> orderedFields;
    orderedFields.append(qMakePair(apiDefs::key::name, serverConfigObject[apiDefs::key::name].toString()));
    orderedFields.append(qMakePair(apiDefs::key::description, serverConfigObject[apiDefs::key::description].toString()));
    orderedFields.append(qMakePair(apiDefs::key::configVersion, serverConfigObject[apiDefs::key::configVersion].toDouble()));
    orderedFields.append(qMakePair(apiDefs::key::protocol, serverConfigObject[apiDefs::key::protocol].toString()));
    orderedFields.append(qMakePair(apiDefs::key::apiEndpoint, serverConfigObject[apiDefs::key::apiEndpoint].toString()));
    orderedFields.append(qMakePair(apiDefs::key::apiKey, serverConfigObject[apiDefs::key::apiKey].toString()));

    QString vpnKeyStr = "{";
    for (int i = 0; i < orderedFields.size(); ++i) {
        const auto &pair = orderedFields[i];
        if (pair.second.typeId() == QMetaType::Type::QString) {
            vpnKeyStr += "\"" + pair.first + "\": \"" + pair.second.toString() + "\"";
        } else if (pair.second.typeId() == QMetaType::Type::Double || pair.second.typeId() == QMetaType::Type::Int) {
            vpnKeyStr += "\"" + pair.first + "\": " + QString::number(pair.second.toDouble(), 'f', 1);
        }

        if (i < orderedFields.size() - 1) {
            vpnKeyStr += ", ";
        }
    }
    vpnKeyStr += "}";

    QByteArray vpnKeyCompressed = escapeUnicode(vpnKeyStr).toUtf8();
    vpnKeyCompressed = qCompress(vpnKeyCompressed, 6);
    vpnKeyCompressed = vpnKeyCompressed.mid(4);

    QByteArray signedData = AMNEZIA_CONFIG_SIGNATURE + vpnKeyCompressed;

    return QString("vpn://%1").arg(QString(signedData.toBase64(QByteArray::Base64UrlEncoding)));
}

QString apiUtils::getPremiumV2VpnKey(const QJsonObject &serverConfigObject)
{
    if (apiUtils::getConfigType(serverConfigObject) != apiDefs::ConfigType::AmneziaPremiumV2) {
        return {};
    }

    QString vpnKeyText = "";

    auto apiConfig = serverConfigObject.value(apiDefs::key::apiConfig).toObject();
    auto authData = serverConfigObject.value(QLatin1String("auth_data")).toObject();

    const QString name = serverConfigObject.value(apiDefs::key::name).toString();
    const QString description = serverConfigObject.value(apiDefs::key::description).toString();
    const double configVersion = serverConfigObject.value(apiDefs::key::configVersion).toDouble();

    const QString serviceType = apiConfig.value(apiDefs::key::serviceType).toString();
    const QString serviceProtocol = apiConfig.value(QLatin1String("service_protocol")).toString();
    const QString userCountryCode = apiConfig.value(QLatin1String("user_country_code")).toString();

    const QString apiKey = authData.value(apiDefs::key::apiKey).toString();

    QString vpnKeyStr = "{";
    vpnKeyStr += "\"" + QString(apiDefs::key::name) + "\": \"" + name + "\", ";
    vpnKeyStr += "\"" + QString(apiDefs::key::description) + "\": \"" + description + "\", ";
    vpnKeyStr += "\"" + QString(apiDefs::key::configVersion) + "\": " + QString::number(static_cast<int>(configVersion)) + ", ";

    vpnKeyStr += "\"" + QString(apiDefs::key::apiConfig) + "\": {";
    vpnKeyStr += "\"" + QString(apiDefs::key::serviceType) + "\": \"" + serviceType + "\", ";
    vpnKeyStr += "\"service_protocol\": \"" + serviceProtocol + "\", ";
    vpnKeyStr += "\"user_country_code\": \"" + userCountryCode + "\"";
    vpnKeyStr += "}, ";

    vpnKeyStr += "\"auth_data\": {";
    vpnKeyStr += "\"" + QString(apiDefs::key::apiKey) + "\": \"" + apiKey + "\"";
    vpnKeyStr += "}";

    vpnKeyStr += "}";

    QByteArray vpnKeyCompressed = escapeUnicode(vpnKeyStr).toUtf8();
    vpnKeyCompressed = qCompress(vpnKeyCompressed, 6);
    vpnKeyCompressed = vpnKeyCompressed.mid(4);

    QByteArray signedData = AMNEZIA_CONFIG_SIGNATURE + vpnKeyCompressed;
    vpnKeyText = QString("vpn://%1").arg(QString(signedData.toBase64(QByteArray::Base64UrlEncoding)));

    return vpnKeyText;
}

QJsonObject apiUtils::translateLegacyHysteria2Outbound(const QJsonObject &outbound)
{
    if (outbound.value(QStringLiteral("protocol")).toString() != QStringLiteral("hysteria2")) {
        return outbound;
    }

    const QJsonArray servers = outbound.value(QStringLiteral("settings")).toObject()
                                       .value(QStringLiteral("servers")).toArray();
    const QJsonObject server = servers.isEmpty() ? QJsonObject() : servers.at(0).toObject();

    QJsonObject streamSettings = outbound.value(QStringLiteral("streamSettings")).toObject();
    QJsonObject tlsSettings = streamSettings.value(QStringLiteral("tlsSettings")).toObject();
    // hy2 works over HTTP/3 only, while backends may send a generic HTTPS ALPN
    tlsSettings[QStringLiteral("alpn")] = QJsonArray { QStringLiteral("h3") };

    QJsonObject hysteriaSettings;
    hysteriaSettings[QStringLiteral("version")] = 2;
    hysteriaSettings[QStringLiteral("auth")] = server.value(QStringLiteral("password")).toString();

    streamSettings[QStringLiteral("network")] = QStringLiteral("hysteria");
    streamSettings[QStringLiteral("tlsSettings")] = tlsSettings;
    streamSettings[QStringLiteral("hysteriaSettings")] = hysteriaSettings;

    QJsonObject settings;
    settings[QStringLiteral("version")] = 2;
    settings[QStringLiteral("address")] = server.value(QStringLiteral("address")).toString();
    settings[QStringLiteral("port")] = server.value(QStringLiteral("port")).toInt();

    QJsonObject translated = outbound;
    translated[QStringLiteral("protocol")] = QStringLiteral("hysteria");
    translated[QStringLiteral("settings")] = settings;
    translated[QStringLiteral("streamSettings")] = streamSettings;
    return translated;
}
