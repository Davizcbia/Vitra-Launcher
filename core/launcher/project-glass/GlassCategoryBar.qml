// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

Item {
    id: bar
    property var options: []
    property string selected: ""
    property bool reducedMotion: false
    property bool fusionEnabled: true
    property color foreground: "white"
    property color accent: "#0A84FF"
    property Component material
    property int pressedIndex: -1
    property int lastPressedIndex: -1
    property int geometryRevision: 0
    property real fusionProgress: pressedIndex >= 0 && fusionEnabled && !reducedMotion ? 1 : 0
    Behavior on fusionProgress { enabled: !bar.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    signal chosen(string value)
    implicitWidth: buttons.width
    implicitHeight: 56
    function shape(index) {
        var revision = geometryRevision
        var button = repeater.itemAt(index)
        if (!button) return Qt.vector4d(0,0,0,0)
        return Qt.vector4d(button.x + (1-button.scale)*button.width/2,
                          button.y + 8 + (1-button.scale)*button.height/2,
                          button.width*button.scale, button.height*button.scale)
    }
    Loader { anchors.fill: parent; sourceComponent: bar.material }
    Row {
        id: buttons
        y: 8; spacing: 7
        Repeater {
            id: repeater
            model: bar.options
            onItemAdded: bar.geometryRevision++
            onItemRemoved: bar.geometryRevision++
            delegate: Item {
                id: button
                required property string modelData
                required property int index
                objectName: "categoryButton-" + modelData
                width: label.implicitWidth+28; height: 40
                scale: bar.reducedMotion ? 1 : pointer.pressed ? 1.07 : pointer.containsMouse ? 1.025 : 1
                Behavior on scale { enabled: !bar.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
                Rectangle { anchors.fill: parent; radius: height/2; color: "#20FFFFFF"; visible: !bar.material }
                Text { id: label; anchors.centerIn: parent; text: (prismBridge.languageRevision, qsTranslate("ProjectGlass", button.modelData)); color: bar.selected===button.modelData ? bar.accent : bar.foreground; font.pixelSize: 13; font.weight: bar.selected===button.modelData ? Font.DemiBold : Font.Normal }
                activeFocusOnTab: true
                Accessible.role: Accessible.Button; Accessible.name: modelData
                Keys.onSpacePressed: bar.chosen(modelData)
                Keys.onReturnPressed: bar.chosen(modelData)
                MouseArea {
                    id: pointer
                    anchors.fill: parent; hoverEnabled: true
                    onPressed: { bar.pressedIndex=button.index; bar.lastPressedIndex=button.index }
                    onReleased: bar.pressedIndex=-1
                    onCanceled: bar.pressedIndex=-1
                    onClicked: bar.chosen(button.modelData)
                }
            }
        }
    }
}
