/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

// XEN-341: tests for the Xenia Files update check rules (gui/xenia/xeniaupdatelogic).

#include <QtTest>

#include "xenia/xeniaupdatelogic.h"

using namespace OCC::Xenia;

namespace
{

QByteArray release(const QString &tag, bool prerelease = false, bool draft = false, const QStringList &assetNames = {})
{
    QJsonArray assets;
    for (const auto &name : assetNames) {
        assets.append(QJsonObject{
            {QStringLiteral("name"), name},
            {QStringLiteral("browser_download_url"), QStringLiteral("https://github.com/Krateos-BV/files-desktop/releases/download/%1/%2").arg(tag, name)},
        });
    }
    const QJsonObject object{
        {QStringLiteral("tag_name"), tag},
        {QStringLiteral("prerelease"), prerelease},
        {QStringLiteral("draft"), draft},
        {QStringLiteral("html_url"), QStringLiteral("https://github.com/Krateos-BV/files-desktop/releases/tag/%1").arg(tag)},
        {QStringLiteral("assets"), assets},
    };
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QByteArray list(const QList<QByteArray> &releases)
{
    QByteArray body = "[";
    for (qsizetype i = 0; i < releases.size(); ++i) {
        if (i > 0) {
            body += ',';
        }
        body += releases.at(i);
    }
    body += ']';
    return body;
}

QStringList allAssets(const QString &tag)
{
    return {
        QStringLiteral("Xenia-Files-%1-linux-x86_64-unsigned.AppImage").arg(tag),
        QStringLiteral("Xenia-Files-%1-windows-x64-unsigned.zip").arg(tag),
        QStringLiteral("Xenia-Files-%1-windows-x64-unsigned.msi").arg(tag),
        QStringLiteral("Xenia-Files-%1-macos-arm64-signed.zip").arg(tag),
        QStringLiteral("SHA256SUMS"),
    };
}

} // namespace

class TestXeniaUpdateCheck : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void testCalVerTags()
    {
        QVERIFY(isCalVerTag(QStringLiteral("26.11.6")));
        QVERIFY(isCalVerTag(QStringLiteral("v26.11.6")));
        QVERIFY(isCalVerTag(QStringLiteral("v26.11.6.1")));
        QVERIFY(!isCalVerTag(QStringLiteral("v33.0.0-rc4")));
        QVERIFY(!isCalVerTag(QStringLiteral("latest")));
        QVERIFY(!isCalVerTag(QStringLiteral("26.11")));
        QVERIFY(!isCalVerTag(QStringLiteral("v34.0.3"))); // an upstream tag
        QVERIFY(!isCalVerTag(QStringLiteral("26.13.1")));
        QVERIFY(!isCalVerTag(QString()));
    }

    void testCompareCalVer()
    {
        QVERIFY(compareCalVer(QStringLiteral("26.11.4"), QStringLiteral("26.11.4.1")) < 0);
        QVERIFY(compareCalVer(QStringLiteral("v26.11.4.1"), QStringLiteral("26.11.10")) < 0);
        QVERIFY(compareCalVer(QStringLiteral("26.12.1"), QStringLiteral("26.11.30")) > 0);
        QVERIFY(compareCalVer(QStringLiteral("27.1.1"), QStringLiteral("26.12.31.9")) > 0);
        QCOMPARE(compareCalVer(QStringLiteral("v26.11.6"), QStringLiteral("26.11.6.0")), 0);
    }

