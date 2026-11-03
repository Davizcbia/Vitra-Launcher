// SPDX-License-Identifier: GPL-3.0-only
#include "../ModpackDrop.h"
#include <QCoreApplication>
#include <QDir>
#include <QTemporaryDir>
#include <cstdlib>
#include <iostream>
static void check(bool value,const char* message)
{
    if (!value) { std::cerr << "FAILED: " << message << '\n'; std::exit(1); }
}
int main(int argc,char** argv)
{
    QCoreApplication app(argc,argv); QTemporaryDir temp;
    check(temp.isValid(),"temporary directory");
    const QString pack=QDir(temp.path()).filePath(QString::fromUtf8("整合包 100%.MRPACK"));
    QFile file(pack); check(file.open(QIODevice::WriteOnly) && file.write("fixture")==7,"write fixture"); file.close();
    check(ModpackDrop::validate(QUrl::fromLocalFile(pack)).isEmpty(),"local Unicode mrpack and uppercase extension");
    const QString zip=QDir(temp.path()).filePath("pack.ZIP");
    check(QFile::copy(pack,zip) && ModpackDrop::validate(QUrl::fromLocalFile(zip)).isEmpty(),"local zip");
    check(!ModpackDrop::validate(QUrl("https://example.invalid/pack.zip")).isEmpty(),"reject remote URL");
    check(!ModpackDrop::validate(QUrl::fromLocalFile(temp.path()+"/missing.zip")).isEmpty(),"reject missing file");
    check(!ModpackDrop::validate(QUrl::fromLocalFile(temp.path()+"/file.jar")).isEmpty(),"reject unsupported extension");
    const QString folder=temp.path()+"/folder.zip";
    check(QDir().mkpath(folder) && !ModpackDrop::validate(QUrl::fromLocalFile(folder)).isEmpty(),"reject directory named zip");
    std::cout << "ModpackDropTest passed\n";
}
