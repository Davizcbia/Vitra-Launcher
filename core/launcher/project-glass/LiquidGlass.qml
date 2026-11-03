// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// A surface draws only its material. Labels, hit regions and actions stay in
// the owning control. All instances share textures supplied by the scene.
Item {
    id: glass
    required property Item surface
    required property Item viewport
    property var sharpTexture
    property var blurredTexture
    // Optional content in front of the glass, seen through it (same frame as
    // sharpTexture): the bevel refracts it, the flat centre leaves it sharp.
    property var foregroundTexture: null
    property real foregroundBevel: 16
    property real radius: 0
    property bool circular: false
    property bool fusion: false
    property vector4d firstShape: Qt.vector4d(0,0,width,height)
    property vector4d secondShape: Qt.vector4d(0,0,0,0)
    property real fusionDistance: 40
    // A row of capsules uses the same smooth-union material as the lab's
    // card/ball fusion. Only neighbours of the pressed capsule merge.
    property int capsuleCount: 0
    property int pressedCapsule: -1
    property real capsuleFusionProgress: 0
    property vector4d capsuleOne: Qt.vector4d(0,0,0,0)
    property vector4d capsuleTwo: Qt.vector4d(0,0,0,0)
    property vector4d capsuleThree: Qt.vector4d(0,0,0,0)
    property vector4d capsuleFour: Qt.vector4d(0,0,0,0)
    property vector4d capsuleFive: Qt.vector4d(0,0,0,0)
    property color tint: "transparent"
    property color stroke: "transparent"
    property real strokeWidth: 0
    property real density: 0.35
    property real frost: 0.72
    property real refraction: 0.55
    property real refractionDirection: 1
    property real flatBevel: 0
    property real glare: 0.55
    property real refractiveIndex: 1.45
    property real bevelWidth: 16
    property real dispersion: 0.035
    property real magnification: 1
    property real saturation: 1.1
    property real brightness: 1
    property real fresnelAmount: 1
    property real specularAmount: 1
    property real edgeAmount: 1
    property real shadowAmount: 1
    property real lightAngle: -120
    property real interactionStrength: 1
    property real interactionRadius: 70
    property real responseTime: 80
    // Controls with an input handler above the visual surface can forward the
    // pointer explicitly; the passive observer cannot see those presses.
    property bool externalInteractionEnabled: false
    property vector4d externalInteraction: Qt.vector4d(width/2,height/2,0,0)
    property bool dark: true
    property bool reducedTransparency: false
    property bool reducedMotion: false
    property url shader: "qrc:/pgshaders/liquidglass.frag.qsb"

    // Read ancestor geometry as binding dependencies: mapToItem() alone does
    // not notify when a Flickable, popup or ancestor animation moves the item.
    readonly property vector4d sceneRect: {
        var geometry = 0
        for (var item = surface; item; item = item.parent) {
            geometry += item.x + item.y + item.width + item.height + item.scale + item.rotation
        }
        if (!viewport || !surface || !isFinite(geometry)) return Qt.vector4d(0, 0, 1, 1)
        var p = surface.mapToItem(viewport, 0, 0)
        var q = surface.mapToItem(viewport, surface.width, surface.height)
        return Qt.vector4d(p.x, p.y, q.x - p.x, q.y - p.y)
    }

    // Observe before child MouseAreas accept the press. A passive grab does
    // not consume clicks or prevent the existing drag/scroll handlers.
    Item {
        parent: glass.surface
        anchors.fill: parent
        z: 10000
        visible: glass.visible
        HoverHandler { id: hover; enabled: !glass.reducedMotion }
        PointHandler { id: press; target: null; enabled: !glass.reducedMotion }
    }
    property real hoverAmount: reducedMotion ? 0 : (externalInteractionEnabled ? externalInteraction.z : (hover.hovered ? 1 : 0))
    property real pressAmount: reducedMotion ? 0 : (externalInteractionEnabled ? externalInteraction.w : (press.active ? 1 : 0))
    property real pointerX: externalInteractionEnabled && !reducedMotion ? externalInteraction.x : (press.active ? press.point.position.x : hover.hovered ? hover.point.position.x : width / 2)
    property real pointerY: externalInteractionEnabled && !reducedMotion ? externalInteraction.y : (press.active ? press.point.position.y : hover.hovered ? hover.point.position.y : height / 2)
    Behavior on hoverAmount { enabled: !glass.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on pressAmount { enabled: !glass.reducedMotion; NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
    Behavior on pointerX { enabled: !glass.reducedMotion; NumberAnimation { duration: glass.responseTime; easing.type: Easing.OutCubic } }
    Behavior on pointerY { enabled: !glass.reducedMotion; NumberAnimation { duration: glass.responseTime; easing.type: Easing.OutCubic } }

    ShaderEffect {
        objectName: "liquidGlassShader"
        x: -12; y: -12; width: glass.width + 24; height: glass.height + 24
        property var sharpSource: glass.sharpTexture
        property var blurredSource: glass.blurredTexture
        property var foregroundSource: glass.foregroundTexture || glass.sharpTexture
        property real foregroundAmount: glass.foregroundTexture ? 1 : 0
        property real foregroundBevel: glass.foregroundBevel
        property vector2d viewportSize: Qt.vector2d(glass.viewport.width, glass.viewport.height)
        property vector2d surfaceSize: Qt.vector2d(glass.width, glass.height)
        property vector2d sharpTextureSize: Qt.vector2d(glass.sharpTexture ? glass.sharpTexture.textureSize.width : 1, glass.sharpTexture ? glass.sharpTexture.textureSize.height : 1)
        property vector2d blurredTextureSize: Qt.vector2d(glass.blurredTexture ? glass.blurredTexture.textureSize.width : 1, glass.blurredTexture ? glass.blurredTexture.textureSize.height : 1)
        property vector4d panelRect: glass.sceneRect
        property real cornerRadius: glass.radius
        property real circularShape: glass.circular ? 1 : 0
        property vector4d shapeA: glass.firstShape
        property vector4d shapeB: glass.secondShape
        property vector4d fusionConfig: Qt.vector4d(glass.fusion?1:0,Math.max(0.01,glass.fusionDistance),glass.radius,0)
        property vector4d capsuleConfig: Qt.vector4d(glass.capsuleCount, glass.fusionDistance, glass.pressedCapsule, glass.capsuleFusionProgress)
        property vector4d capsuleOne: glass.capsuleOne
        property vector4d capsuleTwo: glass.capsuleTwo
        property vector4d capsuleThree: glass.capsuleThree
        property vector4d capsuleFour: glass.capsuleFour
        property vector4d capsuleFive: glass.capsuleFive
        property real darkAppearance: glass.dark ? 1 : 0
        property real blurStrength: Math.max(0, Math.min(1, glass.frost))
        property real reduceTransparency: glass.reducedTransparency ? 1 : 0
        property color tintColor: glass.tint
        property color strokeColor: glass.stroke
        property real strokeWidth: glass.strokeWidth
        property real materialDensity: glass.density
        property real refractionStrength: Math.max(0, Math.min(1, glass.refraction))
        property real refractionDirection: glass.refractionDirection
        property real flatBevel: Math.min(1, glass.flatBevel)
        property real glareStrength: Math.max(0, Math.min(1, glass.glare))
        property vector4d interaction: Qt.vector4d(glass.pointerX, glass.pointerY, glass.hoverAmount, glass.pressAmount)
        property vector4d optics: Qt.vector4d(Math.max(1,glass.refractiveIndex), Math.max(0.1,glass.bevelWidth), Math.max(0,glass.dispersion), Math.max(0.25,glass.magnification))
        property vector4d lighting: Qt.vector4d(glass.fresnelAmount, glass.specularAmount, glass.edgeAmount, glass.lightAngle * Math.PI / 180)
        property vector4d appearance: Qt.vector4d(glass.saturation, glass.brightness, glass.shadowAmount, 0)
        property vector2d touch: Qt.vector2d(glass.interactionStrength, Math.max(1,glass.interactionRadius))
        fragmentShader: glass.shader
    }
}
