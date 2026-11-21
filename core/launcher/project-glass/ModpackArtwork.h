// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QThread>
#include <QUrl>
#include <functional>
#include <memory>
#include "BuildConfig.h"
#include "InstanceBackground.h"
#include "modplatform/helpers/HashUtils.h"

// A modpack's project icon as the new instance's card picture.
//  - From the download page the icon address is known (search results).
//  - A local .mrpack / .zip carries no icon: its file is looked up by hash on
//    Modrinth (SHA-512) and then CurseForge (fingerprint); a pack that is not
//    published on either keeps the default artwork.
// Icons come only from the two sites' image hosts and are decoded and size
// checked (InstanceBackground) before use.
namespace ModpackArtwork {

inline bool allowedIcon(const QUrl& url)
{
    static const QStringList hosts{ "cdn.modrinth.com", "media.forgecdn.net", "mediafilez.forgecdn.net", "edge.forgecdn.net" };
    return url.isValid() && url.scheme() == "https" && hosts.contains(url.host().toLower());
}

inline QNetworkRequest request(const QUrl& url)
{
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, BuildConfig.USER_AGENT);
    request.setTransferTimeout(20000);
    return request;
}

// Downloads `icon` and stores it as the card picture of the instance at
// `instanceRoot`. done(file URL) on success, done("") otherwise.
inline void store(QNetworkAccessManager* network, QObject* context, const QUrl& icon, const QString& instanceRoot,
                  std::function<void(const QString&)> done)
{
    if (!allowedIcon(icon) || instanceRoot.isEmpty()) return done({});
    QNetworkReply* reply = network->get(request(icon));
    QObject::connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64) {
        if (received > InstanceBackground::MaxBytes) reply->abort();
    });
    QObject::connect(reply, &QNetworkReply::finished, context, [reply, instanceRoot, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) return done({});
        QTemporaryDir temp;
        if (!temp.isValid()) return done({});
        QFile file(temp.filePath(QStringLiteral("icon")));
        const QByteArray bytes = reply->readAll();
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()) return done({});
        file.close();
        done(InstanceBackground::store(instanceRoot, file.fileName()));
    });
}

// The project icon of a local modpack file, found by its hash; done("") when
// neither site knows the file.
inline void lookUp(QNetworkAccessManager* network, QObject* context, const QString& path, const QString& curseForgeKey,
                   std::function<void(const QUrl&)> done)
{
    struct Hashes {
        QString sha512;
        qint64 fingerprint = -1;
    };
    auto result = std::make_shared<Hashes>();
    auto* thread = QThread::create([path, result] {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly)) result->sha512 = Hashing::hash(&file, Hashing::Algorithm::Sha512);
        QFile again(path);
        if (again.open(QIODevice::ReadOnly)) result->fingerprint = Hashing::hash(&again, Hashing::Algorithm::Murmur2).toLongLong();
    });
    QObject::connect(thread, &QThread::finished, context, [network, context, result, curseForgeKey, done, thread] {
        thread->deleteLater();
        auto tryCurseForge = [network, context, result, curseForgeKey, done] {
            if (curseForgeKey.isEmpty() || result->fingerprint < 0) return done({});
            QNetworkRequest post = request(QUrl(BuildConfig.FLAME_BASE_URL + QStringLiteral("/fingerprints/432")));
            post.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
            post.setRawHeader("x-api-key", curseForgeKey.toUtf8());
            QNetworkReply* reply = network->post(post, QJsonDocument(QJsonObject{ { "fingerprints", QJsonArray{ result->fingerprint } } }).toJson(QJsonDocument::Compact));
            QObject::connect(reply, &QNetworkReply::finished, context, [network, context, reply, curseForgeKey, done] {
                reply->deleteLater();
                const auto matches = QJsonDocument::fromJson(reply->readAll()).object().value("data").toObject().value("exactMatches").toArray();
                const qint64 modId = matches.isEmpty() ? 0 : matches.first().toObject().value("file").toObject().value("modId").toInteger();
                if (modId <= 0) return done({});
                QNetworkRequest get = request(QUrl(BuildConfig.FLAME_BASE_URL + QStringLiteral("/mods/%1").arg(modId)));
                get.setRawHeader("x-api-key", curseForgeKey.toUtf8());
                QNetworkReply* mod = network->get(get);
                QObject::connect(mod, &QNetworkReply::finished, context, [mod, done] {
                    mod->deleteLater();
                    const auto logo = QJsonDocument::fromJson(mod->readAll()).object().value("data").toObject().value("logo").toObject();
                    done(QUrl(logo.value("thumbnailUrl").toString(logo.value("url").toString())));
                });
            });
        };
        if (result->sha512.isEmpty()) return tryCurseForge();
        QNetworkReply* version = network->get(request(QUrl(QStringLiteral("https://api.modrinth.com/v2/version_file/%1?algorithm=sha512").arg(result->sha512))));
        QObject::connect(version, &QNetworkReply::finished, context, [network, context, version, done, tryCurseForge] {
            version->deleteLater();
            const QString project = QJsonDocument::fromJson(version->readAll()).object().value("project_id").toString();
            static const QRegularExpression id(QStringLiteral("^[A-Za-z0-9]{1,32}$"));
            if (!id.match(project).hasMatch()) return tryCurseForge();
            QNetworkReply* info = network->get(request(QUrl(QStringLiteral("https://api.modrinth.com/v2/project/%1").arg(project))));
            QObject::connect(info, &QNetworkReply::finished, context, [info, done, tryCurseForge] {
                info->deleteLater();
                const QUrl icon(QJsonDocument::fromJson(info->readAll()).object().value("icon_url").toString());
                if (icon.isEmpty()) return tryCurseForge();
                done(icon);
            });
        });
    });
    thread->start();
}

}  // namespace ModpackArtwork
