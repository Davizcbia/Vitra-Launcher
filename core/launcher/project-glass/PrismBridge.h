// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QDesktopServices>
#include <QUrl>
#include <QUrlQuery>
#include <QFileInfo>
#include <QDir>
#include <QRegularExpression>
#include <QMessageBox>
#include <QInputDialog>
#include <QSettings>
#include "minecraft/auth/AccountList.h"
#include "minecraft/auth/MinecraftAccount.h"
#include "Application.h"
#include "ui/dialogs/MSALoginDialog.h"
#include "minecraft/VanillaInstanceCreationTask.h"
#include "meta/Version.h"
#include "ModrinthInstallTask.h"
#include "PgTranslate.h"
#include "MemoryOptimizer.h"
#include "LaunchDiagnosis.h"
#include "ModpackDrop.h"
#include "FileSystem.h"
#include <QElapsedTimer>
#include <QPushButton>
#include <QTemporaryFile>
#include <QTranslator>
#include <QThread>
#include <functional>
#include "InstanceEditorFiles.h"
#include "minecraft/mod/Resource.h"
#include <QFileSystemWatcher>
#include <QProcess>
#include <QApplication>
#include <QClipboard>
#include <QBuffer>
#include <QHash>
#include <QPainter>
#include <qrencode.h>
#include "minecraft/mod/tasks/LocalModParseTask.h"
#include "InstanceImportTask.h"
#include "modplatform/modrinth/ModrinthPackIndex.h"
#include "modplatform/flame/FlameModIndex.h"
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFile>
#include <QPointer>
#include "settings/SettingsObject.h"
#include "InstanceList.h"
#include "minecraft/MinecraftInstance.h"
#include "java/JavaInstallList.h"
#include "java/JavaInstall.h"
#include "updater/ExternalUpdater.h"
#include "launch/LaunchTask.h"
#include "BuildConfig.h"
#include <QFontDatabase>
#include "ScreenColorPicker.h"
#include "translations/TranslationsModel.h"
#ifdef Q_OS_WIN
#include <qt_windows.h>
#endif
#include "minecraft/PackProfile.h"

// Compatibility context name for the accepted QML frontend. No external process.
class PrismBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap editorDetails READ editorDetails NOTIFY editorDetailsChanged)
    Q_PROPERTY(QString editorInstanceKey READ editorInstanceKey NOTIFY editorDetailsChanged)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)
    Q_PROPERTY(double installProgress READ installProgress NOTIFY changed)
    Q_PROPERTY(bool importingLocalPack READ importingLocalPack NOTIFY changed)
    Q_PROPERTY(bool canCancelInstall READ canCancelInstall NOTIFY changed)
    Q_PROPERTY(QVariantList savedAccounts READ savedAccounts NOTIFY changed)
    Q_PROPERTY(QString currentAccountName READ currentAccountName NOTIFY changed)
    Q_PROPERTY(bool signingIn READ signingIn NOTIFY changed)
    Q_PROPERTY(QString loginQr READ loginQr NOTIFY changed)
    Q_PROPERTY(QString loginCode READ loginCode NOTIFY changed)
    Q_PROPERTY(QString loginUrl READ loginUrl NOTIFY changed)
    Q_PROPERTY(bool offlineMode READ offlineMode NOTIFY changed)
    Q_PROPERTY(QString offlineName READ offlineName NOTIFY changed)
    Q_PROPERTY(QString executable READ executable NOTIFY changed)
    Q_PROPERTY(QString dataRoot READ dataRoot NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QVariantList instances READ instances NOTIFY instancesChanged)
    // Bumped when the interface language changes; QML's tr() reads it so its
    // bindings re-evaluate.
    Q_PROPERTY(int languageRevision READ languageRevision NOTIFY languageChanged)
    Q_PROPERTY(bool memoryOptimizerAvailable READ memoryOptimizerAvailable CONSTANT)
    Q_PROPERTY(bool optimizingMemory READ optimizingMemory NOTIFY changed)
    Q_PROPERTY(QString availableUpdate READ availableUpdate NOTIFY updateStateChanged)
