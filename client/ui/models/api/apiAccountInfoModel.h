#ifndef APIACCOUNTINFOMODEL_H
#define APIACCOUNTINFOMODEL_H

#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocale>

#include "core/api/apiDefs.h"

class ApiAccountInfoModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        SubscriptionStatusRole = Qt::UserRole + 1,
        ConnectedDevicesRole,
        ServiceDescriptionRole,
        EndDateRole,
        IsComponentVisibleRole,
        HasExpiredWorkerRole,
        IsProtocolSelectionSupportedRole,
        UnlinkAvailableAtRole
    };

    explicit ApiAccountInfoModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    // the app's language, for dates
    void setLocale(const QLocale &locale) { m_locale = locale; }

public slots:
    void updateModel(const QJsonObject &accountInfoObject, const QJsonObject &serverConfig);
    QVariant data(const QString &roleString);

    QJsonArray getAvailableCountries();
    QJsonArray getIssuedConfigsInfo();

    QString getTelegramBotLink();
    QString getEmailLink();
    QString getBillingEmailLink();
    QString getSiteLink();
    QString getFullSiteLink();

protected:
    QHash<int, QByteArray> roleNames() const override;

private:
    struct AccountInfoData
    {
        QString subscriptionEndDate;
        int activeDeviceCount;
        int maxDeviceCount;

        apiDefs::ConfigType configType;

        QStringList supportedProtocols;

        QString subscriptionDescription;

        // when another device may be unlinked (one a day), empty = now
        QDateTime unlinkAvailableAt;
    };

    AccountInfoData m_accountInfoData;
    QLocale m_locale;
    QJsonArray m_availableCountries;
    QJsonArray m_issuedConfigsInfo;
    QJsonObject m_supportInfo;
};

#endif // APIACCOUNTINFOMODEL_H
