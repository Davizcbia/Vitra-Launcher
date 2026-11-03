// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// Analytic coverage at the final physical pixel size. No thresholded mask
// texture, tessellation seams or residual alpha outside the contour.
ShaderEffect {
    property var source
    property real radius: 24
    property vector2d surfaceSize: Qt.vector2d(width, height)
    // Optional line just inside the contour, following the continuous corners.
    property real rimWidth: 0
    property color rimColor: "transparent"
    fragmentShader: "qrc:/pgshaders/continuousclip.frag.qsb"
}