public:
    explicit PrismBridge(Application *app):QObject(app),m_app(app){
        app->setProperty("projectGlassAuthBridge",QVariant::fromValue(static_cast<QObject *>(this)));
        applyInterfaceLanguage(m_app->settings()->get("Language").toString());
        connect(app,&Application::projectGlassLaunchFailed,this,&PrismBridge::launchFailed);
        connect(app,&Application::projectGlassLaunchEnded,this,&PrismBridge::launchEnded);
        connect(app,&Application::projectGlassLaunchStatus,this,[this](const QString &status){
            m_status=status;emit changed();
        });
        m_editorWatcher=new QFileSystemWatcher(this);
        m_editorReload=new QTimer(this);m_editorReload->setInterval(120);m_editorReload->setSingleShot(true);
        connect(m_editorReload,&QTimer::timeout,this,&PrismBridge::refreshEditor);
        connect(m_editorWatcher,&QFileSystemWatcher::directoryChanged,this,&PrismBridge::queueEditorReload);
        connect(m_editorWatcher,&QFileSystemWatcher::fileChanged,this,&PrismBridge::queueEditorReload);
        m_modParser=new QTimer(this);m_modParser->setInterval(0);
        connect(m_modParser,&QTimer::timeout,this,&PrismBridge::parseQueuedMods);
        m_refreshSoon=new QTimer(this);m_refreshSoon->setSingleShot(true);m_refreshSoon->setInterval(0);
        connect(m_refreshSoon,&QTimer::timeout,this,&PrismBridge::refresh);
        auto *timer=new QTimer(this);timer->setInterval(1500);
        connect(timer,&QTimer::timeout,this,&PrismBridge::refresh);timer->start();refresh();
    }
    bool offlineMode()const{QSettings prefs("ProjectGlass","CoreAccount");return prefs.value("offlineMode",false).toBool();}
    QString offlineName()const{QSettings prefs("ProjectGlass","CoreAccount");return prefs.value("offlineName","Player").toString();}
    Q_INVOKABLE void setOfflineMode(bool enabled){
        QSettings prefs("ProjectGlass","CoreAccount");prefs.setValue("offlineMode",enabled);
        m_status=enabled?pgTr("Offline profile selected · ")+offlineName():pgTr("Microsoft account mode selected");emit changed();
    }
    Q_INVOKABLE bool renameOffline(const QString &value){
        const auto name=value.trimmed();
        if(!QRegularExpression("^[A-Za-z0-9_]{3,16}$").match(name).hasMatch()){
            m_status=pgTr("Name must contain 3–16 letters, digits or underscores");emit changed();return false;
        }
        QSettings prefs("ProjectGlass","CoreAccount");prefs.setValue("offlineName",name);emit changed();return true;
    }
    Q_INVOKABLE void configureOffline(){
        bool ok=false;const auto name=QInputDialog::getText(nullptr,pgTr("Offline profile"),pgTr("Player name (3–16 letters, digits or underscores):"),QLineEdit::Normal,offlineName(),&ok).trimmed();
        if(!ok)return;
        if(!QRegularExpression("^[A-Za-z0-9_]{3,16}$").match(name).hasMatch()){QMessageBox::information(nullptr,pgTr("Invalid name"),pgTr("Use 3–16 letters, digits or underscores."));return;}
        QSettings prefs("ProjectGlass","CoreAccount");prefs.setValue("offlineName",name);prefs.setValue("offlineMode",true);
        m_status=pgTr("Offline profile selected · ")+name;emit changed();
    }
    Q_INVOKABLE void useMicrosoft(){signIn();}
    QString executable()const{return pgTr("Built-in Prism core");}
    QString dataRoot()const{return m_app->dataRoot();}
    QString status()const{return m_status;}
    QVariantList instances()const{return m_instances;}
    Q_INVOKABLE void configure(QString,QString root){
        if(QDir::cleanPath(root)!=QDir::cleanPath(dataRoot())){m_status=pgTr("Data folder is fixed for this session. Restart with --dir <folder> to change it.");emit changed();return;}
        refresh();
    }
    Q_INVOKABLE void refresh(){
        if(m_app->status()!=Application::Initialized || !m_app->instances())return;
        if(m_observedUpdater!=m_app->updater()) {
            m_observedUpdater=m_app->updater();
            if(m_observedUpdater)connect(m_observedUpdater.data(),&ExternalUpdater::availableVersionChanged,this,&PrismBridge::updateStateChanged);
            emit updateStateChanged();
        }
        if(m_observedAccounts!=m_app->accounts()) {
            m_observedAccounts=m_app->accounts();
            connect(m_observedAccounts.data(),&AccountList::listChanged,this,&PrismBridge::changed);
            connect(m_observedAccounts.data(),&AccountList::defaultAccountChanged,this,&PrismBridge::changed);
        }
        if(m_observedInstances!=m_app->instances()) {
            m_observedInstances=m_app->instances();
            auto queueRefresh=[this]{m_refreshSoon->start();};
            connect(m_observedInstances.data(),&QAbstractItemModel::rowsInserted,this,queueRefresh);
            connect(m_observedInstances.data(),&QAbstractItemModel::rowsRemoved,this,queueRefresh);
            connect(m_observedInstances.data(),&QAbstractItemModel::modelReset,this,queueRefresh);
            connect(m_observedInstances.data(),&QAbstractItemModel::dataChanged,this,queueRefresh);
            connect(m_observedInstances.data(),&InstanceList::instanceSelectRequest,this,[this](const QString &id){
                m_pendingInstance="prism:"+id;m_refreshSoon->start();
            });
        }
        QVariantList rows;
        for(int i=0;i<m_app->instances()->count();++i){
            auto *instance=m_app->instances()->at(i);auto *profile=instance->getPackProfile();
            QMap<QString,QString> manifestVersions;
            // A newly committed instance may not have resolved its profile yet.
            // Read display versions from its already-written local manifest;
            // never start a metadata download just to pick the card artwork.
            if(!profile || profile->rowCount()==0 || profile->getComponentVersion("net.minecraft").isEmpty()) {
                QFile file(QDir(instance->instanceRoot()).filePath("mmc-pack.json"));
                if(file.open(QIODevice::ReadOnly)) {
                    const auto components=QJsonDocument::fromJson(file.readAll()).object().value("components").toArray();
                    for(const auto &value:components) {
                        const auto component=value.toObject();manifestVersions.insert(component.value("uid").toString(),component.value("version").toString());
                    }
                }
            }
            auto componentVersion=[profile,&manifestVersions](const QString &uid){
                const auto resolved=profile?profile->getComponentVersion(uid):QString();
                return resolved.isEmpty()?manifestVersions.value(uid):resolved;
            };
            QString game=componentVersion("net.minecraft"),loader="Minecraft";
            for(const auto &pair: {qMakePair(QString("net.fabricmc.fabric-loader"),QString("Fabric")),qMakePair(QString("net.minecraftforge"),QString("Forge")),qMakePair(QString("net.neoforged"),QString("NeoForge")),qMakePair(QString("org.quiltmc.quilt-loader"),QString("Quilt"))})
                if(!componentVersion(pair.first).isEmpty())loader=pair.second;
            rows.append(QVariantMap{{"key","prism:"+instance->id()},{"coverKey",loader=="Minecraft"?QString("vanilla"):loader.toLower()},{"label",instance->name()},{"version",loader+" "+game},{"hours",qRound(instance->totalTimePlayed()/36.0)/100.0},{"launches",0},{"installed",true},{"lastPlayed",false},{"running",instance->isRunning()}});
        }
        const bool changedRows=rows!=m_instances;m_instances=rows;
        if(m_status.isEmpty())m_status=pgTr("Built-in core ready · %1 instances").arg(rows.size());
        auto account=m_app->accounts()->defaultAccount();
        if(account && !account->accountData()->msaClientID.isEmpty() && account->accountData()->msaClientID!=m_app->getMSAClientID()
           && (m_status.startsWith(pgTr("Built-in core ready · %1 instances").section("%1",0,0))
               || m_status==pgTr("Microsoft account mode selected")))
            m_status=pgTr("Microsoft account needs sign-in again: launcher client ID changed. Open Accounts and add the account again.");
        if(changedRows){emit instancesChanged();emit changed();}
        if(!m_pendingInstance.isEmpty()) {
            for(const auto &row:rows)if(row.toMap().value("key").toString()==m_pendingInstance) {
                const auto key=m_pendingInstance;m_pendingInstance.clear();emit instanceReady(key);
                if(m_sharedCreating){m_sharedKey=key;reportSharedInstance();}
                break;
            }
        }
    }
    Q_INVOKABLE bool launch(const QString &key){
        if(installing() && key==m_installInstance){m_status=pgTr("Wait for this instance’s installation to finish.");emit changed();return false;}
        if(offlineMode())return launchOffline(key,offlineName());
        m_launchRetried=false;
        auto *instance=lookup(key);if(!instance){m_status=pgTr("Instance unavailable. Refresh the list.");emit changed();return false;}
        if(instance->isRunning() || !instance->canLaunch()){m_status=pgTr("Instance is running or busy.");emit changed();return false;}
        if(deferForMemory([this,key]{launchNow(key);}))return true;
        return launchNow(key);
    }
    // ---- Settings › Memory: optimize memory (Windows) ----
    bool memoryOptimizerAvailable()const{return MemoryOptimizer::supported();}
    bool optimizingMemory()const{return m_optimizingMemory;}
    Q_INVOKABLE void setOptimizeBeforeLaunch(bool on){m_optimizeBeforeLaunch=on;}
    // Optimize Now: the full optimization, through an elevated helper (UAC).
    Q_INVOKABLE void optimizeMemory(){if(!m_optimizingMemory)runMemoryOptimization(true,{});}
private:
    // Before a launch: the quick, unelevated pass, then the launch itself.
    bool deferForMemory(std::function<void()> launchLater){
        if(!m_optimizeBeforeLaunch || !MemoryOptimizer::supported() || m_optimizingMemory)return false;
        runMemoryOptimization(false,std::move(launchLater));return true;
    }
    void runMemoryOptimization(bool full,std::function<void()> next){
#ifdef Q_OS_WIN
        HANDLE helper=nullptr;
        if(full && !MemoryOptimizer::elevated() && !(helper=MemoryOptimizer::startElevatedPurge())) {
            m_status=pgTr("Full memory optimization needs administrator permission.");emit changed();
            if(next)next();
            return;
        }
        m_optimizingMemory=true;m_status=pgTr("Optimizing memory…");emit changed();
        const quint64 before=MemoryOptimizer::availableBytes();
        auto *worker=QThread::create([full,helper]{
            MemoryOptimizer::trimUserProcesses();
            if(full)(void)(helper ? MemoryOptimizer::waitForPurge(helper) : MemoryOptimizer::purgeSystemLists());
        });
        connect(worker,&QThread::finished,this,[this,worker,before,next]{
            worker->deleteLater();
            const qint64 freed=qMax<qint64>(0,qint64(MemoryOptimizer::availableBytes())-qint64(before))/(1024*1024);
            m_optimizingMemory=false;m_status=pgTr("Memory optimized · freed %1 MB").arg(freed);emit changed();
            if(next)next();
        });
        worker->start();
#else
        Q_UNUSED(full);if(next)next();
#endif
    }
    // The launch proper; the instance is looked up again after a deferral.
    bool launchNow(const QString &key){
        auto *instance=lookup(key);
        if(!instance || instance->isRunning() || !instance->canLaunch()){m_status=pgTr("Instance is running or busy.");emit changed();return false;}
        rememberLaunch(key,[this,key]{launchNow(key);});
        const bool accepted=m_app->launch(instance);
        m_status=accepted?pgTr("Built-in core is preparing the game. Authentication or download dialogs may appear."):pgTr("Core rejected the launch request.");
        if(accepted)applyProcessPriority(instance);
        emit changed();return accepted;
    }
    void rememberLaunch(const QString &key,std::function<void()> again){
        m_launchKey=key;m_launchStarted=QDateTime::currentDateTime();m_launchAgain=std::move(again);
    }
    void launchFailed(const QString &reason){
        using LaunchDiagnosis::Kind;
        m_status=pgTr("Launch failed · ")+reason;
        auto *instance=lookup(m_launchKey);
        const auto diagnosis=instance?LaunchDiagnosis::diagnose(instance->gameRoot(),m_launchStarted):LaunchDiagnosis::Result{};
        if(diagnosis.kind==Kind::EarlyWindowRace && !m_launchRetried) {
            m_launchRetried=true;m_status=pgTr("NeoForge stopped at a startup timing fault. Starting again…");emit changed();
            QTimer::singleShot(1500,this,[this]{if(m_launchAgain)m_launchAgain();});
            return;
        }
        emit changed();
        // After this signal has finished: the core is still ending the launch task.
        if(diagnosis.kind!=Kind::Unknown)QTimer::singleShot(0,this,[this,key=m_launchKey,diagnosis]{explainFailure(key,diagnosis);});
    }
    // NeoForge shows mod loading errors on its own screen, and closing that exits
    // with code 0: to the core a normal end, though the game never got past it.
    void launchEnded(){
        auto *instance=lookup(m_launchKey);if(!instance)return;
        const auto diagnosis=LaunchDiagnosis::diagnose(instance->gameRoot(),m_launchStarted);
        if(diagnosis.kind==LaunchDiagnosis::Kind::ModLoading)QTimer::singleShot(0,this,[this,key=m_launchKey,diagnosis]{explainFailure(key,diagnosis);});
    }
    void explainFailure(const QString &key,const LaunchDiagnosis::Result &diagnosis){
        using LaunchDiagnosis::Kind;
        auto *instance=lookup(key);if(!instance)return;
        QMessageBox box;box.setIcon(QMessageBox::Warning);box.setWindowTitle(pgTr("The game could not start"));
        if(diagnosis.kind==Kind::ModLoading) {
            box.setText(pgTr("The mods in this instance cannot load together."));
            box.setInformativeText(diagnosis.issues.join('\n'));
        } else if(diagnosis.kind==Kind::OutOfMemory) {
            box.setText(pgTr("The game ran out of memory."));
            box.setInformativeText(pgTr("%1 MiB is allocated now. Raise the maximum memory in Settings or in this instance’s settings.").arg(instance->settings()->get("MaxMemAlloc").toInt()));
        } else {
            box.setText(pgTr("NeoForge stopped at the same startup timing fault twice."));
            box.setInformativeText(pgTr("This fault is in NeoForge, not in your mods. Start the game again."));
        }
        QPushButton *disable=diagnosis.conflictingMod.isEmpty()?nullptr:box.addButton(pgTr("Disable %1 and start again").arg(diagnosis.conflictingMod),QMessageBox::AcceptRole);
        QPushButton *report=diagnosis.reportPath.isEmpty()?nullptr:box.addButton(pgTr("Open crash report"),QMessageBox::ActionRole);
        box.addButton(QMessageBox::Close);
        box.exec();
        if(report && box.clickedButton()==report)QDesktopServices::openUrl(QUrl::fromLocalFile(diagnosis.reportPath));
        if(!disable || box.clickedButton()!=disable)return;
        if(!disableMod(instance,diagnosis.conflictingMod)) {
            m_status=pgTr("%1 is inside another mod’s file. Disable it in the instance’s Mods tab.").arg(diagnosis.conflictingMod);emit changed();return;
        }
        if(m_launchAgain)m_launchAgain();
    }
    static bool disableMod(MinecraftInstance *instance,const QString &modId){
        for(const auto &file:QDir(instance->modsRoot()).entryInfoList({"*.jar"},QDir::Files)) {
            Mod mod(file);
            if(ModUtils::process(mod,ModUtils::ProcessingLevel::BasicInfoOnly) && mod.details().mod_id==modId)return mod.enable(EnableAction::DISABLE);
        }
        return false;
    }
    bool launchOfflineNow(const QString &key,const QString &player){
        auto *instance=lookup(key);
        if(!instance || !instance->canLaunch() || instance->isRunning()){m_status=pgTr("Instance unavailable or busy.");emit changed();return false;}
        auto account=MinecraftAccount::createOffline(player);
        if(!account){m_status=pgTr("Could not create offline profile.");emit changed();return false;}
        m_status=pgTr("Preparing offline play · ")+player;emit changed();
        rememberLaunch(key,[this,key,player]{launchOfflineNow(key,player);});
        const bool accepted=m_app->launch(instance,LaunchMode::Offline,nullptr,account,player);
        if(accepted)applyProcessPriority(instance);
        if(!accepted){m_status=pgTr("Offline launch was not accepted.");emit changed();}return accepted;
    }
