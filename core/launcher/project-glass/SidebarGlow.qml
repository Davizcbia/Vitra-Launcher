// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Effects

Item {
    id: glow
    property Item scene
    property real sceneLeft: 0
    property real sampleWidth: 240
    property real softness: 1
    property real saturation: 0.5
    property bool active: true
    property url shader: "qrc:/pgshaders/sidebarglow.frag.qsb"
    visible: active
    ShaderEffectSource {
        id: capture
        sourceItem: glow.active ? glow.scene : null
        sourceRect: Qt.rect(glow.sceneLeft, 0, Math.max(1, Math.min(glow.sampleWidth, glow.scene ? glow.scene.width-glow.sceneLeft : 1)), glow.height)
        // Avoid stretching a handful of 8-bit columns into visible stripes.
        textureSize: Qt.size(Math.max(96, Math.ceil(glow.width)), Math.max(1, Math.ceil(glow.height / 2)))
        format: ShaderEffectSource.RGBA16F
        live: glow.active; visible: false; smooth: true
    }
    MultiEffect {
        id: softened
        anchors.fill: parent
        source: capture
        blurEnabled: true; blur: glow.softness; blurMax: 64; blurMultiplier: 2
        autoPaddingEnabled: false; saturation: glow.saturation
        visible: false; layer.enabled: true; layer.smooth: true
        layer.format: ShaderEffectSource.RGBA16F
    }
    ShaderEffect {
        anchors.fill: parent
        property var glowSource: softened
        fragmentShader: glow.shader
    }
}
