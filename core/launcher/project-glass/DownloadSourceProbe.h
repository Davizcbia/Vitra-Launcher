// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QElapsedTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>
#include <algorithm>
#include <functional>
#include <iterator>
#include <memory>
#include "BuildConfig.h"
#include "net/DownloadMirror.h"

// Download source speed test (Settings › Downloads › Test speed, and the
// "Automatic" source at startup). Downloads the first 4 MB of one real file
// from each official server and its mirror, at most 8 s each, in parallel,
// and records the faster source for game files and for mod files in
// Net::DownloadMirror. Speeds are bytes per second; 0 = unreachable.
namespace DownloadSourceProbe {

struct Target {
    const char* key;
    const char* url;
};
// Same file on both sides (checked against the mirrors' path rules).
inline const Target targets[] = {
    { "gameOfficial", "https://libraries.minecraft.net/com/ibm/icu/icu4j/73.2/icu4j-73.2.jar" },
    { "gameMirror", "https://bmclapi2.bangbang93.com/maven/com/ibm/icu/icu4j/73.2/icu4j-73.2.jar" },
    { "modOfficial", "https://cdn.modrinth.com/data/P7dR8mSH/versions/rvI2dfzR/fabric-api-0.92.12%2B1.20.1.jar" },
    { "modMirror", "https://mod.mcimirror.top/data/P7dR8mSH/versions/rvI2dfzR/fabric-api-0.92.12%2B1.20.1.jar" },
};
inline constexpr qint64 sampleBytes = 4 * 1024 * 1024;
inline constexpr int sampleMs = 8000;

inline void run(QNetworkAccessManager* network, QObject* context, std::function<void(const QVariantMap&)> done)
{
    struct State {
        QVariantMap speeds;
        int pending = 0;
        std::function<void(const QVariantMap&)> done;
    };
    auto state = std::make_shared<State>();
    state->done = std::move(done);
    state->pending = int(std::size(targets));

    auto finish = [state] {
        if (--state->pending > 0)
            return;
        const auto faster = [&](const char* official, const char* mirror) {
            const double o = state->speeds.value(official).toDouble(), m = state->speeds.value(mirror).toDouble();
            return o <= 0 && m <= 0 ? -1 : m > o ? 1 : 0;
        };
        Net::DownloadMirror::gameMirrorFaster = faster("gameOfficial", "gameMirror");
        Net::DownloadMirror::modMirrorFaster = faster("modOfficial", "modMirror");
        if (state->done)
            state->done(state->speeds);
    };

    for (const auto& target : targets) {
        QNetworkRequest request{ QUrl(QString::fromLatin1(target.url)) };
        request.setHeader(QNetworkRequest::UserAgentHeader, BuildConfig.USER_AGENT);
        request.setRawHeader("Range", QByteArray("bytes=0-") + QByteArray::number(sampleBytes - 1));
        request.setRawHeader("Cache-Control", "no-cache");
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
        request.setTransferTimeout(sampleMs);
        QNetworkReply* reply = network->get(request);
        auto clock = std::make_shared<QElapsedTimer>();
        auto received = std::make_shared<qint64>(0);
        auto settled = std::make_shared<bool>(false);
        clock->start();
        const QString key = QString::fromLatin1(target.key);
        auto settle = [state, reply, clock, received, settled, key, finish](bool reachable) {
            if (*settled)
                return;
            *settled = true;
            const double seconds = std::max<qint64>(clock->elapsed(), 1) / 1000.0;
            state->speeds.insert(key, reachable && *received > 0 ? *received / seconds : 0.0);
            reply->deleteLater();
            finish();
        };
        QObject::connect(reply, &QIODevice::readyRead, context, [reply, received, settle] {
            *received += reply->readAll().size();
            if (*received >= sampleBytes) {
                settle(true);
                reply->abort();
            }
        });
        QObject::connect(reply, &QNetworkReply::finished, context, [reply, settle] {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            settle(reply->error() == QNetworkReply::NoError && (status == 200 || status == 206));
        });
        // A slow source still yields a speed: what arrived within the window.
        QTimer::singleShot(sampleMs, context, [reply = QPointer<QNetworkReply>(reply), settle] {
            if (!reply)
                return;
            settle(true);
            reply->abort();
        });
    }
}

}  // namespace DownloadSourceProbe
