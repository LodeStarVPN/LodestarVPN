#include "updateController.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlEngine>
#include <QSharedPointer>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>
#include <QtConcurrent>

#include <openssl/evp.h>

#include "core/api/apiDefs.h"
#include "core/controllers/gatewayController.h"
#include "version.h"

#ifdef Q_OS_ANDROID
    #include "platforms/android/android_controller.h"
#endif
#ifdef Q_OS_WIN
    #include <QCoreApplication>
    #include <QProcess>
    #ifndef NOMINMAX
        #define NOMINMAX
    #endif
    #include <windows.h>
#endif

// the platforms that update themselves (elsewhere nothing runs)
#if defined(Q_OS_ANDROID) || defined(Q_OS_WIN)
    #define LODESTAR_SELF_UPDATE
#endif

namespace
{
    // The release key (Ed25519, public half): an update installs only when this key signed
    // its description - what the gateway or the way to it says can not make the app install
    // anything else. The private half stays on the publisher's PC (publish_update.py)
    constexpr char kReleaseKey[] = "JNbYwdFSQxrtsLIp0YkwH4ULQwnfyGIoFVWCMHJ/cKQ=";

    // the platform the gateway publishes this app's releases under
    QString platformName()
    {
#ifdef Q_OS_WIN
        return QStringLiteral("windows");
#else
        return QStringLiteral("android");
#endif
    }

    // what publish_update.py signs: keep the two the same
    QByteArray signedText(const QString &version, qint64 versionCode, const QString &abi, const QByteArray &sha256,
                          qint64 size)
    {
        return QStringList { QStringLiteral("lodestar-update-v1"), platformName(), version, QString::number(versionCode),
                             abi, QString::fromLatin1(sha256), QString::number(size) }
                .join(QLatin1Char('\n'))
                .toUtf8();
    }

    bool releaseKeySigned(const QByteArray &text, const QString &signatureBase64)
    {
        const QByteArray key = QByteArray::fromBase64(kReleaseKey);
        const QByteArray signature = QByteArray::fromBase64(signatureBase64.toLatin1());
        if (key.size() != 32 || signature.size() != 64) {
            return false;
        }
        EVP_PKEY *pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr,
                                                     reinterpret_cast<const unsigned char *>(key.constData()), key.size());
        EVP_MD_CTX *ctx = EVP_MD_CTX_new();
        const bool ok = pkey && ctx && EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, pkey) == 1
                && EVP_DigestVerify(ctx, reinterpret_cast<const unsigned char *>(signature.constData()), signature.size(),
                                    reinterpret_cast<const unsigned char *>(text.constData()), text.size())
                        == 1;
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        return ok;
    }

    // major·1000000 + minor·1000 + patch, as the build makes the Android versionCode
    qint64 versionCodeOf(const QString &version)
    {
        const QStringList parts = version.split(QLatin1Char(' ')).first().split(QLatin1Char('.'));
        if (parts.size() < 3) {
            return 0;
        }
        return parts.at(0).toLongLong() * 1000000 + parts.at(1).toLongLong() * 1000 + parts.at(2).toLongLong();
    }

    constexpr int kFirstCheckDelayMs = 20 * 1000;
    // an update left half-done (the app restarted on its way): no need to wait as long
    constexpr int kFirstCheckDelayWithFileMs = 3 * 1000;
    constexpr int kCheckIntervalMs = 6 * 60 * 60 * 1000;
    // the 6 h timer may fire a little before 6 h have passed since the check it follows
    constexpr qint64 kCheckSlackMs = 10 * 60 * 1000;
    // a background check that failed is not repeated on every return to the app
    constexpr qint64 kRetryAfterFailureMs = 30 * 60 * 1000;
    constexpr int kTransferTimeoutMs = 60 * 1000;
    constexpr int kInstallWatchMs = 15 * 1000;
    // Windows: how long the VPN may take to go down before the install starts anyway
    constexpr int kDisconnectWaitMs = 15 * 1000;
    // the installer's process is up: the app closes a moment later
    constexpr int kQuitAfterLaunchMs = 500;
    // a VPN turned off for the install comes back after the servers are in
    constexpr int kReconnectDelayMs = 1500;

    // keep synchronized with SelfUpdater.kt
    enum InstallResult {
        InstallSuccess = 0,
        InstallConfirming = 1,
        InstallPlayProtect = 2,
        InstallCancelled = 3,
        InstallPermissionNeeded = 4,
        InstallFailedOther = 5,
        InstallBlockedBySystem = 6
    };

    // verifyUpdateApk: unreadable, another package, not newer, another signer —
    // such a file never installs (-5, an error on the way, may pass next time)
    bool isDeadFile(qint64 code)
    {
        return code == -1 || code == -2 || code == -3 || code == -4;
    }

    // verifyFile: the file's size or SHA-256 is not the published one's
    // (none of verifyUpdateApk's codes)
    constexpr qint64 kNotThisRelease = -100;

    // this build's file in the release: the Android ABI of its native code, Windows' x64 MSI
    QString appAbi()
    {
        const QString arch = QSysInfo::buildCpuArchitecture();
#ifdef Q_OS_WIN
        return arch == QLatin1String("x86_64") ? QStringLiteral("x64") : QString();
#endif
        if (arch == QLatin1String("arm64")) {
            return QStringLiteral("arm64-v8a");
        }
        if (arch == QLatin1String("arm")) {
            return QStringLiteral("armeabi-v7a");
        }
        if (arch == QLatin1String("x86_64")) {
            return QStringLiteral("x86_64");
        }
        if (arch == QLatin1String("i386")) {
            return QStringLiteral("x86");
        }
        return {};
    }
}

