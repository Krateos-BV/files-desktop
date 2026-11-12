/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "xeniaupdatecheck.h"

#include "config.h"
#include "configfile.h"
#include "theme.h"

#include <QAction>
#include <QDesktopServices>
#include <QLoggingCategory>
#include <QMenu>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>

#include <chrono>

using namespace std::chrono_literals;

namespace OCC::Xenia
{

Q_LOGGING_CATEGORY(lcXeniaUpdate, "xenia.gui.updatecheck", QtInfoMsg)

namespace
{

constexpr auto firstCheckDelay = 30s;
constexpr auto checkInterval = 24h;
constexpr auto requestTimeout = 30s;
constexpr auto lastAnnouncedKey = "Xenia/lastAnnouncedUpdate";

QString releaseVersion()
{
#if defined(XENIA_RELEASE_VERSION)
    return QStringLiteral(XENIA_RELEASE_VERSION);
#else
    return {};
#endif
}

QString updateRepository()
{
#if defined(XENIA_UPDATE_REPOSITORY)
    return QStringLiteral(XENIA_UPDATE_REPOSITORY);
#else
    return {};
#endif
}

} // namespace

UpdateCheck *UpdateCheck::instance()
{
    static auto *check = new UpdateCheck;
    return check;
}

UpdateCheck::UpdateCheck(QObject *parent)
    : QObject(parent)
{
    _dailyTimer.setInterval(checkInterval);
    connect(&_dailyTimer, &QTimer::timeout, this, &UpdateCheck::checkNow);
}

bool UpdateCheck::isEnabled()
{
    return isCalVerTag(releaseVersion()) && !updateRepository().isEmpty();
}

void UpdateCheck::start()
{
    if (_started) {
        return;
    }
    if (!isEnabled()) {
        qCInfo(lcXeniaUpdate) << "Update check off: this build has no release version";
        return;
    }
    _started = true;
    _network = new QNetworkAccessManager(this);
    QTimer::singleShot(firstCheckDelay, this, &UpdateCheck::checkNow);
    _dailyTimer.start();
}

void UpdateCheck::checkNow()
{
    // Anonymous call to the public GitHub API, the same one Xenia Talk uses. Nothing
    // about the installation is sent apart from the User-Agent.
    QNetworkRequest request(QUrl(QStringLiteral("https://api.github.com/repos/%1/releases").arg(updateRepository())));
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Xenia-Files/%1").arg(releaseVersion()));
    request.setTransferTimeout(static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(requestTimeout).count()));

    auto *reply = _network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError || status != 200) {
            // Without this a rate limit (403) or an outage looks exactly like "no update".
            qCWarning(lcXeniaUpdate) << "Update check failed: HTTP" << status << reply->errorString();
            return;
        }

        QString note;
        const auto offer = pickUpdate(reply->readAll(), releaseVersion(), currentUpdatePlatform(), &note);
        if (!note.isEmpty()) {
            qCInfo(lcXeniaUpdate) << "Update check:" << note;
        }
        if (!offer.isValid()) {
            qCInfo(lcXeniaUpdate) << "No newer release than" << releaseVersion();
            if (_offer.isValid()) {
                _offer = {};
                Q_EMIT offerChanged();
            }
            return;
        }

        qCInfo(lcXeniaUpdate) << "Newer release available:" << offer.version << offer.openUrl();
        const auto changed = offer.version != _offer.version || offer.openUrl() != _offer.openUrl();
        _offer = offer;
        if (changed) {
            Q_EMIT offerChanged();
        }
        announceOnce();
    });
}

void UpdateCheck::announceOnce()
{
    QSettings settings(ConfigFile().configFile(), QSettings::IniFormat);
    if (settings.value(QLatin1String(lastAnnouncedKey)).toString() == _offer.version) {
        return;
    }
    settings.setValue(QLatin1String(lastAnnouncedKey), _offer.version);

    const auto appName = Theme::instance()->appNameGUI();
    Q_EMIT updateAnnouncement(tr("%1 update available").arg(appName),
                              tr("%1 %2 is available. Use \"Update to %1 %2\" in the tray menu to download it.").arg(appName, _offer.version),
                              _offer.openUrl());
}

void UpdateCheck::addMenuAction(QMenu *menu)
{
    if (!menu || !isEnabled()) {
        return;
    }

    auto *action = menu->addAction(QString());
    action->setObjectName(QStringLiteral("xeniaUpdateAction"));
    const QPointer<QAction> guardedAction(action);
    const auto refresh = [this, guardedAction] {
        if (!guardedAction) {
            return;
        }
        guardedAction->setText(tr("Update to %1 %2").arg(Theme::instance()->appNameGUI(), _offer.version));
        guardedAction->setVisible(_offer.isValid());
    };
    refresh();
    connect(this, &UpdateCheck::offerChanged, action, refresh);
    connect(action, &QAction::triggered, this, &UpdateCheck::openOffer);
}

QString UpdateCheck::menuText() const
{
    if (!_offer.isValid()) {
        return {};
    }
    return tr("Update to %1 %2").arg(Theme::instance()->appNameGUI(), _offer.version);
}

void UpdateCheck::openOffer() const
{
    if (_offer.isValid()) {
        QDesktopServices::openUrl(_offer.openUrl());
    }
}

} // namespace OCC::Xenia
