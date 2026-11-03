// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// One continuous contour for the fill, rim and children. This avoids mixing
// circular Rectangle corners with a differently clipped material on top.
Item {
    id: panel
    property real radius: 24
    property color color: "transparent"
    property real rimWidth: 0
    property color rimColor: "transparent"
    property url clipShader: "qrc:/pgshaders/continuousclip.frag.qsb"
    layer.enabled: true
    layer.smooth: true
    layer.effect: ContinuousClip {
        radius: panel.radius
        rimWidth: panel.rimWidth
        rimColor: panel.rimColor
        fragmentShader: panel.clipShader
    }
    Rectangle { anchors.fill: parent; color: panel.color }
}
