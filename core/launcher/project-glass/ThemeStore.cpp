// SPDX-License-Identifier: GPL-3.0-only
#include "ThemeStore.h"
#include "PgTranslate.h"
#include <QBuffer>
#include <QCryptographicHash>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUuid>
#include <cmath>

namespace {
constexpr qint64 MaxDocument = 8 * 1024 * 1024;
constexpr qint64 MaxImage = 4 * 1024 * 1024;
const QMap<QString, QPair<double, double>>& ranges()
{
    static const QMap<QString, QPair<double, double>> value{
        {"frost",{0,1}}, {"refraction",{0,1}}, {"glare",{0,1}}, {"density",{0,1}}, {"strokeWidth",{0,3}},
        {"refractiveIndex",{1,2.5}}, {"bevelWidth",{1,40}}, {"dispersion",{0,0.3}}, {"magnification",{0.5,2}},
        {"blurSpread",{0,1}}, {"saturation",{0,2.5}}, {"brightness",{0,2}}, {"fresnelAmount",{0,3}},
        {"specularAmount",{0,3}}, {"edgeAmount",{0,3}}, {"shadowAmount",{0,3}}, {"lightAngle",{-180,180}},
        {"interactionStrength",{0,3}}, {"interactionRadius",{10,200}}, {"responseTime",{0,500}},
        {"materialVariant",{0,4}}, {"fusionDistance",{1,100}}, {"sidebarFrost",{0,1}}, {"sidebarGlow",{0,1}},
        {"sidebarGlowCoverage",{0.2,0.65}}, {"sidebarGlowWidth",{80,600}}, {"sidebarGlowBlur",{0,1}},
        {"sidebarGlowSaturation",{0,1}}, {"lensLabelRange",{8,32}}
    };
    return value;
}
bool colour(const QJsonValue& value)
{
    static const QRegularExpression hex(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    return value.isString() && hex.match(value.toString()).hasMatch();
}
bool writeJson(const QString& path, const QJsonObject& object)
{
    QSaveFile file(path);
    const auto bytes = QJsonDocument(object).toJson();
    return bytes.size() <= MaxDocument && file.open(QIODevice::WriteOnly) &&
        file.write(bytes) == bytes.size() && file.commit();
}
QJsonObject readJson(const QString& path, QString& error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > MaxDocument) {
        error = pgTr("Cannot read theme file (maximum 8 MB)."); return {};
    }
    QJsonParseError parse;
    const auto doc = QJsonDocument::fromJson(file.read(MaxDocument + 1), &parse);
    if (parse.error != QJsonParseError::NoError || !doc.isObject()) {
        error = pgTr("Invalid theme JSON."); return {};
    }
    return doc.object();
}
QString embeddedImage(const QString& source, bool allowLocal, QString& error)
{
    QByteArray bytes;
    if (source.startsWith("data:image/png;base64,") || source.startsWith("data:image/jpeg;base64,")) {
        const auto encoded = source.mid(source.indexOf(',') + 1).toLatin1();
        if (encoded.size() > (MaxImage + 2) / 3 * 4) {
            error = pgTr("Theme wallpaper is too large (maximum 4 MB)."); return {};
        }
        const auto decoded = QByteArray::fromBase64Encoding(encoded, QByteArray::AbortOnBase64DecodingErrors);
        if (!decoded) { error = pgTr("Invalid theme wallpaper."); return {}; }
        bytes = decoded.decoded;
    } else if (allowLocal && QUrl(source).isLocalFile()) {
        QFile file(QUrl(source).toLocalFile());
        if (!file.open(QIODevice::ReadOnly) || file.size() > MaxImage) {
            error = pgTr("Cannot read wallpaper (maximum 4 MB)."); return {};
        }
        bytes = file.read(MaxImage + 1);
    } else { error = pgTr("Theme wallpaper must be embedded in the theme file."); return {}; }
    QBuffer input(&bytes); input.open(QIODevice::ReadOnly);
    QImageReader reader(&input);
    const QSize size = reader.size();
    const auto format = reader.format().toLower();
    if (bytes.isEmpty() || bytes.size() > MaxImage || (format != "png" && format != "jpeg" && format != "jpg" && allowLocal == false) ||
        !size.isValid() || qint64(size.width()) * size.height() > 16 * 1024 * 1024) {
        error = pgTr("Invalid theme wallpaper or image dimensions."); return {};
    }
    const QImage image = reader.read();
    QByteArray png;
    QBuffer output(&png); output.open(QIODevice::WriteOnly);
    if (image.isNull() || !image.save(&output, "PNG") || png.size() > MaxImage) {
        error = pgTr("Theme wallpaper is too large or cannot be decoded."); return {};
    }
    return "data:image/png;base64," + QString::fromLatin1(png.toBase64());
}
QJsonObject preset(const QString& name, const QString& mode, const QString& first,
                   const QString& second, const QString& accent, double frost)
{
    return {{"format","vitra-theme"},{"version",1},{"name",name},{"author","Vitra"},
        {"appearance",QJsonObject{{"mode",mode},{"accent",accent},
            {"background",QJsonObject{{"kind","gradient"},{"angle",45},
                {"stops",QJsonArray{QJsonObject{{"color",first},{"position",0}},QJsonObject{{"color",second},{"position",1}}}}}},
            {"glass",QJsonObject{{"frost",frost},{"materialVariant",0}}}}}};
}
QJsonObject prismPreset(const QString& name, const QString& cat = {})
{
    auto result=preset(name,"Dark","#313131","#313131","#96DB59",0.33);
    result.insert("author","Prism Launcher");
    if (!cat.isEmpty()) {
        auto appearance=result.value("appearance").toObject();
        appearance.insert("cat",cat); result.insert("appearance",appearance);
    }
    return result;
}
QVariantMap entry(const QString& id, const QJsonObject& document, bool official)
{
    auto result = document.toVariantMap();
    result.insert("id",id); result.insert("builtIn",official);
    return result;
}
}

