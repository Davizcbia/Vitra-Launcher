// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <functional>
#include "Application.h"
#include "Json.h"
#include "ResourceDownloadTask.h"
#include "minecraft/MinecraftInstance.h"
#include "minecraft/PackProfile.h"
#include "minecraft/mod/ModFolderModel.h"
#include "modplatform/EnsureMetadataTask.h"
#include "modplatform/flame/FlameCheckUpdate.h"
#include "modplatform/modrinth/ModrinthCheckUpdate.h"
#include "tasks/ConcurrentTask.h"
#include "tasks/SequentialTask.h"
#include "PgTranslate.h"

// Update check for an instance editor list, without Prism's modal dialogs:
// metadata is looked up by file hash (Modrinth first, then CurseForge), then
// both providers are asked for newer releases that fit the instance. The
// result is a list the frontend shows for selection; apply() downloads the
// chosen releases (ResourceDownloadTask replaces the old file).
class ResourceUpdateCheck final : public QObject {
public:
    struct Result {
        QVariantList updates;  // {index, name, fileName, oldVersion, newVersion, provider}
        int failed = 0;
        QString error;
    };
    using Done = std::function<void(const Result &)>;

    ResourceUpdateCheck(MinecraftInstance *instance, ResourceFolderModel *model, bool mods, bool curseForge, QObject *parent)
        : QObject(parent), m_instance(instance), m_model(model), m_mods(mods), m_curseForge(curseForge) {}

    void start(Done done) {
        m_done = std::move(done);
        if (!m_instance || !m_model) return finish(pgTr("The instance is unavailable."));
        if (APPLICATION->settings()->get("ModMetadataDisabled").toBool())
            return finish(pgTr("Updates are unavailable while mod metadata is disabled in the core settings."));
        auto *profile = m_instance->getPackProfile();
        if (profile && (profile->rowCount() == 0 || profile->getComponentVersion("net.minecraft").isEmpty()))
            (void)profile->reload(Net::Mode::Offline);
        const auto game = profile ? profile->getComponentVersion("net.minecraft") : QString();
        if (game.isEmpty()) return finish(pgTr("The instance’s Minecraft version is unknown."));
        m_versions = {Version(game)};
        if (m_mods) {
            m_loaders = profile->getModLoadersList();
            if (m_loaders.isEmpty()) return finish(pgTr("Install a mod loader before updating mods."));
        }
        m_releaseTypes = ModPlatform::IndexedVersionType::fromStringList(
            Json::toStringList(APPLICATION->settings()->get("ModUpdateReleaseTypes").toString()));
        // Writing .index files would make the model reload and replace the
        // Resource objects the tasks hold.
        m_model->stopWatching();
        m_status = pgTr("Reading installed files…");
        connect(m_model, &ResourceFolderModel::updateFinished, this, &ResourceUpdateCheck::collect, Qt::SingleShotConnection);
        m_model->update();
    }
    bool abort() {
        m_aborted = true;
        if (m_current && m_current->canAbort()) m_current->abort();
        return true;
    }
    QString status() const { return m_status; }
    std::function<void()> onStatus;

