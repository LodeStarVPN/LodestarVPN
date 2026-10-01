#ifndef SPLITPRESETSMODEL_H
#define SPLITPRESETSMODEL_H

#include <QAbstractListModel>
#include <QJsonObject>
#include <QSet>
#include <QSharedPointer>

#include "settings.h"
#include "servers_model.h"

class SplitPresetsModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        PresetIdRole = Qt::UserRole + 1,
        NameRole,
        DescriptionRole,
        DomainsCountRole,
        EnabledRole
    };

    explicit SplitPresetsModel(std::shared_ptr<Settings> settings, const QSharedPointer<ServersModel> &serversModel,
                               QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int routeMode READ routeMode WRITE setRouteMode NOTIFY routeModeChanged)
    Q_PROPERTY(int enabledCount READ enabledCount NOTIFY enabledCountChanged)

    Q_INVOKABLE void fetchPresets();
    Q_INVOKABLE void setPresetEnabled(int row, bool enabled);

    int routeMode() const;
    void setRouteMode(int routeMode);

    int enabledCount() const { return m_enabledPresets.size(); }

signals:
    void countChanged();
    void routeModeChanged();
    void enabledCountChanged();
    void fetchPresetsFinished();

protected:
    QHash<int, QByteArray> roleNames() const override;

private:
    struct Preset
    {
        QString id;
        QString name;
        QString description;
        QStringList domains;
    };

    void loadFromCache();
    void rebuildMergedPresets();
    void saveToCache() const;
    static Preset presetFromJson(const QJsonObject &presetObj);
    static QJsonObject presetToJson(const Preset &preset);

    std::shared_ptr<Settings> m_settings;
    QSharedPointer<ServersModel> m_serversModel;

    QList<Preset> m_apiPresets;
    QList<Preset> m_presets;
    QSet<QString> m_enabledPresets;
    QString m_version;
};

#endif
