// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include "PgTranslate.h"

namespace ModpackDrop {
inline QString validate(const QUrl& url)
{
    if (!url.isLocalFile()) return pgTr("Drop a local modpack file.");
    const QFileInfo file(url.toLocalFile());
    const QString suffix=file.suffix().toLower();
    if (suffix!="zip" && suffix!="mrpack") return pgTr("Drop a .mrpack or .zip modpack file.");
    if (!file.isFile()) return pgTr("The modpack file does not exist or is not a regular file.");
    QFile input(file.filePath());
    if (!input.open(QIODevice::ReadOnly)) return pgTr("Cannot read the modpack file.");
    return {};
}
}
