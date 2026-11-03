#include "CreateGameFolders.h"
#include <QFile>
#include "Application.h"
#include "FileSystem.h"
#include "launch/LaunchTask.h"
#include "minecraft/MinecraftInstance.h"

CreateGameFolders::CreateGameFolders(LaunchTask* parent) : LaunchStep(parent) {}

void CreateGameFolders::executeTask()
{
    auto instance = m_parent->instance();

    if (!FS::ensureFolderPathExists(instance->gameRoot())) {
        emit logLine("Couldn't create the main game folder", MessageLevel::Error);
        emitFailed(tr("Couldn't create the main game folder"));
        return;
    }

    // HACK: this is a workaround for MCL-3732 - 'server-resource-packs' folder is created.
    if (!FS::ensureFolderPathExists(FS::PathCombine(instance->gameRoot(), "server-resource-packs"))) {
        emit logLine("Couldn't create the 'server-resource-packs' folder", MessageLevel::Error);
    }

    // Project Glass: default options. Only fills a gap, so an instance's own
    // options.txt (played, copied or shipped by a modpack) always wins, and a
    // copy rather than a link keeps the game from rewriting the source file.
    auto settings = APPLICATION->settings();
    const QString source = settings->get("DefaultOptionsFile").toString();
    const QString target = FS::PathCombine(instance->gameRoot(), "options.txt");
    if (settings->get("DefaultOptionsEnabled").toBool() && !source.isEmpty() && !QFile::exists(target)) {
        if (!QFile::exists(source)) {
            emit logLine("Default options file not found: " + source, MessageLevel::Warning);
        } else if (QFile::copy(source, target)) {
            // QFile::copy keeps a read-only source read-only; the game must save here.
            QFile::setPermissions(target, QFile::permissions(target) | QFile::WriteOwner | QFile::WriteUser);
            emit logLine("Copied default options from " + source, MessageLevel::Launcher);
        } else {
            emit logLine("Couldn't copy default options from " + source, MessageLevel::Warning);
        }
    }
    emitSucceeded();
}
