// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QCursor>
#include <QGuiApplication>
#include <QImage>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPixmap>
#include <QScreen>
#include <QWidget>
#include <functional>

// macOS-style eyedropper: freezes the screen under the cursor in a full-screen
// overlay, follows the pointer with a magnifying loupe, and reports the colour
// clicked. Right-click or Esc cancels. Header-only and signal-free, so it needs
// no moc; the overlay deletes itself when it closes.
class ScreenColorPicker final : public QWidget {
public:
    static void pick(std::function<void(const QColor &)> done)
    {
        auto *picker = new ScreenColorPicker(std::move(done));
        picker->show();
        picker->activateWindow();
        picker->raise();
        picker->grabKeyboard();
    }

private:
    explicit ScreenColorPicker(std::function<void(const QColor &)> done) : m_done(std::move(done))
    {
        QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
        if (!screen)
            screen = QGuiApplication::primaryScreen();
        m_shot = screen->grabWindow(0);
        m_image = m_shot.toImage();
        setWindowFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool);
        setAttribute(Qt::WA_DeleteOnClose);
        setGeometry(screen->geometry());
        setCursor(Qt::CrossCursor);
        setMouseTracking(true);
        m_pos = mapFromGlobal(QCursor::pos());
    }

    QColor colorAt(QPoint logical) const
    {
        const qreal dpr = m_shot.devicePixelRatio();
        const QPoint px(qBound(0, int(logical.x() * dpr), m_image.width() - 1), qBound(0, int(logical.y() * dpr), m_image.height() - 1));
        return m_image.pixelColor(px);
    }

    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.drawPixmap(rect(), m_shot);
        painter.setRenderHint(QPainter::Antialiasing);

        // Loupe: 11 × 11 screen pixels, 11× magnified, beside the pointer and
        // kept on screen.
        constexpr int cells = 11, cell = 11, size = cells * cell;
        QPoint origin = m_pos + QPoint(24, 24);
        if (origin.x() + size > width())
            origin.setX(m_pos.x() - 24 - size);
        if (origin.y() + size + 34 > height())
            origin.setY(m_pos.y() - 24 - size - 34);
        const QRect loupe(origin, QSize(size, size));
        QPainterPath circle;
        circle.addEllipse(loupe);
        painter.save();
        painter.setClipPath(circle);
        const qreal dpr = m_shot.devicePixelRatio();
        const QPoint centre(int(m_pos.x() * dpr), int(m_pos.y() * dpr));
        for (int y = 0; y < cells; ++y)
            for (int x = 0; x < cells; ++x) {
                const QPoint px(qBound(0, centre.x() + x - cells / 2, m_image.width() - 1), qBound(0, centre.y() + y - cells / 2, m_image.height() - 1));
                painter.fillRect(QRect(origin + QPoint(x * cell, y * cell), QSize(cell, cell)), m_image.pixelColor(px));
            }
        painter.restore();
        const QColor picked = colorAt(m_pos);
        painter.setPen(QPen(QColor(255, 255, 255, 230), 1.5));
        painter.setBrush(Qt::NoBrush);
        painter.drawRect(QRect(origin + QPoint((cells / 2) * cell, (cells / 2) * cell), QSize(cell, cell)));
        painter.setPen(QPen(picked.lightness() > 140 ? QColor(0, 0, 0, 160) : QColor(255, 255, 255, 220), 3));
        painter.drawEllipse(loupe);

        // Hex capsule under the loupe.
        const QString hex = picked.name().toUpper();
        QFont font = painter.font();
        font.setPixelSize(12);
        font.setBold(true);
        painter.setFont(font);
        const QRect label(loupe.center().x() - 42, loupe.bottom() + 8, 84, 24);
        painter.setPen(Qt::NoPen);
        painter.setBrush(QColor(28, 28, 32, 230));
        painter.drawRoundedRect(label, 12, 12);
        painter.setPen(Qt::white);
        painter.drawText(label, Qt::AlignCenter, hex);
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        m_pos = event->position().toPoint();
        update();
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton && m_done)
            m_done(colorAt(event->position().toPoint()));
        close();
    }

    void keyPressEvent(QKeyEvent *event) override
    {
        if (event->key() == Qt::Key_Escape)
            close();
    }

    std::function<void(const QColor &)> m_done;
    QPixmap m_shot;
    QImage m_image;
    QPoint m_pos;
};