public:
    MinecraftInstance *instanceForKey(const QString &key)const{return lookup(key);}
    Q_INVOKABLE void openInstance(const QString &key){auto *instance=lookup(key);if(instance)QDesktopServices::openUrl(QUrl::fromLocalFile(instance->instanceRoot()));}
    Q_INVOKABLE void promptOffline(const QString &key){bool ok=false;auto name=QInputDialog::getText(nullptr,pgTr("Play offline"),pgTr("Player name (3–16 letters, digits or underscores):"),QLineEdit::Normal,"Player",&ok);if(ok)launchOffline(key,name);}
    Q_INVOKABLE bool launchOffline(const QString &key,const QString &name){
        if(installing() && key==m_installInstance){m_status=pgTr("Wait for this instance’s installation to finish.");emit changed();return false;}
        auto *instance=lookup(key);const QString player=name.trimmed();
        if(!instance || !instance->canLaunch() || instance->isRunning()){m_status=pgTr("Instance unavailable or busy.");emit changed();return false;}
        if(!QRegularExpression("^[A-Za-z0-9_]{3,16}$").match(player).hasMatch()){m_status=pgTr("Use a player name with 3–16 letters, digits or underscores.");emit changed();return false;}
        m_launchRetried=false;
        if(deferForMemory([this,key,player]{launchOfflineNow(key,player);}))return true;
        return launchOfflineNow(key,player);
    }
    Q_INVOKABLE QString microsoftClientId()const{return m_app->getMSAClientID();}
    Q_INVOKABLE void setMicrosoftClientId(const QString &id){if(!QRegularExpression("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$").match(id.trimmed()).hasMatch()){m_status=pgTr("Invalid Microsoft application client ID");emit changed();return;}m_app->settings()->set("MSAClientIDOverride",id.trimmed());m_status=pgTr("Microsoft client ID saved");emit changed();}
    bool installing()const{return !m_installTask.isNull();}
    double installProgress()const{return m_installProgress;}
    bool importingLocalPack()const{return m_importingLocalPack;}
    bool canCancelInstall()const{return m_installTask && m_installTask->canAbort();}
    Q_INVOKABLE void cancelInstall(){if(m_installTask && m_installTask->canAbort())m_installTask->abort();}
    Q_INVOKABLE bool importLocalModpack(const QUrl &source){
        auto reject=[this](const QString &reason){m_status=reason;emit changed();return false;};
        if(installing())return reject(pgTr("Finish the current installation before importing a modpack."));
        const QString problem=ModpackDrop::validate(source);
        if(!problem.isEmpty())return reject(problem);
        if(!m_app->instances())return reject(pgTr("Instance list is not available yet."));
        auto *creation=new InstanceImportTask(source,false,nullptr);
        const QString name=QFileInfo(source.toLocalFile()).completeBaseName();
        creation->setName(name.trimmed().isEmpty()?pgTr("Imported modpack"):name);
        creation->setAlwaysCreateNew(true);
        creation->setIcon("default");
        creation->setRequireGameFiles(true);
        Task *task=m_app->instances()->wrapInstanceTask(creation);
        m_importingLocalPack=true;
        connect(task,&Task::succeeded,this,[this]{m_importingLocalPack=false;emit localPackImportFinished(true,pgTr("Modpack imported. A new instance has been added."));});
        connect(task,&Task::failed,this,[this](const QString &reason){m_importingLocalPack=false;emit localPackImportFinished(false,pgTr("Modpack import failed: ")+reason);});
        connect(task,&Task::aborted,this,[this]{m_importingLocalPack=false;emit localPackImportFinished(false,pgTr("Modpack import cancelled."));});
        return runInstall(task);
    }
    // Reports through sharedInstanceCreated once the instance exists and its game files are in.
    bool installSharedInstance(const QString &gameVersion,const QString &loader,const QString &loaderVersion,const QString &name){
        m_sharedCreating=true;m_sharedInstalled=false;m_sharedKey.clear();
        if(!installGame(gameVersion,loader,loaderVersion,name)){m_sharedCreating=false;return false;}
        return true;
    }
    Q_INVOKABLE bool installGame(const QString &gameVersion,const QString &loader,const QString &loaderVersion,const QString &name=QString()){
        if(installing())return false;
        const QRegularExpression safeVersion(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._+\\-]*$"));
        const QMap<QString,QString> loaders{{"Fabric","net.fabricmc.fabric-loader"},{"Forge","net.minecraftforge"},
                                          {"NeoForge","net.neoforged"},{"Quilt","org.quiltmc.quilt-loader"}};
        if(!safeVersion.match(gameVersion).hasMatch() ||
           (loader!="Vanilla" && (!loaders.contains(loader) || !safeVersion.match(loaderVersion).hasMatch()))) {
            m_status=pgTr("Choose a Minecraft version and a compatible loader release.");emit changed();return false;
        }
        auto game=std::make_shared<Meta::Version>(QStringLiteral("net.minecraft"),gameVersion);
        VanillaCreationTask *creation=loader=="Vanilla" ? new VanillaCreationTask(game) :
            new VanillaCreationTask(game,loaders.value(loader),std::make_shared<Meta::Version>(loaders.value(loader),loaderVersion));
        creation->setName(!name.isEmpty()?name:loader=="Vanilla"?QString("Minecraft %1").arg(gameVersion):QString("%1 %2").arg(loader,gameVersion));
        creation->setIcon(loader=="Vanilla"?QStringLiteral("default"):loader.toLower());
        creation->setRequireGameFiles(true);
        return runInstall(m_app->instances()->wrapInstanceTask(creation));
    }
    Q_INVOKABLE bool installModrinth(const QString &key,const QString &category,const QString &projectId,
                                    const QString &name,const QVariantMap &release,const QString &slug=QString()){
        if(installing())return false;
        auto reject=[this](const QString &reason){m_status=reason;emit changed();return false;};
        const auto raw=QJsonObject::fromVariantMap(release);
        if(projectId.isEmpty() || raw.value("project_id").toString()!=projectId)
            return reject(pgTr("The selected release does not belong to this project."));
        auto parsed=Modrinth::loadIndexedPackVersion(raw);
        if(!parsed || !ModrinthInstallTask::validFile(*parsed))
            return reject(pgTr("The selected release has invalid download metadata or no checksum."));
        if(category=="Modpacks" && !parsed->fileName.endsWith(".mrpack",Qt::CaseInsensitive))return reject(pgTr("Select a Modrinth .mrpack release."));
        return installRelease(key,category,projectId,name,*parsed,slug,ModPlatform::ResourceProvider::MODRINTH);
    }
    // The key is compiled in (or set in core settings); empty disables CurseForge.
    Q_INVOKABLE QString curseForgeKey()const{return m_app->getFlameAPIKey();}
    Q_INVOKABLE bool installCurseForge(const QString &key,const QString &category,const QString &projectId,
                                       const QString &name,const QVariantMap &release,const QString &slug=QString()){
        if(installing())return false;
        auto reject=[this](const QString &reason){m_status=reason;emit changed();return false;};
        const auto raw=QJsonObject::fromVariantMap(release);
        if(projectId.isEmpty() || QString::number(raw.value("modId").toInteger())!=projectId)
            return reject(pgTr("The selected release does not belong to this project."));
        auto parsed=FlameMod::loadIndexedPackVersion(raw);
        if(!parsed)return reject(pgTr("The selected release has invalid download metadata."));
        if(parsed->downloadUrl.isEmpty()) {
            // The author has disabled third-party downloads for this file.
            static const QMap<QString,QString> sections{{"Mods","mc-mods"},{"Resource packs","texture-packs"},{"Shaders","shaders"},{"Modpacks","modpacks"}};
            QDesktopServices::openUrl(QUrl(QString("https://www.curseforge.com/minecraft/%1/%2/files/%3")
                .arg(sections.value(category,"mc-mods"),slug.isEmpty()?projectId:slug,parsed->fileId.toString())));
            return reject(pgTr("The author only allows this file to be downloaded from CurseForge. Opened its page in your browser."));
        }
        if(!ModrinthInstallTask::validFile(*parsed))
            return reject(pgTr("The selected release has invalid download metadata or no checksum."));
        if(category=="Modpacks" && !parsed->fileName.endsWith(".zip",Qt::CaseInsensitive))return reject(pgTr("Select a CurseForge .zip modpack release."));
        return installRelease(key,category,projectId,name,*parsed,slug,ModPlatform::ResourceProvider::FLAME);
    }
    // Shared by both providers once the release file has been validated.
    bool installRelease(const QString &key,const QString &category,const QString &projectId,const QString &name,
                        const ModPlatform::IndexedVersion &version,const QString &slug,ModPlatform::ResourceProvider provider){
        auto reject=[this](const QString &reason){m_status=reason;emit changed();return false;};
        if(category=="Modpacks") {
            QMap<QString,QString> info{{"pack_id",projectId},{"pack_version_id",version.fileId.toString()}};
            auto *creation=new InstanceImportTask(QUrl(version.downloadUrl),true,nullptr,info);
            creation->setName(name);creation->setIcon("default");creation->setRequireGameFiles(true);
            creation->setArchiveChecksum(version.hashType,version.hash);
            return runInstall(m_app->instances()->wrapInstanceTask(creation));
        }
        auto *instance=lookup(key);
        if(!instance || instance->isRunning() || !instance->canLaunch())return reject(pgTr("Select a stopped, installed instance first."));
        auto *profile=instance->getPackProfile();
        // The instance list never loads profiles (it reads mmc-pack.json), and
        // an unloaded profile reports no Minecraft version or loader, so every
        // release was rejected. Try loading it from disk (no download), and
        // fall back to the manifest exactly as the instance list does.
        if(profile && (profile->rowCount()==0 || profile->getComponentVersion("net.minecraft").isEmpty()))
            (void)profile->reload(Net::Mode::Offline);
        const auto manifest=manifestComponents(instance);
        auto componentVersion=[profile,&manifest](const QString &uid){
            const auto resolved=profile?profile->getComponentVersion(uid):QString();
            return resolved.isEmpty()?manifest.value(uid):resolved;
        };
        const QString game=componentVersion("net.minecraft");
        if(game.isEmpty() || !version.mcVersion.contains(game)) {
            auto listed=version.mcVersion;listed.removeDuplicates(); // each version is stored twice
            return reject(pgTr("This release supports Minecraft %1, but the instance is Minecraft %2.")
                          .arg(listed.isEmpty()?pgTr("(none listed)"):listed.mid(0,6).join(", "),
                               game.isEmpty()?pgTr("(unknown)"):game));
        }
        ResourceFolderModel *folder=nullptr;
        ModPlatform::ResourceType type=ModPlatform::ResourceType::Unknown;
        if(category=="Mods") {
            auto loaders=profile?profile->getSupportedModLoaders().value_or(ModPlatform::ModLoaderTypes(0)):ModPlatform::ModLoaderTypes(0);
            if(!loaders) {
                // Same mapping as PackProfile: Quilt also runs Fabric mods.
                if(!componentVersion("net.fabricmc.fabric-loader").isEmpty())loaders|=ModPlatform::Fabric;
                if(!componentVersion("org.quiltmc.quilt-loader").isEmpty())loaders|=ModPlatform::Quilt|ModPlatform::Fabric;
                if(!componentVersion("net.minecraftforge").isEmpty())loaders|=ModPlatform::Forge;
                if(!componentVersion("net.neoforged").isEmpty())loaders|=ModPlatform::NeoForge;
            }
            if(!loaders || !version.loaders || !version.loaders.testAnyFlags(loaders))
                return reject(pgTr("This mod does not support the selected instance’s loader."));
            folder=instance->loaderModList();type=ModPlatform::ResourceType::Mod;
        }
        else if(category=="Resource packs") {folder=instance->resourcePackList();type=ModPlatform::ResourceType::ResourcePack;}
        else if(category=="Shaders") {folder=instance->shaderPackList();type=ModPlatform::ResourceType::ShaderPack;}
        else return reject(pgTr("Unsupported project category."));
        auto pack=std::make_shared<ModPlatform::IndexedPack>();
        // CurseForge ids are integers everywhere else (dependencies, metadata).
        pack->addonId=provider==ModPlatform::ResourceProvider::FLAME?QVariant(projectId.toInt()):QVariant(projectId);
        pack->name=name;pack->provider=provider;pack->resourceType=type;
        // packwiz metadata is only valid with a slug ("Invalid metadata" after
        // the download otherwise); the project id is a stable fallback.
        pack->slug=slug.isEmpty()?projectId:slug;
        m_installInstance=key;
        return runInstall(new ModrinthInstallTask(instance,folder,pack,version));
    }
    QVariantMap editorDetails()const{return m_editorDetails;}
    QString editorInstanceKey()const{return m_editorKey;}
    Q_INVOKABLE QVariantMap instanceDetails(const QString &key)const {return details(key,true);}
    QVariantMap details(const QString &key,bool parseNow)const {
        auto *instance=lookup(key);if(!instance)return {{"key",key},{"error",pgTr("Instance unavailable")}};
        auto data=InstanceEditorFiles::snapshot(instance->instanceRoot(),editorFolders(instance));
        auto mods=data.value("mods").toList();
        for(auto &entry:mods){auto row=entry.toMap();QFileInfo file(QUrl(row.value("source").toString()).toLocalFile());
            const auto cacheKey=modCacheKey(file);
            if(!m_modDisplayCache.contains(cacheKey)) {
                if(parseNow)parseMod(file);
                // Each one opens a jar. The editor shows file names until parseQueuedMods is done.
                else{if(!m_modParseQueue.contains(file.absoluteFilePath()))m_modParseQueue.append(file.absoluteFilePath());m_modParser->start();}
            }
            const auto info=m_modDisplayCache.value(cacheKey);for(auto it=info.begin();it!=info.end();++it)if(!it.value().toString().isEmpty())row.insert(it.key(),it.value());entry=row;
        }data.insert("mods",mods);
        auto *settings=instance->settings();
        data.insert("key",key);data.insert("name",instance->name());data.insert("notes",instance->notes());
        data.insert("javaPath",settings->get("JavaPath").toString());data.insert("javaArgs",settings->get("JvmArgs").toString());
        data.insert("useDefaultMemory",!settings->get("OverrideMemory").toBool());data.insert("memoryMiB",settings->get("MaxMemAlloc").toInt());
        data.insert("running",instance->isRunning());return data;
    }
    Q_INVOKABLE void watchInstance(const QString &key) {m_editorKey=key;refreshEditor();}
    Q_INVOKABLE void refreshEditor() {
        const auto old=m_editorDetails;
        if(m_editorKey.isEmpty())m_editorDetails.clear();else m_editorDetails=details(m_editorKey,false);
        const auto watched=m_editorWatcher->directories()+m_editorWatcher->files();if(!watched.isEmpty())m_editorWatcher->removePaths(watched);
        if(auto *instance=lookup(m_editorKey)) {
            QStringList paths{instance->instanceRoot()};
            for(const auto &path:editorFolders(instance))if(QFileInfo(path).exists())paths.append(path);
            const QDir game(instance->gameRoot());
            for(const auto &path:{QDir(instance->instanceRoot()).filePath("instance.cfg"),QDir(instance->instanceRoot()).filePath("mmc-pack.json"),game.filePath("servers.dat"),game.filePath("logs"),game.filePath("logs/latest.log"),game.filePath("crash-reports")})if(QFileInfo(path).exists())paths.append(path);
            paths.removeDuplicates();m_editorWatcher->addPaths(paths);
        }
        if(old!=m_editorDetails)emit editorDetailsChanged();
    }
    Q_INVOKABLE bool saveEditorSettings(const QString &key,const QVariantMap &patch) {
        auto *instance=lookup(key);if(!instance)return editorError(pgTr("Instance unavailable"));
        if(patch.contains("name") && patch.value("name").toString().trimmed().isEmpty())return editorError(pgTr("Enter an instance name"));
        if(patch.contains("memoryMiB") && (patch.value("memoryMiB").toInt()<128 || patch.value("memoryMiB").toInt()>1048576))return editorError(pgTr("Invalid memory allocation"));
        auto *settings=instance->settings();
        {
            SettingsObject::Lock lock(settings);
            if(patch.contains("name"))instance->setName(patch.value("name").toString().trimmed());
            if(patch.contains("notes"))instance->setNotes(patch.value("notes").toString());
            if(patch.contains("useDefaultMemory"))settings->set("OverrideMemory",!patch.value("useDefaultMemory").toBool());
            if(patch.contains("memoryMiB")) {
                const int memory=patch.value("memoryMiB").toInt();settings->set("OverrideMemory",true);settings->set("MaxMemAlloc",memory);
                if(settings->get("MinMemAlloc").toInt()>memory)settings->set("MinMemAlloc",memory);
            }
            if(patch.contains("javaPath")) {
                const auto value=patch.value("javaPath").toString().trimmed();settings->set("OverrideJavaLocation",!value.isEmpty());
                if(!value.isEmpty())settings->set("JavaPath",value);
            }
            if(patch.contains("javaArgs")) {
                const auto value=patch.value("javaArgs").toString();settings->set("OverrideJavaArgs",!value.isEmpty());
                if(!value.isEmpty())settings->set("JvmArgs",value);
            }
        }
        m_status=pgTr("Instance settings saved");refresh();refreshEditor();emit changed();return true;
    }
    Q_INVOKABLE bool importEditorAsset(const QString &key,const QString &bucket,const QUrl &source) {
        auto *instance=editableInstance(key);if(!instance)return false;
        auto *model=editorResourceModel(instance,bucket);if(!model || !source.isLocalFile())return editorError(pgTr("Choose a local mod or pack file"));
        const QFileInfo file(source.toLocalFile());const auto name=file.fileName();
        if(!file.isFile() || file.isSymLink() || !file.isReadable())return editorError(pgTr("Cannot read the selected file"));
        if(QFileInfo::exists(model->dir().filePath(name)) || QFileInfo::exists(model->dir().filePath(name+".disabled")))return editorError(pgTr("A file with this name is already installed"));
        if(!QDir().mkpath(model->dir().absolutePath()) || !model->installResource(file.absoluteFilePath()))return editorError(pgTr("Could not import ")+name);
        model->startWatching();refreshEditor();m_status=pgTr("Imported ")+name;emit changed();return true;
    }
    Q_INVOKABLE bool setEditorAssetEnabled(const QString &key,const QString &bucket,const QString &fileName,bool enabled) {
        auto *instance=editableInstance(key);if(!instance)return false;
        if(!editorResourceModel(instance,bucket))return editorError(pgTr("This entry cannot be enabled or disabled"));
        const auto path=editorAssetPath(instance,bucket,fileName);if(path.isEmpty())return editorError(pgTr("File is unavailable; refresh the list"));
        Resource resource{QFileInfo(path)};
        if(resource.enabled()!=enabled && !resource.enable(enabled?EnableAction::ENABLE:EnableAction::DISABLE))return editorError(pgTr("Could not change ")+fileName);
        refreshEditor();return true;
    }
    Q_INVOKABLE bool removeEditorAsset(const QString &key,const QString &bucket,const QString &fileName) {
        auto *instance=editableInstance(key);if(!instance)return false;
        const auto path=editorAssetPath(instance,bucket,fileName);if(path.isEmpty())return editorError(pgTr("File is unavailable; refresh the list"));
        if(!QFile::moveToTrash(path))return editorError(pgTr("Could not move this entry to Trash"));
        refreshEditor();m_status=pgTr("Moved to Trash");emit changed();return true;
    }
    Q_INVOKABLE void openEditorFolder(const QString &key,const QString &bucket) {
        auto *instance=lookup(key);if(!instance)return;
        const auto path=editorFolders(instance).value(bucket);if(path.isEmpty())return;
        if(QDir().mkpath(path))QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }
    Q_INVOKABLE void revealEditorAsset(const QString &key,const QString &bucket,const QString &fileName) {
        auto *instance=lookup(key);if(!instance)return;const auto path=editorAssetPath(instance,bucket,fileName);if(path.isEmpty())return;
#ifdef Q_OS_MACOS
        QProcess::startDetached(QStringLiteral("open"),QStringList{QStringLiteral("-R"),path});
#else
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).isDir()?path:QFileInfo(path).absolutePath()));
#endif
    }
    Q_INVOKABLE bool editServer(const QString &key,const QString &address,int removeIndex) {
        auto *instance=editableInstance(key);if(!instance)return false;QString error;
        if(!QDir().mkpath(instance->gameRoot()))return editorError(pgTr("Could not open the game directory"));
        if(!InstanceEditorFiles::changeServer(QDir(instance->gameRoot()).filePath("servers.dat"),address,removeIndex,error))return editorError(error);
        refreshEditor();return true;
    }
    Q_INVOKABLE void signIn(){
        if(m_app->getMSAClientID().trimmed().isEmpty()){m_status=pgTr("Microsoft sign-in needs a registered client ID. Open Settings to configure it.");emit changed();return;}
        if(m_loginTask)return;
        m_loginAccount=MinecraftAccount::createBlankMSA();
        auto *task=new AuthFlow(m_loginAccount->accountData(),AuthFlow::Action::DeviceCode);m_loginTask=task;
        m_loginCode.clear();m_loginUrl.clear();m_status=pgTr("Preparing Microsoft sign-in");emit changed();
        connect(task,&AuthFlow::authorizeWithBrowserWithExtra,this,[this](QString url,QString code,int){m_loginUrl=url;m_loginCode=code;emit changed();});
        connect(task,&Task::status,this,[this](const QString &status){m_status=status;emit changed();});
        connect(task,&Task::succeeded,this,[this,task]{
            auto *accounts=m_app->accounts();int existing=-1;
            for(int i=0;i<accounts->count();++i)if(accounts->at(i)->profileId()==m_loginAccount->profileId())existing=i;
            if(existing>=0)accounts->removeAccount(accounts->index(existing,0));
            accounts->addAccount(m_loginAccount);accounts->setDefaultAccount(m_loginAccount);
            m_loginTask=nullptr;task->deleteLater();setOfflineMode(false);m_status=pgTr("Microsoft account added");emit changed();
        });
        connect(task,&Task::failed,this,[this,task](const QString &reason){m_status=pgTr("Sign-in failed: ")+reason;m_loginTask=nullptr;task->deleteLater();emit changed();});
        connect(task,&Task::aborted,this,[this,task]{m_status=pgTr("Sign-in cancelled");m_loginTask=nullptr;task->deleteLater();emit changed();});
        task->start();
    }
    bool signingIn()const{return !m_loginTask.isNull();}
    Q_INVOKABLE void copyLoginCode(){QApplication::clipboard()->setText(m_loginCode);}
    QString loginQr()const {
        if(m_loginUrl.isEmpty())return {};
        QUrl url(m_loginUrl);if(!m_loginCode.isEmpty()){QUrlQuery query(url);query.addQueryItem("otc",m_loginCode);url.setQuery(query);}
        auto *qr=QRcode_encodeString(url.toString().toUtf8().constData(),0,QR_ECLEVEL_M,QR_MODE_8,1);if(!qr)return {};
        const int n=qr->width;QImage image((n+8)*4,(n+8)*4,QImage::Format_RGB32);image.fill(Qt::white);
        QPainter painter(&image);painter.setPen(Qt::NoPen);painter.setBrush(Qt::black);
        for(int y=0;y<n;++y)for(int x=0;x<n;++x)if(qr->data[y*n+x]&1)painter.drawRect((x+4)*4,(y+4)*4,4,4);
        painter.end();QRcode_free(qr);QByteArray png;QBuffer buffer(&png);buffer.open(QIODevice::WriteOnly);image.save(&buffer,"PNG");return "data:image/png;base64,"+QString::fromLatin1(png.toBase64());
    }
    QString loginCode()const{return m_loginCode;}
    QString loginUrl()const{return m_loginUrl;}
    Q_INVOKABLE void cancelSignIn(){if(m_loginTask)m_loginTask->abort();}
    QString currentAccountName()const{auto a=m_app->accounts()->defaultAccount();return a?a->profileName():QString();}
    QVariantList savedAccounts()const {
        QVariantList rows;auto *accounts=m_app->accounts();
        for(int i=0;i<accounts->count();++i){auto a=accounts->at(i);rows.append(QVariantMap{{"id",a->internalId()},{"name",a->profileName()},{"selected",a==accounts->defaultAccount()},{"type",a->typeString()}});}return rows;
    }
    Q_INVOKABLE void selectSavedAccount(const QString &id){auto *accounts=m_app->accounts();for(int i=0;i<accounts->count();++i)if(accounts->at(i)->internalId()==id){accounts->setDefaultAccount(accounts->at(i));setOfflineMode(false);emit changed();return;}}
    Q_INVOKABLE void removeSavedAccount(const QString &id){auto *accounts=m_app->accounts();for(int i=0;i<accounts->count();++i)if(accounts->at(i)->internalId()==id){accounts->removeAccount(accounts->index(i,0));if(!accounts->defaultAccount() && accounts->count())accounts->setDefaultAccount(accounts->at(0));if(!accounts->count())setOfflineMode(true);emit changed();return;}}
    Q_INVOKABLE void openAccounts(){m_app->ShowGlobalSettings(nullptr,"accounts");}
    Q_INVOKABLE void openCoreSettings(){m_app->ShowGlobalSettings(nullptr);}
    // ---- Settings page: core (Prism) settings, Java, updates, priority ----
    // Read/write a registered global setting by key (JvmArgs, PreLaunchCommand,
    // MinecraftWinWidth, UseDiscreteGpu, CustomVersionType, …). Unknown keys
    // are ignored rather than created.
    Q_INVOKABLE QVariant coreSetting(const QString &key)const{auto settings=m_app->settings();return settings->contains(key)?settings->get(key):QVariant();}
    Q_INVOKABLE void setCoreSetting(const QString &key,const QVariant &value){auto settings=m_app->settings();if(settings->contains(key))settings->set(key,value);}
    Q_INVOKABLE QString localFilePath(const QUrl &url)const{return url.toLocalFile();}
    // ---- Settings page: storage ----
    // A folder setting ("InstanceDir", "JavaDir") as a full path; relative ones are under the data folder.
    Q_INVOKABLE QString storageFolder(const QString &key)const{return QDir::cleanPath(QDir::current().absoluteFilePath(m_app->settings()->get(key).toString()));}
    Q_INVOKABLE void openStorageFolder(const QString &key){const auto path=storageFolder(key);if(QDir().mkpath(path))QDesktopServices::openUrl(QUrl::fromLocalFile(path));}
    // New instances go to the chosen folder. Nothing is moved: the previous folder
    // stays listed as an additional one, so its instances keep working where they are.
    // Both return what went wrong; empty on success.
    Q_INVOKABLE QString setInstanceFolder(const QUrl &folder){
        const QString chosen=folder.toLocalFile();
        if(!m_app->updatesAreAllowed() || installing())return pgTr("Stop the running game and finish installations before changing this folder.");
        if(const auto problem=folderProblem(chosen);!problem.isEmpty())return problem;
        if(QFileInfo::exists(QDir(chosen).filePath("instance.cfg")))return pgTr("This folder is an instance. Choose the folder that should hold instances.");
        auto settings=m_app->settings();
        const QString current=settings->get("InstanceDir").toString(),target=FS::NormalizePath(chosen);
        const auto same=[&target](const QString &dir){return QDir(dir).canonicalPath()==QDir(target).canonicalPath();};
        if(same(current))return {};
        QStringList additional=settings->get("AdditionalInstanceDirs").toStringList();
        additional.removeIf(same);
        if(holdsInstances(current) && !additional.contains(current))additional.append(current);
        settings->set("AdditionalInstanceDirs",additional);
        settings->set("InstanceDir",target);
        m_refreshSoon->start();
        return {};
    }
    Q_INVOKABLE QString setJavaFolder(const QUrl &folder){
        if(const auto problem=folderProblem(folder.toLocalFile());!problem.isEmpty())return problem;
        m_app->settings()->set("JavaDir",FS::NormalizePath(folder.toLocalFile()));
        return {};
    }
    // The game discards an options.txt without a version line, wherever it sits.
    Q_INVOKABLE QVariantMap inspectOptionsFile(const QString &path)const{
        QVariantMap info{{"name",QFileInfo(path).fileName()},{"exists",false},{"version",0}};
        QFile file(path);
        if(path.isEmpty()||!file.open(QIODevice::ReadOnly|QIODevice::Text))return info;
        info["exists"]=true;
        while(!file.atEnd()){
            const auto line=QString::fromUtf8(file.readLine()).trimmed();
            if(line.startsWith(QStringLiteral("version:"))){info["version"]=line.mid(8).toInt();break;}
        }
        return info;
    }
    // Detected Java runtimes: [{path, version, arch}], refreshed on request.
    Q_INVOKABLE QVariantList javaInstalls()const{return m_javaInstalls;}
    Q_INVOKABLE bool javaScanning()const{return m_javaScanning;}
    Q_INVOKABLE void refreshJavaInstalls(){
        auto *list=m_app->javalist();if(!list||m_javaScanning)return;
        auto task=list->getLoadTask(true);if(!task)return;
        m_javaScanning=true;emit changed();
        connect(task.get(),&Task::finished,this,[this,list]{
            m_javaInstalls.clear();
            for(int i=0;i<list->count();i++) {
                const auto java=std::dynamic_pointer_cast<JavaInstall>(list->at(i));
                if(java)m_javaInstalls.append(QVariantMap{{"path",java->path},{"version",java->id.toString()},{"arch",java->arch}});
            }
            m_javaScanning=false;emit changed();
        },Qt::SingleShotConnection);
        if(!task->isRunning())task->start();
    }
    // Launcher updates (Prism's external updater; absent in some builds).
    Q_INVOKABLE bool updaterAvailable()const{return m_app->updater()!=nullptr;}
    Q_INVOKABLE bool autoUpdateChecks()const{auto *updater=m_app->updater();return updater&&updater->getAutomaticallyChecksForUpdates();}
    Q_INVOKABLE void setAutoUpdateChecks(bool on){if(auto *updater=m_app->updater())updater->setAutomaticallyChecksForUpdates(on);}
    Q_INVOKABLE int updateCheckHours()const{auto *updater=m_app->updater();return updater?int(updater->getUpdateCheckInterval()/3600):24;}
    Q_INVOKABLE void setUpdateCheckHours(int hours){if(auto *updater=m_app->updater())updater->setUpdateCheckInterval(hours*3600.0);}
    // Update alerts: off, an automatic check only records the update; the
    // Settings badge and its "update available" row show it instead.
    Q_INVOKABLE bool updateAlerts()const{auto *updater=m_app->updater();return !updater || updater->getShowsUpdateAlerts();}
    Q_INVOKABLE void setUpdateAlerts(bool on){if(auto *updater=m_app->updater())updater->setShowsUpdateAlerts(on);}
    // The newer version found by the last check (empty when up to date).
    QString availableUpdate()const{auto *updater=m_app->updater();return updater?updater->availableVersion():QString();}
    Q_INVOKABLE void installAvailableUpdate(){if(auto *updater=m_app->updater())updater->offerAvailableUpdate();}
    Q_INVOKABLE void checkForUpdates(){
        if(auto *updater=m_app->updater()){updater->checkForUpdates();m_status=pgTr("Checking for updates…");}
        else m_status=pgTr("Updates are not available in this build.");
        emit changed();
    }
    Q_INVOKABLE QString launcherVersion()const{return BuildConfig.printableVersionString();}
    // Game process priority (Windows): 0 below normal, 1 normal, 2 above
    // normal, 3 high. Applied once the launched game's process id is known.
    Q_INVOKABLE void setProcessPriority(int priority){m_processPriority=qBound(0,priority,3);}
    Q_INVOKABLE bool isRunning(const QString &key)const{auto *instance=lookup(key);return instance&&instance->isRunning();}
    // macOS 27's system typeface (SF Pro) if installed. Apple licenses it for
    // Apple platforms only, so it is never bundled; empty when absent.
    static QString macSystemFontFamily(){
        const auto families=QFontDatabase::families();
        for(const auto &name:{QStringLiteral("SF Pro"),QStringLiteral("SF Pro Text"),QStringLiteral("SF Pro Display"),QStringLiteral(".AppleSystemUIFont")})
            if(families.contains(name))return name;
        return {};
    }
    Q_INVOKABLE QString systemFontFamily()const{return macSystemFontFamily();}
    // Core language (Prism's dialogs), replacing the setup wizard's page:
    // [{key, name}] from the translations index, which loads in the background.
    Q_INVOKABLE QVariantList languages()const{
        QVariantList result;auto *model=m_app->translations();if(!model)return result;
        for(int row=0;row<model->rowCount();row++) {
            const auto index=model->index(row,0);
            result.append(QVariantMap{{"key",model->data(index,Qt::UserRole)},{"name",model->data(index,Qt::DisplayRole)}});
        }
        return result;
    }
    Q_INVOKABLE QString currentLanguage()const{return m_app->settings()->get("Language").toString();}
    Q_INVOKABLE void setLanguage(const QString &key){
        m_app->settings()->set("Language",key);
        if(auto *model=m_app->translations()){model->selectLanguage(key);model->updateLanguage(key);}
        applyInterfaceLanguage(key);
    }
    int languageRevision()const{return m_languageRevision;}
    // The frontend's own text (Prism's dialogs use Prism's translations).
    // Simplified Chinese for zh_CN/zh_SG/zh_Hans; anything else stays English.
    void applyInterfaceLanguage(const QString &key){
        QCoreApplication::removeTranslator(&m_interfaceTranslator);
        const bool simplified=key.startsWith("zh") && !key.contains("TW") && !key.contains("HK") && !key.contains("MO") && !key.contains("Hant");
        if(simplified && m_interfaceTranslator.load(QStringLiteral(":/qt/qml/ProjectGlass/i18n/projectglass_zh_CN.qm")))
            QCoreApplication::installTranslator(&m_interfaceTranslator);
        ++m_languageRevision;emit languageChanged();
    }
    // Colour panel eyedropper: picks a colour anywhere on the screen.
    Q_INVOKABLE void pickScreenColor(){
        QPointer<PrismBridge> self(this);
        ScreenColorPicker::pick([self](const QColor &color){if(self)emit self->screenColorPicked(color.name());});
    }
    // The only QWidget UI left is Prism's dialogs (core settings, prompts).
    // Style them like the launcher: grouped rounded panels, capsule-ish
    // controls, the theme accent for selection, checks and the default button.
    Q_INVOKABLE void setWidgetStyle(const QString &accent,bool dark){
        const QString bg=dark?"#1C1C1E":"#F2F2F7",panel=dark?"#2C2C2E":"#FFFFFF",field=dark?"#1C1C1E":"#FFFFFF",
                      ink=dark?"#F5F5F7":"#1D1D1F",muted=dark?"#98989D":"#6E6E73",line=dark?"#3A3A3C":"#D1D1D6",
                      control=dark?"#3A3A3C":"#E5E5EA",controlHover=dark?"#48484A":"#D8D8DD";
        const QString symbols=QStringLiteral(":/qt/qml/ProjectGlass/assets/symbols/");
        const QString arrow=symbols+(dark?"chevron.up.chevron.down.white.svg":"chevron.up.chevron.down.svg");
        QString css=QStringLiteral(R"(
QWidget { color: %ink%; font-size: 13px; selection-background-color: %accent%; selection-color: white; }
QDialog, QMainWindow { background: %bg%; }
QLabel, QCheckBox, QRadioButton { background: transparent; }
QAbstractScrollArea, QScrollArea > QWidget > QWidget { background: transparent; border: none; }
QGroupBox { background: %panel%; border: none; border-radius: 12px; margin-top: 24px; padding: 14px 12px 10px 12px; font-weight: 600; }
QGroupBox::title { subcontrol-origin: margin; subcontrol-position: top left; left: 8px; top: 2px; color: %muted%; background: transparent; }
QGroupBox > QLabel, QGroupBox > QCheckBox, QGroupBox > QRadioButton { font-weight: normal; }
QPushButton { background: %control%; border: none; border-radius: 8px; padding: 6px 16px; min-height: 18px; font-weight: normal; }
QPushButton:hover { background: %controlHover%; }
QPushButton:pressed { background: %line%; }
QPushButton:default { background: %accent%; color: white; }
QPushButton:disabled { color: %muted%; }
QLineEdit, QAbstractSpinBox, QComboBox, QPlainTextEdit, QTextEdit { background: %field%; border: 1px solid %line%; border-radius: 8px; padding: 5px 8px; font-weight: normal; }
QLineEdit:focus, QAbstractSpinBox:focus, QComboBox:focus, QPlainTextEdit:focus, QTextEdit:focus { border-color: %accent%; }
QAbstractSpinBox::up-button, QAbstractSpinBox::down-button { width: 0; border: none; }
QComboBox::drop-down { border: none; width: 26px; }
QComboBox::down-arrow { image: url(%arrow%); width: 12px; height: 12px; }
QComboBox QAbstractItemView { background: %panel%; border: 1px solid %line%; border-radius: 10px; padding: 4px; outline: 0; selection-background-color: %accent%; }
QCheckBox { spacing: 8px; font-weight: normal; }
QCheckBox::indicator { width: 16px; height: 16px; border-radius: 4px; border: 1px solid %line%; background: %field%; }
QCheckBox::indicator:checked { background: %accent%; border-color: %accent%; image: url(%check%); }
QRadioButton { spacing: 8px; font-weight: normal; }
QRadioButton::indicator { width: 16px; height: 16px; border-radius: 8px; border: 1px solid %line%; background: %field%; }
QRadioButton::indicator:checked { border: 5px solid %accent%; background: white; }
QListView, QTreeView, QTableView { background: %panel%; border: none; border-radius: 10px; padding: 4px; outline: 0; }
QListView::item, QTreeView::item { border-radius: 6px; padding: 4px 6px; }
QListView::item:hover:!selected, QTreeView::item:hover:!selected { background: %control%; }
QListView::item:selected, QTreeView::item:selected { background: %accent%; color: white; }
QHeaderView::section { background: transparent; border: none; border-bottom: 1px solid %line%; padding: 4px 6px; color: %muted%; }
QTabWidget::pane { border: none; background: transparent; }
QTabBar::tab { background: %control%; border-radius: 7px; padding: 5px 14px; margin: 2px; }
QTabBar::tab:selected { background: %accent%; color: white; }
QSlider::groove:horizontal { height: 4px; background: %line%; border-radius: 2px; }
QSlider::sub-page:horizontal { background: %accent%; border-radius: 2px; }
QSlider::handle:horizontal { background: white; width: 20px; height: 20px; margin: -8px 0; border-radius: 10px; }
QScrollBar:vertical { background: transparent; width: 10px; margin: 2px; }
QScrollBar:horizontal { background: transparent; height: 10px; margin: 2px; }
QScrollBar::handle { background: %line%; border-radius: 3px; min-height: 30px; min-width: 30px; }
QScrollBar::add-line, QScrollBar::sub-line { width: 0; height: 0; }
QScrollBar::add-page, QScrollBar::sub-page { background: transparent; }
QMenu { background: %panel%; border: 1px solid %line%; border-radius: 10px; padding: 5px; }
QMenu::item { padding: 5px 20px 5px 24px; border-radius: 6px; }
QMenu::item:selected { background: %accent%; color: white; }
QMenu::separator { height: 1px; background: %line%; margin: 5px 10px; }
QToolButton { background: transparent; border: none; border-radius: 6px; padding: 4px; }
QToolButton:hover { background: %control%; }
QToolTip { background: %panel%; color: %ink%; border: 1px solid %line%; border-radius: 6px; padding: 4px 8px; }
)");
        const QList<QPair<QString,QString>> tokens{{"%bg%",bg},{"%panel%",panel},{"%field%",field},{"%ink%",ink},{"%muted%",muted},
            {"%line%",line},{"%controlHover%",controlHover},{"%control%",control},{"%accent%",accent},{"%arrow%",arrow},
            {"%check%",symbols+"checkmark.white.svg"}};
        for(const auto &token:tokens)css.replace(token.first,token.second);
        qApp->setStyleSheet(css);
    }
    Q_INVOKABLE void openLogs(){QDesktopServices::openUrl(QUrl::fromLocalFile(dataRoot()+"/logs"));}
