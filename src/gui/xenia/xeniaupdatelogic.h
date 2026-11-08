/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

// XEN-341: the pure part of the Xenia Files update check. It only needs QtCore,
// so the unit test can exercise it without the rest of the client.
//
// The rules follow Krateos-BV/talk-desktop's src/app/githubRelease.service.ts,
// so both desktop clients treat the same GitHub release list the same way.

#include <QJsonArray>
#include <QString>
#include <QUrl>

class QByteArray;

namespace OCC::Xenia
{

enum class UpdatePlatform {
    MacArm64,
    WindowsX64,
    LinuxX64,
    Other, // no asset is built for it, so the release page is offered instead
};

struct UpdateOffer {
    QString version; // the release tag without the leading "v", e.g. "26.11.6"
    QUrl downloadUrl; // empty when no asset matches this platform
    QUrl releaseUrl; // the release page on GitHub

    [[nodiscard]] bool isValid() const
    {
        return !version.isEmpty();
    }
    [[nodiscard]] QUrl openUrl() const
    {
        return downloadUrl.isValid() ? downloadUrl : releaseUrl;
    }
};

/// "26.11.6", "v26.11.6.1": the CalVer shape of a Xenia release tag, optional "v".
[[nodiscard]] bool isCalVerTag(const QString &tag);

/// Negative when a is older than b, 0 when equal, positive when newer.
/// Both must pass isCalVerTag(); a missing fourth part counts as 0.
[[nodiscard]] int compareCalVer(const QString &a, const QString &b);

/// The platform of this build, from QSysInfo.
[[nodiscard]] UpdatePlatform currentUpdatePlatform();

/// The release asset for a platform: "Xenia-Files-v<tag>-<os>-<arch>...<ext>",
/// picking the first extension in the platform's preference list. Empty when none.
[[nodiscard]] QUrl matchAsset(const QJsonArray &assets, UpdatePlatform platform);

/// Pick the newest published, non-prerelease CalVer release from a GitHub
/// "list releases" JSON body and return it if it is newer than currentVersion.
/// Returns an invalid offer when there is nothing newer; a reason is written to
/// *note when the answer is "nothing" for a reason worth logging.
[[nodiscard]] UpdateOffer pickUpdate(const QByteArray &json, const QString &currentVersion, UpdatePlatform platform, QString *note = nullptr);

} // namespace OCC::Xenia
