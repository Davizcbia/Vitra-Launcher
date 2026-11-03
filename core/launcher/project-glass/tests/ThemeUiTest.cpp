// SPDX-License-Identifier: GPL-3.0-only
#include "../ThemeStore.h"
#include "../MacWindowMetrics.h"
#include <QFile>
#include <QMimeData>
#ifdef VITRA_HAS_WINDOW_DRAG_TEST
#include <qpa/qplatformdrag.h>
#include <qpa/qwindowsysteminterface.h>
#endif
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QTemporaryDir>
#include <QtQuickTest/quicktest.h>
class ReviewHarness : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QVariant evaluate(QObject* object, const QString& code)
    {
        QQmlExpression expression(qmlContext(object),object,code);
        auto result=expression.evaluate();
        if (expression.hasError()) qFatal("Review expression failed: %s",qPrintable(expression.error().toString()));
        return result;
    }
    Q_INVOKABLE bool captureWindow(QObject* object, const QString& path)
    {
        auto* window=qobject_cast<QQuickWindow*>(object);
        return window && window->grabWindow().save(path);
    }
    Q_INVOKABLE bool supportsWindowDrag() const
    {
#ifdef VITRA_HAS_WINDOW_DRAG_TEST
        return true;
#else
        return false;
#endif
    }
    Q_INVOKABLE bool dropFiles(QObject* object, const QVariantList& urls)
    {
        return dispatchDrop(object,urls,Qt::CopyAction,Qt::NoModifier);
    }
    Q_INVOKABLE bool dropFilesWithShift(QObject* object, const QVariantList& urls)
    {
        return dispatchDrop(object,urls,Qt::CopyAction | Qt::MoveAction,Qt::ShiftModifier);
    }
    Q_INVOKABLE bool dropMoveOnly(QObject* object, const QVariantList& urls)
    {
        return dispatchDrop(object,urls,Qt::MoveAction,Qt::ShiftModifier);
    }
    bool dispatchDrop(QObject* object, const QVariantList& urls, Qt::DropActions actions, Qt::KeyboardModifiers modifiers)
    {
#ifdef VITRA_HAS_WINDOW_DRAG_TEST
        auto* window=qobject_cast<QQuickWindow*>(object);
        if (!window) return false;
        QMimeData mime;
        QList<QUrl> converted;
        for (const auto& url : urls) converted.append(QUrl(url.toString()));
        if (!converted.isEmpty()) mime.setUrls(converted); else mime.setText("not a file");
        const QPoint position(100,100);
        const auto drag=QWindowSystemInterface::handleDrag(window,&mime,position,actions,Qt::LeftButton,modifiers);
        if (!drag.isAccepted()) {
            QWindowSystemInterface::handleDrag(window,nullptr,position,actions,Qt::LeftButton,modifiers);
            return false;
        }
        const auto drop=QWindowSystemInterface::handleDrop(window,&mime,position,actions,Qt::LeftButton,modifiers);
        return drop.isAccepted() && drop.acceptedAction()==Qt::CopyAction;
#else
        Q_UNUSED(object); Q_UNUSED(urls); Q_UNUSED(actions); Q_UNUSED(modifiers);
        return false;
#endif
    }
};
// Only the core adapter is mocked. The frontend, material renderer, theme
// store and all dialog controls below are the production components.
static QObject* bridgeMock(QQmlEngine* engine)
{
    QFile file(QStringLiteral(FRONTEND_SOURCE_DIR "/PrismBridge.h"));
    if (!file.open(QIODevice::ReadOnly)) qFatal("Cannot read bridge declarations");
    const QString header=QString::fromUtf8(file.readAll());
    QString body="import QtQuick\nQtObject {\nproperty var dropRequests: []\n";
    QSet<QString> properties, methods;
    auto props=QRegularExpression("Q_PROPERTY\\((\\w+) (\\w+)").globalMatch(header);
    while (props.hasNext()) {
        const auto match=props.next(); const QString type=match.captured(1), name=match.captured(2);
        QString qmlType="string", value="\"\"";
        if (type=="bool") { qmlType="bool"; value=name=="offlineMode"?"true":"false"; }
        else if (type=="int") { qmlType="int"; value="0"; }
        else if (type=="double") { qmlType="real"; value="0"; }
        else if (type=="QVariantList") { qmlType="var"; value="[]"; }
        else if (type=="QVariantMap") { qmlType="var"; value="({})"; }
        body+="property "+qmlType+" "+name+": "+value+"\n"; properties.insert(name);
    }
    auto functions=QRegularExpression("Q_INVOKABLE\\s+(\\w+)\\s+(\\w+)\\(").globalMatch(header);
    while (functions.hasNext()) {
        const auto match=functions.next(); const QString type=match.captured(1), name=match.captured(2);
        if (methods.contains(name) || properties.contains(name)) continue;
        methods.insert(name);
        if (name=="importLocalModpack") {
            body+="function importLocalModpack(url) { dropRequests=dropRequests.concat([String(url)]); status=\"Importing\"; importingLocalPack=true; canCancelInstall=true; return true }\n";
            continue;
        }
        QString value="\"\"";
        if (type=="QVariantList" || type=="QStringList") value="[]";
        else if (type=="QVariantMap") value="({})";
        else if (type=="bool") value="false";
        else if (type=="int" || type=="double") value="0";
        else if (type=="QVariant") value="null";
        body+="function "+name+"() { return "+value+" }\n";
    }
    const auto signalsSection=header.mid(header.indexOf("signals:"));
    auto signalMatches=QRegularExpression("void (\\w+)\\(([^)]*)\\)").globalMatch(signalsSection.left(signalsSection.indexOf("private:")));
    while (signalMatches.hasNext()) {
        const auto match=signalMatches.next(); QStringList args;
        if (!match.captured(2).trimmed().isEmpty()) {
            const auto count=match.captured(2).split(',').size();
            for (int i=0;i<count;++i) args.append("var arg"+QString::number(i));
        }
        const QString name=match.captured(1);
        if (!properties.contains(name) && !(name.endsWith("Changed") && properties.contains(name.chopped(7))))
            body+="signal "+name+"("+args.join(',')+")\n";
    }
    QQmlComponent component(engine); component.setData((body+"}").toUtf8(),QUrl());
    auto* object=component.create();
    if (!object) qFatal("Cannot create review bridge: %s",qPrintable(component.errorString()));
    object->setParent(engine); return object;
}
class ThemeUiSetup : public QObject {
    Q_OBJECT
public slots:
    void applicationAvailable()
    {
        QQuickStyle::setStyle("Basic");
        QCoreApplication::setOrganizationName("VitraReview");
        QCoreApplication::setApplicationName("ThemeUi");
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,temporary.path());
    }
    void qmlEngineAvailable(QQmlEngine* engine)
    {
        engine->rootContext()->setContextProperty("themeStore",new ThemeStore(temporary.path(),engine));
        engine->rootContext()->setContextProperty("reviewOutput",qEnvironmentVariable("VITRA_REVIEW_OUTPUT"));
        engine->rootContext()->setContextProperty("reviewHarness",new ReviewHarness(engine));
        engine->rootContext()->setContextProperty("prismBridge",bridgeMock(engine));
        engine->rootContext()->setContextProperty("macWindowMetrics",new MacWindowMetrics(engine));
        QQmlComponent sync(engine);
        sync.setData("import QtQuick\nQtObject { property string state: \"idle\"; property string pin: \"\"; property string message: \"\"; property int secondsLeft: 0; property string address: \"\"; property var preview: ({}); property int completed: 0; property int total: 0; property var failures: []; function cancel() {} function startShare() {} function connectCode() {} function apply() {} }",QUrl());
        auto* syncObject=sync.create(); syncObject->setParent(engine);
        engine->rootContext()->setContextProperty("instanceSync",syncObject);
    }
private:
    QTemporaryDir temporary;
};
QUICK_TEST_MAIN_WITH_SETUP(ThemeUi,ThemeUiSetup)
#include "ThemeUiTest.moc"