    void testNewerStableReleaseIsOffered()
    {
        const auto body = list({release(QStringLiteral("v26.11.6"), false, false, allAssets(QStringLiteral("v26.11.6"))),
                                release(QStringLiteral("v26.11.20"), false, false, allAssets(QStringLiteral("v26.11.20")))});
        const auto offer = pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64);
        QVERIFY(offer.isValid());
        QCOMPARE(offer.version, QStringLiteral("26.11.20"));
        QVERIFY(offer.downloadUrl.toString().endsWith(QStringLiteral("Xenia-Files-v26.11.20-linux-x86_64-unsigned.AppImage")));
        QCOMPARE(offer.openUrl(), offer.downloadUrl);
    }

    void testAssetPerPlatform()
    {
        const auto body = list({release(QStringLiteral("v26.12.1"), false, false, allAssets(QStringLiteral("v26.12.1")))});
        QVERIFY(pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::WindowsX64)
                    .downloadUrl.toString()
                    .endsWith(QStringLiteral("-windows-x64-unsigned.msi")));
        QVERIFY(
            pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::MacArm64).downloadUrl.toString().endsWith(QStringLiteral("-macos-arm64-signed.zip")));

        // A .dmg is preferred over the zipped .app when both exist.
        auto withDmg = allAssets(QStringLiteral("v26.12.1"));
        withDmg.append(QStringLiteral("Xenia-Files-v26.12.1-macos-arm64-signed.dmg"));
        const auto dmgBody = list({release(QStringLiteral("v26.12.1"), false, false, withDmg)});
        QVERIFY(pickUpdate(dmgBody, QStringLiteral("26.11.6"), UpdatePlatform::MacArm64).downloadUrl.toString().endsWith(QStringLiteral(".dmg")));
    }

    void testNoMatchingAssetFallsBackToReleasePage()
    {
        // Windows with only the zip of the build output: offer the release page.
        const auto body = list({release(QStringLiteral("v26.12.1"), false, false, {QStringLiteral("Xenia-Files-v26.12.1-windows-x64-unsigned.zip")})});
        QString note;
        const auto offer = pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::WindowsX64, &note);
        QVERIFY(offer.isValid());
        QVERIFY(!offer.downloadUrl.isValid());
        QCOMPARE(offer.openUrl(), QUrl(QStringLiteral("https://github.com/Krateos-BV/files-desktop/releases/tag/v26.12.1")));
        QVERIFY(!note.isEmpty());

        // A platform nothing is built for (Intel Mac) gets the release page too.
        QVERIFY(!pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::Other).downloadUrl.isValid());
    }

    void testSameOrOlderIsNotOffered()
    {
        const auto body = list({release(QStringLiteral("v26.11.6"), false, false, allAssets(QStringLiteral("v26.11.6")))});
        QVERIFY(!pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64).isValid());
        QVERIFY(!pickUpdate(body, QStringLiteral("26.11.6.1"), UpdatePlatform::LinuxX64).isValid());
    }

    void testDraftsPrereleasesAndUpstreamTagsAreSkipped()
    {
        const auto body = list({release(QStringLiteral("v26.11.6")),
                                release(QStringLiteral("v26.12.1"), true),
                                release(QStringLiteral("v26.12.2"), false, true),
                                release(QStringLiteral("v34.0.3")),
                                release(QStringLiteral("v33.0.0-rc4")),
                                release(QStringLiteral("latest"))});
        QVERIFY(!pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64).isValid());
    }

    void testOnlyPrereleasesIsReported()
    {
        QString note;
        const auto body = list({release(QStringLiteral("v26.12.1"), true)});
        QVERIFY(!pickUpdate(body, QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64, &note).isValid());
        QVERIFY(note.contains(QStringLiteral("prerelease")));
    }

    void testBadInput()
    {
        QString note;
        QVERIFY(
            !pickUpdate(QByteArrayLiteral("{\"message\":\"API rate limit exceeded\"}"), QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64, &note).isValid());
        QVERIFY(!note.isEmpty());
        QVERIFY(!pickUpdate(QByteArrayLiteral("not json"), QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64).isValid());
        QVERIFY(!pickUpdate(QByteArrayLiteral("[]"), QStringLiteral("26.11.6"), UpdatePlatform::LinuxX64).isValid());
        // A build without a release version never offers anything.
        const auto body = list({release(QStringLiteral("v26.12.1"))});
        QVERIFY(!pickUpdate(body, QString(), UpdatePlatform::LinuxX64).isValid());
        QVERIFY(!pickUpdate(body, QStringLiteral("35.0.50 alpha"), UpdatePlatform::LinuxX64).isValid());
    }

    void testNonHttpsAssetIsIgnored()
    {
        QJsonArray assets{QJsonObject{
            {QStringLiteral("name"), QStringLiteral("Xenia-Files-v26.12.1-linux-x86_64-unsigned.AppImage")},
            {QStringLiteral("browser_download_url"), QStringLiteral("http://example.com/x.AppImage")},
        }};
        QVERIFY(!matchAsset(assets, UpdatePlatform::LinuxX64).isValid());
    }
};

QTEST_GUILESS_MAIN(TestXeniaUpdateCheck)
#include "testxeniaupdatecheck.moc"
