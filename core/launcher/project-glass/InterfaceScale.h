// SPDX-License-Identifier: GPL-3.0-only
#pragma once
// Settings › General › Interface size: Qt's global scale factor. It must be
// set before the application object exists, so it lives in its own small
// settings file (read in main.cpp) and takes effect after a restart.
#include <QByteArray>
#include <QCoreApplication>
#include <QProcess>
#include <QSettings>
#include <QStringList>
#include <QtGlobal>
#include <cstdlib>
#include <cstring>
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <csignal>
#include <unistd.h>
#endif

namespace InterfaceScale {
inline constexpr double Minimum = 0.75, Maximum = 2.0;
inline double saved()
{
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("VitraLauncher"), QStringLiteral("Interface"));
    const double value = settings.value(QStringLiteral("scale"), 1.0).toDouble();
    return value >= Minimum && value <= Maximum ? value : 1.0;
}
inline void save(double value)
{
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("VitraLauncher"), QStringLiteral("Interface"));
    settings.setValue(QStringLiteral("scale"), qBound(Minimum, value, Maximum));
    settings.sync();
}
// Before QApplication. A QT_SCALE_FACTOR set outside the launcher wins; one
// the launcher set itself (marked by PG_INTERFACE_SCALE, and inherited by a
// restarted launcher) is replaced with the saved value, so a restart picks
// up every change, not only the first.
inline void apply()
{
    const bool ours = qEnvironmentVariableIsSet("PG_INTERFACE_SCALE");
    if (!ours && !qEnvironmentVariableIsEmpty("QT_SCALE_FACTOR")) return;
    const double value = saved();
    if (qAbs(value - 1.0) > 0.001) qputenv("QT_SCALE_FACTOR", QByteArray::number(value, 'f', 2));
    else qunsetenv("QT_SCALE_FACTOR");
    qputenv("PG_INTERFACE_SCALE", "1");
}
// A restarted launcher waits for the previous process to exit first, or
// that one would receive it as a second instance. Removes the two
// arguments so the core's own parser never sees them.
inline void waitForPrevious(int& argc, char** argv)
{
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "--pg-wait-pid") != 0) continue;
        const long pid = std::strtol(argv[i + 1], nullptr, 10);
        for (int j = i; j + 2 <= argc; ++j) argv[j] = argv[j + 2];
        argc -= 2;
        if (pid <= 0) return;
#ifdef Q_OS_WIN
        if (HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, DWORD(pid))) {
            WaitForSingleObject(process, 15000);
            CloseHandle(process);
        }
#else
        for (int waited = 0; waited < 150 && kill(pid_t(pid), 0) == 0; ++waited) usleep(100000);
#endif
        return;
    }
}
// Starts a new launcher that waits for this one, then quits this one.
inline bool restart()
{
    QStringList arguments = QCoreApplication::arguments().mid(1);
    arguments << QStringLiteral("--pg-wait-pid") << QString::number(QCoreApplication::applicationPid());
    if (!QProcess::startDetached(QCoreApplication::applicationFilePath(), arguments)) return false;
    QCoreApplication::quit();
    return true;
}
}  // namespace InterfaceScale