QJsonObject ThemeStore::normalize(const QJsonObject& input, QString& error)
{
    auto invalid = [&error](const QString& reason) { error = reason; return QJsonObject{}; };
    if (input.value("format") != "vitra-theme" || input.value("version") != 1)
        return invalid(pgTr("Unsupported theme format or version."));
    const QString name = input.value("name").toString().trimmed(), author = input.value("author").toString().trimmed();
    if (name.isEmpty() || name.size() > 80 || author.size() > 80)
        return invalid(pgTr("Theme name and author must be at most 80 characters."));
    const auto appearance = input.value("appearance").toObject();
    const QString cat=appearance.value("cat").toString();
    if ((!appearance.value("cat").isUndefined() && !appearance.value("cat").isString()) ||
        !QStringList{"","kitteh","rory","rory-flat","teawie"}.contains(cat))
        return invalid(pgTr("Invalid Prism cat."));
    const QString mode = appearance.value("mode").toString();
    if (!QStringList{"Dark","Light","System"}.contains(mode) || !colour(appearance.value("accent")))
        return invalid(pgTr("Invalid theme colour or appearance mode."));
    const auto background = appearance.value("background").toObject();
    const QString kind = background.value("kind").toString();
    if (!QStringList{"gradient","image"}.contains(kind)) return invalid(pgTr("Invalid theme background."));
    QJsonObject cleanBackground{{"kind",kind}};
    if (kind == "image") {
        const QString image = embeddedImage(background.value("image").toString(), false, error);
        if (!error.isEmpty()) return {};
        const QString placement = background.value("placement").toString("Fill");
        if (!QStringList{"Fill","Fit","Stretch","Tile","Center"}.contains(placement))
            return invalid(pgTr("Invalid wallpaper placement."));
        cleanBackground.insert("image",image); cleanBackground.insert("placement",placement);
    } else {
        const auto stops = background.value("stops").toArray();
        const auto angle = background.value("angle");
        if (stops.size() < 2 || stops.size() > 8 || !angle.isDouble() || angle.toDouble() < 0 || angle.toDouble() > 360)
            return invalid(pgTr("A theme gradient needs 2 to 8 stops and an angle from 0 to 360."));
        QJsonArray cleaned;
        double previous = -1;
        for (const auto& stop : stops) {
            const auto item = stop.toObject(); const auto position = item.value("position");
            if (!colour(item.value("color")) || !position.isDouble() || position.toDouble() < previous ||
                position.toDouble() < 0 || position.toDouble() > 1) return invalid(pgTr("Invalid theme gradient stop."));
            previous = position.toDouble();
            cleaned.append(QJsonObject{{"color",item.value("color")},{"position",position}});
        }
        cleanBackground.insert("stops",cleaned); cleanBackground.insert("angle",angle);
    }
    if (!appearance.value("glass").isObject()) return invalid(pgTr("Invalid theme glass parameters."));
    QJsonObject glass;
    const auto rawGlass = appearance.value("glass").toObject();
    for (auto it = rawGlass.begin(); it != rawGlass.end(); ++it) {
        if (ranges().contains(it.key())) {
            const auto bounds = ranges().value(it.key());
            if (!it.value().isDouble() || !std::isfinite(it.value().toDouble()) || it.value().toDouble() < bounds.first ||
                it.value().toDouble() > bounds.second || (it.key() == "materialVariant" && std::floor(it.value().toDouble()) != it.value().toDouble()))
                return invalid(pgTr("Invalid theme glass parameter: ") + it.key());
            glass.insert(it.key(),it.value());
        } else if (QStringList{"glassEnabled","fusionEnabled","frostedMode"}.contains(it.key())) {
            if (!it.value().isBool()) return invalid(pgTr("Invalid theme glass parameter: ") + it.key());
            glass.insert(it.key(),it.value());
        } else if (!QStringList{"version","reducedMotion","reducedTransparency","increaseContrast","reduceBrightEffects"}.contains(it.key()))
            return invalid(pgTr("Unknown theme glass parameter: ") + it.key());
        // Accessibility preferences belong to the recipient, never the theme.
    }
    QJsonObject cleanAppearance{{"mode",mode},{"accent",appearance.value("accent")},
        {"background",cleanBackground},{"glass",glass}};
    if (!cat.isEmpty()) cleanAppearance.insert("cat",cat);
    return {{"format","vitra-theme"},{"version",1},{"name",name},{"author",author},
        {"appearance",cleanAppearance}};
}

