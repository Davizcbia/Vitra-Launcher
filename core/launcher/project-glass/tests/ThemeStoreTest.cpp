// SPDX-License-Identifier: GPL-3.0-only
#include "../ThemeStore.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <cstdlib>
#include <iostream>
static void check(bool condition, const char* label)
{
    if (!condition) { std::cerr << "FAILED: " << label << '\n'; std::exit(1); }
}
static void write(const QString& path, const QJsonObject& value)
{
    QFile file(path); const auto bytes=QJsonDocument(value).toJson();
    check(file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size(), "write theme fixture");
}
int main(int argc, char** argv)
{
    QCoreApplication app(argc,argv);
    QTemporaryDir first, second;
    check(first.isValid() && second.isValid(), "temporary library folders");
    ThemeStore store(first.path());
    check(store.themes().size()==10, "built-in Vitra and Prism themes");
    const auto aurora=store.theme("official-aurora");
    check(aurora.value("builtIn").toBool(), "official attribution");
    check(!store.removeTheme("official-aurora") && store.themes().size()==10, "official themes cannot be deleted");
    const QString shared=second.filePath("shared.vitra-theme.json");
    check(store.exportTheme("official-aurora",QUrl::fromLocalFile(shared)), "export official theme");
    ThemeStore receiver(second.path());
    const auto imported=receiver.importTheme(QUrl::fromLocalFile(shared));
    check(!imported.value("id").toString().isEmpty() && !imported.value("builtIn").toBool(), "imports receive local identity");
    check(imported.value("appearance")==aurora.value("appearance"), "share retains appearance");
    check(ThemeStore(second.path()).themes().size()==11, "custom themes survive restart");
    for (const QString& cat : {QString("kitteh"),QString("rory"),QString("rory-flat"),QString("teawie")}) {
        const auto theme=store.theme("official-prism-"+cat);
        check(theme.value("appearance").toMap().value("cat").toString()==cat, "each Prism cat is included");
        check(store.catImage(cat).startsWith("qrc:/backgrounds/"+cat), "cat uses the bundled Prism resource");
        check(store.exportTheme("official-prism-"+cat,QUrl::fromLocalFile(shared)), "export Prism cat theme");
        const auto restored=receiver.importTheme(QUrl::fromLocalFile(shared));
        check(restored.value("appearance").toMap().value("cat").toString()==cat, "cat selection survives sharing");
    }
    check(store.catImage("../../private").isEmpty(), "cat paths are restricted to built-in packs");
    auto playerCat=QJsonObject::fromVariantMap(store.theme("official-prism-kitteh"));
    playerCat.insert("name","My cat theme");
    const auto savedCat=store.saveTheme(playerCat.toVariantMap());
    check(savedCat.value("appearance").toMap().value("cat").toString()=="kitteh", "player themes retain selected cat");
    check(store.exportTheme(savedCat.value("id").toString(),QUrl::fromLocalFile(shared)), "export player cat theme");
    check(receiver.importTheme(QUrl::fromLocalFile(shared)).value("appearance").toMap().value("cat").toString()=="kitteh", "shared player theme retains cat");
    check(store.removeTheme(savedCat.value("id").toString()), "remove player cat test fixture");

    auto custom=QJsonObject::fromVariantMap(aurora);
    custom.insert("name","../player theme"); custom.insert("author","Player");
    auto look=custom.value("appearance").toObject();
    auto glass=look.value("glass").toObject();
    glass.insert("reducedMotion",false); glass.insert("increaseContrast",false);
    look.insert("glass",glass); custom.insert("appearance",look);
    const auto saved=store.saveTheme(custom.toVariantMap());
    check(!saved.isEmpty(), "save current appearance");
    check(!saved.value("appearance").toMap().value("glass").toMap().contains("reducedMotion"), "themes exclude accessibility settings");
    const auto files=QDir(first.filePath("themes")).entryList({"*.json"},QDir::Files);
    check(files.size()==1 && !files.first().contains("player"), "metadata never becomes a file path");

    const auto count=store.themes().size();
    auto reject=[&](const QJsonObject& document,const char* label) {
        write(shared,document);
        check(store.importTheme(QUrl::fromLocalFile(shared)).isEmpty() && !store.error().isEmpty() && store.themes().size()==count,label);
    };
    auto bad=custom; bad.insert("version",2); reject(bad,"reject future format without changing library");
    bad=custom; look=bad.value("appearance").toObject(); look.insert("cat","../../private"); bad.insert("appearance",look); reject(bad,"reject arbitrary cat paths");
    bad=custom; look=bad.value("appearance").toObject(); glass=look.value("glass").toObject();
    glass.insert("frost",4); look.insert("glass",glass); bad.insert("appearance",look); reject(bad,"reject invalid glass range");
    glass.insert("frost",0.3); glass.insert("materialVariant",1.5); look.insert("glass",glass); bad.insert("appearance",look); reject(bad,"reject fractional material mode");
    bad=custom; look=bad.value("appearance").toObject(); look.insert("accent","url(file:///secret)"); bad.insert("appearance",look); reject(bad,"reject invalid colours");
    bad=custom; look=bad.value("appearance").toObject();
    look.insert("background",QJsonObject{{"kind","image"},{"image","https://example.invalid/remote.png"},{"placement","Fill"}});
    bad.insert("appearance",look); reject(bad,"reject remote wallpaper references");
    look.insert("background",QJsonObject{{"kind","image"},{"image",QUrl::fromLocalFile(first.filePath("private.png")).toString()},{"placement","Fill"}});
    bad.insert("appearance",look); reject(bad,"import cannot read recipient local files");
    look.insert("background",QJsonObject{{"kind","image"},{"image","data:image/png;base64,%%%"},{"placement","Fill"}});
    bad.insert("appearance",look); reject(bad,"reject corrupt embedded image");

    QImage image(32,32,QImage::Format_ARGB32); image.fill(Qt::cyan);
    const QString wallpaper=first.filePath("wallpaper.png"); check(image.save(wallpaper),"wallpaper fixture");
    look=custom.value("appearance").toObject();
    look.insert("background",QJsonObject{{"kind","image"},{"image",QUrl::fromLocalFile(wallpaper).toString()},{"placement","Fit"}});
    custom.insert("appearance",look);
    const auto imageTheme=store.saveTheme(custom.toVariantMap());
    const QString embedded=imageTheme.value("appearance").toMap().value("background").toMap().value("image").toString();
    check(embedded.startsWith("data:image/png;base64,"), "local wallpaper is embedded");
    const QUrl cached(store.wallpaperForTheme(imageTheme.value("id").toString()));
    check(cached.isLocalFile() && QImage(cached.toLocalFile()).pixelColor(0,0)==Qt::cyan,"materialize wallpaper for native and QML renderers");
    check(store.exportTheme(imageTheme.value("id").toString(),QUrl::fromLocalFile(shared)), "export image theme");
    check(QFile::remove(wallpaper),"remove author's wallpaper");
    const auto sharedImage=receiver.importTheme(QUrl::fromLocalFile(shared));
    check(sharedImage.value("appearance").toMap().value("background").toMap().value("image").toString()==embedded,"wallpaper works without author's files");
    check(store.removeTheme(saved.value("id").toString()),"remove player theme");
    check(ThemeStore(first.path()).themes().size()==11,"removed entry stays removed after restart");
    std::cout << "ThemeStoreTest passed\n";
}