UpdateController::UpdateController(const std::shared_ptr<Settings> &settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
    m_dismissedVersion = m_settings->updateDismissedVersion();

#ifdef LODESTAR_SELF_UPDATE
#ifdef Q_OS_ANDROID
    m_xiaomi = AndroidController::instance()->isXiaomiFamily();
#endif
#ifdef Q_OS_WIN
    // what came of an install this app started before it closed for it
    takeInstallOutcome();
#endif

    m_checkTimer.setInterval(kCheckIntervalMs);
    connect(&m_checkTimer, &QTimer::timeout, this, [this]() { checkForUpdate(false); });

    const int firstCheckDelay = QFile::exists(updateFilePath()) ? kFirstCheckDelayWithFileMs : kFirstCheckDelayMs;
    QTimer::singleShot(firstCheckDelay, this, [this]() {
        m_started = true;
        m_checkTimer.start();
        // a file left from before (installed since, or cut off) goes first
        cleanUpStaleFile([this]() { checkForUpdate(false); });
    });

#ifdef Q_OS_ANDROID
    m_installWatch.setSingleShot(true);
    m_installWatch.setInterval(kInstallWatchMs);
    connect(&m_installWatch, &QTimer::timeout, this, [this]() {
        if (m_state == Installing && QGuiApplication::applicationState() == Qt::ApplicationActive) {
            qInfo() << "[UPDATE] no installer window over the app: back to the Install button";
            setState(ReadyToInstall);
        }
    });

    connect(AndroidController::instance(), &AndroidController::updateInstallResult, this, &UpdateController::onInstallResult,
            Qt::QueuedConnection);
#endif

    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive) {
            onApplicationActive();
        } else {
            m_installWatch.stop();
        }
    });
#endif
}

// static
void UpdateController::declareQmlEnums()
{
    qmlRegisterUncreatableMetaObject(UpdateController::staticMetaObject, "UpdateEnum", 1, 0, "UpdateEnum", "Error: only enums");
}

bool UpdateController::isSupported() const
{
#ifdef LODESTAR_SELF_UPDATE
    return true;
#else
    return false;
#endif
}

bool UpdateController::isHomeCardVisible() const
{
    return m_updateAvailable && m_version != m_dismissedVersion;
}

