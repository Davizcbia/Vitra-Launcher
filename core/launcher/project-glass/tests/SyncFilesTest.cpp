// SPDX-License-Identifier: GPL-3.0-only
#include "../SyncFiles.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <cstdlib>
#include <iostream>

static void check(bool value, const char* label)
{
    if (!value) { std::cerr << "FAILED: " << label << '\n'; std::exit(1); }
}
static void write(const QString& path, const QByteArray& bytes)
{
    check(QDir().mkpath(QFileInfo(path).absolutePath()), "create fixture folder");
    QFile file(path);
    check(file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size(), "write fixture");
}
static QByteArray read(const QString& path)
{
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), "read fixture");
    return file.readAll();
}
int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir temporary;
    check(temporary.isValid(), "temporary folder");
    const QString root = temporary.path();
    const QString old = root + "/mods/a.jar", backup = root + "/backup/a.jar", incoming = root + "/tmp/new";
    write(old, "original"); write(incoming, "replacement");
    {
        SyncFiles::Transaction transaction;
        check(transaction.move(old, backup), "back up original");
        check(transaction.move(incoming, old), "install replacement");
        write(root + "/mods/conflict.jar", "existing");
        check(!transaction.move(root + "/missing", root + "/mods/conflict.jar"), "reject failing later operation");
        check(transaction.rollback(), "roll back completed moves");
        check(read(old) == "original" && read(incoming) == "replacement", "restore original and staged content");
    }
    {
        SyncFiles::Transaction transaction;
        write(backup, "existing backup");
        check(!transaction.move(old, backup), "never overwrite a backup");
        check(read(old) == "original" && read(backup) == "existing backup", "collision preserves both files");
        check(QFile::remove(backup), "clear collision fixture");
        check(transaction.move(old, backup), "back up for rollback conflict");
        write(old, "external change");
        check(!transaction.rollback() && !transaction.error.isEmpty(), "report rollback obstruction");
        check(read(backup) == "original", "retain recoverable original");
        check(QFile::remove(old) && transaction.rollback(), "retry rollback after obstruction clears");
    }
    {
        SyncFiles::Transaction transaction;
        check(transaction.move(old, backup) && transaction.move(incoming, old), "successful replacement");
        transaction.commit();
        check(transaction.rollback() && read(old) == "replacement" && read(backup) == "original", "commit keeps new file and backup");
    }
    const QByteArray bytes("verified content");
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha512).toHex());
    QFile output(root + "/download");
    check(output.open(QIODevice::WriteOnly) && output.write(bytes) == bytes.size(), "write download");
    check(SyncFiles::verified(output, bytes.size(), hash), "verify flushed file on disk");
    check(output.open(QIODevice::WriteOnly) && output.write(bytes.left(3)) == 3, "write truncated download");
    check(!SyncFiles::verified(output, bytes.size(), hash), "reject truncated disk file");
    check(output.open(QIODevice::WriteOnly) && output.write(QByteArray(bytes.size(), 'x')) == bytes.size(), "write corrupt download");
    check(!SyncFiles::verified(output, bytes.size(), hash), "reject equal-size corrupt disk file");
    std::cout << "SyncFilesTest passed\n";
}
