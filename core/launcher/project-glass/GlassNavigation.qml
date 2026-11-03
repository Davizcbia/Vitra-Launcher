// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// Same press/stretch/drag/release behaviour as the Glass Lab navigation lens.
Item {
    id: nav
    property var tabs: ["Launch", "Download", "Settings"]
    property int currentIndex: 0
    property bool reducedMotion: false
    property color foreground: "white"
    // Label colour of the current tab (the theme accent).
    property color selectedForeground: foreground
    property color selectionColor: "#30FFFFFF"
    property Component selectionMaterial
    // Drawn above the labels while pressed; it shows them itself, refracted.
    property Component pressedMaterial
    property Item selectionParent: null
    // Notification badges by tab name, e.g. { "Settings": 1 } (iOS red count).
    property var badges: ({})
    readonly property alias selectionItem: lens
    readonly property alias labelsItem: labels
    readonly property alias inputArea: pointer
    readonly property real tabWidth: width / tabs.length
    readonly property bool pressingSelection: pointer.pressed
    property real lensAmount: pressingSelection && !reducedMotion ? 1 : 0
    Behavior on lensAmount { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    property int previewIndex: currentIndex
    property bool draggingSelection: false
    property real dragCenter: 0
    property real dragStretch: 0
    readonly property vector4d interaction: Qt.vector4d(pointer.mouseX-lens.x+lens.origin.x, pointer.mouseY-lens.y+lens.origin.y, 1, pressingSelection ? 1 : 0)
    signal activated(int index)
    implicitWidth: 310; implicitHeight: 44
    Item {
        id: lens
        objectName: "navigationSelection"
        parent: nav.selectionParent || nav
        visible: nav.visible
        readonly property point origin: {
            var geometry=0
            for (var item=nav; item; item=item.parent) geometry+=item.x+item.y+item.width+item.height
            return nav.mapToItem(parent,0,0)
        }
        property real centerPosition: nav.draggingSelection
            ? Math.max(nav.tabWidth/2, Math.min(nav.width-nav.tabWidth/2, nav.dragCenter))
            : ((nav.pressingSelection ? nav.previewIndex : nav.currentIndex)+0.5)*nav.tabWidth
        width: nav.pressingSelection && !nav.reducedMotion ? nav.tabWidth*(1.12+nav.dragStretch) : nav.tabWidth
        height: nav.pressingSelection && !nav.reducedMotion ? 72 : nav.height
        x: origin.x+centerPosition-width/2; y: origin.y+(nav.height-height)/2
        Behavior on centerPosition { enabled: !nav.draggingSelection && !nav.pressingSelection && !nav.reducedMotion; NumberAnimation { duration: 550; easing.type: Easing.OutElastic; easing.period: 0.7 } }
        Behavior on width { enabled: !nav.reducedMotion; NumberAnimation { duration: nav.pressingSelection ? 120 : 550; easing.type: nav.pressingSelection ? Easing.OutCubic : Easing.OutElastic; easing.period: 0.7 } }
        Behavior on height { enabled: !nav.reducedMotion; NumberAnimation { duration: nav.pressingSelection ? 160 : 550; easing.type: nav.pressingSelection ? Easing.OutCubic : Easing.OutElastic; easing.period: 0.7 } }
        Rectangle { anchors.fill: parent; radius: height/2; color: nav.selectionColor; visible: !nav.selectionMaterial }
        Loader { anchors.fill: parent; sourceComponent: nav.selectionMaterial }
    }
    // Above the resting selection, below the pressed lens.
    Row {
        id: labels
        parent: nav.selectionParent || nav
        x: lens.origin.x; y: lens.origin.y; z: 1
        Repeater {
            model: nav.tabs
            delegate: Item {
                required property string modelData
                required property int index
                width: nav.tabWidth; height: nav.height
                activeFocusOnTab: true
                Accessible.role: Accessible.Button; Accessible.name: modelData
                Keys.onReturnPressed: nav.activated(index)
                Keys.onSpacePressed: nav.activated(index)
                Text {
                    id: tabLabel
                    x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
                    // Distance-field glyphs stay sharp while scaled; native ones blur.
                    renderType: Text.QtRendering
                    text: (prismBridge.languageRevision, qsTranslate("ProjectGlass", parent.modelData))
                    color: nav.currentIndex===parent.index ? nav.selectedForeground : nav.foreground
                    font.pixelSize: 13; font.bold: nav.currentIndex===parent.index
                    scale: nav.pressingSelection && !nav.reducedMotion && Math.round(lens.centerPosition/nav.tabWidth-0.5)===parent.index ? 1.25 : 1
                    Behavior on scale { enabled: !nav.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    readonly property int count: nav.badges[parent.modelData] || 0
                    visible: count > 0
                    x: tabLabel.x + tabLabel.width - 2; y: tabLabel.y - height / 2 + 1
                    height: 16; width: Math.max(height, badgeText.implicitWidth + 8); radius: height / 2
                    color: "#FF3B30"
                    Text { id: badgeText; anchors.centerIn: parent; text: parent.count; color: "white"; font.pixelSize: 10; font.bold: true }
                }
            }
        }
    }
    Loader {
        parent: nav.selectionParent || nav
        x: lens.x; y: lens.y; z: 2
        width: lens.width; height: lens.height
        sourceComponent: nav.pressedMaterial
    }
    MouseArea {
        id: pointer
        objectName: "navigationDragArea"
        anchors.fill: parent; hoverEnabled: true; preventStealing: true
        property bool grabbedLens: false
        property real startX: 0
        property real startCenter: 0
        property real lastX: 0
        onPressed: function(mouse) {
            nav.previewIndex=Math.max(0,Math.min(nav.tabs.length-1,Math.floor(mouse.x/nav.tabWidth)))
            startX=mouse.x; lastX=mouse.x; startCenter=(nav.previewIndex+0.5)*nav.tabWidth
            grabbedLens=true
            nav.dragStretch=0; nav.dragCenter=startCenter
        }
        onPositionChanged: function(mouse) {
            if (!pressed || !grabbedLens) return
            if (!nav.draggingSelection && Math.abs(mouse.x-startX)<Qt.styleHints.startDragDistance) return
            nav.dragCenter=startCenter+mouse.x-startX; nav.draggingSelection=true
            nav.dragStretch=Math.min(0.35, Math.abs(mouse.x-lastX)*0.02); lastX=mouse.x
        }
        onReleased: function(mouse) {
            var index=nav.draggingSelection ? Math.round(lens.centerPosition/nav.tabWidth-0.5) : Math.floor(mouse.x/nav.tabWidth)
            nav.activated(Math.max(0,Math.min(nav.tabs.length-1,index)))
            nav.draggingSelection=false; nav.dragStretch=0; grabbedLens=false
        }
        onCanceled: { nav.draggingSelection=false; nav.dragStretch=0; grabbedLens=false }
        onEnabledChanged: if (!enabled) { nav.draggingSelection=false; nav.dragStretch=0; grabbedLens=false }
    }
}