void UpdateController::checkForUpdate(bool userInitiated)
{
#ifdef LODESTAR_SELF_UPDATE
    // the release on its way down or into the system stays as it is
    if (m_state == Downloading || m_state == Installing) {
        return;
    }

    if (m_checkInFlight) {
        if (userInitiated) {
            m_userCheckPending = true;
            if (!m_updateAvailable) {
                setState(Checking);
            }
        }
        return;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!userInitiated
        && (now - m_lastCheckAt < kCheckIntervalMs - kCheckSlackMs || now - m_lastAttemptAt < kRetryAfterFailureMs)) {
        return;
    }

    m_lastAttemptAt = now;
    m_checkInFlight = true;
    m_userCheckPending = userInitiated;
    if (userInitiated && !m_updateAvailable) {
        setState(Checking);
    }
    requestUpdateInfo();
#else
    Q_UNUSED(userInitiated)
#endif
}

void UpdateController::requestUpdateInfo()
{
    QJsonObject apiPayload;
    apiPayload[apiDefs::key::osVersion] = QSysInfo::productType();
    apiPayload[QStringLiteral("app_version")] = QString(APP_VERSION).split(' ').first();
    apiPayload[QStringLiteral("abis")] = deviceAbis().join(',');

    qInfo() << "[UPDATE] checking: installed" << installedVersionCode() << "abi" << appAbi() << "device abis" << deviceAbis();

    // as ApiConfigsController::executeRequestAsync: no subscription needed, an
    // expired one must still be able to update
    auto gatewayController = QSharedPointer<GatewayController>::create(
            m_settings->getGatewayEndpoint(false), m_settings->isDevGatewayEnv(false), apiDefs::requestTimeoutMsecs,
            m_settings->isStrictKillSwitchEnabled(), nullptr, m_settings->getGatewayEndpointFallback(false));
    auto future = gatewayController->postAsync(QString("%1v1/app_update"), apiPayload);
    future.then(this, [this, gatewayController, attemptAt = m_lastAttemptAt](QPair<amnezia::ErrorCode, QByteArray> result) {
        m_checkInFlight = false;
        const bool userInitiated = m_userCheckPending;
        m_userCheckPending = false;

        if (result.first != amnezia::ErrorCode::NoError) {
            qInfo() << "[UPDATE] check failed, error" << static_cast<int>(result.first);
            if (userInitiated && !m_updateAvailable) {
                setState(Failed, Network);
            }
            return;
        }

        m_lastCheckAt = attemptAt;
        applyUpdateInfo(userInitiated, QJsonDocument::fromJson(result.second).object());
    });
}