    // Downloads for the chosen update indices.
    Task *downloads(const QList<int> &chosen) {
        auto *task = new ConcurrentTask(pgTr("Updating resources"), APPLICATION->settings()->get("NumberOfConcurrentDownloads").toInt());
        for (int index : chosen)
            if (index >= 0 && index < int(m_updates.size()) && m_updates[index].download) task->addTask(m_updates[index].download);
        return task;
    }
    void resumeWatching() { if (m_model) m_model->startWatching(); }

private:
    void setStatus(const QString &status) { m_status = status; if (onStatus) onStatus(); }
    void collect() {
        if (m_aborted || !m_model) return finish(pgTr("Update check cancelled."));
        for (auto *resource : m_model->allResources()) {
            if (!resource || resource->type() == ResourceType::FOLDER) continue;
            m_fileNames.insert(resource, resource->fileinfo().fileName());
            if (resource->status() == ResourceStatus::NoMetadata) m_missing.append(resource);
            else sort(resource);
        }
        ensure(m_missing, ModPlatform::ResourceProvider::MODRINTH);
    }
    // Hash lookup on one provider; misses go to the other one.
    void ensure(QList<Resource *> resources, ModPlatform::ResourceProvider provider) {
        if (resources.isEmpty()) return check();
        setStatus(provider == ModPlatform::ResourceProvider::MODRINTH ? pgTr("Identifying files on Modrinth…") : pgTr("Identifying files on CurseForge…"));
        m_retry.clear();
        auto task = makeShared<EnsureMetadataTask>(resources, m_model->indexDir(), provider);
        connect(task.get(), &EnsureMetadataTask::metadataReady, this, [this](Resource *resource) { sort(resource); });
        connect(task.get(), &EnsureMetadataTask::metadataFailed, this, [this](Resource *resource) { m_retry.append(resource); });
        auto sequence = makeShared<SequentialTask>();
        if (task->getHashingTask()) sequence->addTask(task->getHashingTask());
        sequence->addTask(task);
        run(sequence, [this, provider] {
            const auto misses = m_retry;
            if (provider == ModPlatform::ResourceProvider::MODRINTH && m_curseForge) ensure(misses, ModPlatform::ResourceProvider::FLAME);
            else { m_failed += misses.size(); check(); }
        });
    }
    void sort(Resource *resource) {
        if (!resource || !resource->metadata() || resource->lockUpdate()) return;
        if (resource->metadata()->provider == ModPlatform::ResourceProvider::FLAME) {
            if (m_curseForge && !m_flame.contains(resource)) m_flame.append(resource);
        } else if (!m_modrinth.contains(resource)) m_modrinth.append(resource);
    }
    void check() {
        if (m_aborted) return finish(pgTr("Update check cancelled."));
        setStatus(pgTr("Checking for updates…"));
        auto sequence = makeShared<SequentialTask>(pgTr("Checking for updates"));
        auto failed = [this](Resource *, const QString &, const QUrl &) { ++m_failed; };
        if (!m_modrinth.isEmpty()) {
            m_modrinthCheck.reset(new ModrinthCheckUpdate(m_modrinth, m_versions, m_loaders, m_model, m_releaseTypes));
            connect(m_modrinthCheck.get(), &CheckUpdateTask::checkFailed, this, failed);
            sequence->addTask(m_modrinthCheck);
        }
        if (!m_flame.isEmpty()) {
            m_flameCheck.reset(new FlameCheckUpdate(m_flame, m_versions, m_loaders, m_model, m_releaseTypes));
            connect(m_flameCheck.get(), &CheckUpdateTask::checkFailed, this, failed);
            sequence->addTask(m_flameCheck);
        }
        if (!m_modrinthCheck && !m_flameCheck) return finish({});
        run(sequence, [this] {
            if (m_modrinthCheck) for (auto &update : m_modrinthCheck->getUpdates()) m_updates.push_back(std::move(update));
            if (m_flameCheck) for (auto &update : m_flameCheck->getUpdates()) m_updates.push_back(std::move(update));
            finish({});
        });
    }
    void run(const Task::Ptr &task, std::function<void()> next) {
        m_current = task;
        connect(task.get(), &Task::finished, this, [this, task, next = std::move(next)] {
            m_current.reset();
            if (m_aborted) return finish(pgTr("Update check cancelled."));
            if (!task->wasSuccessful() && !task->failReason().isEmpty() && task->failReason() != "Aborted")
                qWarning() << "Resource update check step failed:" << task->failReason();
            next();
        }, Qt::QueuedConnection);
        task->start();
    }
    void finish(const QString &error) {
        if (!m_done) return;
        Result result;
        result.error = error;
        result.failed = m_failed;
        if (error.isEmpty()) {
            // Project name / old hash → installed file name, so the list can show its icon.
            QHash<QString, QString> byName, byHash;
            for (auto *resource : m_modrinth + m_flame) {
                const auto file = m_fileNames.value(resource);
                if (auto metadata = resource->metadata()) { byName.insert(metadata->name, file); byHash.insert(metadata->hash, file); }
                byName.insert(resource->name(), file);
            }
            for (int i = 0; i < int(m_updates.size()); ++i) {
                const auto &update = m_updates[i];
                result.updates.append(QVariantMap{
                    {"index", i}, {"name", update.name}, {"fileName", byHash.value(update.oldHash, byName.value(update.name))},
                    {"oldVersion", update.oldVersion}, {"newVersion", update.newVersion},
                    {"provider", ModPlatform::ProviderCapabilities::readableName(update.provider)},
                    {"versionType", update.newVersionType ? update.newVersionType->toString() : QString()}});
            }
        }
        auto done = std::move(m_done);
        m_done = nullptr;
        done(result);
    }

    QPointer<MinecraftInstance> m_instance;
    QPointer<ResourceFolderModel> m_model;
    bool m_mods, m_curseForge;
    bool m_aborted = false;
    int m_failed = 0;
    QString m_status;
    Done m_done;
    Task::Ptr m_current;
    // CheckUpdateTask keeps references to these.
    std::vector<Version> m_versions;
    QList<ModPlatform::ModLoaderType> m_loaders;
    std::vector<ModPlatform::IndexedVersionType> m_releaseTypes;
    QList<Resource *> m_missing, m_retry, m_modrinth, m_flame;
    QHash<Resource *, QString> m_fileNames;
    shared_qobject_ptr<CheckUpdateTask> m_modrinthCheck, m_flameCheck;
    std::vector<CheckUpdateTask::Update> m_updates;
};