ThemeStore::ThemeStore(const QString& dataRoot, QObject* parent)
    : QObject(parent), m_directory(QDir(dataRoot).filePath("themes"))
{
    m_official.insert("official-aurora",preset("Aurora","Dark","#122C38","#675291","#65D9D1",0.33));
    m_official.insert("official-dusk",preset("Dusk","Dark","#221C35","#70425A","#C1A3FF",0.42));
    m_official.insert("official-forest",preset("Forest","Dark","#102922","#315C4B","#80D8A3",0.5));
    m_official.insert("official-paper",preset("Paper","Light","#F5F2EB","#DFE8ED","#3268A8",0.55));
    auto bright=preset("Prism Bright","Light","#FFFFFF","#FFFFFF","#89CF54",0.33);
    bright.insert("author","Prism Launcher");
    m_official.insert("official-prism-bright",bright);
    m_official.insert("official-prism-dark",prismPreset("Prism Dark"));
    m_official.insert("official-prism-kitteh",prismPreset("Prism Kitteh","kitteh"));
    m_official.insert("official-prism-rory",prismPreset("Prism Rory","rory"));
    m_official.insert("official-prism-rory-flat",prismPreset("Prism Rory Flat","rory-flat"));
    m_official.insert("official-prism-teawie",prismPreset("Prism Teawie","teawie"));
    static const QRegularExpression id(QStringLiteral("^[0-9a-f-]{36}\\.json$"));
    for (const auto& info : QDir(m_directory).entryInfoList({"*.json"}, QDir::Files | QDir::NoSymLinks, QDir::Name)) {
        if (!id.match(info.fileName()).hasMatch() || m_custom.size() >= 64) continue;
        QString error;
        const auto raw = readJson(info.filePath(),error);
        const auto document = error.isEmpty() ? normalize(raw,error) : QJsonObject{};
        if (error.isEmpty()) m_custom.insert(info.baseName(),document);
        else m_error = pgTr("Some saved themes could not be loaded.");
    }
}
QString ThemeStore::catImage(const QString& id) const
{
    if (!QStringList{"kitteh","rory","rory-flat","teawie"}.contains(id)) return {};
    // Match Prism's original seasonal cat-pack selection order and date ranges.
    const auto now=QDate::currentDate();
    QString suffix;
    if (std::abs(now.daysTo(QDate(now.year(),12,25))) <= 4) suffix="-xmas";
    else if (std::abs(now.daysTo(QDate(now.year(),10,31))) <= 4) suffix="-spooky";
    else if (std::abs(now.daysTo(QDate(now.year(),11,1))) <= 12) suffix="-bday";
    return "qrc:/backgrounds/" + id + suffix;
}
QVariantList ThemeStore::themes() const
{
    QVariantList result;
    for (auto it=m_official.begin();it!=m_official.end();++it) result.append(entry(it.key(),it.value(),true));
    for (auto it=m_custom.begin();it!=m_custom.end();++it) result.append(entry(it.key(),it.value(),false));
    return result;
}
QVariantMap ThemeStore::theme(const QString& id) const
{
    if (m_official.contains(id)) return entry(id,m_official.value(id),true);
    if (m_custom.contains(id)) return entry(id,m_custom.value(id),false);
    return {};
}
void ThemeStore::fail(const QString& error) { m_error=error; emit changed(); }
QVariantMap ThemeStore::store(const QJsonObject& document)
{
    if (m_custom.size() >= 64) { fail(pgTr("The theme library is full (maximum 64 custom themes).")); return {}; }
    const QString id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (!QDir().mkpath(m_directory) || !writeJson(QDir(m_directory).filePath(id+".json"),document)) {
        fail(pgTr("Cannot save theme.")); return {};
    }
    m_custom.insert(id,document); m_error.clear(); emit changed();
    return entry(id,document,false);
}
QVariantMap ThemeStore::saveTheme(const QVariantMap& document)
{
    auto raw=QJsonObject::fromVariantMap(document);
    auto appearance=raw.value("appearance").toObject();
    auto background=appearance.value("background").toObject();
    QString error;
    if (background.value("kind")=="image") {
        background.insert("image",embeddedImage(background.value("image").toString(),true,error));
        if (!error.isEmpty()) { fail(error); return {}; }
        appearance.insert("background",background); raw.insert("appearance",appearance);
    }
    const auto clean=normalize(raw,error);
    if (!error.isEmpty()) { fail(error); return {}; }
    return store(clean);
}
QVariantMap ThemeStore::importTheme(const QUrl& source)
{
    if (!source.isLocalFile()) { fail(pgTr("Choose a local theme file.")); return {}; }
    QString error;
    const auto raw=readJson(source.toLocalFile(),error);
    const auto clean=error.isEmpty()?normalize(raw,error):QJsonObject{};
    if (!error.isEmpty()) { fail(error); return {}; }
    return store(clean);
}
bool ThemeStore::exportTheme(const QString& id, const QUrl& destination)
{
    const auto document=m_official.contains(id)?m_official.value(id):m_custom.value(id);
    if (document.isEmpty() || !destination.isLocalFile() || !writeJson(destination.toLocalFile(),document)) {
        fail(pgTr("Cannot export theme.")); return false;
    }
    m_error.clear(); emit changed(); return true;
}
bool ThemeStore::removeTheme(const QString& id)
{
    if (!m_custom.contains(id) || !QFile::remove(QDir(m_directory).filePath(id+".json"))) {
        fail(pgTr("Cannot remove theme.")); return false;
    }
    m_custom.remove(id); m_error.clear(); emit changed(); return true;
}
QString ThemeStore::wallpaperForTheme(const QString& id)
{
    const auto document=m_official.contains(id)?m_official.value(id):m_custom.value(id);
    const auto background=document.value("appearance").toObject().value("background").toObject();
    if (background.value("kind")!="image") { fail(pgTr("Invalid theme background.")); return {}; }
    const QString image=background.value("image").toString();
    const QByteArray bytes=QByteArray::fromBase64(image.mid(image.indexOf(',')+1).toLatin1());
    const QString folder=QDir(m_directory).filePath("wallpapers");
    const QString path=QDir(folder).filePath(QString::fromLatin1(QCryptographicHash::hash(bytes,QCryptographicHash::Sha256).toHex())+".png");
    QSaveFile file(path);
    if (bytes.isEmpty() || !QDir().mkpath(folder) || !file.open(QIODevice::WriteOnly) || file.write(bytes)!=bytes.size() || !file.commit()) {
        fail(pgTr("Cannot save theme wallpaper.")); return {};
    }
    m_error.clear(); emit changed();
    return QUrl::fromLocalFile(path).toString();
}