void UpdateController::applyUpdateInfo(bool userInitiated, const QJsonObject &data)
{
    // the system has the file now: what came of it decides, not this answer
    if (m_state == Installing) {
        return;
    }

    const qint64 installed = installedVersionCode();
    const QString version = data.value(QStringLiteral("version")).toString();
    const qint64 versionCode = data.value(QStringLiteral("version_code")).toInteger();
    const QJsonObject apks = data.value(QStringLiteral("apks")).toObject();

    // the ABI this app runs as, else the universal APK. Not another ABI the device
    // lists: Qt loads only the libraries of the primary one, so an arm64 APK on an
    // x86_64 device that also runs arm code would not start
    QString abi;
    if (const QString own = appAbi(); !own.isEmpty() && apks.contains(own)) {
        abi = own;
    }
    if (abi.isEmpty() && apks.contains(QStringLiteral("universal"))) {
        abi = QStringLiteral("universal");
    }

    const QJsonObject apk = apks.value(abi).toObject();
    QStringList urls;
    for (const QJsonValue &url : apk.value(QStringLiteral("urls")).toArray()) {
        // https only: the hash comes from our gateway, the file from anywhere
        if (url.toString().startsWith(QLatin1String("https://"))) {
            urls.append(url.toString());
        }
    }
    const QByteArray sha256 = apk.value(QStringLiteral("sha256")).toString().toLatin1().toLower();
    const qint64 size = apk.value(QStringLiteral("size")).toInteger();
    const bool wellFormed = !abi.isEmpty() && !urls.isEmpty() && sha256.size() == 64
            && QByteArray::fromHex(sha256).toHex() == sha256 && size > 0 && !version.isEmpty();
    // the release key's word on exactly this version, file, hash and size: a release the
    // gateway (or anyone on the way to it) offers without it is not ours to install
    const bool signedByUs = wellFormed
            && releaseKeySigned(signedText(version, versionCode, abi, sha256, size), apk.value(QStringLiteral("sig")).toString());
    const bool usable = wellFormed && signedByUs;

    if (versionCode <= installed || !usable) {
        if (versionCode > installed && wellFormed && !signedByUs) {
            qWarning() << "[UPDATE] release" << version << "is not signed by the release key: ignored";
        } else if (versionCode > installed) {
            qWarning() << "[UPDATE] release" << version << "has nothing usable for" << appAbi();
        } else {
            qInfo() << "[UPDATE] up to date: installed" << installed << "published" << versionCode;
        }
        // withdrawn (or installed since): its file is of no use, and it is big;
        // one still coming down stops first
        if (m_state == Downloading) {
            stopDownload();
        }
        QFile::remove(updateFilePath());
        clearOffer();
        setState(userInitiated ? UpToDate : Idle);
        return;
    }

    if (m_updateAvailable && versionCode == m_versionCode && abi == m_abi && sha256 == m_sha256) {
        // the same release: the user stays where they are with it; its sources may have changed
        if (m_state != Downloading) {
            m_urls = urls;
        }
        return;
    }

    // another release than the one coming down: that download is of no use now
    if (m_state == Downloading) {
        stopDownload();
        QFile::remove(updateFilePath());
    }

    qInfo() << "[UPDATE] available" << version << "code" << versionCode << "installed" << installed << "abi" << abi
            << "size" << size << "sources" << urls.size();
    const bool cardWasVisible = isHomeCardVisible();
    m_updateAvailable = true;
    m_version = version;
    m_versionCode = versionCode;
    m_abi = abi;
    m_urls = urls;
    m_sha256 = sha256;
    m_size = size;
    emit updateAvailableChanged();
    if (isHomeCardVisible() != cardWasVisible) {
        emit homeCardVisibleChanged();
    }

    ++m_generation;
    setProgress(0);
    setState(Available);

    // already downloaded before the app restarted (on some phones allowing the
    // installs restarts it): straight to the Install button, no new download
    if (QFile::exists(updateFilePath())) {
        verifyFile([this](qint64 code) {
            if (m_state != Available) {
                return;
            }
            if (code == m_versionCode) {
                qInfo() << "[UPDATE] the file from before is" << m_version << ": ready to install";
                setProgress(1);
                // Windows: the install this app closed for did not happen (no «Yes» to Windows,
                // or it failed): the sheet says so first, its button tries again
                if (m_installNotDone) {
                    m_installNotDone = false;
                    setState(Failed, Cancelled);
                    emit installNotDone();
                } else {
                    setState(ReadyToInstall);
                }
            } else {
                qInfo() << "[UPDATE] the file from before is not this release, verify code" << code;
                QFile::remove(updateFilePath());
            }
        });
    }
}

void UpdateController::clearOffer()
{
    if (!m_updateAvailable) {
        return;
    }
    const bool cardWasVisible = isHomeCardVisible();
    m_updateAvailable = false;
    m_version.clear();
    m_versionCode = 0;
    m_abi.clear();
    m_urls.clear();
    m_sha256.clear();
    m_size = 0;
    ++m_generation;
    setProgress(0);
    emit updateAvailableChanged();
    if (cardWasVisible) {
        emit homeCardVisibleChanged();
    }
}

