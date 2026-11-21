#include "CreateGameFolders.h"
#include <QFile>
#include <QFileInfo>
#include <QUuid>
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

    // Project Glass: default options. Each time the default is turned on (or
    // a different file is chosen) it gets a new stamp; an instance's options.txt
    // is replaced once per stamp, on its next launch, so changes made in game
    // afterwards are kept. Instances opt out with UseDefaultOptions. A copy
    // rather than a link keeps the game from rewriting the source file.
    auto settings = APPLICATION->settings();
    auto instanceSettings = instance->settings();
    const QString source = settings->get("DefaultOptionsFile").toString();
    const QString target = FS::PathCombine(instance->gameRoot(), "options.txt");
    const bool instanceUses = instanceSettings->contains("UseDefaultOptions") ? instanceSettings->get("UseDefaultOptions").toBool() : true;
    if (settings->get("DefaultOptionsEnabled").toBool() && instanceUses && !source.isEmpty()) {
        QString stamp = settings->get("DefaultOptionsStamp").toString();
        if (stamp.isEmpty()) {
            stamp = QUuid::createUuid().toString(QUuid::WithoutBraces);
            settings->set("DefaultOptionsStamp", stamp);
        }
        const bool applied = instanceSettings->contains("DefaultOptionsApplied") && instanceSettings->get("DefaultOptionsApplied").toString() == stamp;
        const QFileInfo sourceInfo(source), targetInfo(target);
        auto markApplied = [&] {
            if (instanceSettings->contains("DefaultOptionsApplied"))
                instanceSettings->set("DefaultOptionsApplied", stamp);
        };
        if (applied) {
            // Already replaced once for this default; keep the instance's own changes.
        } else if (!sourceInfo.exists()) {
            emit logLine("Default options file not found: " + source, MessageLevel::Warning);
        } else if (targetInfo.exists() && sourceInfo.canonicalFilePath() == targetInfo.canonicalFilePath()) {
            markApplied();  // The default file is this instance's own options.txt.
        } else if (targetInfo.exists() && !QFile::remove(target)) {
            emit logLine("Couldn't replace options.txt with the default options", MessageLevel::Warning);
        } else if (QFile::copy(source, target)) {
            // QFile::copy keeps a read-only source read-only; the game must save here.
            QFile::setPermissions(target, QFile::permissions(target) | QFile::WriteOwner | QFile::WriteUser);
            markApplied();
            emit logLine("Copied default options from " + source, MessageLevel::Launcher);
        } else {
            emit logLine("Couldn't copy default options from " + source, MessageLevel::Warning);
        }
    }
    emitSucceeded();
}
