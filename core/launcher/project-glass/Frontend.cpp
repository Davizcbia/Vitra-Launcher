// SPDX-License-Identifier: GPL-3.0-only
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>
#include <QPointer>
#include <QEvent>
#include <QApplication>
#include <QStyleFactory>
#include <QWindow>
#include <QWidget>
#include <QMenu>
#include <QSettings>
#include <QFont>
#ifdef Q_OS_MACOS
void clearMacPopupBackground(QWindow *window);
#endif
class PopupTransparency final:public QObject {
public:using QObject::QObject;
 bool eventFilter(QObject *object,QEvent *event)override {
  if(event->type()==QEvent::Polish){
   if(auto *widget=qobject_cast<QWidget *>(object)) {
    if(widget->isWindow() && (widget->windowType()==Qt::Popup || widget->windowType()==Qt::ToolTip)) {
     widget->setAttribute(Qt::WA_TranslucentBackground,true);
     widget->setAutoFillBackground(false);
    }
   }
  }
  if(event->type()==QEvent::Show || event->type()==QEvent::Expose){
#ifdef Q_OS_MACOS
   if(auto *widget=qobject_cast<QWidget *>(object)) {
    if(widget->isWindow() && (widget->windowType()==Qt::Popup || widget->windowType()==Qt::ToolTip))
     if(auto *handle=widget->windowHandle())clearMacPopupBackground(handle);
   }
   if(auto *handle=qobject_cast<QWindow *>(object)) {
    if(handle->type()==Qt::Popup || handle->type()==Qt::ToolTip)clearMacPopupBackground(handle);
   }
#endif
   if(auto *window=qobject_cast<QQuickWindow *>(object)) {
    window->setColor(Qt::transparent);
#ifdef Q_OS_MACOS
    if(window->transientParent() && (window->type()==Qt::Popup || window->type()==Qt::ToolTip || window->type()==Qt::Tool)) {
     clearMacPopupBackground(window);
     QTimer::singleShot(0,window,[window]{clearMacPopupBackground(window);});
    }
#endif
   }

  }return false;
 }
};
#include "Application.h"
#include "InstanceSync.h"
#include "PrismBridge.h"
#include "ThemeStore.h"
#include "MacWindowMetrics.h"
#ifdef Q_OS_MACOS
void configureMacWindow(QQuickWindow *,MacWindowMetrics *);
#else
#include <QBuffer>
#include <QHash>
#include <QImageReader>
#include <QPainter>
// SF Symbols exist only on macOS. Elsewhere the same names resolve to the
// bundled stand-ins in assets/symbols, tinted and returned as PNG data URLs,
// matching what the AppKit reader hands to QML.
static QString bundledSymbolIcon(const QString &name,const QString &hex){
    static QHash<QString,QString> cache;
    const QString key=name+QLatin1Char('|')+hex;
    if(const auto it=cache.constFind(key);it!=cache.cend())return *it;
    static const QHash<QString,QString> aliases{
        {QStringLiteral("appkit.disclosure.open"),QStringLiteral("chevron.up")},
        {QStringLiteral("appkit.disclosure.closed"),QStringLiteral("chevron.right")},
        {QStringLiteral("appkit.selector"),QStringLiteral("chevron.up.chevron.down")}};
    const QColor tint(hex);
    QImageReader reader(QStringLiteral(":/qt/qml/ProjectGlass/assets/symbols/%1.svg").arg(aliases.value(name,name)));
    reader.setScaledSize(QSize(64,64)); // Sharp at 16-28 pt up to 2x scaling.
    QImage image=reader.read();
    if(image.isNull() || !tint.isValid())return cache[key]=QString();
    image=image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    QPainter painter(&image);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(image.rect(),tint);
    painter.end();
    QByteArray png;QBuffer buffer(&png);buffer.open(QIODevice::WriteOnly);image.save(&buffer,"PNG");
    return cache[key]=QStringLiteral("data:image/png;base64,")+QString::fromLatin1(png.toBase64());
}
#endif
#ifdef Q_OS_WIN
#include <QAbstractNativeEventFilter>
#include <QCoreApplication>
#include <dwmapi.h>
#include <windowsx.h>
// macOS-style window chrome on Windows 11. DWM only offers 8 px, 4 px or
// square corners, so the main window is created frameless (Qt then composes
// it with per-pixel alpha) and QML draws 16 pt corners and the window
// buttons. The resizable frame styles are restored, while WM_NCCALCSIZE keeps
// the whole window as client area: resize edges, Snap and maximize stay native.
class WindowsChrome final:public QAbstractNativeEventFilter {
public:
    explicit WindowsChrome(QWindow *window):hwnd(reinterpret_cast<HWND>(window->winId())){
        SetWindowLongPtrW(hwnd,GWL_STYLE,GetWindowLongPtrW(hwnd,GWL_STYLE)|WS_THICKFRAME|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX|WS_MAXIMIZEBOX);
        const DWM_WINDOW_CORNER_PREFERENCE corners=DWMWCP_DONOTROUND;
        DwmSetWindowAttribute(hwnd,DWMWA_WINDOW_CORNER_PREFERENCE,&corners,sizeof(corners));
        // The 1 px DWM border would trace the square outline around the round corners.
        const COLORREF noBorder=DWMWA_COLOR_NONE;
        DwmSetWindowAttribute(hwnd,DWMWA_BORDER_COLOR,&noBorder,sizeof(noBorder));
        // No frame extension: DWM would paint its frame material behind the
        // transparent corner pixels and lighten whatever is under the window.
        const MARGINS margins{0,0,0,0};
        DwmExtendFrameIntoClientArea(hwnd,&margins);
        SetWindowPos(hwnd,nullptr,0,0,0,0,SWP_FRAMECHANGED|SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    }
    bool nativeEventFilter(const QByteArray &,void *message,qintptr *result)override{
        auto *msg=static_cast<MSG *>(message);
        if(msg->hwnd!=hwnd)return false;
        if(msg->message==WM_NCCALCSIZE && msg->wParam){
            // A maximized window overhangs the monitor by its frame; keep content on screen.
            if(IsZoomed(hwnd)){
                const UINT dpi=GetDpiForWindow(hwnd);
                const int frame=GetSystemMetricsForDpi(SM_CXSIZEFRAME,dpi)+GetSystemMetricsForDpi(SM_CXPADDEDBORDER,dpi);
                RECT &client=reinterpret_cast<NCCALCSIZE_PARAMS *>(msg->lParam)->rgrc[0];
                client.left+=frame;client.right-=frame;client.top+=frame;client.bottom-=frame;
            }
            *result=0;return true;
        }
        if(msg->message==WM_NCHITTEST && !IsZoomed(hwnd)){
            const POINT pt{GET_X_LPARAM(msg->lParam),GET_Y_LPARAM(msg->lParam)};
            RECT r;GetWindowRect(hwnd,&r);
            const int edge=MulDiv(6,GetDpiForWindow(hwnd),96);
            const bool left=pt.x<r.left+edge,right=pt.x>=r.right-edge,top=pt.y<r.top+edge,bottom=pt.y>=r.bottom-edge;
            LRESULT hit=0;
            if(top && left)hit=HTTOPLEFT;else if(top && right)hit=HTTOPRIGHT;
            else if(bottom && left)hit=HTBOTTOMLEFT;else if(bottom && right)hit=HTBOTTOMRIGHT;
            else if(left)hit=HTLEFT;else if(right)hit=HTRIGHT;else if(top)hit=HTTOP;else if(bottom)hit=HTBOTTOM;
            if(hit){*result=hit;return true;}
        }
        return false;
    }
private:
    HWND hwnd;
};
#endif
// Own the frontend explicitly: QObject child creation order is not teardown order.
class FrontendSession final:public QObject {
public:
    explicit FrontendSession(Application *app):QObject(app),app(app){
        bridge=new PrismBridge(app);bridge->setParent(this);
        metrics=new MacWindowMetrics(this);
#ifndef Q_OS_MACOS
        metrics->setSymbolIconReader(bundledSymbolIcon);
#endif
#ifdef Q_OS_WIN
        // Transparent pixels outside the rounded window corners (WindowsChrome).
        QQuickWindow::setDefaultAlphaBuffer(true);
#endif
        engine=new QQmlApplicationEngine(this);
        engine->rootContext()->setContextProperty("prismBridge",bridge);
        engine->rootContext()->setContextProperty("themeStore",new ThemeStore(app->dataRoot(),this));
        auto *sync=new InstanceSync(this->app,[this](const QString &key){return bridge->instanceForKey(key);},
            [this](const QString &game,const QString &loader,const QString &loaderVersion,const QString &name){return bridge->installSharedInstance(game,loader,loaderVersion,name);},this);
        QObject::connect(bridge,&PrismBridge::sharedInstanceCreated,sync,&InstanceSync::instanceCreated);
        QObject::connect(bridge,&PrismBridge::sharedInstanceFailed,sync,&InstanceSync::creationFailed);
        engine->rootContext()->setContextProperty("instanceSync",sync);
        engine->rootContext()->setContextProperty("macWindowMetrics",metrics);
        this->app->installEventFilter(this);
        QObject::connect(app,&QCoreApplication::aboutToQuit,this,[this]{shutdown();});
        QObject::connect(app,&Application::updateAllowedChanged,this,[this](bool allowed){
            if(allowed && closeRequested)this->app->quit();
        });
        QObject::connect(engine,&QQmlApplicationEngine::objectCreated,this,[this](QObject *object,const QUrl &){
            auto *window=qobject_cast<QQuickWindow *>(object);if(!window)return;
            mainWindow=window;window->setColor(Qt::transparent);
#ifdef Q_OS_WIN
            if(!chrome){chrome=new WindowsChrome(window);this->app->installNativeEventFilter(chrome);}
#endif
            if (this->app->property("projectGlassPendingSignIn").toBool()) {
                this->app->setProperty("projectGlassPendingSignIn", false);
                QMetaObject::invokeMethod(bridge, "signIn", Qt::QueuedConnection);
            }
#ifdef Q_OS_MACOS
            QPointer<MacWindowMetrics> safeMetrics=metrics;
            QTimer::singleShot(0,window,[window,safeMetrics]{if(safeMetrics)configureMacWindow(window,safeMetrics);});
#endif
        });
        QObject::connect(engine,&QQmlApplicationEngine::objectCreationFailed,this,[this]{this->app->exit(1);},Qt::QueuedConnection);
        // Settings › Appearance › "macOS system font": applied before the QML
        // loads, since plain Text items take the application font at creation.
        const bool appleFonts=QSettings().value(QStringLiteral("ProjectGlassPrototype091/useSystemFont"),false).toBool();
        if(appleFonts) {
            const auto family=PrismBridge::macSystemFontFamily();
            if(!family.isEmpty()){QFont font=QGuiApplication::font();font.setFamily(family);QGuiApplication::setFont(font);}
        }
#ifdef Q_OS_WIN
        // Chinese interface text: with no CJK family listed, Qt falls back per
        // character and mixes a Japanese face (common Han characters) with
        // Microsoft YaHei (simplified-only ones) at different weights. Listing
        // one Chinese face after the Latin family keeps every Han character in
        // it: PingFang SC when the macOS system font option is on and the user
        // installed it (Apple licenses it for Apple platforms, so it is never
        // bundled), otherwise Microsoft YaHei UI.
        {
            QFont font=QGuiApplication::font();
            QStringList families{font.family()};
            if(appleFonts && QFontDatabase::families().contains(QStringLiteral("PingFang SC")))families<<QStringLiteral("PingFang SC");
            families<<QStringLiteral("Microsoft YaHei UI")<<QStringLiteral("Microsoft YaHei");
            font.setFamilies(families);
            QGuiApplication::setFont(font);
        }
        // DirectWrite text: Qt's distance-field glyphs drew small, dense Chinese
        // characters thin and grey. Scaled text (press and fan animations) is
        // rasterized at its final size instead of staying smooth mid-animation.
        QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
#endif
        engine->loadFromModule("ProjectGlass","Main");
    }
    ~FrontendSession()override{shutdown();}
    bool eventFilter(QObject *object,QEvent *event)override{
        if(!stopping && object==mainWindow && event->type()==QEvent::Close){
            QPointer<FrontendSession> self=this;
            // Check after QML has accepted/rejected closing the window.
            QTimer::singleShot(0,this,[self]{
                if(!self || self->stopping || (self->mainWindow && self->mainWindow->isVisible()))return;
                self->closeRequested=true;
                if(self->app->updatesAreAllowed())self->app->quit();
            });
        }
        return false;
    }
    void shutdown(){
        if(stopping)return;
        stopping=true;this->app->removeEventFilter(this);
        if(bridge)for(auto *timer:bridge->findChildren<QTimer *>())timer->stop();
#ifdef Q_OS_WIN
        if(chrome){this->app->removeNativeEventFilter(chrome);delete chrome;chrome=nullptr;}
#endif
        if(engine){
            for(auto *timer:engine->findChildren<QTimer *>())timer->stop();
            // Destroy QML windows while both context objects remain valid.
            delete engine;engine=nullptr;mainWindow=nullptr;
        }
        if(metrics){metrics->clearNativeCallbacks();delete metrics;metrics=nullptr;}
        this->app->setProperty("projectGlassAuthBridge", QVariant());
        delete bridge;bridge=nullptr;
    }
private:
    Application *app;
    PrismBridge *bridge=nullptr;
    MacWindowMetrics *metrics=nullptr;
    QQmlApplicationEngine *engine=nullptr;
    QPointer<QQuickWindow> mainWindow;
#ifdef Q_OS_WIN
    WindowsChrome *chrome=nullptr;
#endif
    bool stopping=false,closeRequested=false;
};

void startProjectGlass(Application *app){
    auto *wait=new QTimer(app);wait->setInterval(30);
    QObject::connect(wait,&QTimer::timeout,app,[app,wait]{
        if(app->status()==Application::Failed){app->exit(1);return;}
        if(app->status()!=Application::Initialized)return;
        wait->stop();wait->deleteLater();
        app->setStyleSheet(QString());
#ifdef Q_OS_MACOS
        if(auto *style=QStyleFactory::create("macos"))app->setStyle(style);
#endif
        app->installEventFilter(new PopupTransparency(app));
        new FrontendSession(app);
    });wait->start();
}
