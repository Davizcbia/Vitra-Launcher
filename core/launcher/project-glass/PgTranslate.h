// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QCoreApplication>

// Interface text from the "ProjectGlass" translation, the same context the
// QML frontend's tr() reads (i18n/projectglass_*.ts).
inline QString pgTr(const char *text){return QCoreApplication::translate("ProjectGlass",text);}