void UpdateController::startUpdate()
{
#ifdef LODESTAR_SELF_UPDATE
    if (!m_updateAvailable || m_state == Downloading || m_state == Installing) {
        return;
    }

    ++m_generation;
    setProgress(0);
    setState(Downloading);

    // a file from an earlier start may be this very release: no second download
    if (QFile::exists(updateFilePath())) {
        setProgress(1);
        verifyFile([this](qint64 code) {
            if (m_state != Downloading) {
                return;
            }
            if (code == m_versionCode) {
                qInfo() << "[UPDATE] the file from before is" << m_version << ": ready to install";
                setState(ReadyToInstall);
                return;
            }
            qInfo() << "[UPDATE] the file from before is not this release, verify code" << code;
            QFile::remove(updateFilePath());
            downloadFrom(0);
        });
        return;
    }
    downloadFrom(0);
#endif
}

void UpdateController::downloadFrom(int index)
{
    if (index >= m_urls.size()) {
        qWarning() << "[UPDATE] the download failed from every source";
        setProgress(0);
        setState(Failed, Network);
        return;
    }

    m_urlIndex = index;
    m_received = 0;
    m_hash.reset();
    setProgress(0);

    const QString path = updateFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    m_file.setFileName(path);
    if (!m_file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[UPDATE] cannot write the update file:" << m_file.errorString();
        setState(Failed, Corrupt);
        return;
    }

    if (!m_network) {
        m_network = new QNetworkAccessManager(this);
    }
    QNetworkRequest request { QUrl(m_urls.at(index)) };
    // GitHub hands the file out through a redirect: on to https only
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(kTransferTimeoutMs);

    qInfo() << "[UPDATE] downloading" << m_version << "for" << m_abi << "from source" << index + 1 << "of" << m_urls.size();
    QNetworkReply *reply = m_network->get(request);
    m_reply = reply;
    connect(reply, &QNetworkReply::readyRead, this, &UpdateController::onDownloadReadyRead);
    connect(reply, &QNetworkReply::finished, this, &UpdateController::onDownloadFinished);
}

void UpdateController::onDownloadReadyRead()
{
    if (!m_reply) {
        return;
    }
    const QByteArray chunk = m_reply->readAll();
    m_received += chunk.size();
    if (m_received > m_size) {
        // more than the release's size: not our file, and not worth the storage
        qWarning() << "[UPDATE] the download is bigger than the release";
        stopDownload();
        QFile::remove(updateFilePath());
        setProgress(0);
        setState(Failed, Corrupt);
        return;
    }
    m_hash.addData(chunk);
    if (m_file.write(chunk) != chunk.size()) {
        qWarning() << "[UPDATE] cannot write the update file:" << m_file.errorString();
        stopDownload();
        QFile::remove(updateFilePath());
        setProgress(0);
        setState(Failed, Corrupt);
        return;
    }
    setProgress(double(m_received) / double(m_size));
}

void UpdateController::onDownloadFinished()
{
    if (!m_reply) {
        return;
    }
    if (m_reply->bytesAvailable() > 0) {
        onDownloadReadyRead();
        if (!m_reply) {
            return; // the last bytes were too many or could not be written
        }
    }

    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    reply->deleteLater();
    m_file.close();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[UPDATE] the download from source" << m_urlIndex + 1 << "failed:" << reply->error() << "HTTP"
                   << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QFile::remove(updateFilePath());
        downloadFrom(m_urlIndex + 1);
        return;
    }

    if (m_received != m_size || m_hash.result().toHex() != m_sha256) {
        qWarning() << "[UPDATE] the downloaded file is not the release: size" << m_received << "of" << m_size;
        QFile::remove(updateFilePath());
        setProgress(0);
        setState(Failed, Corrupt);
        return;
    }

    qInfo() << "[UPDATE] downloaded" << m_received << "bytes, the hash matches";
    setProgress(1);
    // the package, its signer and its version: the system would refuse another
    // signer only at the very end, after the user went through its windows
    verifyFile([this](qint64 code) {
        if (m_state != Downloading) {
            return;
        }
        if (code == m_versionCode) {
            qInfo() << "[UPDATE]" << m_version << "is signed by our key: ready to install";
            setState(ReadyToInstall);
            return;
        }
        qWarning() << "[UPDATE] the downloaded file failed the package check, code" << code;
        QFile::remove(updateFilePath());
        setProgress(0);
        setState(Failed, Corrupt);
    });
}

