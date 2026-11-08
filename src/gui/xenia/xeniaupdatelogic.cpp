/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "xeniaupdatelogic.h"

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>
#include <QSysInfo>

#include <algorithm>

namespace OCC::Xenia
{

namespace
{

QString bareTag(const QString &tag)
{
    return tag.startsWith(QLatin1Char('v')) ? tag.mid(1) : tag;
}

struct AssetRule {
    QString token; // "-<os>-<arch>"
    QStringList extensions; // in order of preference
};

AssetRule assetRule(UpdatePlatform platform)
{
    switch (platform) {
    case UpdatePlatform::MacArm64:
        return {QStringLiteral("-macos-arm64"), {QStringLiteral(".dmg"), QStringLiteral(".zip")}};
    case UpdatePlatform::WindowsX64:
        // Only an installer. A zip of the build output is not something to hand a user,
        // so without an .msi the release page is offered instead.
        return {QStringLiteral("-windows-x64"), {QStringLiteral(".msi")}};
    case UpdatePlatform::LinuxX64:
        return {QStringLiteral("-linux-x86_64"), {QStringLiteral(".AppImage")}};
    case UpdatePlatform::Other:
        break;
    }
    return {};
}

} // namespace

bool isCalVerTag(const QString &tag)
{
    // The same shape xenia-release.yml accepts for a release tag (vYY.M.D or vYY.M.D.N,
    // years 26 to 29). Upstream tags that reach the fork, such as v34.0.3, never match.
    static const QRegularExpression pattern(QStringLiteral("^2[6-9]\\.([1-9]|1[0-2])\\.([1-9]|[12][0-9]|3[01])(\\.\\d+)?$"));
    return pattern.match(bareTag(tag)).hasMatch();
}

int compareCalVer(const QString &a, const QString &b)
{
    const auto partsA = bareTag(a).split(QLatin1Char('.'));
    const auto partsB = bareTag(b).split(QLatin1Char('.'));
    for (int i = 0; i < 4; ++i) {
        const auto valueA = i < partsA.size() ? partsA.at(i).toLongLong() : 0;
        const auto valueB = i < partsB.size() ? partsB.at(i).toLongLong() : 0;
        if (valueA != valueB) {
            return valueA < valueB ? -1 : 1;
        }
    }
    return 0;
}

UpdatePlatform currentUpdatePlatform()
{
    const auto arch = QSysInfo::buildCpuArchitecture();
#if defined(Q_OS_MACOS)
    return arch == QLatin1String("arm64") ? UpdatePlatform::MacArm64 : UpdatePlatform::Other;
#elif defined(Q_OS_WIN)
    return arch == QLatin1String("x86_64") ? UpdatePlatform::WindowsX64 : UpdatePlatform::Other;
#elif defined(Q_OS_LINUX)
    return arch == QLatin1String("x86_64") ? UpdatePlatform::LinuxX64 : UpdatePlatform::Other;
#else
    Q_UNUSED(arch)
    return UpdatePlatform::Other;
#endif
}

QUrl matchAsset(const QJsonArray &assets, UpdatePlatform platform)
{
    const auto rule = assetRule(platform);
    if (rule.token.isEmpty()) {
        return {};
    }

    for (const auto &extension : rule.extensions) {
        for (const auto &assetValue : assets) {
            const auto asset = assetValue.toObject();
            const auto name = asset.value(QStringLiteral("name")).toString();
            if (name.startsWith(QStringLiteral("Xenia-Files-v")) && name.contains(rule.token) && name.endsWith(extension)) {
                const QUrl url(asset.value(QStringLiteral("browser_download_url")).toString());
                if (url.isValid() && url.scheme() == QLatin1String("https")) {
                    return url;
                }
            }
        }
    }
    return {};
}

UpdateOffer pickUpdate(const QByteArray &json, const QString &currentVersion, UpdatePlatform platform, QString *note)
{
    const auto setNote = [note](const QString &text) {
        if (note) {
            *note = text;
        }
    };

    if (!isCalVerTag(currentVersion)) {
        setNote(QStringLiteral("this build has no CalVer release version (%1)").arg(currentVersion));
        return {};
    }

    QJsonParseError parseError{};
    const auto document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
        setNote(QStringLiteral("the releases response is not a JSON array"));
        return {};
    }

    QList<QJsonObject> candidates;
    bool sawPrerelease = false;
    for (const auto &value : document.array()) {
        const auto release = value.toObject();
        // A draft is not public yet, and a tag that is not CalVer (an upstream tag
        // that reached the fork, or something like "latest") is never a Xenia release.
        if (release.value(QStringLiteral("draft")).toBool() || !isCalVerTag(release.value(QStringLiteral("tag_name")).toString())) {
            continue;
        }
        // Stable channel only. Marking a release as prerelease is how a release is held back.
        if (release.value(QStringLiteral("prerelease")).toBool()) {
            sawPrerelease = true;
            continue;
        }
        candidates.append(release);
    }

    if (candidates.isEmpty()) {
        // Without this, "only prereleases" looks exactly like "already up to date" (XEN-226 on Talk).
        setNote(sawPrerelease ? QStringLiteral("only prereleases found, so there is no stable release") : QStringLiteral("no usable release found"));
        return {};
    }

    const auto newest = *std::max_element(candidates.cbegin(), candidates.cend(), [](const QJsonObject &a, const QJsonObject &b) {
        return compareCalVer(a.value(QStringLiteral("tag_name")).toString(), b.value(QStringLiteral("tag_name")).toString()) < 0;
    });

    const auto newestTag = newest.value(QStringLiteral("tag_name")).toString();
    if (compareCalVer(newestTag, currentVersion) <= 0) {
        return {};
    }

    UpdateOffer offer;
    offer.version = bareTag(newestTag);
    offer.releaseUrl = QUrl(newest.value(QStringLiteral("html_url")).toString());
    offer.downloadUrl = matchAsset(newest.value(QStringLiteral("assets")).toArray(), platform);
    if (!offer.downloadUrl.isValid()) {
        setNote(QStringLiteral("release %1 has no asset for this platform, offering the release page").arg(newestTag));
    }
    return offer;
}

} // namespace OCC::Xenia
