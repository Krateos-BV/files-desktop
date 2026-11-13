/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

// XEN-341: Xenia Files update check, the same path as Xenia Talk desktop.
//
// At start and once a day it reads the public GitHub release list of
// XENIA_UPDATE_REPOSITORY. When a newer stable release exists it announces it once
// (tray notification) and adds an "Update to Xenia Files X" entry to the tray menu,
// which opens the installer for this platform in the browser. The app never
// downloads or runs anything itself; the operating system checks the signature
// when the user opens the file.
//
// This replaces nothing upstream: BUILD_UPDATER stays OFF, so there is no Sparkle,
// no update server and no silent MSI install. A build without a release version
// (XENIA_RELEASE_VERSION, from xenia-release-version.txt) never checks.

#include "xeniaupdatelogic.h"

#include <QObject>
#include <QPointer>
#include <QTimer>

class QMenu;
class QNetworkAccessManager;

namespace OCC::Xenia
{

class UpdateCheck : public QObject
{
    Q_OBJECT

public:
    static UpdateCheck *instance();

    /// Whether this build checks at all (it has a release version and a repository).
    [[nodiscard]] static bool isEnabled();

    /// Start the first check shortly after launch and the daily timer. No-op when disabled.
    void start();

    [[nodiscard]] UpdateOffer offer() const
    {
        return _offer;
    }

    /// Add the "Update to ..." action to a tray menu. It is hidden while there is no
    /// offer and follows later offers on its own, so menus built once still update.
    void addMenuAction(QMenu *menu);

    /// For trays that are rebuilt each time they open (the native macOS popup):
    /// the entry's text, and the action behind it. menuText() is empty while there
    /// is no offer, so the caller adds no row.
    [[nodiscard]] QString menuText() const;
    void openOffer() const;

Q_SIGNALS:
    /// Emitted once per new version, for the tray notification.
    void updateAnnouncement(const QString &title, const QString &message, const QUrl &url);
    void offerChanged();

private:
    explicit UpdateCheck(QObject *parent = nullptr);
    void checkNow();
    void announceOnce();

    QNetworkAccessManager *_network = nullptr;
    QTimer _dailyTimer;
    UpdateOffer _offer;
    bool _started = false;
};

} // namespace OCC::Xenia