void UpdateController::stopDownload()
{
    if (m_reply) {
        QNetworkReply *reply = m_reply;
        m_reply = nullptr;
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    m_file.close();
}

void UpdateController::cancelDownload()
{
#ifdef LODESTAR_SELF_UPDATE
    if (m_state != Downloading) {
        return;
    }
    ++m_generation;
    stopDownload();
    QFile::remove(updateFilePath());
    qInfo() << "[UPDATE] download cancelled";
    setProgress(0);
    setState(m_updateAvailable ? Available : Idle);
#endif
}

void UpdateController::install()
{
#ifdef LODESTAR_SELF_UPDATE
    if (!m_updateAvailable || m_state == Downloading || m_state == Installing) {
        return;
    }

    const QString path = updateFilePath();
    // nothing checked to install yet: download (or verify) first
    if (m_state == Available || (m_state == Failed && (m_failure == Network || m_failure == Corrupt))
        || !QFile::exists(path)) {
        startUpdate();
        return;
    }

#ifdef Q_OS_WIN
    qInfo() << "[UPDATE] installing" << m_version << "code" << m_versionCode << "over" << installedVersionCode();
    setState(Installing);
    // the package stops the service and replaces the app: the VPN goes down cleanly first
    // (a VLESS tunnel cut by the service stopping leaves its routes behind), and comes back
    // when the app opens again
    if (m_vpnConnected && m_vpnConnected() && m_disconnectVpn) {
        m_settings->setUpdateReconnect(true);
        m_launchWhenDisconnected = true;
        m_disconnectVpn();
        QTimer::singleShot(kDisconnectWaitMs, this, [this]() {
            if (m_launchWhenDisconnected) {
                qWarning() << "[UPDATE] the VPN did not say it is off: installing anyway";
                launchInstaller();
            }
        });
        return;
    }
    launchInstaller();
#else
    if (!AndroidController::instance()->canInstallUpdates()) {
        qInfo() << "[UPDATE] the app may not install apps yet: asking the user";
        setState(WaitingPermission);
        return;
    }

    qInfo() << "[UPDATE] installing" << m_version << "code" << m_versionCode << "over" << installedVersionCode();
    setState(Installing);
    AndroidController::instance()->installUpdate(path);
#endif
#endif
}

void UpdateController::setVpnControl(std::function<bool()> isConnected, std::function<void()> connectVpn,
                                     std::function<void()> disconnectVpn)
{
    m_vpnConnected = std::move(isConnected);
    m_connectVpn = std::move(connectVpn);
    m_disconnectVpn = std::move(disconnectVpn);
    // the VPN this app turned off for an install it closed for comes back now,
    // after the servers are in (as the auto connect at start does)
    if (m_reconnectAfterStart && m_connectVpn) {
        m_reconnectAfterStart = false;
        QTimer::singleShot(kReconnectDelayMs, this, [this]() {
            if (m_vpnConnected && !m_vpnConnected()) {
                qInfo() << "[UPDATE] the VPN was on before the install: connecting";
                m_connectVpn();
            }
        });
    }
}

void UpdateController::onVpnDisconnected()
{
    if (m_launchWhenDisconnected) {
        launchInstaller();
    }
}

void UpdateController::launchInstaller()
{
#ifdef Q_OS_WIN
    m_launchWhenDisconnected = false;
    // PowerShell's single-quoted string: a ' inside doubles
    const auto quoted = [](QString text) {
        return QLatin1Char('\'') + text.replace(QLatin1Char('\''), QLatin1String("''")) + QLatin1Char('\'');
    };
    const QString msi = QDir::toNativeSeparators(updateFilePath());
    const QString app = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
    // msiexec asks Windows for the rights (UAC) and shows only its progress; this app is
    // closed by then (the package would close it anyway) and opens again when it is done,
    // whatever came of it: its next start tells (takeInstallOutcome)
    const QString script = QStringLiteral("Start-Process -FilePath msiexec.exe -ArgumentList @('/i', %1, '/passive', '/norestart') -Wait; "
                                          "Start-Process -FilePath %2")
                                   .arg(quoted(QLatin1Char('"') + msi + QLatin1Char('"')), quoted(app));
    // -EncodedCommand: UTF-16LE in base64, no quoting of paths through the command line
    const QByteArray encoded =
            QByteArray(reinterpret_cast<const char *>(script.utf16()), script.size() * 2).toBase64();

    m_settings->setUpdatePending(m_versionCode, m_version);
    QProcess process;
    process.setProgram(QStringLiteral("powershell.exe"));
    process.setArguments({ QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"), QStringLiteral("-ExecutionPolicy"),
                           QStringLiteral("Bypass"), QStringLiteral("-WindowStyle"), QStringLiteral("Hidden"),
                           QStringLiteral("-EncodedCommand"), QString::fromLatin1(encoded) });
    process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) { args->flags |= CREATE_NO_WINDOW; });
    if (!process.startDetached()) {
        qWarning() << "[UPDATE] the installer did not start:" << process.errorString();
        m_settings->clearUpdatePending();
        if (m_settings->updateReconnect() && m_connectVpn) {
            m_settings->setUpdateReconnect(false);
            m_connectVpn();
        }
        setState(Failed, Other);
        return;
    }
    qInfo() << "[UPDATE] the installer runs; the app closes and opens again after it";
    QTimer::singleShot(kQuitAfterLaunchMs, qApp, &QCoreApplication::quit);
