// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QString>
#include <QUrl>

// Instance card backgrounds live in the instance folder (<instance>/.vitra/),
// so they survive moving the original picture and can go along when the
// instance is shared (InstanceSync). Only real images of a common format and
// a bounded size are accepted: the bytes are decoded, not just the name read.
namespace InstanceBackground {

inline constexpr qint64 MaxBytes = 16 * 1024 * 1024;
inline constexpr int MaxSide = 8192;

inline QString folder(const QString& instanceRoot)
{
    return QDir(instanceRoot).filePath(QStringLiteral(".vitra"));
}

// The file's real image type ("png", "jpg", "webp", "bmp"), or empty when it
// is not an acceptable picture.
inline QString imageType(const QString& path)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.size() <= 0 || info.size() > MaxBytes) return {};
    QImageReader reader(path);
    reader.setDecideFormatFromContent(true);
    const QByteArray format = reader.format().toLower();
    static const QList<QByteArray> allowed{ "png", "jpeg", "jpg", "webp", "bmp" };
    if (!allowed.contains(format)) return {};
    const QSize size = reader.size();
    if (!size.isValid() || size.width() > MaxSide || size.height() > MaxSide) return {};
    return format == "jpeg" ? QStringLiteral("jpg") : QString::fromLatin1(format);
}

inline bool allowedExtension(const QString& extension)
{
    static const QStringList allowed{ "png", "jpg", "webp", "bmp" };
    return allowed.contains(extension);
}

inline QString sha512(const QString& path)
{
    QFile file(path);
    QCryptographicHash hash(QCryptographicHash::Sha512);
    if (!file.open(QIODevice::ReadOnly) || !hash.addData(&file)) return {};
    return QString::fromLatin1(hash.result().toHex());
}

// Copies `source` into the instance as background-<time>.<type> (a new name,
// so image caches show the new picture) and removes older backgrounds.
// Returns the copy's file URL, or empty when the picture is not acceptable.
inline QString store(const QString& instanceRoot, const QString& source)
{
    const QString type = imageType(source);
    if (type.isEmpty()) return {};
    QDir dir(folder(instanceRoot));
    if (!dir.mkpath(QStringLiteral("."))) return {};
    const QString name = QStringLiteral("background-%1.%2").arg(QDateTime::currentMSecsSinceEpoch()).arg(type);
    const QString target = dir.filePath(name);
    if (QFileInfo(source).absoluteFilePath() != QFileInfo(target).absoluteFilePath() && !QFile::copy(source, target)) return {};
    for (const auto& old : dir.entryInfoList({ QStringLiteral("background-*") }, QDir::Files))
        if (old.fileName() != name) QFile::remove(old.filePath());
    return QUrl::fromLocalFile(target).toString();
}

// Deletes the stored backgrounds of an instance (Remove background).
inline void remove(const QString& instanceRoot)
{
    QDir dir(folder(instanceRoot));
    for (const auto& file : dir.entryInfoList({ QStringLiteral("background-*") }, QDir::Files)) QFile::remove(file.filePath());
}

}  // namespace InstanceBackground
