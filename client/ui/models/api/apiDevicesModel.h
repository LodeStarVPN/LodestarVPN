#ifndef APIDEVICESMODEL_H
#define APIDEVICESMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>
#include <QVector>

#include "settings.h"

class ApiDevicesModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        OsVersionRole = Qt::UserRole + 1,
        SupportTagRole,
        CountryCodeRole,
        LastUpdateRole,
        IsCurrentDeviceRole,
        // a device without our app: "amneziawg" (files for the AmneziaWG app), "link"; "" ours
        OtherAppRole,
        // such a device whose key is gone from the servers (a copy of it was caught)
        NeedsNewFileRole
    };

    explicit ApiDevicesModel(std::shared_ptr<Settings> settings, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    // the subscription's devices without our app of this name ("iPhone"): [{ id, needsNewFile }]
    Q_INVOKABLE QVariantList otherDevices(const QString &name) const;

public slots:
    void updateModel(const QJsonArray &issuedConfigs);

protected:
    QHash<int, QByteArray> roleNames() const override;

private:
    struct IssuedConfigInfo
    {
        QString installationUuid;
        QString workerLastUpdated;
        QString lastDownloaded;
        QString sourceType;
        QString osVersion;

        QString countryName;
        QString countryCode;

        bool isCurrent = false;   // the gateway says it is this device
        QString otherApp;
        bool needsNewFile = false;
    };

    QVector<IssuedConfigInfo> m_issuedConfigs;

    std::shared_ptr<Settings> m_settings;
};
#endif // APIDEVICESMODEL_H