signals:
    void localPackImportFinished(bool success, const QString &message);
    void screenColorPicked(const QString &color);
    void editorDetailsChanged();
    void instanceReady(const QString &key);
    void sharedInstanceCreated(const QString &key);
    void sharedInstanceFailed(const QString &reason);
    void instancesChanged();
    void changed();
    void languageChanged();
    void updateStateChanged();
private:
    QTranslator m_interfaceTranslator;int m_languageRevision=0;
    bool m_optimizeBeforeLaunch=false,m_optimizingMemory=false;
    mutable QHash<QString,QVariantMap> m_modDisplayCache;
    QPointer<AccountList> m_observedAccounts;
    QPointer<ExternalUpdater> m_observedUpdater;
    QPointer<AuthFlow> m_loginTask;
    MinecraftAccountPtr m_loginAccount;
    QString m_loginCode,m_loginUrl;
    bool editorError(const QString &message){m_status=message;emit changed();return false;}
    static QString folderProblem(const QString &path){
        if(path.isEmpty())return pgTr("Choose a folder on this computer.");
        if(FS::checkProblemticPathJava(QDir(path)))return pgTr("Java cannot start from a path that contains “!”. Choose another folder.");
        QTemporaryFile probe(QDir(path).filePath("XXXXXX.tmp"));
        if(!QDir().mkpath(path) || !probe.open())return pgTr("This folder cannot be written to. Choose another folder.");
        return {};
    }
    static bool holdsInstances(const QString &path){
        const QDir root(path);
        for(const auto &name:root.entryList(QDir::Dirs|QDir::NoDotAndDotDot))if(QFileInfo::exists(root.filePath(name+"/instance.cfg")))return true;
        return false;
    }
    static QString modCacheKey(const QFileInfo &file){return file.absoluteFilePath()+":"+QString::number(file.size())+":"+QString::number(file.lastModified().toMSecsSinceEpoch());}
    void parseMod(const QFileInfo &file)const{
        QVariantMap info;Mod mod(file);
        if(ModUtils::process(mod)){info.insert("name",mod.name());info.insert("version",mod.version());auto icon=mod.icon(QSize(64,64),Qt::KeepAspectRatio);if(!icon.isNull()){QByteArray bytes;QBuffer out(&bytes);out.open(QIODevice::WriteOnly);icon.save(&out,"PNG");info.insert("icon","data:image/png;base64,"+QString::fromLatin1(bytes.toBase64()));}}
        m_modDisplayCache.insert(modCacheKey(file),info);
    }
    // A few jars per turn of the event loop, so hundreds of them never stop the
    // window or the reading of a starting game's output.
    void parseQueuedMods(){
        QElapsedTimer turn;turn.start();
        while(!m_modParseQueue.isEmpty() && !turn.hasExpired(12))parseMod(QFileInfo(m_modParseQueue.takeFirst()));
        if(m_modParseQueue.isEmpty()){m_modParser->stop();m_editorReload->start();}
    }
    // A running game writes its log all the time and a refresh covers every mod,
    // so it runs at most once a second then.
    void queueEditorReload(){
        auto *instance=lookup(m_editorKey);const bool running=instance && instance->isRunning();
        if(running && m_editorReload->isActive())return;
        m_editorReload->setInterval(running?1000:120);m_editorReload->start();
    }
    MinecraftInstance *editableInstance(const QString &key) {
        auto *instance=lookup(key);
        if(!instance || instance->isRunning() || (installing() && m_installInstance==key)){editorError(pgTr("Stop the instance and finish its installation before changing files"));return nullptr;}
        return instance;
    }
    static QMap<QString,QString> editorFolders(MinecraftInstance *instance) {
        return {{"game",instance->gameRoot()},{"mods",instance->modsRoot()},{"resourcePacks",instance->resourcePacksDir()},
                {"shaderPacks",instance->shaderPacksDir()},{"worlds",instance->worldDir()},{"screenshots",QDir(instance->gameRoot()).filePath("screenshots")}};
    }
    static ResourceFolderModel *editorResourceModel(MinecraftInstance *instance,const QString &bucket) {
        if(bucket=="mods")return instance->loaderModList();if(bucket=="resourcePacks")return instance->resourcePackList();
        if(bucket=="shaderPacks")return instance->shaderPackList();return nullptr;
    }
    static QString editorAssetPath(MinecraftInstance *instance,const QString &bucket,const QString &name) {
        if(name.isEmpty() || name=="." || name==".." || name.contains('/') || name.contains('\\'))return {};
        const auto directory=editorFolders(instance).value(bucket);if(directory.isEmpty() || bucket=="game")return {};
        const QFileInfo file(QDir(directory).filePath(name));if(!file.exists() || file.isSymLink())return {};
        return file.absoluteFilePath();
    }
    // Polls the launch task until the game process exists (auth and
    // downloads come first), then sets its Windows priority class.
    void applyProcessPriority(MinecraftInstance *instance){
#ifdef Q_OS_WIN
        if(m_processPriority==1)return;
        static const DWORD classes[]={BELOW_NORMAL_PRIORITY_CLASS,NORMAL_PRIORITY_CLASS,ABOVE_NORMAL_PRIORITY_CLASS,HIGH_PRIORITY_CLASS};
        const DWORD priorityClass=classes[m_processPriority];
        QPointer<MinecraftInstance> target(instance);
        auto *timer=new QTimer(this);timer->setInterval(500);
        auto attempts=std::make_shared<int>(0);
        connect(timer,&QTimer::timeout,this,[target,timer,attempts,priorityClass]{
            auto *task=target?target->getLaunchTask():nullptr;
            const qint64 pid=task?task->pid():0;
            if(pid>0) {
                if(HANDLE process=OpenProcess(PROCESS_SET_INFORMATION,FALSE,DWORD(pid))) {SetPriorityClass(process,priorityClass);CloseHandle(process);}
                timer->deleteLater();return;
            }
            if(!target || ++*attempts>600)timer->deleteLater(); // give up after 5 minutes
        });
        timer->start();
#else
        Q_UNUSED(instance);
#endif
    }
    // Component uid → version straight from the instance's mmc-pack.json,
    // for when its PackProfile has not been loaded.
    static QHash<QString,QString> manifestComponents(MinecraftInstance *instance){
        QHash<QString,QString> versions;
        QFile file(QDir(instance->instanceRoot()).filePath("mmc-pack.json"));
        if(!file.open(QIODevice::ReadOnly))return versions;
        const auto components=QJsonDocument::fromJson(file.readAll()).object().value("components").toArray();
        for(const auto &value:components) {
            const auto component=value.toObject();
            versions.insert(component.value("uid").toString(),component.value("version").toString());
        }
        return versions;
    }
    void reportSharedInstance(){
        if(!m_sharedInstalled || m_sharedKey.isEmpty())return;
        m_sharedCreating=false;emit sharedInstanceCreated(m_sharedKey);
    }
    void failSharedInstance(const QString &reason){
        if(!m_sharedCreating)return;
        m_sharedCreating=false;emit sharedInstanceFailed(reason);
    }
    bool runInstall(Task *task){
        task->setParent(this);m_installTask=task;m_installProgress=0;
        connect(task,&Task::abortStatusChanged,this,[this](bool){emit changed();});
        connect(task,&Task::status,this,[this](const QString &status){m_status=status;emit changed();});
        connect(task,&Task::progress,this,[this](qint64 current,qint64 total){m_installProgress=total>0?qBound(0.0,double(current)/double(total),1.0):0;emit changed();});
        connect(task,&Task::succeeded,this,[this,task]{m_installTask=nullptr;m_installInstance.clear();m_installProgress=1;m_status=pgTr("Installation complete");m_sharedInstalled=true;refresh();refreshEditor();emit changed();if(m_sharedCreating)reportSharedInstance();task->deleteLater();});
        connect(task,&Task::failed,this,[this,task](const QString &reason){m_installTask=nullptr;m_installInstance.clear();m_status=pgTr("Installation failed · ")+reason;failSharedInstance(m_status);emit changed();task->deleteLater();});
        connect(task,&Task::aborted,this,[this,task]{m_installTask=nullptr;m_installInstance.clear();m_status=pgTr("Installation cancelled");failSharedInstance(m_status);emit changed();task->deleteLater();});
        m_status=pgTr("Preparing installation…");emit changed();task->start();return true;
    }
    MinecraftInstance *lookup(const QString &key)const{return key.startsWith("prism:") && m_app->instances()?m_app->instances()->getInstanceById(key.mid(6)):nullptr;}
    QFileSystemWatcher *m_editorWatcher=nullptr;
    QTimer *m_editorReload=nullptr;
    QTimer *m_modParser=nullptr;mutable QStringList m_modParseQueue;
    QString m_editorKey;QVariantMap m_editorDetails;
    QString m_launchKey;QDateTime m_launchStarted;std::function<void()> m_launchAgain;bool m_launchRetried=false;
    QTimer *m_refreshSoon=nullptr;
    QPointer<InstanceList> m_observedInstances;
    QString m_pendingInstance;
    bool m_sharedCreating=false,m_sharedInstalled=false;QString m_sharedKey;
    QString m_installInstance;
    QPointer<Task> m_installTask;double m_installProgress=0;
    bool m_importingLocalPack=false;
    QVariantList m_javaInstalls;bool m_javaScanning=false;int m_processPriority=1;
    Application *m_app;QString m_status;QVariantList m_instances;
};