#endif
}

#ifdef Q_OS_WIN
void UpdateController::takeInstallOutcome()
{
    const qint64 pending = m_settings->updatePendingCode();
    if (pending <= 0) {
        return;
    }
    const QString version = m_settings->updatePendingVersion();
    m_reconnectAfterStart = m_settings->updateReconnect();
    m_settings->clearUpdatePending();
    if (installedVersionCode() >= pending) {
        qInfo() << "[UPDATE] updated to" << version;
        QFile::remove(updateFilePath());
        m_updatedVersion = version;
    } else {
        // no «Yes» to Windows, or the package failed: the offer opens saying so
        qInfo() << "[UPDATE] the install of" << version << "did not happen";
        m_installNotDone = true;
    }
}
#endif

void UpdateController::openInstallPermission()
{
#ifdef Q_OS_ANDROID
    qInfo() << "[UPDATE] opening the install permission settings";
    AndroidController::instance()->openUpdateInstallSettings();
#endif
}

void UpdateController::dismissHomeCard()
{
    if (!m_updateAvailable || m_dismissedVersion == m_version) {
        return;
    }
    m_dismissedVersion = m_version;
    m_settings->setUpdateDismissedVersion(m_version);
    qInfo() << "[UPDATE] home card closed for" << m_version;
    emit homeCardVisibleChanged();
}

void UpdateController::onInstallResult(int code)
{
    qInfo() << "[UPDATE] install result" << code;
    if (!m_updateAvailable) {
        return;
    }

    switch (code) {
    case InstallSuccess: // the system replaces the app now
    case InstallConfirming:
        setState(Installing);
        m_installWatch.start();
        break;
    case InstallPlayProtect: setState(Failed, PlayProtect); break;
    case InstallCancelled: setState(Failed, Cancelled); break;
    case InstallPermissionNeeded: setState(WaitingPermission); break;
    case InstallBlockedBySystem: setState(Failed, BlockedBySystem); break;
    case InstallFailedOther:
    default: setState(Failed, Other); break;
    }
}

void UpdateController::onApplicationActive()
{
#ifdef LODESTAR_SELF_UPDATE
#ifdef Q_OS_ANDROID
    // back from the system settings with the installs allowed: on to the install
    if (m_state == WaitingPermission && AndroidController::instance()->canInstallUpdates()) {
        qInfo() << "[UPDATE] installs allowed";
        install();
        return;
    }
    if (m_state == Installing) {
        m_installWatch.start();
    }
#endif
    if (m_started) {
        checkForUpdate(false);
    }
#endif
}

