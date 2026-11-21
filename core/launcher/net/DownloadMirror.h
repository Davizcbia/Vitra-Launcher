// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QString>
#include <QUrl>
#include <atomic>

// Download source ("DownloadMirror" setting), as offered by PCL2:
//   0 = official servers only
//   1 = prefer the mirror, fall back to the official server
//   2 = prefer the official server, fall back to the mirror
//   3 = automatic: the faster source of a speed test (DownloadSourceProbe),
//       separately for game files and mod files; until a test has finished,
//       as 2. The other source stays the fallback either way.
// Minecraft and mod loader files use BMCLAPI; Modrinth and CurseForge mod
// files use MCIM. Only GET requests to the hosts below are affected; search
// and project APIs, the Prism metadata server and accounts stay official.
// Request.cpp sends API keys by the *requested* host, so a mirrored request
// never carries the CurseForge key or a Modrinth token.
namespace Net::DownloadMirror {

enum Mode { Official = 0, PreferMirror = 1, PreferOfficial = 2, Automatic = 3 };

// Result of the last speed test for Automatic: -1 untested, 0 official
// faster, 1 mirror faster. Written by DownloadSourceProbe (main thread).
inline std::atomic<int> gameMirrorFaster{ -1 };
inline std::atomic<int> modMirrorFaster{ -1 };

// Official URL → BMCLAPI URL, or an empty QUrl when the host is not mirrored.
// See https://bmclapidoc.bangbang93.com/
inline QUrl bmclapi(const QUrl& url)
{
    static const QString mirror = QStringLiteral("https://bmclapi2.bangbang93.com");
    struct Rule {
        const char* prefix;
        const char* target;
    };
    static const Rule rules[] = {
        { "https://piston-meta.mojang.com/", "/" },
        { "https://piston-data.mojang.com/", "/" },
        { "https://launchermeta.mojang.com/", "/" },
        { "https://launcher.mojang.com/", "/" },
        { "https://resources.download.minecraft.net/", "/assets/" },
        { "https://libraries.minecraft.net/", "/maven/" },
        { "https://maven.minecraftforge.net/", "/maven/" },
        { "https://files.minecraftforge.net/maven/", "/maven/" },
        { "https://maven.neoforged.net/releases/", "/maven/" },
        { "https://maven.fabricmc.net/", "/maven/" },
        { "https://meta.fabricmc.net/", "/fabric-meta/" },
        { "https://maven.quiltmc.org/repository/release/", "/maven/" },
        { "https://meta.quiltmc.org/", "/quilt-meta/" },
    };
    QString text = url.toString(QUrl::FullyEncoded);
    if (text.startsWith(QStringLiteral("http://")))
        text.replace(0, 7, QStringLiteral("https://"));
    for (const auto& rule : rules) {
        const QString prefix = QString::fromLatin1(rule.prefix);
        if (text.startsWith(prefix))
            return QUrl(mirror + QString::fromLatin1(rule.target) + text.mid(prefix.size()), QUrl::StrictMode);
    }
    return {};
}

// Modrinth / CurseForge file CDN → MCIM, or an empty QUrl.
// See https://mod.mcimirror.top/docs
inline QUrl mcim(const QUrl& url)
{
    if (url.scheme() != QStringLiteral("https"))
        return {};
    const QString host = url.host();
    if (host != QStringLiteral("cdn.modrinth.com") && host != QStringLiteral("edge.forgecdn.net") &&
        host != QStringLiteral("mediafilez.forgecdn.net"))
        return {};
    QUrl mirrored(url);
    mirrored.setHost(QStringLiteral("mod.mcimirror.top"));
    return mirrored;
}

// The mirror for any supported official URL, or an empty QUrl.
inline QUrl mirrorFor(const QUrl& url)
{
    const QUrl game = bmclapi(url);
    return game.isEmpty() ? mcim(url) : game;
}

// Whether a request to `url` should try its mirror before the official
// server under `mode` (only meaningful when mirrorFor(url) is not empty).
inline bool mirrorFirst(int mode, const QUrl& url)
{
    if (mode == PreferMirror)
        return true;
    if (mode != Automatic)
        return false;
    const bool game = !bmclapi(url).isEmpty();
    return (game ? gameMirrorFaster : modMirrorFaster).load() == 1;
}

// Whether `mode` uses mirrors at all.
inline bool usesMirror(int mode)
{
    return mode == PreferMirror || mode == PreferOfficial || mode == Automatic;
}

}  // namespace Net::DownloadMirror
