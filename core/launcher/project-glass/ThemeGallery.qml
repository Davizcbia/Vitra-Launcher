// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: gallery
    property var themes: []
    property string selectedId: ""
    property color ink: "white"
    property color muted: "#AAB8CC"
    property color accent: "#65D9D1"
    property bool dark: true
    property var catImageFor: function(id) { return "" }
    property url clipShader: "qrc:/pgshaders/continuousclip.frag.qsb"
    signal selected(string themeId)
    implicitHeight: grid.implicitHeight
    GridLayout {
        id: grid
        width: parent.width
        columns: gallery.width >= 600 ? 3 : 2
        columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: gallery.themes
            delegate: Item {
                id: card
                required property var modelData
                objectName: "themeCard-" + modelData.id
                readonly property var appearance: modelData.appearance
                readonly property var background: appearance.background
                readonly property bool chosen: gallery.selectedId === modelData.id
                Layout.fillWidth: true
                Layout.preferredHeight: 166
                Layout.minimumWidth: 130
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.name
                Accessible.checked: chosen
                activeFocusOnTab: true
                Keys.onSpacePressed: gallery.selected(modelData.id)
                Keys.onReturnPressed: gallery.selected(modelData.id)
                RoundedPanel {
                    anchors.fill: parent; radius: 18
                    clipShader: gallery.clipShader
                    color: gallery.dark ? "#10FFFFFF" : "#08000000"
                    rimWidth: card.chosen || card.activeFocus ? 2 : 1
                    rimColor: card.chosen || card.activeFocus ? gallery.accent : gallery.dark ? "#22FFFFFF" : "#18000000"
                }
                RoundedPanel {
                    x: 6; y: 6; width: parent.width - 12; height: 100; radius: 12
                    clipShader: gallery.clipShader
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: card.background.kind === "gradient" ? card.background.stops[0].color : "#243344" }
                            GradientStop { position: 1; color: card.background.kind === "gradient" ? card.background.stops[card.background.stops.length-1].color : "#243344" }
                        }
                    }
                    Image { anchors.fill: parent; visible: card.background.kind === "image"; source: visible ? card.background.image : ""; fillMode: Image.PreserveAspectCrop; sourceSize.width: 400 }
                    Rectangle { x: 10; y: 12; width: 28; height: 76; radius: 8; color: card.appearance.mode === "Light" ? "#99FFFFFF" : "#55202028" }
                    Rectangle { x: 46; y: 18; width: parent.width-62; height: 12; radius: 6; color: card.appearance.mode === "Light" ? "#88000000" : "#88FFFFFF" }
                    Rectangle { x: 46; y: 38; width: (parent.width-62)*0.7; height: 7; radius: 3.5; color: card.appearance.mode === "Light" ? "#33000000" : "#55FFFFFF" }
                    Rectangle { x: 46; y: 62; width: 50; height: 22; radius: 11; color: card.appearance.accent }
                    Image {
                        objectName: "prismCatPreview"
                        visible: !!card.appearance.cat
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 3
                        width: parent.width*0.46; height: parent.height*0.92
                        horizontalAlignment: Image.AlignRight; verticalAlignment: Image.AlignBottom
                        fillMode: Image.PreserveAspectFit; sourceSize.width: 180
                        source: visible ? gallery.catImageFor(card.appearance.cat) : ""
                    }
                }
                Text { x: 12; y: 116; width: parent.width-44; text: card.modelData.name; color: gallery.ink; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; textFormat: Text.PlainText }
                Text { x: 12; y: 139; width: parent.width-24; text: card.modelData.builtIn ? qsTranslate("ProjectGlass","Official") : (card.modelData.author || qsTranslate("ProjectGlass","Player theme")); color: gallery.muted; font.pixelSize: 11; elide: Text.ElideRight; textFormat: Text.PlainText }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 117
                    width: 18; height: 18; radius: 9; color: card.chosen ? gallery.accent : "transparent"
                    border.width: 1; border.color: card.chosen ? gallery.accent : gallery.muted
                    Text { anchors.centerIn: parent; visible: card.chosen; text: "✓"; color: "#15232C"; font.pixelSize: 12 }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { card.forceActiveFocus(); gallery.selected(card.modelData.id) } }
            }
        }
    }
}
