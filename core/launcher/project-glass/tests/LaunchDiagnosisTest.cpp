// SPDX-License-Identifier: GPL-3.0-only
// Standalone Qt Core test of the crash report reader, on the text NeoForge writes.
#include "../LaunchDiagnosis.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QThread>
#include <cstdlib>
#include <iostream>
static void check(bool condition,const char *label) {
    if(condition)return;
    std::cerr<<"FAILED: "<<label<<"\n";std::exit(1);
}
static void write(const QString &path,const QByteArray &bytes) {
    QDir().mkpath(QFileInfo(path).absolutePath());QFile file(path);
    check(file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size(),"write fixture");
}
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    using namespace LaunchDiagnosis;
    const QString race=QStringLiteral("Caused by: java.lang.NullPointerException: Cannot invoke \"java.lang.Boolean.booleanValue()\"\n"
        "\tat MC-BOOTSTRAP/fml_loader@4.0.44/net.neoforged.fml.loading.FMLConfig.getBoolConfigValue(FMLConfig.java:215)\n"
        "\tat MC-BOOTSTRAP/fml_earlydisplay@4.0.44/net.neoforged.fml.earlydisplay.DisplayWindow.initRender(DisplayWindow.java:238)\n");
    check(analyze(race,{}).kind==Kind::EarlyWindowRace,"early window race");

    const QString conflict=QStringLiteral("Description: Mod loading failures have occurred\n\n"
        "-- MOD citresewn --\nDetails:\n\tMod File: citresewn.jar\n\tFailure message: Mod citresewn is incompatible with connector any\r\n"
        "\tMod Version: 0\n-- MOD other --\n\tFailure message: Mod citresewn is incompatible with connector any\n");
    const auto mods=analyze(conflict,{});
    check(mods.kind==Kind::ModLoading,"mod loading failure");
    check(mods.issues==QStringList{"Mod citresewn is incompatible with connector any"},"issues are collected once");
    check(mods.conflictingMod=="citresewn","conflicting mod id");

    const auto missing=analyze(QStringLiteral("\tFailure message: Mod create requires flywheel 1.0 or above\n"),{});
    check(missing.kind==Kind::ModLoading && missing.conflictingMod.isEmpty(),"other failures name no mod to disable");

    check(analyze({},QStringLiteral("java.lang.OutOfMemoryError: Java heap space")).kind==Kind::OutOfMemory,"out of memory in the log");
    check(analyze(QStringLiteral("java.lang.IllegalStateException: boom"),{}).kind==Kind::Unknown,"unknown crash");

    QTemporaryDir game;check(game.isValid(),"temporary folder");
    const QString report=QDir(game.path()).filePath("crash-reports/crash-1.txt");
    write(report,conflict.toUtf8());
    QThread::msleep(20);
    check(diagnose(game.path(),QDateTime::currentDateTime().addSecs(60)).kind==Kind::Unknown,"a report from before the launch is ignored");
    const auto fresh=diagnose(game.path(),QDateTime::currentDateTime().addSecs(-60));
    check(fresh.kind==Kind::ModLoading && QFileInfo(fresh.reportPath)==QFileInfo(report),"a report from this launch is read");
    std::cout<<"LaunchDiagnosisTest passed\n";
    return 0;
}
