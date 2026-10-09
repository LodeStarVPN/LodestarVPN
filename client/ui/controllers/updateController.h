#ifndef UPDATECONTROLLER_H
#define UPDATECONTROLLER_H

#include <QCryptographicHash>
#include <QFile>
#include <QJsonObject>
#include <QNetworkReply>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QTimer>

#include <functional>
#include <memory>

#include "settings.h"

class QNetworkAccessManager;

// The in-app update (Android and Windows): asks the gateway what is published
// (/v1/app_update), takes only a release the release key signed, downloads this
// build's file, checks its size and hash (Android: package, signer and version
// too) and hands it to the system installer: SelfUpdater.kt on Android, msiexec
// on Windows (the app closes for it and opens again). The user confirms every
// install in the system's own windows; nothing installs silently. Elsewhere
// nothing runs (supported false).
class UpdateController : public QObject
{
    Q_OBJECT

public:
    enum State {
        Idle,
        Checking,
        UpToDate,
        Available,
        Downloading,
        ReadyToInstall,
        WaitingPermission,
        Installing,
        Failed
    };
    Q_ENUM(State)

    enum Failure {
        NoFailure,
        Network,
        Corrupt,
        PlayProtect,
        Cancelled,
        BlockedBySystem,
        Other
    };
    Q_ENUM(Failure)

    Q_PROPERTY(bool supported READ isSupported CONSTANT)
    Q_PROPERTY(bool updateAvailable READ isUpdateAvailable NOTIFY updateAvailableChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY updateAvailableChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(Failure failure READ failure NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(qint64 downloadSize READ downloadSize NOTIFY updateAvailableChanged)
    Q_PROPERTY(bool xiaomi READ isXiaomi CONSTANT)
    Q_PROPERTY(bool homeCardVisible READ isHomeCardVisible NOTIFY homeCardVisibleChanged)
    // Windows: the version an install this app closed for brought (once, at the start after it)
    Q_PROPERTY(QString updatedVersion READ updatedVersion CONSTANT)

    explicit UpdateController(const std::shared_ptr<Settings> &settings, QObject *parent = nullptr);

    // QML reads the enums as UpdateEnum.Available etc.
    static void declareQmlEnums();

    bool isSupported() const;
    bool isUpdateAvailable() const { return m_updateAvailable; }
    QString availableVersion() const { return m_version; }
    State state() const { return m_state; }
    Failure failure() const { return m_failure; }
    double progress() const { return m_progress; }
    qint64 downloadSize() const { return m_size; }
    bool isXiaomi() const { return m_xiaomi; }
    bool isHomeCardVisible() const;
    QString updatedVersion() const { return m_updatedVersion; }

    // Windows: the VPN goes down before the package replaces the service, and comes back
    // after an install this app closed for (CoreController hands these in)
    void setVpnControl(std::function<bool()> isConnected, std::function<void()> connectVpn,
                       std::function<void()> disconnectVpn);
    void onVpnDisconnected();

    Q_INVOKABLE void checkForUpdate(bool userInitiated);
    Q_INVOKABLE void startUpdate();
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void install();
    Q_INVOKABLE void openInstallPermission();
    Q_INVOKABLE void dismissHomeCard();

signals:
    void updateAvailableChanged();
    void stateChanged();
    void progressChanged();
    void homeCardVisibleChanged();
    // Windows: the install this app closed for did not happen (the sheet opens to say so)
    void installNotDone();

private:
    void setState(State state, Failure failure = NoFailure);
    void setProgress(double progress);
    void clearOffer();

    void cleanUpStaleFile(const std::function<void()> &then);
    void requestUpdateInfo();
    void applyUpdateInfo(bool userInitiated, const QJsonObject &data);

    void downloadFrom(int index);
    void onDownloadReadyRead();
    void onDownloadFinished();
    void stopDownload();
    // verifyUpdateApk on a worker thread; done gets its code unless a cancel or
    // another release came meanwhile
    void verifyFile(const std::function<void(qint64)> &done);

    void onInstallResult(int code);
    void onApplicationActive();

    // Windows: msiexec through a hidden PowerShell that opens the app again after it
    void launchInstaller();
#ifdef Q_OS_WIN
    void takeInstallOutcome();
#endif

    QString updateFilePath() const;
    qint64 installedVersionCode();
    QStringList deviceAbis();

    std::shared_ptr<Settings> m_settings;

    State m_state = Idle;
    Failure m_failure = NoFailure;
    double m_progress = 0;
    bool m_xiaomi = false;
    QString m_dismissedVersion;

    // the published release for this device (from the gateway)
    bool m_updateAvailable = false;
    QString m_version;
    qint64 m_versionCode = 0;
    QString m_abi;
    QStringList m_urls;
    QByteArray m_sha256; // lowercase hex
    qint64 m_size = 0;

    qint64 m_installedCode = 0;
    QStringList m_deviceAbis;

    bool m_started = false;
    bool m_checkInFlight = false;
    bool m_userCheckPending = false;
    qint64 m_lastCheckAt = 0;
    qint64 m_lastAttemptAt = 0;
    QTimer m_checkTimer;
    // Installing with the app on screen and no system window over it for a while:
    // the installer never showed one (or it was left), back to the Install button
    QTimer m_installWatch;

    QNetworkAccessManager *m_network = nullptr;
    QPointer<QNetworkReply> m_reply;
    QFile m_file;
    QCryptographicHash m_hash { QCryptographicHash::Sha256 };
    int m_urlIndex = 0;
    qint64 m_received = 0;
    // bumped by every cancel or new download: a late verification result is dropped
    int m_generation = 0;

    // Windows
    std::function<bool()> m_vpnConnected;
    std::function<void()> m_connectVpn;
    std::function<void()> m_disconnectVpn;
    bool m_launchWhenDisconnected = false;
    bool m_reconnectAfterStart = false;
    bool m_installNotDone = false;
    QString m_updatedVersion;
};

#endif // UPDATECONTROLLER_H
