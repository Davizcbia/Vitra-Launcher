// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QList>
#include <QPair>
#include <QStringList>

namespace SyncFiles {
// Verify the file on disk, including errors that can occur while flushing it.
inline bool verified(QFile& output, qint64 size, const QString& sha512)
{
    const bool flushed = output.flush();
    output.close();
    if (!flushed) return false;
    QFile input(output.fileName());
    if (!input.open(QIODevice::ReadOnly) || input.size() != size) return false;
    QCryptographicHash hash(QCryptographicHash::Sha512);
    return hash.addData(&input) && QString::fromLatin1(hash.result().toHex()) == sha512;
}

// Record each completed move so a later failure can undo it in reverse order.
// Keep unsuccessful rollback entries for a retry and report their locations.
class Transaction {
public:
    bool move(const QString& from, const QString& to)
    {
        if (!QFileInfo::exists(from) || QFileInfo::exists(to) ||
            !QDir().mkpath(QFileInfo(to).absolutePath()) || !QDir().rename(from, to)) {
            error = QStringLiteral("Cannot move %1 to %2").arg(from, to);
            return false;
        }
        moves.append({from, to});
        return true;
    }
    bool rollback()
    {
        QStringList failures;
        // Stop if an inverse move fails: earlier moves may depend on it.
        while (!moves.isEmpty()) {
            const auto entry = moves.last();
            if (QFileInfo::exists(entry.first) || !QDir().rename(entry.second, entry.first)) {
                failures.append(QStringLiteral("Cannot restore %1 from %2").arg(entry.first, entry.second));
                break;
            }
            moves.removeLast();
        }
        error = failures.join('\n');
        return failures.isEmpty();
    }
    void commit() { moves.clear(); }
    QString error;
private:
    QList<QPair<QString, QString>> moves;
};
}
