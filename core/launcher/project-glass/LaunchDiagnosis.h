// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStringList>

// Why a game that just stopped did not start, from the crash report and log it
// left behind. "Game crashed." alone says nothing, and in large modpacks the
// cause is usually in the mod set rather than in the launcher.
namespace LaunchDiagnosis {
enum class Kind {
    Unknown,
    // NeoForge's FMLServiceProvider reloads fml.toml while the early window's
    // render thread reads it, and the reload starts from an empty config. Only
    // timing decides it, so the next attempt normally passes.
    EarlyWindowRace,
    ModLoading,
    OutOfMemory
};
struct Result {
    Kind kind = Kind::Unknown;
    QStringList issues;      // the mod loader's own messages
    QString conflictingMod;  // id of a mod that declares itself incompatible
    QString reportPath;
};
inline QString tail(const QString& path, qint64 limit)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    if (file.size() > limit) file.seek(file.size() - limit);
    return QString::fromUtf8(file.read(limit));
}
inline Result analyze(const QString& report, const QString& log)
{
    Result result;
    if (report.contains(QStringLiteral("FMLConfig.getBoolConfigValue")) && report.contains(QStringLiteral("DisplayWindow.initRender"))) {
        result.kind = Kind::EarlyWindowRace;
        return result;
    }
    static const QRegularExpression failure(QStringLiteral("^\\s*Failure message:\\s*(.+?)\\s*$"), QRegularExpression::MultilineOption);
    static const QRegularExpression conflict(QStringLiteral("^Mod (\\S+) is incompatible with \\S+"));
    for (auto match = failure.globalMatch(report); match.hasNext();) {
        const QString issue = match.next().captured(1);
        if (result.issues.contains(issue)) continue;
        result.issues.append(issue);
        if (result.conflictingMod.isEmpty()) result.conflictingMod = conflict.match(issue).captured(1);
    }
    if (!result.issues.isEmpty())
        result.kind = Kind::ModLoading;
    else if (report.contains(QStringLiteral("java.lang.OutOfMemoryError")) || log.contains(QStringLiteral("java.lang.OutOfMemoryError")))
        result.kind = Kind::OutOfMemory;
    return result;
}
// Only files written by this launch count: an old report describes an old failure.
inline Result diagnose(const QString& gameRoot, const QDateTime& since)
{
    const QDir game(gameRoot);
    QString reportPath, log;
    const auto reports = QDir(game.filePath("crash-reports")).entryInfoList({ "*.txt" }, QDir::Files, QDir::Time);
    if (!reports.isEmpty() && reports.first().lastModified() >= since) reportPath = reports.first().filePath();
    const QFileInfo latest(game.filePath("logs/latest.log"));
    if (latest.exists() && latest.lastModified() >= since) log = tail(latest.filePath(), 1024 * 1024);
    Result result = analyze(reportPath.isEmpty() ? QString() : tail(reportPath, 4 * 1024 * 1024), log);
    result.reportPath = reportPath;
    return result;
}
}  // namespace LaunchDiagnosis