void UpdateController::setState(State state, Failure failure)
{
    if (m_state == state && m_failure == failure) {
        return;
    }
    qInfo() << "[UPDATE] state" << state << failure;
    m_state = state;
    m_failure = failure;
    if (state == Installing) {
        m_installWatch.start();
    } else {
        m_installWatch.stop();
    }
    emit stateChanged();
}

void UpdateController::setProgress(double progress)
{
    // half a percent is a step the bar shows: not one signal per network chunk
    if (progress == m_progress || (progress > 0 && progress < 1 && qAbs(progress - m_progress) < 0.005)) {
        return;
    }
    m_progress = progress;
    emit progressChanged();
}

void UpdateController::cleanUpStaleFile(const std::function<void()> &then)
{
#ifdef Q_OS_ANDROID
    const QString path = updateFilePath();
    // a release on offer owns the file (coming down, checked, kept for a retry):
    // applyUpdateInfo decides about it. A check from About may come before this.
    if (m_updateAvailable || m_state == Downloading || m_state == Installing || !QFile::exists(path)) {
        then();
        return;
    }
    const int generation = m_generation;
    QtConcurrent::run([path]() { return AndroidController::instance()->verifyUpdateApk(path); })
            .then(this, [this, path, generation, then](qint64 code) {
                // a release offered or a download started meanwhile owns the file now
                if (generation == m_generation && !m_updateAvailable && m_state != Downloading && isDeadFile(code)) {
                    qInfo() << "[UPDATE] an old update file removed, verify code" << code;
                    QFile::remove(path);
                }
                then();
            });
#else
    then();
#endif
}

void UpdateController::verifyFile(const std::function<void(qint64)> &done)
{
#ifdef LODESTAR_SELF_UPDATE
    const QString path = updateFilePath();
    const int generation = m_generation;
    // the hash and the APK parser read the whole file: off the UI thread
    QtConcurrent::run([path, size = m_size, sha256 = m_sha256, versionCode = m_versionCode]() -> qint64 {
        // the very bytes on offer, not just a build with this version code: a
        // release republished under its tag (or another main's build) keeps the code
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            return -1; // unreadable, as verifyUpdateApk says it
        }
        QCryptographicHash hash(QCryptographicHash::Sha256);
        if (file.size() != size || !hash.addData(&file) || hash.result().toHex() != sha256) {
            return kNotThisRelease;
        }
        file.close();
#ifdef Q_OS_ANDROID
        Q_UNUSED(versionCode)
        return AndroidController::instance()->verifyUpdateApk(path);
#else
        // the MSI: the very bytes the release key signed, nothing more to read from it
        return versionCode;
#endif
    }).then(this, [this, generation, done](qint64 code) {
                // cancelled, or another release came meanwhile
                if (generation == m_generation) {
                    done(code);
                }
            });
#else
    Q_UNUSED(done)
#endif
}

QString UpdateController::updateFilePath() const
{
    // the app's own files dir on Android: no other app reads or swaps it; on Windows the
    // user's own app data (the installer, run with the rights Windows gives, reads it there)
#ifdef Q_OS_WIN
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/updates/LodestarVPN-update.msi");
#else
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/updates/LodestarVPN-update.apk");
#endif
}

qint64 UpdateController::installedVersionCode()
{
#ifdef Q_OS_ANDROID
    if (m_installedCode <= 0) {
        m_installedCode = AndroidController::instance()->appVersionCode();
    }
#else
    // the version this build was made as, by the Android rule
    m_installedCode = versionCodeOf(QString(APP_VERSION));
#endif
    return m_installedCode;
}

QStringList UpdateController::deviceAbis()
{
#ifdef Q_OS_ANDROID
    if (m_deviceAbis.isEmpty()) {
        m_deviceAbis = AndroidController::instance()->updateAbis();
    }
#endif
    return m_deviceAbis;
}
