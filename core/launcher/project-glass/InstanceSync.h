// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMessageAuthenticationCode>
#include <QNetworkAccessManager>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QNetworkReply>
#include <QPointer>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUuid>
#include <QTcpServer>
#include <QTcpSocket>
#include <QThread>
#include <QTimer>
#include <QUdpSocket>
#include <QVariantMap>
#include <functional>
#include <memory>
#include "Application.h"
#include "BuildConfig.h"
#include "PgTranslate.h"
#include "SyncFiles.h"
#include "minecraft/MinecraftInstance.h"
#include "minecraft/MinecraftLoadAndCheck.h"
#include "minecraft/PackProfile.h"
#include "modplatform/helpers/HashUtils.h"
#include "tasks/SequentialTask.h"

// Shares an instance's content list with another computer on the same network:
// game components plus, for each mod, resource pack and shader pack, a public
// download address and its SHA-512. The sharer looks each file up on Modrinth by
// SHA-512, then on CurseForge by fingerprint. The receiving side downloads the
// files itself from the official CDNs and verifies them, so it needs no API key.
//
// A file neither site offers is marked "direct": the receiver may take it from
// the sharer over TCP. That is code from another computer instead of from a
// site, so it happens only if the receiver turns it on for this sync, after
// seeing the file names.
//
// Protocol: the receiver broadcasts a hash of the PIN over UDP and the sharer
// answers with its TCP port. Over TCP the sharer sends a nonce, the receiver
// answers HMAC-SHA256(PIN, nonce), and the sharer sends the manifest with an
// HMAC over the nonce and manifest, showing that it holds the PIN too, plus a
// ticket for direct files. Each direct file is one more connection: nonce, then
// "file <id> <HMAC(ticket, nonce|id)>". Five wrong answers end the share.
// A six-digit PIN keeps out mistakes and casual neighbours, not someone set on
// attacking the network: its hashes can be searched offline.
//
// A receiver without a target instance gets a new one: the core installs the
// shared game and loader, then the content downloads into it.
class InstanceSync final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString pin READ pin NOTIFY changed)
    Q_PROPERTY(int secondsLeft READ secondsLeft NOTIFY changed)
    Q_PROPERTY(QString address READ address NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QVariantMap preview READ preview NOTIFY changed)
    Q_PROPERTY(int completed READ completed NOTIFY changed)
    Q_PROPERTY(int total READ total NOTIFY changed)
    Q_PROPERTY(QStringList failures READ failures NOTIFY changed)
   public:
    using Resolver = std::function<MinecraftInstance*(const QString&)>;
    // game version, loader name ("Vanilla", "Fabric"…), loader version, instance name
    using Creator = std::function<bool(const QString&, const QString&, const QString&, const QString&)>;
    explicit InstanceSync(Application* app, Resolver resolver, Creator creator, QObject* parent = nullptr)
        : QObject(parent), m_app(app), m_resolver(std::move(resolver)), m_creator(std::move(creator))
    {
        m_tick.setInterval(1000);
        connect(&m_tick, &QTimer::timeout, this, [this] {
            if (--m_secondsLeft <= 0) {
                stopServing();
                setState("expired", pgTr("This code has expired."));
            } else
                emit changed();
        });
        connect(&m_server, &QTcpServer::newConnection, this, &InstanceSync::acceptClient);
        connect(&m_discovery, &QUdpSocket::readyRead, this, &InstanceSync::answerDiscovery);
    }
    ~InstanceSync() override { cancel(); }

    QString state() const { return m_state; }
    QString pin() const { return m_pin; }
    int secondsLeft() const { return m_secondsLeft; }
    QString address() const { return m_address; }
    QString message() const { return m_message; }
    QVariantMap preview() const { return m_preview; }
    int completed() const { return m_completed; }
    int total() const { return m_downloads.size(); }
    QStringList failures() const { return m_failures; }

    // ---- Sharing side ----
    // kinds: any of "mods", "resourcepacks", "shaderpacks". Game versions always go along.
    Q_INVOKABLE void startShare(const QString& key, int minutes, bool singleUse, const QStringList& kinds)
    {
        cancel();
        if (m_state == "error") return;
        auto* instance = m_resolver(key);
        if (!instance) return setState("error", pgTr("Instance unavailable. Refresh the list."));
        m_singleUse = singleUse;
        m_lifetime = qBound(1, minutes, 30) * 60;
        setState("preparing", pgTr("Reading the instance…"));
        auto folders = contentFolders(instance);
        for (const auto& kind : folders.keys())
            if (!kinds.contains(kind)) folders.remove(kind);
        const int run = m_run;
        QJsonArray components = sharedComponents(instance->instanceRoot());
        const QString name = instance->name();
        runAsync([folders] { return scan(folders); }, [this, run, components, kinds, name](const QList<LocalFile>& files) {
            if (run == m_run) lookUpDownloads(files, components, kinds, name);
        });
    }

    // ---- Receiving side ----
    // A code is the six digits, or digits@host:port where broadcasts don't arrive.
    // An empty key creates a new instance from the share.
    Q_INVOKABLE void connectCode(const QString& key, const QString& code)
    {
        cancel();
        if (m_state == "error") return;
        m_targetKey = key;
        m_createNew = key.isEmpty();
        const auto match = QRegularExpression(QStringLiteral("^(\\d{6})(?:@([^:\\s]+):(\\d{1,5}))?$")).match(code.trimmed());
        if (!match.hasMatch()) return setState("error", pgTr("Enter the 6-digit code shown on the other computer."));
        m_pin = match.captured(1);
        setState("connecting", pgTr("Looking for the other computer…"));
        if (!match.captured(2).isEmpty()) return connectTo(match.captured(2), quint16(match.captured(3).toUInt()));
        discover();
    }
    // The sharer chose the content; the receiver only decides about the versions.
    Q_INVOKABLE void apply(bool syncVersions, bool allowDirect = false)
    {
        if (m_state == "review" && !allowDirect) m_downloads.removeIf([](const Download& file) { return file.direct; });
        if (m_state == "review" && m_createNew) return createInstance();
        auto* instance = m_resolver(m_targetKey);
        if (m_state != "review" || !instance || instance->isRunning()) return setState("error", pgTr("Stop the instance before syncing."));
        m_componentChanges = m_componentChanges && syncVersions;
        startDownloads(instance);
    }
    // From the core, once the new instance and its game files are in place.
    void instanceCreated(const QString& key)
    {
        if (m_state != "creating") return;
        auto* instance = m_resolver(key);
        if (!instance) return setState("error", pgTr("Instance unavailable. Refresh the list."));
        m_targetKey = key;
        m_createNew = false;
        const auto folders = contentFolders(instance);
        for (auto& file : m_downloads) file.folder = folders.value(file.kind);
        const auto mine = componentMap(sharedComponents(instance->instanceRoot()));
        const auto theirs = componentMap(m_manifest.value("components").toArray());
        m_componentChanges = false;
        for (auto it = theirs.begin(); it != theirs.end(); ++it)
            if (mine.value(it.key()).first != it.value().first) m_componentChanges = true;
        startDownloads(instance);
    }
    void creationFailed(const QString& reason)
    {
        if (m_state == "creating") setState("error", reason);
    }
    void startDownloads(MinecraftInstance* instance)
    {
        m_root = instance->instanceRoot();
        m_completed = 0;
        m_active = 0;
        m_next = 0;
        m_failures.clear();
        m_tempDir = QDir(m_root).filePath(".vitra-sync-tmp-" + QUuid::createUuid().toString(QUuid::WithoutBraces));
        if (!QDir().mkpath(m_tempDir)) {
            m_tempDir.clear();
            return setState("error", pgTr("Cannot create the sync download folder."));
        }
        setState("downloading", pgTr("Downloading…"));
        pump();
    }
    Q_INVOKABLE void cancel()
    {
        ++m_run;
        stopServing();
        if (m_gameFiles) m_gameFiles->abort();
        m_gameFiles.reset();
        const QString restoreError = restoreComponents();
        m_finder.reset();
        m_client.reset();
        for (auto& reply : m_replies)
            if (reply) reply->abort();
        m_replies.clear();
        for (auto& socket : m_peers)
            if (socket) socket->abort();
        m_peers.clear();
        m_direct.clear();
        m_ticket.clear();
        m_peerHost.clear();
        if (!m_tempDir.isEmpty()) QDir(m_tempDir).removeRecursively();
        m_tempDir.clear();
        m_pin.clear();
        m_address.clear();
        m_preview.clear();
        m_downloads.clear();
        m_moves.clear();
        m_renames.clear();
        m_failures.clear();
        m_completed = 0;
        setState(restoreError.isEmpty() ? "idle" : "error", restoreError);
    }

   signals:
    void changed();

   private:
    struct LocalFile {
        QString kind, name, path, sha512;
        bool enabled = true;
        bool directory = false;
        qint64 size = 0;
        QString url;  // from the folder's .index metadata, then the sites
        QString version;
        bool listed = false;  // a site knows this file: no need to ask the next one
    };
    struct Download {
        QString kind, folder, name, url, sha512;
        bool enabled = true;
        qint64 size = 0;
        QString tempPath;
        QString replaces;  // existing file to back up once this one is verified
        bool ok = false;
        bool direct = false;  // from the sharer, not from a site
        int directId = -1;
    };

    static constexpr quint16 DiscoveryPort = 47821;
    static constexpr qint64 MaxLine = 16 * 1024 * 1024;
    static constexpr qint64 MaxDirectFile = qint64(2) * 1024 * 1024 * 1024;
    static constexpr int MinecraftGameId = 432;

    void setState(const QString& state, const QString& message)
    {
        m_state = state;
        m_message = message;
        emit changed();
    }
    template <class Work, class Done>
    void runAsync(Work work, Done done)
    {
        auto result = std::make_shared<decltype(work())>();
        auto* thread = QThread::create([work, result] { *result = work(); });
        connect(thread, &QThread::finished, this, [result, done, thread] {
            done(*result);
            thread->deleteLater();
        });
        thread->start();
    }
    static QMap<QString, QString> contentFolders(MinecraftInstance* instance)
    {
        return { { "mods", instance->modsRoot() }, { "resourcepacks", instance->resourcePacksDir() }, { "shaderpacks", instance->shaderPacksDir() } };
    }
    static QByteArray fileHash(const QString& path)
    {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) return {};
        QCryptographicHash hash(QCryptographicHash::Sha512);
        return hash.addData(&file) ? hash.result().toHex() : QByteArray();
    }
    static QString activeName(const QString& name)
    {
        return name.endsWith(".disabled", Qt::CaseInsensitive) ? name.chopped(9) : name;
    }
    // Prism's download metadata, for files Modrinth doesn't know by hash.
    static QHash<QString, QString> indexedUrls(const QString& folder)
    {
        QHash<QString, QString> urls;
        const QDir index(QDir(folder).filePath(".index"));
        for (const auto& entry : index.entryInfoList({ "*.pw.toml" }, QDir::Files)) {
            QFile file(entry.filePath());
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
            const QString text = QString::fromUtf8(file.readAll());
            static const QRegularExpression filename(QStringLiteral("^filename\\s*=\\s*[\"'](.+)[\"']\\s*$"), QRegularExpression::MultilineOption);
            static const QRegularExpression url(QStringLiteral("^url\\s*=\\s*[\"'](.+)[\"']\\s*$"), QRegularExpression::MultilineOption);
            static const QRegularExpression fileId(QStringLiteral("^file-id\\s*=\\s*(\\d+)\\s*$"), QRegularExpression::MultilineOption);
            const QString name = filename.match(text).captured(1);
            if (name.isEmpty()) continue;
            QString address = url.match(text).captured(1);
            const qint64 id = fileId.match(text).captured(1).toLongLong();
            if (address.isEmpty() && id > 0)
                address = QStringLiteral("https://edge.forgecdn.net/files/%1/%2/%3").arg(id / 1000).arg(id % 1000).arg(QString::fromUtf8(QUrl::toPercentEncoding(name)));
            if (!address.isEmpty()) urls.insert(name, address);
        }
        return urls;
    }
    static QList<LocalFile> scan(const QMap<QString, QString>& folders)
    {
        QList<LocalFile> files;
        for (auto folder = folders.begin(); folder != folders.end(); ++folder) {
            const auto urls = indexedUrls(folder.value());
            for (const auto& entry : QDir(folder.value()).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
                const QString name = activeName(entry.fileName());
                const QString extension = QFileInfo(name).suffix().toLower();
                if (!entry.isDir() && extension != "jar" && extension != "litemod" && extension != "zip") continue;
                LocalFile file;
                file.kind = folder.key();
                file.name = name;
                file.path = entry.filePath();
                file.enabled = name == entry.fileName();
                file.directory = entry.isDir();
                file.size = entry.size();
                file.url = urls.value(name);
                if (!file.directory) file.sha512 = QString::fromLatin1(fileHash(entry.filePath()));
                files.append(file);
            }
        }
        return files;
    }
    static QJsonArray sharedComponents(const QString& root)
    {
        QJsonArray list;
        QFile file(QDir(root).filePath("mmc-pack.json"));
        if (!file.open(QIODevice::ReadOnly)) return list;
        for (const auto& value : QJsonDocument::fromJson(file.readAll()).object().value("components").toArray()) {
            const auto component = value.toObject();
            if (component.value("dependencyOnly").toBool()) continue;
            list.append(QJsonObject{ { "uid", component.value("uid") }, { "version", component.value("version") }, { "name", component.value("cachedName") } });
        }
        return list;
    }

    void lookUpDownloads(const QList<LocalFile>& files, const QJsonArray& components, const QStringList& kinds, const QString& name)
    {
        setState("preparing", pgTr("Finding download addresses…"));
        QJsonArray hashes;
        for (const auto& file : files)
            if (!file.sha512.isEmpty()) hashes.append(file.sha512);
        QNetworkRequest request(QUrl(QStringLiteral("https://api.modrinth.com/v2/version_files")));
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        request.setRawHeader("User-Agent", BuildConfig.USER_AGENT.toUtf8());
        const QByteArray body = QJsonDocument(QJsonObject{ { "hashes", hashes }, { "algorithm", "sha512" } }).toJson(QJsonDocument::Compact);
        auto* reply = m_app->network()->post(request, body);
        const int run = m_run;
        connect(reply, &QNetworkReply::finished, this, [this, reply, run, files, components, kinds, name] {
            reply->deleteLater();
            if (run != m_run) return;
            const auto found = QJsonDocument::fromJson(reply->readAll()).object();
            auto resolved = files;
            for (auto& file : resolved) {
                const auto version = found.value(file.sha512).toObject();
                for (const auto& candidate : version.value("files").toArray()) {
                    const auto object = candidate.toObject();
                    if (object.value("hashes").toObject().value("sha512").toString() == file.sha512) file.url = object.value("url").toString();
                }
                file.version = version.value("version_number").toString();
                file.listed = !version.isEmpty();
            }
            lookUpCurseForge(resolved, components, kinds, name);
        });
    }
    // What Modrinth doesn't have, by CurseForge's own file fingerprint.
    void lookUpCurseForge(const QList<LocalFile>& files, const QJsonArray& components, const QStringList& kinds, const QString& name)
    {
        QStringList paths;
        for (const auto& file : files)
            if (!file.listed && !file.directory) paths.append(file.path);
        const QString key = m_app->getFlameAPIKey();
        if (paths.isEmpty() || key.isEmpty()) return publish(files, components, kinds, name);
        setState("preparing", pgTr("Looking on CurseForge…"));
        const int run = m_run;
        runAsync(
            [paths] {
                QHash<QString, qint64> fingerprints;
                for (const auto& path : paths) {
                    QFile file(path);
                    if (file.open(QIODevice::ReadOnly)) fingerprints.insert(path, Hashing::hash(&file, Hashing::Algorithm::Murmur2).toLongLong());
                }
                return fingerprints;
            },
            [this, run, files, components, kinds, name, key](const QHash<QString, qint64>& fingerprints) {
                if (run != m_run) return;
                QJsonArray list;
                for (const auto fingerprint : fingerprints) list.append(fingerprint);
                QNetworkRequest request(QUrl(BuildConfig.FLAME_BASE_URL + QStringLiteral("/fingerprints/%1").arg(MinecraftGameId)));
                request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
                request.setRawHeader("User-Agent", BuildConfig.USER_AGENT.toUtf8());
                request.setRawHeader("x-api-key", key.toUtf8());
                auto* reply = m_app->network()->post(request, QJsonDocument(QJsonObject{ { "fingerprints", list } }).toJson(QJsonDocument::Compact));
                connect(reply, &QNetworkReply::finished, this, [this, reply, run, files, components, kinds, name, fingerprints] {
                    reply->deleteLater();
                    if (run != m_run) return;
                    QHash<qint64, QString> urls;
                    const auto data = QJsonDocument::fromJson(reply->readAll()).object().value("data").toObject();
                    for (const auto& value : data.value("exactMatches").toArray()) {
                        const auto file = value.toObject().value("file").toObject();
                        urls.insert(file.value("fileFingerprint").toInteger(), file.value("downloadUrl").toString());
                    }
                    auto resolved = files;
                    for (auto& file : resolved) {
                        const auto match = urls.constFind(fingerprints.value(file.path, -1));
                        if (file.listed || match == urls.cend()) continue;
                        // An empty address is the author's refusal of third-party
                        // downloads, whatever an older .index entry says.
                        file.url = *match;
                        file.listed = true;
                    }
                    publish(resolved, components, kinds, name);
                });
            });
    }
    void publish(const QList<LocalFile>& files, const QJsonArray& components, const QStringList& kinds, const QString& name)
    {
        QJsonArray entries, unavailable;
        for (const auto& file : files) {
            QJsonObject entry{ { "kind", file.kind }, { "name", file.name }, { "sha512", file.sha512 }, { "size", file.size }, { "enabled", file.enabled }, { "version", file.version } };
            if (!file.directory && !file.url.isEmpty() && allowedUrl(file.url)) {
                entry.insert("url", file.url);
            } else if (!file.directory && file.size <= MaxDirectFile) {
                entry.insert("direct", true);
                entry.insert("id", int(m_direct.size()));
                m_direct.append(file.path);
            } else {
                unavailable.append(QJsonObject{ { "kind", file.kind }, { "name", file.name } });
                continue;
            }
            entries.append(entry);
        }
        if (!m_direct.isEmpty()) m_ticket = QByteArray::number(QRandomGenerator::system()->generate64(), 16) + QByteArray::number(QRandomGenerator::system()->generate64(), 16);
        m_manifest = QJsonObject{ { "format", 2 }, { "name", name }, { "kinds", QJsonArray::fromStringList(kinds) }, { "components", components }, { "files", entries }, { "unavailable", unavailable } };
        m_preview = QVariantMap{ { "shared", int(entries.size()) }, { "unavailableCount", int(unavailable.size()) }, { "directCount", int(m_direct.size()) } };
        serve();
    }
    void serve()
    {
        if (!m_server.listen(QHostAddress::Any)) return setState("error", pgTr("Could not start sharing on this network."));
        m_discovery.bind(QHostAddress::AnyIPv4, DiscoveryPort, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);
        m_pin = QStringLiteral("%1").arg(QRandomGenerator::system()->bounded(1000000), 6, 10, QLatin1Char('0'));
        m_failedProofs = 0;
        m_secondsLeft = m_lifetime;
        m_address = lanAddress();
        if (!m_address.isEmpty()) m_address += QStringLiteral(":%1").arg(m_server.serverPort());
        m_tick.start();
        setState("sharing", QString());
    }
    static QString lanAddress()
    {
        for (const auto& interface : QNetworkInterface::allInterfaces()) {
            if (!(interface.flags() & QNetworkInterface::IsUp) || (interface.flags() & QNetworkInterface::IsLoopBack)) continue;
            for (const auto& entry : interface.addressEntries())
                if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol && !entry.broadcast().isNull()) return entry.ip().toString();
        }
        return {};
    }
    void stopServing()
    {
        m_tick.stop();
        m_server.close();
        m_discovery.close();
        m_secondsLeft = 0;
    }
    static QByteArray discoveryToken(const QString& pin)
    {
        return QCryptographicHash::hash("vitra-sync|" + pin.toUtf8(), QCryptographicHash::Sha256).toHex();
    }
    static QByteArray proofFor(const QString& pin, const QByteArray& nonce)
    {
        return QMessageAuthenticationCode::hash(nonce, pin.toUtf8(), QCryptographicHash::Sha256).toHex();
    }
    static QByteArray sharerProof(const QString& pin, const QByteArray& nonce, const QByteArray& manifest)
    {
        const QByteArray digest = QCryptographicHash::hash(manifest, QCryptographicHash::Sha256);
        return QMessageAuthenticationCode::hash("sharer|" + nonce + "|" + digest, pin.toUtf8(), QCryptographicHash::Sha256).toHex();
    }
    static QByteArray fileProof(const QByteArray& ticket, const QByteArray& nonce, const QByteArray& id)
    {
        return QMessageAuthenticationCode::hash(nonce + "|" + id, ticket, QCryptographicHash::Sha256).toHex();
    }
    void answerDiscovery()
    {
        while (m_discovery.hasPendingDatagrams()) {
            QHostAddress sender;
            quint16 port = 0;
            QByteArray data(int(qMin<qint64>(m_discovery.pendingDatagramSize(), 256)), Qt::Uninitialized);
            m_discovery.readDatagram(data.data(), data.size(), &sender, &port);
            if (m_state == "sharing" && data == discoveryToken(m_pin))
                m_discovery.writeDatagram(QByteArray::number(m_server.serverPort()), sender, port);
        }
    }
    void acceptClient()
    {
        while (auto* socket = m_server.nextPendingConnection()) {
            const QByteArray nonce = QByteArray::number(QRandomGenerator::system()->generate64(), 16);
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            auto* guard = new QTimer(socket);
            guard->setSingleShot(true);
            connect(guard, &QTimer::timeout, socket, [socket] { socket->abort(); });
            guard->start(10000);
            connect(socket, &QTcpSocket::readyRead, this, [this, socket, nonce, guard] {
                if (!socket->canReadLine()) {
                    if (socket->bytesAvailable() > 256) socket->abort();
                    return;
                }
                const QByteArray line = socket->readLine().trimmed();
                if (line.startsWith("file ")) return sendFile(socket, nonce, line, guard);
                const bool accepted = m_state == "sharing" && line == proofFor(m_pin, nonce);
                if (!accepted) {
                    socket->write("{\"ok\":false}\n");
                    socket->disconnectFromHost();
                    if (m_state == "sharing" && ++m_failedProofs >= 5) {
                        stopServing();
                        setState("expired", pgTr("Too many wrong codes. Sharing has stopped."));
                    }
                    return;
                }
                const QByteArray manifest = QJsonDocument(m_manifest).toJson(QJsonDocument::Compact);
                socket->write(QJsonDocument(QJsonObject{ { "ok", true }, { "manifestText", QString::fromUtf8(manifest) },
                                                         { "proof", QString::fromLatin1(sharerProof(m_pin, nonce, manifest)) },
                                                         { "ticket", QString::fromLatin1(m_ticket) } })
                                  .toJson(QJsonDocument::Compact) + "\n");
                socket->disconnectFromHost();
                if (!m_singleUse) return;
                if (m_direct.isEmpty()) {
                    stopServing();
                    setState("expired", pgTr("The code was used and has expired."));
                } else {
                    // The code is spent, but the receiver may still ask for its files.
                    m_discovery.close();
                    setState("serving", pgTr("Code used. Keep this open until the other computer has finished syncing."));
                }
            });
            socket->write(nonce + "\n");
        }
    }

    // Only a file this share listed, by its number; a request carries no path.
    void sendFile(QTcpSocket* socket, const QByteArray& nonce, const QByteArray& line, QTimer* guard)
    {
        const auto parts = line.split(' ');
        bool valid = false;
        const int id = parts.size() == 3 ? parts[1].toInt(&valid) : -1;
        if (!valid || m_ticket.isEmpty() || id < 0 || id >= m_direct.size() || parts[2] != fileProof(m_ticket, nonce, parts[1])) return socket->abort();
        auto file = std::make_shared<QFile>(m_direct[id]);
        if (!file->open(QIODevice::ReadOnly)) return socket->abort();
        m_secondsLeft = qMax(m_secondsLeft, 120);
        disconnect(socket, &QTcpSocket::readyRead, this, nullptr);
        socket->write("ok " + QByteArray::number(file->size()) + "\n");
        const int run = m_run;
        auto send = [this, socket, file, guard, run] {
            if (run != m_run) return socket->abort();
            guard->start(60000);
            while (socket->bytesToWrite() < 256 * 1024 && !file->atEnd()) socket->write(file->read(64 * 1024));
            if (file->atEnd()) socket->disconnectFromHost();
        };
        connect(socket, &QTcpSocket::bytesWritten, socket, send);
        send();
    }

    void discover()
    {
        m_finder = std::make_unique<QUdpSocket>();
        m_finder->bind(QHostAddress::AnyIPv4, 0);
        m_probing = true;
        const int run = m_run;
        auto* finder = m_finder.get();
        connect(finder, &QUdpSocket::readyRead, this, [this, finder, run] {
            if (run != m_run) return;
            QHostAddress sender;
            QByteArray data(16, Qt::Uninitialized);
            const auto size = finder->readDatagram(data.data(), data.size(), &sender);
            const quint16 port = data.left(qMax<qint64>(size, 0)).toUShort();
            if (port && m_probing) {
                m_probing = false;
                connectTo(sender.toString(), port);
            }
        });
        sendProbe(0, run);
    }
    void sendProbe(int attempt, int run)
    {
        if (run != m_run || !m_finder || !m_probing) return;
        if (attempt >= 8) return setState("error", pgTr("No computer is sharing with this code. If both are on one network, enter the code with the address shown beside it, like 123456@192.168.1.5:50000."));
        const QByteArray token = discoveryToken(m_pin);
        m_finder->writeDatagram(token, QHostAddress::Broadcast, DiscoveryPort);
        m_finder->writeDatagram(token, QHostAddress::LocalHost, DiscoveryPort);
        for (const auto& interface : QNetworkInterface::allInterfaces())
            for (const auto& entry : interface.addressEntries())
                if (!entry.broadcast().isNull()) m_finder->writeDatagram(token, entry.broadcast(), DiscoveryPort);
        QTimer::singleShot(500, this, [this, attempt, run] { sendProbe(attempt + 1, run); });
    }
    void connectTo(const QString& host, quint16 port)
    {
        m_client = std::make_unique<QTcpSocket>();
        auto* client = m_client.get();
        const int run = m_run;
        auto stage = std::make_shared<int>(0);
        auto nonce = std::make_shared<QByteArray>();
        auto fail = [this, run](const QString& text) {
            if (run == m_run && m_state == "connecting") setState("error", text);
        };
        connect(client, &QTcpSocket::errorOccurred, this, [fail, stage] {
            if (*stage < 2) fail(pgTr("Could not reach the other computer. Check that both are on the same network and the firewall allows Vitra Launcher."));
        });
        connect(client, &QTcpSocket::readyRead, this, [this, client, stage, nonce, fail, run, host, port] {
            if (run != m_run) return;
            if (client->bytesAvailable() > MaxLine) return client->abort();
            while (client->canReadLine()) {
                const QByteArray line = client->readLine().trimmed();
                if (*stage == 0) {
                    *stage = 1;
                    *nonce = line;
                    client->write(proofFor(m_pin, line) + "\n");
                } else {
                    *stage = 2;
                    const auto reply = QJsonDocument::fromJson(line).object();
                    client->disconnectFromHost();
                    if (!reply.value("ok").toBool()) return fail(pgTr("That code is wrong or has expired."));
                    // Older versions send the list without proving they hold the PIN.
                    const QByteArray text = reply.value("manifestText").toString().toUtf8();
                    if (text.isEmpty()) return receiveManifest(reply.value("manifest").toObject());
                    if (reply.value("proof").toString().toLatin1() != sharerProof(m_pin, *nonce, text)) return fail(pgTr("The other computer did not prove it holds this code."));
                    m_ticket = reply.value("ticket").toString().toLatin1();
                    m_peerHost = host;
                    m_peerPort = port;
                    receiveManifest(QJsonDocument::fromJson(text).object());
                    return;
                }
            }
        });
        QTimer::singleShot(10000, client, [fail, stage] {
            if (*stage < 2) fail(pgTr("The other computer did not respond."));
        });
        client->connectToHost(host, port);
    }

    // Everything below handles data from another machine, so nothing is trusted:
    // only https addresses on the official CDNs, plain file names, and a hash.
    // Direct files are the one exception to the CDN rule, and only on request.
    static bool allowedUrl(const QString& text)
    {
        const QUrl url(text);
        static const QStringList hosts{ "cdn.modrinth.com", "edge.forgecdn.net", "mediafilez.forgecdn.net", "media.forgecdn.net" };
        return url.isValid() && url.scheme() == "https" && hosts.contains(url.host().toLower());
    }
    static bool allowedName(const QString& kind, const QString& name)
    {
        static const QRegularExpression plain(QStringLiteral("^[^/\\\\:*?\"<>|\\x00-\\x1f]+$"));
        if (!plain.match(name).hasMatch() || name.startsWith('.')) return false;
        const QString extension = QFileInfo(name).suffix().toLower();
        return kind == "mods" ? extension == "jar" || extension == "litemod" : (kind == "resourcepacks" || kind == "shaderpacks") && extension == "zip";
    }
    static bool validHash(const QString& hash)
    {
        static const QRegularExpression hex(QStringLiteral("^[0-9a-f]{128}$"));
        return hex.match(hash).hasMatch();
    }
    void receiveManifest(const QJsonObject& manifest)
    {
        const int format = manifest.value("format").toInt();
        if (format != 1 && format != 2) return setState("error", pgTr("The other computer runs an incompatible version."));
        if (m_createNew) {
            // Nothing local to compare; the folders are known once it exists.
            m_manifest = manifest;
            return buildPlan({}, { { "mods", QString() }, { "resourcepacks", QString() }, { "shaderpacks", QString() } }, QString());
        }
        auto* instance = m_resolver(m_targetKey);
        if (!instance) return setState("error", pgTr("Instance unavailable. Refresh the list."));
        const auto folders = contentFolders(instance);
        const QString root = instance->instanceRoot();
        m_manifest = manifest;
        const int run = m_run;
        setState("connecting", pgTr("Comparing with this instance…"));
        runAsync([folders] { return scan(folders); }, [this, run, folders, root](const QList<LocalFile>& files) {
            if (run == m_run) buildPlan(files, folders, root);
        });
    }
    void buildPlan(const QList<LocalFile>& local, const QMap<QString, QString>& folders, const QString& root)
    {
        m_downloads.clear();
        m_moves.clear();
        m_renames.clear();
        QHash<QString, LocalFile> present;
        for (const auto& file : local) present.insert(file.kind + "/" + file.name.toLower(), file);

        // Only what the sharer included is compared: a kind left out says nothing
        // about this instance's own files.
        QStringList sharedKinds;
        for (const auto& value : m_manifest.value("kinds").toArray())
            if (folders.contains(value.toString())) sharedKinds.append(value.toString());
        struct KindPlan {
            int add = 0, replace = 0, remove = 0, unchanged = 0;
            qint64 bytes = 0;
            QStringList unavailable;
        };
        QMap<QString, KindPlan> plans;
        for (const auto& kind : sharedKinds) plans[kind];

        QStringList wanted, direct;
        for (const auto& value : m_manifest.value("unavailable").toArray()) {
            const auto entry = value.toObject();
            const QString kind = entry.value("kind").toString();
            if (!plans.contains(kind)) continue;
            plans[kind].unavailable.append(entry.value("name").toString());
            wanted.append(kind + "/" + entry.value("name").toString().toLower());
        }
        for (const auto& value : m_manifest.value("files").toArray()) {
            const auto entry = value.toObject();
            Download file;
            file.kind = entry.value("kind").toString();
            file.name = entry.value("name").toString();
            file.url = entry.value("url").toString();
            file.sha512 = entry.value("sha512").toString();
            file.size = entry.value("size").toInteger();
            file.enabled = entry.value("enabled").toBool(true);
            file.folder = folders.value(file.kind);
            file.direct = entry.value("direct").toBool() && !m_ticket.isEmpty() && file.size <= MaxDirectFile;
            file.directId = entry.value("id").toInt(-1);
            if (!plans.contains(file.kind)) continue;
            auto& plan = plans[file.kind];
            if (!allowedName(file.kind, file.name) || (!file.direct && !allowedUrl(file.url)) || !validHash(file.sha512) || file.size <= 0) {
                plan.unavailable.append(file.name);
                continue;
            }
            const QString key = file.kind + "/" + file.name.toLower();
            wanted.append(key);
            const auto existing = present.constFind(key);
            if (existing != present.cend() && existing->sha512 == file.sha512) {
                ++plan.unchanged;
                if (existing->enabled != file.enabled)
                    m_renames.append({ existing->path, QDir(file.folder).filePath(file.enabled ? file.name : file.name + ".disabled") });
                continue;
            }
            if (existing != present.cend()) {
                file.replaces = existing->path;
                ++plan.replace;
            } else
                ++plan.add;
            plan.bytes += file.size;
            if (file.direct) direct.append(file.name);
            m_downloads.append(file);
        }
        // Extra mods would break the set; packs beside the list do no harm.
        if (plans.contains("mods"))
            for (const auto& file : local)
                if (file.kind == "mods" && !file.directory && !wanted.contains(file.kind + "/" + file.name.toLower())) {
                    m_moves.append(file.path);
                    ++plans["mods"].remove;
                }

        QStringList versionChanges;
        const QHash<QString, QPair<QString, QString>> mine = root.isEmpty() ? QHash<QString, QPair<QString, QString>>() : componentMap(sharedComponents(root));
        m_componentChanges = false;
        const auto theirs = m_manifest.value("components").toArray();
        QSet<QString> theirIds;
        static const QRegularExpression safe(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._+\\-]*$"));
        for (const auto& value : theirs) {
            const auto component = value.toObject();
            const QString uid = component.value("uid").toString(), version = component.value("version").toString();
            if (!safe.match(uid).hasMatch() || !safe.match(version).hasMatch()) return setState("error", pgTr("The list from the other computer is not valid."));
            theirIds.insert(uid);
            const auto current = mine.constFind(uid);
            const QString label = component.value("name").toString(uid);
            if (current == mine.cend())
                versionChanges.append(label + " " + version);
            else if (current->first != version)
                versionChanges.append(label + " " + current->first + " → " + version);
        }
        for (auto it = mine.begin(); it != mine.end(); ++it)
            if (!theirIds.contains(it.key())) versionChanges.append(pgTr("Remove %1").replace("%1", it.value().second.isEmpty() ? it.key() : it.value().second));
        m_componentChanges = !versionChanges.isEmpty();

        QVariantList kinds;
        for (auto plan = plans.begin(); plan != plans.end(); ++plan)
            kinds.append(QVariantMap{ { "kind", plan.key() }, { "add", plan->add }, { "replace", plan->replace }, { "remove", plan->remove }, { "unchanged", plan->unchanged },
                                      { "unavailable", plan->unavailable }, { "megabytes", int((plan->bytes + 524288) / 1048576) } });
        m_preview = QVariantMap{ { "versions", versionChanges }, { "kinds", kinds }, { "name", sharedName() }, { "direct", direct } };
        setState("review", QString());
    }
    QString sharedName() const
    {
        static const QRegularExpression unsafe(QStringLiteral("[/\\\\:*?\"<>|\\x00-\\x1f]"));
        QString name = m_manifest.value("name").toString();
        name = name.remove(unsafe).trimmed().left(64);
        return name.isEmpty() ? QStringLiteral("Minecraft %1").arg(componentMap(m_manifest.value("components").toArray()).value("net.minecraft").first) : name;
    }
    void createInstance()
    {
        static const QList<QPair<QString, QString>> loaders{ { "net.fabricmc.fabric-loader", "Fabric" }, { "net.minecraftforge", "Forge" },
                                                             { "net.neoforged", "NeoForge" }, { "org.quiltmc.quilt-loader", "Quilt" } };
        const auto theirs = componentMap(m_manifest.value("components").toArray());
        const QString game = theirs.value("net.minecraft").first;
        if (game.isEmpty()) return setState("error", pgTr("The shared instance has no Minecraft version."));
        QString loader = QStringLiteral("Vanilla"), loaderVersion;
        for (const auto& known : loaders)
            if (theirs.contains(known.first)) {
                loader = known.second;
                loaderVersion = theirs.value(known.first).first;
                break;
            }
        setState("creating", pgTr("Installing the game and mod loader…"));
        if (!m_creator(game, loader, loaderVersion, sharedName())) setState("error", pgTr("Another installation is running. Wait for it to finish."));
    }
    static QHash<QString, QPair<QString, QString>> componentMap(const QJsonArray& list)
    {
        QHash<QString, QPair<QString, QString>> map;
        for (const auto& value : list) {
            const auto component = value.toObject();
            map.insert(component.value("uid").toString(), { component.value("version").toString(), component.value("name").toString() });
        }
        return map;
    }

    void pump()
    {
        while (m_active < 4 && m_next < m_downloads.size()) fetch(m_next++);
        if (m_active == 0 && m_next >= m_downloads.size()) install();
    }
    void fetch(int index)
    {
        auto& file = m_downloads[index];
        file.tempPath = QDir(m_tempDir).filePath(QString::number(index));
        if (file.direct) return fetchDirect(index);
        auto output = std::make_shared<QFile>(file.tempPath);
        auto hash = std::make_shared<QCryptographicHash>(QCryptographicHash::Sha512);
        auto received = std::make_shared<qint64>(0);
        if (!output->open(QIODevice::WriteOnly)) {
            m_failures.append(file.name);
            ++m_completed;
            return;
        }
        ++m_active;
        QNetworkRequest request{ QUrl(file.url) };
        request.setRawHeader("User-Agent", BuildConfig.USER_AGENT.toUtf8());
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        request.setTransferTimeout(30000);
        auto* reply = m_app->network()->get(request);
        m_replies.append(reply);
        const qint64 size = file.size;
        connect(reply, &QIODevice::readyRead, this, [reply, output, hash, received, size] {
            const QByteArray data = reply->readAll();
            *received += data.size();
            if (*received > size) return reply->abort();
            hash->addData(data);
            if (output->write(data) != data.size()) reply->abort();
        });
        const int run = m_run;
        connect(reply, &QNetworkReply::finished, this, [this, reply, output, hash, received, index, run] {
            reply->deleteLater();
            if (run != m_run) { output->close(); return; }
            m_replies.removeAll(reply);
            const auto& file = m_downloads[index];
            const bool valid = reply->error() == QNetworkReply::NoError && *received == file.size &&
                QString::fromLatin1(hash->result().toHex()) == file.sha512 &&
                SyncFiles::verified(*output, file.size, file.sha512);
            output->close();
            downloadFinished(index, valid);
        });
    }
    void downloadFinished(int index, bool ok)
    {
        auto& file = m_downloads[index];
        file.ok = ok;
        if (!ok) m_failures.append(file.name);
        --m_active;
        ++m_completed;
        emit changed();
        pump();
    }
    // The same checks as a site download: nothing unverified reaches the instance.
    void fetchDirect(int index)
    {
        const auto file = m_downloads[index];
        auto output = std::make_shared<QFile>(file.tempPath);
        if (!output->open(QIODevice::WriteOnly)) {
            m_failures.append(file.name);
            ++m_completed;
            return;
        }
        ++m_active;
        auto* socket = new QTcpSocket(this);
        m_peers.append(socket);
        auto* guard = new QTimer(socket);
        guard->setSingleShot(true);
        guard->setInterval(30000);
        connect(guard, &QTimer::timeout, socket, [socket] { socket->abort(); });
        auto hash = std::make_shared<QCryptographicHash>(QCryptographicHash::Sha512);
        auto received = std::make_shared<qint64>(0);
        auto stage = std::make_shared<int>(0);
        auto ended = std::make_shared<bool>(false);
        const int run = m_run;
        auto end = [this, socket, output, ended, run, index](bool ok) {
            if (*ended) return;
            *ended = true;
            output->close();
            socket->deleteLater();
            if (run == m_run) downloadFinished(index, ok);
        };
        connect(socket, &QTcpSocket::readyRead, this, [socket, guard, output, hash, received, stage, end, file, ticket = m_ticket] {
            guard->start();
            if (*stage == 0 && socket->canReadLine()) {
                const QByteArray id = QByteArray::number(file.directId);
                socket->write("file " + id + " " + fileProof(ticket, socket->readLine().trimmed(), id) + "\n");
                *stage = 1;
            }
            if (*stage == 1 && socket->canReadLine()) {
                if (socket->readLine().trimmed() != "ok " + QByteArray::number(file.size)) return end(false);
                *stage = 2;
            }
            if (*stage != 2) return;
            const QByteArray data = socket->read(file.size - *received);
            *received += data.size();
            hash->addData(data);
            if (output->write(data) != data.size()) return end(false);
            if (*received == file.size) end(QString::fromLatin1(hash->result().toHex()) == file.sha512 &&
                SyncFiles::verified(*output, file.size, file.sha512));
        });
        connect(socket, &QTcpSocket::disconnected, this, [end] { end(false); });
        connect(socket, &QTcpSocket::errorOccurred, this, [end] { end(false); });
        guard->start();
        socket->connectToHost(m_peerHost, m_peerPort);
    }
    void syncError(const QString& reason)
    {
        const QString restoreError = restoreComponents();
        setState("error", reason + (restoreError.isEmpty() ? QString() : "\n" + restoreError));
    }
    // Prepare game files before changing the content set. A failed download
    // must not remove mods from a previously working instance.
    void install()
    {
        if (!m_failures.isEmpty())
            return syncError(pgTr("Sync stopped because some downloads failed. Instance content was not changed."));
        auto* instance = m_resolver(m_targetKey);
        if (!instance || instance->isRunning())
            return syncError(pgTr("Stop the instance before syncing."));
        if (m_componentChanges) {
            instance->getPackProfile()->saveNow();
            // Removing or reverting a custom component can delete local patch
            // files and jar mods. A manifest backup cannot restore those.
            const auto mine = componentMap(sharedComponents(m_root));
            const auto theirs = componentMap(m_manifest.value("components").toArray());
            for (auto it = mine.begin(); it != mine.end(); ++it) {
                if ((!theirs.contains(it.key()) || theirs.value(it.key()).first != it.value().first) &&
                    QFileInfo::exists(instance->getPackProfile()->patchFilePathForUid(it.key())))
                    return syncError(pgTr("Cannot replace custom game components. Sync without changing versions."));
            }
            const QString source = QDir(m_root).filePath("mmc-pack.json");
            m_componentBackup = QDir(m_root).filePath(".vitra-sync-backup/" + QUuid::createUuid().toString(QUuid::WithoutBraces) + "/mmc-pack.json");
            if (!QDir().mkpath(QFileInfo(m_componentBackup).absolutePath()) || !QFile::copy(source, m_componentBackup)) {
                m_componentBackup.clear();
                return syncError(pgTr("Cannot back up game and loader versions."));
            }
            if (!applyComponents(instance)) return syncError(pgTr("Cannot update game and loader versions."));
            fetchGameFiles(instance);
        } else installContent();
    }
    QString restoreComponents()
    {
        if (m_componentBackup.isEmpty()) return {};
        auto* instance = m_resolver(m_targetKey);
        if (instance) {
            auto profile = instance->getPackProfile();
            if (auto task = profile->getCurrentTask()) task->abort();
            profile->saveNow();
        }
        QFile backup(m_componentBackup);
        QSaveFile target(QDir(m_root).filePath("mmc-pack.json"));
        if (!backup.open(QIODevice::ReadOnly) || !target.open(QIODevice::WriteOnly))
            return pgTr("Cannot restore game and loader versions. Backup: ") + m_componentBackup;
        const QByteArray bytes = backup.readAll();
        if (backup.error() != QFileDevice::NoError || target.write(bytes) != bytes.size() || !target.commit())
            return pgTr("Cannot restore game and loader versions. Backup: ") + m_componentBackup;
        m_componentBackup.clear();
        if (instance && !instance->getPackProfile()->reload(Net::Mode::Offline))
            return pgTr("Versions were restored. Restart the launcher before using this instance.");
        return {};
    }
    void installContent()
    {
        auto* instance = m_resolver(m_targetKey);
        if (!instance || instance->isRunning()) return syncError(pgTr("Stop the instance before syncing."));
        const QString backup = QDir(m_root).filePath(".vitra-sync-backup/" + QUuid::createUuid().toString(QUuid::WithoutBraces));
        SyncFiles::Transaction transaction;
        auto fail = [this, &transaction] {
            QString reason = transaction.error;
            if (!transaction.rollback()) reason += "\n" + transaction.error;
            syncError(reason);
        };
        auto keep = [&backup, &transaction](const QString& path) {
            const QFileInfo file(path);
            return transaction.move(path, QDir(backup).filePath(file.dir().dirName() + "/" + file.fileName()));
        };
        for (const auto& path : m_moves) if (!keep(path)) return fail();
        for (const auto& rename : m_renames)
            if (!transaction.move(rename.first, rename.second)) return fail();
        for (const auto& file : m_downloads) {
            if (!file.ok) return fail();
            if (!file.replaces.isEmpty() && !keep(file.replaces)) return fail();
            if (!transaction.move(file.tempPath, QDir(file.folder).filePath(file.enabled ? file.name : file.name + ".disabled")))
                return fail();
        }
        transaction.commit();
        m_componentBackup.clear();
        QDir(m_tempDir).removeRecursively();
        m_tempDir.clear();
        finish(m_downloads.size());
    }
    // The changed game and loader are ready to play, as after a new install.
    void fetchGameFiles(MinecraftInstance* instance)
    {
        setState("finishing", pgTr("Downloading game files…"));
        auto task = makeShared<SequentialTask>();
        task->addTask(makeShared<MinecraftLoadAndCheck>(instance, Net::Mode::Online));
        for (const auto& step : instance->createUpdateTask()) task->addTask(step);
        const int run = m_run;
        connect(task.get(), &Task::finished, this, [this, task, run] {
            if (run != m_run) return;
            const bool successful = task->wasSuccessful();
            m_gameFiles.reset();
            if (!successful) return syncError(pgTr("Cannot download game files. Instance content was not changed."));
            installContent();
        }, Qt::SingleShotConnection);
        m_gameFiles = task;
        task->start();
    }
    void finish(int installed)
    {
        setState("done", m_failures.isEmpty() ? pgTr("Sync complete. %1 files downloaded.").replace("%1", QString::number(installed))
                                              : pgTr("%1 files downloaded, %2 failed.").replace("%1", QString::number(installed)).replace("%2", QString::number(m_failures.size())));
    }
    bool applyComponents(MinecraftInstance* instance)
    {
        auto profile = instance->getPackProfile();
        // An unloaded profile accepts changes but refuses to save them.
        if (!profile->reload(Net::Mode::Offline)) return false;
        const auto mine = componentMap(sharedComponents(instance->instanceRoot()));
        const auto theirs = componentMap(m_manifest.value("components").toArray());
        for (auto it = mine.begin(); it != mine.end(); ++it)
            if (!theirs.contains(it.key()) && !profile->remove(it.key())) return false;
        for (auto it = theirs.begin(); it != theirs.end(); ++it)
            if (it.key() != "net.minecraft" && mine.value(it.key()).first != it.value().first &&
                !profile->setComponentVersion(it.key(), it.value().first)) return false;
        profile->saveNow();
        // Last and important: this resolves dependencies (LWJGL, mappings) for the new set.
        const QString game = theirs.value("net.minecraft").first;
        if (!game.isEmpty() && mine.value("net.minecraft").first != game) {
            if (!profile->setComponentVersion("net.minecraft", game, true)) return false;
        } else if (!profile->reload(Net::Mode::Online)) return false;
        profile->saveNow();
        const auto saved = componentMap(sharedComponents(instance->instanceRoot()));
        for (auto it = theirs.begin(); it != theirs.end(); ++it)
            if (saved.value(it.key()).first != it.value().first) {
                return false;
            }
        return true;
    }

    Application* m_app;
    Resolver m_resolver;
    Creator m_creator;
    Task::Ptr m_gameFiles;
    QString m_state = "idle", m_message, m_pin, m_address, m_targetKey, m_root, m_tempDir;
    QVariantMap m_preview;
    QString m_componentBackup;
    QStringList m_failures;
    QJsonObject m_manifest;
    QTcpServer m_server;
    QUdpSocket m_discovery;
    std::unique_ptr<QUdpSocket> m_finder;
    std::unique_ptr<QTcpSocket> m_client;
    QTimer m_tick;
    QList<Download> m_downloads;
    QStringList m_moves;
    QList<QPair<QString, QString>> m_renames;
    QList<QPointer<QNetworkReply>> m_replies;
    QList<QPointer<QTcpSocket>> m_peers;
    QStringList m_direct;  // sharing side: what "file <id>" may ask for
    QByteArray m_ticket;
    QString m_peerHost;
    quint16 m_peerPort = 0;
    int m_run = 0, m_secondsLeft = 0, m_lifetime = 300, m_failedProofs = 0, m_completed = 0, m_active = 0, m_next = 0;
    bool m_singleUse = true, m_componentChanges = false, m_probing = false, m_createNew = false;
};
