import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import "CanvasLayout.js" as CanvasLayout
import "InstanceData.js" as InstanceData
import "DownloadLogic.js" as DownloadLogic

ApplicationWindow {
    id: appRoot
    width: 1220
    height: 780
    minimumWidth: 850
    minimumHeight: 560
    visible: true
    // Empty: Qt then shows the application display name alone ("Vitra Launcher
    // 1.0.0"); any title gets " - <display name>" appended on Windows.
    title: ""
    // Interface text: the "ProjectGlass" context of the translation built from
    // translation/Vitra 界面翻译.xlsx. Reading languageRevision makes
    // every binding that calls this re-evaluate when Core language changes.
    // Values the code compares (categories, options, page names) stay English
    // and are translated only where shown.
    function tr(text) {
        var revision = prismBridge.languageRevision
        return qsTranslate("ProjectGlass", text)
    }
    // Windows: macOS-style chrome (Frontend.cpp WindowsChrome). The window is
    // frameless with native resize/Snap kept; QML rounds it to the macOS 27
    // window radius and draws the window buttons.
    readonly property bool customWindowChrome: Qt.platform.os === "windows"
    // Windows: macOS traffic lights at the top left (on), or Windows 11
    // caption buttons at the top right (off). Settings › Appearance.
    property bool macWindowControls: true
    // Settings › Appearance: traffic lights turn grey while the window is inactive.
    property bool greyInactiveWindowButtons: true
    readonly property bool trafficLights: customWindowChrome && macWindowControls
    // Height of the Windows caption buttons, which top-right controls clear.
    readonly property real captionInset: customWindowChrome && !macWindowControls ? 32 : 0
    // Three 46 pt caption buttons. Toolbar items stay beside them, on their row.
    readonly property real captionWidth: customWindowChrome && !macWindowControls ? 138 : 0
    flags: customWindowChrome ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    // macOS 27's outer window radius for third-party windows (~16 pt, down
    // from Tahoe's 22).
    readonly property real windowRadius: customWindowChrome && visibility !== Window.Maximized
                                         && visibility !== Window.FullScreen ? 16 : 0
    // Settings › Appearance: the window greys a little while another window is active.
    property bool greyInactiveWindow: true
    property real inactiveGrey: customWindowChrome && greyInactiveWindow && !active ? 1 : 0
    Behavior on inactiveGrey { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    contentItem.layer.enabled: windowRadius > 0 || inactiveGrey > 0
    contentItem.layer.smooth: true
    // The 1 pt line AppKit draws just inside every window edge.
    contentItem.layer.effect: ContinuousClip {
        radius: appRoot.windowRadius
        inactive: appRoot.inactiveGrey
        rimWidth: 1
        rimColor: appRoot.darkMode ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1)
    }
    // The first sync also sets up the cards for rows restored from settings.
    property bool prismInstancesSynced: false
    function syncPrismInstances() {
        var records=prismBridge.instances, rows=[]
        for(var r=0;r<instances.count;r++)if(instances.get(r).key.indexOf("prism:")===0)rows.push(r)
        // Same instances: update in place. Rebuilding the rows would recreate
        // every card, and a running game's play time changes on each refresh.
        var sameRows=prismInstancesSynced && rows.length===records.length && records.every(function(record,n){
            var row=instances.get(rows[n])
            return row.key===record.key && row.label===record.label && row.version===record.version && row.coverKey===record.coverKey
        })
        if(sameRows) {
            for(var s=0;s<records.length;s++)instances.set(rows[s],records[s])
            statusMessage=prismBridge.status
            return
        }
        prismInstancesSynced=true
        for(var i=instances.count-1;i>=0;i--)if(instances.get(i).key.indexOf("prism:")===0)instances.remove(i)
        for(var j=0;j<records.length;j++)instances.append(records[j])
        if(records.length && (selectedId.indexOf("prism:")!==0 || !instanceRecord(selectedId)))chooseCard(records[0])
        statusMessage=prismBridge.status
        syncDockArtwork()
        syncCanvasCards()
    }
    Connections {
        target: prismBridge
        function onChanged() { appRoot.statusMessage = prismBridge.status;if(prismBridge.currentAccountName){appRoot.accountDisplayName=prismBridge.currentAccountName;appRoot.accountProvider=appRoot.tr("Microsoft account")} }
        function onLocalPackImportFinished(success,message) {
            appRoot.packImportMessage=message; appRoot.packImportOverride=true; appRoot.packImportNotice=true
            if(success) packImportDismiss.restart()
        }
        function onInstancesChanged() { appRoot.syncPrismInstances() }
        function onInstanceReady(key) {
            var record=appRoot.instanceRecord(key)
            if(record)appRoot.chooseCard(record)
            appRoot.syncDockArtwork();appRoot.syncCanvasCards()
        }
        // A modpack installed from the download page: its project icon becomes
        // the card picture, unless the card already has one.
        function onInstanceArtworkReady(key, url) {
            if(!(appRoot.cardMetadata[key] || {}).background) appRoot.setInstanceMetadata(key, {background: url})
        }
    }
    // A shared instance brought its card background along.
    Connections {
        target: instanceSync
        ignoreUnknownSignals: true
        function onBackgroundReceived(key, url, placement) {
            appRoot.setInstanceMetadata(key, {background: url})
            try { appRoot.setArtworkPlacement(key, JSON.parse(placement || "{}")) } catch (e) {}
        }
    }
    property bool packImportNotice: false
    property bool packImportOverride: false
    property string packImportMessage: ""
    // Title of the drop notice when it is not a modpack import.
    property string noticeTitle: ""
    function handleModpackDrop(urls) {
        packImportDismiss.stop()
        noticeTitle=""
        packImportNotice=true
        if (prismBridge.importingLocalPack) {
            packImportMessage=appRoot.tr("Finish the current installation before importing a modpack.")
            packImportOverride=true
            return
        }
        if (!urls || urls.length !== 1) {
            packImportMessage=appRoot.tr("Drop one modpack file at a time.")
            packImportOverride=true
            return
        }
        packImportMessage=appRoot.tr("Preparing modpack import…")
        packImportOverride=false
        if (!prismBridge.importLocalModpack(urls[0])) {
            packImportMessage=prismBridge.status
            packImportOverride=true
        }
    }
    Timer { id: packImportDismiss; interval: 6000; onTriggered: if (!prismBridge.importingLocalPack) appRoot.packImportNotice=false }
    // Canvas menu › Import modpack from file…
    FileDialog {
        id: modpackFileDialog
        title: appRoot.tr("Import modpack from file")
        nameFilters: [appRoot.tr("Modpacks (*.mrpack *.zip)")]
        onAccepted: appRoot.handleModpackDrop([selectedFile])
    }
    FolderDialog { id:prismRootChooser; title:appRoot.tr("Choose Prism Launcher root"); onAccepted:prismRootField.text=decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//,"")) }
    FileDialog { id:prismExecutableChooser; title:appRoot.tr("Choose Prism executable or .app"); onAccepted:prismExecutableField.text=decodeURIComponent(selectedFile.toString().replace(/^file:\/\//,"")) }
    component ConnectionField: TextField {
        id: connectionField
        implicitHeight:36
        font.pixelSize:13; color:appRoot.ink
        leftPadding:12;rightPadding:12
        selectByMouse:true
        onAccepted:focus=false
        Keys.onEscapePressed:focus=false
        background:GlassSurface {
            objectName:"accountGlassControl";radius:10
            liquidGlass: !appRoot.customWindowChrome
            color: appRoot.customWindowChrome ? appRoot.fieldFill : (macWindowMetrics.nativeAccountGlass ? "transparent" : (appRoot.darkMode?"#24FFFFFF":"#60FFFFFF"))
            border.width: macWindowMetrics.nativeAccountGlass ? 0 : 1
            border.color: appRoot.customWindowChrome ? (connectionField.activeFocus ? appRoot.accent : (appRoot.darkMode ? "#0AFFFFFF" : "#1A000000")) : appRoot.outline
        }
    }
    // Hex field with a leading colour well (macOS NSColorWell): the well shows
    // the colour and opens the shared colour panel.
    component ColorHexField: ConnectionField {
        id: colorHexField
        property color swatch: "black"
        signal picked(string value)
        leftPadding: 38
        font.family: "Consolas"
        Rectangle {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11
            color: colorHexField.swatch
            border.width: 1; border.color: appRoot.darkMode ? "#40FFFFFF" : "#26000000"
            TapHandler { cursorShape: Qt.PointingHandCursor; onTapped: appRoot.pickColor(colorHexField.swatch, function(value) { colorHexField.picked(value) }) }
        }
    }
    // Colour panel in the window (replaces Qt's QColorDialog), laid out as the
    // iOS colour picker: eyedropper, title and close; Grid / Spectrum / Sliders;
    // opacity; the current colour beside saved colours (+ adds the current one).
    // Close (×) keeps the colour; Esc or a click outside cancels.
    property string savedPickerColorsJson: ""
    property string colorPickerMode: "Grid"
    function pickColor(current, callback, title) {
        colorPicker.pickCallback = callback
        colorPicker.title = title || appRoot.tr("Colors")
        colorPicker.setColor(Qt.color(String(current)))
        colorPicker.open()
    }
    // A colour track (opacity, red/green/blue): a capsule gradient, checkered
    // under translucent colours, with the iOS ring thumb.
    component ColorTrack: Item {
        id: colorTrack
        property real value: 0
        property color from: "black"
        property color to: "white"
        property color thumbColor: "white"
        property bool checker: false
        signal moved(real value)
        height: 30
        // The track: semicircular ends, a little inside the thumb, so the
        // thumb's ring stays visible over the pale end.
        Canvas {
            id: trackCanvas
            readonly property real inset: 3
            x: inset; y: inset
            width: colorTrack.width - inset * 2; height: colorTrack.height - inset * 2
            readonly property string signature: String(colorTrack.from) + String(colorTrack.to) + colorTrack.checker
            onSignatureChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"), r = height / 2, cell = 6
                ctx.reset()
                ctx.save()
                ctx.beginPath()
                ctx.arc(r, r, r, Math.PI / 2, Math.PI * 1.5, false)
                ctx.arc(width - r, r, r, Math.PI * 1.5, Math.PI / 2, false)
                ctx.closePath()
                ctx.clip()
                if (colorTrack.checker)
                    for (var y = 0; y < height; y += cell)
                        for (var x = 0; x < width; x += cell) {
                            ctx.fillStyle = (Math.round((x + y) / cell)) % 2 === 0 ? "#FFFFFF" : "#C8C8C8"
                            ctx.fillRect(x, y, cell, cell)
                        }
                var gradient = ctx.createLinearGradient(0, 0, width, 0)
                gradient.addColorStop(0, colorTrack.from)
                gradient.addColorStop(1, colorTrack.to)
                ctx.fillStyle = gradient
                ctx.fillRect(0, 0, width, height)
                ctx.restore()
            }
        }
        Rectangle {
            readonly property real travel: colorTrack.width - colorTrack.height
            x: Math.max(0, Math.min(1, colorTrack.value)) * travel
            width: colorTrack.height; height: colorTrack.height; radius: height / 2
            color: "transparent"; border.width: 3; border.color: "white"
            Rectangle { anchors.fill: parent; anchors.margins: 3; radius: height / 2; color: colorTrack.thumbColor }
        }
        MouseArea {
            anchors.fill: parent; preventStealing: true
            function pick(mouse) { colorTrack.moved(Math.max(0, Math.min(1, (mouse.x - colorTrack.height / 2) / Math.max(1, colorTrack.width - colorTrack.height)))) }
            onPressed: function(mouse) { pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
        }
    }
    // A small dark value box beside a track (100%, 255), typed into.
    component ColorValueBox: TextField {
        property string suffix: ""
        width: 64; height: 30
        leftPadding: 4; rightPadding: 4; topPadding: 0; bottomPadding: 0
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold; selectByMouse: true
        inputMethodHints: Qt.ImhDigitsOnly
        background: Rectangle { radius: 8; color: "#E6000000"; border.width: parent.activeFocus ? 1 : 0; border.color: appRoot.accent }
        onAccepted: focus = false
    }
    Popup {
        id: colorPicker
        parent: appRoot.contentItem; anchors.centerIn: parent
        modal: true; focus: true; padding: 16; topPadding: 12
        Overlay.modal: SheetDim {}
        popupType: Popup.Item
        width: 344
        property var pickCallback: null
        property string title: "Colors"
        // Hidden while the eyedropper captures the screen; the callback and
        // colour stay, so the panel reopens as it was.
        property bool eyedropping: false
        function startEyedropper() {
            eyedropping = true
            close()
            // After the close transition and a rendered frame.
            prismBridge.pickScreenColor(260)
        }
        property real hue: 0
        property real saturation: 1
        property real brightness: 1
        property real alpha: 1
        readonly property color current: Qt.hsva(hue, saturation, brightness, alpha)
        readonly property color opaque: Qt.hsva(hue, saturation, brightness, 1)
        readonly property color pureHue: Qt.hsva(hue, 1, 1, 1)
        function setColor(c) {
            if (c.hsvHue >= 0) hue = c.hsvHue
            saturation = c.hsvSaturation; brightness = c.hsvValue; alpha = c.a
        }
        // Keeps the alpha when a swatch or channel sets the colour.
        function setRgb(c) { setColor(Qt.rgba(c.r, c.g, c.b, alpha)) }
        function byte(x) { var h = Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16); return h.length < 2 ? "0" + h : h }
        function rgbHex(c) { return "#" + byte(c.r) + byte(c.g) + byte(c.b) }
        // #RRGGBB when opaque (as before), Qt's #AARRGGBB otherwise.
        function hexOf(c) { return c.a >= 0.999 ? rgbHex(c) : "#" + byte(c.a) + rgbHex(c).slice(1) }
        readonly property var systemColors: ["#30D158", "#FFD60A", "#FF9F0A", "#FF453A", "#BF5AF2", "#0A84FF", "#5E5CE6", "#FF2D55", "#64D2FF"]
        readonly property var savedColors: {
            try { var list = JSON.parse(appRoot.savedPickerColorsJson); if (Array.isArray(list) && list.length) return list } catch (e) {}
            return systemColors
        }
        function saveCurrent() {
            var hex = hexOf(current).toUpperCase()
            var list = savedColors.filter(function(c) { return c.toUpperCase() !== hex })
            appRoot.savedPickerColorsJson = JSON.stringify([hex].concat(list).slice(0, 9))
        }
        // Grid: a grey row, then nine rows of twelve hues from dark to pale.
        readonly property var gridHues: [197, 218, 258, 283, 330, 4, 17, 32, 43, 52, 62, 92]
        function gridColor(row, column) {
            if (row === 0) { var v = 1 - column / 11; return Qt.rgba(v, v, v, 1) }
            var t = (row - 1) / 8
            return Qt.hsla(gridHues[column] / 360, t < 0.75 ? 1 : 1 - (t - 0.75) * 1.2, 0.13 + 0.8 * t, 1)
        }
        function apply() { if (pickCallback) pickCallback(hexOf(current)); close() }
        background: SheetBackground {}
        contentItem: Column {
            spacing: 14
            Connections {
                target: prismBridge
                function onScreenColorPicked(color) {
                    if (color) colorPicker.setRgb(Qt.color(color))
                    if (colorPicker.eyedropping) { colorPicker.eyedropping = false; colorPicker.open() }
                }
            }
            // Eyedropper · title · close.
            Item {
                width: 312; height: 34
                Item {
                    width: 34; height: 34
                    Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Pick a colour from the screen")
                    SymbolImage { anchors.centerIn: parent; width: 20; height: 20; symbol: "eyedropper"; tint: appRoot.ink }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: colorPicker.startEyedropper() }
                }
                GlassText { anchors.centerIn: parent; text: colorPicker.title; color: appRoot.ink; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, 220) }
                Item {
                    anchors.right: parent.right
                    width: 34; height: 34
                    Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Done")
                    SymbolImage { anchors.centerIn: parent; width: 16; height: 16; symbol: "xmark"; tint: appRoot.ink }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: colorPicker.apply() }
                }
            }
            // Grid / Spectrum / Sliders.
            Rectangle {
                id: pickerModes
                width: 312; height: 32; radius: 9
                color: appRoot.darkMode ? "#1FFFFFFF" : "#14000000"
                readonly property var modes: ["Grid", "Spectrum", "Sliders"]
                readonly property int index: Math.max(0, modes.indexOf(appRoot.colorPickerMode))
                Rectangle {
                    x: 2 + pickerModes.index * (pickerModes.width - 4) / 3; y: 2
                    width: (pickerModes.width - 4) / 3; height: pickerModes.height - 4; radius: 7
                    color: appRoot.darkMode ? "#59FFFFFF" : "white"
                    Behavior on x { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                Row {
                    x: 2; y: 2
                    Repeater {
                        model: pickerModes.modes
                        delegate: Item {
                            required property string modelData
                            required property int index
                            width: (pickerModes.width - 4) / 3; height: pickerModes.height - 4
                            GlassText { anchors.centerIn: parent; text: appRoot.tr(modelData); color: appRoot.ink; font.pixelSize: 13; font.weight: index === pickerModes.index ? Font.DemiBold : Font.Normal }
                            TapHandler { onTapped: appRoot.colorPickerMode = modelData }
                        }
                    }
                }
            }
            // The three ways to choose, in one fixed-height area.
            Item {
                width: 312; height: 240
                // Grid.
                Item {
                    anchors.fill: parent
                    visible: pickerModes.index === 0
                    readonly property real cellWidth: width / 12
                    readonly property real cellHeight: height / 10
                    Item {
                        anchors.fill: parent
                        layer.enabled: true; layer.smooth: true
                        layer.effect: ContinuousClip { radius: 8 }
                        Repeater {
                            model: 120
                            delegate: Rectangle {
                                required property int index
                                x: (index % 12) * parent.parent.cellWidth; y: Math.floor(index / 12) * parent.parent.cellHeight
                                width: Math.ceil(parent.parent.cellWidth); height: Math.ceil(parent.parent.cellHeight)
                                color: colorPicker.gridColor(Math.floor(index / 12), index % 12)
                            }
                        }
                    }
                    // The chosen cell, outlined in white.
                    Repeater {
                        model: 120
                        delegate: Rectangle {
                            required property int index
                            readonly property color cell: colorPicker.gridColor(Math.floor(index / 12), index % 12)
                            visible: colorPicker.rgbHex(cell) === colorPicker.rgbHex(colorPicker.opaque)
                            x: (index % 12) * parent.cellWidth - 1; y: Math.floor(index / 12) * parent.cellHeight - 1
                            width: parent.cellWidth + 2; height: parent.cellHeight + 2; radius: 3
                            color: "transparent"; border.width: 3; border.color: "white"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; preventStealing: true
                        function pick(mouse) {
                            var column = Math.max(0, Math.min(11, Math.floor(mouse.x / parent.cellWidth)))
                            var row = Math.max(0, Math.min(9, Math.floor(mouse.y / parent.cellHeight)))
                            colorPicker.setRgb(colorPicker.gridColor(row, column))
                        }
                        onPressed: function(mouse) { pick(mouse) }
                        onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
                    }
                }
                // Spectrum: saturation (x) / brightness (y) and the hue strip.
                Column {
                    anchors.fill: parent
                    visible: pickerModes.index === 1
                    spacing: 16
                    Item {
                        id: svField
                        width: 312; height: 200
                        // Three square layers under one rounded clip: each layer rounding
                        // itself left the hue showing through at the corners.
                        Item {
                            anchors.fill: parent
                            layer.enabled: true; layer.smooth: true
                            layer.effect: ContinuousClip { radius: 8 }
                            Rectangle { anchors.fill: parent; color: colorPicker.pureHue }
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "transparent" } }
                            }
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "black" } }
                            }
                        }
                        Rectangle {
                            x: colorPicker.saturation * svField.width - width / 2
                            y: (1 - colorPicker.brightness) * svField.height - height / 2
                            width: 22; height: 22; radius: 11
                            color: colorPicker.opaque; border.width: 3; border.color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent; preventStealing: true
                            function pick(mouse) {
                                colorPicker.saturation = Math.max(0, Math.min(1, mouse.x / width))
                                colorPicker.brightness = 1 - Math.max(0, Math.min(1, mouse.y / height))
                            }
                            onPressed: function(mouse) { pick(mouse) }
                            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
                        }
                    }
                    Rectangle {
                        id: hueStrip
                        width: 312; height: 24; radius: 12
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#FF0000" } GradientStop { position: 0.167; color: "#FFFF00" }
                            GradientStop { position: 0.333; color: "#00FF00" } GradientStop { position: 0.5; color: "#00FFFF" }
                            GradientStop { position: 0.667; color: "#0000FF" } GradientStop { position: 0.833; color: "#FF00FF" }
                            GradientStop { position: 1.0; color: "#FF0000" }
                        }
                        Rectangle {
                            x: colorPicker.hue * (hueStrip.width - width); anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: colorPicker.pureHue; border.width: 3; border.color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6; preventStealing: true
                            function pick(mouse) { colorPicker.hue = Math.max(0, Math.min(0.9999, (mouse.x - 6) / hueStrip.width)) }
                            onPressed: function(mouse) { pick(mouse) }
                            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
                        }
                    }
                }
                // Sliders: red, green, blue and the hex value.
                Column {
                    anchors.fill: parent
                    visible: pickerModes.index === 2
                    spacing: 8
                    Repeater {
                        model: [{ name: "Red", key: "r" }, { name: "Green", key: "g" }, { name: "Blue", key: "b" }]
                        delegate: Column {
                            id: channelRow
                            required property var modelData
                            spacing: 4
                            readonly property color c: colorPicker.opaque
                            function withChannel(v) { return Qt.rgba(channelRow.modelData.key === "r" ? v : c.r, channelRow.modelData.key === "g" ? v : c.g, channelRow.modelData.key === "b" ? v : c.b, 1) }
                            GlassText { text: appRoot.tr(channelRow.modelData.name).toUpperCase(); color: appRoot.muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Row {
                                spacing: 10
                                ColorTrack {
                                    width: 238
                                    value: channelRow.c[channelRow.modelData.key]
                                    from: channelRow.withChannel(0); to: channelRow.withChannel(1)
                                    thumbColor: colorPicker.opaque
                                    onMoved: function(v) { colorPicker.setRgb(channelRow.withChannel(v)) }
                                }
                                ColorValueBox {
                                    id: channelBox
                                    validator: IntValidator { bottom: 0; top: 255 }
                                    Binding on text { when: !channelBox.activeFocus; value: String(Math.round(channelRow.c[channelRow.modelData.key] * 255)); restoreMode: Binding.RestoreNone }
                                    onEditingFinished: { var v = parseInt(text); if (!isNaN(v)) colorPicker.setRgb(channelRow.withChannel(Math.max(0, Math.min(255, v)) / 255)) }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        topPadding: 6
                        GlassText { width: 238; height: 30; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: appRoot.tr("Hex colour #"); color: appRoot.muted; font.pixelSize: 13 }
                        ColorValueBox {
                            id: pickerHex
                            width: 64; font.pixelSize: 12; font.family: "Consolas"
                            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                            onEditingFinished: { var t = text.charAt(0) === "#" ? text : "#" + text; if (/^#[0-9a-fA-F]{6}$/.test(t)) colorPicker.setRgb(Qt.color(t)) }
                            Binding on text { when: !pickerHex.activeFocus; value: colorPicker.rgbHex(colorPicker.opaque).slice(1).toUpperCase(); restoreMode: Binding.RestoreNone }
                        }
                    }
                }
            }
            // Opacity.
            Column {
                spacing: 6
                GlassText { text: appRoot.tr("Opacity").toUpperCase(); color: appRoot.muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                Row {
                    spacing: 10
                    ColorTrack {
                        width: 238; checker: true
                        value: colorPicker.alpha
                        from: Qt.rgba(colorPicker.opaque.r, colorPicker.opaque.g, colorPicker.opaque.b, 0); to: colorPicker.opaque
                        thumbColor: colorPicker.current
                        onMoved: function(v) { colorPicker.alpha = v }
                    }
                    ColorValueBox {
                        id: opacityBox
                        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,3}%?/ }
                        Binding on text { when: !opacityBox.activeFocus; value: Math.round(colorPicker.alpha * 100) + "%"; restoreMode: Binding.RestoreNone }
                        onEditingFinished: { var v = parseInt(text); if (!isNaN(v)) colorPicker.alpha = Math.max(0, Math.min(100, v)) / 100 }
                    }
                }
            }
            Rectangle { width: 312; height: 1; color: appRoot.hairline }
            // The current colour and the saved ones; + saves the current colour.
            Row {
                spacing: 24
                Item {
                    width: 76; height: 76
                    Item {
                        anchors.fill: parent
                        layer.enabled: true; layer.smooth: true
                        layer.effect: ContinuousClip { radius: 12 }
                        Canvas {
                            anchors.fill: parent
                            visible: colorPicker.alpha < 0.999
                            onPaint: {
                                var ctx = getContext("2d"), cell = 8
                                for (var y = 0; y < height; y += cell)
                                    for (var x = 0; x < width; x += cell) {
                                        ctx.fillStyle = ((x + y) / cell) % 2 === 0 ? "#FFFFFF" : "#C8C8C8"
                                        ctx.fillRect(x, y, cell, cell)
                                    }
                            }
                        }
                        Rectangle { anchors.fill: parent; color: colorPicker.current }
                    }
                }
                Grid {
                    columns: 5; spacing: 12
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: colorPicker.savedColors
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool chosen: colorPicker.hexOf(colorPicker.current).toUpperCase() === modelData.toUpperCase()
                            width: 30; height: 30; radius: 15; color: modelData
                            Accessible.role: Accessible.Button; Accessible.name: modelData
                            // Chosen: a ring of the panel's colour inside, as on iOS.
                            Rectangle { anchors.fill: parent; anchors.margins: 3; radius: height / 2; visible: parent.chosen; color: "transparent"; border.width: 2; border.color: appRoot.darkMode ? "#2C2C2E" : "white" }
                            TapHandler { cursorShape: Qt.PointingHandCursor; onTapped: colorPicker.setColor(Qt.color(modelData)) }
                        }
                    }
                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: appRoot.darkMode ? "#4DFFFFFF" : "#26000000"
                        Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Save the current colour")
                        // Drawn, so it is exactly centred (the "+" glyph sat low).
                        Rectangle { anchors.centerIn: parent; width: 14; height: 2.5; radius: 1.25; color: "white" }
                        Rectangle { anchors.centerIn: parent; width: 2.5; height: 14; radius: 1.25; color: "white" }
                        TapHandler { cursorShape: Qt.PointingHandCursor; onTapped: colorPicker.saveCurrent() }
                    }
                }
            }
        }
    }
    // Liquid Glass button inside a sheet. Glass in a popup would sample the
    // page behind the popup; this one samples `texture`, a capture of the
    // sheet's own backdrop (`scene`), so it never shows through the sheet.
    component SheetButton: Button {
        id: sheetButton
        property bool primary: false
        property Item scene: null
        property var texture: null
        readonly property bool glassy: appRoot.liquidGlass && glassTuning.materialVisible && !!scene && !!texture
        implicitHeight: 34; implicitWidth: Math.max(80, implicitContentWidth + 28)
        leftPadding: 14; rightPadding: 14
        opacity: enabled ? 1 : 0.45
        contentItem: GlassText {
            text: sheetButton.text
            color: sheetButton.primary ? (sheetButton.glassy ? "white" : appRoot.accentButtonText) : (appRoot.customWindowChrome ? appRoot.buttonText : appRoot.ink)
            font.pixelSize: 13; font.weight: sheetButton.primary ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        background: Item {
            // Flat fallback without Liquid Glass (as ConnectionButton).
            Rectangle {
                anchors.fill: parent; radius: height / 2
                visible: !sheetButton.glassy
                color: sheetButton.primary ? appRoot.accent : appRoot.buttonFill(sheetButton.down, sheetButton.hovered)
            }
            Loader {
                anchors.fill: parent
                active: sheetButton.glassy && sheetButton.visible
                sourceComponent: TunedLiquidGlass {
                    surface: sheetButton.background
                    viewport: sheetButton.scene
                    sharpTexture: sheetButton.texture
                    blurredTexture: sheetButton.texture
                    radius: height / 2
                    tint: sheetButton.primary ? appRoot.accent : "transparent"
                }
            }
        }
    }
    component ConnectionButton: Button {
        id: connectionButton
        property bool primary:false
        // false: the flat fill only (notices and sheets over busy content).
        property bool glass:true
        implicitHeight:34;implicitWidth:Math.max(80,implicitContentWidth+28)
        leftPadding:14;rightPadding:14
        contentItem:GlassText { text:parent.text;color:appRoot.customWindowChrome && parent.primary ? appRoot.accentButtonText : appRoot.customWindowChrome ? appRoot.buttonText : appRoot.ink;font.pixelSize:13;font.weight:parent.primary?Font.DemiBold:Font.Normal;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
        background:GlassSurface {
            objectName:"accountGlassControl";radius:17
            prominent:appRoot.liquidGlass && parent.primary
            liquidGlass: connectionButton.glass // Liquid Glass (and its press response) on Windows too
            opacity: connectionButton.enabled ? 1 : 0.45
            property bool glassHovered:parent.hovered
            color: appRoot.customWindowChrome ? (connectionButton.primary ? appRoot.accent : appRoot.buttonFill(connectionButton.down, connectionButton.hovered)) : (parent.primary?Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.28):(macWindowMetrics.nativeAccountGlass?"transparent":appRoot.glassSoft))
            border.width: appRoot.customWindowChrome ? 0 : (parent.primary?1:0);border.color:appRoot.accent
        }
    }
    Timer {
        interval:80;repeat:true;running:prismConnection.visible && macWindowMetrics.nativeGlassDock
        onTriggered:macWindowMetrics.setAccountGlass(prismConnection.contentItem,true)
    }
    Popup {
        id:prismConnection
        parent:appRoot.contentItem
        // Windows: dimmed like the other sheets, for readability.
        modal:true;focus:true;dim:appRoot.customWindowChrome;padding:24
        Overlay.modal: SheetDim {}
        popupType:macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        anchors.centerIn:parent
        width:Math.min(600,appRoot.width-64)
        height:prismConnectionLayout.implicitHeight+48
        closePolicy:Popup.CloseOnEscape
        onOpened:if(macWindowMetrics.nativeGlassDock)macWindowMetrics.setAccountGlass(contentItem,true)
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        background:SheetBackground {}
        contentItem:ColumnLayout {
            id:prismConnectionLayout;spacing:18
            RowLayout {
                Layout.fillWidth:true
                Image { source:macWindowMetrics.symbolIcon("link",appRoot.accent.toString());Layout.preferredWidth:28;Layout.preferredHeight:28;fillMode:Image.PreserveAspectFit }
                GlassText { text:appRoot.tr("Launcher core");color:appRoot.ink;font.pixelSize:20;font.weight:Font.DemiBold;Layout.fillWidth:true }
            }
            GlassText { text:appRoot.tr("Built-in authentication, Java and game launch");color:appRoot.muted;font.pixelSize:13 }
            ColumnLayout {
                Layout.fillWidth:true;spacing:8
                GlassText { text:appRoot.tr("Backend");color:appRoot.ink;font.pixelSize:13;font.weight:Font.Medium }
                RowLayout { Layout.fillWidth:true;spacing:10
                    ConnectionField { id:prismExecutableField;Layout.fillWidth:true;text:prismBridge.executable;readOnly:true }
                    
                }
                Item { Layout.preferredHeight:4 }
                GlassText { text:appRoot.tr("Data folder");color:appRoot.ink;font.pixelSize:13;font.weight:Font.Medium }
                RowLayout { Layout.fillWidth:true;spacing:10
                    ConnectionField { id:prismRootField;Layout.fillWidth:true;text:prismBridge.dataRoot;readOnly:true }
                    
                }
                GlassText { text:appRoot.tr("Active data folder. Restart with --dir to use another folder.");color:appRoot.muted;font.pixelSize:11;wrapMode:Text.Wrap;Layout.fillWidth:true }
            }
            Rectangle { Layout.fillWidth:true;implicitHeight:1;color:appRoot.outline;opacity:0.35 }
            GlassText {
                Layout.fillWidth:true;color:appRoot.muted;font.pixelSize:12;wrapMode:Text.Wrap
                text:prismBridge.status.indexOf("Launch request sent")===0?appRoot.tr("Launch request sent to Prism. Open Logs for details."):prismBridge.status
            }
            RowLayout { Layout.fillWidth:true;spacing:10
                ConnectionButton { text:appRoot.tr("Accounts");onClicked:accountsPopup.open() }
                ConnectionButton { text:appRoot.tr("Core settings");onClicked:prismBridge.openCoreSettings() }
                ConnectionButton { text:appRoot.tr("Logs");onClicked:prismBridge.openLogs() }
                Item { Layout.fillWidth:true }
                ConnectionButton { text:appRoot.tr("Refresh");onClicked:{prismBridge.configure(prismExecutableField.text,prismRootField.text);appRoot.syncPrismInstances()} }
                ConnectionButton { text:appRoot.tr("Done");primary:true;onClicked:prismConnection.close() }
            }
        }
    }
    property string backgroundMode: "Gray"
    property string backgroundImage: ""
    property string backgroundPlacement: "Fill"
    readonly property color backgroundColor: backgroundMode === "White" ? "#FFFFFF" : backgroundMode === "Black" ? "#000000" : "#1E1E1E"
    property string appearanceMode: "Auto"
    property bool darkMode: appearanceMode === "Dark" ? true : appearanceMode === "Light" ? false : appearanceMode === "System" ? Qt.styleHints.colorScheme === Qt.Dark : backgroundMode === "White" ? false : backgroundMode === "Custom" ? Qt.styleHints.colorScheme === Qt.Dark : true
    property color customColorStart:"#152238"
    property color customColorEnd:"#7356a6"
    property string gradientStopsJson:'[{"color":"#152238","position":0},{"color":"#7356a6","position":1}]'
    readonly property var gradientStops:JSON.parse(gradientStopsJson)
    function updateGradientStop(index,color,position) {var stops=JSON.parse(gradientStopsJson);if(color)stops[index].color=color;if(position!==undefined)stops[index].position=Math.max(0,Math.min(1,position));gradientStopsJson=JSON.stringify(stops)}
    function snapGradientAngle(value){var snap=Math.round(value/45)*45;return Math.abs(value-snap)<=3?snap:value}
    function addGradientStop(){var stops=JSON.parse(gradientStopsJson);stops.push({color:"#ffffff",position:0.5});gradientStopsJson=JSON.stringify(stops)}
    function removeGradientStop(index){var stops=JSON.parse(gradientStopsJson);if(stops.length<=2)return;stops.splice(index,1);gradientStopsJson=JSON.stringify(stops)}
    onGradientStopsJsonChanged:syncBackground()
    property bool customGradient:false
    property real customGradientAngle:45
    function syncBackground() { macWindowMetrics.setBackground(backgroundMode, backgroundMode==="Custom color"?JSON.stringify({start:customColorStart.toString(),end:customColorEnd.toString(),gradient:customGradient,stops:gradientStops,angle:customGradientAngle}):backgroundImage, backgroundPlacement) }
    onCustomColorStartChanged:syncBackground()
    onCustomColorEndChanged:syncBackground()
    onCustomGradientChanged:syncBackground()
    onCustomGradientAngleChanged:syncBackground()
    onBackgroundModeChanged: syncBackground()
    onBackgroundImageChanged: syncBackground()
    onBackgroundPlacementChanged: syncBackground()
    FileDialog {
        id: backgroundFileDialog
        title: appRoot.tr("Choose background image")
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: {
            appRoot.backgroundImage = selectedFile.toString()
            appRoot.backgroundMode = "Custom"
        }
    }
    property string appliedThemeId: ""
    property string themeCat: ""
    property string themeMessage: ""
    property bool applyingTheme: false
    property bool themeReady: false
    readonly property string themeAppearanceJson: JSON.stringify(currentThemeAppearance())
    onThemeAppearanceJsonChanged: if (themeReady && !applyingTheme) appliedThemeId = ""
    function currentThemeAppearance() {
        var background
        if (backgroundMode === "Custom") {
            background = {kind:"image",image:backgroundImage,placement:backgroundPlacement}
        } else {
            var stops = backgroundMode === "Custom color" && customGradient ? gradientStops.slice().sort(function(a,b){return a.position-b.position})
                : [{color:backgroundMode === "Custom color" ? customColorStart.toString() : backgroundColor.toString(),position:0},
                   {color:backgroundMode === "Custom color" ? customColorStart.toString() : backgroundColor.toString(),position:1}]
            background = {kind:"gradient",stops:stops,angle:customGradientAngle}
        }
        var material = glassTuning.parameters()
        delete material.reducedMotion; delete material.reducedTransparency
        delete material.increaseContrast; delete material.reduceBrightEffects
        return {mode:appearanceMode === "Auto" ? (darkMode ? "Dark" : "Light") : appearanceMode,
            accent:chosenAccent.toString(),background:background,glass:material,cat:themeCat}
    }
    function applyTheme(document) {
        if (!document || !document.appearance) return
        applyingTheme = true
        try {
            var look = document.appearance, background = look.background
            var wallpaper = background.kind === "image" ? themeStore.wallpaperForTheme(document.id) : ""
            if (background.kind === "image" && !wallpaper.length) { themeMessage=themeStore.error; return }
            var parameters = Object.assign({}, look.glass)
            // Theme authors cannot override the recipient's accessibility choices.
            parameters.reducedMotion = glassTuning.reducedMotion
            parameters.reducedTransparency = glassTuning.reducedTransparency
            parameters.increaseContrast = glassTuning.increaseContrast
            parameters.reduceBrightEffects = glassTuning.reduceBrightEffects
            // A chosen Liquid Glass preset (Settings › Liquid Glass) stays put.
            if (!glassPresetLocked) glassTuning.apply(parameters)
            appearanceMode = look.mode
            themeCat = look.cat || ""
            customAccent = look.accent; themeChoice = "Custom"
            if (background.kind === "image") {
                backgroundImage = wallpaper; backgroundPlacement = background.placement; backgroundMode = "Custom"
            } else {
                gradientStopsJson = JSON.stringify(background.stops)
                customColorStart = background.stops[0].color
                customColorEnd = background.stops[background.stops.length-1].color
                customGradientAngle = background.angle; customGradient = true; backgroundMode = "Custom color"
            }
            appliedThemeId = document.id
            themeMessage = appRoot.tr("Theme applied: ") + document.name
        } catch (e) { themeMessage = e.message }
        finally { applyingTheme = false }
    }
    FileDialog {
        id: themeImportDialog; title: appRoot.tr("Import theme")
        nameFilters: [appRoot.tr("Vitra themes (*.vitra-theme.json *.json)")]
        onAccepted: {
            var imported = themeStore.importTheme(selectedFile)
            if (imported.id) { themeLibraryPopup.selectedId = imported.id; appRoot.themeMessage = appRoot.tr("Theme imported. Select Use theme to apply it.") }
            else appRoot.themeMessage = themeStore.error
        }
    }
    FileDialog {
        id: themeExportDialog; title: appRoot.tr("Export theme"); fileMode: FileDialog.SaveFile
        defaultSuffix: "vitra-theme.json"
        nameFilters: [appRoot.tr("Vitra themes (*.vitra-theme.json *.json)")]
        property string themeId: ""
        onAccepted: appRoot.themeMessage = themeStore.exportTheme(themeId,selectedFile) ? appRoot.tr("Theme exported. Send this file to share it.") : themeStore.error
    }
    property color ink: darkMode ? "#F7FAFF" : "#172333"
    property color muted: darkMode ? "#AAB8CC" : "#58697D"
    property color glass: darkMode ? "#A82A394D" : "#D9F6FAFF"
    property color glassStrong: darkMode ? "#CC30465E" : "#ECF8FBFF"
    property color glassSoft: darkMode ? "#84334660" : "#DCEEF7FF"
    property color outline: darkMode ? "#65E5F5FF" : "#8095B5CD"
    // AppKit's hairline around panes and controls (Windows; AppKit draws its own).
    // Glass samples the page, which lies under any popup: inside one it would
    // show the page straight through the popup. Popups are solid instead.
    readonly property color popupSurface: darkMode ? "#2B2B2B" : "#F6F6F6"
    function insidePopup(item) {
        for (; item; item = item.parent)
            if (String(item).indexOf("QQuickPopupItem") === 0) return true
        return false
    }
    // A popup whose see-through MenuPanel is its surface, not the solid one.
    function insideMenuPanel(item) {
        for (; item; item = item.parent)
            if (item.objectName === "menuPanelContent") return true
        return false
    }
    readonly property color hairline: !customWindowChrome ? "transparent" : darkMode ? "#22FFFFFF" : "#14000000"
    property string themeChoice: "System"
    property color customAccent: "#8B5CF6"
    property color systemAccent: "#0A84FF"
    readonly property var themePalette: ({Blue:"#0A84FF",Purple:"#BF5AF2",Pink:"#FF375F",Red:"#FF453A",Orange:"#FF9F0A",Yellow:"#FFD60A",Green:"#30D158"})
    readonly property color autoAccent: backgroundMode==="Custom"?macWindowMetrics.artworkTint(backgroundImage):backgroundMode==="Custom color"?(customGradient?gradientStops[Math.floor(gradientStops.length/2)].color:customColorStart):systemAccent
    readonly property color chosenAccent: themeChoice === "Auto" ? autoAccent : themeChoice === "System" ? systemAccent : themeChoice === "Custom" ? customAccent : (themePalette[themeChoice] || systemAccent)
    function readableAccent(value) {
        function luminance(r,g,b) {
            function linear(v) {return v<=0.04045?v/12.92:Math.pow((v+0.055)/1.055,2.4)}
            return 0.2126*linear(r)+0.7152*linear(g)+0.0722*linear(b)
        }
        var background=darkMode?luminance(30/255,30/255,30/255):1
        var r=value.r,g=value.g,b=value.b
        for(var i=0;i<=32;i++) {
            var l=luminance(r,g,b)
            if((Math.max(l,background)+0.05)/(Math.min(l,background)+0.05)>=3)break
            var t=(i+1)/32, target=darkMode?1:0
            r=value.r+(target-value.r)*t;g=value.g+(target-value.g)*t;b=value.b+(target-value.b)*t
        }
        return Qt.rgba(r,g,b,1)
    }
    readonly property color accent: readableAccent(chosenAccent)
    readonly property color accentButtonText: {
        function linear(v) { return v <= 0.04045 ? v/12.92 : Math.pow((v+0.055)/1.055,2.4) }
        var luminance=0.2126*linear(accent.r)+0.7152*linear(accent.g)+0.0722*linear(accent.b)
        return luminance > 0.179 ? "#101820" : "white"
    }
    // Accent for text and symbols on dark glass: deep accents (purple, navy)
    // read as dim there, so dark mode mixes in white.
    readonly property color accentLabel: darkMode ? Qt.tint(accent, "#8CFFFFFF") : accent
    // Flat Windows button fill (buttons, pop-up buttons, round glyph buttons).
    readonly property color fieldFill: darkMode ? "#14FFFFFF" : "#66FFFFFF"
    // macOS pop-up button: a flat lighter plate, stronger than a button's.
    function selectFill(down, hovered) {
        return darkMode ? (down ? "#33FFFFFF" : hovered ? "#24FFFFFF" : "#18FFFFFF")
                        : (down ? "#30000000" : hovered ? "#1C000000" : "#12000000")
    }
    function buttonFill(down, hovered) {
        return darkMode ? (down ? "#33FFFFFF" : hovered ? "#20FFFFFF" : "#12FFFFFF")
                        : (down ? "#30000000" : hovered ? "#18000000" : "#0D000000")
    }
    readonly property color buttonText: ink
    // Settings › Appearance: switches turn on in the accent colour (macOS)
    // instead of green (iOS).
    property bool accentSwitches: true
    // Settings › Canvas: strength of the instance cards' ambient glow
    // (0 turns it off and skips its blur).
    property real cardGlow: 0.85
    // Settings › Layout: default strength of a card's Liquid Glass tint, and
    // of the dark shade under card captions (1 = the original).
    property real cardGlassTintOpacity: 0.6
    property real cardCaptionShade: 1
    // Settings › Layout: an accent glow under selected cards.
    property bool selectionGlow: true
    // Settings › Layout: shadow behind text standing on the wallpaper.
    property real textShadow: 0.85
    // Settings › Layout: how far a selected card lifts (0.03 = 103%).
    property real selectionLift: 0.03
    // Settings › Layout › Card glass (LiquidGlass.cardStyle).
    property real cardGlassFrost: 0.75
    property real cardGlassDimming: 0.4
    property real cardGlassCaption: 0.3
    // Radius in px of the wider blur (the card glass's softness).
    property real cardGlassBlur: 22
    // Settings panes and the sidebar share the cards' frost, dimming and
    // blur (no caption contrast: that is for a card's name).
    readonly property vector4d panelGlassStyle: Qt.vector4d(cardGlassFrost, cardGlassDimming, 0, cardGlassBlur)
    // Settings › Appearance: macOS 27 system font (SF Pro) when installed.
    // Read by Frontend.cpp at startup; the change applies after a restart.
    property bool useSystemFont: false
    readonly property string systemFontFamily: prismBridge.systemFontFamily()
    onAccentChanged: { macWindowMetrics.setThemeAccent(accent.toString()); prismBridge.setWidgetStyle(accent.toString(), darkMode); sidebarMaterialSignature=""; if(appRoot)appRoot.queueSidebarMaterials() }
    property bool sidebarGuideSeen: false
    property int sidebarGuideStep: 0
    function showSidebarGuide() { sidebarGuideStep=0; sidebarGuideSeen=false; sidebarMode=true; launchShowsEditor=false; activePage="Launch" }

    property bool smartLayout: true
    property bool quickCards: true
    // Opt-in, full-window aligned compositor; default off preserves stable 09.21.1 visuals.
    property bool dockLiveBlur: false
    // Adjustable intensity: 0 = no blur, 1 = strongest. Saved automatically.
    property real dockBlurAmount: 0.30
    property int globalMemoryMiB: 4096
    property var systemMemory: ({})
    readonly property int memoryLimitMiB: systemMemory.totalMiB > 0 ? Math.max(0, Math.floor(systemMemory.totalMiB - systemMemory.usedMiB)) : 0
    function clampMemory(value) { return Math.max(Math.min(512, memoryLimitMiB), Math.min(memoryLimitMiB, Math.round(Number(value) || 4096))) }
    function effectiveMemoryMiB(key) {
        if(key===editingInstanceKey && coreEditing && editingMetadata.memoryMiB)return Number(editingMetadata.memoryMiB)
        var meta = cardMetadata[key] || ({})
        return clampMemory(meta.useDefaultMemory !== false ? globalMemoryMiB : (meta.memoryMiB || globalMemoryMiB))
    }
    readonly property string memoryStatus: systemMemory.totalMiB > 0 ?
        appRoot.tr("System: ") + (systemMemory.totalMiB / 1024).toFixed(1) + appRoot.tr(" GiB total · ") + (systemMemory.usedMiB / 1024).toFixed(1) + appRoot.tr(" GiB used · ") + (memoryLimitMiB / 1024).toFixed(1) + appRoot.tr(" GiB available") : appRoot.tr("System memory unavailable")
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { appRoot.systemMemory = macWindowMetrics.systemMemory(); appRoot.systemAccent=macWindowMetrics.systemAccentColor() }
    }
    property real glassOpacity: 0.72
    // Instance picker fan: blur and shadow behind it (Settings › Layout).
    property real pickerBlurAmount: 0.8
    property real pickerShadowAmount: 0.5
    // Settings: a straight column instead of the Dock's arc.
    property bool pickerVertical: false
    // Windows renders the surfaces that macOS draws with NSGlassEffectView
    // through Glass Lab's LiquidGlass.qml; parameters use the lab's JSON format.
    GlassTuning { id: glassTuning }
    readonly property bool liquidGlass: Qt.platform.os === "windows" && glassTuning.glassEnabled
    property string glassTuningStatus: ""
    // Liquid Glass presets (Settings › Liquid Glass): named parameter sets kept
    // apart from themes. While a preset or "Keep current" is chosen, applying a
    // theme leaves the Liquid Glass parameters as they are.
    property string glassPresetsJson: "[]"
    readonly property var glassPresets: { try { var v = JSON.parse(glassPresetsJson); return Array.isArray(v) ? v : [] } catch (e) { return [] } }
    // "" follows the theme, "custom" keeps the current values, anything else
    // is the name of a saved preset (its edits are saved into it).
    property string glassPresetChoice: ""
    readonly property bool glassPresetLocked: glassPresetChoice.length > 0
    property bool applyingGlassPreset: false
    readonly property var glassAccessibilityKeys: ["reducedMotion", "reducedTransparency", "increaseContrast", "reduceBrightEffects"]
    function glassPresetIndex(name) {
        for (var i = 0; i < glassPresets.length; ++i) if (glassPresets[i].name === name) return i
        return -1
    }
    function currentGlassPresetParameters() {
        var p = glassTuning.parameters()
        glassAccessibilityKeys.forEach(function(k) { delete p[k] })
        return p
    }
    function chooseGlassPreset(choice) {
        if (choice !== "" && choice !== "custom") {
            var i = glassPresetIndex(choice)
            if (i < 0) return
            var p = Object.assign({}, glassPresets[i].parameters)
            // Accessibility switches belong to this computer, not the preset.
            glassAccessibilityKeys.forEach(function(k) { p[k] = glassTuning[k] })
            applyingGlassPreset = true
            try { glassTuning.apply(p) } catch (e) { glassTuningStatus = e.message; applyingGlassPreset = false; return }
            applyingGlassPreset = false
        }
        glassPresetChoice = choice
    }
    function saveGlassPreset(name) {
        name = name.trim()
        if (!name.length) return
        var list = glassPresets.slice(), entry = {name: name, parameters: currentGlassPresetParameters()}
        var i = glassPresetIndex(name)
        if (i >= 0) list[i] = entry; else list.push(entry)
        glassPresetsJson = JSON.stringify(list)
        glassPresetChoice = name
    }
    function deleteGlassPreset(name) {
        glassPresetsJson = JSON.stringify(glassPresets.filter(function(p) { return p.name !== name }))
        if (glassPresetChoice === name) glassPresetChoice = "custom"
    }
    // Edits made while a saved preset is chosen go into that preset.
    Connections {
        target: glassTuning
        function onSerializedChanged() {
            if (appRoot.applyingGlassPreset || !glassTuning.loaded) return
            var i = appRoot.glassPresetIndex(appRoot.glassPresetChoice)
            if (i < 0) return
            var list = appRoot.glassPresets.slice()
            list[i] = {name: list[i].name, parameters: appRoot.currentGlassPresetParameters()}
            var json = JSON.stringify(list)
            if (json !== appRoot.glassPresetsJson) appRoot.glassPresetsJson = json
        }
    }
    // Settings › Liquid Glass: hides the tuning only, the values stay applied.
    property bool glassSettingsVisible: false
    readonly property bool showGlassSettings: Qt.platform.os === "windows" && glassSettingsVisible
    // The Glass Lab's sliders, in its order. Ranges come from GlassTuning.
    readonly property var glassParameterGroups: [
        { caption: "Glass material", tile: "#BF5AF2", symbol: "sparkles", parameters: [
            { key: "refraction", title: "Lens depth", step: 0.01 },
            { key: "glare", title: "Reflection strength", step: 0.01 },
            { key: "density", title: "Material density", step: 0.01 },
            { key: "strokeWidth", title: "Stroke width", step: 0.1, unit: " pt" },
            { key: "strokeOpacity", title: "Stroke darkness", step: 0.01 } ] },
        // Only with "Reflection does not follow the pointer"; 1 = the macOS look.
        { caption: "Fixed reflection", tile: "#FFD60A", symbol: "sparkles", parameters: [
            { key: "staticTopLight", title: "Top highlight", step: 0.01 },
            { key: "staticBottomLight", title: "Bottom highlight", step: 0.01 },
            { key: "staticBottomGlow", title: "Bottom glow", step: 0.01 } ] },
        { caption: "Optics and blur", tile: "#0A84FF", symbol: "circle.lefthalf.filled", parameters: [
            { key: "refractiveIndex", title: "Refractive index", step: 0.01 },
            { key: "bevelWidth", title: "Lens edge width", step: 1, unit: " pt" },
            { key: "dispersion", title: "Dispersion", step: 0.005 },
            { key: "magnification", title: "Backdrop magnification", step: 0.01 },
            { key: "blurSpread", title: "Pre-blur range", step: 0.01 } ] },
        { caption: "Lighting and color", tile: "#FF9F0A", symbol: "paintpalette", parameters: [
            { key: "saturation", title: "Backdrop saturation", step: 0.01 },
            { key: "glassLift", title: "Dark glass lift", step: 0.01 },
            { key: "fresnelAmount", title: "Fresnel edge reflection", step: 0.01 },
            { key: "specularAmount", title: "Specular highlight", step: 0.01 },
            { key: "edgeAmount", title: "Outline highlight", step: 0.01 },
            { key: "shadowAmount", title: "Shadow strength", step: 0.01 },
            { key: "lightAngle", title: "Light direction", step: 1, unit: "°" } ] },
        { caption: "Interaction", tile: "#30D158", symbol: "sparkles", parameters: [
            { key: "interactionStrength", title: "Pointer and press strength", step: 0.01 },
            { key: "interactionRadius", title: "Interaction radius", step: 1, unit: " pt" },
            { key: "responseTime", title: "Pointer follow delay", step: 5, unit: " ms" } ] }
    ]
    readonly property var glassAccessibilityFlags: [
        { key: "reducedMotion", title: "Reduce motion" },
        { key: "reducedTransparency", title: "Reduce transparency" },
        { key: "reduceBrightEffects", title: "Reduce bright effects" },
        { key: "increaseContrast", title: "Increase contrast" }
    ]
    function importGlassTuning() {
        try {
            glassTuning.applyJson(macWindowMetrics.clipboardText())
            glassTuningStatus = appRoot.tr("Applied Glass Lab parameters from the clipboard")
        } catch (e) {
            glassTuningStatus = appRoot.tr("Clipboard does not contain Glass Lab parameters: ") + e.message
        }
    }
    onGlassOpacityChanged: macWindowMetrics.setGlassStrength(glassOpacity)
    onDarkModeChanged: { macWindowMetrics.setGlassStrength(glassOpacity); prismBridge.setWidgetStyle(accent.toString(), darkMode); sidebarMaterialSignature = ""; appRoot.queueSidebarMaterials() }
    Connections { target: Qt.styleHints
        function onColorSchemeChanged() {
            Qt.callLater(function() { macWindowMetrics.setGlassStrength(appRoot.glassOpacity); appRoot.sidebarMaterialSignature=""; appRoot.queueSidebarMaterials() })
        }
    }
    readonly property color materialTint: darkMode ? Qt.rgba(0.11, 0.23, 0.31, glassOpacity) : Qt.rgba(0.94, 0.98, 1.0, glassOpacity)
    property bool autoSelect: true
    property string sortMode: "Smart"
    property string selectedId: ""
    property string searchText: ""
    property bool searchExpanded: false
    property bool sidebarMode: false
    property bool instancePickerOpen: false
    readonly property color navigationText: darkMode ? "#FAFBFF" : "#242424"
    readonly property color navigationSelectedText: darkMode ? "#FFFFFF" : "#050505"
    property var selectedCardKeys: []
    property string selectionAnchor: ""
    property string instanceRecordsJson: ""
    property string cardMetadataJson: "{}"
    readonly property var cardMetadata: { try { return JSON.parse(cardMetadataJson) } catch(e) { return ({}) } }
    property string editingInstanceKey: ""
    readonly property var editingRecord: instanceRecord(editingInstanceKey)
    readonly property bool coreEditing:editingInstanceKey.indexOf("prism:")===0
    readonly property var editingMetadata: coreEditing ? Object.assign({mods:[],resourcePacks:[],shaderPacks:[],worlds:[],screenshots:[],servers:[],components:[]},{background:(cardMetadata[editingInstanceKey] || {}).background || ""},prismBridge.editorInstanceKey===editingInstanceKey?prismBridge.editorDetails:{}) : cardMetadata[editingInstanceKey] || ({mods:[],background:""})
    property string editorLogText:""
    property var editorDirtyFields:({})
    function syncEditorFields() {
        var data=editingMetadata
        if(!editorDirtyFields.name && !editInstanceName.activeFocus)editInstanceName.text=editingRecord?editingRecord.label:""
        if(!editInstanceVersion.activeFocus)editInstanceVersion.text=editingRecord?editingRecord.version:""
        if(!editorDirtyFields.notes && !instanceNotes.activeFocus)instanceNotes.text=data.notes || ""
        if(!editorDirtyFields.javaPath && !instanceJava.activeFocus)instanceJava.text=data.javaPath || ""
        if(!editorDirtyFields.javaArgs && !instanceJavaArgs.activeFocus)instanceJavaArgs.text=data.javaArgs || ""
        if(logKeepUpdating || editorLogText.length===0)editorLogText=data.minecraftLog || ""
    }
    Connections {target:prismBridge;function onEditorDetailsChanged(){appRoot.syncEditorFields()}}
    Timer {interval:1000;repeat:true;running:appRoot.activePage==="Instance" && appRoot.coreEditing && appRoot.logKeepUpdating;onTriggered:prismBridge.refreshEditor()}
    onEditorTabChanged:if(coreEditing && activePage==="Instance")prismBridge.refreshEditor()
    onLogKeepUpdatingChanged:if(logKeepUpdating)editorLogText=editingMetadata.minecraftLog || ""
    function toggleEditorAsset(bucket,entry,enabled) {
        if(coreEditing)return prismBridge.setEditorAssetEnabled(editingInstanceKey,bucket,entry.fileName,enabled)
        var list=InstanceData.clone(editingMetadata[bucket] || []);for(var i=0;i<list.length;i++)if(list[i].source===entry.source)list[i].enabled=enabled
        saveEditorAssets(list,bucket);return true
    }
    function removeEditorAsset(bucket,entry) {
        if(coreEditing){prismBridge.removeEditorAsset(editingInstanceKey,bucket,entry.fileName);return}
        saveEditorAssets((editingMetadata[bucket] || []).filter(function(item){return item.source!==entry.source}),bucket)
    }
    function openEditorAsset(bucket,entry) {
        if(coreEditing)prismBridge.revealEditorAsset(editingInstanceKey,bucket,entry.fileName);else Qt.openUrlExternally(entry.source)
    }
    function addEditorServer(address) {
        address=address.trim();if(!address)return
        if(coreEditing){prismBridge.editServer(editingInstanceKey,address,-1);return}
        var list=InstanceData.clone(editingMetadata.servers || []);list.push({name:address,address:address});setInstanceMetadata(editingInstanceKey,{servers:list})
    }
    function removeEditorServer(entry,index) {
        if(coreEditing){prismBridge.editServer(editingInstanceKey,entry.address || entry.name,entry.index);return}
        var list=InstanceData.clone(editingMetadata.servers || []);list.splice(index,1);setInstanceMetadata(editingInstanceKey,{servers:list})
    }
    // Instances that receive the picture chosen in cardBackgroundDialog.
    property var pendingBackgroundKeys: []
    function chooseBackgroundFor(keys) { pendingBackgroundKeys=keys.slice(); cardBackgroundDialog.open() }
    // Batch background edits from the card menu (one or more selected cards).
    function setArtworkPlacementFor(keys,patch) { keys.forEach(function(k){ setArtworkPlacement(k,patch) }) }
    function artworkPlacementMatches(keys,patch) {
        return keys.length>0 && keys.every(function(k){ var p=artworkPlacement(k); return Object.keys(patch).every(function(f){ return p[f]===patch[f] }) })
    }
    function artworkPlacementIs(keys,field,value) {
        return keys.length>0 && keys.every(function(k){ return artworkPlacement(k)[field]===value })
    }
    function removeBackgrounds(keys) {
        keys.forEach(function(k) {
            prismBridge.removeInstanceBackground(k)
            setInstanceMetadata(k,{background:""})
            setArtworkPlacement(k,{fit:"fill",scale:1,x:0,y:0,color:""})
        })
    }
    function instanceRecord(key) {
        for(var i=0;i<instances.count;i++)if(instances.get(i).key===key)return instances.get(i)
        return null
    }
    function instanceRecords() { var records=[];for(var i=0;i<instances.count;i++)records.push(JSON.parse(JSON.stringify(instances.get(i))));return records }
    function persistInstances() { instanceRecordsJson=JSON.stringify(instanceRecords()) }
    function selectCanvasCard(card,modifiers,rangeCards) {
        var keys=(rangeCards || sortedCards).map(function(c){return c.key})
        if((modifiers & Qt.ShiftModifier) && keys.indexOf(selectionAnchor)>=0) {
            var a=keys.indexOf(selectionAnchor),b=keys.indexOf(card.key)
            selectedCardKeys=keys.slice(Math.min(a,b),Math.max(a,b)+1)
        } else {
            selectedCardKeys=InstanceData.select(selectedCardKeys,card.key,!!(modifiers & (Qt.ControlModifier|Qt.MetaModifier)))
            selectionAnchor=card.key
        }
        chooseCard(card,true)
    }
    function openCardMenu(card,x,y) {
        if(selectedCardKeys.indexOf(card.key)<0)selectedCardKeys=[card.key]
        cardContextMenu.contextKeys=selectedCardKeys.slice()
        accountMenuOpen=false
        cardContextMenu.popup(x,y)
    }
    function duplicateCards(keys) {
        var sourceRecords=instanceRecords(), sources=sourceRecords.filter(function(r){return keys.indexOf(r.key)>=0})
        var result=InstanceData.duplicate(sourceRecords,keys,cardMetadata)
        result.copies.forEach(function(record){instances.append(record)})
        cardMetadataJson=JSON.stringify(result.metadata)
        var groups=InstanceData.clone(instanceGroups)
        groups.forEach(function(g){result.copies.forEach(function(copy,i){
            var source=sources[i]
            if(source && g.keys.indexOf(source.key)>=0)g.keys.push(copy.key)
        })})
        instanceGroupsJson=JSON.stringify(groups)
        customInstanceOrder=customInstanceOrder.concat(result.copies.map(function(c){return c.key}))
        selectedCardKeys=result.copies.map(function(c){return c.key})
        if(selectedCardKeys.length)selectedId=selectedCardKeys[0]
        persistInstances()
    }
    function setInstanceMetadata(key,patch) {
        if(key.indexOf("prism:")===0) {
            var settings={},visual={}
            Object.keys(patch).forEach(function(name){if(["notes","javaPath","javaArgs","memoryMiB","useDefaultMemory","useDefaultOptions"].indexOf(name)>=0)settings[name]=patch[name];else visual[name]=patch[name]})
            if(Object.keys(settings).length && prismBridge.saveEditorSettings(key,settings)) {
                Object.keys(settings).forEach(function(name){delete editorDirtyFields[name]});syncEditorFields()
            }
            patch=visual;if(!Object.keys(patch).length)return
        }
        var data=InstanceData.clone(cardMetadata),record=data[key]||{mods:[],background:""}
        Object.keys(patch).forEach(function(k){record[k]=patch[k]})
        data[key]=record;cardMetadataJson=JSON.stringify(data)
    }
    // How an instance's card picture is placed (CardArtwork): fill mode,
    // scale, offset from the centre and the colour behind it.
    function artworkPlacement(key) {
        var meta=cardMetadata[key]||{}
        // Earlier builds kept the glass tint in iconFill ("glass-accent", "glass-icon").
        var fill=meta.iconFill||"", legacyTint=fill==="glass-accent"?"accent":fill==="glass-icon"?"artwork":""
        return {fit:meta.backgroundFit||"fill",scale:meta.backgroundScale===undefined?1:meta.backgroundScale,
                x:meta.backgroundX||0,y:meta.backgroundY||0,color:meta.backgroundColor||"",
                // Behind a built-in loader icon (no picture): "" automatic tint,
                // "transparent", "glass" or a colour.
                iconFill:fill.indexOf("glass")===0?"glass":fill,
                // A Liquid Glass base (icon or picture): "" clear, "accent" the
                // theme colour, "artwork" the icon's or picture's colour; and
                // its strength, -1 = Settings › Layout › Card glass tint.
                glassTint:meta.glassTint!==undefined?meta.glassTint:legacyTint,
                tintOpacity:meta.glassTintOpacity===undefined?-1:meta.glassTintOpacity}
    }
    function setArtworkPlacement(key,patch) {
        var next={}
        if(patch.fit!==undefined)next.backgroundFit=patch.fit
        if(patch.scale!==undefined)next.backgroundScale=Math.max(0.1,Math.min(4,patch.scale))
        if(patch.x!==undefined)next.backgroundX=Math.max(-1,Math.min(1,patch.x))
        if(patch.y!==undefined)next.backgroundY=Math.max(-1,Math.min(1,patch.y))
        if(patch.color!==undefined)next.backgroundColor=patch.color
        if(patch.iconFill!==undefined)next.iconFill=patch.iconFill
        if(patch.glassTint!==undefined)next.glassTint=patch.glassTint
        if(patch.tintOpacity!==undefined)next.glassTintOpacity=patch.tintOpacity<0?-1:Math.max(0.05,Math.min(1,patch.tintOpacity))
        setInstanceMetadata(key,next)
    }
    function saveInstanceDetails(name,version) {
        if(!name.trim().length)return
        if(coreEditing){if(prismBridge.saveEditorSettings(editingInstanceKey,{name:name})){delete editorDirtyFields.name;syncEditorFields()}return}
        for(var i=0;i<instances.count;i++)if(instances.get(i).key===editingInstanceKey){
            instances.setProperty(i,"label",name.trim());instances.setProperty(i,"version",version.trim());break
        }
        persistInstances()
    }
    function editInstance(key) {
        editingInstanceKey=key;editorDirtyFields=({});editorLogText="";editorTab="Overview";activePage="Instance"
        if(coreEditing)prismBridge.watchInstance(key)
        syncEditorFields()
    }
    function moveCardsToGroup(keys,id) {
        var groups=instanceGroups
        keys.forEach(function(key){groups=CanvasLayout.assignGroup(groups,key,id)})
        instanceGroupsJson=JSON.stringify(groups);groupedLayoutEnabled=true;groupingMethod="Custom"
    }
    FileDialog {
        id: defaultOptionsDialog
        title: appRoot.tr("Choose options.txt")
        nameFilters: [appRoot.tr("Minecraft options (options*.txt)"), appRoot.tr("Text files (*.txt)")]
        onAccepted: appRoot.setCore("DefaultOptionsFile", prismBridge.localFilePath(selectedFile))
    }
    FileDialog {
        id: cardBackgroundDialog
        title: appRoot.tr("Choose instance background")
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        // Installed instances keep a copy in their folder (it survives moving the
        // original and goes along when shared); other cards keep the path.
        onAccepted: {
            var keys=appRoot.pendingBackgroundKeys
            appRoot.pendingBackgroundKeys=[]
            for(var i=0;i<keys.length;i++) {
                var key=keys[i]
                var stored=key.indexOf("prism:")===0 ? prismBridge.storeInstanceBackground(key,selectedFile) : selectedFile.toString()
                if(stored.length) appRoot.setInstanceMetadata(key,{background:stored})
                else { appRoot.statusMessage=appRoot.tr("Choose a PNG, JPG, WebP or BMP picture up to 16 MB."); break }
            }
        }
        onRejected: appRoot.pendingBackgroundKeys=[]
    }
    FileDialog {
        id: instanceModsDialog
        title: appRoot.tr("Add Mod files")
        fileMode: FileDialog.OpenFiles
        nameFilters: [appRoot.tr("Mods (*.jar)")]
        onAccepted: {
            if(appRoot.coreEditing){for(var f=0;f<selectedFiles.length;f++)prismBridge.importEditorAsset(appRoot.editingInstanceKey,"mods",selectedFiles[f]);return}
            var mods=InstanceData.clone(appRoot.editingMetadata.mods||[])
            for(var i=0;i<selectedFiles.length;i++){
                var url=selectedFiles[i].toString()
                if(!mods.some(function(m){return m.source===url}))mods.push({name:decodeURIComponent(url.split("/").pop()),source:url,enabled:true})
            }
            appRoot.setInstanceMetadata(appRoot.editingInstanceKey,{mods:mods})
        }
    }
    property string collapsedInstanceGroupsJson: "[]"
    readonly property var collapsedInstanceGroups: {try{return JSON.parse(collapsedInstanceGroupsJson)}catch(e){return []}}
    function sidebarDisplayRows() { return InstanceData.sidebarRows(sortedCards,effectiveInstanceGroups,collapsedInstanceGroups,hasInstanceGroups) }
    function toggleSidebarGroup(id) {
        var ids=collapsedInstanceGroups.slice(),i=ids.indexOf(id)
        if(i<0)ids.push(id);else ids.splice(i,1)
        collapsedInstanceGroupsJson=JSON.stringify(ids)
    }
    property string editorTab: "Overview"
    // Order matches the editor's StackLayout pages.
    readonly property var editorTabs: ["Overview","Minecraft Log","Version","Background","Mods","Resource Packs","Shader Packs","Notes","Worlds","Servers","Screenshots","Settings","Other Logs"]
    property string editorAssetBucket: "mods"
    property string exportPayload: ""
    property var deletionKeys: []
    property bool logKeepUpdating: true
    property bool logWrapLines: true
    function exportSelection(keys) {
        var records=instanceRecords().filter(function(r){return keys.indexOf(r.key)>=0}), metadata={}
        keys.forEach(function(key){metadata[key]=cardMetadata[key]||{}})
        return JSON.stringify({format:"ProjectGlass-instance-config",version:1,instances:records,metadata:metadata},null,2)
    }
    function showInstanceFolder(key) { if(key.indexOf("prism:")===0)prismBridge.openInstance(key);else macWindowMetrics.openInstanceFolder(key,exportSelection([key])) }
    function requestExport(keys,modsOnly) {
        exportPayload=modsOnly ? keys.map(function(key){return (key.indexOf("prism:")===0?prismBridge.instanceDetails(key):(cardMetadata[key]||{})).mods||[]}).reduce(function(a,b){return a.concat(b)},[]).map(function(m){return (m.enabled?appRoot.tr("[enabled] "):appRoot.tr("[disabled] "))+m.name+"  "+m.source}).join("\n") : exportSelection(keys)
        exportConfigDialog.nameFilters=modsOnly ? [appRoot.tr("Mod list (*.txt)")] : ["Instance configuration (*.json)"]
        exportConfigDialog.open()
    }
    function deleteInstances(keys) {
        for(var i=instances.count-1;i>=0;i--)if(keys.indexOf(instances.get(i).key)>=0)instances.remove(i)
        var metadata=InstanceData.clone(cardMetadata);keys.forEach(function(key){delete metadata[key]})
        cardMetadataJson=JSON.stringify(metadata)
        instanceGroupsJson=JSON.stringify(instanceGroups.map(function(g){return {id:g.id,name:g.name,keys:g.keys.filter(function(key){return keys.indexOf(key)<0})}}))
        customInstanceOrder=customInstanceOrder.filter(function(key){return keys.indexOf(key)<0})
        selectedCardKeys=[];selectedId=instances.count?instances.get(0).key:"";persistInstances()
    }
    // Width shared by the editor list's header actions and row buttons.
    FontMetrics { id: editorButtonMetrics }
    readonly property real editorButtonWidth: Math.ceil(Math.max(88, 32 + Math.max(
        editorButtonMetrics.advanceWidth(tr("Open")), editorButtonMetrics.advanceWidth(tr("Remove")),
        editorButtonMetrics.advanceWidth(tr("Download")), editorButtonMetrics.advanceWidth(tr("Update")),
        editorButtonMetrics.advanceWidth(tr("Add from File…")), editorButtonMetrics.advanceWidth(tr("Open folder…")),
        editorButtonMetrics.advanceWidth(tr("Add…")))))
    // Buckets with a catalogue to download from.
    readonly property var editorDownloadCategories: ({ mods: "Mods", resourcePacks: "Resource packs", shaderPacks: "Shaders" })
    // Set while the instance editor is open under Launch (also while another
    // page is shown): Launch returns to the editor (onActivePageChanged).
    property bool launchShowsEditor: false
    property string shownPage: "Launch"
    function downloadForEditor(bucket) {
        var record=instanceRecord(editingInstanceKey)
        if(record)chooseCard(record)
        openDownloadCategory(editorDownloadCategories[bucket])
    }
    function openEditorAssets(bucket) {
        editorAssetBucket=bucket
        if(coreEditing && (bucket==="worlds" || bucket==="screenshots")){prismBridge.openEditorFolder(editingInstanceKey,bucket);return}
        if(bucket==="worlds")instanceWorldDialog.open()
        else {
            editorAssetsDialog.nameFilters=bucket==="screenshots" ? ["Images (*.png *.jpg *.jpeg *.webp)"] : bucket==="mods" ? [appRoot.tr("Mods (*.jar)")] : [appRoot.tr("Packs (*.zip)")]
            editorAssetsDialog.open()
        }
    }
    function addEditorAsset(source) {
        if(coreEditing){prismBridge.importEditorAsset(editingInstanceKey,editorAssetBucket,source);return}
        var entries=InstanceData.clone(editingMetadata[editorAssetBucket]||[])
        if(!entries.some(function(e){return e.source===source}))entries.push({name:decodeURIComponent(source.replace(/\/$/,"").split("/").pop()),source:source,enabled:true})
        var patch={};patch[editorAssetBucket]=entries;setInstanceMetadata(editingInstanceKey,patch)
    }
    function checkEditorUpdates(bucket) {
        resourceUpdatePopup.bucket=bucket
        if(prismBridge.checkingResourceUpdates || prismBridge.checkEditorUpdates(editingInstanceKey,bucket)){resourceUpdatePopup.chosen=[];resourceUpdatePopup.open()}
    }
    // Editor tabs that take dropped files, and the folder each one fills.
    readonly property var editorTabBuckets: ({ "Mods": "mods", "Resource Packs": "resourcePacks", "Shader Packs": "shaderPacks", "Worlds": "worlds", "Screenshots": "screenshots" })
    readonly property var editorDropBuckets: ({ mods: ".jar", resourcePacks: ".zip", shaderPacks: ".zip", worlds: "level.dat", screenshots: ".png  ·  .jpg  ·  .webp" })
    readonly property string editorDropBucket: activePage==="Instance" && !!editingInstanceKey ? (editorTabBuckets[editorTab] || "") : ""
    function handleEditorDrop(bucket,urls) {
        packImportDismiss.stop()
        var list=[];for(var i=0;i<urls.length;i++)list.push(urls[i].toString())
        var message=""
        if(coreEditing)message=prismBridge.importEditorAssets(editingInstanceKey,bucket,list)
        else{editorAssetBucket=bucket;list.forEach(function(source){addEditorAsset(source)});message=tr("Added %1 files").replace("%1",list.length)}
        noticeTitle=tr("Add to %1").replace("%1",tr(editorTab))
        packImportMessage=message||prismBridge.status;packImportOverride=true;packImportNotice=true
        packImportDismiss.restart()
    }
    function saveEditorAssets(entries,bucket) {if(coreEditing){prismBridge.refreshEditor();return}var patch={};patch[bucket]=entries;setInstanceMetadata(editingInstanceKey,patch)}
    FileDialog {
        id: exportConfigDialog; title: appRoot.tr("Export instance"); fileMode: FileDialog.SaveFile
        onAccepted: if(!macWindowMetrics.writeTextFile(selectedFile,appRoot.exportPayload))appRoot.statusMessage=appRoot.tr("Could not save export")
    }
    FileDialog {
        id: shortcutDialog; title: appRoot.tr("Create launch shortcut"); fileMode: FileDialog.SaveFile
        nameFilters: [appRoot.tr("macOS launch shortcut (*.command)")]
        onAccepted: if(!macWindowMetrics.writeLaunchShortcut(selectedFile,cardContextMenu.contextKeys[0]))appRoot.statusMessage=appRoot.tr("Could not save shortcut")
    }
    FileDialog {
        id: editorAssetsDialog; fileMode: FileDialog.OpenFiles
        onAccepted: {for(var i=0;i<selectedFiles.length;i++)appRoot.addEditorAsset(selectedFiles[i].toString())}
    }
    // Instance editor › Update: newer releases from Modrinth / CurseForge.
    Popup {
        id: resourceUpdatePopup
        parent: appRoot.contentItem
        popupType: macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        property string bucket: "mods"
        property var chosen: []
        readonly property var updates: prismBridge.resourceUpdates || []
        readonly property bool checking: prismBridge.checkingResourceUpdates
        function iconFor(update) {
            var list = appRoot.editingMetadata[bucket] || []
            for (var i = 0; i < list.length; i++) if (list[i].fileName === update.fileName) return list[i].icon || ""
            return ""
        }
        function toggle(index, on) {
            var next = chosen.filter(function(item) { return item !== index })
            if (on) next.push(index)
            chosen = next
        }
        function all() { return updates.map(function(update) { return update.index }) }
        Connections {
            target: prismBridge
            function onResourceUpdatesChecked(success, count, message) { resourceUpdatePopup.chosen = resourceUpdatePopup.all() }
        }
        anchors.centerIn: parent
        width: Math.min(560, appRoot.width - 48); padding: 24
        modal: true; dim: true; focus: true
        Overlay.modal: SheetDim {}
        closePolicy: Popup.CloseOnEscape
        onClosed: if (checking) prismBridge.cancelEditorUpdateCheck(); else prismBridge.dismissEditorUpdates()
        background: Rectangle {
            radius: 24
            color: appRoot.darkMode ? "#2B2B2B" : "#F6F6F6"
            border.width: 1; border.color: appRoot.hairline
        }
        contentItem: Column {
            spacing: 14
            GlassText {
                width: parent.width; wrapMode: Text.Wrap
                text: appRoot.tr("Update %1").replace("%1", appRoot.tr(appRoot.editorTab))
                color: appRoot.ink; font.pixelSize: 20; font.bold: true
            }
            Row {
                width: parent.width; spacing: 10
                BusyIndicator { visible: resourceUpdatePopup.checking; running: visible; width: 22; height: 22 }
                GlassText {
                    width: parent.width - (resourceUpdatePopup.checking ? 32 : 0); wrapMode: Text.Wrap
                    text: prismBridge.resourceUpdateStatus || (resourceUpdatePopup.checking ? appRoot.tr("Checking for updates…") : "")
                    color: appRoot.muted; font.pixelSize: 13; textFormat: Text.PlainText
                }
            }
            Row {
                visible: !resourceUpdatePopup.checking && resourceUpdatePopup.updates.length > 0
                width: parent.width; spacing: 10
                GlassText {
                    width: parent.width - 83; height: 34; verticalAlignment: Text.AlignVCenter
                    text: appRoot.tr("Select all") + "  (" + resourceUpdatePopup.chosen.length + "/" + resourceUpdatePopup.updates.length + ")"
                    color: appRoot.ink; font.pixelSize: 14
                }
                GlassSwitch {
                    checked: resourceUpdatePopup.updates.length > 0 && resourceUpdatePopup.chosen.length === resourceUpdatePopup.updates.length
                    onToggled: resourceUpdatePopup.chosen = checked ? resourceUpdatePopup.all() : []
                }
            }
            Rectangle { visible: !resourceUpdatePopup.checking && resourceUpdatePopup.updates.length > 0; width: parent.width; height: 1; color: appRoot.hairline }
            Flickable {
                visible: !resourceUpdatePopup.checking && resourceUpdatePopup.updates.length > 0
                width: parent.width; height: Math.min(updateRows.implicitHeight, Math.max(160, appRoot.height - 360))
                contentHeight: updateRows.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: updateRows
                    width: parent.width - 10; spacing: 6
                    Repeater {
                        model: resourceUpdatePopup.checking ? [] : resourceUpdatePopup.updates
                        delegate: RowLayout {
                            required property var modelData
                            width: updateRows.width; height: 48; spacing: 12
                            GlassSwitch {
                                padding: 0
                                checked: resourceUpdatePopup.chosen.indexOf(modelData.index) >= 0
                                onToggled: resourceUpdatePopup.toggle(modelData.index, checked)
                            }
                            Image { source: resourceUpdatePopup.iconFor(modelData); Layout.preferredWidth: 28; Layout.preferredHeight: 28 }
                            Column {
                                Layout.fillWidth: true; spacing: 2
                                GlassText { width: parent.width; text: modelData.name; color: appRoot.ink; font.pixelSize: 14; elide: Text.ElideRight }
                                GlassText {
                                    width: parent.width; elide: Text.ElideRight; color: appRoot.muted; font.pixelSize: 12
                                    text: (modelData.oldVersion || "?") + "  →  " + modelData.newVersion
                                          + (modelData.versionType && modelData.versionType !== "release" ? " (" + modelData.versionType + ")" : "")
                                          + "  ·  " + modelData.provider
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                width: parent.width; spacing: 10
                Item { Layout.fillWidth: true }
                ConnectionButton {
                    glass: false
                    text: resourceUpdatePopup.checking ? appRoot.tr("Cancel") : resourceUpdatePopup.updates.length ? appRoot.tr("Cancel") : appRoot.tr("Close")
                    onClicked: resourceUpdatePopup.close()
                }
                ConnectionButton {
                    glass: false
                    visible: !resourceUpdatePopup.checking && resourceUpdatePopup.updates.length > 0
                    enabled: resourceUpdatePopup.chosen.length > 0 && !prismBridge.installing
                    text: appRoot.tr("Update selected (%1)").replace("%1", resourceUpdatePopup.chosen.length)
                    onClicked: {
                        var chosen = resourceUpdatePopup.chosen.slice()
                        if (prismBridge.applyEditorUpdates(chosen)) resourceUpdatePopup.close()
                    }
                }
            }
        }
    }
    FolderDialog { id: instanceWorldDialog; title: appRoot.tr("Add world folder"); onAccepted: appRoot.addEditorAsset(selectedFolder.toString()) }
    FolderDialog { id: instanceFolderDialog; title: appRoot.tr("Choose instance folder"); onAccepted: { appRoot.storageError = prismBridge.setInstanceFolder(selectedFolder); appRoot.coreRevision++ } }
    FolderDialog { id: javaFolderDialog; title: appRoot.tr("Choose Java download folder"); onAccepted: { appRoot.storageError = prismBridge.setJavaFolder(selectedFolder); appRoot.coreRevision++ } }
    // Share / receive an instance's content list (InstanceSync.h).
    Popup {
        id: instanceSyncPopup
        parent: appRoot.contentItem
        popupType: macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        property string mode: "share"
        property string key: ""
        // Content kinds, with the labels both sides show.
        readonly property var kindTitles: ({ mods: appRoot.tr("Mods"), resourcepacks: appRoot.tr("Resource packs"), shaderpacks: appRoot.tr("Shader packs"), background: appRoot.tr("Instance background") })
        // The card picture of the shared instance, sent along when chosen.
        readonly property string shareBackground: mode === "share" ? ((appRoot.cardMetadata[key] || {}).background || "") : ""
        readonly property var shareKinds: ["mods", "resourcepacks", "shaderpacks"].concat(shareBackground.length ? ["background"] : [])
        // Share: kinds to leave out. Receive: leave the versions as they are.
        property var skippedKinds: []
        property bool keepVersions: false
        property bool allowDirect: false
        readonly property string phase: instanceSync.state
        readonly property var preview: instanceSync.preview
        readonly property bool versionsDiffer: !!preview.versions && preview.versions.length > 0
        function toggleKind(kind, on) {
            var kinds = skippedKinds.filter(function(item) { return item !== kind })
            if (!on) kinds.push(kind)
            skippedKinds = kinds
        }
        function selectedKinds(all) { return all.filter(function(kind) { return skippedKinds.indexOf(kind) < 0 }) }
        function begin(newMode, newKey) { instanceSync.cancel(); mode = newMode; key = newKey; skippedKinds = []; keepVersions = false; allowDirect = false; syncCode.text = ""; open() }
        // Receiving with no instance chosen: the share becomes a new instance.
        readonly property bool createsInstance: mode === "receive" && key === ""
        function dismiss() {
            if (phase === "creating") prismBridge.cancelInstall()
            instanceSync.cancel(); close()
        }
        anchors.centerIn: parent
        width: 420; padding: 24
        modal: true; dim: true; focus: true
        Overlay.modal: SheetDim {}
        closePolicy: Popup.CloseOnEscape
        onClosed: instanceSync.cancel()
        // Opaque: small text and controls sit over busy instance artwork.
        background: Rectangle {
            radius: 24
            color: appRoot.darkMode ? "#2B2B2B" : "#F6F6F6"
            border.width: 1; border.color: appRoot.hairline
        }
        contentItem: Column {
            spacing: 14
            GlassText {
                width: parent.width; wrapMode: Text.Wrap
                text: instanceSyncPopup.mode === "share" ? appRoot.tr("Share this instance") : appRoot.tr("Sync from a code")
                color: appRoot.ink; font.pixelSize: 20; font.bold: true
            }
            GlassText {
                visible: instanceSyncPopup.phase === "idle"
                width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 13
                text: instanceSyncPopup.mode === "share"
                      ? appRoot.tr("Sends the game version and the lists you choose below. The other computer downloads the files from Modrinth and CurseForge itself; files on neither site can be sent from here if it accepts. Both computers must be on the same network.")
                      : instanceSyncPopup.createsInstance ? appRoot.tr("Creates a new instance with the shared game version, mod loader and content, and downloads everything.")
                      : appRoot.tr("Compares this instance with the shared one and shows what will change before anything does.")
            }
            // Share: options
            Row {
                visible: instanceSyncPopup.mode === "share" && instanceSyncPopup.phase === "idle"
                spacing: 10; width: parent.width
                GlassText { width: parent.width - 170; height: 34; verticalAlignment: Text.AlignVCenter; text: appRoot.tr("Code expires after (minutes)"); color: appRoot.ink; font.pixelSize: 14 }
                GlassSelect {
                    id: syncDuration
                    width: 160
                    property string minutes: "5"
                    options: ["1", "5", "10"]
                    selected: minutes
                    onChosen: function(value) { minutes = value }
                }
            }
            Row {
                visible: instanceSyncPopup.mode === "share" && instanceSyncPopup.phase === "idle"
                spacing: 10; width: parent.width
                GlassText { width: parent.width - 83; height: 34; verticalAlignment: Text.AlignVCenter; text: appRoot.tr("Expire after one use"); color: appRoot.ink; font.pixelSize: 14 }
                GlassSwitch { id: syncSingleUse; checked: true }
            }
            Repeater {
                model: instanceSyncPopup.mode === "share" && instanceSyncPopup.phase === "idle" ? instanceSyncPopup.shareKinds : []
                delegate: Row {
                    required property string modelData
                    spacing: 10; width: instanceSyncPopup.availableWidth
                    GlassText { width: parent.width - 83; height: 34; verticalAlignment: Text.AlignVCenter; text: instanceSyncPopup.kindTitles[parent.modelData]; color: appRoot.ink; font.pixelSize: 14 }
                    GlassSwitch {
                        checked: instanceSyncPopup.skippedKinds.indexOf(parent.modelData) < 0
                        onToggled: instanceSyncPopup.toggleKind(parent.modelData, checked)
                    }
                }
            }
            // Receive: code
            GroupField {
                id: syncCode
                visible: instanceSyncPopup.mode === "receive" && (instanceSyncPopup.phase === "idle" || instanceSyncPopup.phase === "error")
                width: parent.width
                placeholderText: appRoot.tr("6-digit code")
                onAccepted: instanceSync.connectCode(instanceSyncPopup.key, text)
            }
            // Share: the code
            GlassText {
                visible: instanceSyncPopup.phase === "sharing"
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: instanceSync.pin.slice(0, 3) + " " + instanceSync.pin.slice(3)
                color: appRoot.ink; font.pixelSize: 44; font.bold: true; font.letterSpacing: 2
            }
            GlassText {
                visible: instanceSyncPopup.phase === "sharing"
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                color: appRoot.muted; font.pixelSize: 13
                text: appRoot.tr("Expires in %1:%2").replace("%1", Math.floor(instanceSync.secondsLeft / 60)).replace("%2", String(instanceSync.secondsLeft % 60).padStart(2, "0"))
                      + "\n" + appRoot.tr("%1 items shared, %2 unavailable").replace("%1", instanceSyncPopup.preview.shared || 0).replace("%2", instanceSyncPopup.preview.unavailableCount || 0)
                      + (instanceSyncPopup.preview.directCount ? "\n" + appRoot.tr("%1 not on Modrinth or CurseForge: sent from this computer if the other side accepts").replace("%1", instanceSyncPopup.preview.directCount) : "")
                      + (instanceSyncPopup.preview.background ? "\n" + appRoot.tr("The instance background is sent from this computer") : "")
                      + (instanceSync.address.length ? "\n" + instanceSync.address : "")
            }
            // Receive: review
            Column {
                visible: instanceSyncPopup.phase === "review" && instanceSyncPopup.createsInstance
                width: parent.width; spacing: 2
                GlassText { width: parent.width; wrapMode: Text.Wrap; text: appRoot.tr("New instance: %1").replace("%1", instanceSyncPopup.preview.name || ""); color: appRoot.ink; font.pixelSize: 14 }
                GlassText { visible: !!instanceSyncPopup.preview.background; width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 12; text: appRoot.tr("Includes the instance background") }
                GlassText { width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 12; text: (instanceSyncPopup.preview.versions || []).join("\n") }
            }
            Row {
                visible: instanceSyncPopup.phase === "review" && instanceSyncPopup.versionsDiffer && !instanceSyncPopup.createsInstance
                spacing: 10; width: parent.width
                Column {
                    width: parent.width - 83; spacing: 2
                    GlassText { width: parent.width; text: appRoot.tr("Sync to the shared version"); color: appRoot.ink; font.pixelSize: 14 }
                    GlassText {
                        width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 12
                        text: (instanceSyncPopup.preview.versions || []).join("\n")
                    }
                }
                GlassSwitch {
                    checked: !instanceSyncPopup.keepVersions
                    onToggled: instanceSyncPopup.keepVersions = !checked
                }
            }
            GlassText {
                visible: instanceSyncPopup.phase === "review" && !instanceSyncPopup.createsInstance && !!instanceSyncPopup.preview.background
                width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 13
                text: appRoot.tr("Includes the instance background")
            }
            GlassText {
                visible: instanceSyncPopup.phase === "review" && instanceSyncPopup.versionsDiffer && instanceSyncPopup.keepVersions
                width: parent.width; wrapMode: Text.Wrap; color: "#FF9F0A"; font.pixelSize: 13
                text: appRoot.tr("Files made for the shared version may not work on this instance's version.")
            }
            // A large pack lists hundreds of names: every one stays readable by scrolling.
            Flickable {
                visible: instanceSyncPopup.phase === "review"
                width: parent.width; height: Math.min(syncPlan.implicitHeight, Math.max(160, appRoot.height - 340))
                contentHeight: syncPlan.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: syncPlan
                    width: parent.width - 10; spacing: 14
            Repeater {
                model: instanceSyncPopup.phase === "review" ? (instanceSyncPopup.preview.kinds || []) : []
                delegate: Column {
                    required property var modelData
                    width: syncPlan.width; spacing: 2
                        GlassText { width: parent.width; text: instanceSyncPopup.kindTitles[modelData.kind]; color: appRoot.ink; font.pixelSize: 14 }
                        GlassText {
                            width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 12
                            text: {
                                var p = modelData, parts = []
                                if (p.add + p.replace > 0) parts.push(appRoot.tr("%1 to download (%2 MB)").replace("%1", p.add + p.replace).replace("%2", p.megabytes))
                                if (p.replace) parts.push(appRoot.tr("%1 replaced with another version").replace("%1", p.replace))
                                if (p.remove) parts.push(appRoot.tr("%1 extra mods moved to a backup folder").replace("%1", p.remove))
                                parts.push(appRoot.tr("%1 already match").replace("%1", p.unchanged))
                                return parts.join(" · ")
                            }
                        }
                        GlassText {
                            visible: modelData.unavailable.length > 0
                            width: parent.width; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: "#FF9F0A"; font.pixelSize: 12
                            text: visible ? appRoot.tr("Not available for download, add these yourself: %1").replace("%1", modelData.unavailable.join(", ")) : ""
                        }
                }
            }
                    GlassText {
                        visible: text.length > 0
                        width: parent.width; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: appRoot.muted; font.pixelSize: 12
                        text: (instanceSyncPopup.preview.direct || []).join(", ")
                    }
                }
            }
            // Files neither site has: code from the other computer, so off until chosen.
            Row {
                visible: instanceSyncPopup.phase === "review" && (instanceSyncPopup.preview.direct || []).length > 0
                spacing: 10; width: parent.width
                Column {
                    width: parent.width - 83; spacing: 2
                    GlassText { width: parent.width; wrapMode: Text.Wrap; text: appRoot.tr("Receive %1 files directly from that computer").replace("%1", (instanceSyncPopup.preview.direct || []).length); color: appRoot.ink; font.pixelSize: 14 }
                    GlassText {
                        width: parent.width; wrapMode: Text.Wrap; color: "#FF9F0A"; font.pixelSize: 12
                        text: instanceSyncPopup.allowDirect
                              ? appRoot.tr("These files are not on Modrinth or CurseForge, and mods run as programs on this computer. Accept them only from a computer you trust.")
                              : appRoot.tr("Without these files the instance may not start.")
                    }
                }
                GlassSwitch {
                    checked: instanceSyncPopup.allowDirect
                    onToggled: instanceSyncPopup.allowDirect = checked
                }
            }
            // Progress
            Rectangle {
                visible: instanceSyncPopup.phase === "downloading" || instanceSyncPopup.phase === "creating"
                width: parent.width; height: 6; radius: 3
                color: appRoot.darkMode ? "#26FFFFFF" : "#1A000000"
                Rectangle {
                    width: parent.width * (instanceSyncPopup.phase === "creating" ? prismBridge.installProgress : instanceSync.total > 0 ? instanceSync.completed / instanceSync.total : 0)
                    height: parent.height; radius: 3; color: appRoot.accent
                    Behavior on width { NumberAnimation { duration: appRoot.motionMs } }
                }
            }
            GlassText {
                visible: instanceSync.message.length > 0 || instanceSyncPopup.phase === "downloading"
                width: parent.width; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 13
                text: instanceSyncPopup.phase === "downloading"
                      ? appRoot.tr("Downloading %1 of %2").replace("%1", instanceSync.completed).replace("%2", instanceSync.total)
                      : instanceSync.message
            }
            Flickable {
                visible: instanceSync.failures.length > 0 && instanceSyncPopup.phase === "done"
                width: parent.width; height: Math.min(syncFailures.implicitHeight, Math.max(160, appRoot.height - 340))
                contentHeight: syncFailures.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                GlassText {
                    id: syncFailures
                    width: parent.width - 10; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: "#FF9F0A"; font.pixelSize: 13
                    text: appRoot.tr("Failed: %1").replace("%1", instanceSync.failures.join(", "))
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 10
                GroupButton {
                    text: instanceSyncPopup.phase === "done" || instanceSyncPopup.phase === "expired" ? appRoot.tr("Done")
                          : instanceSyncPopup.phase === "sharing" ? appRoot.tr("Stop sharing") : appRoot.tr("Cancel")
                    onClicked: instanceSyncPopup.dismiss()
                }
                GroupButton {
                    visible: instanceSyncPopup.mode === "share" && instanceSyncPopup.phase === "idle"
                    text: appRoot.tr("Create code")
                    onClicked: instanceSync.startShare(instanceSyncPopup.key, Number(syncDuration.minutes), syncSingleUse.checked, instanceSyncPopup.selectedKinds(instanceSyncPopup.shareKinds), instanceSyncPopup.shareBackground, JSON.stringify(appRoot.artworkPlacement(instanceSyncPopup.key)))
                }
                GroupButton {
                    visible: instanceSyncPopup.mode === "receive" && (instanceSyncPopup.phase === "idle" || instanceSyncPopup.phase === "error")
                    text: appRoot.tr("Connect")
                    onClicked: instanceSync.connectCode(instanceSyncPopup.key, syncCode.text)
                }
                GroupButton {
                    visible: instanceSyncPopup.phase === "review"
                    text: instanceSyncPopup.createsInstance ? appRoot.tr("Create and sync") : appRoot.tr("Sync")
                    onClicked: instanceSync.apply(!instanceSyncPopup.keepVersions, instanceSyncPopup.allowDirect)
                }
            }
        }
    }
    Dialog {
        id: deleteInstanceDialog
        parent: appRoot.contentItem
        popupType: macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        title: appRoot.tr("Delete instance configuration?")
        width: 380
        modal: true; dim: false
        Overlay.modal: SheetDim {}
        standardButtons: Dialog.Ok | Dialog.Cancel
        anchors.centerIn: parent
        onAccepted: appRoot.deleteInstances(appRoot.deletionKeys)
        contentItem: GlassText { text: appRoot.tr("The launcher configuration will be removed. Referenced files are kept."); color: appRoot.ink; wrapMode: Text.WordWrap }
        background: SheetBackground { emphasized: true }
    }
    function launchInstanceKey(key) { var record=instanceRecord(key);if(record){launchShowsEditor=false;activePage="Launch";activateCard(record)} }

    // ---- Settings › Launch / Java / Updates ----
    // Core (Prism) settings. coreRevision makes bindings re-read after a write.
    property int coreRevision: 0
    function core(key) { coreRevision; return prismBridge.coreSetting(key) }
    function setCore(key, value) { prismBridge.setCoreSetting(key, value); coreRevision++ }
    function storagePath(key) { coreRevision; return prismBridge.storageFolder(key) }
    property string storageError: ""
    // Instances without an override launch with the core's value. Not clamped:
    // the clamp follows the RAM free right now, this is the saved default.
    function syncCoreMemory() {
        var memory = Math.round(Number(globalMemoryMiB) || 4096)
        if (Number(prismBridge.coreSetting("MaxMemAlloc")) !== memory) setCore("MaxMemAlloc", memory)
        if (Number(prismBridge.coreSetting("MinMemAlloc")) > memory) setCore("MinMemAlloc", memory)
    }
    onGlobalMemoryMiBChanged: syncCoreMemory()
    // After the game starts: "Stay open", "Minimize", or "Minimize until it exits".
    property string afterLaunch: "Stay open"
    property string restoreAfterKey: ""
    // Game process priority (Windows): Below normal, Normal, Above normal, High.
    property int processPriority: 1
    onProcessPriorityChanged: prismBridge.setProcessPriority(processPriority)
    // Badge count on Settings: 1 while a newer release waits (Settings › Updates).
    readonly property int updatesPending: prismBridge.availableUpdate ? 1 : 0
    // Settings › Memory (Windows): the quick memory optimization before each launch.
    property bool optimizeMemoryBeforeLaunch: false
    onOptimizeMemoryBeforeLaunchChanged: prismBridge.setOptimizeBeforeLaunch(optimizeMemoryBeforeLaunch)
    function startGame(key) {
        if (!prismBridge.launch(key)) return
        if (afterLaunch !== "Stay open") { showMinimized(); restoreAfterKey = afterLaunch === "Minimize until it exits" ? key : "" }
    }
    Timer {
        // Restores the window once the game started above has exited.
        interval: 2000; repeat: true
        running: appRoot.restoreAfterKey !== ""
        property bool seenRunning: false
        onRunningChanged: seenRunning = false
        onTriggered: {
            if (prismBridge.isRunning(appRoot.restoreAfterKey)) { seenRunning = true; return }
            if (seenRunning) { appRoot.restoreAfterKey = ""; appRoot.showNormal(); appRoot.raise(); appRoot.requestActivate() }
        }
    }
    // Detected Java runtimes from the core.
    property var javaList: []
    property bool javaScanning: false
    Connections {
        target: prismBridge
        function onChanged() {
            appRoot.javaScanning = prismBridge.javaScanning()
            if (!appRoot.javaScanning) appRoot.javaList = prismBridge.javaInstalls()
        }
    }
    // Garbage-collector presets: rewrite the GC flags inside the JVM arguments.
    readonly property var gcPresets: ({
        "Default": "",
        "G1GC (tuned)": "-XX:+UseG1GC -XX:+UnlockExperimentalVMOptions -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M",
        "ZGC": "-XX:+UseZGC",
        "Shenandoah": "-XX:+UseShenandoahGC"
    })
    function gcPresetOf(args) {
        args = args || ""
        if (args.indexOf("-XX:+UseZGC") >= 0) return "ZGC"
        if (args.indexOf("-XX:+UseShenandoahGC") >= 0) return "Shenandoah"
        if (args.indexOf("-XX:G1NewSizePercent") >= 0) return "G1GC (tuned)"
        return "Default"
    }
    function applyGcPreset(name) {
        var args = String(core("JvmArgs") || "")
            .replace(/\s*-XX:[+-]Use\w+GC\b/g, "").replace(/\s*-XX:G1\w+=\S+/g, "")
            .replace(/\s*-XX:MaxGCPauseMillis=\S+/g, "").replace(/\s*-XX:[+-]UnlockExperimentalVMOptions\b/g, "").trim()
        var flags = gcPresets[name] || ""
        setCore("JvmArgs", (args + " " + flags).trim())
    }
    // Window size: Default (854 × 480), Maximized, or Custom.
    readonly property string windowSizeMode: core("LaunchMaximized") ? "Maximized"
        : (Number(core("MinecraftWinWidth")) === 854 && Number(core("MinecraftWinHeight")) === 480) ? "Default" : "Custom"
    property bool customWindowSize: false
    function setWindowSizeMode(mode) {
        customWindowSize = mode === "Custom"
        setCore("LaunchMaximized", mode === "Maximized")
        if (mode === "Default") { setCore("MinecraftWinWidth", 854); setCore("MinecraftWinHeight", 480) }
    }
    property bool accountMenuOpen: false
    property string accountDisplayName: "Player"
    property string accountProvider: "Not signed in"
    property bool sidebarInstancesExpanded: false
    property bool sidebarQuickDownloadExpanded: false
    readonly property var quickVersionOptions: {
        var versions = downloadData.quickVersions.slice()
        if (sidebarQuickVersion && versions.indexOf(sidebarQuickVersion) < 0) versions.unshift(sidebarQuickVersion)
        return versions
    }
    property string sidebarQuickVersion: "1.21.8"
    property string sidebarQuickLoader: "Fabric"
    function toggleAccountMenu() {
        accountMenuOpen = !accountMenuOpen
        if (accountMenuOpen) {
            instancePickerOpen = false
            if (sidebarMode) {
                sidebarInstancesExpanded = false
                sidebarQuickDownloadExpanded = false
            }
        }
    }
    property string activePage: "Launch"
    property string downloadCategory: "Versions"
    property string downloadSearch: ""
    property string downloadSort: "Featured"
    property string downloadProvider: "Modrinth"
    property string downloadLoaderFilter: "All loaders"
    readonly property var downloadCategories: ["Versions", "Mods", "Shaders", "Resource packs", "Modpacks"]
    readonly property var downloadResults: downloadData.catalogue
    ListModel { id: downloadRows; objectName: "downloadRows"; dynamicRoles: true }
    property var downloadRowKeys: []
    Connections {
        target: downloadData
        function onCatalogueChanged() {
            var rows = downloadData.catalogue
            function key(row) { return row.projectId || row.version || row.name }
            var append = rows.length >= downloadRows.count
            for (var i = 0; append && i < downloadRows.count; i++)
                if (appRoot.downloadRowKeys[i] !== key(rows[i])) append = false
            if (!append) { downloadRows.clear(); appRoot.downloadRowKeys = [] }
            var keys = appRoot.downloadRowKeys.slice()
            for (var j = downloadRows.count; j < rows.length; j++) {
                downloadRows.append({ entry: rows[j] })
                keys.push(key(rows[j]))
            }
            appRoot.downloadRowKeys = keys
        }
    }
    DownloadData {
        id: downloadData; objectName: "downloadData"
        curseForgeKey: typeof prismBridge.curseForgeKey === "function" ? prismBridge.curseForgeKey() : ""
    }
    readonly property var downloadProviders: downloadData.curseForgeKey ? ["Modrinth", "CurseForge"] : ["Modrinth"]
    property bool downloadReady: false
    Component.onCompleted: {
        // Prism's QWidget dialogs (core settings, prompts) follow the launcher style.
        prismBridge.setWidgetStyle(accent.toString(), darkMode)
        prismBridge.setProcessPriority(processPriority)
        prismBridge.setOptimizeBeforeLaunch(optimizeMemoryBeforeLaunch)
        if(instanceRecordsJson.length) {
            try { var records=JSON.parse(instanceRecordsJson);if(Array.isArray(records)){instances.clear();records.forEach(function(r){instances.append(r)})} } catch(e) {}
        }
        if(activePage==="Instance")activePage="Launch"
        syncPrismInstances()
        if (downloadProviders.indexOf(downloadProvider) < 0) downloadProvider = "Modrinth"
        downloadReady = true
        Qt.callLater(function() {
            var savedTheme=themeStore.theme(appRoot.appliedThemeId)
            if (savedTheme.id) appRoot.applyTheme(savedTheme)
            appRoot.themeReady = true
        })
        if (groupingMethod === "Off") groupedLayoutEnabled=false
        else if (!groupedLayoutEnabled) { lastActiveGroupingMethod=groupingMethod; groupingMethod="Off" }
        if (canvasLayoutRevision < 2) { sortMode = "Smart"; resetCanvas(); canvasLayoutRevision = 2 }
        macWindowMetrics.setDockInfo(selectedLabel(), selectedVersion())
        macWindowMetrics.setDockGeometry(bottomDock.x, bottomDock.y, bottomDock.width,
                                         bottomDock.height, bottomDock.radius)
        if (activePage === "Download") catalogueRefresh.restart()
    }
    Timer {
        id: catalogueRefresh
        interval: 350
        onTriggered: {
            if (appRoot.downloadReady && appRoot.activePage === "Download" && !appRoot.downloadSelection)
                downloadData.loadCatalogue(appRoot.downloadCategory, appRoot.downloadSearch, appRoot.downloadSort, false, appRoot.downloadLoaderFilter, appRoot.downloadProvider)
        }
    }
    function refreshCatalogue() {
        if (!downloadReady) return
        downloadData.invalidateCatalogue()
        catalogueRefresh.restart()
    }
    function submitDownloadSearch(query) {
        if (!downloadReady || activePage !== "Download" || downloadSelection) return
        downloadSearch = String(query).trim()
        catalogueRefresh.stop()
        downloadData.invalidateCatalogue()
        downloadData.loadCatalogue(downloadCategory, downloadSearch, downloadSort, false,
                                   downloadLoaderFilter, downloadProvider)
    }
    onDownloadSearchChanged: refreshCatalogue()
    onDownloadCategoryChanged: refreshCatalogue()
    onDownloadSortChanged: refreshCatalogue()
    onDownloadProviderChanged: { if (downloadProviders.indexOf(downloadProvider) < 0) downloadProvider = "Modrinth"; else refreshCatalogue() }
    onDownloadLoaderFilterChanged: refreshCatalogue()
    onActivePageChanged: {
        // The instance editor belongs to Launch: left for Download or Settings,
        // Launch returns to it. Back (or Launch while it shows) leaves it.
        var from=shownPage
        if(activePage==="Launch" && launchShowsEditor && from!=="Instance" && from!=="Launch" && instanceRecord(editingInstanceKey)) {
            activePage="Instance"
            if(coreEditing)prismBridge.watchInstance(editingInstanceKey)
            return
        }
        if(activePage==="Instance")launchShowsEditor=true
        else if(activePage==="Launch")launchShowsEditor=false
        shownPage=activePage
        if(activePage!=="Launch")cardSizeEditing=false
        if(activePage!=="Instance" && editingInstanceKey.indexOf("prism:")===0)prismBridge.watchInstance("")
        if (!downloadReady) return
        if (activePage === "Download") {
            if (downloadSelection) releaseRefresh.restart()
            else refreshCatalogue()
        } else {
            catalogueRefresh.stop()
            releaseRefresh.stop()
            downloadData.invalidateCatalogue()
            downloadData.closeReleases()
            selectedRelease = ""
        }
    }
    function openDownloadCategory(category) {
        downloadCategory = category
        activePage = "Download"
        downloadSelection = null
        accountMenuOpen = false
        instancePickerOpen = false
    }
    property var downloadSelection: null
    property bool projectIntroduction: false
    property string projectBody: ""
    // The description as text and picture blocks (DownloadLogic.descriptionSegments).
    property var projectSegments: []
    // Translate (project page): the language shown ("" = original), the
    // translated blocks and summary, and the request in flight.
    property string projectTranslation: ""
    property var projectTranslatedSegments: []
    property string projectTranslatedDetail: ""
    property bool projectTranslating: false
    property string projectTranslateError: ""
    property int projectTranslateRun: 0
    readonly property var translationLanguages: [
        {code: "zh-CN", name: "简体中文"}, {code: "zh-TW", name: "繁體中文"}, {code: "en", name: "English"},
        {code: "ja", name: "日本語"}, {code: "ko", name: "한국어"}, {code: "ru", name: "Русский"},
        {code: "es", name: "Español"}, {code: "fr", name: "Français"}, {code: "de", name: "Deutsch"},
        {code: "pt", name: "Português"}]
    function resetProjectTranslation() {
        projectTranslateRun++
        projectTranslation = ""; projectTranslatedSegments = []; projectTranslatedDetail = ""
        projectTranslating = false; projectTranslateError = ""
    }
    // Translation of downloaded text (Settings › Downloads): the service,
    // whether descriptions follow the launcher language, and that language.
    TranslationService { id: translationService }
    property bool autoTranslateDescriptions: true
    readonly property string contentLanguage: (prismBridge.languageRevision, translationService.targetFor(prismBridge.currentLanguage()))
    readonly property bool autoTranslating: autoTranslateDescriptions && translationService.ready
    // A catalogue summary in the launcher language once translated.
    function shownSummary(text) {
        if (!autoTranslating || !text) return text || ""
        return translationService.cached(text, contentLanguage) || text
    }
    function prefetchSummaries(rows) {
        if (!autoTranslating || !rows) return
        translationService.prefetch(rows.map(function(r) { return r.detail || "" }), contentLanguage)
    }
    Connections {
        target: downloadData
        function onCatalogueChanged() { appRoot.prefetchSummaries(downloadData.catalogue) }
        function onDependenciesChanged() { appRoot.prefetchSummaries(downloadData.dependencies) }
    }
    onContentLanguageChanged: { prefetchSummaries(downloadData.catalogue); prefetchSummaries(downloadData.dependencies) }
    onAutoTranslatingChanged: { prefetchSummaries(downloadData.catalogue); prefetchSummaries(downloadData.dependencies) }
    // Translates the summary and every text block, a few paragraphs per
    // request; pictures stay in place. `automatic`: opened in the launcher
    // language, and left as it is when it already is in that language.
    function translateProject(language, automatic) {
        resetProjectTranslation()
        var run = projectTranslateRun, html = projectBodyHtml
        var detail = downloadSelection ? (downloadSelection.detail || "") : ""
        var blocks = projectSegments.length ? projectSegments : (projectBody ? [{kind: "text", text: projectBody, url: ""}] : [])
        var jobs = [], texts = []
        var sources = blocks.map(function(block, i) {
            if (block.kind !== "text") return null
            var source = DownloadLogic.translationSource(block.text, html)
            DownloadLogic.translationChunks(source.text, 1800).forEach(function(chunk, j) { jobs.push({block: i, part: j}); texts.push(chunk) })
            return source
        })
        if (detail) { jobs.push({block: -1, part: 0}); texts.push(detail) }
        if (!jobs.length) return
        if (automatic && !texts.some(function(t) { return translationService.worthSending(t, language) })) return
        projectTranslating = true
        translationService.translate(texts, language, function(error, translated) {
            if (run !== projectTranslateRun) return
            projectTranslating = false
            if (error) { projectTranslateError = automatic ? "" : error; return }
            // Already in this language: nothing to show for an automatic pass.
            if (automatic && translated.every(function(t, i) { return t === texts[i] })) return
            var results = {}
            jobs.forEach(function(job, i) { results[job.block + ":" + job.part] = translated[i] })
            projectTranslatedSegments = blocks.map(function(block, i) {
                if (block.kind !== "text") return block
                var parts = [], k = 0
                while (results[i + ":" + k] !== undefined) { parts.push(results[i + ":" + k]); k++ }
                return {kind: "text", text: DownloadLogic.restoreTranslation(parts.join(""), sources[i].links), url: "", markdown: true}
            })
            projectTranslatedDetail = results["-1:0"] || ""
            projectTranslation = language
        })
    }
    property string projectBodyError: ""
    property bool projectBodyBusy: false
    property bool projectBodyHtml: false
    // Projects left for one of their dependencies; Back returns to them.
    property var downloadHistory: []
    function openDependency(entry) {
        downloadHistory = downloadHistory.concat([downloadSelection])
        var history = downloadHistory
        beginDownload(entry)
        downloadHistory = history
    }
    // Back retraces the way in: a catalogue row's Download skips the introduction.
    property bool projectIntroductionSeen: false
    function downloadBack() {
        if (downloadHistory.length) {
            var previous = downloadHistory[downloadHistory.length - 1], rest = downloadHistory.slice(0, -1)
            beginDownload(previous)
            downloadHistory = rest
        } else if (!projectIntroduction && projectIntroductionSeen) projectIntroduction = true
        else downloadSelection = null
    }
    property var collapsedReleaseGroups: ({})
    function toggleReleaseGroup(group) {
        var next=Object.assign({},collapsedReleaseGroups)
        next[group]=!next[group]; collapsedReleaseGroups=next
    }
    function releaseRows() {
        var result=[], previous=""
        for(var i=0;i<releaseChoices.length;i++) {
            var release=releaseChoices[i]
            if(release.group!==previous) { result.push({heading:true,group:release.group,issue:release.issue||""});previous=release.group }
            if(!collapsedReleaseGroups[release.group]) result.push(release)
        }
        // Grouped list geometry: which rows open and close their group block.
        for(var j=0;j<result.length;j++) {
            if(result[j].heading) continue
            result[j]=Object.assign({},result[j],{groupFirst:j===0||!!result[j-1].heading,groupLast:j===result.length-1||!!result[j+1].heading})
        }
        return result
    }
    function openProject(entry) {
        beginDownload(entry)
        if(entry.category === "Versions") return
        projectIntroduction=true; projectIntroductionSeen=true; projectBody=""; projectSegments=[]; projectBodyError=""; projectBodyHtml=false
        resetProjectTranslation()
        introductionFlick.contentY = -introductionFlick.topMargin
        if(!entry.projectId) { projectBody=entry.detail || "";return }
        projectBodyBusy=true
        var identity=downloadSelection
        var curse=entry.provider==="CurseForge"
        projectBodyHtml=curse
        var url=curse ? downloadData.curseForgeBase+"/mods/"+encodeURIComponent(entry.projectId)+"/description"
                      : downloadData.modrinthBase+"/project/"+encodeURIComponent(entry.projectId)
        downloadData.request("introduction",url,function(error,data) {
            if(appRoot.downloadSelection!==identity)return
            appRoot.projectBodyBusy=false
            appRoot.projectBodyError=error || ""
            appRoot.projectSegments=!data ? [] : DownloadLogic.descriptionSegments(curse ? data.data : (data.body || data.description), curse)
            appRoot.projectBody=appRoot.projectSegments.length ? "" : (entry.detail || "")
            if(!error && appRoot.autoTranslating) appRoot.translateProject(appRoot.contentLanguage, true)
        })
    }
    property string selectedLoader: sidebarQuickLoader
    readonly property string targetMinecraftVersion: {
        var source = selectedVersion()
        var match = source.match(/\d+(?:\.\d+)+/)
        return match ? match[0] : ""
    }
    readonly property string targetLoader: {
        var source = selectedVersion()
        return source.indexOf("Fabric") === 0 ? "Fabric" : source.indexOf("NeoForge") === 0 ? "NeoForge" : source.indexOf("Forge") === 0 ? "Forge" : source.indexOf("Quilt") === 0 ? "Quilt" : "Vanilla"
    }
    property string selectedRelease: ""
    onSelectedIdChanged: {
        // The instance editor follows the selection, keeping its current tab.
        if (activePage === "Instance" && selectedId !== editingInstanceKey) {
            var record = instanceRecord(selectedId)
            if (record && record.installed) {
                var tab = editorTab
                editInstance(selectedId)
                editorTab = tab
            }
        }
        macWindowMetrics.setDockInfo(selectedLabel(), selectedVersion())
        selectedRelease = ""
        if (downloadReady && downloadSelection && downloadSelection.category !== "Versions") {
            downloadData.closeReleases()
            releaseRefresh.restart()
        }
    }
    Connections {
        target: macWindowMetrics
        function onDeletionConfirmed() { appRoot.deleteInstances(appRoot.deletionKeys) }
        function onSearchCloseRequested() { appRoot.searchExpanded = false }
        function onSearchStateRequested(text, sort, scale) {
            appRoot.searchText = text
            appRoot.groupingMethod = sort
            appRoot.zoom = scale
        }
        function onNativeGlassDockChanged() {
            appRoot.syncNativeNavigation()
            appRoot.syncBackground()
            macWindowMetrics.setGlassStrength(appRoot.glassOpacity)
            macWindowMetrics.setThemeAccent(appRoot.accent.toString())
        }
        function onNativeSidebarChanged() { appRoot.syncNativeNavigation(); appRoot.syncBackground() }
        function onNavigationRequested(action) {
            appRoot.instancePickerOpen = false
            if (action === 5) appRoot.sidebarMode = false
            else if (action === 0) appRoot.sidebarMode = true
            else if (action === 4) appRoot.toggleSearch()
            else if (action === 6) appRoot.toggleAccountMenu()
            else appRoot.activePage = ["Launch", "Download", "Settings"][action - 1]
        }
        function onInstanceSelected(index) {
            if (index >= 0 && index < instances.count) appRoot.chooseCard(instances.get(index))
            appRoot.instancePickerOpen = false
        }
        function onInstancePickerRequested() { appRoot.instancePickerOpen = !appRoot.instancePickerOpen }
        function onLaunchRequested() { appRoot.launchInstanceKey(appRoot.selectedId) }
    }
    function beginDownload(entry) {
        projectIntroduction=false; projectIntroductionSeen=false; projectBodyBusy=false; collapsedReleaseGroups=({})
        downloadData.cancel("introduction")
        downloadSelection = JSON.parse(JSON.stringify(entry))
        selectedLoader = sidebarQuickLoader
        selectedRelease = ""
        activePage = "Download"
    }
    readonly property var releaseChoices: downloadData.releases
    readonly property var selectedReleaseDetails: {
        for (var i = 0; i < releaseChoices.length; i++) if (releaseChoices[i].id === selectedRelease) return releaseChoices[i]
        return null
    }
    onDownloadSelectionChanged: {
        installRequested = false
        if (!downloadSelection) { downloadData.cancel("introduction"); projectBodyBusy=false; projectIntroduction=false; downloadHistory=[] }
        if (!downloadReady) return
        selectedRelease = ""
        downloadData.closeReleases()
        releaseRefresh.stop()
        if (downloadSelection) {
            catalogueRefresh.stop()
            downloadData.cancel("catalogue")
            downloadData.catalogueBusy = false
            releaseRefresh.restart()
        } else if (activePage === "Download") refreshCatalogue()
    }
    onSelectedLoaderChanged: {
        if (!downloadReady || !downloadSelection || downloadSelection.category !== "Versions") return
        selectedRelease = ""
        downloadData.closeReleases()
        releaseRefresh.restart()
    }
    Timer {
        id: releaseRefresh
        interval: 1
        onTriggered: {
            if (appRoot.activePage === "Download" && appRoot.downloadSelection)
                downloadData.loadReleases(appRoot.downloadSelection, appRoot.selectedLoader, appRoot.targetMinecraftVersion, appRoot.targetLoader)
        }
    }
    readonly property color warningColor: darkMode ? "#FF9F0A" : "#C93400"
    // Compatible versions sort first, so an incompatible first row means none is.
    readonly property bool releasesAllIncompatible: !projectIntroduction && !downloadData.releaseBusy && releaseChoices.length > 0 && !!releaseChoices[0].issue
    function canInstallRelease(release) {
        return !!downloadSelection && !!release && !release.heading && !!release.eligible && !prismBridge.installing &&
            !downloadData.releaseBusy && !downloadData.releaseError &&
            (downloadSelection.category === "Versions" || downloadSelection.category === "Modpacks" || selectedId.indexOf("prism:")===0)
    }
    function downloadRelease(release) {
        if(!canInstallRelease(release))return
        selectedRelease=release.id
        installSelectedRelease()
    }
    // Set once an install is requested on the release page, so the bridge's
    // answer (including a rejection such as "Select a stopped, installed
    // instance first.") is shown there; cleared when the page changes.
    property bool installRequested: false
    readonly property bool releaseNotice: !projectIntroduction && (downloadData.releaseBusy || downloadData.releaseError.length > 0 || (releaseChoices.length === 0 && !downloadData.vanillaValid))
    // The bridge's status is translated: match the translated install outcomes.
    readonly property bool releaseOutcomeVisible: !projectIntroduction && !prismBridge.installing && (installRequested
        || prismBridge.status === tr("Installation complete") || prismBridge.status === tr("Installation cancelled")
        || prismBridge.status.indexOf(tr("Installation failed · ")) === 0)
    function installSelectedRelease() {
        if (!downloadSelection || prismBridge.installing) return
        installRequested = true
        if (downloadSelection.category === "Versions") {
            prismBridge.installGame(downloadSelection.version, selectedLoader,
                                   selectedReleaseDetails ? selectedReleaseDetails.loaderVersion : "")
        } else if (selectedReleaseDetails && selectedReleaseDetails.eligible) {
            if (downloadSelection.provider === "CurseForge")
                prismBridge.installCurseForge(selectedId, downloadSelection.category, downloadSelection.projectId,
                                              downloadSelection.name, selectedReleaseDetails.raw, downloadSelection.slug || "", downloadSelection.icon || "")
            else
                prismBridge.installModrinth(selectedId, downloadSelection.category, downloadSelection.projectId,
                                            downloadSelection.name, selectedReleaseDetails.raw, downloadSelection.slug || "", downloadSelection.icon || "")
        }
    }

    // One animation drives sidebar, navigation and the content-region geometry.
    property real sidebarProgress: macWindowMetrics.nativeSidebar
        ? macWindowMetrics.sidebarAnimationProgress : (sidebarMode ? 1.0 : 0.0)
    Behavior on sidebarProgress {
        enabled: !macWindowMetrics.nativeSidebar
        NumberAnimation { duration: 390; easing.type: Easing.InOutCubic }
    }
    property real sidebarPreferredWidth: 282
    readonly property real sidebarMaximumWidth: Math.max(240, Math.min(420, width - 520))
    readonly property real contentLeft: sidebarProgress * sidebar.width
    property bool groupedLayoutEnabled: true
    property string groupingMethod: "Smart"
    property string lastActiveGroupingMethod: "Smart"
    onGroupedLayoutEnabledChanged: {
        if (!downloadReady) return
        if (!groupedLayoutEnabled && groupingMethod !== "Off") {
            lastActiveGroupingMethod=groupingMethod; groupingMethod="Off"
        } else if (groupedLayoutEnabled && groupingMethod === "Off") groupingMethod=lastActiveGroupingMethod
        resetCanvas()
    }
    onGroupingMethodChanged: {
        if (!downloadReady) return
        if (groupingMethod === "Off") groupedLayoutEnabled=false
        else { lastActiveGroupingMethod=groupingMethod; groupedLayoutEnabled=true }
        resetCanvas()
    }
    readonly property var effectiveInstanceGroups: groupingMethod === "Custom" ? instanceGroups : CanvasLayout.automaticGroups(sortedCards,groupingMethod)
    property string instanceGroupsJson: "[]"
    readonly property var instanceGroups: {
        try { var groups=JSON.parse(instanceGroupsJson); return Array.isArray(groups) ? groups : [] }
        catch(e) { return [] }
    }
    readonly property bool hasInstanceGroups: groupedLayoutEnabled && groupingMethod !== "Off"
    function moveInstanceGroup(from, to) {
        var groups=instanceGroups.slice()
        groups.splice(to,0,groups.splice(from,1)[0])
        instanceGroupsJson=JSON.stringify(groups)
    }
    function createInstanceGroup(name, key) {
        name = name.trim()
        if (!name.length) return
        var groups=instanceGroups.slice(), id="group-"+Date.now(), suffix=0
        while(groups.some(function(g){return g.id===id})) id="group-"+Date.now()+"-"+(++suffix)
        groups.push({id:id,name:name,keys:[]})
        var keys=Array.isArray(key)?key:(key?[key]:[])
        keys.forEach(function(k){groups=CanvasLayout.assignGroup(groups,k,id)})
        instanceGroupsJson=JSON.stringify(groups)
        groupedLayoutEnabled=true; groupingMethod="Custom"
        resetCanvas()
    }
    function renameInstanceGroup(id,name) {
        name=name.trim(); if(!name.length)return
        var current=instanceGroups.filter(function(g){return g.id===id})
        if(!current.length || current[0].name===name)return
        instanceGroupsJson=JSON.stringify(instanceGroups.map(function(g){return {id:g.id,name:g.id===id?name:g.name,keys:g.keys.slice()}}))
    }
    function deleteInstanceGroup(id) {
        instanceGroupsJson=JSON.stringify(instanceGroups.filter(function(g){return g.id!==id}))
        resetCanvas()
    }
    function assignInstanceGroup(key,id) {
        groupedLayoutEnabled=true; groupingMethod="Custom"
        instanceGroupsJson=JSON.stringify(CanvasLayout.assignGroup(instanceGroups,key,id))
    }
    property var customInstanceOrder: []
    property string draggedInstanceKey: ""
    property int instanceDropSlot: -1
    property real instanceDragSceneY: 0
    property int canvasLayoutRevision: 0
    property real panX: 0
    property real panY: 0
    property real zoom: 1
    // Shared geometry tokens for consistent cross-platform corners.
    readonly property real panelRadius: 30
    readonly property real cardRadius: 26
    readonly property real pillRadius: 24
    readonly property real innerRadius: 16
    readonly property real settingsCardRadius: 22
    // Download toolbar: one 40 pt control height, matching the category capsules.
    readonly property real downloadControlHeight: 40
    readonly property real downloadControlRadius: 20
    readonly property real macOSWindowCornerRadius: macWindowMetrics.windowCornerRadius
    readonly property int motionMs: 280
    onSidebarModeChanged: {
        if (macWindowMetrics.nativeSidebar) macWindowMetrics.animateSidebar(sidebarMode)
        accountMenuOpen = false
        instancePickerOpen = false
        // Keep the canvas offsets and zoom untouched.
    }
    property string statusMessage: "Built-in launcher core"
    // Windows chrome: backgroundBackdrop paints inside the rounded clip; a window
    // colour would fill the square corners outside it.
    color: macWindowMetrics.nativeSidebar || customWindowChrome ? "transparent" : appRoot.backgroundColor
    // Persistent user preferences and window geometry (Qt application settings).
    Settings {
        category: "ProjectGlassPrototype091"
        property alias gradientStopsJson:appRoot.gradientStopsJson
        property alias customColorStart:appRoot.customColorStart
        property alias customColorEnd:appRoot.customColorEnd
        property alias customGradient:appRoot.customGradient
        property alias customGradientAngle:appRoot.customGradientAngle
        property alias backgroundMode: appRoot.backgroundMode
        property alias backgroundImage: appRoot.backgroundImage
        property alias backgroundPlacement: appRoot.backgroundPlacement
        property alias sidebarMode: appRoot.sidebarMode
        property alias sidebarWidth: appRoot.sidebarPreferredWidth
        property alias smartLayout: appRoot.smartLayout
        property alias quickCards: appRoot.quickCards
        property alias macWindowControls: appRoot.macWindowControls
        property alias greyInactiveWindowButtons: appRoot.greyInactiveWindowButtons
        property alias greyInactiveWindow: appRoot.greyInactiveWindow
        property alias accentSwitches: appRoot.accentSwitches
        property alias cardGlow: appRoot.cardGlow
        property alias cardGlassTintOpacity: appRoot.cardGlassTintOpacity
        property alias cardCaptionShade: appRoot.cardCaptionShade
        property alias selectionGlow: appRoot.selectionGlow
        property alias textShadow: appRoot.textShadow
        property alias selectionLift: appRoot.selectionLift
        property alias cardGlassFrost: appRoot.cardGlassFrost
        property alias cardGlassDimming: appRoot.cardGlassDimming
        property alias cardGlassCaption: appRoot.cardGlassCaption
        property alias cardGlassBlur: appRoot.cardGlassBlur
        property alias useSystemFont: appRoot.useSystemFont
        property alias afterLaunch: appRoot.afterLaunch
        property alias processPriority: appRoot.processPriority
        property alias optimizeMemoryBeforeLaunch: appRoot.optimizeMemoryBeforeLaunch
        property alias dockLiveBlur: appRoot.dockLiveBlur
        property alias dockBlurAmount: appRoot.dockBlurAmount
        property alias themeChoice: appRoot.themeChoice
        property alias appearanceMode: appRoot.appearanceMode
        property alias appliedThemeId: appRoot.appliedThemeId
        property alias glassPresetsJson: appRoot.glassPresetsJson
        property alias autoTranslateDescriptions: appRoot.autoTranslateDescriptions
        property alias glassPresetChoice: appRoot.glassPresetChoice
        property alias themeCat: appRoot.themeCat
        property alias customAccent: appRoot.customAccent
        property alias savedPickerColorsJson: appRoot.savedPickerColorsJson
        property alias pickerMode: appRoot.colorPickerMode
        property alias sidebarGuideSeen: appRoot.sidebarGuideSeen
        property alias globalMemoryMiB: appRoot.globalMemoryMiB
        Component.onCompleted: appRoot.syncCoreMemory()
        property alias glassOpacity: appRoot.glassOpacity
        property alias glassSettingsVisible: appRoot.glassSettingsVisible
        property alias pickerBlurAmount: appRoot.pickerBlurAmount
        property alias pickerShadowAmount: appRoot.pickerShadowAmount
        property alias pickerVertical: appRoot.pickerVertical
        property alias autoSelect: appRoot.autoSelect
        property alias sortMode: appRoot.sortMode
        property alias selectedId: appRoot.selectedId
        property alias accountDisplayName: appRoot.accountDisplayName
        property alias sidebarInstancesExpanded: appRoot.sidebarInstancesExpanded
        property alias sidebarQuickVersion: appRoot.sidebarQuickVersion
        property alias sidebarQuickLoader: appRoot.sidebarQuickLoader
        property alias downloadCategory: appRoot.downloadCategory
        property alias downloadProvider: appRoot.downloadProvider
        property alias activePage: appRoot.activePage
        property alias searchText: appRoot.searchText
        property alias searchExpanded: appRoot.searchExpanded
        property alias groupedLayoutEnabled: appRoot.groupedLayoutEnabled
        property alias lastActiveGroupingMethod: appRoot.lastActiveGroupingMethod
        property alias groupingMethod: appRoot.groupingMethod
        property alias collapsedInstanceGroupsJson: appRoot.collapsedInstanceGroupsJson
        property alias instanceRecordsJson: appRoot.instanceRecordsJson
        property alias cardMetadataJson: appRoot.cardMetadataJson
        property alias instanceGroupsJson: appRoot.instanceGroupsJson
        property alias customInstanceOrder: appRoot.customInstanceOrder
        property alias canvasLayoutRevision: appRoot.canvasLayoutRevision
        property alias freeAvoidOverlap:appRoot.freeAvoidOverlap
        property alias freeMinimumGap:appRoot.freeMinimumGap
        property alias freeCanvasEnabled:appRoot.freeCanvasEnabled
        property alias groupCardSizesJson:appRoot.groupCardSizesJson
        property alias customCardSizesJson:appRoot.customCardSizesJson
        property alias freeRectsJson:appRoot.freeRectsJson
        property alias freeHiddenJson:appRoot.freeHiddenJson
        property alias panX: appRoot.panX
        property alias panY: appRoot.panY
        property alias zoom: appRoot.zoom
        property alias windowWidth: appRoot.width
        property alias windowHeight: appRoot.height
        property alias windowX: appRoot.x
        property alias windowY: appRoot.y
    }


    // Window-space navigation: top 14pt + height 56pt + equal bottom gap 14pt.
    readonly property real navigationTopInset: 14
    // Compact navigation hidden while a project page is scrolled down
    // (releasePage.trackScroll); 0..1 with an Apple-style ease.
    property bool navigationCollapsed: false
    property real navigationCollapse: navigationCollapsed && activePage === "Download" && !sidebarMode ? 1 : 0
    Behavior on navigationCollapse { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
    readonly property real navigationBarHeight: 56
    readonly property real compactPageTop: navigationTopInset * 2 + navigationBarHeight
    readonly property real sidebarPageTop: sidebarScroll && sidebar ? sidebar.y + sidebarScroll.y : 28
    readonly property real sidebarPageWindowTop: sidebarPageTop + contentItem.y
    function pageTop() {
        return (compactPageTop - contentItem.y) * (1 - sidebarProgress) + sidebarPageTop * sidebarProgress
    }
    function panelHeight(top) {
        // Full-window dock: bottom inset 20, then its height, then a 16pt clear gap.
        return Math.max(0,height-contentItem.y-20-bottomDock.height-16-top)
    }
    readonly property real compactContentRise: 12 * (1 - sidebarProgress)
    property bool sidebarDownloadExpanded: true
    property var sidebarDownloadAnchor: null
    readonly property bool sidebarDownloadTools: macWindowMetrics.nativeGlassDock && sidebarProgress > 0.5 && sidebarDownloadAnchor !== null
    // Windows (Apple Music style): with the sidebar open, download categories
    // are sub-items under Download and the toolbar collapses to one row.
    readonly property bool sidebarDownloadCategories: customWindowChrome && sidebarProgress > 0.5
    function syncNativePageUI() {
        if (!downloadReady || !macWindowMetrics.nativeGlassDock) return
        var page = activePage === "Instance" ? (editorTab === "Minecraft Log" ? logControlsNativeArea : instanceMemoryNativeArea) : (activePage === "Settings" ? pageContent : downloadPage)
        var point = page.mapToItem(null, 0, 0)
        macWindowMetrics.setPageUI({editorTab: editorTab, logKeepUpdating: logKeepUpdating, logWrapLines: logWrapLines,
            gradientStops:gradientStops,customGradient:customGradient,customColorStart:customColorStart.toString(),customGradientAngle:customGradientAngle,themeChoice: themeChoice, customAccent: customAccent.toString(), accent: accent.toString(),
            edgeX: contentLeft, settingsTop: pageContent.mapToItem(null,0,0).y, page: activePage, sidebarDownloads: sidebarDownloadTools, categoriesExpanded: sidebarDownloadExpanded,
            categoryX: sidebarDownloadAnchor ? sidebarDownloadAnchor.mapToItem(null,0,0).x : 0,
            categoryY: sidebarDownloadAnchor ? sidebarDownloadAnchor.mapToItem(null,0,0).y : 0,
            categoryWidth: sidebarDownloadAnchor ? sidebarDownloadAnchor.width : 0,
            categoryHeight: sidebarDownloadAnchor ? sidebarDownloadAnchor.height : 0,
            sidebarClipTop: sidebarScroll.mapToItem(null,0,0).y - (sidebarDownloadAnchor ? sidebarDownloadAnchor.mapToItem(null,0,0).y : 0),
            sidebarClipBottom: sidebarAccountFooter.mapToItem(null,0,0).y - 14 - (sidebarDownloadAnchor ? sidebarDownloadAnchor.mapToItem(null,0,0).y : 0), x: point.x, y: point.y,
            width: page.width, height: page.height,
            visible: (activePage === "Instance" && editorTab === "Settings") || activePage === "Settings" || (activePage === "Download" && !downloadSelection),
            dark: darkMode,
            interactive: !prismConnection.visible && !accountMenuOpen && !instancePickerOpen && !searchExpanded,
            smart: smartLayout, grouped: groupedLayoutEnabled, groupingMethod: groupingMethod, quick: quickCards, background: backgroundMode,
            instanceDefault: editingMetadata.useDefaultMemory !== false,
            memoryTotal: systemMemory.totalMiB || 0, memoryUsed: systemMemory.usedMiB || 0,
            memory: activePage === "Instance" ? effectiveMemoryMiB(editingInstanceKey) : clampMemory(globalMemoryMiB), memoryLimit: memoryLimitMiB, memoryStatus: memoryStatus,
            image: backgroundImage, placement: backgroundPlacement, glass: glassOpacity,
            provider: downloadProvider, providers: downloadProviders, query: downloadSearch, category: downloadCategory,
            sort: downloadSort, loader: downloadLoaderFilter, busy: downloadData.catalogueBusy})
    }
    Connections {
        target: macWindowMetrics
        function onPageControlChanged(key, value) {
            if(key === "prismConnection")prismConnection.open()
            else if(key === "logKeepUpdating") appRoot.logKeepUpdating=value
            else if(key === "logWrapLines") appRoot.logWrapLines=value
            else if (key === "themeChoice") appRoot.themeChoice=value
            else if(key === "customAccent") { appRoot.customAccent=value; appRoot.themeChoice="Custom" }
            else if(key === "sidebarGuide") appRoot.showSidebarGuide()
            else if (key === "grouped") appRoot.groupedLayoutEnabled = value
            else if (key === "groupingMethod") appRoot.groupingMethod = value
            else if (key === "smart") appRoot.smartLayout = value
            else if (key === "quick") appRoot.quickCards = value
            else if (key === "background") appRoot.backgroundMode=value
            else if (key === "placement") appRoot.backgroundPlacement = value
            else if (key === "instanceDefault") appRoot.setInstanceMetadata(appRoot.editingInstanceKey, {useDefaultMemory: value})
            else if (key === "instanceMemory") appRoot.setInstanceMetadata(appRoot.editingInstanceKey, {memoryMiB: appRoot.clampMemory(value)})
            else if (key === "memory") appRoot.globalMemoryMiB = appRoot.clampMemory(value)
            else if (key === "glass") appRoot.glassOpacity = value
            else if (key === "chooseImage") {if(appRoot.backgroundMode!=="Custom color")backgroundFileDialog.open()}
            else if(key==="gradientStops")appRoot.gradientStopsJson=JSON.stringify(value)
            else if(key==="customGradient")appRoot.customGradient=value
            else if(key==="customColorStart")appRoot.customColorStart=value
            else if(key==="customGradientAngle")appRoot.customGradientAngle=appRoot.snapGradientAngle(value)
            else if (key === "provider") appRoot.downloadProvider = value
            else if (key === "query") appRoot.downloadSearch = value
            else if (key === "searchSubmit") appRoot.submitDownloadSearch(value)
            else if (key === "accountClose") appRoot.accountMenuOpen = false
            else if (key === "accountName") appRoot.accountDisplayName = value
            else if (key === "accountSettings") { appRoot.accountMenuOpen = false; appRoot.activePage = "Settings" }
            else if (key === "accountMicrosoft") {
                appRoot.accountMenuOpen = false
                prismBridge.useMicrosoft()
            }
            else if (key === "category") appRoot.openDownloadCategory(value)
            else if (key === "sort") appRoot.downloadSort = value
            else if (key === "loader") appRoot.downloadLoaderFilter = value
            else if (key === "refresh") appRoot.refreshCatalogue()
        }
    }

    function queueSidebarMaterials() {
        if (downloadReady && sidebarMaterialSync) sidebarMaterialSync.restart()
    }
    function syncNativeSearchButton() {
        if (!downloadReady || !searchDock || !searchToggle) return
        var target = appRoot.searchExpanded ? searchToggle : searchDock
        var point = target.mapToItem(null, 0, 0)
        macWindowMetrics.setSearchButton(point.x, point.y, target.height, searchDock.opacity,
            searchDock.visible && searchDock.enabled && !appRoot.searchExpanded && !appRoot.accountMenuOpen && !appRoot.instancePickerOpen,
            appRoot.searchExpanded)
        var panelPoint = searchDock.mapToItem(null, 0, 0)
        macWindowMetrics.setSearchPanel(panelPoint.x, panelPoint.y, searchDock.width, searchDock.height,
            searchDock.opacity, searchDock.visible && appRoot.searchExpanded && !appRoot.accountMenuOpen && !appRoot.instancePickerOpen,
            appRoot.searchText, appRoot.groupingMethod, appRoot.zoom)
    }
    component MemoryAllocation: ColumnLayout {
        id: memoryControl
        property int allocation: 4096
        signal committed(int value)
        spacing: 10
        // macOS storage bar: a capsule. clip only cuts a rectangle, and the
        // continuous-corner clip did not match the bar's own circular end, so
        // every segment is masked by one capsule shape instead.
        Rectangle {
            id: memoryBar
            Layout.fillWidth: true; Layout.preferredHeight: 16; radius: 8
            color: appRoot.darkMode ? "#33FFFFFF" : "#1F000000"
            layer.enabled: true; layer.smooth: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: memoryBarMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            Rectangle { id: memoryBarMask; anchors.fill: parent; radius: parent.radius; visible: false; layer.enabled: true }
            readonly property real total: Math.max(1, appRoot.systemMemory.totalMiB || 1)
            Rectangle { height: parent.height; width: parent.width * Math.min(1,(appRoot.systemMemory.usedMiB || 0)/parent.total); color: "#8E8E93" }
            Rectangle { height: parent.height; x: parent.width * Math.min(1,(appRoot.systemMemory.usedMiB || 0)/parent.total)
                width: parent.width * Math.min(appRoot.memoryLimitMiB,memoryControl.allocation)/parent.total; color: appRoot.accent }
        }
        RowLayout {
            GlassSlider { Layout.fillWidth: true; enabled: appRoot.memoryLimitMiB >= 512
                from: Math.min(512, appRoot.memoryLimitMiB); to: Math.max(from,appRoot.memoryLimitMiB); stepSize: 128
                value: Math.min(memoryControl.allocation,appRoot.memoryLimitMiB); onMoved: memoryControl.committed(appRoot.clampMemory(value)) }
            // The limit follows live free memory, so a plain text binding was
            // re-evaluated mid-typing and reset the field. It follows the
            // slider only while not focused; the value is clamped on commit
            // (not by the validator, whose moving bound rejected keystrokes).
            GroupField { id: memoryField; Layout.preferredWidth: 100; enabled: appRoot.memoryLimitMiB >= 512
                selectByMouse: true
                validator: IntValidator { bottom: 0; top: 1048576 }
                onAccepted: focus=false
                Keys.onEscapePressed: focus=false
                onEditingFinished: if (text.length) memoryControl.committed(appRoot.clampMemory(text))
                Binding on text { when: !memoryField.activeFocus; value: String(appRoot.clampMemory(memoryControl.allocation)); restoreMode: Binding.RestoreNone } }
        }
        // Legend with colour dots, as under the macOS storage bar.
        Row {
            spacing: 14
            Repeater {
                model: [{label: appRoot.tr("Used"), color: "#8E8E93"}, {label: appRoot.tr("Allocation"), color: appRoot.accent}, {label: appRoot.tr("Remaining"), color: appRoot.darkMode ? "#33FFFFFF" : "#1F000000"}]
                delegate: Row {
                    required property var modelData
                    spacing: 6
                    Rectangle { width: 8; height: 8; radius: 4; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                    GlassText { text: modelData.label; color: appRoot.muted; font.pixelSize: 11 }
                }
            }
        }
    }

    component RoundedInstanceImage: Item {
        id: roundedInstanceImage
        property url source
        property real cornerRadius: 6
        property bool defaultArtwork: false
        // The instance's placement of a custom picture (artworkPlacement).
        property var placement: ({})
        layer.enabled: true
        layer.smooth: true
        layer.effect: ContinuousClip { radius: roundedInstanceImage.cornerRadius }
        Rectangle { anchors.fill: parent; visible: roundedInstanceImage.defaultArtwork; color: roundedInstanceImage.defaultArtwork ? (macWindowMetrics.artworkTint(roundedInstanceImage.source) || "#80466E41") : "transparent" }
        Image {
            anchors.fill: parent
            anchors.margins: Math.min(parent.width,parent.height)*0.175
            visible: roundedInstanceImage.defaultArtwork
            source: roundedInstanceImage.defaultArtwork ? roundedInstanceImage.source : ""
            smooth: true; mipmap: true
            fillMode: Image.PreserveAspectFit
        }
        // Same aspect as a card, centred: a square thumbnail shows the middle
        // of the card's composition, as the card itself would at that size.
        Item {
            anchors.fill: parent
            visible: !roundedInstanceImage.defaultArtwork
            clip: true
            CardArtwork {
                readonly property real cardAspect: 240 / 168
                width: Math.max(parent.width, parent.height * cardAspect); height: width / cardAspect
                anchors.centerIn: parent
                source: roundedInstanceImage.defaultArtwork ? "" : roundedInstanceImage.source
                placement: roundedInstanceImage.placement
            }
        }
    }
    component SidebarControl: GlassSurface {
        objectName: "sidebarGlassControl"
        property color fallbackColor: "transparent"
        property bool nativeSelected: false
        property string nativeRole: "row"
        // Matches the AppKit sidebar: rows gain glass only while selected.
        liquidGlass: nativeSelected || ["panel", "account", "avatar", "field"].indexOf(nativeRole) >= 0
        selectedGlass: appRoot.liquidGlass && nativeSelected
        // Neutral capsule with a rim; the accent stays in the label and icon.
        selectedTint: appRoot.darkMode ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.1)
        surfaceLift: nativeSelected ? 0.17 : 0
        rimColor: nativeSelected ? appRoot.hairline : "transparent"
        color: macWindowMetrics.nativeSidebar ? "transparent" : fallbackColor
        // No outline by default: over selected glass it drew a dark box.
        border.width: 0
        onXChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onYChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onChildrenRectChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onWidthChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onHeightChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onVisibleChanged: if (appRoot) appRoot.queueSidebarMaterials()
        onNativeSelectedChanged: if (appRoot) appRoot.queueSidebarMaterials()
        Component.onCompleted: if (appRoot) appRoot.queueSidebarMaterials()
    }
    Timer {
        id: sidebarMaterialSync
        interval: 0
        onTriggered: appRoot.syncSidebarMaterials()
    }
    property string sidebarMaterialSignature: ""
    function syncSidebarMaterials() {
        var rows = []
        if (sidebarProgress > 0.001 && macWindowMetrics.nativeSidebar) {
            var clipTop = sidebarScroll.mapToItem(null, 0, 0).y
            var clipBottom = sidebarAccountFooter.mapToItem(null, 0, 0).y - 14
            function visit(item, clipped) {
                if (!item || !item.visible) return
                if (item.objectName === "sidebarGlassControl") {
                    var point = item.mapToItem(null, 0, 0)
                    var top = clipped ? Math.max(point.y, clipTop) : point.y
                    var bottom = clipped ? Math.min(point.y + item.height, clipBottom) : point.y + item.height
                    if (bottom > top && item.width > 0)
                        rows.push({x: point.x, y: top, width: item.width, height: bottom - top,
                                   radius: item.radius, active: !!item.nativeSelected, role: item.nativeRole || "row",
                                   opacity: Math.min(1, sidebarProgress * 1.7)})
                }
                for (var i = 0; i < item.children.length; ++i) visit(item.children[i], clipped)
            }
            visit(sidebar, true)
            visit(sidebarAccountFooter, false)
        }
        var signature = JSON.stringify(rows)
        if (signature === sidebarMaterialSignature) return
        sidebarMaterialSignature = signature
        macWindowMetrics.setSidebarControls(rows)
    }
    Connections {
        target: appRoot
        function onAfterAnimating() {
            macWindowMetrics.setEditorGlass(appRoot.activePage === "Launch" ? appRoot.contentItem : appRoot.activePage === "Download" ? (appRoot.downloadSelection ? releasePage : downloadPage) : instanceEditorPage,
                appRoot.activePage === "Instance" || appRoot.activePage === "Download" || appRoot.activePage === "Launch")
            appRoot.syncNativePageUI()
            appRoot.syncCanvasCards()
            if(canvasQuickDownload.visible)macWindowMetrics.setAccountGlass(canvasQuickDownload.contentItem,true)
            if(accountSettingsPopup.visible)macWindowMetrics.setAccountGlass(accountSettingsPopup.contentItem,true)

            appRoot.syncSidebarMaterials()
            appRoot.syncNativeSearchButton()
            macWindowMetrics.setAccountButton(appRoot.width - 62, 18,
                Math.max(0, 1 - appRoot.sidebarProgress * 4),
                appRoot.sidebarProgress < 0.999, !appRoot.accountMenuOpen)
            if (sidebarCloseButton) {
                var point = sidebarCloseButton.mapToItem(null, 0, 0)
                macWindowMetrics.setSidebarButton(point.x, point.y, appRoot.sidebarProgress, topBar.parent.height)
            }
        }
        function onSelectedIdChanged() { appRoot.queueSidebarMaterials() }
        function onSidebarInstancesExpandedChanged() { appRoot.queueSidebarMaterials() }
        function onSidebarQuickDownloadExpandedChanged() {
            appRoot.queueSidebarMaterials()
            if (appRoot.sidebarQuickDownloadExpanded) downloadData.loadQuickVersions(false)
        }
    }
    Connections {
        target: macWindowMetrics
        function onNativeSidebarChanged() {
            if (macWindowMetrics.nativeSidebar)
                macWindowMetrics.animateSidebar(appRoot.sidebarMode, true)
        }
    }
    // Glass-styled ComboBox keeps Qt's native selection, keyboard and popup
    // handling while placing the popup in the unclipped application overlay.
    // iPadOS / macOS Settings layout: inset grouped sections of rows, each row
    // with a coloured symbol tile, a title, trailing controls and a separator
    // that starts at the title.
    function settingsContentFollows(item) {
        var siblings = item.parent ? item.parent.children : []
        var found = false
        for (var i = 0; i < siblings.length; ++i) {
            if (siblings[i] === item) found = true
            else if (found && siblings[i].visible && siblings[i].height > 0) return true
        }
        // Repeater delegates wrap each setting in its own Column; the next
        // setting is then outside it. Such a wrapper says so itself.
        return !!(item.parent && item.parent.settingsGroupContinues === true)
    }
    component SettingsSection: GlassPane {
        default property alias rows: sectionRows.data
        width: parent ? parent.width : 0
        height: sectionRows.implicitHeight
        radius: 24
        subtle: true
        edgeGlow: false
        cardStyle: appRoot.panelGlassStyle
        Column { id: sectionRows; width: parent.width }
    }
    // iOS/macOS notification badge: a red capsule with the white count.
    component NotificationBadge: Rectangle {
        property int count: 1
        height: 18; width: Math.max(height, badgeCount.implicitWidth + 10); radius: height / 2
        color: "#FF3B30"
        GlassText { id: badgeCount; anchors.centerIn: parent; text: parent.count; color: "white"; font.pixelSize: 11; font.bold: true }
    }
    // Text standing on the wallpaper (section titles, captions, the Settings
    // rail, page titles): a small soft shadow, like the instance picker's, so
    // it reads over busy wallpapers. Dark: a dark shadow under light text;
    // light: a light halo around dark text. Text inside glass stays plain.
    // Strength: Settings › Layout › Text shadow.
    component BackdropText: GlassText {
        layer.enabled: visible && text.length > 0 && appRoot.textShadow > 0.01
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: appRoot.darkMode ? "black" : "white"
            shadowOpacity: Math.min(1, appRoot.textShadow * (appRoot.darkMode ? 1 : 1.1))
            shadowBlur: 0.6; blurMax: 24
            shadowVerticalOffset: appRoot.darkMode ? 1 : 0
        }
    }
    component SettingsCaption: BackdropText {
        width: parent ? parent.width : 0
        leftPadding: 18; rightPadding: 18
        color: appRoot.muted; font.pixelSize: 13
        wrapMode: Text.Wrap
    }
    component SettingsRow: Item {
        id: settingsRow
        property string symbol: ""
        property color tileColor: "#8E8E93"
        property string title: ""
        property string value: ""
        property bool chevron: false
        property bool last: false
        readonly property real titleX: symbol.length ? 62 : 18
        default property alias accessory: rowAccessory.data
        signal clicked()
        width: parent ? parent.width : 0
        height: 54
        // Found by the Settings search (settingsSearch) and briefly lit there.
        readonly property bool isSettingsRow: true
        property real searchFlash: 0
        function flash() { rowFlash.restart() }
        SequentialAnimation {
            id: rowFlash
            NumberAnimation { target: settingsRow; property: "searchFlash"; to: 1; duration: 160; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 700 }
            NumberAnimation { target: settingsRow; property: "searchFlash"; to: 0; duration: 600; easing.type: Easing.InOutQuad }
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 4; radius: 20
            color: appRoot.accent; opacity: settingsRow.searchFlash * 0.28
            visible: opacity > 0
        }
        // Concentric with the section: 24 − 4 inset.
        Rectangle {
            anchors.fill: parent; anchors.margins: 4; radius: 20
            color: appRoot.darkMode ? "#16FFFFFF" : "#10000000"
            visible: settingsRow.chevron && settingsRow.enabled && (rowHover.hovered || rowTap.pressed)
        }
        Rectangle {
            id: rowTile
            visible: settingsRow.symbol.length > 0
            x: 18; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            color: settingsRow.tileColor
            SymbolImage { anchors.centerIn: parent; width: 19; height: 19; symbol: settingsRow.symbol; tint: "white" }
        }
        GlassText {
            x: settingsRow.titleX; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, rowTrailing.x - x - 12)
            text: settingsRow.title; color: appRoot.ink; font.pixelSize: 15; elide: Text.ElideRight; textFormat: Text.PlainText
        }
        Row {
            id: rowTrailing
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            GlassText {
                visible: settingsRow.value.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: settingsRow.value; color: appRoot.muted; font.pixelSize: 15; textFormat: Text.PlainText
            }
            Row { id: rowAccessory; spacing: 8; anchors.verticalCenter: parent.verticalCenter }
            SymbolImage {
                visible: settingsRow.chevron
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; symbol: "chevron.right"; tint: appRoot.muted
            }
        }
        // A visible SettingsBlock right after this row is the same setting
        // (its slider or options), so no separator between them (Apple
        // Settings); the block draws the one that ends the setting.
        readonly property bool detailFollows: {
            var siblings = parent ? parent.children : []
            var mine = -1
            for (var j = 0; j < siblings.length; j++) if (siblings[j] === settingsRow) mine = j
            if (mine < 0) return false
            // The next *visible* sibling: hidden blocks (e.g. the image options
            // while a colour background is chosen) sit between a row and its
            // shown options.
            for (var i = mine + 1; i < siblings.length; i++)
                if (siblings[i].visible) return !!siblings[i].isSettingsBlock
            return false
        }
        Rectangle {
            visible: !settingsRow.last && !settingsRow.detailFollows && appRoot.settingsContentFollows(settingsRow)
            anchors.left: parent.left; anchors.leftMargin: settingsRow.titleX
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom
            height: 1; color: appRoot.darkMode ? "#2EFFFFFF" : "#26000000"
        }
        HoverHandler { id: rowHover; enabled: settingsRow.chevron }
        TapHandler { id: rowTap; enabled: settingsRow.chevron; onTapped: settingsRow.clicked() }
    }
    // App Store "Get" button: an accent capsule that becomes a determinate
    // progress ring with a stop square while prismBridge installs.
    component InstallButton: Item {
        id: installButton
        property bool ready: true
        readonly property bool busy: prismBridge.installing
        signal install()
        implicitWidth: busy ? 34 : 92
        implicitHeight: 34
        Behavior on implicitWidth { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.Button
        Accessible.name: busy ? appRoot.tr("Stop installing, ") + Math.round(prismBridge.installProgress * 100) + "%" : appRoot.tr("Install")
        GlassPane {
            objectName: "editorGlassControl"
            property string materialRole: "button"
            anchors.fill: parent; radius: height / 2
            opacity: installButton.busy ? 0 : (installButton.ready ? 1 : 0.45)
            Behavior on opacity { NumberAnimation { duration: 160 } }
            color: macWindowMetrics.nativeGlassDock ? "transparent" : Qt.darker(appRoot.accent, installTap.pressed ? 1.18 : installHover.hovered ? 1.08 : 1)
            border.width: 0; edgeGlow: false
            GlassText {
                anchors.centerIn: parent
                text: appRoot.tr("Install")
                color: macWindowMetrics.nativeGlassDock ? appRoot.ink : "white"
                font.pixelSize: 13; font.bold: true
            }
        }
        Canvas {
            id: installRing
            anchors.fill: parent
            visible: installButton.busy
            readonly property real progress: prismBridge.installProgress
            onProgressChanged: requestPaint()
            onVisibleChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"), r = width / 2 - 2
                ctx.reset(); ctx.lineWidth = 3; ctx.lineCap = "round"
                ctx.strokeStyle = appRoot.darkMode ? "#33FFFFFF" : "#26000000"
                ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2); ctx.stroke()
                if (progress > 0) {
                    ctx.strokeStyle = appRoot.accent
                    ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, progress)); ctx.stroke()
                }
            }
            SymbolImage { anchors.centerIn: parent; width: 14; height: 14; symbol: installButton.busy ? "stop.fill" : ""; tint: appRoot.accent }
        }
        HoverHandler { id: installHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: installTap
            onTapped: if (installButton.busy) prismBridge.cancelInstall(); else if (installButton.ready) installButton.install()
        }
    }
    // Material tint laid over liquid glass. The glass shader draws continuous
    // (squircle) corners; a Rectangle's circular corners left glass pixels
    // showing outside the tint at each corner, so the tint uses the same clip.
    component GlassTint: Item {
        id: glassTint
        property color color: appRoot.darkMode ? "#D91C1C20" : "#E0F6F6F8"
        property real radius: 0
        anchors.fill: parent
        layer.enabled: visible; layer.smooth: true
        layer.effect: ContinuousClip { radius: glassTint.radius }
        Rectangle { anchors.fill: parent; color: glassTint.color }
    }
    // Sheet / dialog background: liquid glass under a sheet tint (Windows),
    // so the rim stays glass but nothing behind reads through the text.
    // A sheet's title or button bar, as a Download page's bar: the content
    // under it blurred over the sheet colour, and a hairline toward the content.
    // A modal popup's dim, cut to the window's continuous corners (the same
    // contour as contentItem's clip). Qt's default dim is a plain rectangle
    // over the whole window, which greyed the transparent pixels outside the
    // rounded corners.
    component SheetDim: RoundedPanel { radius: appRoot.windowRadius; color: Qt.rgba(0, 0, 0, 0.5) }
    component SheetBar: Item {
        id: sheetBar
        property Item source: null
        property bool hairlineAtBottom: true
        Rectangle { anchors.fill: parent; color: appRoot.popupSurface }
        ShaderEffectSource {
            id: sheetBarSource
            anchors.fill: parent
            sourceItem: sheetBar.source
            sourceRect: Qt.rect(sheetBar.x, sheetBar.y, sheetBar.width, sheetBar.height)
            live: true; hideSource: false; visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: sheetBarSource
            blurEnabled: true; blur: 1.0; blurMax: 40
            autoPaddingEnabled: false
            opacity: 0.85
        }
        Rectangle {
            width: parent.width; height: 1
            y: sheetBar.hairlineAtBottom ? parent.height - 1 : 0
            color: appRoot.darkMode ? "#2EFFFFFF" : "#1F000000"
        }
    }
    component SheetBackground: GlassPane {
        radius: 24
        color: appRoot.customWindowChrome || macWindowMetrics.nativeAccountGlass ? "transparent" : appRoot.glassStrong
        border.width: 0
        solidInPopup: false
        liquidGlass: !appRoot.customWindowChrome
        RoundedPanel {
            anchors.fill: parent; visible: appRoot.customWindowChrome
            radius: parent.radius; color: appRoot.popupSurface
            rimWidth: 1; rimColor: appRoot.darkMode ? "#1FFFFFFF" : "#14000000"
        }
    }
    // macOS 27 context menu. macOS keeps the system menu (Popup.Native);
    // The macOS 27 menu material. A menu floats directly over the page, so it
    // samples it, unless its host is inside a popup: that hides the page.
    component MenuPanel: Item {
        id: menuPanel
        property bool open: false
        property Item host: null
        property real radius: 13
        implicitWidth: 250
        onOpenChanged: appRoot.openGlassMenus += open ? 1 : -1
        readonly property bool blurred: appRoot.liquidGlass && glassTuning.materialVisible && !glassTuning.reducedTransparency && !appRoot.insidePopup(host)
        GlassPane {
            anchors.fill: parent
            visible: !menuPanel.blurred
            radius: menuPanel.radius
            color: appRoot.glassStrong
            border.width: 1
            border.color: appRoot.darkMode ? "#33FFFFFF" : "#26000000"
            edgeGlow: false
            GlassTint { radius: parent.radius }
        }
        Loader {
            anchors.fill: parent
            active: menuPanel.blurred && menuPanel.open
            sourceComponent: TunedLiquidGlass {
                surface: menuPanel
                viewport: contentScene
                sharpTexture: sceneSharpTexture
                blurredTexture: menuFrostTexture
                radius: menuPanel.radius
                frost: 1; density: 0; refraction: 0; glare: 0
                // The bevel thins the frost, which would leave the rim legible.
                bevelWidth: 1
                fresnelAmount: 0; specularAmount: 0; edgeAmount: 0; strokeWidth: 0
                saturation: 1.5; brightness: appRoot.darkMode ? 1.1 : 1
                shadowAmount: 3
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: menuPanel.blurred
            radius: menuPanel.radius
            color: appRoot.darkMode ? "#1AFFFFFF" : "#40FFFFFF"
            // The glass edge comes from Settings › Liquid Glass, not a fixed border.
            border.width: 0
        }
    }
    // elsewhere the menu is an in-window item drawn like the macOS 27 one: a
    // 250 pt panel of the blurred page with a 13 pt radius, 5 pt padding, 24 pt
    // items with a checkmark column, accent highlight with white text, submenu
    // chevrons and hairline separators aligned with the titles.
    component GlassMenu: Menu {
        id: glassMenu
        popupType: Qt.platform.os === "osx" ? Popup.Native : Popup.Item
        padding: 5
        margins: 8
        overlap: 6
        implicitWidth: 250
        // Hides this submenu's row. `visible` would open the menu itself.
        property bool rowHidden: false
        delegate: GlassMenuItem { }
        background: MenuPanel { open: glassMenu.visible }
    }
    component GlassMenuItem: MenuItem {
        id: glassMenuItem
        implicitWidth: Math.max(200, menuItemLabel.implicitWidth + 64)
        implicitHeight: 24
        visible: !(subMenu && subMenu.rowHidden)
        height: visible ? implicitHeight : 0
        leftPadding: 25; rightPadding: 28
        readonly property bool lit: highlighted && enabled
        contentItem: GlassText {
            id: menuItemLabel
            text: glassMenuItem.text
            font.pixelSize: 13
            color: glassMenuItem.lit ? "white" : appRoot.ink
            opacity: glassMenuItem.enabled ? 1 : 0.35
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: SymbolImage {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12
            visible: glassMenuItem.checkable && glassMenuItem.checked
            symbol: visible ? "checkmark" : ""
            tint: glassMenuItem.lit ? "white" : appRoot.ink
        }
        arrow: SymbolImage {
            x: glassMenuItem.width - width - 11; anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14
            visible: !!glassMenuItem.subMenu
            symbol: visible ? "chevron.right" : ""
            tint: glassMenuItem.lit ? "white" : appRoot.ink
            opacity: glassMenuItem.enabled ? 1 : 0.35
        }
        background: Rectangle {
            radius: 8
            color: glassMenuItem.lit ? appRoot.accent : "transparent"
        }
    }
    component GlassMenuSeparator: MenuSeparator {
        height: visible ? implicitHeight : 0
        topPadding: 5; bottomPadding: 5; leftPadding: 25; rightPadding: 10
        contentItem: Rectangle {
            implicitHeight: 1
            color: appRoot.darkMode ? "#26FFFFFF" : "#1A000000"
        }
    }
    // macOS menu item: leading symbol, left-aligned title; the hovered item
    // gets an accent highlight with white text and symbol.
    component AccountMenuRow: Item {
        id: menuRow
        property string symbol: ""
        property string title: ""
        signal activated()
        width: parent ? parent.width : 0; height: 34
        Accessible.role: Accessible.MenuItem; Accessible.name: title
        Rectangle {
            anchors.fill: parent; radius: 8
            color: menuRowHover.hovered ? appRoot.accent : "transparent"
        }
        SymbolImage { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; symbol: menuRow.symbol; tint: menuRowHover.hovered ? "white" : appRoot.ink }
        GlassText { x: 36; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; text: menuRow.title; elide: Text.ElideRight; color: menuRowHover.hovered ? "white" : appRoot.ink; font.pixelSize: 13 }
        HoverHandler { id: menuRowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: menuRow.activated() }
    }
    // Download toolbar filters: refresh, loader (Mods only) and sort.
    component DownloadFilters: RowLayout {
        spacing: 6
        GlassPane {
            objectName: "editorGlassControl"
            property string materialRole:"button"
            color: macWindowMetrics.nativeGlassDock ? "transparent" : prominent ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.24) : (appRoot.darkMode ? "#0CFFFFFF" : "#35FFFFFF")
            border.width: macWindowMetrics.nativeGlassDock ? 0 : 1
            edgeGlow: !macWindowMetrics.nativeGlassDock
            Layout.preferredWidth: 84; Layout.preferredHeight: appRoot.downloadControlHeight; radius: appRoot.downloadControlRadius
            GlassText { anchors.centerIn: parent; text: appRoot.tr("Refresh"); color: appRoot.ink; font.pixelSize: 13 }
            TapHandler { enabled: !downloadData.catalogueBusy; onTapped: appRoot.refreshCatalogue() }
        }
        GlassSelect {
            visible: appRoot.downloadCategory === "Mods"
            Layout.preferredWidth: 132
            Layout.preferredHeight: appRoot.downloadControlHeight
            controlHeight: appRoot.downloadControlHeight
            cornerRadius: appRoot.downloadControlRadius
            glassMaterial: true
            options: ["All loaders", "Fabric", "Forge", "NeoForge", "Quilt"]
            selected: appRoot.downloadLoaderFilter
            onChosen: function(value) { appRoot.downloadLoaderFilter = value }
        }
        GlassSelect {
            Layout.preferredWidth: 142
            Layout.preferredHeight: appRoot.downloadControlHeight
            controlHeight: appRoot.downloadControlHeight
            cornerRadius: appRoot.downloadControlRadius
            glassMaterial: true
            options: ["Featured", "Newest", "Updated"]
            selected: appRoot.downloadSort
            onChosen: function(value) { appRoot.downloadSort = value }
        }
    }
    // Multi-line field for long values (JVM arguments), styled like GroupField.
    // Follows its source while not focused; commits on focus loss.
    component SettingsTextArea: TextArea {
        id: settingsTextArea
        property string source: ""
        signal committed(string value)
        wrapMode: TextEdit.WrapAnywhere
        font.family: "Consolas"; font.pixelSize: 12
        color: appRoot.ink; selectByMouse: true
        leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
        background: Rectangle {
            radius: 10
            color: appRoot.fieldFill
            border.width: 1
            border.color: settingsTextArea.activeFocus ? appRoot.accent : (appRoot.darkMode ? "#0AFFFFFF" : "#1A000000")
        }
        onActiveFocusChanged: if (!activeFocus && text !== source) committed(text)
        Binding on text { when: !settingsTextArea.activeFocus; value: settingsTextArea.source; restoreMode: Binding.RestoreNone }
    }
    // Single-line core setting field: follows the setting while not focused.
    component CoreSettingField: GroupField {
        id: coreField
        property string key: ""
        property string fallback: ""
        selectByMouse: true
        onEditingFinished: appRoot.setCore(key, text)
        onAccepted: focus = false
        Binding on text { when: !coreField.activeFocus; value: String(appRoot.core(coreField.key) || coreField.fallback); restoreMode: Binding.RestoreNone }
    }
    // Small round glyph button (macOS list +/− controls).
    component CircleGlyphButton: Rectangle {
        id: glyphButton
        property string glyph: ""
        signal clicked()
        implicitWidth: 26; implicitHeight: 26; radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: appRoot.buttonFill(glyphTap.pressed, glyphHover.hovered)
        Accessible.role: Accessible.Button; Accessible.name: glyph
        GlassText { anchors.centerIn: parent; text: glyphButton.glyph; color: appRoot.buttonText; font.pixelSize: 16; font.bold: true }
        HoverHandler { id: glyphHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: glyphTap; onTapped: glyphButton.clicked() }
    }
    // Numbered instruction for the sign-in sheet.
    component LoginStep: Row {
        id: loginStep
        property string number: ""
        property string text: ""
        width: parent ? parent.width : 0; spacing: 10
        Rectangle {
            width: 22; height: 22; radius: 11
            color: appRoot.darkMode ? "#24FFFFFF" : "#14000000"
            GlassText { anchors.centerIn: parent; text: loginStep.number; color: appRoot.ink; font.pixelSize: 12; font.bold: true }
        }
        GlassText { width: loginStep.width - 32; anchors.verticalCenter: parent.verticalCenter; text: loginStep.text; wrapMode: Text.Wrap; color: appRoot.ink; font.pixelSize: 14 }
    }
    // Free-form content inside a section, aligned with the row titles.
    component SettingsBlock: Item {
        id: settingsBlock
        readonly property bool isSettingsBlock: true
        property bool last: false
        default property alias content: blockContent.data
        width: parent ? parent.width : 0
        // Continues the row above: little top padding, the row's own bottom.
        height: blockContent.implicitHeight + 16
        Column { id: blockContent; x: 62; y: 2; width: parent.width - 62 - 16; spacing: 10 }
        Rectangle {
            visible: !settingsBlock.last && appRoot.settingsContentFollows(settingsBlock)
            anchors.left: parent.left; anchors.leftMargin: 62
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom
            height: 1; color: appRoot.darkMode ? "#2EFFFFFF" : "#26000000"
        }
    }

    // SF Symbol on macOS; bundled stand-in elsewhere (Frontend.cpp). Callers
    // keep their glyph fallback visible until status is Image.Ready.
    component SymbolImage: Image {
        property string symbol: ""
        property color tint: appRoot.ink
        source: { var revision=macWindowMetrics.symbolRevision; return symbol ? macWindowMetrics.symbolIcon(symbol,tint.toString()) : "" }
        fillMode: Image.PreserveAspectFit
    }
    component NativeChevron: Image {
        property string symbol: "chevron.down"
        property color tint: appRoot.muted
        readonly property bool disclosure: symbol === "chevron.down" || symbol === "chevron.right" || symbol === "chevron.up"
        width:16; height:16
        source:{ var revision=macWindowMetrics.symbolRevision; return macWindowMetrics.symbolIcon(disclosure ? (symbol === "chevron.right" ? "appkit.disclosure.closed" : "appkit.disclosure.open") : symbol,tint.toString()) }
        // The AppKit cell is centered in a padded canvas at its natural size.
        // Explicit raster size avoids treating Retina pixels as logical points.
        sourceSize.width:32; sourceSize.height:32
        fillMode:Image.PreserveAspectFit
    }
    component GlassSelect: ComboBox {
        id: glassSelectRoot
        property var options: []
        property string selected: ""
        property bool accountMaterial: false
        property bool nativeDownloadMaterial: false
        property bool sidebarMaterial: false
        property bool compact: false
        // Windows: glass instead of the flat field fill, for selectors that sit
        // beside glass capsules (download toolbar).
        property bool glassMaterial: false
        property real controlHeight: appRoot.customWindowChrome ? 26 : 34
        property real cornerRadius: appRoot.customWindowChrome ? 8 : 14
        readonly property real rowHeight: appRoot.customWindowChrome ? 24 : 32
        signal chosen(string value)
        height: controlHeight
        implicitHeight: controlHeight
        model: options
        function syncSelectedIndex() {
            var index = options.indexOf(selected)
            if (index >= 0 && currentIndex !== index) currentIndex = index
        }
        onSelectedChanged: syncSelectedIndex()
        onOptionsChanged: syncSelectedIndex()
        Component.onCompleted: syncSelectedIndex()
        onActivated: function(index) { chosen(options[index]) }

        contentItem: GlassText {
            leftPadding: 12
            rightPadding: 30
            // Options stay English values; only their labels are translated.
            text: appRoot.tr(glassSelectRoot.selected)
            color: appRoot.customWindowChrome ? appRoot.buttonText : appRoot.ink
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: GlassPane {
            x:glassSelectRoot.width-width-6; y:(glassSelectRoot.height-height)/2
            width:24; height:24; radius:12
            visible: !appRoot.customWindowChrome
            objectName:glassSelectRoot.sidebarMaterial ? "sidebarGlassControl" : ""
            property string nativeRole:"field"
            color:macWindowMetrics.nativeSidebar && glassSelectRoot.sidebarMaterial ? "transparent" : (appRoot.darkMode ? "#20FFFFFF" : "#20000000")
            border.width:0
            edgeGlow:false
            NativeChevron { anchors.centerIn:parent; width:14; height:14; symbol:"appkit.selector" }
            MouseArea {
                anchors.fill:parent
                onPressed:function(mouse) { if(glassSelectRoot.popup.visible)glassSelectRoot.popup.close();else glassSelectRoot.popup.open();mouse.accepted=true }
            }
        }
        background: GlassSurface {
            objectName: glassSelectRoot.accountMaterial && macWindowMetrics.nativeGlassDock ? "accountGlassControl" : glassSelectRoot.nativeDownloadMaterial && macWindowMetrics.nativeGlassDock ? "editorGlassControl" : (glassSelectRoot.sidebarMaterial ? "sidebarGlassControl" : "")
            property bool nativeSelected: glassSelectRoot.popup.visible
            property bool glassHovered: glassSelectRoot.hovered || glassSelectRoot.popup.visible
            property string nativeRole: "field"
            // Every selector field is native glass on macOS (popup button or
            // a sidebar/account/editor material).
            // On a glass pane: plain blur (GlassSurface.plainBlur).
            liquidGlass: !appRoot.customWindowChrome || glassSelectRoot.glassMaterial || onLiquidPane
            radius: glassSelectRoot.cornerRadius
            color: glassSelectRoot.glassMaterial && appRoot.customWindowChrome ? appRoot.buttonFill(glassSelectRoot.down, glassSelectRoot.hovered) : appRoot.customWindowChrome ? appRoot.selectFill(glassSelectRoot.down, glassSelectRoot.hovered) : (glassSelectRoot.accountMaterial && macWindowMetrics.nativeGlassDock) || (glassSelectRoot.nativeDownloadMaterial && macWindowMetrics.nativeGlassDock) || (macWindowMetrics.nativeSidebar && glassSelectRoot.sidebarMaterial) ? "transparent" : (appRoot.darkMode ? "#3E57768C" : "#C7EAF4FC")
            border.width: appRoot.customWindowChrome ? 0 : (glassSelectRoot.accountMaterial && macWindowMetrics.nativeGlassDock) || (glassSelectRoot.nativeDownloadMaterial && macWindowMetrics.nativeGlassDock) || (macWindowMetrics.nativeSidebar && glassSelectRoot.sidebarMaterial) ? 0 : 1
            border.color: glassSelectRoot.hovered || glassSelectRoot.popup.visible
                          ? appRoot.accent : appRoot.outline
            Behavior on border.color { ColorAnimation { duration: 150 } }
            NativeChevron { visible: appRoot.customWindowChrome; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; symbol: "appkit.selector"; tint: appRoot.ink }
        }
        delegate: ItemDelegate {
            id: selectorItem
            required property string modelData
            required property int index
            // macOS menu: the item under the pointer (or keyboard) gets an
            // accent highlight with white text; the chosen value has a checkmark.
            readonly property bool chosenItem: modelData === glassSelectRoot.selected
            readonly property bool lit: !macWindowMetrics.nativeGlassDock && (hovered || glassSelectRoot.highlightedIndex === index)
            width: glassSelectRoot.popup.availableWidth
            height: glassSelectRoot.rowHeight
            highlighted: glassSelectRoot.highlightedIndex === index
            leftPadding: appRoot.customWindowChrome ? 25 : 30
            topPadding: 0; bottomPadding: 0
            contentItem: GlassText {
                text: appRoot.tr(modelData)
                color: selectorItem.lit ? "white" : appRoot.ink
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            SymbolImage {
                visible: selectorItem.chosenItem
                x: appRoot.customWindowChrome ? 6 : 10; anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; symbol: visible ? "checkmark" : ""
                tint: selectorItem.lit ? "white" : appRoot.ink
            }
            onHoveredChanged: if(selectorPopup.visible && macWindowMetrics.nativeGlassDock)macWindowMetrics.setAccountGlass(selectorPopup.contentItem,true)
            background: GlassSurface {
                objectName: macWindowMetrics.nativeGlassDock && (selectorItem.chosenItem || parent.hovered) ? "accountGlassControl" : ""
                liquidGlass: macWindowMetrics.nativeGlassDock && (selectorItem.chosenItem || parent.hovered)
                selectedGlass: macWindowMetrics.nativeGlassDock && selectorItem.chosenItem
                solidInPopup: false
                radius: 8
                color: selectorItem.lit ? appRoot.accent : "transparent"
            }
            onClicked: {
                glassSelectRoot.currentIndex = index
                glassSelectRoot.chosen(modelData)
                glassSelectRoot.popup.close()
            }
        }
        popup: Popup {
            id: selectorPopup
            popupType:macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
            onOpened:if(macWindowMetrics.nativeGlassDock)macWindowMetrics.setAccountGlass(contentItem,true)
            onClosed:if(macWindowMetrics.nativeGlassDock)macWindowMetrics.setAccountGlass(contentItem,false)
            Timer { interval:16;repeat:true;running:selectorPopup.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(selectorPopup.contentItem,true) }
            focus: true
            modal: false
            readonly property bool overTrigger: appRoot.customWindowChrome
            padding: overTrigger ? 5 : 6
            z: 300
            // macOS pop-up button: the chosen row lies over the control, its
            // title on the control's; margins keep the list inside the window.
            readonly property real titleOffset: padding + 25 - 12
            margins: overTrigger ? 8 : -1
            x: overTrigger ? -titleOffset : 0
            width: glassSelectRoot.width + (overTrigger ? titleOffset : 0)
            height: Math.min(glassSelectRoot.options.length * glassSelectRoot.rowHeight + 2 * padding, appRoot.height - 24)
            readonly property point triggerPoint: glassSelectRoot.mapToItem(appRoot.contentItem, 0, 0)
            readonly property real triggerGap: 8
            y: overTrigger ? (glassSelectRoot.height - glassSelectRoot.rowHeight) / 2 - padding - Math.max(0, glassSelectRoot.currentIndex) * glassSelectRoot.rowHeight
               : triggerPoint.y + glassSelectRoot.height + triggerGap + height <= appRoot.height - 12
               ? glassSelectRoot.height + triggerGap
               : -height - triggerGap
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            background: Item {
                MenuPanel { anchors.fill: parent; visible: selectorPopup.overTrigger; open: selectorPopup.overTrigger && selectorPopup.visible; host: glassSelectRoot }
                GlassPane {
                    anchors.fill: parent; visible: !selectorPopup.overTrigger
                    // Item radius (8) plus the 6 pt menu padding.
                    radius: 14
                    emphasized: true
                    color:macWindowMetrics.nativeAccountGlass?"transparent":appRoot.glassStrong
                    edgeGlow:!macWindowMetrics.nativeAccountGlass
                    border.width:macWindowMetrics.nativeAccountGlass?0:1
                    border.color: appRoot.outline
                }
            }
            contentItem: ListView {
                clip: true
                model: selectorPopup.visible ? glassSelectRoot.delegateModel : null
                currentIndex: glassSelectRoot.highlightedIndex
                onContentYChanged:if(selectorPopup.visible && macWindowMetrics.nativeGlassDock)macWindowMetrics.setAccountGlass(selectorPopup.contentItem,true)
                implicitHeight: contentHeight
                ScrollBar.vertical: ScrollBar { }
            }
        }
    }

    // LiquidGlass with every GlassTuning parameter bound; users set geometry,
    // textures and per-control extras.
    component TunedLiquidGlass: LiquidGlass {
        stroke: glassTuning.strokeColor(appRoot.darkMode)
        strokeWidth: glassTuning.effectiveStrokeWidth
        density: glassTuning.effectiveDensity
        frost: glassTuning.effectiveFrost
        refraction: glassTuning.effectiveRefraction
        glare: glassTuning.effectiveGlare
        refractiveIndex: glassTuning.refractiveIndex
        bevelWidth: glassTuning.bevelWidth
        dispersion: glassTuning.dispersion
        magnification: glassTuning.magnification
        saturation: glassTuning.saturation
        brightness: glassTuning.brightness
        fresnelAmount: glassTuning.fresnelAmount
        specularAmount: glassTuning.effectiveSpecular
        edgeAmount: glassTuning.effectiveEdge
        shadowAmount: glassTuning.shadowAmount
        lightAngle: glassTuning.lightAngle
        interactionStrength: glassTuning.interactionStrength
        interactionRadius: glassTuning.interactionRadius
        responseTime: glassTuning.responseTime
        dark: appRoot.darkMode
        reducedTransparency: glassTuning.reducedTransparency
        reducedMotion: glassTuning.reducedMotion
        staticReflection: glassTuning.staticReflection
        macStyle: glassTuning.macStyle
    }

    // Glass Lab switch/slider thumb: a white capsule at rest that grows and
    // fades into Liquid Glass while pressed. The glass samples `backdrop`, a
    // small composite of the wallpaper and the control's own track that never
    // contains the thumb itself.
    component GlassThumb: Item {
        id: thumb
        property real amount: 0
        property Item backdrop: null
        property var backdropTexture: null
        property real refractionDirection: 1
        property real gain: 1
        property point pointer: Qt.point(width / 2, height / 2)
        Behavior on width { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Loader {
            anchors.fill: parent
            opacity: thumb.amount
            active: appRoot.liquidGlass && glassTuning.materialVisible && thumb.amount > 0.001
                    && thumb.backdrop !== null && Window.window === appRoot
            sourceComponent: TunedLiquidGlass {
                surface: thumb
                viewport: thumb.backdrop
                sharpTexture: thumb.backdropTexture
                blurredTexture: thumb.backdropTexture
                radius: Math.min(thumb.width, thumb.height) / 2
                refractionDirection: thumb.refractionDirection
                externalInteractionEnabled: true
                externalInteraction: Qt.vector4d(thumb.pointer.x, thumb.pointer.y, 1, 1)
                interactionStrength: glassTuning.interactionStrength * thumb.gain
            }
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: height / 2
            color: "white"
            // Without Liquid Glass the thumb stays a white capsule.
            opacity: !appRoot.liquidGlass || !glassTuning.materialVisible ? 1 : 1 - thumb.amount
        }
    }

    // Wallpaper region beneath a control, for GlassThumb backdrops. Children
    // add copies of the control's track at matching positions.
    component GlassThumbBackdrop: Item {
        id: thumbBackdrop
        property bool active: false
        visible: false
        readonly property rect wallpaperRect: {
            if (!active) return Qt.rect(0, 0, 1, 1)
            var p = mapToItem(backgroundLayer, 0, 0)
            return Qt.rect(p.x, p.y, width, height)
        }
        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: thumbBackdrop.active ? backgroundLayer : null
            sourceRect: thumbBackdrop.wallpaperRect
            live: thumbBackdrop.active
            hideSource: false; smooth: true
        }
        // The pane under the control: a thumb must not cut through it to the
        // wallpaper. A Liquid Glass pane is redrawn as it looks (the frosted
        // wallpaper); a fixed grey showed as a dark ring in the grown lens.
        readonly property bool inMenu: appRoot.insideMenuPanel(thumbBackdrop)
        readonly property bool solid: appRoot.insidePopup(thumbBackdrop)
        readonly property bool glassPane: appRoot.liquidGlass && glassTuning.materialVisible && !inMenu && !solid
        ShaderEffectSource {
            anchors.fill: parent
            visible: thumbBackdrop.glassPane
            opacity: glassTuning.reducedTransparency ? 0 : Math.max(0.35, glassTuning.effectiveFrost)
            sourceItem: thumbBackdrop.active && thumbBackdrop.glassPane ? wallpaperBlur : null
            sourceRect: thumbBackdrop.wallpaperRect
            live: thumbBackdrop.active
            hideSource: false; smooth: true
        }
        Rectangle {
            anchors.fill: parent
            color: thumbBackdrop.inMenu ? (appRoot.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.4))
                 : thumbBackdrop.solid ? appRoot.popupSurface
                 // The lens applies the glass brightness again: no extra veil.
                 : thumbBackdrop.glassPane ? (appRoot.darkMode ? "transparent" : Qt.rgba(1, 1, 1, 0.2))
                 : appRoot.darkMode ? Qt.rgba(0.17, 0.17, 0.17, 0.72) : Qt.rgba(0.96, 0.96, 0.96, 0.72)
        }
    }

    // Switch from the Glass Lab: grey/green capsule track, white thumb that
    // stretches into a convex glass lens while pressed. Click, drag and keys
    // keep the stock Switch behaviour, including toggled().
    component GlassSwitch: Switch {
        id: glassSwitch
        property real interactionAmount: pressed ? 1 : 0
        Behavior on interactionAmount { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        property real thumbPosition: visualPosition
        Behavior on thumbPosition {
            enabled: !glassSwitch.pressed && !glassTuning.reducedMotion
            NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.65 }
        }
        readonly property bool glassActive: appRoot.liquidGlass && interactionAmount > 0.001
        PointHandler { id: switchPointer; target: null }
        indicator: Item {
            id: switchIndicator
            implicitWidth: 64; implicitHeight: 28
            x: glassSwitch.text ? (glassSwitch.mirrored ? glassSwitch.width - width - glassSwitch.rightPadding : glassSwitch.leftPadding)
                                : glassSwitch.leftPadding + (glassSwitch.availableWidth - width) / 2
            y: glassSwitch.topPadding + (glassSwitch.availableHeight - height) / 2
            opacity: glassSwitch.enabled ? 1 : 0.45
            Rectangle {
                id: switchTrack
                anchors.fill: parent; radius: height / 2
                // Accent (macOS) or green (iOS): Settings › Appearance.
                color: glassSwitch.checked ? (appRoot.accentSwitches ? appRoot.accent : "#34C759") : (appRoot.customWindowChrome && appRoot.darkMode ? "#1AFFFFFF" : "#DADADA")
                Behavior on color { enabled: !glassTuning.reducedMotion; ColorAnimation { duration: 220 } }
            }
            GlassThumbBackdrop {
                id: switchBackdrop
                x: -16; y: -16; width: parent.width + 32; height: parent.height + 32
                active: glassSwitch.glassActive
                Rectangle { x: 16; y: 16; width: switchTrack.width; height: switchTrack.height; radius: switchTrack.radius; color: switchTrack.color }
            }
            ShaderEffectSource {
                id: switchBackdropTexture
                sourceItem: glassSwitch.glassActive ? switchBackdrop : null
                textureSize: Qt.size(Math.ceil(switchBackdrop.width * appRoot.glassPixelRatio), Math.ceil(switchBackdrop.height * appRoot.glassPixelRatio))
                live: glassSwitch.glassActive; hideSource: false; visible: false; smooth: true
            }
            GlassThumb {
                // The resting thumb's centre stays fixed while the lens grows.
                readonly property bool grown: glassSwitch.pressed && !glassTuning.reducedMotion
                width: grown ? 56 : (appRoot.customWindowChrome ? 38 : 40); height: grown ? 39 : 24
                x: 2 + (appRoot.customWindowChrome ? 19 : 20) + Math.max(0, Math.min(1, glassSwitch.thumbPosition)) * (switchIndicator.width - (appRoot.customWindowChrome ? 42 : 44)) - width / 2
                y: (switchIndicator.height - height) / 2
                amount: glassSwitch.interactionAmount
                backdrop: switchBackdrop
                backdropTexture: switchBackdropTexture
                refractionDirection: -1
                gain: 3
                pointer: switchPointer.active ? mapFromItem(glassSwitch, switchPointer.point.position.x, switchPointer.point.position.y)
                                              : Qt.point(width / 2, height / 2)
            }
        }
    }

    // Slider from the Glass Lab: thin track with an accent fill and a white
    // horizontal capsule (40 x 30 at rest, 50 x 36 pressed) that turns into
    // glass while dragged. thumbScale shrinks it for compact toolbars.
    component GlassSlider: Slider {
        id: glassSlider
        // Windows: a smaller pill, close to the macOS 26 slider knob.
        property real thumbScale: appRoot.customWindowChrome ? 0.8 : 1
        // macOS tick marks: short marks under the track; snapToTick() pulls a
        // value within 2.5% of the range onto the nearest mark.
        property var tickValues: []
        function snapToTick(v) {
            var reach = Math.abs(to - from) * 0.025
            for (var i = 0; i < tickValues.length; i++) if (Math.abs(v - tickValues[i]) <= reach) return tickValues[i]
            return v
        }
        readonly property real thumbWidth: 40 * thumbScale
        readonly property real thumbHeight: 30 * thumbScale
        property real interactionAmount: pressed ? 1 : 0
        Behavior on interactionAmount { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        readonly property bool glassActive: appRoot.liquidGlass && interactionAmount > 0.001
        PointHandler { id: sliderPointer; target: null }
        background: Item {
            id: sliderBackground
            x: glassSlider.leftPadding
            y: glassSlider.topPadding + (glassSlider.availableHeight - height) / 2
            implicitWidth: 200; implicitHeight: 6
            width: glassSlider.availableWidth; height: 6
            opacity: glassSlider.enabled ? 1 : 0.45
            // The track ends at the thumb centres, as in the lab.
            Rectangle {
                id: sliderTrack
                x: glassSlider.thumbWidth / 2
                width: Math.max(0, parent.width - glassSlider.thumbWidth); height: 6; radius: 3
                color: appRoot.darkMode ? "#4B4B4D" : "#DADADA"
                Rectangle { width: parent.width * glassSlider.visualPosition; height: 6; radius: 3; color: appRoot.accent }
            }
            Repeater {
                model: glassSlider.tickValues
                delegate: Rectangle {
                    required property var modelData
                    readonly property real position: (modelData - glassSlider.from) / Math.max(1e-9, glassSlider.to - glassSlider.from)
                    x: sliderTrack.x + position * sliderTrack.width - width / 2
                    y: sliderTrack.height + 9
                    width: 2; height: 6; radius: 1
                    color: appRoot.darkMode ? "#59FFFFFF" : "#40000000"
                }
            }
            GlassThumbBackdrop {
                id: sliderBackdrop
                x: -16; y: -24; width: parent.width + 32; height: parent.height + 48
                active: glassSlider.glassActive
                Rectangle {
                    x: 16 + sliderTrack.x; y: 24; width: sliderTrack.width; height: 6; radius: 3; color: sliderTrack.color
                    Rectangle { width: parent.width * glassSlider.visualPosition; height: 6; radius: 3; color: appRoot.accent }
                }
            }
            ShaderEffectSource {
                id: sliderBackdropTexture
                sourceItem: glassSlider.glassActive ? sliderBackdrop : null
                textureSize: Qt.size(Math.ceil(sliderBackdrop.width * appRoot.glassPixelRatio), Math.ceil(sliderBackdrop.height * appRoot.glassPixelRatio))
                live: glassSlider.glassActive; hideSource: false; visible: false; smooth: true
            }
        }
        // A fixed-size handle keeps Slider's pointer-to-value mapping exact;
        // the visible thumb grows around its centre.
        handle: Item {
            x: glassSlider.leftPadding + glassSlider.visualPosition * (glassSlider.availableWidth - width)
            y: glassSlider.topPadding + (glassSlider.availableHeight - height) / 2
            implicitWidth: glassSlider.thumbWidth; implicitHeight: glassSlider.thumbHeight
            opacity: glassSlider.enabled ? 1 : 0.45
            GlassThumb {
                readonly property bool grown: glassSlider.pressed && !glassTuning.reducedMotion
                anchors.centerIn: parent
                width: glassSlider.thumbWidth * (grown ? 1.25 : 1); height: glassSlider.thumbHeight * (grown ? 1.2 : 1)
                amount: glassSlider.interactionAmount
                backdrop: sliderBackdrop
                backdropTexture: sliderBackdropTexture
                gain: 1.8
                pointer: sliderPointer.active ? mapFromItem(glassSlider, sliderPointer.point.position.x, sliderPointer.point.position.y)
                                              : Qt.point(width / 2, height / 2)
            }
        }
    }

    // Rectangle-compatible surface. Where macOS places an NSGlassEffectView,
    // Windows draws the Glass Lab LiquidGlass material instead of the fill. All
    // surfaces share four captures: the wallpaper (for glass inside pages and
    // the canvas) and the composed content (for floating chrome), each sharp
    // and blurred. A surface never samples a texture that contains itself.
    component GlassSurface: Item {
        id: glassSurface
        property alias color: surfaceFill.color
        property alias gradient: surfaceFill.gradient
        property alias border: surfaceFill.border
        property real radius: 0
        property bool prominent: false
        property string materialRole: "glass"
        property bool selectedGlass: false
        property color selectedTint: Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, 0.6)
        // Tint of the Liquid Glass when neither prominent nor selected.
        property color glassTint: "transparent"
        // Large glass only (instance cards): see LiquidGlass.cardStyle.
        property vector4d cardStyle: Qt.vector4d(0, 0, 0, 0)
        // Dark mode: lifts the material to AppKit's level. Rim: see hairline.
        property real surfaceLift: 0
        property color rimColor: "transparent"
        // AppKit uses NSVisualEffectView for content backgrounds and scroll
        // edges; those keep the fill.
        property bool liquidGlass: (objectName === "accountGlassControl" || objectName === "editorGlassControl")
                                   && materialRole !== "content" && materialRole.indexOf("scrollEdge") !== 0
        // Popup.Window content lives in another QQuickWindow and cannot use
        // this window's textures.
        readonly property bool insidePopup: appRoot.insidePopup(parent)
        readonly property bool liquidActive: appRoot.liquidGlass && liquidGlass && Window.window === appRoot && !insidePopup
        readonly property bool insideContent: {
            for (var item = parent; item; item = item.parent)
                if (item === contentScene) return true
            return false
        }
        // The sidebar rail and its account footer use a frostier material.
        readonly property bool insideSidebar: {
            for (var item = parent; item; item = item.parent)
                if (item === sidebar || item === sidebarAccountFooter) return true
            return false
        }
        // The sidebar's frostier material, for large panes (instance editor).
        property bool frosted: false
        // Buttons and fields on a frosted pane (instance editor) take its frost:
        // with the clearer default glass they looked like holes in the pane.
        readonly property bool insideFrosted: {
            for (var item = parent; item; item = item.parent)
                if (item.frosted === true && item.glassFrost !== undefined) return true
            return false
        }
        // Off for a row of a menu, which shows the menu's own panel.
        property bool solidInPopup: !appRoot.insideMenuPanel(glassSurface)
        // Extra frost on top of the Settings value (e.g. the dock fan's capsules).
        property real frostBoost: 0
        readonly property real glassFrost: Math.min(1, (insideSidebar || frosted || insideFrosted ? glassTuning.effectiveSidebarFrost : glassTuning.effectiveFrost) + frostBoost)
        // A button or selector on a Liquid Glass pane (instance editor, dock,
        // sidebar panels) is plain blur: the blurred backdrop only, without
        // refraction, rim, highlights or press response, so glass never sits
        // on glass. Elsewhere it stays Liquid Glass.
        property bool plainBlurOnGlass: true
        readonly property bool onLiquidPane: {
            if (!plainBlurOnGlass) return false
            for (var item = parent; item; item = item.parent)
                if (item.liquidActive === true && item.glassFrost !== undefined) return true
            return false
        }
        // Plain blur wherever it sits (the sidebar's quick download panel).
        property bool forcePlainBlur: false
        readonly property bool plainBlur: liquidActive && (onLiquidPane || forcePlainBlur)
        Rectangle {
            anchors.fill: parent
            radius: glassSurface.radius
            visible: glassSurface.solidInPopup && glassSurface.insidePopup && appRoot.customWindowChrome
            color: appRoot.popupSurface
        }
        Rectangle {
            id: surfaceFill
            anchors.fill: parent
            radius: glassSurface.radius
            visible: !glassSurface.liquidActive
        }
        Loader {
            anchors.fill: parent
            active: glassSurface.liquidActive && !glassSurface.plainBlur && glassTuning.materialVisible && glassSurface.visible
                    && glassSurface.width > 0 && glassSurface.height > 0
            sourceComponent: TunedLiquidGlass {
                surface: glassSurface
                viewport: glassSurface.insideContent ? backgroundLayer : contentScene
                sharpTexture: glassSurface.insideContent ? wallpaperSharpTexture : sceneSharpTexture
                blurredTexture: glassSurface.glassFrost <= 0.001 || glassTuning.reducedTransparency ? sharpTexture
                                : glassSurface.insideContent ? wallpaperFrostTexture : sceneFrostTexture
                frost: glassSurface.glassFrost
                radius: Math.min(glassSurface.radius, glassSurface.width / 2, glassSurface.height / 2)
                tint: glassSurface.prominent ? appRoot.accent
                      : glassSurface.selectedGlass ? glassSurface.selectedTint : glassSurface.glassTint
                cardStyle: glassSurface.cardStyle
                softTexture: glassSurface.cardStyle.w > 0.5 ? (glassSurface.insideContent ? wallpaperSoftTexture : sceneSoftTexture) : null
            }
        }
        Loader {
            anchors.fill: parent
            active: glassSurface.plainBlur && glassTuning.materialVisible && glassSurface.visible
                    && glassSurface.width > 0 && glassSurface.height > 0
            sourceComponent: TunedLiquidGlass {
                surface: glassSurface
                viewport: glassSurface.insideContent ? backgroundLayer : contentScene
                sharpTexture: glassSurface.insideContent ? wallpaperSharpTexture : sceneSharpTexture
                blurredTexture: glassTuning.reducedTransparency ? sharpTexture
                                : glassSurface.insideContent ? wallpaperFrostTexture : sceneFrostTexture
                radius: Math.min(glassSurface.radius, glassSurface.width / 2, glassSurface.height / 2)
                // As the menus' panel: all frost, no optics.
                frost: 1; density: 0; refraction: 0; glare: 0; dispersion: 0; magnification: 1
                bevelWidth: 1
                fresnelAmount: 0; specularAmount: 0; edgeAmount: 0; strokeWidth: 0; shadowAmount: 0
                interactionStrength: 0
                staticReflection: true
                macStyle: Qt.vector4d(0, 0, 0, glassTuning.macStyle.w)
                tint: glassSurface.prominent ? Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, 0.55)
                      : glassSurface.selectedGlass ? glassSurface.selectedTint : glassSurface.glassTint
            }
        }
        // A plain-blur control's own light veil, brighter under the pointer,
        // so it reads as a button on the pane.
        Rectangle {
            anchors.fill: parent
            radius: glassSurface.radius
            visible: glassSurface.plainBlur && !glassSurface.prominent
            color: glassSurface.glassHovered === true
                   ? (appRoot.darkMode ? "#26FFFFFF" : "#59FFFFFF")
                   : (appRoot.darkMode ? "#14FFFFFF" : "#40FFFFFF")
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: glassSurface.radius
            visible: appRoot.customWindowChrome && (glassSurface.surfaceLift > 0 || glassSurface.rimColor.a > 0)
            color: appRoot.darkMode ? Qt.rgba(1, 1, 1, glassSurface.surfaceLift) : "transparent"
            // Over Liquid Glass the shader draws the edge from Settings › Liquid
            // Glass (stroke width, outline highlight); no fixed hairline on top.
            border.width: glassSurface.rimColor.a > 0 && !glassSurface.liquidActive ? 1 : 0
            border.color: glassSurface.rimColor
        }
        // Selection outlines (cards, account button) stay visible over glass.
        Rectangle {
            anchors.fill: parent
            radius: glassSurface.radius
            color: "transparent"
            visible: glassSurface.liquidActive && glassSurface.selectedGlass && surfaceFill.border.width > 0
            border.width: surfaceFill.border.width
            border.color: surfaceFill.border.color
        }
    }

    // Shared glass pane. macOS 26+ replaces these with AppKit glass; Windows
    // uses the GlassSurface LiquidGlass path; elsewhere the QML fallback stays.
    component GlassPane: GlassSurface {
        id: glassPane
        property bool emphasized: false
        property bool subtle: false
        property bool edgeGlow: true
        // Only overlays OUTSIDE sceneLayer may capture it: this prevents
        // feedback loops and keeps instance cards efficient.
        property bool backdropBlur: false
        readonly property bool legacyBlur: backdropBlur && !liquidActive
        surfaceLift: subtle ? 0.03 : 0
        rimColor: subtle ? appRoot.hairline : "transparent"
        liquidGlass: materialRole !== "content" && materialRole.indexOf("scrollEdge") !== 0
        radius: appRoot.panelRadius
        clip: legacyBlur
        color: backdropBlur ? (appRoot.darkMode ? "#66324661" : "#99F4FAFF")
                            : (subtle ? appRoot.glassSoft : (emphasized ? appRoot.glassStrong : appRoot.glass))
        border.width: selectedGlass ? 1.6 : 1
        border.color: selectedGlass ? appRoot.accent : appRoot.outline
        // Real-time Qt Quick backdrop blur. The captured source consists of
        // the canvas and background only, never this overlay or its text.
        // Loaded only when used: every pane (list rows included) would
        // otherwise build a MultiEffect and two texture sources, which made
        // rebuilding a list noticeably slow.
        Loader {
            anchors.fill: parent
            z: 0
            active: glassPane.legacyBlur
            sourceComponent: Item {
                ShaderEffectSource {
                    id: panelBackdropSource
                    anchors.fill: parent
                    sourceItem: sceneLayer
                    sourceRect: {
                        var p = glassPane.mapToItem(sceneLayer, 0, 0)
                        return Qt.rect(p.x, p.y, glassPane.width, glassPane.height)
                    }
                    live: true
                    hideSource: false
                    visible: false
                }
                // Rounded alpha mask: clip:true only clips a rectangular QQuickItem.
                // Without this mask, the blurred image forms a visible square behind
                // rounded panels (particularly the bottom launch dock).
                Rectangle {
                    id: panelBlurMaskShape
                    width: parent.width
                    height: parent.height
                    radius: glassPane.radius
                    color: "white"
                    visible: false
                }
                ShaderEffectSource {
                    id: panelBlurMaskTexture
                    sourceItem: panelBlurMaskShape
                    hideSource: true
                    live: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: panelBackdropSource
                    maskEnabled: true
                    maskSource: panelBlurMaskTexture
                    blurEnabled: true
                    blur: 0.85
                    blurMax: 42
                    autoPaddingEnabled: false
                    opacity: appRoot.darkMode ? 0.84 : 0.90
                }
            }
        }
        // Top-edge specular sheen, clipped to the panel shape.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: appRoot.darkMode ? "#23FFFFFF" : "#78FFFFFF"
            visible: parent.edgeGlow && !parent.liquidActive
            z: -1
        }
        Behavior on color { ColorAnimation { duration: appRoot.motionMs } }
        Behavior on border.color { ColorAnimation { duration: appRoot.motionMs } }
        // Broad, low-contrast specular gradient; the native material bridge
        // is a separate macOS integration and is not emulated here.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Math.max(0, parent.radius - 2)
            gradient: Gradient { GradientStop { position: 0.0; color: appRoot.darkMode ? "#1CFFFFFF" : "#50FFFFFF" } GradientStop { position: 0.22; color: "#08FFFFFF" } GradientStop { position: 0.85; color: "#00FFFFFF" } GradientStop { position: 1.0; color: appRoot.darkMode ? "#0DFFFFFF" : "#15FFFFFF" } }
            opacity: parent.edgeGlow && !parent.liquidActive ? 0.65 : 0.0
            z: -1
        }
    }

    // Quick download cards only; installed instances come from the core
    // (prism:… rows). A fresh install shows just these three cards.
    ListModel {
        id: instances
        ListElement { key: "fabric"; coverKey: "fabric"; label: "Fabric"; version: "Quick download"; hours: 0; launches: 0; installed: false; lastPlayed: false }
        ListElement { key: "neoforge"; coverKey: "neoforge"; label: "NeoForge"; version: "Quick download"; hours: 0; launches: 0; installed: false; lastPlayed: false }
        ListElement { key: "quilt"; coverKey: "quilt"; label: "Quilt"; version: "Quick download"; hours: 0; launches: 0; installed: false; lastPlayed: false }
    }
    property var sortedCards: {
        var a = []
        for (var i = 0; i < instances.count; i++) {
            var v = instances.get(i)
            // Installed cards are real core instances only (older builds kept
            // demo instances, which may still be in the saved records).
            if(v.installed && v.key.indexOf("prism:")!==0)continue
            if ((!v.installed && !quickCards) ||
                (searchText.length && (v.label + " " + v.version).toLowerCase().indexOf(searchText.toLowerCase()) < 0)) continue
            a.push({ key: v.key, label: v.label, version: v.version, hours: v.hours, launches: v.launches, installed: v.installed, coverKey: v.coverKey || v.key, background: (cardMetadata[v.key]||{}).background || "", backgroundPlacement: artworkPlacement(v.key) })
        }
        if (sortMode === "Name") a.sort(function(x,y) { return x.label.localeCompare(y.label) })
        else if (sortMode === "Smart") a.sort(function(x,y) { return y.hours - x.hours || y.launches - x.launches })
        else if (sortMode === "Custom") {
            var order = appRoot.customInstanceOrder
            a.sort(function(x,y) {
                var xi=order.indexOf(x.key), yi=order.indexOf(y.key)
                return (xi < 0 ? 100000 : xi) - (yi < 0 ? 100000 : yi)
            })
        }
        return a
    }
    function sidebarOrderIndex(key) {
        var list=sidebarInstalledCards()
        for(var i=0;i<list.length;i++)if(list[i].key===key)return i
        return -1
    }
    function updateInstanceDrop(sceneY) {
        instanceDragSceneY=sceneY
        var all=sidebarInstalledCards(), display=sidebarDisplayRows(), y=instanceRows.mapFromItem(null,0,sceneY).y, top=0
        instanceDropSlot=0
        for(var i=0;i<display.length;i++) {
            var row=display[i], height=row.type==="header"?28:35
            if(row.type==="instance" && y<top+height/2) {
                for(var j=0;j<all.length;j++)if(all[j].key===row.key){instanceDropSlot=j;return}
            }
            if(row.type==="instance")instanceDropSlot=sidebarOrderIndex(row.key)+1
            top+=height+3
        }
    }
    function commitInstanceDrop(key, slot) {
        var visibleRows = sidebarInstalledCards()
        if (!key || slot < 0 || !visibleRows.length) return
        var keys = sortedCards.map(function(card){return card.key})
        for (var i=0; i<instances.count; i++) {
            var id = instances.get(i).key
            if (keys.indexOf(id)<0) keys.push(id)
        }
        var after = slot >= visibleRows.length
        var target = visibleRows[after ? visibleRows.length-1 : slot].key
        customInstanceOrder = CanvasLayout.reorder(keys, key, target, after)
        sortMode="Custom"
    }
    function sidebarInstalledCards() {
        var a = []
        var source = appRoot.sortedCards
        for (var i = 0; i < source.length; ++i) {
            if (source[i].installed) a.push(source[i])
        }
        return a
    }
    readonly property var selectedDockCard: {
        var cards=sortedCards
        for(var i=0;i<cards.length;i++)if(cards[i].key===selectedId)return cards[i]
        return null
    }
    readonly property string selectedDockArtwork: selectedDockCard ? (selectedDockCard.background || defaultCardArt(selectedDockCard)) : ""
    readonly property bool selectedDockDefaultArtwork: !selectedDockCard || !selectedDockCard.background
    function syncDockArtwork() {
        macWindowMetrics.setDockArtwork(selectedDockArtwork,selectedDockDefaultArtwork)
        macWindowMetrics.setDockInfo(selectedLabel(),selectedVersion())
    }
    onSelectedDockArtworkChanged: syncDockArtwork()
    onSelectedDockDefaultArtworkChanged: syncDockArtwork()
    function selectedLabel() {
        for (var i=0;i<instances.count;i++) if (instances.get(i).key === selectedId) return instances.get(i).label
        return appRoot.tr("Select a version")
    }
    function selectedVersion() {
        for (var i=0;i<instances.count;i++) if (instances.get(i).key === selectedId) return instances.get(i).version
        return ""
    }
    function chooseCard(c,keepSelection) {
        if (!c || !c.key) return
        if(!keepSelection) selectedCardKeys=[c.key]
        selectedId = c.key
        statusMessage = c.installed ? appRoot.tr("Selected ") + c.label : appRoot.tr("Quick download: ") + c.label
    }
    function defaultCardArt(c) {
        var key=c.coverKey||"vanilla"
        if(["fabric","forge","neoforge","quilt"].indexOf(key)<0)key="vanilla"
        return Qt.resolvedUrl("assets/default-"+key+((key==="vanilla"||key==="forge")?".png":".svg")).toString()
    }
    function activateCard(c) {
        chooseCard(c)
        if (!c.installed) {
            var loaders = {fabric:"Fabric",forge:"Forge",neoforge:"NeoForge",quilt:"Quilt"}
            sidebarQuickLoader = loaders[c.coverKey] || "Vanilla"
            canvasQuickDownload.open()
        } else if(c.key.indexOf("prism:")===0)appRoot.startGame(c.key)
        else {statusMessage=appRoot.tr("Test card · Connect a real Prism instance to launch");prismConnection.open()}
    }
    function toggleSearch() {
        searchExpanded = !searchExpanded
        if (searchExpanded && !macWindowMetrics.nativeGlassDock) searchInput.forceActiveFocus()
        else searchInput.focus = false
    }
    property bool cardSizeEditing:false
    // Mouse wheel distance per angleDelta unit, as Flickable scrolls: the
    // system's lines per notch (Frontend.cpp) × 24 px over 120 units.
    readonly property real wheelPixelsPerDegree: Math.max(1, Qt.styleHints.wheelScrollLines) * 24 / 120
    property string customCardSizesJson:"{}"
    readonly property var customCardSizes:JSON.parse(customCardSizesJson)
    readonly property var cardSizeBounds:({minWidth:180,minHeight:126,maxWidth:640,maxHeight:480})
    property string groupCardSizesJson:"{}"
    readonly property var groupCardSizes:JSON.parse(groupCardSizesJson)
    function cardSizeGroupKey(key) {
        var groups=effectiveInstanceGroups
        for(var i=0;i<groups.length;i++)if(groups[i].keys.indexOf(key)>=0)return groupingMethod+":"+groups[i].id
        return groupingMethod+":ungrouped"
    }
    function cardSize(key,width,height) {
        return (hasInstanceGroups?groupCardSizes[cardSizeGroupKey(key)]:customCardSizes[key]) || {width:width,height:height}
    }
    function setCardSize(key,width,height) {
        var bounded=CanvasLayout.resizeRect({x:0,y:0,width:width,height:height},"bottomright",0,0,cardSizeBounds)
        if(hasInstanceGroups) {
            var groupSizes=JSON.parse(groupCardSizesJson);groupSizes[cardSizeGroupKey(key)]={width:bounded.width,height:bounded.height};groupCardSizesJson=JSON.stringify(groupSizes)
            return
        }
        var sizes=JSON.parse(customCardSizesJson);sizes[key]={width:bounded.width,height:bounded.height};customCardSizesJson=JSON.stringify(sizes)
        if(freeCanvasActive)setFreeRect(key,{width:bounded.width,height:bounded.height})
    }
    // Aspect presets (card menu): the card keeps about the same area, takes the
    // new proportions and stays within cardSizeBounds.
    function currentCardSize(key) {
        var rect=freeCanvasActive ? freeRects[key] : null
        if(rect && rect.width>0 && rect.height>0)return {width:rect.width,height:rect.height}
        return cardSize(key,240,168)
    }
    // A card of about `area` with these proportions, within cardSizeBounds.
    function cardSizeFor(area,ratio) {
        var b=cardSizeBounds,w=Math.sqrt(area*ratio),h=w/ratio
        var shrink=Math.min(1,b.maxWidth/w,b.maxHeight/h);w*=shrink;h*=shrink
        var grow=Math.max(1,b.minWidth/w,b.minHeight/h);w*=grow;h*=grow
        return {width:Math.round(Math.min(b.maxWidth,w)),height:Math.round(Math.min(b.maxHeight,h))}
    }
    function setCardAspect(keys,ratio) {
        keys.forEach(function(key) {
            var size=currentCardSize(key),next=cardSizeFor(size.width*size.height,ratio)
            setCardSize(key,next.width,next.height)
        })
    }
    // Size presets (areas of 180x126, 240x168 and 440x308) keep each card's
    // current proportions, so a chosen aspect ratio survives them.
    readonly property var cardSizePresets: ({Small:180*126,Medium:240*168,Large:440*308})
    function setCardPresetSize(keys,preset) {
        keys.forEach(function(key) {
            var size=currentCardSize(key),next=cardSizeFor(cardSizePresets[preset],size.width/size.height)
            setCardSize(key,next.width,next.height)
        })
    }
    function cardAspectIs(keys,ratio) {
        return keys.length>0 && keys.every(function(key){var s=currentCardSize(key);return Math.abs(s.width/s.height-ratio)<0.02})
    }
    function toggleCardSizeEditing() {
        cardSizeEditing=!cardSizeEditing
        statusMessage=cardSizeEditing?appRoot.tr("Resize: 180×126–640×480 · Esc to finish"):appRoot.tr("Card sizes saved")
    }
    function resizeCardFromEdge(key,start,edge,dx,dy) {
        var rect=CanvasLayout.resizeRect(start,edge,dx,dy,cardSizeBounds)
        setCardSize(key,rect.width,rect.height)
        if(freeCanvasActive)setFreeRect(key,rect)
    }
    Shortcut {sequence:"Escape";enabled:appRoot.cardSizeEditing;onActivated:{appRoot.cardSizeEditing=false;appRoot.statusMessage=appRoot.tr("Card sizes saved")}}
    property bool freeCanvasEnabled:false
    readonly property bool freeCanvasActive:freeCanvasEnabled && !hasInstanceGroups
    property string freeRectsJson:"{}"
    property string freeHiddenJson:"[]"
    property bool freeCardDragging:false
    property bool freeAvoidOverlap:false
    property int freeMinimumGap:24
    function freeLayer(key) {var r=freeRects[key];return r && r.layer!==undefined ? r.layer : 0}
    function reorderFreeLayers(keys,action) {
        var cards=canvasCards.slice().sort(function(a,b){return freeLayer(a.key)-freeLayer(b.key)})
        var selected=cards.filter(function(c){return keys.indexOf(c.key)>=0}),others=cards.filter(function(c){return keys.indexOf(c.key)<0})
        if(action==="front")cards=others.concat(selected)
        else if(action==="back")cards=selected.concat(others)
        else if(action==="up") {for(var i=cards.length-2;i>=0;i--)if(keys.indexOf(cards[i].key)>=0 && keys.indexOf(cards[i+1].key)<0){var c=cards[i];cards[i]=cards[i+1];cards[i+1]=c}}
        else {for(var i=1;i<cards.length;i++)if(keys.indexOf(cards[i].key)>=0 && keys.indexOf(cards[i-1].key)<0){var c=cards[i];cards[i]=cards[i-1];cards[i-1]=c}}
        var rects=JSON.parse(freeRectsJson),auto=CanvasLayout.spread(canvasCards.length,24);cards.forEach(function(c,i){if(!rects[c.key])rects[c.key]=auto[canvasCards.indexOf(c)];rects[c.key].layer=i});freeRectsJson=JSON.stringify(rects)
    }
    function normalizeFreeSpacing() {
        if(!freeAvoidOverlap || !freeCanvasActive)return
        var rects=JSON.parse(freeRectsJson),placed=[]
        var auto=CanvasLayout.spread(canvasCards.length,24)
        canvasCards.forEach(function(c,i){var r=rects[c.key] || auto[i];rects[c.key]=r;var safe=CanvasLayout.avoidOverlap(r,placed,freeMinimumGap);r.x=safe.x;r.y=safe.y;placed.push(r)})
        var encoded=JSON.stringify(rects);if(encoded!==freeRectsJson)freeRectsJson=encoded
    }
    onFreeCanvasActiveChanged:normalizeFreeSpacing()
    onFreeAvoidOverlapChanged:normalizeFreeSpacing()
    onFreeMinimumGapChanged:normalizeFreeSpacing()
    readonly property var freeRects:JSON.parse(freeRectsJson)
    readonly property var freeHidden:JSON.parse(freeHiddenJson)
    readonly property var canvasCards:sortedCards.filter(function(c){return freeHidden.indexOf(c.key)<0})
    function setFreeRect(key,patch) {
        var rects=JSON.parse(freeRectsJson),rect=rects[key] || {x:0,y:0,width:240,height:168}
        Object.keys(patch).forEach(function(k){rect[k]=patch[k]})
        if(freeAvoidOverlap && freeCanvasActive && !cardSizeEditing && (patch.x!==undefined || patch.y!==undefined || patch.width!==undefined || patch.height!==undefined)) {
            var obstacles=canvasCards.filter(function(c){return c.key!==key}).map(function(c){return rects[c.key]}).filter(function(r){return !!r})
            var safe=CanvasLayout.avoidOverlap(rect,obstacles,freeMinimumGap);rect.x=safe.x;rect.y=safe.y
        }
        rects[key]=rect;freeRectsJson=JSON.stringify(rects)
    }
    function setFreeVisible(key,show) {
        var hidden=freeHidden.filter(function(k){return k!==key});if(!show)hidden.push(key)
        freeHiddenJson=JSON.stringify(hidden);normalizeFreeSpacing()
    }
    function enableFreeCanvas() {
        var rects=JSON.parse(freeRectsJson),auto=CanvasLayout.spread(sortedCards.length,24)
        sortedCards.forEach(function(c,i){if(!rects[c.key])rects[c.key]=auto[i]})
        freeRectsJson=JSON.stringify(rects);freeCanvasEnabled=!freeCanvasEnabled;normalizeFreeSpacing()
    }
    Timer { id:canvasBoundsSettle;interval:0;onTriggered:appRoot.clampCanvas() }
    function clampCanvas() {
        if(hasInstanceGroups || freeCardDragging || !world || !canvas)return
        var bounds=world.currentPanLimits
        var x=Math.max(bounds.minX,Math.min(bounds.maxX,panX))
        var y=Math.max(bounds.minY,Math.min(bounds.maxY,panY))
        if(Math.abs(x-panX)>0.01)panX=x
        if(Math.abs(y-panY)>0.01)panY=y
    }
    Connections {
        target:appRoot
        function onPanXChanged(){appRoot.clampCanvas()}
        function onPanYChanged(){appRoot.clampCanvas()}
        function onZoomChanged(){canvasBoundsSettle.restart()}
        function onWidthChanged(){canvasBoundsSettle.restart()}
        function onHeightChanged(){canvasBoundsSettle.restart()}
        function onSortedCardsChanged(){appRoot.normalizeFreeSpacing();canvasBoundsSettle.restart()}
        function onCanvasCardsChanged(){canvasBoundsSettle.restart()}
        function onSidebarProgressChanged(){canvasBoundsSettle.restart()}
        function onHasInstanceGroupsChanged(){canvasBoundsSettle.restart()}
    }
    function resetCanvas() { panX=0; panY=0; zoom=1;canvasBoundsSettle.restart() }
    function changeZoom(factor) {
        zoom = Math.max(0.55, Math.min(1.65, zoom * factor))
    }
    // Keyboard navigation: zoom in/out and return to the original view.
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; enabled: appRoot.activePage === "Launch"; onActivated: appRoot.changeZoom(1.12) }
    Shortcut { sequence: "Ctrl+-"; enabled: appRoot.activePage === "Launch"; onActivated: appRoot.changeZoom(1 / 1.12) }
    Shortcut { sequence: "Ctrl+0"; enabled: appRoot.activePage === "Launch"; onActivated: appRoot.resetCanvas() }
    // Direct trackpad pinching must feel immediate; the slider animates its own thumb.


    component CanvasCard: GlassPane {
        id:instanceCard
        objectName:"canvasNativeCard"
        opacity:macWindowMetrics.nativeGlassDock?0:1
        materialRole:"quickCard"
        // Only quick-download cards are glass. Installed cards are opaque: custom
        // artwork covers the card, default (loader) artwork sits on a solid fill
        // tinted with its colour.
        readonly property bool defaultArtwork:modelData.installed && !modelData.background
        readonly property color artworkTint:defaultArtwork ? macWindowMetrics.artworkTint(appRoot.defaultCardArt(modelData)) || "#80466E41" : "transparent"
        // An opaque tint is the artwork's own background (Forge): used as is;
        // otherwise the tint colours a dark base.
        readonly property color artworkFill: artworkTint.a > 0.99 ? artworkTint : Qt.tint("#1F1F1F", Qt.rgba(artworkTint.r, artworkTint.g, artworkTint.b, 0.45))
        // A custom picture without a base colour (Background › Colour behind
        // the picture › Liquid Glass) sits on the quick cards' glass.
        // Behind a built-in loader icon (Background › Icon background):
        // "" automatic tint, "transparent", Liquid Glass ("glass", tinted with
        // the theme colour "glass-accent" or the icon's colour "glass-icon")
        // or a chosen colour.
        readonly property var placementData: modelData.backgroundPlacement || ({})
        readonly property string iconFill: defaultArtwork ? (placementData.iconFill || "") : ""
        readonly property bool iconGlass: iconFill === "glass"
        // Transparent or glass: no base of its own, so no dark footer shade,
        // no colour glow, and captions in the theme's text colours.
        readonly property bool bareIcon: iconFill === "transparent" || iconGlass
        readonly property color iconBase: iconFill === "" ? artworkFill : bareIcon ? "transparent" : iconFill
        // Tint of a Liquid Glass base: the theme colour or the icon's/picture's.
        readonly property string glassTintMode: glassBase ? (placementData.glassTint || "") : ""
        readonly property color pictureTint: glassTintMode === "artwork" && !defaultArtwork && !!modelData.background
                                             ? (macWindowMetrics.artworkTint(modelData.background) || appRoot.accent) : "transparent"
        readonly property color tintSource: glassTintMode === "accent" ? appRoot.accent : defaultArtwork ? artworkTint : pictureTint
        readonly property real tintStrength: placementData.tintOpacity >= 0 ? placementData.tintOpacity : appRoot.cardGlassTintOpacity
        glassTint: glassTintMode ? Qt.rgba(tintSource.r, tintSource.g, tintSource.b, tintStrength) : "transparent"
        readonly property bool glassBase:modelData.installed && ((!!modelData.background && !!modelData.backgroundPlacement && modelData.backgroundPlacement.color === "glass") || iconGlass)
        liquidGlass:!modelData.installed || glassBase
        surfaceLift:modelData.installed && !glassBase ? 0 : 0.03
        rimColor:modelData.installed && !glassBase ? "transparent" : appRoot.hairline
        // Installed cards draw everything inside one continuous-corner shape
        // (the content clip and the selection ring below): a Rectangle fill or
        // border here has circular corners that do not line up with it.
        color:macWindowMetrics.nativeGlassDock || (modelData.installed && !glassBase) ? "transparent" : appRoot.glassSoft
        edgeGlow:false
        border.width:0
        // The ring is an accent fill under the inset content: a glass card has
        // no opaque content to cover it, so it shows selection like the quick
        // cards (tinted glass).
        readonly property real contentInset: modelData.installed && !glassBase && selectedGlass ? 3 : 0
        // Settings › Layout › Card glass: a frostier centre with a clear rim,
        // dimming over bright backdrops and a legible caption area.
        cardStyle: Qt.vector4d(appRoot.cardGlassFrost, appRoot.cardGlassDimming, appRoot.cardGlassCaption, appRoot.cardGlassBlur)
        // Selected, the card lifts a little on a spring (Apple's selection
        // feedback) and, with Settings › Layout › Selection glow, glows in
        // the accent colour.
        property real lift: selectedGlass && !glassTuning.reducedMotion ? 1 : 0
        Behavior on lift { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.002 } }
        scale: 1 + appRoot.selectionLift * lift
        RectangularShadow {
            // Beneath every card, like the artwork glow.
            parent: instanceCard.parent
            z: -999
            visible: appRoot.selectionGlow && instanceCard.selectedGlass && instanceCard.visible && !macWindowMetrics.nativeGlassDock
            x: instanceCard.x; y: instanceCard.y; width: instanceCard.width; height: instanceCard.height
            scale: instanceCard.scale
            radius: instanceCard.radius
            blur: 30; spread: 2
            color: Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, (appRoot.darkMode ? 0.6 : 0.45) * Math.max(0.35, instanceCard.lift))
            opacity: instanceCard.opacity
        }
        required property var modelData
        property bool featured:false
        property bool resizeHovered:false
        // Footer shade starts just above the caption.
        readonly property real footerFadeStart:Math.max(0,Math.min(1,(cardCaption.y+4)/height))
        width:240;height:168;radius:appRoot.cardRadius
        selectedGlass:appRoot.selectedCardKeys.indexOf(modelData.key)>=0
        // Ambient glow (installed cards only): a heavily blurred copy of the
        // card's artwork underneath it, so its colours bleed softly past the
        // edges, like album art in Apple Music. The copy is its own hidden
        // item: using the card's content layer as the effect source took that
        // layer over and broke the card's clip and position.
        readonly property bool glowing: modelData.installed && !macWindowMetrics.nativeGlassDock && appRoot.cardGlow > 0.01 && !bareIcon
        // The blur is confined to the effect item's own rectangle, so the
        // canvas is glowMargin larger than the card on every side with the
        // colour only in the middle: the halo fades out completely inside it.
        // (Equal to the card, the glow hid under it; 10 pt larger, it was cut
        // off 10 pt out, which read as an outline.)
        readonly property real glowMargin: 48
        Item {
            id: glowSource
            x: -instanceCard.glowMargin; y: -instanceCard.glowMargin
            width: instanceCard.width + 2 * instanceCard.glowMargin; height: instanceCard.height + 2 * instanceCard.glowMargin
            visible: false
            layer.enabled: instanceCard.glowing
            Item {
                anchors.fill: parent; anchors.margins: instanceCard.glowMargin
                Rectangle {
                    anchors.fill: parent; radius: instanceCard.radius
                    color: !instanceCard.defaultArtwork ? "transparent" : instanceCard.iconFill !== "" ? instanceCard.iconBase
                           : instanceCard.artworkTint.a > 0.99 ? instanceCard.artworkTint
                           : Qt.tint("#1F1F1F", Qt.rgba(instanceCard.artworkTint.r, instanceCard.artworkTint.g, instanceCard.artworkTint.b, 0.6))
                }
                Image {
                    readonly property real iconSize: Math.min(parent.width, parent.height) * 0.55
                    x: (parent.width - iconSize) / 2; y: 10
                    width: iconSize; height: iconSize
                    visible: instanceCard.defaultArtwork
                    source: instanceCard.glowing && instanceCard.defaultArtwork ? appRoot.defaultCardArt(instanceCard.modelData) : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                // Custom pictures glow as placed on the card.
                CardArtwork {
                    anchors.fill: parent
                    visible: !instanceCard.defaultArtwork
                    source: instanceCard.glowing && !instanceCard.defaultArtwork ? instanceCard.modelData.background : ""
                    placement: instanceCard.modelData.backgroundPlacement || ({})
                    decodeSize: Qt.size(96, 96)
                }
            }
        }
        MultiEffect {
            // Drawn in the card's container beneath every card: as a child it
            // painted over the previous card (z only orders within one card).
            parent: instanceCard.parent
            z: -1000
            visible: instanceCard.glowing && instanceCard.visible
            // Follows the card's position and scale.
            x: instanceCard.x - instanceCard.glowMargin; y: instanceCard.y - instanceCard.glowMargin
            width: glowSource.width; height: glowSource.height
            scale: instanceCard.scale
            source: glowSource
            // Reach (about glowMargin) also fits the grouped rows' glowPad.
            blurEnabled: true; blur: 1.0; blurMax: 40; blurMultiplier: 0.2
            autoPaddingEnabled: false
            saturation: 0.4; brightness: 0.12
            opacity: Math.min(1, instanceCard.opacity * appRoot.cardGlow * (appRoot.darkMode ? 1.15 : 0.7))
        }
        // Selection ring: the card's continuous shape in the accent, showing
        // around the inset content.
        Item {
            anchors.fill:parent
            visible:instanceCard.contentInset > 0
            layer.enabled:visible; layer.smooth:true
            layer.effect:ContinuousClip { radius: instanceCard.radius }
            Rectangle { anchors.fill:parent; color:appRoot.accent }
        }
        Item {
            id: cardContent
            anchors.fill:parent;anchors.margins:instanceCard.contentInset
            layer.enabled:true; layer.smooth:true
            layer.textureSize: Qt.size(Math.ceil(width * appRoot.glassPixelRatio * Math.max(1, appRoot.zoom)), Math.ceil(height * appRoot.glassPixelRatio * Math.max(1, appRoot.zoom)))
            layer.effect:ContinuousClip { radius: Math.max(0, instanceCard.radius-instanceCard.contentInset) }
            // Opaque base for default (loader) artwork, tinted with its colour.
            Rectangle {
                anchors.fill:parent;visible:instanceCard.defaultArtwork
                color:instanceCard.iconBase
            }
            // The blurred footer samples a hidden copy of the placed picture:
            // given the visible item, MultiEffect hid it and drew only itself.
            Item {
                id:cardArtworkBlurSource;anchors.fill:parent;visible:false
                layer.enabled:instanceCard.modelData.installed && !instanceCard.defaultArtwork
                CardArtwork {
                    anchors.fill:parent
                    source:parent.layer.enabled ? instanceCard.modelData.background : ""
                    placement:instanceCard.modelData.backgroundPlacement || ({})
                }
            }
            Item {
                id:cardArtwork;anchors.fill:parent;visible:instanceCard.modelData.installed
                Image {
                    visible:instanceCard.defaultArtwork
                    readonly property real iconSize:Math.min(parent.width,parent.height)*0.55
                    x:(parent.width-iconSize)/2; y:10
                    width:iconSize; height:iconSize
                    source:cardArtwork.visible && instanceCard.defaultArtwork ? appRoot.defaultCardArt(instanceCard.modelData) : ""
                    sourceSize:Qt.size(Math.ceil(iconSize*2),Math.ceil(iconSize*2))
                    fillMode:Image.PreserveAspectFit
                }
                CardArtwork {
                    anchors.fill:parent;visible:!instanceCard.defaultArtwork
                    source:cardArtwork.visible && !instanceCard.defaultArtwork ? instanceCard.modelData.background : ""
                    placement:instanceCard.modelData.backgroundPlacement || ({})
                }
            }
            Rectangle {
                id:bottomFadeMask;width:parent.width;height:parent.height
                visible:false;layer.enabled:true
                gradient:Gradient {
                    GradientStop { position:0;color:"transparent" }
                    GradientStop { position:instanceCard.footerFadeStart;color:"transparent" }
                    GradientStop { position:instanceCard.footerFadeStart+(1-instanceCard.footerFadeStart)*0.45;color:"white" }
                    GradientStop { position:1;color:"white" }
                }
            }
            MultiEffect {
                // The blurred footer copies full-bleed covers only; a centred
                // default icon would be stretched across the card.
                anchors.fill:parent;visible:instanceCard.modelData.installed && !instanceCard.defaultArtwork
                source:cardArtworkBlurSource;autoPaddingEnabled:false;blurEnabled:true;blur:0.75;blurMax:40
                maskEnabled:true;maskSource:bottomFadeMask
                maskThresholdMin:0.5;maskSpreadAtMin:1.0
            }
            Rectangle {
                anchors.fill:parent;visible:instanceCard.modelData.installed && !instanceCard.bareIcon
                gradient:Gradient {
                    GradientStop { position:0;color:"transparent" }
                    GradientStop { position:instanceCard.footerFadeStart;color:"transparent" }
                    // Strength: Settings › Layout › Caption shade.
                    GradientStop { position:instanceCard.footerFadeStart+(1-instanceCard.footerFadeStart)*0.45;color:Qt.rgba(0,0,0,Math.min(1,0.45*appRoot.cardCaptionShade)) }
                    GradientStop { position:1;color:Qt.rgba(0,0,0,Math.min(1,0.7*appRoot.cardCaptionShade)) }
                }
            }
        }
        // Glass cards (no opaque content to inset): an accent ring on the
        // card's own continuous contour, as wide as the opaque cards' ring.
        ShaderEffect {
            anchors.fill:parent
            visible:instanceCard.selectedGlass && (!modelData.installed || instanceCard.glassBase) && !macWindowMetrics.nativeGlassDock
            property real radius:instanceCard.radius
            property vector2d surfaceSize:Qt.vector2d(width,height)
            property real ringWidth:3
            property color ringColor:appRoot.accent
            fragmentShader:"qrc:/pgshaders/continuousring.frag.qsb"
        }
        SymbolImage { id:quickCardSymbol;visible:!modelData.installed;x:20;y:16;width:28;height:28;symbol:visible ? "arrow.down" : "";tint:appRoot.accent }
        GlassText { visible:!modelData.installed && quickCardSymbol.status!==Image.Ready;x:20;y:16;text:"↓";color:appRoot.accent;font.pixelSize:28 }
        Column {
            id:cardCaption
            anchors.left:parent.left;anchors.leftMargin:20
            anchors.bottom:parent.bottom;anchors.bottomMargin:18
            // The name has the whole width (the play time shares the version's
            // line only); it shrinks to 14 pt before it is cut short, and the
            // full name shows on hover.
            width:Math.max(60,parent.width-40);spacing:5
            GlassText {
                width:parent.width;text:modelData.label;font.bold:true;elide:Text.ElideRight
                font.pixelSize:featured?22:18;fontSizeMode:Text.HorizontalFit;minimumPixelSize:14
                color:!modelData.installed || instanceCard.bareIcon?appRoot.ink:"white"
                HoverHandler { id:cardNameHover }
                ToolTip.visible:cardNameHover.hovered && truncated
                ToolTip.text:modelData.label
                ToolTip.delay:500
            }
            GlassText {
                width:Math.max(0,parent.width-(modelData.installed?cardStats.implicitWidth+8:0))
                text:appRoot.tr(modelData.version);font.pixelSize:12;elide:Text.ElideRight
                color:!modelData.installed || instanceCard.bareIcon?appRoot.muted:"#DDE6ED"
            }
        }
        GlassText {
            id:cardStats
            visible:modelData.installed
            anchors.right:parent.right;anchors.rightMargin:16
            anchors.bottom:parent.bottom;anchors.bottomMargin:18
            width:Math.min(100,implicitWidth);horizontalAlignment:Text.AlignRight;elide:Text.ElideRight
            text:Number(Number(modelData.hours || 0).toFixed(2))+appRoot.tr(" h · ")+modelData.launches+appRoot.tr(" runs")
            color:instanceCard.bareIcon?appRoot.muted:"#DDE6ED";font.pixelSize:10
        }
        DragHandler {
            target:null;enabled:appRoot.freeCanvasActive && !appRoot.cardSizeEditing;acceptedButtons:Qt.LeftButton
            property real startX:0;property real startY:0
            onActiveChanged:{ if(active){startX=instanceCard.x;startY=instanceCard.y;appRoot.freeCardDragging=true}else {appRoot.freeCardDragging=false;canvasBoundsSettle.restart()} }
            onTranslationChanged:if(active)appRoot.setFreeRect(instanceCard.modelData.key,{x:startX+translation.x/appRoot.zoom,y:startY+translation.y/appRoot.zoom})
        }
        Repeater {
            model:appRoot.cardSizeEditing?(appRoot.freeCanvasActive?["top","bottom","left","right","topleft","topright","bottomleft","bottomright"]:["right","bottom","bottomright"]):[]
            delegate:MouseArea {
                required property string modelData
                objectName:"cardResizeHandle-"+instanceCard.modelData.key+"-"+modelData
                readonly property bool horizontal:modelData==="top" || modelData==="bottom"
                readonly property bool vertical:modelData==="left" || modelData==="right"
                readonly property real handle:12
                x:modelData.indexOf("left")>=0?0:modelData.indexOf("right")>=0?instanceCard.width-handle:handle
                y:modelData.indexOf("top")>=0?0:modelData.indexOf("bottom")>=0?instanceCard.height-handle:handle
                width:horizontal?Math.max(handle,instanceCard.width-handle*2):handle
                height:vertical?Math.max(handle,instanceCard.height-handle*2):handle
                z:20;acceptedButtons:Qt.LeftButton;hoverEnabled:true;preventStealing:true
                cursorShape:horizontal?Qt.SizeVerCursor:vertical?Qt.SizeHorCursor:(modelData==="topleft" || modelData==="bottomright")?Qt.SizeFDiagCursor:Qt.SizeBDiagCursor
                property var startRect:({})
                property point startScene:Qt.point(0,0)
                property real sceneScale:1
                onEntered:instanceCard.resizeHovered=true
                onExited:if(!pressed)instanceCard.resizeHovered=false
                onPressed:function(mouse) {
                    appRoot.selectCanvasCard(instanceCard.modelData,Qt.NoModifier)
                    startRect={x:instanceCard.x,y:instanceCard.y,width:instanceCard.width,height:instanceCard.height}
                    startScene=mapToItem(appRoot.contentItem,mouse.x,mouse.y)
                    var p=instanceCard.mapToItem(appRoot.contentItem,0,0),q=instanceCard.mapToItem(appRoot.contentItem,instanceCard.width,0)
                    sceneScale=Math.max(0.01,Math.abs(q.x-p.x)/instanceCard.width)
                    appRoot.freeCardDragging=true
                }
                onPositionChanged:function(mouse) {
                    if(!pressed)return
                    var point=mapToItem(appRoot.contentItem,mouse.x,mouse.y)
                    appRoot.resizeCardFromEdge(instanceCard.modelData.key,startRect,modelData,(point.x-startScene.x)/sceneScale,(point.y-startScene.y)/sceneScale)
                }
                onReleased:{appRoot.freeCardDragging=false;instanceCard.resizeHovered=containsMouse;appRoot.normalizeFreeSpacing();canvasBoundsSettle.restart()}
                onCanceled:{appRoot.freeCardDragging=false;instanceCard.resizeHovered=false;canvasBoundsSettle.restart()}
            }
        }
        // Resize mode: a white arc inside the bottom-right corner, following
        // the card's corner (the edges stay draggable without drawn strips).
        Canvas {
            visible:appRoot.cardSizeEditing && !macWindowMetrics.nativeGlassDock
            readonly property real cornerRadius:instanceCard.radius
            width:cornerRadius; height:cornerRadius
            x:instanceCard.width-width; y:instanceCard.height-height
            z:19
            opacity:instanceCard.resizeHovered ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration:120 } }
            onCornerRadiusChanged:requestPaint()
            onVisibleChanged:if(visible)requestPaint()
            onPaint: {
                var ctx=getContext("2d"),r=Math.max(4,cornerRadius-7)
                ctx.reset()
                ctx.lineCap="round"
                ctx.beginPath()
                ctx.arc(0,0,r,Math.PI*0.1,Math.PI*0.4,false)
                // A soft dark edge keeps it legible on pale artwork.
                ctx.lineWidth=5;ctx.strokeStyle="rgba(0,0,0,0.25)";ctx.stroke()
                ctx.lineWidth=3;ctx.strokeStyle="white";ctx.stroke()
            }
        }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            if(mouse.button===Qt.RightButton) {
                                var point=mapToItem(appRoot.contentItem,mouse.x,mouse.y)
                                appRoot.openCardMenu(modelData,point.x,point.y)
                            } else appRoot.selectCanvasCard(modelData,mouse.modifiers)
                        }
                        onDoubleClicked: function(mouse) {
                            if(!appRoot.cardSizeEditing && mouse.button===Qt.LeftButton && !(mouse.modifiers & (Qt.ControlModifier|Qt.MetaModifier|Qt.ShiftModifier)))appRoot.activateCard(modelData)
                        }
                    }
    }

    // Background, canvas and pages. Floating chrome (navigation, sidebar,
    // dock, search, popups) stays outside, so Windows Liquid Glass chrome can
    // sample this whole item without capturing itself. Stacking is unchanged:
    // pages use z 12 here, all chrome uses z 40 and above.
    Item {
        id: contentScene
        anchors.fill: parent
    }

    // Composite background and cards into one offscreen scene for sidebar blur.
    // The sidebar itself is outside this scene to avoid recursive capture.
    Item {
        id: sceneViewport
        parent: contentScene
        y: -appRoot.contentItem.y
        x: macWindowMetrics.nativeSidebar ? appRoot.contentLeft : 0
        width: appRoot.width - x
        height: parent.height + appRoot.contentItem.y
        clip: true
        Item {
        id: sceneLayer
        objectName: "sidebarSceneSource"
        x: -sceneViewport.x
        width: appRoot.width
        height: sceneViewport.height
    // Wallpaper only: the Liquid Glass source for cards and page surfaces.
    Item {
        id: backgroundLayer
        anchors.fill: parent
    Rectangle {
        id: backgroundBackdrop
        anchors.fill: parent
        color: appRoot.backgroundMode==="Custom color"?appRoot.customColorStart:appRoot.backgroundColor
        visible: !macWindowMetrics.nativeSidebar
    }
    Canvas {
        id:customGradientCanvas
        anchors.fill:parent;visible:appRoot.backgroundMode==="Custom color" && appRoot.customGradient && !macWindowMetrics.nativeSidebar
        onWidthChanged:requestPaint();onHeightChanged:requestPaint()
        Connections {target:appRoot
            function onCustomColorStartChanged(){customGradientCanvas.requestPaint()}
            function onCustomColorEndChanged(){customGradientCanvas.requestPaint()}
            function onCustomGradientAngleChanged(){customGradientCanvas.requestPaint()}
            function onGradientStopsJsonChanged(){customGradientCanvas.requestPaint()}
        }
        onPaint:{var c=getContext("2d"),a=appRoot.customGradientAngle*Math.PI/180,span=(Math.abs(width*Math.cos(a))+Math.abs(height*Math.sin(a)))/2;var g=c.createLinearGradient(width/2-Math.cos(a)*span,height/2-Math.sin(a)*span,width/2+Math.cos(a)*span,height/2+Math.sin(a)*span);var stops=appRoot.gradientStops.slice().sort(function(a,b){return a.position-b.position});for(var i=0;i<stops.length;i++)g.addColorStop(stops[i].position,stops[i].color);c.fillStyle=g;c.fillRect(0,0,width,height)}
    }
    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: appRoot.backgroundMode === "Custom" ? appRoot.backgroundImage : ""
        visible: appRoot.backgroundMode === "Custom" && !macWindowMetrics.nativeSidebar
        asynchronous: true
        clip: true
        fillMode: appRoot.backgroundPlacement === "Stretch" ? Image.Stretch
                  : appRoot.backgroundPlacement === "Fit" ? Image.PreserveAspectFit
                  : appRoot.backgroundPlacement === "Center" ? Image.Pad
                  : appRoot.backgroundPlacement === "Tile" ? Image.Tile : Image.PreserveAspectCrop
    }
    Image {
        id: themeCatArtwork
        objectName: "themeCatArtwork"
        anchors.right: parent.right; anchors.bottom: parent.bottom
        width: Math.min(460,appRoot.width*0.42); height: Math.min(540,appRoot.height*0.70)
        horizontalAlignment: Image.AlignRight; verticalAlignment: Image.AlignBottom
        fillMode: Image.PreserveAspectFit
        source: appRoot.themeCat.length ? themeStore.catImage(appRoot.themeCat) : ""
        visible: appRoot.activePage === "Launch" && appRoot.themeCat.length > 0
        asynchronous: true
    }
    } // backgroundLayer

    // Full-window canvas: the floating controls never divide the background.
    Item {
        id: canvas
        anchors.fill: parent
        clip: true
        visible: appRoot.activePage === "Launch"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: appRoot.freeCanvasActive ? Qt.LeftButton|Qt.RightButton : Qt.RightButton
            property point lastPoint:Qt.point(0,0)
            onPressed:function(mouse){lastPoint=Qt.point(mouse.x,mouse.y)}
            onPositionChanged:function(mouse){if(appRoot.freeCanvasActive && pressed && (pressedButtons & Qt.LeftButton)){appRoot.panX+=mouse.x-lastPoint.x;appRoot.panY+=mouse.y-lastPoint.y;lastPoint=Qt.point(mouse.x,mouse.y)}}
            onClicked: function(mouse) { if(mouse.button!==Qt.RightButton)return;var point=mapToItem(appRoot.contentItem,mouse.x,mouse.y);canvasAppearanceMenu.popup(point.x,point.y) }
        }
        Item {
            id: world
            visible: !appRoot.hasInstanceGroups
            readonly property var cardPositions: {
                if(appRoot.hasInstanceGroups)return []
                var auto=CanvasLayout.spread(appRoot.canvasCards.length,24,appRoot.canvasCards.map(function(c){return appRoot.customCardSizes[c.key] || null}))
                return appRoot.canvasCards.map(function(c,i){
                    if(!appRoot.freeCanvasActive)return auto[i]
                    var rect=Object.assign({},appRoot.freeRects[c.key] || auto[i]),size=appRoot.customCardSizes[c.key]
                    if(size){rect.width=size.width;rect.height=size.height}
                    return rect
                })
            }
            readonly property var currentPanLimits: CanvasLayout.panLimits(cardPositions,appRoot.zoom,originX,originY,
                {left:(macWindowMetrics.nativeSidebar?24:appRoot.contentLeft+24)-80,
                 top:(appRoot.sidebarProgress>0.5?appRoot.sidebarPageWindowTop:appRoot.compactPageTop)-80,
                 right:canvas.width+56,bottom:canvas.height-32},{x:32,y:180})
            onCurrentPanLimitsChanged:canvasBoundsSettle.restart()
            readonly property real originX:(canvas.width+appRoot.contentLeft)/2
            x:originX+appRoot.panX
            readonly property real layoutTop: appRoot.canvasCards.length ? Math.min.apply(null,CanvasLayout.spread(appRoot.canvasCards.length,24).map(function(rect){return rect.y})) : 0
            readonly property real originY:(canvas.height/2-appRoot.compactContentRise)*(1-appRoot.sidebarProgress)+(appRoot.sidebarPageWindowTop-layoutTop*appRoot.zoom)*appRoot.sidebarProgress
            y:originY+appRoot.panY
            scale: appRoot.zoom
            Repeater {
                model: appRoot.hasInstanceGroups ? [] : appRoot.canvasCards
                delegate: CanvasCard {
                    required property int index
                    featured: index === 0
                    readonly property var placement: world.cardPositions[index] || ({x:0,y:0,width:240,height:168})
                    x: placement.x; y: placement.y; width: placement.width; height: placement.height
                    z:appRoot.freeCanvasActive?appRoot.freeLayer(modelData.key):0
                }
            }
        }
        Flickable {
            id: groupedPage
            visible: appRoot.hasInstanceGroups
            // Clip only at the window edge. Insets belong to scrollable content.
            x: 0; y: 0
            width: canvas.width
            height: canvas.height
            readonly property real contentInsetLeft: appRoot.contentLeft+28
            readonly property real contentInsetTop: appRoot.compactPageTop * (1-appRoot.sidebarProgress) + appRoot.sidebarPageWindowTop*appRoot.sidebarProgress
            readonly property real contentInsetBottom: bottomDock.height+44
            contentWidth: width
            contentHeight: contentInsetTop+groupedColumn.implicitHeight+contentInsetBottom
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive:!appRoot.freeCardDragging
            clip: true
            ScrollBar.vertical: ScrollBar { }
            Connections {
                target: appRoot
                function onGroupingMethodChanged() { groupedPage.contentY=0 }
                function onGroupedLayoutEnabledChanged() { groupedPage.contentY=0 }
            }
            Column {
                id: groupedColumn
                y: groupedPage.contentInsetTop
                width: groupedPage.width
                spacing: 36
                Repeater {
                    id: groupedSections
                    model: appRoot.hasInstanceGroups ? CanvasLayout.grouped(appRoot.canvasCards,appRoot.effectiveInstanceGroups,appRoot.groupingMethod).sections : []
                    delegate: Item {
                        id: groupSection
                        required property var modelData
                        readonly property var cards: appRoot.canvasCards.filter(function(card) {
                            if (modelData.id === "ungrouped")
                                return !appRoot.effectiveInstanceGroups.some(function(g){return g.keys.indexOf(card.key)>=0})
                            var groups=appRoot.effectiveInstanceGroups.filter(function(g){return g.id===modelData.id})
                            return groups.length && groups[0].keys.indexOf(card.key)>=0
                        })
                        property alias rowViewport: groupRow
                        readonly property bool frequent: appRoot.groupingMethod === "Smart" && modelData.name === "Frequently played"
                        readonly property real cardWidth: modelData.cardWidth
                        readonly property real cardHeight: modelData.cardHeight
                        readonly property var rowMetrics:CanvasLayout.shelfSizes(cards.map(function(card){return appRoot.cardSize(card.key,cardWidth,cardHeight)}),24)
                        width: groupedColumn.width
                        height: cards.length ? rowMetrics.height+40 : 76
                        BackdropText { height:implicitHeight+(42-implicitHeight)*appRoot.sidebarProgress; verticalAlignment:Text.AlignVCenter; x: groupedPage.contentInsetLeft; text: appRoot.tr(groupSection.modelData.name); color: appRoot.ink; font.pixelSize: 22; font.bold: true }
                        GlassText {
                            x: groupedPage.contentInsetLeft; y: 40; visible: !groupSection.cards.length
                            text: appRoot.tr("Right-click a card to add it to this group"); color: appRoot.muted; font.pixelSize: 12
                        }
                        Item {
                            // Beneath the section titles, which the cards' glow
                            // (extending above the row) would otherwise dim.
                            z: -1
                            y: 40; width: parent.width; height: groupSection.rowMetrics.height
                            visible: groupSection.cards.length > 0
                            Flickable {
                                id: groupRow
                                // Room above and below the cards for their glow, which
                                // the row's horizontal clip would otherwise cut flat.
                                readonly property real glowPad: 64
                                anchors.fill: parent; anchors.topMargin: -glowPad; anchors.bottomMargin: -glowPad
                                contentWidth: groupedPage.contentInsetLeft+groupSection.rowMetrics.width+28
                                interactive:!appRoot.freeCardDragging
                                contentHeight: height
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                Repeater {
                                    model: groupSection.cards
                                    delegate: CanvasCard {
                                        required property int index
                                        readonly property var sizePlacement:groupSection.rowMetrics.positions[index] || ({x:0,width:240,height:168})
                                        x: groupedPage.contentInsetLeft+sizePlacement.x; y: groupRow.glowPad
                                        featured: groupSection.frequent
                                        width:sizePlacement.width;height:sizePlacement.height
                                    }
                                }
                            }

                        }
                    }
                }
            }
        }
        MouseArea {
            anchors.fill: groupedPage
            visible: appRoot.hasInstanceGroups
            acceptedButtons: Qt.NoButton
            onWheel: function(event) {
                var pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
                var dx = pixels ? event.pixelDelta.x : event.angleDelta.x * appRoot.wheelPixelsPerDegree
                var dy = pixels ? event.pixelDelta.y : event.angleDelta.y * appRoot.wheelPixelsPerDegree
                var route = CanvasLayout.routeScroll(dx,dy,!!(event.modifiers & Qt.ShiftModifier))
                if(route.axis === "y") {
                    groupedPage.cancelFlick()
                    groupedPage.contentY=CanvasLayout.scrollPosition(groupedPage.contentY,route.delta,groupedPage.contentHeight,groupedPage.height)
                } else {
                    for(var i=0;i<groupedSections.count;i++) {
                        var section=groupedSections.itemAt(i)
                        if(!section)continue
                        var row=section.rowViewport
                        var point=row.mapToItem(groupedPage,0,0)
                        // The row extends glowPad above and below its cards.
                        if(event.y>=point.y+row.glowPad && event.y<point.y+row.height-row.glowPad) {
                            row.cancelFlick()
                            row.contentX=CanvasLayout.scrollPosition(row.contentX,route.delta,row.contentWidth,row.width)
                            break
                        }
                    }
                }
                event.accepted=true
            }
        }
        PinchHandler {
            id: canvasPinch
            target: null
            enabled: !appRoot.hasInstanceGroups && appRoot.activePage === "Launch" && !appRoot.instancePickerOpen
                     && !sidebarHover.hovered && !navHover.hovered
                     && !searchHover.hovered && !bottomHover.hovered
            property real lastFactor: 1.0
            onActiveChanged: { lastFactor = 1.0 }
            onScaleChanged: {
                if (!active) return
                var factor = scale / Math.max(0.0001, lastFactor)
                appRoot.changeZoom(factor)
                lastFactor = scale
            }
        }
        DragHandler {
            id: canvasDrag
            target: null
            acceptedButtons: Qt.LeftButton
            // Overlay hover regions disable panning before the gesture begins.
            enabled: !appRoot.hasInstanceGroups && !appRoot.freeCanvasActive && appRoot.activePage === "Launch" && !appRoot.instancePickerOpen && !windowStripHover.hovered && !canvasPinch.active && !sidebarHover.hovered && !navHover.hovered && !searchHover.hovered && !statusHover.hovered && !bottomHover.hovered
            onTranslationChanged: {
                appRoot.panX += translation.x - previousTranslation.x
                appRoot.panY += translation.y - previousTranslation.y
                previousTranslation = translation
            }
            property point previousTranslation: Qt.point(0,0)
            onActiveChanged: if(!active)previousTranslation=Qt.point(0,0)
        }
        WheelHandler {
            target: null
            enabled: !appRoot.hasInstanceGroups && appRoot.activePage === "Launch" && !appRoot.instancePickerOpen && !canvasPinch.active
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                if (appRoot.hasInstanceGroups || appRoot.activePage !== "Launch" || appRoot.instancePickerOpen || sidebarHover.hovered || navHover.hovered || searchHover.hovered || bottomHover.hovered) return
                if (event.modifiers & Qt.ControlModifier) {
                    var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y
                    if (dy !== 0) appRoot.changeZoom(Math.exp(dy * 0.0015))
                } else {
                    appRoot.panX += event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x * appRoot.wheelPixelsPerDegree
                    appRoot.panY += event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y * appRoot.wheelPixelsPerDegree
                }
            }
        }
    }

    } // sceneLayer
    } // sceneViewport

    function syncCanvasCards() {
        if(!macWindowMetrics.nativeGlassDock)return
        var rows=[]
        function collect(item) {
            if(!item.visible)return
            if(item.objectName==="canvasNativeCard") {
                var p=item.mapToItem(null,0,0),q=item.mapToItem(null,item.width,item.height)
                var x=Math.min(p.x,q.x),y=Math.min(p.y,q.y),w=Math.abs(q.x-p.x),h=Math.abs(q.y-p.y)
                var left=Math.max(x,0),top=Math.max(0,y),right=Math.min(appRoot.width,x+w),bottom=Math.min(appRoot.height,y+h)
                for(var a=item.parent;a;a=a.parent)if(a.clip && a!==sceneViewport){var ap=a.mapToItem(null,0,0),aq=a.mapToItem(null,a.width,a.height);left=Math.max(left,Math.min(ap.x,aq.x));top=Math.max(top,Math.min(ap.y,aq.y));right=Math.min(right,Math.max(ap.x,aq.x));bottom=Math.min(bottom,Math.max(ap.y,aq.y))}
                var c=item.modelData,scale=w/Math.max(1,item.width)
                rows.push({key:c.key,x:x,y:y,width:w,height:h,scale:scale,radius:item.radius*scale,clipX:left,clipY:top,clipW:Math.max(0,right-left),clipH:Math.max(0,bottom-top),installed:c.installed,label:c.label,version:c.version,stats:Number(Number(c.hours||0).toFixed(2))+appRoot.tr(" h · ")+c.launches+appRoot.tr(" runs"),image:c.background || appRoot.defaultCardArt(c),defaultArtwork:!c.background,featured:item.featured,selected:item.selectedGlass,dark:appRoot.darkMode,resize:appRoot.cardSizeEditing && item.resizeHovered,editingSize:appRoot.cardSizeEditing,layer:item.z,order:rows.length})
                return
            }
            for(var i=0;i<item.children.length;i++)collect(item.children[i])
        }
        if(activePage==="Launch")collect(canvas)
        rows.sort(function(a,b){return a.layer-b.layer || a.order-b.order})
        macWindowMetrics.setCanvasCards(rows)
    }
    function syncNativeNavigation() {
        if (!downloadReady || !sidebar || !topBar) return
        macWindowMetrics.setNavigation(sidebarProgress, activePage, topBar.parent.height, sidebar.width)
        appRoot.queueSidebarMaterials()
        if (sidebarCloseButton) {
            var point = sidebarCloseButton.mapToItem(null, 0, 0)
            macWindowMetrics.setSidebarButton(point.x, point.y, sidebarProgress, topBar.parent.height)
        }
    }
    Connections {
        target: appRoot
        function onSidebarProgressChanged() { appRoot.syncNativeNavigation() }
        function onActivePageChanged() { appRoot.syncNativeNavigation() }
        function onHeightChanged() { appRoot.syncNativeNavigation() }
        function onWidthChanged() { appRoot.syncNativeNavigation() }
        function onSidebarPreferredWidthChanged() { appRoot.syncNativeNavigation() }
    }
    readonly property bool captureCompactNavigation: topBar.visible && appRoot.liquidGlass && glassTuning.materialVisible && !glassTuning.reducedTransparency
    Item {
        id: navigationComposite
        visible: false; width: topBar.width+64; height: topBar.height+64
        ShaderEffectSource {
            anchors.fill: parent; sourceItem: appRoot.captureCompactNavigation ? sceneSharpTexture : null
            sourceRect: Qt.rect(topBar.x-32,topBar.y-32,width,height)
            live: appRoot.captureCompactNavigation; smooth: true
        }
        // The bar's own glass: the pressed lens shows it shrunk, inside itself.
        ShaderEffectSource {
            x:32; y:32; width:topBar.width; height:topBar.height
            sourceItem: appRoot.captureCompactNavigation ? navGlassGroup : null
            sourceRect: Qt.rect(0,0,width,height)
            live: appRoot.captureCompactNavigation; smooth: true
        }
    }
    // What sits on the bar, in the composite's frame, for the lens to refract.
    Item {
        id: navigationForeground
        visible: false; width: navigationComposite.width; height: navigationComposite.height
        ShaderEffectSource {
            x:32; y:32; width:topBar.width; height:topBar.height
            sourceItem: appRoot.captureCompactNavigation ? topBar : null
            textureSize: Qt.size(Math.ceil(width*appRoot.glassPixelRatio),Math.ceil(height*appRoot.glassPixelRatio))
            live: appRoot.captureCompactNavigation; smooth: true
        }
        ShaderEffectSource {
            x:32+compactTabs.labelsItem.x; y:32+compactTabs.labelsItem.y
            width:compactTabs.labelsItem.width; height:compactTabs.labelsItem.height
            sourceItem: appRoot.captureCompactNavigation ? compactTabs.labelsItem : null
            textureSize: Qt.size(Math.ceil(width*appRoot.glassPixelRatio),Math.ceil(height*appRoot.glassPixelRatio))
            live: appRoot.captureCompactNavigation; smooth: true
        }
    }
    ShaderEffectSource {
        id: navigationForegroundTexture
        sourceItem: appRoot.captureCompactNavigation ? navigationForeground : null
        textureSize: navigationTexture.textureSize
        live: appRoot.captureCompactNavigation; smooth:true; visible:false
    }
    ShaderEffectSource {
        id: navigationTexture
        sourceItem: appRoot.captureCompactNavigation ? navigationComposite : null
        textureSize: Qt.size(Math.ceil(navigationComposite.width*appRoot.glassPixelRatio),Math.ceil(navigationComposite.height*appRoot.glassPixelRatio))
        live: appRoot.captureCompactNavigation; smooth:true; visible:false
    }
    Item {
        id: navigationOverlay
        x:topBar.x; y:topBar.y; width:topBar.width; height:topBar.height
        z:51; visible:topBar.visible; opacity:topBar.opacity
        Item { id:navigationViewport; x:-32; y:-32; width:parent.width+64; height:parent.height+64; visible:false }
    }
    // Unified Apple Music-inspired compact navigation.
    GlassPane {
        id: topBar
        objectName: "topBar"
        backdropBlur: false // The full-window compositor below handles blur.
        // navGlassGroup draws this bar's glass (fused with the search button).
        liquidGlass: !navGlassGroup.active
        color: navGlassGroup.active ? "transparent" : appRoot.materialTint
        border.width: navGlassGroup.active ? 0 : 1
        edgeGlow: !navGlassGroup.active
        z: 50
        visible: appRoot.sidebarProgress < 0.999 && !macWindowMetrics.nativeGlassDock && appRoot.navigationCollapse < 0.999
        opacity: (1.0 - appRoot.sidebarProgress) * (1 - appRoot.navigationCollapse)
        enabled: appRoot.sidebarProgress < 0.15 && appRoot.navigationCollapse < 0.5
        // Sidebar button, tabs, 6 pt insets. On Launch a separate search
        // button grows out from the bar's right edge (Liquid Glass) and the
        // pair re-centres as one.
        readonly property real searchSlotWidth: 56 + 10
        property real searchSlot: appRoot.activePage === "Launch" ? 1 : 0
        Behavior on searchSlot { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.002 } }
        // Apple segmented capsule: the selection is 0.82 of the bar's height,
        // inset evenly, both shapes with semicircular ends.
        width: 5 + 46 + 5 + 310 + 5
        height: 56
        x: Math.round((appRoot.width - width - searchSlotWidth * searchSlot) / 2)
        // Hiding, it rises a little as it fades (Safari's toolbar).
        y: 14 - appRoot.contentItem.y - 18 * appRoot.navigationCollapse
        radius: height / 2
        emphasized: true
        HoverHandler { id: navHover }
        Row {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 5
            // Same 5 pt inset as the tab selection, so both are concentric
            // with the bar (radius 28 - 5 = 23).
            Rectangle {
                width: 46; height: 46; radius: 23
                anchors.verticalCenter: parent.verticalCenter
                // Same neutral fill as the tab selection beside it (no fixed blue).
                color: sidebarButtonHover.hovered ? (appRoot.darkMode ? "#30FFFFFF" : "#18000000") : "transparent"
                HoverHandler { id: sidebarButtonHover }
                PointHandler { id: sidebarButtonPress; target: null }
                scale: glassTuning.reducedMotion ? 1 : sidebarButtonPress.active ? 1.07 : sidebarButtonHover.hovered ? 1.025 : 1
                Behavior on scale { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
                Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Show sidebar")
                SymbolImage { id: expandSidebarSymbol; anchors.centerIn: parent; width: 24; height: 24; symbol: "sidebar.left" }
                // Apple Music-style split sidebar icon (sidebar currently closed).
                Canvas {
                    id: expandSidebarIcon
                    visible: expandSidebarSymbol.status !== Image.Ready
                    anchors.centerIn: parent
                    width: 23; height: 20
                    Connections {
                        target: appRoot
                        function onDarkModeChanged() { expandSidebarIcon.requestPaint() }
                    }
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = appRoot.darkMode ? "#EAF4FF" : "#23374B"
                        ctx.lineWidth = 1.8
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(5, 2); ctx.lineTo(18, 2)
                        ctx.quadraticCurveTo(21, 2, 21, 5)
                        ctx.lineTo(21, 15); ctx.quadraticCurveTo(21, 18, 18, 18)
                        ctx.lineTo(5, 18); ctx.quadraticCurveTo(2, 18, 2, 15)
                        ctx.lineTo(2, 5); ctx.quadraticCurveTo(2, 2, 5, 2)
                        ctx.closePath(); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(8.5, 2); ctx.lineTo(8.5, 18); ctx.stroke()
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appRoot.sidebarMode = true
                }
            }
            GlassNavigation {
                id: compactTabs
                objectName: "compactNavigation"
                width: 310; height: 46
                badges: ({ Settings: appRoot.updatesPending })
                currentIndex: Math.max(0, tabs.indexOf(appRoot.activePage))
                reducedMotion: glassTuning.reducedMotion
                selectionParent: navigationOverlay
                foreground: appRoot.navigationText
                // Brighter than accentLabel: the current tab's text must stand
                // out on the glass lens.
                selectedForeground: appRoot.darkMode ? Qt.tint(appRoot.accent, "#A6FFFFFF") : appRoot.accent
                selectionColor: appRoot.darkMode ? "#30FFFFFF" : "#18000000"
                onActivated: function(index) { appRoot.activePage = tabs[index] }
                selectionMaterial: appRoot.liquidGlass && glassTuning.materialVisible ? compactRestMaterial : null
                pressedMaterial: appRoot.liquidGlass && glassTuning.materialVisible ? compactLensMaterial : null
                // At rest the selection is a dark blurred pill set into the
                // glass bar; only while pressed does it become a glass lens.
                Component {
                    id: compactRestMaterial
                    Item {
                        anchors.fill: parent
                        opacity: 1 - compactTabs.lensAmount
                        visible: opacity > 0
                        TunedLiquidGlass {
                            anchors.fill: parent
                            surface: compactTabs.selectionItem
                            viewport: contentScene
                            sharpTexture: sceneSharpTexture
                            blurredTexture: sceneFrostTexture
                            // Flat, like Apple's selected segment: no stroke, rim or
                            // pointer lights, so the 5 pt gap to the bar reads evenly.
                            frost: 1; density: 1
                            refraction: 0; shadowAmount: 0
                            strokeWidth: 0; glare: 0; specularAmount: 0; edgeAmount: 0; fresnelAmount: 0
                            interactionStrength: 0
                            macStyle: Qt.vector4d(0, 0, 0, 0)
                            radius: height/2
                        }
                        // Dark enough to read on dark wallpapers too.
                        Rectangle { anchors.fill: parent; radius: height/2; color: appRoot.darkMode ? "#6B000000" : "#24000000" }
                    }
                }
                Component {
                    id: compactLensMaterial
                    TunedLiquidGlass {
                        anchors.fill: parent
                        opacity: compactTabs.lensAmount
                        visible: opacity > 0
                        surface: compactTabs.selectionItem
                        viewport: navigationViewport
                        sharpTexture: navigationTexture
                        blurredTexture: navigationTexture
                        foregroundTexture: navigationForegroundTexture
                        foregroundBevel: glassTuning.lensLabelRange
                        frost: 0
                        radius: height/2
                        // Pressed, it minifies: the bar looks smaller inside it,
                        // its straight edges running out to the lens rim.
                        magnification: glassTuning.magnification * (1 - 0.2 * pressAmount)
                        // A narrower bevel keeps the edge refraction clear of the bar's edges.
                        bevelWidth: glassTuning.bevelWidth * (1 - 0.4 * pressAmount)
                        flatBevel: pressAmount
                        externalInteractionEnabled: compactTabs.pressingSelection
                        externalInteraction: compactTabs.interaction
                    }
                }
            }
        }
    }

    // Launch-only search button beside the compact navigation. Liquid Glass
    // appearance: it emerges from under the bar's right edge, growing and
    // fading in with a spring, and retracts the same way.
    GlassPane {
        id: topSearchButton
        objectName: "editorGlassControl"
        property string materialRole: "button"
        z: 50
        readonly property real slot: topBar.searchSlot
        visible: topBar.visible && slot > 0.01
        // With the shared glass below, only the symbol fades; the capsule
        // itself grows out of the bar.
        opacity: topBar.opacity * Math.min(1, Math.max(0, navGlassGroup.active ? (slot - 0.4) / 0.6 : slot))
        enabled: topBar.enabled && appRoot.activePage === "Launch"
        width: topBar.height; height: topBar.height; radius: height / 2
        x: topBar.x + topBar.width + 10 * slot - width * (1 - slot) * 0.6
        y: topBar.y
        // Glass Lab press: swell while pressed, and stay swollen (fused with
        // the bar) while the search panel is open.
        readonly property bool engaged: topSearchPress.active || appRoot.searchExpanded
        property real pressScale: glassTuning.reducedMotion ? 1 : engaged ? 1.07 : topSearchHover.hovered ? 1.025 : 1
        Behavior on pressScale { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
        scale: (0.55 + 0.45 * Math.min(1.08, slot)) * pressScale
        liquidGlass: !navGlassGroup.active
        color: navGlassGroup.active ? "transparent" : appRoot.materialTint
        border.width: navGlassGroup.active ? 0 : 1
        edgeGlow: !navGlassGroup.active
        emphasized: true
        Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Search")
        PointHandler { id: topSearchPress; target: null }
        HoverHandler { id: topSearchHover }
        SymbolImage { id: topSearchSymbol; anchors.centerIn: parent; width: 22; height: 22; symbol: "magnifyingglass" }
        GlassText { anchors.centerIn: parent; visible: topSearchSymbol.status !== Image.Ready; text: "⌕"; font.pixelSize: 27; color: appRoot.ink }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: appRoot.toggleSearch()
        }
    }
    // One Liquid Glass for the bar and the search button, as two capsules,
    // so they can fuse like the Glass Lab's capsules: the search capsule
    // emerges fused to the bar, separates as it slides out, and fuses back
    // while pressed or while search is open.
    Item {
        id: navGlassGroup
        readonly property bool active: appRoot.liquidGlass && glassTuning.materialVisible && topBar.visible
        z: 49
        visible: active
        opacity: topBar.opacity
        x: topBar.x; y: topBar.y
        width: topBar.width + 10 + topBar.height + 16; height: topBar.height
        readonly property vector4d searchShape: {
            var b = topSearchButton, s = b.scale
            if (b.slot < 0.02) return Qt.vector4d(0, 0, 0, 0)
            var cx = b.x + b.width / 2 - x, cy = b.y + b.height / 2 - y
            return Qt.vector4d(cx - b.width * s / 2, cy - b.height * s / 2, b.width * s, b.height * s)
        }
        // Fused while emerging (slot < 1) and while engaged.
        property real engagedFusion: topSearchButton.engaged && !glassTuning.reducedMotion ? 1 : 0
        Behavior on engagedFusion { enabled: !glassTuning.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Loader {
            anchors.fill: parent
            active: navGlassGroup.active
            sourceComponent: TunedLiquidGlass {
                surface: navGlassGroup
                viewport: contentScene
                sharpTexture: sceneSharpTexture
                blurredTexture: glassTuning.needsBlur ? sceneFrostTexture : sceneSharpTexture
                radius: topBar.radius
                capsuleCount: 2
                capsuleOne: Qt.vector4d(0, 0, topBar.width, topBar.height)
                capsuleTwo: navGlassGroup.searchShape
                pressedCapsule: 1
                capsuleFusionProgress: Math.max(navGlassGroup.engagedFusion, Math.max(0, 1 - topSearchButton.slot * 1.4))
                fusionDistance: glassTuning.fusionDistance
            }
        }
    }
    // Account access in compact-navigation mode, aligned to the upper-right.
    GlassPane {
        id: compactAccountButton
        backdropBlur: false // Disable misaligned local scene sampling; keep glass tint and highlight
        z: 72
        visible: appRoot.sidebarProgress < 0.999 && !macWindowMetrics.nativeGlassDock
        // Disappear in place; do not travel into the sidebar profile footer.
        opacity: Math.max(0, 1.0 - appRoot.sidebarProgress * 4)
        enabled: appRoot.sidebarProgress < 0.10
        width: 48; height: 48
        // Window buttons on the right: the top-left corner is the free one.
        x: appRoot.captionWidth > 0 ? 14 : appRoot.width - width - 14
        y: 18 - appRoot.contentItem.y
        radius: 24
        selectedGlass: appRoot.accountMenuOpen
        HoverHandler { id: accountButtonHover }
        Rectangle {
            anchors.centerIn: parent
            width: 30; height: 30; radius: 15
            color: appRoot.darkMode ? "#476B8CA7" : "#8BC4E2F3"
            Image { anchors.centerIn: parent; width: 24; height: 24; source: macWindowMetrics.defaultAccountAvatar; fillMode: Image.PreserveAspectFit }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: appRoot.toggleAccountMenu()
        }
    }

    // Windows: the same soft shadow as the sidebar's, along the top and bottom
    // window edges over the content (below the chrome, no input).
    Rectangle {
        visible: appRoot.customWindowChrome
        z: 45
        x: appRoot.contentLeft; y: -appRoot.contentItem.y
        width: appRoot.width - x; height: 30
        gradient: Gradient {
            GradientStop { position: 0; color: appRoot.darkMode ? "#59000000" : "#24000000" }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Rectangle {
        visible: appRoot.customWindowChrome
        z: 45
        x: appRoot.contentLeft; y: appRoot.height - appRoot.contentItem.y - height
        width: appRoot.width - x; height: 30
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: appRoot.darkMode ? "#59000000" : "#24000000" }
        }
    }
    // Windows: the rail casts a shadow onto the content (only its right edge
    // is on screen). Outside the sidebar because it clips.
    RectangularShadow {
        visible: sidebar.visible && appRoot.customWindowChrome
        z: 59
        x: sidebar.x; y: sidebar.y; width: sidebar.width; height: sidebar.height
        opacity: sidebar.opacity
        blur: 18; spread: 0
        color: appRoot.darkMode ? "#73000000" : "#2E000000"
    }
    Item {
        id: sidebar
        objectName: "sidebar"
        z: 60
        // Sidebar mode is a full-height, edge-to-edge navigation rail.
        visible: appRoot.sidebarProgress > 0.001
        x: -width * (1.0 - appRoot.sidebarProgress)
        opacity: Math.min(1, appRoot.sidebarProgress * 1.7)
        enabled: appRoot.sidebarProgress > 0.85
        y: 0
        width: Math.max(240, Math.min(appRoot.sidebarMaximumWidth, appRoot.sidebarPreferredWidth))
        onWidthChanged: appRoot.syncNativeNavigation()
        height: appRoot.height
        // The full-height navigation rail never needs a rounded floating frame.
        // Full-window aligned blur is shared with the dock and navigation below.
        clip: true
        GlassSurface {
            anchors.fill: parent
            visible: !macWindowMetrics.nativeSidebar
            color: appRoot.materialTint
            liquidGlass: true
            surfaceLift: 0.03
            // The cards' blur, frost and dimming (Settings › Layout › Card glass).
            cardStyle: appRoot.panelGlassStyle
        }
        // The full rail stays liquid glass; a restrained colour reflection lives only
        // along its right edge, at the same vertical position as the artwork.
        SidebarGlow {
            id: sidebarGlow
            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: parent.width * glassTuning.sidebarGlowCoverage
            scene: contentScene; sceneLeft: appRoot.contentLeft
            sampleWidth: glassTuning.sidebarGlowWidth
            softness: glassTuning.sidebarGlowBlur
            saturation: glassTuning.sidebarGlowSaturation
            dark: appRoot.darkMode
            // DockOver parity at the default 50 %; the slider doubles it at 100 %.
            opacity: glassTuning.sidebarGlow * 2
            active: appRoot.liquidGlass && glassTuning.materialVisible && !glassTuning.reducedTransparency
                    && glassTuning.sidebarGlow > 0.001 && appRoot.sidebarProgress > 0.001
        }
        // This hit-test layer consumes canvas gestures while leaving children interactive.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            preventStealing: true
            propagateComposedEvents: false
            onPressed: function(mouse) { mouse.accepted = true }
            onWheel: function(wheel) { wheel.accepted = true }
        }
        HoverHandler { id: sidebarHover }
        // Scrollable sidebar content is clipped ABOVE the fixed account footer.
        // Keep all navigation/instance/download elements clear of the account area.
        Flickable {
            id: sidebarScroll
            onContentYChanged: appRoot.syncNativeNavigation()
            x: 22
            // Same top with traffic lights or Windows caption buttons: the
            // traffic lights (9 pt inset, 14 pt tall) end at 23, above the title.
            y: 28
            width: sidebar.width - 44
            height: Math.max(0, sidebarAccountFooter.y - y - 14)
            clip: true
            contentWidth: width
            contentHeight: sidebarContent.implicitHeight + 10
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: sidebarScroll.contentHeight > sidebarScroll.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
            Column {
                id: sidebarContent
                width: sidebarScroll.width
                spacing: 13
            Row {
                width: parent.width
                height: 42
                spacing: 8
                GlassText {
                    text: appRoot.tr("Vitra")
                    color: ink
                    font.pixelSize: 23
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
                }
                Rectangle {
                    id: sidebarCloseButton
                    width: 40; height: 40; radius: width / 2
                    opacity: macWindowMetrics.nativeGlassDock ? 0 : 1
                    enabled: !macWindowMetrics.nativeGlassDock
                    color: sidebarCloseHover.hovered ? (appRoot.darkMode ? "#20FFFFFF" : "#18000000") : (appRoot.darkMode ? "#10FFFFFF" : "#0A000000")
                    border.width: 1; border.color: appRoot.hairline
                    HoverHandler { id: sidebarCloseHover }
                    SymbolImage { id: collapseSidebarSymbol; anchors.centerIn: parent; width: 24; height: 24; symbol: "menubar.rectangle"; tint: appRoot.darkMode ? "#C6C6C6" : appRoot.ink }
                    // Apple Music-style collapse icon (sidebar currently open).
                    Canvas {
                        id: collapseSidebarIcon
                        visible: collapseSidebarSymbol.status !== Image.Ready
                        anchors.centerIn: parent
                        width: 23; height: 20
                        Connections {
                            target: appRoot
                            function onDarkModeChanged() { collapseSidebarIcon.requestPaint() }
                        }
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = appRoot.darkMode ? "#EAF4FF" : "#23374B"
                            ctx.lineWidth = 1.8
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                        ctx.moveTo(5, 2); ctx.lineTo(18, 2)
                        ctx.quadraticCurveTo(21, 2, 21, 5)
                        ctx.lineTo(21, 15); ctx.quadraticCurveTo(21, 18, 18, 18)
                        ctx.lineTo(5, 18); ctx.quadraticCurveTo(2, 18, 2, 15)
                        ctx.lineTo(2, 5); ctx.quadraticCurveTo(2, 2, 5, 2)
                        ctx.closePath(); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(2, 7); ctx.lineTo(21, 7); ctx.stroke()
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appRoot.sidebarMode = false
                    }
                }
            }
            Column {
                visible: appRoot.sidebarProgress > 0.001
                width: parent.width; spacing: 10
                Repeater {
                    model: ["Launch", "Download", "Settings"]
                    delegate: Column {
                        required property string modelData
                        width: parent.width; spacing: 8
                        SidebarControl {
                        width: parent.width; height: 42; radius: height / 2
                        // Same selected-glass treatment as the top navigation.
                        fallbackColor: appRoot.activePage === modelData
                               ? (appRoot.darkMode ? "#20FFFFFF" : "#18000000") : "transparent"
                        nativeSelected: appRoot.activePage === modelData
                        border.width: 0
                        border.color: appRoot.darkMode ? "#55D5EDFF" : "#80FFFFFF"
                        Behavior on color { ColorAnimation { duration: appRoot.motionMs } }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            // Fixed-width icon column aligns every navigation label.
                            Item {
                                width:24; height:parent.height
                                readonly property string symbolName: modelData === "Launch" ? "play.fill" : modelData === "Download" ? "arrow.down.circle" : "gearshape"
                                // SF Symbols on macOS, bundled stand-ins elsewhere (Frontend.cpp).
                                SymbolImage { id: navSymbol; anchors.centerIn:parent; width:19; height:19
                                    symbol: parent.symbolName; tint: appRoot.accent }
                                GlassText { anchors.centerIn:parent; visible:navSymbol.status!==Image.Ready
                                    text:modelData==="Launch"?"▶":modelData==="Download"?"↓":"⚙"; color:appRoot.accent }
                            }
                            GlassText {
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: appRoot.tr(modelData)
                                color: appRoot.activePage === modelData ? appRoot.accentLabel : appRoot.navigationText
                                font.pixelSize: 14
                                font.bold: appRoot.activePage === modelData
                            }
                        }
                        // Pending update: the iPadOS badge at the trailing edge of Settings.
                        NotificationBadge {
                            visible: modelData === "Settings" && appRoot.updatesPending > 0
                            count: appRoot.updatesPending
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        }
                        MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            if(modelData === "Download") {
                                if(appRoot.activePage === "Download") appRoot.sidebarDownloadExpanded=!appRoot.sidebarDownloadExpanded
                                else appRoot.sidebarDownloadExpanded=true
                            }
                            appRoot.activePage = modelData
                        }
                    }
                        NativeChevron {
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            visible: modelData === "Download"
                            symbol: appRoot.sidebarDownloadExpanded ? "chevron.down" : "chevron.right"
                        }
                        MouseArea {
                            anchors.right: parent.right; width: 42; height: parent.height
                            visible: modelData === "Download"
                            onClicked: appRoot.sidebarDownloadExpanded=!appRoot.sidebarDownloadExpanded
                        }
                    }
                        Item {
                            width: parent.width; height: visible ? (macWindowMetrics.nativeGlassDock ? 236 : sidebarCategoryList.implicitHeight) : 0
                            visible: appRoot.sidebarDownloadExpanded && modelData === "Download" && appRoot.activePage === "Download" && !appRoot.downloadSelection
                                     && (macWindowMetrics.nativeGlassDock || appRoot.sidebarDownloadCategories)
                            Component.onCompleted: if(modelData === "Download") appRoot.sidebarDownloadAnchor = this
                            // Windows: Apple Music style sub-items, indented to the
                            // navigation labels; the current one is a soft capsule
                            // with an accent label.
                            Column {
                                id: sidebarCategoryList
                                visible: !macWindowMetrics.nativeGlassDock
                                width: parent.width; spacing: 2
                                Repeater {
                                    model: appRoot.downloadCategories
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool current: appRoot.downloadCategory === modelData
                                        width: sidebarCategoryList.width; height: 34; radius: height / 2
                                        color: current ? (appRoot.darkMode ? "#1AFFFFFF" : "#12000000")
                                               : categoryHover.hovered ? (appRoot.darkMode ? "#0DFFFFFF" : "#0A000000") : "transparent"
                                        Accessible.role: Accessible.Button; Accessible.name: modelData
                                        GlassText {
                                            x: 46; width: parent.width - 54; anchors.verticalCenter: parent.verticalCenter
                                            text: appRoot.tr(modelData); elide: Text.ElideRight; font.pixelSize: 13
                                            font.bold: parent.current
                                            color: parent.current ? appRoot.accentLabel : appRoot.navigationText
                                        }
                                        HoverHandler { id: categoryHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: appRoot.openDownloadCategory(modelData) }
                                    }
                                }
                            }
                        }
                    }
                }
                Item { width: parent.width; height: 10 }

                Column {
                    visible: !appRoot.sidebarGuideSeen
                    width:parent.width; spacing:8; leftPadding:12; rightPadding:12
                    GlassText { text:appRoot.tr("Sidebar · ") + (appRoot.sidebarGuideStep+1) + "/3"; color:appRoot.ink; font.pixelSize:12; font.bold:true }
                    GlassText { width:parent.width-24; wrapMode:Text.Wrap; color:appRoot.muted; font.pixelSize:12
                        text: [appRoot.tr("Launch keeps your instances and groups together. Select a card, then use the launch bar."),appRoot.tr("Download categories expand below Download. Search and filters stay in the right pane."),appRoot.tr("Settings controls appearance and shared defaults. Drag the sidebar edge to resize it.")][appRoot.sidebarGuideStep] }
                    Row { spacing:16
                        GlassText { text:appRoot.tr("Skip"); color:appRoot.muted; font.pixelSize:12; TapHandler { onTapped:appRoot.sidebarGuideSeen=true } }
                        GlassText { text:appRoot.sidebarGuideStep===2?appRoot.tr("Done"):appRoot.tr("Next"); color:appRoot.accent; font.pixelSize:12; font.bold:true
                            TapHandler { onTapped: { if(appRoot.sidebarGuideStep===2)appRoot.sidebarGuideSeen=true;else {appRoot.sidebarGuideStep++;appRoot.activePage=["Launch","Download","Settings"][appRoot.sidebarGuideStep]} } } }
                    }
                }
                // Collapsible sidebar instance section. Installed instances follow
                // the exact same Name/Smart ordering used by the canvas.
                SidebarControl {
                    width: parent.width
                    height: 34
                    radius: 12
                    fallbackColor: "transparent"
                    HoverHandler { id: instancesHeaderHover }
                    Row {
                        anchors.fill: parent
                        spacing: 8
                        GlassText {
                            width: parent.width - 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: appRoot.tr("Instances")
                            color: muted
                            font.pixelSize: 13
                            font.letterSpacing: 0
                        }
                        NativeChevron {
                            anchors.verticalCenter: parent.verticalCenter
                            symbol: appRoot.sidebarInstancesExpanded ? "chevron.down" : "chevron.right"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appRoot.sidebarInstancesExpanded = !appRoot.sidebarInstancesExpanded
                    }
                }

                Column {
                    id: instanceRows
                    visible: appRoot.sidebarInstancesExpanded
                    width: parent.width
                    spacing: 3

                    Repeater {
                        model: appRoot.sidebarDisplayRows()
                        delegate: SidebarControl {
                            required property var modelData
                            required property int index
                            width: sidebar.width - 44
                            height: modelData.type === "header" ? 28 : 35
                            radius: height / 2
                            opacity: appRoot.draggedInstanceKey === modelData.key ? 0.5 : 1
                            nativeSelected: appRoot.selectedCardKeys.indexOf(modelData.key)>=0
                            fallbackColor: appRoot.selectedCardKeys.indexOf(modelData.key)>=0 ? (appRoot.darkMode ? "#20FFFFFF" : "#18000000") : "transparent"
                            // Same selected glass as the navigation rows: no outline,
                            // which drew a dark box over the glass.
                            border.width: 0
                            RoundedInstanceImage {
                                visible: modelData.type !== "header"
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                defaultArtwork:!modelData.background
                                source: modelData.type === "header" ? "" : modelData.background || appRoot.defaultCardArt(modelData)
                                placement: modelData.type === "header" ? ({}) : appRoot.artworkPlacement(modelData.key)
                            }
                            GlassText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: modelData.type === "header" ? 12 : 46
                                width: parent.width - 58; elide: Text.ElideRight
                                text: appRoot.tr(modelData.label)
                                color: modelData.type === "header" ? appRoot.muted : (appRoot.selectedCardKeys.indexOf(modelData.key)>=0 ? appRoot.accentLabel : appRoot.navigationText)
                                font.bold: modelData.type === "header" || appRoot.selectedCardKeys.indexOf(modelData.key)>=0
                                font.pixelSize: modelData.type === "header" ? 12 : 13
                            }
                            NativeChevron {
                                visible: modelData.type === "header"
                                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                symbol: appRoot.collapsedInstanceGroups.indexOf(modelData.groupId)>=0 ? "chevron.right" : "chevron.down"
                            }
                            Rectangle {
                                x: 6; y: -2; width: parent.width - 12; height: 2
                                color: appRoot.accent
                                visible: appRoot.draggedInstanceKey.length > 0 && modelData.type!=="header" && appRoot.instanceDropSlot === appRoot.sidebarOrderIndex(modelData.key)
                            }
                            Rectangle {
                                x: 6; y: parent.height + 1; width: parent.width - 12; height: 2
                                color: appRoot.accent
                                visible: appRoot.draggedInstanceKey.length > 0 && modelData.type!=="header" && appRoot.instanceDropSlot === appRoot.sidebarOrderIndex(modelData.key)+1
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: modelData.type!=="header"
                                cursorShape: modelData.type!=="header" ? (pressed?Qt.ClosedHandCursor:Qt.OpenHandCursor) : Qt.PointingHandCursor
                                property real pressY: 0
                                onPressed: function(mouse){pressY=mapToItem(null,mouse.x,mouse.y).y}
                                onPositionChanged: function(mouse) {
                                    if(!pressed || !(pressedButtons & Qt.LeftButton) || modelData.type==="header")return
                                    var point=mapToItem(null,mouse.x,mouse.y)
                                    if(Math.abs(point.y-pressY)>6 || appRoot.draggedInstanceKey.length){appRoot.draggedInstanceKey=modelData.key;appRoot.updateInstanceDrop(point.y)}
                                }
                                onReleased: function(mouse) {
                                    if(mouse.button!==Qt.LeftButton)return
                                    var key=appRoot.draggedInstanceKey,slot=appRoot.instanceDropSlot
                                    appRoot.draggedInstanceKey="";appRoot.instanceDropSlot=-1
                                    if(key.length)appRoot.commitInstanceDrop(key,slot)
                                    else if(modelData.type==="header")appRoot.toggleSidebarGroup(modelData.groupId)
                                    else appRoot.selectCanvasCard(modelData,mouse.modifiers,appRoot.sidebarDisplayRows().filter(function(r){return r.type==="instance"}))
                                }
                                onClicked: function(mouse) {
                                    if(mouse.button!==Qt.RightButton || modelData.type==="header")return
                                    var point=mapToItem(appRoot.contentItem,mouse.x,mouse.y)
                                    appRoot.openCardMenu(modelData,point.x,point.y)
                                }
                                onDoubleClicked: function(mouse){if(mouse.button===Qt.LeftButton && modelData.type!=="header")appRoot.activateCard(modelData)}
                                onCanceled: {appRoot.draggedInstanceKey="";appRoot.instanceDropSlot=-1}
                            }
                        }
                    }

                }

                    // Sidebar download remains available with instances collapsed.
                    SidebarControl {
                        width: sidebar.width - 44
                        height: 38
                        radius: height / 2
                        nativeSelected: appRoot.sidebarQuickDownloadExpanded
                        fallbackColor: appRoot.sidebarQuickDownloadExpanded ? "#20FFFFFF" : "transparent"
                        // Selected glass like the navigation rows, without the outline.
                        border.width: 0
                        HoverHandler { id: quickDownloadHover }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                SymbolImage { id: quickDownloadSymbol; anchors.centerIn: parent; width: 19; height: 19
                                    symbol: "arrow.down.to.line"; tint: appRoot.accent }
                                GlassText { anchors.centerIn: parent; visible: quickDownloadSymbol.status !== Image.Ready
                                    text: "↓"; color: appRoot.accent; font.pixelSize: 18 }
                            }
                            GlassText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 64
                                text: appRoot.tr("Quick Download")
                                color: appRoot.sidebarQuickDownloadExpanded ? appRoot.accentLabel : appRoot.navigationText
                                font.bold: appRoot.sidebarQuickDownloadExpanded
                                font.pixelSize: 13
                            }
                            NativeChevron {
                                anchors.verticalCenter: parent.verticalCenter
                                symbol: appRoot.sidebarQuickDownloadExpanded ? "chevron.down" : "chevron.right"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                appRoot.sidebarQuickDownloadExpanded = !appRoot.sidebarQuickDownloadExpanded
                            }
                        }
                    }

                    SidebarControl {
                        nativeRole: "panel"
                        // Frosted, not Liquid Glass (no refraction or rims); its
                        // selectors and Download button are plain blur too.
                        forcePlainBlur: true
                        visible: appRoot.sidebarQuickDownloadExpanded
                        width: sidebar.width - 44
                        height: quickDownloadFields.implicitHeight + 20
                        radius: 17
                        Column {
                            id: quickDownloadFields
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            GlassSelect {
                                id: sidebarQuickVersionSelect
                                sidebarMaterial: true
                                glassMaterial: true
                                width: parent.width
                                options: appRoot.quickVersionOptions
                                selected: appRoot.sidebarQuickVersion
                                onChosen: function(value) { appRoot.sidebarQuickVersion = value }
                            }
                            GlassSelect {
                                sidebarMaterial: true
                                glassMaterial: true
                                width: parent.width
                                options: ["Vanilla", "Fabric", "Forge", "NeoForge", "Quilt"]
                                selected: appRoot.sidebarQuickLoader
                                onChosen: function(value) { appRoot.sidebarQuickLoader = value }
                            }
                            GlassText {
                                width:parent.width;visible:downloadData.quickVersionsBusy || !!downloadData.quickVersionsError
                                text:downloadData.quickVersionsBusy?appRoot.tr("Loading versions…"):downloadData.quickVersionsError
                                color:appRoot.muted;font.pixelSize:11;wrapMode:Text.WordWrap
                            }
                            SidebarControl {
                                width:parent.width;height:34;radius:15;visible:!!downloadData.quickVersionsError
                                GlassText {anchors.centerIn:parent;text:appRoot.tr("Retry versions");color:appRoot.ink;font.pixelSize:12}
                                MouseArea {anchors.fill:parent;onClicked:downloadData.loadQuickVersions(true)}
                            }
                            // Like the download lists' "Get" capsule (accent tint, bright
                            // accent label, press swell), as frosted glass.
                            GlassSurface {
                                width: parent.width
                                height: 34
                                radius: height / 2
                                liquidGlass: true
                                // Accent glass, like the dock's Launch button.
                                prominent: true
                                border.width: 0
                                color: Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, quickDownloadArea.pressed ? 0.5 : quickDownloadArea.containsMouse ? 0.4 : 0.3)
                                scale: glassTuning.reducedMotion ? 1 : quickDownloadArea.pressed ? 1.05 : 1
                                Behavior on scale { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.002 } }
                                Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Download")
                                GlassText {
                                    anchors.centerIn: parent
                                    text: appRoot.tr("Download")
                                    color: appRoot.accentLabel
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                MouseArea {
                                    id: quickDownloadArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        appRoot.beginDownload({ category: "Versions", name: appRoot.tr("Minecraft ") + appRoot.sidebarQuickVersion, version: appRoot.sidebarQuickVersion })
                                    }
                                }
                            }
                        }
                    }
            }
            Column {
                visible: appRoot.sidebarProgress < 0.001
                width: parent.width; spacing: 15
                GlassText { text: appRoot.tr("SELECTED INSTANCE"); color: muted; font.pixelSize: 10; font.letterSpacing: 1.2 }
                GlassText { text: appRoot.selectedLabel(); color: ink; font.pixelSize: 21; font.bold: true; width: parent.width; elide: Text.ElideRight }
                GlassText { text: appRoot.selectedVersion(); color: muted; font.pixelSize: 12 }
                GlassText { text: appRoot.tr("Drag empty canvas to pan · Double-click card to activate"); color: muted; font.pixelSize: 11; wrapMode: Text.WordWrap; width: parent.width }
            }
            }
        }
    }

    Timer {
        interval: 32; repeat: true
        running: appRoot.draggedInstanceKey.length > 0
        onTriggered: {
            var top = sidebarScroll.mapToItem(null, 0, 0).y
            var y = appRoot.instanceDragSceneY
            if (y < top+28) sidebarScroll.contentY = Math.max(0, sidebarScroll.contentY-10)
            else if (y > top+sidebarScroll.height-28)
                sidebarScroll.contentY = Math.min(Math.max(0, sidebarScroll.contentHeight-sidebarScroll.height), sidebarScroll.contentY+10)
            appRoot.updateInstanceDrop(y)
        }
    }
    // A narrow handle captures only edge drags, leaving sidebar rows usable.
    MouseArea {
        id: sidebarResizeHandle
        z: 100
        visible: appRoot.sidebarProgress >= 0.999
        enabled: visible
        x: sidebar.x + sidebar.width - width / 2
        y: 0
        width: 10
        height: appRoot.height
        cursorShape: Qt.SplitHCursor
        preventStealing: true
        property real pressSceneX: 0
        property real pressWidth: 0
        onPressed: function(mouse) {
            pressSceneX = mapToItem(null, mouse.x, mouse.y).x
            pressWidth = sidebar.width
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            var sceneX = mapToItem(null, mouse.x, mouse.y).x
            appRoot.sidebarPreferredWidth = Math.max(240, Math.min(appRoot.sidebarMaximumWidth,
                pressWidth + sceneX - pressSceneX))
        }
        onDoubleClicked: appRoot.sidebarPreferredWidth = 282
    }

    // Sidebar account footer, similar to Apple Music's bottom-left profile.
    SidebarControl {
        id: sidebarAccountFooter
        nativeRole: "accountContents"
        z: 67
        visible: appRoot.sidebarProgress > 0.001
        enabled: appRoot.sidebarProgress > 0.85
        // Match the sidebar and its native glass during the entire transition.
        opacity: Math.min(1, appRoot.sidebarProgress * 1.7)
        x: sidebar.x + 22
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: sidebar.width - 44
        height: 68
        radius: appRoot.macOSWindowCornerRadius
        fallbackColor: "transparent"
        border.width: 0
        border.color: appRoot.outline
        HoverHandler { id: footerHover }
        Row {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 11
            SidebarControl {
                nativeRole: "avatar"
                width: 41; height: 41; radius: 20.5
                anchors.verticalCenter: parent.verticalCenter
                fallbackColor: appRoot.darkMode ? "#527FA0C4" : "#9ED5EBFC"
                Image { anchors.centerIn: parent; width: 29; height: 29; source: macWindowMetrics.defaultAccountAvatar; fillMode: Image.PreserveAspectFit }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: parent.width - 78
                GlassText { text: prismBridge.offlineMode ? prismBridge.offlineName : (prismBridge.currentAccountName || appRoot.tr("Not signed in")); color: appRoot.ink; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; width: parent.width }
                GlassText { text: prismBridge.offlineMode ? appRoot.tr("Offline profile") : (prismBridge.currentAccountName?appRoot.tr("Microsoft account"):appRoot.tr("Not signed in")); color: appRoot.muted; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
            }
            NativeChevron { anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: appRoot.toggleAccountMenu()
        }
    }

    // Liquid Glass captures (Windows), each a full-window texture with the
    // same origin as its viewport. Blur runs at half resolution, as in the
    // Glass Lab, and only while the tuned frost actually mixes it in.
    // textureSize must be explicit: LiquidGlass reads it for its edge clamp,
    // and an automatic size reports 0x0, which pins sampling to the centre.
    readonly property real glassPixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    ShaderEffectSource {
        id: wallpaperSharpTexture
        width: backgroundLayer.width; height: backgroundLayer.height
        textureSize: Qt.size(Math.max(1, Math.ceil(width * appRoot.glassPixelRatio)), Math.max(1, Math.ceil(height * appRoot.glassPixelRatio)))
        sourceItem: appRoot.liquidGlass ? backgroundLayer : null
        live: appRoot.liquidGlass
        hideSource: false; visible: false; smooth: true
    }
    MultiEffect {
        id: wallpaperBlur
        width: backgroundLayer.width; height: backgroundLayer.height
        source: wallpaperSharpTexture
        blurEnabled: true; blur: glassTuning.effectiveBlur; blurMax: 40
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource {
        id: wallpaperFrostTexture
        // Also without frost: the plain-blur controls on glass panes use it.
        readonly property bool active: appRoot.liquidGlass && !glassTuning.reducedTransparency
        sourceItem: active ? wallpaperBlur : null
        textureSize: Qt.size(Math.max(1, Math.ceil(backgroundLayer.width / 2)), Math.max(1, Math.ceil(backgroundLayer.height / 2)))
        live: active
        hideSource: false; visible: false; smooth: true
    }
    ShaderEffectSource {
        id: sceneSharpTexture
        width: contentScene.width; height: contentScene.height
        textureSize: Qt.size(Math.max(1, Math.ceil(width * appRoot.glassPixelRatio)), Math.max(1, Math.ceil(height * appRoot.glassPixelRatio)))
        sourceItem: appRoot.liquidGlass ? contentScene : null
        live: appRoot.liquidGlass
        hideSource: false; visible: false; smooth: true
    }
    MultiEffect {
        id: sceneBlur
        width: contentScene.width; height: contentScene.height
        source: sceneSharpTexture
        blurEnabled: true; blur: glassTuning.effectiveBlur; blurMax: 40
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource {
        id: sceneFrostTexture
        // Always with Liquid Glass: the plain-blur controls (dock button) use it.
        readonly property bool active: appRoot.liquidGlass && !glassTuning.reducedTransparency
        sourceItem: active ? sceneBlur : null
        textureSize: Qt.size(Math.max(1, Math.ceil(contentScene.width / 2)), Math.max(1, Math.ceil(contentScene.height / 2)))
        live: active
        hideSource: false; visible: false; smooth: true
    }
    // Large glass (cards, Settings panes, sidebar): a much softer blur of the
    // frost textures, blurred again at a quarter of the window's size (cheap,
    // and smooth at any strength). Settings › Layout › Card glass blur.
    readonly property real softGlassBlur: Math.min(1, cardGlassBlur / 48)
    MultiEffect {
        id: wallpaperSoftBlur
        width: Math.max(1, Math.ceil(backgroundLayer.width / 4)); height: Math.max(1, Math.ceil(backgroundLayer.height / 4))
        source: wallpaperFrostTexture
        blurEnabled: true; blur: appRoot.softGlassBlur; blurMax: 32
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource {
        id: wallpaperSoftTexture
        readonly property bool active: wallpaperFrostTexture.active && appRoot.cardGlassBlur > 0.5
        sourceItem: active ? wallpaperSoftBlur : null
        textureSize: Qt.size(wallpaperSoftBlur.width, wallpaperSoftBlur.height)
        live: active
        hideSource: false; visible: false; smooth: true
    }
    MultiEffect {
        id: sceneSoftBlur
        width: Math.max(1, Math.ceil(contentScene.width / 4)); height: Math.max(1, Math.ceil(contentScene.height / 4))
        source: sceneFrostTexture
        blurEnabled: true; blur: appRoot.softGlassBlur; blurMax: 32
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource {
        id: sceneSoftTexture
        readonly property bool active: sceneFrostTexture.active && appRoot.cardGlassBlur > 0.5
        sourceItem: active ? sceneSoftBlur : null
        textureSize: Qt.size(sceneSoftBlur.width, sceneSoftBlur.height)
        live: active
        hideSource: false; visible: false; smooth: true
    }

    // Menus blur the page much further than glass does, and only while open.
    property int openGlassMenus: 0
    MultiEffect {
        id: menuBlur
        width: contentScene.width; height: contentScene.height
        source: sceneSharpTexture
        blurEnabled: true; blur: 1; blurMax: 64
        autoPaddingEnabled: false; visible: false
    }
    ShaderEffectSource {
        id: menuFrostTexture
        readonly property bool active: appRoot.liquidGlass && appRoot.openGlassMenus > 0
        sourceItem: active ? menuBlur : null
        textureSize: Qt.size(Math.max(1, Math.ceil(contentScene.width / 2)), Math.max(1, Math.ceil(contentScene.height / 2)))
        live: active
        hideSource: false; visible: false; smooth: true
    }

    // Prototype 09.25.1: one full-window backdrop capture and one full-window
    // rounded alpha mask. The two textures share exactly the window's origin,
    // extent, and device-pixel scaling. No per-panel sourceRect or crop.
    // The scene contains only the canvas/background, never its glass overlays.
    // Liquid Glass replaces this compositor on Windows.
    readonly property bool legacyChromeBlur: dockLiveBlur && !liquidGlass
    ShaderEffectSource {
        id: dockSceneTexture
        anchors.fill: parent
        sourceItem: appRoot.legacyChromeBlur ? sceneLayer : null
        hideSource: false
        live: appRoot.legacyChromeBlur
        recursive: false
        visible: false
    }
    Item {
        id: dockMaskShape
        anchors.fill: parent
        visible: false
        Rectangle {
            x: bottomDock.x
            y: bottomDock.y
            width: bottomDock.width
            height: bottomDock.height
            radius: bottomDock.radius
            color: "white"
        }
    }
    ShaderEffectSource {
        id: dockMaskTexture
        anchors.fill: parent
        sourceItem: dockMaskShape
        hideSource: true
        live: appRoot.legacyChromeBlur
        visible: false
    }
    MultiEffect {
        id: dockBackdropBlur
        anchors.fill: parent
        z: 84
        source: dockSceneTexture
        maskEnabled: true
        maskSource: dockMaskTexture
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.0
        blurEnabled: true
        blur: Math.max(0, Math.min(1, appRoot.dockBlurAmount))
        blurMax: 40
        autoPaddingEnabled: false
        visible: appRoot.legacyChromeBlur && !macWindowMetrics.nativeGlassDock
    }

    // 09.25: compact-navigation glass uses the SAME scene texture as the
    // launch bar, with a separate full-window alpha mask. It never crops the
    // texture or applies its blur over navigation icons / labels.
    Item {
        id: navMaskShape
        anchors.fill: parent
        visible: false
        Rectangle {
            x: topBar.x
            y: topBar.y
            width: topBar.width
            height: topBar.height
            radius: topBar.radius
            color: "white"
            opacity: topBar.opacity
        }
    }
    ShaderEffectSource {
        id: navMaskTexture
        anchors.fill: parent
        sourceItem: navMaskShape
        hideSource: true
        live: appRoot.legacyChromeBlur && appRoot.sidebarProgress < 1
        visible: false
    }
    MultiEffect {
        id: navBackdropBlur
        anchors.fill: parent
        z: 49 // Behind topBar (50), so labels and icons remain sharp.
        source: dockSceneTexture
        maskEnabled: true
        maskSource: navMaskTexture
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.0
        blurEnabled: true
        blur: Math.max(0, Math.min(1, appRoot.dockBlurAmount))
        blurMax: 40
        autoPaddingEnabled: false
        visible: appRoot.legacyChromeBlur && !macWindowMetrics.nativeGlassDock && appRoot.sidebarProgress < 0.999
    }

    // Apple Music-inspired persistent launch bar.
    GlassPane {
        id: bottomDock
        objectName: "bottomDock"
        backdropBlur: false // Never enable old per-panel sourceRect blur.
        // A separate, aligned full-window compositor sits behind this pane.
        // Keep sampled background text as soft shapes, never as a second
        // readable/ghosted text layer. Foreground labels remain crisp above.
        color: appRoot.materialTint
        rimColor: appRoot.hairline
        z: 85
        width: Math.min(560, appRoot.width - appRoot.contentLeft - 48)
        height: sidebarAccountFooter.height
        // Center the launch bar in the available content area, not at
        // the sidebar edge. The account panel remains stationary.
        x: appRoot.contentLeft + (appRoot.width - appRoot.contentLeft - width) / 2
        visible: !macWindowMetrics.nativeGlassDock
        anchors.bottom: parent.bottom
        anchors.bottomMargin: sidebarAccountFooter.anchors.bottomMargin
        radius: height / 2; emphasized: true
        HoverHandler { id: bottomHover }
        MouseArea {
            objectName: "dockInputShield"
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true; preventStealing: true
            propagateComposedEvents: false
            scrollGestureEnabled: true
            onPressed: function(mouse) { mouse.accepted = true }
            onDoubleClicked: function(mouse) { mouse.accepted = true }
            onWheel: function(wheel) { wheel.accepted = true }
        }
        // The Launch button sits as far from the dock's end as from its top
        // and bottom; the artwork gets a wider leading inset, as the album art
        // in Apple Music's mini player on iOS.
        Item {
            anchors.fill: parent
            Rectangle {
                id: dockInstanceIcon
                x: (bottomDock.height - height) / 2 + 7
                anchors.verticalCenter: parent.verticalCenter
                width: 46; height: 46; radius: 14
                // Opaque tile under the artwork (the default art's tint is translucent).
                color: appRoot.darkMode ? "#2C2C2E" : "#E5E5EA"
                RoundedInstanceImage {anchors.fill:parent;source:appRoot.selectedDockArtwork;defaultArtwork:appRoot.selectedDockDefaultArtwork;cornerRadius:14
                    placement:appRoot.selectedDockCard ? appRoot.artworkPlacement(appRoot.selectedDockCard.key) : ({})}
                // Open picker: the artwork turns into a close glyph (a chevron in
                // an outlined square), as a macOS Dock stack while it is open.
                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    color: appRoot.darkMode ? "#1C1C1E" : "#3A3A3C"
                    border.width: 2.5; border.color: "white"
                    opacity: appRoot.instancePickerOpen ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: glassTuning.reducedMotion ? 0 : 160 } }
                    SymbolImage { anchors.centerIn: parent; anchors.verticalCenterOffset: 2; width: 22; height: 22; symbol: "chevron.down"; tint: "white" }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appRoot.instancePickerOpen = !appRoot.instancePickerOpen
                }
            }
            Column {
                anchors.left: dockInstanceIcon.right; anchors.leftMargin: 14
                anchors.right: dockLaunchButton.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter; spacing: 4
                GlassText { text: appRoot.selectedLabel(); color: ink; font.bold: true; font.pixelSize: 14; width: parent.width; elide: Text.ElideRight }
                GlassText { text: appRoot.selectedVersion(); color: muted; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
            }
            GlassPane {
                id: dockLaunchButton
                anchors.right: parent.right; anchors.rightMargin: (bottomDock.height - height) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 105; height: 42; radius: 21
                backdropBlur:true
                prominent: appRoot.liquidGlass
                color: Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.45)
                // Liquid Glass press: the button swells under the finger and
                // springs back (Apple), on top of the material's own response.
                scale: glassTuning.reducedMotion ? 1 : dockLaunchArea.pressed ? 1.1 : dockLaunchArea.containsMouse ? 1.03 : 1
                Behavior on scale { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.002 } }
                // The play symbol at the label's cap height, centred on it (the
                // ▶ character was small and sat low beside the text).
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    // Drawn, not a symbol image: the image's padding made it tiny.
                    // A little taller than the caps, with softly rounded corners.
                    Canvas {
                        id: dockLaunchTriangle
                        width: 12; height: 13
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property color fill: appRoot.ink
                        onFillChanged: requestPaint()
                        onPaint: {
                            // Corner radius as on the iOS play symbol.
                            var ctx = getContext("2d"), r = 2.3
                            ctx.reset()
                            ctx.fillStyle = fill
                            ctx.lineJoin = "round"; ctx.lineWidth = r * 2; ctx.strokeStyle = fill
                            ctx.beginPath()
                            ctx.moveTo(r, r); ctx.lineTo(width - r, height / 2); ctx.lineTo(r, height - r); ctx.closePath()
                            ctx.fill(); ctx.stroke()
                        }
                    }
                    // Measured: the caps sit centred without the optical lift (it
                    // put them 1 px above the button's and the triangle's centre).
                    GlassText { anchors.verticalCenter: parent.verticalCenter; opticalOffset: 0; text: appRoot.tr("Launch"); color: appRoot.ink; font.bold: true; font.pixelSize: 13 }
                }
                MouseArea { id: dockLaunchArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; preventStealing: true; onClicked: appRoot.launchInstanceKey(appRoot.selectedId) }
            }
        }
    }
    Connections {
        target: bottomDock
        function syncDockGeometry() { macWindowMetrics.setDockGeometry(bottomDock.x, bottomDock.y, bottomDock.width, bottomDock.height, bottomDock.radius) }
        function onXChanged() { syncDockGeometry() }
        function onYChanged() { syncDockGeometry() }
        function onWidthChanged() { syncDockGeometry() }
        function onHeightChanged() { syncDockGeometry() }
        function onRadiusChanged() { syncDockGeometry() }
    }

    // Dock-style upward instance picker. Native ListView scrolling works
    // with mouse wheel and macOS trackpad two-finger gestures.
    MouseArea {
        z: 75
        anchors.fill: parent
        visible: appRoot.instancePickerOpen
        onClicked: appRoot.instancePickerOpen = false
        // The picker list passes the wheel on at its ends; stop it here so
        // the page underneath does not scroll while the picker is open.
        onWheel: function(wheel) { wheel.accepted = true }
    }
    // The picker lists real core instances only (as on the canvas).
    readonly property int pickerInstanceCount: {
        var n = 0
        for (var i = 0; i < instances.count; i++) if (instances.get(i).key.indexOf("prism:") === 0) n++
        return n
    }
    // macOS Dock stack "Fan": the instances rise from the dock artwork in a
    // gentle arc, each icon with its name in a dark capsule, springing out one
    // after another (lowest first). The wheel browses a longer list.
    property var pickerRows: []
    // Scroll position in items (fractional while gliding); pickerScroll eases to it.
    property real pickerOffset: 0
    property real pickerScroll: pickerOffset
    Behavior on pickerScroll { enabled: appRoot.pickerFan >= 1 && !glassTuning.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property real pickerMaxOffset: Math.max(0, pickerRows.length - pickerSlots)
    readonly property real pickerStep: 62
    // First icon centre above the dock artwork's: clear of it and its ring.
    readonly property real pickerLift: 66
    readonly property real pickerCurve: pickerVertical ? 0 : 0.8 // sideways drift per slot², as the Dock's fan
    // At most 7 at once, fewer in a short window: the fan keeps clear of the
    // top fifth of the window (at least 110 pt, room for the "Scroll for more"
    // capsule); the wheel scrolls the rest.
    readonly property real pickerTopClearance: Math.max(110, height * 0.2)
    readonly property int pickerSlots: Math.max(1, Math.min(pickerRows.length, 7, Math.floor((instancePicker.originY - pickerLift - 24 - pickerTopClearance) / pickerStep) + 1))
    property real pickerFan: instancePickerOpen ? 1 : 0
    Behavior on pickerFan { NumberAnimation { duration: glassTuning.reducedMotion ? 0 : 360 } }
    // Behind the fan only: the pages blurred and dimmed around the popped-out
    // icons and capsules themselves, fading out from their outline; the dock
    // stays sharp above (z 85).
    Item {
        id: pickerBackdrop
        z: 80
        anchors.fill: parent
        visible: appRoot.pickerFan > 0 && !macWindowMetrics.nativeGlassDock
        opacity: appRoot.pickerFan
        // Mask shape: the fan as drawn (same window coordinates), blurred so it
        // spreads past each item and fades out; it follows the fan's animation.
        ShaderEffectSource {
            id: pickerMaskShape
            anchors.fill: parent; visible: false
            sourceItem: pickerBackdrop.visible ? instancePicker : null
            live: true; hideSource: false
        }
        MultiEffect {
            id: pickerMask
            anchors.fill: parent; visible: false; layer.enabled: true
            source: pickerMaskShape
            blurEnabled: true; blur: 1.0; blurMax: 48; blurMultiplier: 0.6
            autoPaddingEnabled: false
        }
        Item {
            anchors.fill: parent
            layer.enabled: pickerBackdrop.visible
            // The blurred thin capsules leave a faint mask; this ramp reaches
            // full strength at about half its alpha (0.5 / 1 would be linear).
            layer.effect: MultiEffect { maskEnabled: true; maskSource: pickerMask; maskThresholdMin: 0.35; maskSpreadAtMin: 0.5 }
            ShaderEffectSource {
                id: pickerSceneSource
                width: contentScene.width; height: contentScene.height
                sourceItem: pickerBackdrop.visible && !glassTuning.reducedTransparency ? contentScene : null
                live: true; hideSource: false; visible: false
            }
            // The sidebar sits outside the captured scene: blur only the content area.
            Item {
                x: appRoot.contentLeft; width: parent.width - x; height: parent.height; clip: true
                MultiEffect {
                    x: -parent.x; width: contentScene.width; height: contentScene.height
                    visible: !glassTuning.reducedTransparency && appRoot.pickerBlurAmount > 0.001
                    source: pickerSceneSource
                    blurEnabled: true; blur: appRoot.pickerBlurAmount; blurMax: 32
                    autoPaddingEnabled: false
                }
            }
            Rectangle { anchors.fill: parent; color: "black"; opacity: appRoot.pickerShadowAmount * (appRoot.darkMode ? 0.7 : 0.4) }
        }
    }
    Item {
        id: instancePicker
        z: 95
        anchors.fill: parent
        visible: appRoot.pickerFan > 0 && !macWindowMetrics.nativeGlassDock
        // The fan's origin: the centre of the dock artwork.
        readonly property real originX: bottomDock.x + dockInstanceIcon.x + dockInstanceIcon.width / 2
        readonly property real originY: bottomDock.y + dockInstanceIcon.y + dockInstanceIcon.height / 2
        // Mouse wheel: one instance per notch; trackpads glide by pixels.
        // Up shows the instances higher in the list.
        WheelHandler {
            target: null
            enabled: appRoot.instancePickerOpen
            onWheel: function(event) {
                var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y / appRoot.pickerStep : event.angleDelta.y / 120
                appRoot.pickerOffset = Math.max(0, Math.min(appRoot.pickerMaxOffset, appRoot.pickerOffset + delta))
            }
        }
        Repeater {
            model: appRoot.pickerRows
            delegate: Item {
                id: fanItem
                required property var modelData
                required property int index
                readonly property real slot: index - appRoot.pickerScroll
                readonly property bool selected: modelData.key === appRoot.selectedId
                // Staggered progress, then an OutBack overshoot like the Dock's spring.
                readonly property real local: Math.max(0, Math.min(1, appRoot.pickerFan * (1 + 0.08 * appRoot.pickerSlots) - 0.08 * Math.max(0, slot)))
                readonly property real ease: { var c = 1.4, t = local - 1; return 1 + (c + 1) * t * t * t + c * t * t }
                // Rows scrolled past either end barely travel on (a third of the
                // distance) and fade out within 0.6 slot, so the lowest fades
                // above the dock instead of sliding into it.
                readonly property real past: Math.max(-slot, slot - (appRoot.pickerSlots - 1), 0)
                readonly property real place: slot < 0 ? slot / 3 : slot > appRoot.pickerSlots - 1 ? appRoot.pickerSlots - 1 + (slot - appRoot.pickerSlots + 1) / 3 : slot
                readonly property real edge: Math.max(0, 1 - past / 0.6)
                readonly property real targetX: instancePicker.originX - appRoot.pickerCurve * place * place
                readonly property real targetY: instancePicker.originY - appRoot.pickerLift - place * appRoot.pickerStep
                visible: edge > 0 && local > 0
                opacity: Math.min(1, local * 2) * edge
                x: instancePicker.originX + (targetX - instancePicker.originX) * ease - 24
                y: instancePicker.originY + (targetY - instancePicker.originY) * ease - 24
                width: 58 + fanLabel.width; height: 48
                transformOrigin: Item.Left
                scale: (0.4 + 0.6 * ease) * (0.85 + 0.15 * edge)
                // Each row leans with the arc's tangent.
                rotation: -Math.atan2(2 * appRoot.pickerCurve * place, appRoot.pickerStep) * 180 / Math.PI
                // Soft drop shadow under the icon and its capsule.
                layer.enabled: visible
                // Room for the selection ring and the hover growth past the bounds.
                layer.sourceRect: Qt.rect(-8, -8, width + 16, height + 16)
                layer.effect: MultiEffect {
                    shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.5 * appRoot.pickerShadowAmount
                    shadowBlur: 0.6; shadowVerticalOffset: 4
                }
                Item {
                    id: fanIcon
                    width: 48; height: 48
                    scale: fanArea.pressed ? 0.92 : fanArea.containsMouse ? 1.08 : 1
                    Behavior on scale { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.002 } }
                    // Opaque tile: the default artwork's tint is translucent.
                    Rectangle { anchors.fill: parent; radius: 12; color: appRoot.darkMode ? "#2C2C2E" : "#E5E5EA" }
                    RoundedInstanceImage { anchors.fill: parent; source: fanItem.modelData.art; defaultArtwork: fanItem.modelData.defaultArt; cornerRadius: 12
                        placement: appRoot.artworkPlacement(fanItem.modelData.key) }
                    Rectangle {
                        visible: fanItem.selected
                        anchors.fill: parent; anchors.margins: -3; radius: 15
                        color: "transparent"; border.width: 2; border.color: appRoot.accent
                    }
                }
                // Name capsule beside the icon: the shared Liquid Glass material,
                // so it follows Settings' glass appearance and tone.
                GlassPane {
                    id: fanLabel
                    x: 58; anchors.verticalCenter: parent.verticalCenter
                    width: fanLabelText.width + 24; height: 28; radius: 14
                    emphasized: true
                    frostBoost: 0.2 // a little frostier than the dock
                    selectedGlass: fanArea.containsMouse
                    GlassText {
                        id: fanLabelText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 240); elide: Text.ElideRight
                        text: fanItem.modelData.label; color: appRoot.ink; font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
                MouseArea {
                    id: fanArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { appRoot.chooseCard(fanItem.modelData.card); appRoot.instancePickerOpen = false }
                }
            }
        }
        // Above the top icon: how much of a longer list is shown.
        GlassPane {
            readonly property real local: Math.max(0, Math.min(1, appRoot.pickerFan * (1 + 0.08 * appRoot.pickerSlots) - 0.08 * appRoot.pickerSlots))
            emphasized: true
            frostBoost: 0.2
            visible: appRoot.pickerRows.length > appRoot.pickerSlots || appRoot.pickerRows.length === 0
            opacity: local
            x: instancePicker.originX - 24 - appRoot.pickerCurve * appRoot.pickerSlots * appRoot.pickerSlots
            y: instancePicker.originY - appRoot.pickerLift - (appRoot.pickerRows.length ? appRoot.pickerSlots : 0) * appRoot.pickerStep - height / 2
            width: fanHint.implicitWidth + 24; height: 28; radius: 14
            GlassText {
                id: fanHint
                anchors.centerIn: parent; color: appRoot.muted; font.pixelSize: 12
                text: appRoot.pickerRows.length === 0 ? appRoot.tr("No instances yet")
                      : appRoot.tr("Scroll for more · ") + (Math.round(appRoot.pickerScroll) + 1) + "–" + (Math.round(appRoot.pickerScroll) + appRoot.pickerSlots) + appRoot.tr(" of ") + appRoot.pickerRows.length
            }
        }
    }
    onInstancePickerOpenChanged: {
        var rows = []
        var selected = -1
        for (var n = 0; n < instances.count; ++n) {
            var entry = instances.get(n)
            rows.push({label: entry.label, version: entry.version, installed: entry.installed})
            if (entry.key === selectedId) selected = n
        }
        macWindowMetrics.setInstanceMenu(instancePickerOpen, rows, selected)
        if (instancePickerOpen) {
            // Real core instances only, in launch-page order; the selected one in view.
            var fan = [], at = 0
            sortedCards.forEach(function(c) {
                if (!c.key || c.key.indexOf("prism:") !== 0) return
                if (c.key === selectedId) at = fan.length
                fan.push({ key: c.key, label: c.label, art: c.background || defaultCardArt(c), defaultArt: !c.background, card: c })
            })
            pickerRows = fan
            pickerOffset = Math.max(0, Math.min(fan.length - pickerSlots, at - pickerSlots + 1))
        }
    }

    // Instance editor pane. Windows: the sidebar's frosted liquid glass with
    // a soft drop shadow; the pane no longer clips (the shadow lies outside
    // it), so scrolling contents clip themselves.
    component EditorGlassPane: GlassSurface {
        id: editorPane
        objectName: "editorGlassControl"
        clip: !appRoot.customWindowChrome
        radius: 24
        frosted: true
        color: macWindowMetrics.nativeGlassDock ? "transparent" : appRoot.glassStrong
        RectangularShadow {
            visible: appRoot.customWindowChrome
            z: -1
            anchors.fill: parent; anchors.topMargin: 4
            radius: editorPane.radius
            blur: 24; spread: 0
            color: appRoot.darkMode ? "#66000000" : "#26000000"
        }
    }
    component EditorLogBody: Flickable {
        id: logViewport
        property string logText: ""
        property bool wrapLines: true
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: !macWindowMetrics.nativeGlassDock
        contentWidth: width
        contentHeight: logTextArea.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        TextArea {
            id: logTextArea
            width: logViewport.width; height: Math.max(implicitHeight, logViewport.height)
            readOnly: true; text: logViewport.logText; color: appRoot.ink
            wrapMode: logViewport.wrapLines ? TextEdit.Wrap : TextEdit.NoWrap
            background: null
        }
    }
    component EditorSectionHeader: Item {
        id: sectionHeader
        property string title: ""
        property string actionText: ""
        signal triggered()
        default property alias controls: headerContents.data
        Layout.fillWidth: true
        implicitHeight: 44
        Rectangle {
            objectName: "editorGlassControl"
            property string materialRole: "sectionHeader"
            readonly property string headerTitle: sectionHeader.title
            readonly property string headerActionText: sectionHeader.actionText
            readonly property bool headerLog: sectionHeader.title === "Minecraft Log"
            readonly property bool keepUpdating: appRoot.logKeepUpdating
            readonly property bool wrapLines: appRoot.logWrapLines
            signal nativeKeep(bool value)
            signal nativeWrap(bool value)
            signal nativeCopy()
            signal nativeRefresh()
            onNativeKeep: function(value){appRoot.logKeepUpdating=value}
            onNativeWrap: function(value){appRoot.logWrapLines=value}
            onNativeCopy: macWindowMetrics.copyText(appRoot.editorLogText)
            onNativeRefresh: {if(appRoot.coreEditing)prismBridge.refreshEditor();appRoot.editorLogText=appRoot.editingMetadata.minecraftLog || ""}
            signal nativeAction()
            onNativeAction: sectionHeader.triggered()
            // The native mask rounds only the outside top corners.
            x: -16; y: -16; width: parent.width+32; height: parent.height+16
            radius: 24
            // On Windows the enclosing pane's Liquid Glass shows through.
            color: macWindowMetrics.nativeGlassDock || appRoot.liquidGlass ? "transparent" : appRoot.glassStrong
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 24; color: parent.color }
        }
        RowLayout { id: headerContents; visible: !macWindowMetrics.nativeGlassDock; anchors.fill: parent; anchors.bottomMargin: 10; spacing: 12 }
        // Same insets as the pane content below it.
        Rectangle { visible: !macWindowMetrics.nativeGlassDock; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: appRoot.darkMode ? "#2EFFFFFF" : "#26000000" }
    }
    component EditorAssetRow: Item {
        id: assetRow
        required property var modelData;required property int index
        property string bucket: "mods"
        // Windows: the list spans the pane, so rows keep the pane's 16 pt insets.
        property real inset: 0
        readonly property bool toggles: bucket!=="worlds" && bucket!=="screenshots"
        objectName:"editorGlassControl";property string materialRole:"assetRow"
        // Full width so the trailing buttons line up with the header's.
        width:ListView.view?ListView.view.width:0;height:52
        readonly property var assetData:modelData
        readonly property string assetBucket:bucket
        signal nativeToggle(bool enabled)
        signal nativeOpen()
        signal nativeRemove()
        onNativeToggle:function(enabled){appRoot.toggleEditorAsset(bucket,modelData,enabled)}
        onNativeOpen:appRoot.openEditorAsset(bucket,modelData)
        onNativeRemove:appRoot.removeEditorAsset(bucket,modelData)
        RowLayout {anchors.fill:parent;anchors.leftMargin:assetRow.inset;anchors.rightMargin:assetRow.inset;spacing:14;visible:!macWindowMetrics.nativeGlassDock
            // No padding: the switch starts at the title's leading edge.
            GlassSwitch {padding:0;visible:assetRow.toggles;checked:modelData.enabled!==false;onToggled:appRoot.toggleEditorAsset(bucket,modelData,checked)}
            Image {source:modelData.icon || "";Layout.preferredWidth:32;Layout.preferredHeight:32}
            GlassText {text:modelData.name+"  "+(modelData.version || "");color:appRoot.ink;Layout.fillWidth:true;elide:Text.ElideRight}
            GroupButton {Layout.preferredWidth:appRoot.editorButtonWidth;text:appRoot.tr("Open");onClicked:appRoot.openEditorAsset(bucket,modelData)}
            GroupButton {Layout.preferredWidth:appRoot.editorButtonWidth;text:appRoot.tr("Remove");onClicked:appRoot.removeEditorAsset(bucket,modelData)}
        }
        // List hairline from the name's leading edge, between rows.
        Rectangle {
            // ListView.view is null while the delegate is being destroyed.
            visible:!macWindowMetrics.nativeGlassDock && !!assetRow.ListView.view && index<assetRow.ListView.view.count-1
            anchors.left:parent.left;anchors.leftMargin:assetRow.inset+(assetRow.toggles?124:46)
            anchors.right:parent.right;anchors.rightMargin:assetRow.inset;anchors.bottom:parent.bottom;anchors.bottomMargin:-4
            height:1;color:appRoot.darkMode?"#24FFFFFF":"#1F000000"
        }
    }
    component EditorAssetList: EditorGlassPane {
        id: assetList
        property string bucket: "mods"
        readonly property var entries: appRoot.editingMetadata[bucket]||[]
        readonly property bool canUpdate: appRoot.coreEditing && !!appRoot.editorDownloadCategories[bucket]
        readonly property string addText: appRoot.editorDownloadCategories[bucket] ? appRoot.tr("Add from File…") : appRoot.coreEditing && (bucket==="worlds" || bucket==="screenshots")?appRoot.tr("Open folder…"):appRoot.tr("Add…")
        ColumnLayout {
            visible: !appRoot.customWindowChrome
            anchors.fill: parent; anchors.margins: 16; spacing: 12
            EditorSectionHeader {
                title: appRoot.editorTab
                actionText: appRoot.coreEditing && (bucket==="worlds" || bucket==="screenshots")?appRoot.tr("Open folder…"):appRoot.tr("Add…")
                onTriggered: appRoot.openEditorAssets(bucket)
                GlassText { text: appRoot.tr(appRoot.editorTab); color: appRoot.ink; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                GroupButton { visible: !!appRoot.editorDownloadCategories[bucket]; text: appRoot.tr("Download"); onClicked: appRoot.downloadForEditor(bucket) }
                GroupButton { visible: assetList.canUpdate; text: appRoot.tr("Update"); onClicked: appRoot.checkEditorUpdates(bucket) }
                GroupButton { text: assetList.addText; onClicked: appRoot.openEditorAssets(bucket) }
            }
            ListView {
                id:editorAssetViewport
                objectName: "editorAssetViewport"
                ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
                displayMarginBeginning:height;displayMarginEnd:height
                Layout.fillWidth: true; Layout.fillHeight: true; clip: !macWindowMetrics.nativeGlassDock; spacing: 8
                model: appRoot.customWindowChrome ? [] : assetList.entries
                delegate: EditorAssetRow { bucket: assetList.bucket }
            }
            GlassText { visible: !assetList.entries.length; text: appRoot.tr("No entries found"); color: appRoot.muted }
        }
        // Windows: the rows run to the pane's top and bottom edges. Under the
        // header they show blurred (macOS scroll edge effect), as in the log.
        Item {
            id: assetPage
            visible: appRoot.customWindowChrome
            anchors.fill: parent
            readonly property real headerHeight: 64
            ListView {
                id: windowsAssetList
                anchors.fill: parent
                topMargin: assetPage.headerHeight + 8; bottomMargin: 16
                clip: true; spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                displayMarginBeginning: assetPage.headerHeight
                model: appRoot.customWindowChrome ? assetList.entries : []
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; topPadding: assetPage.headerHeight + 4; bottomPadding: 16; rightPadding: 4 }
                delegate: EditorAssetRow { bucket: assetList.bucket; inset: 16 }
                layer.enabled: assetPage.visible
                layer.effect: MultiEffect { maskEnabled: true; maskSource: assetFadeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            // Mask for the sharp rows: the pane's rounded shape, hidden under
            // the header and fading in at the separator.
            Rectangle {
                id: assetFadeMask
                width: windowsAssetList.width; height: windowsAssetList.height
                radius: assetList.radius
                visible: false; layer.enabled: true
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: Math.max(0, assetPage.headerHeight / Math.max(1, windowsAssetList.height)); color: "transparent" }
                    GradientStop { position: Math.min(1, (assetPage.headerHeight + 8) / Math.max(1, windowsAssetList.height)); color: "white" }
                    GradientStop { position: 1; color: "white" }
                }
            }
            // Blurred copy of the rows under the header, inside the pane's top corners.
            Item {
                width: parent.width; height: assetPage.headerHeight; clip: true
                Item {
                    width: parent.width; height: parent.height + 30
                    layer.enabled: assetPage.visible; layer.smooth: true
                    layer.effect: ContinuousClip { radius: 24 }
                    ShaderEffectSource {
                        id: assetEdgeSource
                        width: parent.width; height: assetPage.headerHeight
                        sourceItem: assetPage.visible ? windowsAssetList.contentItem : null
                        sourceRect: Qt.rect(0, windowsAssetList.contentY, parent.width, assetPage.headerHeight)
                        live: true; hideSource: false; visible: false
                    }
                    MultiEffect {
                        width: parent.width; height: assetPage.headerHeight
                        source: assetEdgeSource
                        blurEnabled: true; blur: 1.0; blurMax: 40
                        autoPaddingEnabled: false
                        opacity: 0.85
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; height: 1
                    color: appRoot.darkMode ? "#2EFFFFFF" : "#1F000000"
                }
            }
            RowLayout {
                x: 16; width: parent.width - 32; height: assetPage.headerHeight
                // The rows' spacing and button width: the last two actions sit
                // above Open and Remove.
                spacing: 14
                GlassText { text: appRoot.tr(appRoot.editorTab); color: appRoot.ink; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                GroupButton { glass: true; Layout.preferredWidth: appRoot.editorButtonWidth; visible: !!appRoot.editorDownloadCategories[assetList.bucket]; text: appRoot.tr("Download"); onClicked: appRoot.downloadForEditor(assetList.bucket) }
                GroupButton { glass: true; Layout.preferredWidth: appRoot.editorButtonWidth; visible: assetList.canUpdate; text: appRoot.tr("Update"); onClicked: appRoot.checkEditorUpdates(assetList.bucket) }
                GroupButton { glass: true; Layout.preferredWidth: appRoot.editorButtonWidth; text: assetList.addText; onClicked: appRoot.openEditorAssets(assetList.bucket) }
            }
            GlassText {
                visible: !assetList.entries.length
                x: 16; y: assetPage.headerHeight + 16; width: parent.width - 32; wrapMode: Text.Wrap
                text: appRoot.tr("No entries found") + (appRoot.editorDropBuckets[assetList.bucket] ? " · " + appRoot.tr("Drop files here to add them") : "")
                color: appRoot.muted
            }
        }
    }
    Item {
        id: instanceEditorPage
        parent: contentScene
        visible: appRoot.activePage==="Instance"
        z: 12
        x: appRoot.contentLeft+28; y: appRoot.pageTop()
        width: appRoot.width-x-28; height: appRoot.panelHeight(y)
        ColumnLayout {
            anchors.fill: parent; spacing: 14
            RowLayout {
                Layout.preferredHeight:36+6*appRoot.sidebarProgress
                GroupButton { text: appRoot.tr("‹ Back"); onClicked: appRoot.activePage="Launch" }
                GlassText { text: appRoot.editingRecord?appRoot.editingRecord.label:appRoot.tr("Instance"); color: appRoot.ink; font.pixelSize: 24; font.bold: true; Layout.fillWidth: true }
                GroupButton {visible:appRoot.coreEditing;text:appRoot.tr("Refresh");onClicked:prismBridge.refreshEditor()}
            }
            GlassText {visible:!!appRoot.editingMetadata.error;Layout.fillWidth:true;text:appRoot.editingMetadata.error || "";color:appRoot.accent;wrapMode:Text.Wrap}
            GlassText {visible:!appRoot.coreEditing;Layout.fillWidth:true;text:appRoot.tr("This card is not linked to installed game files. Open an installed instance to manage its files.");color:appRoot.muted;wrapMode:Text.Wrap}
            GlassText {visible:appRoot.coreEditing;Layout.fillWidth:true;text:prismBridge.status;color:appRoot.muted;font.pixelSize:11;wrapMode:Text.Wrap}
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 14
                EditorGlassPane {
                    Layout.preferredWidth: 184; Layout.fillHeight: true
                    Flickable {
                        anchors.fill: parent; anchors.margins: 8; clip: !macWindowMetrics.nativeGlassDock
                        contentHeight: editorNavigation.implicitHeight; contentWidth: width
                        Column {
                            id: editorNavigation; width: parent.width; spacing: 4
                            Repeater {
                                model: appRoot.editorTabs
                                delegate: Rectangle {
                                    required property string modelData
                                    width: editorNavigation.width; height: 36; radius: 12
                                    color: appRoot.editorTab===modelData?"#28FFFFFF":"transparent"
                                    GlassText { anchors.fill: parent; anchors.leftMargin: 10; verticalAlignment: Text.AlignVCenter; text: appRoot.tr(modelData); color: appRoot.editorTab===modelData?appRoot.navigationSelectedText:appRoot.navigationText; font.bold: appRoot.editorTab===modelData; font.pixelSize: 12; elide: Text.ElideRight }
                                    MouseArea { anchors.fill: parent; onClicked: appRoot.editorTab=modelData }
                                }
                            }
                        }
                    }
                }
                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: appRoot.editorTabs.indexOf(appRoot.editorTab)
                    EditorGlassPane {
                        ColumnLayout { anchors.fill:parent; anchors.margins:16; spacing:12
                            EditorSectionHeader { title: appRoot.tr("Overview"); GlassText { text: appRoot.tr("Overview"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            GlassText { text:appRoot.editingRecord?appRoot.editingRecord.label:""; color:appRoot.ink; font.pixelSize:18; Layout.fillWidth:true; elide:Text.ElideRight }
                            GlassText { text:appRoot.editingRecord?appRoot.editingRecord.version:""; color:appRoot.muted; Layout.fillWidth:true; wrapMode:Text.Wrap }
                            Rectangle { Layout.fillWidth:true; height:1; color:appRoot.outline; opacity:0.3 }
                            GlassText { text:appRoot.editingRecord?(appRoot.editingRecord.hours+appRoot.tr(" hours played · ")+appRoot.editingRecord.launches+appRoot.tr(" launches")):"";color:appRoot.muted }
                            GlassText { text:appRoot.tr("Memory · ") + appRoot.effectiveMemoryMiB(appRoot.editingInstanceKey) + appRoot.tr(" MiB · ") + (appRoot.editingMetadata.useDefaultMemory!==false?appRoot.tr("Global default"):appRoot.tr("Instance override"));color:appRoot.muted;Layout.fillWidth:true;wrapMode:Text.Wrap }
                            GlassText { text:((appRoot.editingMetadata.mods||[]).length)+appRoot.tr(" mods · ")+((appRoot.editingMetadata.resourcePacks||[]).length)+appRoot.tr(" resource packs · ")+((appRoot.editingMetadata.shaderPacks||[]).length)+appRoot.tr(" shader packs");color:appRoot.muted;Layout.fillWidth:true;wrapMode:Text.Wrap }
                            Flow { Layout.fillWidth:true; spacing:12
                                GroupButton { text:appRoot.tr("Edit details");onClicked:appRoot.editorTab="Version" }
                                GroupButton { text:appRoot.tr("Runtime settings");onClicked:appRoot.editorTab="Settings" }
                            }
                            Item { Layout.fillHeight:true }
                        }
                    }
                    EditorGlassPane {
                        ColumnLayout {
                            visible: !appRoot.customWindowChrome
                            anchors.fill: parent; anchors.margins: 16
                            EditorSectionHeader {
                                title: appRoot.tr("Minecraft Log")
                                GlassText { text: appRoot.tr("Minecraft Log"); color: appRoot.ink; font.pixelSize: 20; font.bold: true }
                            }
                            Item { id: logControlsNativeArea; visible:false; Layout.preferredHeight:0 }
                            EditorLogBody { visible: !appRoot.customWindowChrome; logText: appRoot.editorLogText||appRoot.tr("No Minecraft log available"); wrapLines: appRoot.logWrapLines }
                        }
                        // Windows: the log runs the full pane height and scrolls up
                        // under the header, which shows it blurred (macOS scroll
                        // edge effect); the sharp text fades out beneath it.
                        Item {
                            id: logPage
                            visible: appRoot.customWindowChrome
                            anchors.fill: parent
                            readonly property real headerHeight: 64
                            property bool copied: false
                            Timer { id: logCopiedTimer; interval: 1500; onTriggered: logPage.copied = false }
                            EditorLogBody {
                                id: windowsLogBody
                                visible: logPage.visible
                                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 12
                                topMargin: logPage.headerHeight
                                logText: appRoot.editorLogText||appRoot.tr("No Minecraft log available"); wrapLines: appRoot.logWrapLines
                                layer.enabled: logPage.visible
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: logFadeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                            }
                            // Mask for the sharp log: hidden under the header, fading in at the separator.
                            Rectangle {
                                id: logFadeMask
                                width: windowsLogBody.width; height: windowsLogBody.height
                                visible: false; layer.enabled: true
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: Math.max(0, logPage.headerHeight / Math.max(1, windowsLogBody.height)); color: "transparent" }
                                    GradientStop { position: Math.min(1, (logPage.headerHeight + 8) / Math.max(1, windowsLogBody.height)); color: "white" }
                                    GradientStop { position: 1; color: "white" }
                                }
                            }
                            // Blurred copy of the log lines under the header, inside the
                            // pane's top corners.
                            Item {
                                width: parent.width; height: logPage.headerHeight; clip: true
                                Item {
                                    width: parent.width; height: parent.height + 30
                                    layer.enabled: logPage.visible; layer.smooth: true
                                    layer.effect: ContinuousClip { radius: 24 }
                                    // The capture spans the whole header width, edge to edge
                                    // of the pane (the 16 pt side margins sample as empty), so
                                    // the blur fills the band above the separator instead of
                                    // stopping in a straight column over the text.
                                    ShaderEffectSource {
                                        id: logEdgeSource
                                        width: parent.width; height: logPage.headerHeight
                                        sourceItem: logPage.visible ? windowsLogBody.contentItem : null
                                        sourceRect: Qt.rect(-16, windowsLogBody.contentY, parent.width, logPage.headerHeight)
                                        live: true; hideSource: false; visible: false
                                    }
                                    // Only the pane's own frosted glass shows here; a second
                                    // glass layer refracted the wallpaper twice and smeared
                                    // the header. The log lines under it are blurred.
                                    MultiEffect {
                                        width: parent.width; height: logPage.headerHeight
                                        source: logEdgeSource
                                        blurEnabled: true; blur: 1.0; blurMax: 40
                                        autoPaddingEnabled: false
                                        opacity: 0.85
                                    }
                                    // No extra tint: the sidebar shows materialTint only as
                                    // its no-glass fallback, and an overlay here turned the
                                    // header into a solid teal band.
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom; width: parent.width; height: 1
                                    color: appRoot.darkMode ? "#2EFFFFFF" : "#1F000000"
                                }
                            }
                            RowLayout {
                                x: 20; width: parent.width - 36; height: logPage.headerHeight
                                spacing: 10
                                GlassText { text: appRoot.tr("Minecraft Log"); color: appRoot.ink; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                                GroupButton {
                                    glass: true
                                    text: logPage.copied ? appRoot.tr("Copied") : appRoot.tr("Copy")
                                    enabled: !!appRoot.editorLogText
                                    onClicked: { macWindowMetrics.copyText(appRoot.editorLogText); logPage.copied = true; logCopiedTimer.restart() }
                                }
                            }
                        }
                    }
                    EditorGlassPane {
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16; spacing: 12
                            EditorSectionHeader { title: appRoot.tr("Version"); GlassText { text: appRoot.tr("Version"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            GlassText { text: appRoot.tr("Instance name"); color: appRoot.ink }
                            GroupField { id: editInstanceName;onTextEdited:appRoot.editorDirtyFields.name=true; Layout.fillWidth: true; text: appRoot.editingRecord?appRoot.editingRecord.label:"" }
                            GlassText { text: appRoot.tr("Minecraft / loader"); color: appRoot.ink }
                            GroupField { id: editInstanceVersion;readOnly:appRoot.coreEditing; Layout.fillWidth: true; text: appRoot.editingRecord?appRoot.editingRecord.version:"" }
                            ListView {
                                id:versionListViewport
                                visible:appRoot.coreEditing;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
                                model:appRoot.editingMetadata.components || []
                                delegate:GlassText {required property var modelData;width:ListView.view.width;height:28;text:modelData.name+" · "+modelData.version;color:appRoot.ink;elide:Text.ElideRight}
                            }
                            Flow { Layout.fillWidth:true; spacing:12
                                GroupButton { text: appRoot.tr("Save"); onClicked: appRoot.saveInstanceDetails(editInstanceName.text,editInstanceVersion.text) }
                                GroupButton { text: appRoot.tr("Background…"); onClicked: {appRoot.chooseBackgroundFor([appRoot.editingInstanceKey])} }
                            }
                            GlassText { text: appRoot.editingRecord?appRoot.editingRecord.hours+appRoot.tr(" h · ")+appRoot.editingRecord.launches+appRoot.tr(" launches"):""; color: appRoot.muted }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    // Background: the card picture and how it sits on the card.
                    // The preview is a card at 1.25×: drag to move, scroll to resize.
                    EditorGlassPane {
                        id: backgroundPane
                        readonly property string instanceKey: appRoot.editingInstanceKey
                        readonly property string picture: (appRoot.cardMetadata[instanceKey] || {}).background || ""
                        readonly property var placement: appRoot.artworkPlacement(instanceKey)
                        // While dragging, the preview moves without saving each step.
                        property var draft: null
                        readonly property var shown: draft || placement
                        readonly property var fitValues: ["fill", "fit", "stretch", "original"]
                        readonly property var fitTitles: ["Fill", "Fit", "Stretch", "Original size"]
                        function commit(patch) { draft = null; appRoot.setArtworkPlacement(instanceKey, patch) }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16; spacing: 14
                            EditorSectionHeader { title: appRoot.tr("Background"); GlassText { text: appRoot.tr("Background"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            GlassText {
                                visible: !backgroundPane.picture.length
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: appRoot.muted
                                text: appRoot.tr("Choose a picture for this instance's card. Then set how it fills the card, its size and position.")
                            }
                            // Without a picture the card shows its loader icon: what sits behind it.
                            RowLayout {
                                visible: !backgroundPane.picture.length
                                Layout.fillWidth: true; spacing: 8
                                readonly property string fill: backgroundPane.placement.iconFill || ""
                                readonly property string mode: fill === "" ? "Automatic" : fill === "transparent" ? "Transparent" : fill.indexOf("glass") === 0 ? "Liquid Glass" : "Custom"
                                function chooseColour() {
                                    appRoot.pickColor(fill.charAt(0) === "#" ? fill : "#1F1F1F", function(value) { backgroundPane.commit({ iconFill: value.toString() }) }, appRoot.tr("Icon background"))
                                }
                                GlassText { Layout.fillWidth: true; text: appRoot.tr("Icon background"); color: appRoot.ink }
                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    visible: parent.mode === "Custom"
                                    color: visible ? parent.fill : "transparent"
                                    border.width: 1; border.color: appRoot.hairline
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.chooseColour() }
                                }
                                GlassSelect {
                                    width: 170; options: ["Automatic", "Transparent", "Liquid Glass", "Custom"]
                                    selected: parent.mode
                                    onChosen: function(value) {
                                        if (value === "Automatic") backgroundPane.commit({ iconFill: "" })
                                        else if (value === "Transparent") backgroundPane.commit({ iconFill: "transparent" })
                                        else if (value === "Liquid Glass") backgroundPane.commit({ iconFill: "glass" })
                                        else parent.chooseColour()
                                        Qt.callLater(syncSelectedIndex)
                                    }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 24
                                // Card preview, same proportions and corner as a canvas card.
                                Item {
                                    width: 300; height: 210
                                    visible: backgroundPane.picture.length > 0
                                    // Without a base colour the card is glass, as on the canvas.
                                    GlassSurface {
                                        anchors.fill: parent
                                        visible: backgroundPane.shown.color === "glass"
                                        radius: appRoot.cardRadius * 1.25
                                        liquidGlass: true
                                        color: appRoot.glassSoft
                                    }
                                    Item {
                                        id: backgroundPreview
                                        anchors.fill: parent
                                        layer.enabled: true; layer.smooth: true
                                        layer.effect: ContinuousClip { radius: appRoot.cardRadius * 1.25 }
                                        Rectangle { anchors.fill: parent; color: "#1F1F1F"; visible: backgroundPane.shown.color !== "glass" }
                                        CardArtwork { anchors.fill: parent; source: backgroundPane.picture; placement: backgroundPane.shown }
                                        Rectangle {
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: parent.height * 0.45
                                            gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "#73000000" } }
                                        }
                                        GlassText {
                                            x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                                            text: appRoot.editingRecord ? appRoot.editingRecord.label : ""; color: "white"; font.pixelSize: 19; font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property point start
                                        property var origin
                                        onPressed: function(mouse) { start = Qt.point(mouse.x, mouse.y); origin = backgroundPane.placement }
                                        onPositionChanged: function(mouse) {
                                            if (!pressed) return
                                            var next = Object.assign({}, origin)
                                            next.x = Math.max(-1, Math.min(1, origin.x + (mouse.x - start.x) / (width / 2)))
                                            next.y = Math.max(-1, Math.min(1, origin.y + (mouse.y - start.y) / (height / 2)))
                                            backgroundPane.draft = next
                                        }
                                        onReleased: if (backgroundPane.draft) backgroundPane.commit({ x: backgroundPane.draft.x, y: backgroundPane.draft.y })
                                        onWheel: function(wheel) { backgroundPane.commit({ scale: backgroundPane.placement.scale * Math.pow(1.1, wheel.angleDelta.y / 120) }) }
                                    }
                                }
                                ColumnLayout {
                                    width: Math.max(260, Math.min(420, backgroundPane.width - 32 - 324)); spacing: 10
                                    visible: backgroundPane.picture.length > 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        GlassText { Layout.fillWidth: true; text: appRoot.tr("Fill mode"); color: appRoot.ink }
                                        GlassSelect {
                                            width: 170; options: backgroundPane.fitTitles
                                            selected: backgroundPane.fitTitles[Math.max(0, backgroundPane.fitValues.indexOf(backgroundPane.shown.fit))]
                                            onChosen: function(value) { backgroundPane.commit({ fit: backgroundPane.fitValues[backgroundPane.fitTitles.indexOf(value)] }) }
                                        }
                                    }
                                    GlassText { text: appRoot.tr("Size") + " · " + Math.round(backgroundPane.shown.scale * 100) + "%"; color: appRoot.ink }
                                    GlassSlider {
                                        Layout.fillWidth: true; from: 0.1; to: 4; stepSize: 0.01; tickValues: [1]
                                        value: backgroundPane.shown.scale
                                        onMoved: backgroundPane.commit({ scale: snapToTick(value) })
                                    }
                                    GlassText { text: appRoot.tr("Horizontal position"); color: appRoot.ink }
                                    GlassSlider {
                                        Layout.fillWidth: true; from: -1; to: 1; stepSize: 0.01; tickValues: [0]
                                        value: backgroundPane.shown.x
                                        onMoved: backgroundPane.commit({ x: snapToTick(value) })
                                    }
                                    GlassText { text: appRoot.tr("Vertical position"); color: appRoot.ink }
                                    GlassSlider {
                                        Layout.fillWidth: true; from: -1; to: 1; stepSize: 0.01; tickValues: [0]
                                        value: backgroundPane.shown.y
                                        onMoved: backgroundPane.commit({ y: snapToTick(value) })
                                    }
                                    // Automatic (the picture's tint), no base (the card's
                                    // liquid glass) or a chosen colour.
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        readonly property string mode: !backgroundPane.shown.color ? "Automatic"
                                                                       : backgroundPane.shown.color === "glass" ? "Liquid Glass" : "Custom"
                                        function chooseColour() {
                                            var current = backgroundPane.shown.color && backgroundPane.shown.color !== "glass" ? backgroundPane.shown.color : "#1F1F1F"
                                            appRoot.pickColor(current, function(value) { backgroundPane.commit({ color: value.toString() }) }, appRoot.tr("Colour behind the picture"))
                                        }
                                        GlassText { Layout.fillWidth: true; text: appRoot.tr("Colour behind the picture"); color: appRoot.ink }
                                        // The chosen colour; click to change it.
                                        Rectangle {
                                            width: 22; height: 22; radius: 11
                                            visible: parent.mode === "Custom"
                                            color: visible ? backgroundPane.shown.color : "transparent"
                                            border.width: 1; border.color: appRoot.hairline
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.chooseColour() }
                                        }
                                        GlassSelect {
                                            width: 170; options: ["Automatic", "Liquid Glass", "Custom"]
                                            selected: parent.mode
                                            onChosen: function(value) {
                                                if (value === "Automatic") backgroundPane.commit({ color: "" })
                                                else if (value === "Liquid Glass") backgroundPane.commit({ color: "glass" })
                                                else parent.chooseColour()
                                                // Cancelling the colour picker keeps the previous mode shown.
                                                Qt.callLater(syncSelectedIndex)
                                            }
                                        }
                                    }
                                }
                            }
                            // A Liquid Glass base (behind the icon, or behind the picture):
                            // its tint and the tint's strength (default from Settings).
                            ColumnLayout {
                                id: glassTintBlock
                                readonly property bool active: backgroundPane.picture.length ? backgroundPane.shown.color === "glass"
                                                                                            : backgroundPane.placement.iconFill === "glass"
                                readonly property string tint: backgroundPane.placement.glassTint || ""
                                readonly property bool useDefault: backgroundPane.placement.tintOpacity < 0
                                readonly property real strength: useDefault ? appRoot.cardGlassTintOpacity : backgroundPane.placement.tintOpacity
                                readonly property var values: ["", "accent", "artwork"]
                                readonly property var titles: ["None", "Theme colour", backgroundPane.picture.length ? "From picture" : "From icon"]
                                visible: active
                                Layout.fillWidth: true; Layout.maximumWidth: 420; spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    GlassText { Layout.fillWidth: true; text: appRoot.tr("Glass tint"); color: appRoot.ink }
                                    GlassSelect {
                                        width: 170; options: glassTintBlock.titles
                                        selected: glassTintBlock.titles[Math.max(0, glassTintBlock.values.indexOf(glassTintBlock.tint))]
                                        onChosen: function(value) { backgroundPane.commit({ glassTint: glassTintBlock.values[glassTintBlock.titles.indexOf(value)] }) }
                                    }
                                }
                                RowLayout {
                                    visible: glassTintBlock.tint !== ""
                                    Layout.fillWidth: true; spacing: 8
                                    GlassText { Layout.fillWidth: true; text: appRoot.tr("Use default tint strength"); color: appRoot.ink }
                                    GlassSwitch {
                                        checked: glassTintBlock.useDefault
                                        onToggled: backgroundPane.commit({ tintOpacity: checked ? -1 : appRoot.cardGlassTintOpacity })
                                    }
                                }
                                GlassText {
                                    visible: glassTintBlock.tint !== ""
                                    text: appRoot.tr("Tint strength") + " · " + Math.round(glassTintBlock.strength * 100) + "%"
                                    color: glassTintBlock.useDefault ? appRoot.muted : appRoot.ink
                                }
                                GlassSlider {
                                    visible: glassTintBlock.tint !== ""
                                    enabled: !glassTintBlock.useDefault
                                    Layout.fillWidth: true; from: 0.05; to: 1; stepSize: 0.01
                                    value: glassTintBlock.strength
                                    onMoved: backgroundPane.commit({ tintOpacity: value })
                                }
                            }
                            GlassText {
                                visible: backgroundPane.picture.length > 0
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: appRoot.muted; font.pixelSize: 12
                                text: appRoot.tr("Drag the preview to move the picture and scroll over it to resize. For an irregular icon, choose Fit or Original size and a colour behind it.")
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 12
                                GroupButton { text: appRoot.tr("Background…"); onClicked: {appRoot.chooseBackgroundFor([backgroundPane.instanceKey])} }
                                GroupButton {
                                    visible: backgroundPane.picture.length > 0
                                    text: appRoot.tr("Reset position and size")
                                    onClicked: backgroundPane.commit({ fit: "fill", scale: 1, x: 0, y: 0, color: "" })
                                }
                                GroupButton {
                                    visible: backgroundPane.picture.length > 0
                                    text: appRoot.tr("Remove background")
                                    onClicked: {
                                        prismBridge.removeInstanceBackground(backgroundPane.instanceKey)
                                        appRoot.setInstanceMetadata(backgroundPane.instanceKey, { background: "" })
                                        appRoot.setArtworkPlacement(backgroundPane.instanceKey, { fit: "fill", scale: 1, x: 0, y: 0, color: "" })
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    EditorAssetList { bucket: "mods" }
                    EditorAssetList { bucket: "resourcePacks" }
                    EditorAssetList { bucket: "shaderPacks" }
                    EditorGlassPane {
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16
                            EditorSectionHeader { title: appRoot.tr("Notes"); GlassText { text: appRoot.tr("Notes"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; TextArea { id: instanceNotes;onTextChanged:if(activeFocus)appRoot.editorDirtyFields.notes=true; text: appRoot.editingMetadata.notes||""; color: appRoot.ink; wrapMode: TextEdit.Wrap } }
                            GroupButton { text: appRoot.tr("Save notes"); onClicked: appRoot.setInstanceMetadata(appRoot.editingInstanceKey,{notes:instanceNotes.text}) }
                        }
                    }
                    EditorAssetList { bucket: "worlds" }
                    EditorGlassPane {
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16
                            EditorSectionHeader { title: appRoot.tr("Servers"); GlassText { text: appRoot.tr("Servers"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            RowLayout {
                                GroupField { id: serverAddress; placeholderText: appRoot.tr("Server address"); Layout.fillWidth: true }
                                GroupButton { text: appRoot.tr("Add"); onClicked:{appRoot.addEditorServer(serverAddress.text);serverAddress.text=""} }
                            }
                            ListView {
                                id:serverListViewport
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                model: appRoot.editingMetadata.servers||[]
                                delegate: RowLayout {
                                    required property var modelData; required property int index
                                    width: ListView.view.width
                                    GlassText { text: modelData.name; color: appRoot.ink; Layout.fillWidth: true }
                                    GroupButton { text: appRoot.tr("Remove"); onClicked:appRoot.removeEditorServer(modelData,index) }
                                }
                            }
                        }
                    }
                    EditorAssetList { bucket: "screenshots" }
                    EditorGlassPane {
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16; spacing: 12
                            EditorSectionHeader { title: appRoot.tr("Settings"); GlassText { text: appRoot.tr("Settings"); color: appRoot.ink; font.pixelSize:20; font.bold:true } }
                            GlassText { text: appRoot.tr("Java path"); color: appRoot.ink }
                            GroupField { id: instanceJava;onTextEdited:appRoot.editorDirtyFields.javaPath=true; Layout.fillWidth: true; text: appRoot.editingMetadata.javaPath||"" }
                            GlassText { text: appRoot.tr("Java arguments"); color: appRoot.ink }
                            GroupField { id: instanceJavaArgs;onTextEdited:appRoot.editorDirtyFields.javaArgs=true; Layout.fillWidth: true; text: appRoot.editingMetadata.javaArgs||"" }
                            Item {
                                id: instanceMemoryNativeArea
                                Layout.fillWidth: true; Layout.preferredHeight: 176
                                ColumnLayout {
                                    anchors.fill: parent; visible: !macWindowMetrics.nativeGlassDock; spacing: 10
                                    RowLayout {
                                        GlassText { text: appRoot.tr("Maximum memory (MiB)"); color: appRoot.ink; Layout.fillWidth: true }
                                        GlassSwitch { text: appRoot.tr("Default"); checked: appRoot.editingMetadata.useDefaultMemory !== false
                                            onToggled: appRoot.setInstanceMetadata(appRoot.editingInstanceKey, {useDefaultMemory: checked}) }
                                    }
                                    MemoryAllocation { Layout.fillWidth: true
                                        enabled: appRoot.editingMetadata.useDefaultMemory === false
                                        allocation: appRoot.effectiveMemoryMiB(appRoot.editingInstanceKey)
                                        onCommitted: function(value) { appRoot.setInstanceMetadata(appRoot.editingInstanceKey, {memoryMiB: value}) } }
                                    GlassText { text: appRoot.memoryStatus; color: appRoot.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: appRoot.coreEditing
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    GlassText { text: appRoot.tr("Use default options.txt"); color: appRoot.ink }
                                    GlassText { text: !appRoot.core("DefaultOptionsEnabled") ? appRoot.tr("Default options.txt is turned off in Settings.")
                                                    : appRoot.tr("Replaces this instance’s options.txt with the default file once, on its next launch.")
                                        color: appRoot.muted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                }
                                GlassSwitch { checked: appRoot.editingMetadata.useDefaultOptions !== false
                                    onToggled: appRoot.setInstanceMetadata(appRoot.editingInstanceKey, {useDefaultOptions: checked}) }
                            }
                            GroupButton { text: appRoot.tr("Save"); onClicked: appRoot.setInstanceMetadata(appRoot.editingInstanceKey,{javaPath:instanceJava.text,javaArgs:instanceJavaArgs.text}) }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    EditorGlassPane {
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16
                            EditorSectionHeader {
                                title: appRoot.tr("Other Logs")
                                GlassText { text: appRoot.tr("Other Logs"); color: appRoot.ink; font.pixelSize: 20; font.bold: true }
                            }
                            EditorLogBody { logText: appRoot.editingMetadata.otherLogs||appRoot.tr("No other logs available"); wrapLines: true }
                        }
                    }
                }
            }
        }
    }
    // Dedicated content pages replace the canvas, never float above it.
    Item {
        id: pageContent
        parent: contentScene
        z: 12
        opacity: macWindowMetrics.nativeGlassDock ? 0 : 1
        enabled: !macWindowMetrics.nativeGlassDock
        visible: appRoot.activePage === "Settings"
        x: appRoot.contentLeft + 28
        y: appRoot.pageTop()
        width: appRoot.width - appRoot.contentLeft - 56
        height: appRoot.height-appRoot.contentItem.y-y
        // The column stays centred at every width: equal gutters on both sides,
        // the section rail in the right one. Its labels need 122 pt from the
        // column to the window edge (the page's own 28 pt inset included);
        // below that the rail is bars only and the labels float out on hover.
        readonly property real railGutter: 24
        readonly property bool railLabels: (width - settingsColumn.width) / 2 + 28 >= 122
        readonly property var railSections: {
            var sections = [{title: "General", item: settingsHeaderPane}, {title: "Appearance", item: settingsCaptionAppearance},
                            {title: "Layout", item: settingsCaptionLayout}, {title: "Memory", item: settingsCaptionMemory},
                            {title: "Storage", item: settingsCaptionStorage},
                            {title: "Launch", item: settingsCaptionLaunch}, {title: "Java", item: settingsCaptionJava},
                            {title: "Downloads", item: settingsCaptionDownloads},
                            {title: "Translation", item: settingsCaptionTranslation},
                            {title: "Updates", item: settingsCaptionUpdates}]
            if (Qt.platform.os === "windows") sections.push({title: "Liquid Glass", item: settingsCaptionGlass})
            return sections
        }
        // 2.4 = 40% of the way from section 2 to section 3, for the thumb.
        property real railPosition: 0
        property int railTarget: -1
        property real railTargetY: 0
        function railStops() {
            var maxY = Math.max(0, settingsFlick.contentHeight - settingsFlick.height)
            return railSections.map(function(section) { return Math.min(maxY, section.item.mapToItem(settingsContent, 0, 0).y) })
        }
        function syncRail() {
            if (!visible) return
            // A click holds its section until the page is scrolled away from it:
            // the sections at the end can share one scroll position.
            if (railTarget >= 0 && !railScroll.running && Math.abs(settingsFlick.contentY - railTargetY) > 1) railTarget = -1
            if (railTarget >= 0) { railPosition = railTarget; return }
            var stops = railStops(), y = settingsFlick.contentY, i = 0
            while (i < stops.length - 1 && y >= stops[i + 1]) i++
            var span = i < stops.length - 1 ? stops[i + 1] - stops[i] : 0
            railPosition = i + (span > 0 ? (y - stops[i]) / span : 0)
        }
        function jumpToSection(index) {
            railScroll.stop()
            settingsFlick.cancelFlick()
            railTarget = index
            railTargetY = railStops()[index]
            railPosition = index
            railScroll.to = railTargetY
            railScroll.start()
        }
        // Dragging: position runs over the bars as in railPosition.
        function scrollToRail(position) {
            railScroll.stop()
            settingsFlick.cancelFlick()
            railTarget = -1
            var stops = railStops(), p = Math.max(0, Math.min(stops.length - 1, position)), i = Math.floor(p)
            var next = Math.min(i + 1, stops.length - 1)
            settingsFlick.contentY = stops[i] + (stops[next] - stops[i]) * (p - i)
        }
        onVisibleChanged: syncRail()
        NumberAnimation {
            id: railScroll
            target: settingsFlick; property: "contentY"
            duration: glassTuning.reducedMotion ? 0 : 320; easing.type: Easing.OutCubic
        }
        Flickable {
            id: settingsFlick
            objectName: "settingsFlickable"
            x: 0; y: -pageContent.y-appRoot.contentItem.y
            width: parent.width; height: appRoot.height
            contentWidth: width; contentHeight: settingsContent.y+settingsContent.implicitHeight+bottomDock.height+44
            clip: false; boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: pageContent.syncRail()
            onContentHeightChanged: pageContent.syncRail()
            onHeightChanged: pageContent.syncRail()
        Column {
            id: settingsContent
            y: pageContent.y+appRoot.contentItem.y
            width: parent.width
            spacing: 24
            Column {
                id: settingsColumn
                visible: appRoot.activePage === "Settings"
                width: Math.min(760, pageContent.width - pageContent.railGutter * 2)
                x: (pageContent.width - width) / 2
                spacing: 10
                // Header card, as in iPadOS Settings > General.
                GlassPane {
                    id: settingsHeaderPane
                    width: parent.width; height: settingsHeader.implicitHeight + 48; radius: 28
                    subtle: true; edgeGlow: false
                    Column {
                        id: settingsHeader
                        x: 24; y: 24; width: parent.width - 48; spacing: 10
                        Rectangle {
                            width: 64; height: 64; radius: 15
                            gradient: Gradient { GradientStop { position: 0; color: "#9C9CA3" } GradientStop { position: 1; color: "#636369" } }
                            SymbolImage { anchors.centerIn: parent; width: 46; height: 46; symbol: "gearshape"; tint: "white" }
                        }
                        GlassText { text: appRoot.tr("Settings"); color: appRoot.ink; font.pixelSize: 26; font.bold: true }
                        GlassText {
                            width: parent.width; wrapMode: Text.Wrap
                            text: appRoot.tr("Manage the launcher core, appearance, canvas layout, memory and the Liquid Glass material.")
                            color: appRoot.muted; font.pixelSize: 15
                        }
                    }
                }
                Item { width: 1; height: 4 }
                // Apple Settings search: a capsule field with a magnifier, a clear
                // button while typing, and the matching settings listed below.
                // Choosing one scrolls to it and lights it briefly.
                Item {
                    id: settingsSearch
                    width: parent.width; height: appRoot.downloadControlHeight
                    property string query: ""
                    property int highlighted: 0
                    readonly property var results: query.trim().length ? find(query) : []
                    onQueryChanged: highlighted = 0
                    function find(text) {
                        var q = text.trim().toLowerCase(), found = []
                        var stops = pageContent.railSections.map(function(section) {
                            return {title: appRoot.tr(section.title), y: section.item.mapToItem(settingsContent, 0, 0).y}
                        })
                        function sectionAt(y) { var t = ""; for (var i = 0; i < stops.length; ++i) if (stops[i].y <= y + 1) t = stops[i].title; return t }
                        function visit(item) {
                            // The search itself would re-run this binding as its results change.
                            if (!item || !item.visible || item === settingsSearch || item === settingsSearchResults) return
                            if (item.isSettingsRow === true && item.title.length) {
                                var section = sectionAt(item.mapToItem(settingsContent, 0, 0).y)
                                if (item.title.toLowerCase().indexOf(q) >= 0 || section.toLowerCase().indexOf(q) >= 0)
                                    found.push({row: item, title: item.title, section: section, symbol: item.symbol, tile: String(item.tileColor)})
                            }
                            for (var i = 0; i < item.children.length; ++i) visit(item.children[i])
                        }
                        visit(settingsColumn)
                        return found.slice(0, 40)
                    }
                    function reveal(result) {
                        if (!result || !result.row) return
                        var row = result.row
                        settingsSearchInput.focus = false
                        query = ""
                        // After the results list closes, the row has its final place.
                        Qt.callLater(function() {
                            var maxY = Math.max(0, settingsFlick.contentHeight - settingsFlick.height)
                            var y = row.mapToItem(settingsContent, 0, 0).y + settingsContent.y - settingsFlick.height / 3
                            railScroll.stop(); settingsFlick.cancelFlick(); pageContent.railTarget = -1
                            railScroll.to = Math.max(0, Math.min(maxY, y))
                            railScroll.start()
                            row.flash()
                        })
                    }
                    SearchField {
                        id: settingsSearchInput
                        anchors.fill: parent
                        placeholderText: appRoot.tr("Search")
                        rightPadding: clearSearch.visible ? 36 : 14
                        text: settingsSearch.query
                        onTextEdited: settingsSearch.query = text
                        Keys.onEscapePressed: { settingsSearch.query = ""; focus = false }
                        Keys.onDownPressed: settingsSearch.highlighted = Math.min(settingsSearch.results.length - 1, settingsSearch.highlighted + 1)
                        Keys.onUpPressed: settingsSearch.highlighted = Math.max(0, settingsSearch.highlighted - 1)
                        onAccepted: settingsSearch.reveal(settingsSearch.results[settingsSearch.highlighted])
                    }
                    // Clear: a filled grey circle with a white x, as on iOS.
                    Rectangle {
                        id: clearSearch
                        visible: settingsSearch.query.length > 0
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 17; height: 17; radius: 8.5
                        color: appRoot.darkMode ? "#99EBEBF5" : "#8C3C3C43"
                        SymbolImage { anchors.centerIn: parent; width: 9; height: 9; symbol: "xmark"; tint: appRoot.darkMode ? "#1C1C1E" : "white" }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { settingsSearch.query = ""; settingsSearchInput.forceActiveFocus() } }
                    }
                }
                SettingsSection {
                    id: settingsSearchResults
                    visible: settingsSearch.query.trim().length > 0
                    Repeater {
                        model: settingsSearch.results
                        delegate: Item {
                            id: resultRow
                            required property var modelData
                            required property int index
                            readonly property bool lit: index === settingsSearch.highlighted
                            width: parent ? parent.width : 0; height: 48
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 4; radius: 20
                                color: resultRow.lit || resultHover.hovered ? (appRoot.darkMode ? "#16FFFFFF" : "#10000000") : "transparent"
                            }
                            Rectangle {
                                visible: resultRow.modelData.symbol.length > 0
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26; radius: 7; color: resultRow.modelData.tile
                                SymbolImage { anchors.centerIn: parent; width: 16; height: 16; symbol: resultRow.modelData.symbol; tint: "white" }
                            }
                            GlassText {
                                x: 56; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - resultSection.implicitWidth - 32
                                text: resultRow.modelData.title; color: appRoot.ink; font.pixelSize: 15
                                elide: Text.ElideRight; textFormat: Text.PlainText
                            }
                            GlassText {
                                id: resultSection
                                anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                text: resultRow.modelData.section; color: appRoot.muted; font.pixelSize: 13; textFormat: Text.PlainText
                            }
                            Rectangle {
                                visible: resultRow.index < settingsSearch.results.length - 1
                                anchors.left: parent.left; anchors.leftMargin: 56
                                anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom
                                height: 1; color: appRoot.darkMode ? "#2EFFFFFF" : "#26000000"
                            }
                            HoverHandler { id: resultHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: settingsSearch.reveal(resultRow.modelData) }
                        }
                    }
                    GlassText {
                        visible: settingsSearch.results.length === 0
                        width: parent ? parent.width : 0; height: 64
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: appRoot.tr("No Results for “%1”").replace("%1", settingsSearch.query.trim())
                        color: appRoot.muted; font.pixelSize: 15; textFormat: Text.PlainText
                    }
                }
                Item { width: 1; height: 14 }
                // iPadOS "Software Update Available": first, with the badge.
                SettingsSection {
                    visible: appRoot.updatesPending > 0
                    SettingsRow {
                        symbol: "arrow.down.circle"; tileColor: "#30D158"
                        title: appRoot.tr("Update available · Vitra Launcher %1").replace("%1", prismBridge.availableUpdate || "")
                        chevron: true; last: true
                        onClicked: prismBridge.installAvailableUpdate()
                        NotificationBadge { count: appRoot.updatesPending }
                    }
                }
                Item { width: 1; height: 14; visible: appRoot.updatesPending > 0 }
                SettingsSection {
                    SettingsRow {
                        symbol: "cpu"; tileColor: "#0A84FF"; title: appRoot.tr("Launcher core"); value: appRoot.tr("Accounts, Java, logs")
                        chevron: true
                        onClicked: prismConnection.open()
                    }
                    // Replaces the core's first-run language page; affects the core's
                    // own dialogs. The list arrives with the translations index, so
                    // it is re-read whenever Settings opens.
                    SettingsRow {
                        id: languageRow
                        symbol: "list.bullet"; tileColor: "#5E5CE6"; title: appRoot.tr("Core language"); last: true
                        property var languages: []
                        property int revision: 0
                        function reload() { languages = prismBridge.languages() }
                        Component.onCompleted: reload()
                        Connections { target: appRoot; function onActivePageChanged() { if (appRoot.activePage === "Settings") languageRow.reload() } }
                        GlassSelect {
                            width: 210
                            options: languageRow.languages.map(function(l) { return l.name })
                            selected: {
                                languageRow.revision
                                var key = prismBridge.currentLanguage()
                                for (var i = 0; i < languageRow.languages.length; i++) if (languageRow.languages[i].key === key) return languageRow.languages[i].name
                                return key
                            }
                            onChosen: function(value) {
                                for (var i = 0; i < languageRow.languages.length; i++) if (languageRow.languages[i].name === value) prismBridge.setLanguage(languageRow.languages[i].key)
                                languageRow.revision++
                            }
                        }
                    }
                }

                // Interface size: Qt's scale factor, applied at the next start.
                SettingsSection {
                    id: interfaceScaleSection
                    property real saved: prismBridge.interfaceScale()
                    readonly property real session: prismBridge.sessionInterfaceScale()
                    readonly property var values: [0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
                    readonly property bool pending: Math.abs(saved - session) > 0.001
                    function label(v) { return Math.round(v * 100) + "%" }
                    SettingsRow {
                        symbol: "magnifyingglass"; tileColor: "#0A84FF"; title: appRoot.tr("Interface size")
                        last: !interfaceScaleSection.pending
                        GlassSelect {
                            width: 120
                            options: interfaceScaleSection.values.map(interfaceScaleSection.label)
                            selected: interfaceScaleSection.label(interfaceScaleSection.saved)
                            onChosen: function(value) {
                                var v = interfaceScaleSection.values[options.indexOf(value)]
                                prismBridge.setInterfaceScale(v); interfaceScaleSection.saved = v
                            }
                        }
                    }
                    SettingsRow {
                        visible: interfaceScaleSection.pending
                        symbol: "arrow.uturn.backward"; tileColor: "#30D158"; title: appRoot.tr("Restart to apply the new size")
                        chevron: true; last: true
                        onClicked: if (!prismBridge.restartLauncher()) appRoot.statusMessage = appRoot.tr("Could not restart. Close and open the launcher to apply.")
                    }
                }
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionAppearance; text: appRoot.tr("Appearance") }
                SettingsSection {
                    // Windows only: off moves the window buttons to the top
                    // right as Windows 11 caption buttons.
                    SettingsRow {
                        symbol: "paintpalette"; tileColor: "#8B5CF6"; title: appRoot.tr("Themes")
                        value: appRoot.appliedThemeId ? themeStore.theme(appRoot.appliedThemeId).name || appRoot.tr("Custom") : appRoot.tr("Custom")
                        chevron: true; onClicked: themeLibraryPopup.open()
                    }
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#636366"; title: appRoot.tr("Appearance mode")
                        GlassSelect { width: 210; options: ["Auto","System","Dark","Light"]; selected: appRoot.appearanceMode; onChosen: function(value) { appRoot.appearanceMode = value } }
                    }
                    SettingsRow {
                        visible: appRoot.customWindowChrome
                        symbol: "square.grid.2x2"; tileColor: "#FF453A"; title: appRoot.tr("macOS window buttons on the left")
                        GlassSwitch { checked: appRoot.macWindowControls; onToggled: appRoot.macWindowControls = checked }
                    }
                    // As on macOS: the window buttons turn grey while another window is active.
                    SettingsRow {
                        visible: appRoot.trafficLights
                        symbol: "circle.lefthalf.filled"; tileColor: "#8E8E93"; title: appRoot.tr("Grey window buttons when inactive")
                        GlassSwitch { checked: appRoot.greyInactiveWindowButtons; onToggled: appRoot.greyInactiveWindowButtons = checked }
                    }
                    SettingsRow {
                        visible: appRoot.customWindowChrome
                        symbol: "circle.lefthalf.filled"; tileColor: "#636366"; title: appRoot.tr("Grey window when inactive")
                        GlassSwitch { checked: appRoot.greyInactiveWindow; onToggled: appRoot.greyInactiveWindow = checked }
                    }
                    SettingsRow {
                        symbol: "paintpalette"; tileColor: "#FF9F0A"; title: appRoot.tr("Accent color")
                        GlassSelect {
                            width: 160
                            options: ["Auto","System","Blue","Purple","Pink","Red","Orange","Yellow","Green","Custom"]
                            selected: appRoot.themeChoice
                            onChosen: function(value) { appRoot.themeChoice = value }
                        }
                        GroupButton { text: appRoot.tr("Choose…"); implicitHeight: 26; cornerRadius: 8; plate: true; onClicked: appRoot.pickColor(appRoot.customAccent, function(value) { appRoot.customAccent = value; appRoot.themeChoice = "Custom" }, appRoot.tr("Accent Color")) }
                    }
                    SettingsRow {
                        symbol: "paintpalette"; tileColor: "#BF5AF2"; title: appRoot.tr("Switches use accent color")
                        GlassSwitch { checked: appRoot.accentSwitches; onToggled: appRoot.accentSwitches = checked }
                    }
                    SettingsRow {
                        id: systemFontRow
                        symbol: "doc.on.doc"; tileColor: "#0A84FF"; title: appRoot.tr("macOS system font (SF Pro)")
                        // The font actually in use (set at startup) vs. the switch.
                        readonly property bool inUse: appRoot.systemFontFamily.length > 0 && Qt.application.font.family === appRoot.systemFontFamily
                        value: appRoot.systemFontFamily.length === 0 ? appRoot.tr("Not installed")
                               : appRoot.useSystemFont !== inUse ? appRoot.tr("Restart to apply") : ""
                        GlassSwitch {
                            enabled: appRoot.systemFontFamily.length > 0
                            checked: appRoot.useSystemFont
                            onToggled: appRoot.useSystemFont = checked
                        }
                    }
                    SettingsRow {
                        symbol: "photo"; tileColor: "#32ADE6"; title: appRoot.tr("Background")
                        last: appRoot.backgroundMode !== "Custom" && appRoot.backgroundMode !== "Custom color"
                        GlassSelect {
                            width: 160; options: ["White", "Gray", "Black", "Custom", "Custom color"]
                            selected: appRoot.backgroundMode
                            onChosen: function(value) { appRoot.backgroundMode = value }
                        }
                    }
                    SettingsBlock {
                        visible: appRoot.backgroundMode === "Custom"
                        last: true
                        Row {
                            width: parent.width; spacing: 10
                            GroupButton { text: appRoot.tr("Choose image…"); onClicked: backgroundFileDialog.open() }
                            GlassText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 140; elide: Text.ElideMiddle
                                text: /\/themes\/wallpapers\/[0-9a-f]{64}\.(png|jpg)$/.test(appRoot.backgroundImage) ? appRoot.tr("Theme wallpaper") : appRoot.backgroundImage.length ? decodeURIComponent(appRoot.backgroundImage.split("/").pop()) : appRoot.tr("No image selected")
                                color: appRoot.muted; font.pixelSize: 12
                            }
                        }
                        Row {
                            width: parent.width; spacing: 10
                            GlassText { anchors.verticalCenter: parent.verticalCenter; text: appRoot.tr("Placement"); color: appRoot.ink; font.pixelSize: 14; width: parent.width - 170 }
                            GlassSelect {
                                width: 160; options: ["Fill", "Fit", "Stretch", "Center", "Tile"]
                                selected: appRoot.backgroundPlacement
                                onChosen: function(value) { appRoot.backgroundPlacement = value }
                            }
                        }
                    }
                    SettingsBlock {
                        visible: appRoot.backgroundMode === "Custom color"
                        last: true
                        // Apple form rows: label leading, control trailing.
                        RowLayout {
                            width: parent.width
                            GlassText { text: appRoot.tr("Style"); color: appRoot.ink; font.pixelSize: 13; Layout.fillWidth: true }
                            GlassSelect {
                                Layout.preferredWidth: 160; options: ["Solid","Gradient"]
                                selected: appRoot.customGradient ? "Gradient" : "Solid"
                                onChosen: function(value) { appRoot.customGradient = value === "Gradient" }
                            }
                        }
                        RowLayout {
                            visible: !appRoot.customGradient; width: parent.width
                            GlassText { text: appRoot.tr("Color"); color: appRoot.ink; font.pixelSize: 13; Layout.fillWidth: true }
                            ColorHexField {
                                Layout.preferredWidth: 160
                                swatch: appRoot.customColorStart
                                text: appRoot.customColorStart.toString()
                                onTextEdited: if (/^#[0-9a-fA-F]{6}$/.test(text)) appRoot.customColorStart = text
                                onPicked: function(value) { appRoot.customColorStart = value }
                            }
                        }
                        Repeater {
                            // Counted model: moving a stop rewrites gradientStopsJson, and
                            // an array model would rebuild the row (and drop the slider's
                            // press) on every step.
                            model: appRoot.customGradient ? appRoot.gradientStops.length : 0
                            delegate: RowLayout {
                                required property int index
                                readonly property var stop: appRoot.gradientStops[index] || ({color: "#000000", position: 0})
                                width: parent.width; spacing: 12
                                ColorHexField {
                                    Layout.preferredWidth: 130; swatch: stop.color; text: stop.color
                                    onEditingFinished: if (/^#[0-9a-fA-F]{6}$/.test(text)) appRoot.updateGradientStop(index, text)
                                    onPicked: function(value) { appRoot.updateGradientStop(index, value) }
                                }
                                GlassSlider { Layout.fillWidth: true; from: 0; to: 1; value: stop.position; onMoved: appRoot.updateGradientStop(index, "", value) }
                                // macOS list remove button: small round minus.
                                CircleGlyphButton { glyph: "−"; enabled: appRoot.gradientStops.length > 2; onClicked: appRoot.removeGradientStop(index) }
                            }
                        }
                        ConnectionButton { visible: appRoot.customGradient; text: appRoot.tr("Add Color Stop"); onClicked: appRoot.addGradientStop() }
                        RowLayout {
                            visible: appRoot.customGradient; width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Angle"); color: appRoot.ink; font.pixelSize: 13 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 360
                                // Common angles every 45°, with macOS tick snapping.
                                tickValues: [0, 45, 90, 135, 180, 225, 270, 315, 360]
                                value: appRoot.customGradientAngle
                                onMoved: appRoot.customGradientAngle = snapToTick(value)
                            }
                            // Typed angle, like the memory field; applied on Return or focus loss.
                            GroupField {
                                id: angleField
                                Layout.preferredWidth: 64
                                horizontalAlignment: Text.AlignRight; rightPadding: 22
                                validator: IntValidator { bottom: 0; top: 360 }
                                onEditingFinished: if (acceptableInput) appRoot.customGradientAngle = Number(text)
                                onAccepted: focus = false
                                Keys.onEscapePressed: focus = false
                                GlassText { anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; text: "°"; color: appRoot.muted }
                                // Follows the slider except while being typed in.
                                Binding on text { when: !angleField.activeFocus; value: String(Math.round(appRoot.customGradientAngle)); restoreMode: Binding.RestoreNone }
                            }
                        }
                    }
                }
                SettingsSection {
                    SettingsRow {
                        symbol: "questionmark.circle"; tileColor: "#8E8E93"; title: appRoot.tr("Show sidebar guide")
                        chevron: true; last: true
                        onClicked: appRoot.showSidebarGuide()
                    }
                }

                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionLayout; text: appRoot.tr("Layout") }
                SettingsSection {
                    SettingsRow {
                        symbol: "square.grid.2x2"; tileColor: "#0A84FF"; title: appRoot.tr("Grouped layout")
                        GlassSwitch { checked: appRoot.groupedLayoutEnabled; onToggled: appRoot.groupedLayoutEnabled = checked }
                    }
                    SettingsRow {
                        symbol: "list.bullet"; tileColor: "#5E5CE6"; title: appRoot.tr("Group by")
                        GlassSelect {
                            width: 190
                            options: ["Off", "Smart", "Minecraft version", "Mod loader", "Installed status", "Custom"]
                            selected: appRoot.groupingMethod
                            onChosen: function(value) { appRoot.groupingMethod = value }
                        }
                    }
                    SettingsRow {
                        symbol: "bolt.fill"; tileColor: "#FF9F0A"; title: appRoot.tr("Quick cards")
                        GlassSwitch { checked: appRoot.quickCards; onToggled: appRoot.quickCards = checked }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#FFD60A"; title: appRoot.tr("Card glow")
                        value: appRoot.cardGlow < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.cardGlow * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                // Snap tick at the default strength.
                                tickValues: [0.85]
                                value: appRoot.cardGlow
                                onMoved: appRoot.cardGlow = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    // Default for cards whose Liquid Glass is tinted (an instance
                    // can set its own in Edit › Background).
                    SettingsRow {
                        symbol: "paintpalette"; tileColor: "#BF5AF2"; title: appRoot.tr("Card glass tint")
                        value: Math.round(appRoot.cardGlassTintOpacity * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Faint"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0.05; to: 1; stepSize: 0.01
                                tickValues: [0.6]
                                value: appRoot.cardGlassTintOpacity
                                onMoved: appRoot.cardGlassTintOpacity = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    // Section titles, captions and other text on the wallpaper.
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#3A3A3C"; title: appRoot.tr("Text shadow")
                        value: appRoot.textShadow < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.textShadow * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                tickValues: [0.85]
                                value: appRoot.textShadow
                                onMoved: appRoot.textShadow = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#0A84FF"; title: appRoot.tr("Selection glow")
                        GlassSwitch { checked: appRoot.selectionGlow; onToggled: appRoot.selectionGlow = checked }
                    }
                    // How far a selected card lifts on its spring.
                    SettingsRow {
                        symbol: "arrow.down.to.line"; tileColor: "#30D158"; title: appRoot.tr("Selection lift")
                        value: appRoot.selectionLift < 0.001 ? appRoot.tr("Off") : "+" + Math.round(appRoot.selectionLift * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 0.08; stepSize: 0.005
                                tickValues: [0.03]
                                value: appRoot.selectionLift
                                onMoved: appRoot.selectionLift = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    // Liquid Glass cards (quick download, glass backgrounds); frost,
                    // blur and dimming also apply to Settings panes and the sidebar.
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#64D2FF"; title: appRoot.tr("Card glass frost")
                        value: Math.round(appRoot.cardGlassFrost * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Clear"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                tickValues: [0.75]
                                value: appRoot.cardGlassFrost
                                onMoved: appRoot.cardGlassFrost = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Frosted"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#64D2FF"; title: appRoot.tr("Card glass blur")
                        value: appRoot.cardGlassBlur < 0.5 ? appRoot.tr("Off") : Math.round(appRoot.cardGlassBlur) + " px"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 48; stepSize: 1
                                tickValues: [22]
                                value: appRoot.cardGlassBlur
                                onMoved: appRoot.cardGlassBlur = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#5E5CE6"; title: appRoot.tr("Card glass dimming")
                        value: appRoot.cardGlassDimming < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.cardGlassDimming * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 0.7; stepSize: 0.01
                                tickValues: [0.4]
                                value: appRoot.cardGlassDimming
                                onMoved: appRoot.cardGlassDimming = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "list.bullet"; tileColor: "#8E8E93"; title: appRoot.tr("Card glass caption contrast")
                        value: appRoot.cardGlassCaption < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.cardGlassCaption * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 0.6; stepSize: 0.01
                                tickValues: [0.3]
                                value: appRoot.cardGlassCaption
                                onMoved: appRoot.cardGlassCaption = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    // The dark shade under a card's name and version.
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#636366"; title: appRoot.tr("Caption shade")
                        value: appRoot.cardCaptionShade < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.cardCaptionShade * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1.4; stepSize: 0.01
                                tickValues: [1]
                                value: appRoot.cardCaptionShade
                                onMoved: appRoot.cardCaptionShade = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "list.bullet"; tileColor: "#5E5CE6"; title: appRoot.tr("Vertical instance picker")
                        GlassSwitch { checked: appRoot.pickerVertical; onToggled: appRoot.pickerVertical = checked }
                    }
                    // Behind the dock's instance fan.
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#64D2FF"; title: appRoot.tr("Instance picker blur")
                        value: appRoot.pickerBlurAmount < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.pickerBlurAmount * 100) + "%"
                    }
                    SettingsBlock {
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                tickValues: [0.8]
                                value: appRoot.pickerBlurAmount
                                onMoved: appRoot.pickerBlurAmount = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#8E8E93"; title: appRoot.tr("Instance picker shadow")
                        value: appRoot.pickerShadowAmount < 0.01 ? appRoot.tr("Off") : Math.round(appRoot.pickerShadowAmount * 100) + "%"
                    }
                    SettingsBlock {
                        last: true
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Off"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                tickValues: [0.5]
                                value: appRoot.pickerShadowAmount
                                onMoved: appRoot.pickerShadowAmount = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Strong"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                }

                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionMemory; text: appRoot.tr("Memory") }
                SettingsSection {
                    SettingsRow {
                        symbol: "memorychip"; tileColor: "#30D158"; title: appRoot.tr("Maximum memory")
                        value: appRoot.clampMemory(appRoot.globalMemoryMiB) + appRoot.tr(" MiB")
                    }
                    SettingsBlock {
                        last: !prismBridge.memoryOptimizerAvailable
                        MemoryAllocation {
                            width: parent.width; allocation: appRoot.globalMemoryMiB
                            onCommitted: function(value) { appRoot.globalMemoryMiB = value }
                        }
                        GlassText { width: parent.width; wrapMode: Text.Wrap; text: appRoot.memoryStatus; color: appRoot.muted; font.pixelSize: 12 }
                    }
                    // Windows: free memory before the game starts (MemoryOptimizer.h).
                    SettingsRow {
                        visible: !!prismBridge.memoryOptimizerAvailable
                        symbol: "sparkles"; tileColor: "#64D2FF"; title: appRoot.tr("Optimize memory before launching")
                        GlassSwitch { checked: appRoot.optimizeMemoryBeforeLaunch; onToggled: appRoot.optimizeMemoryBeforeLaunch = checked }
                    }
                    SettingsRow {
                        visible: !!prismBridge.memoryOptimizerAvailable
                        symbol: "memorychip"; tileColor: "#8E8E93"; title: appRoot.tr("Optimize memory now"); last: true
                        GroupButton {
                            text: prismBridge.optimizingMemory ? appRoot.tr("Optimizing…") : appRoot.tr("Optimize Now")
                            enabled: !prismBridge.optimizingMemory
                            onClicked: prismBridge.optimizeMemory()
                        }
                    }
                }
                SettingsCaption {
                    visible: !!prismBridge.memoryOptimizerAvailable
                    text: (prismBridge.optimizingMemory || prismBridge.status.indexOf(appRoot.tr("Memory optimized · freed %1 MB").split("%1")[0]) === 0
                           || prismBridge.status === appRoot.tr("Full memory optimization needs administrator permission.") ? prismBridge.status + "\n" : "")
                          + appRoot.tr("Before launching, memory held by your other apps is freed without an administrator prompt. Optimize Now also clears the system file cache and asks for administrator permission.")
                }

                // ---- Storage: where instances and Java downloads are kept ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionStorage; text: appRoot.tr("Storage") }
                SettingsSection {
                    SettingsRow {
                        symbol: "folder"; tileColor: "#0A84FF"; title: appRoot.tr("Instance folder")
                        GroupButton { text: appRoot.tr("Open"); onClicked: prismBridge.openStorageFolder("InstanceDir") }
                        GroupButton { text: appRoot.tr("Change…"); onClicked: instanceFolderDialog.open() }
                    }
                    SettingsBlock {
                        GlassText { width: parent.width; wrapMode: Text.WrapAnywhere; text: appRoot.storagePath("InstanceDir"); color: appRoot.muted; font.pixelSize: 12 }
                    }
                    SettingsRow {
                        symbol: "folder"; tileColor: "#FF9F0A"; title: appRoot.tr("Java download folder")
                        GroupButton { text: appRoot.tr("Open"); onClicked: prismBridge.openStorageFolder("JavaDir") }
                        GroupButton { text: appRoot.tr("Change…"); onClicked: javaFolderDialog.open() }
                    }
                    SettingsBlock {
                        last: true
                        GlassText { width: parent.width; wrapMode: Text.WrapAnywhere; text: appRoot.storagePath("JavaDir"); color: appRoot.muted; font.pixelSize: 12 }
                    }
                }
                SettingsCaption {
                    text: (appRoot.storageError ? appRoot.storageError + "\n" : "")
                          + appRoot.tr("New instances go to the instance folder. Existing instances stay where they are and remain in your list.")
                }

                // ---- Launch: what happens around starting the game ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionLaunch; text: appRoot.tr("Launch") }
                SettingsSection {
                    SettingsRow {
                        symbol: "play.fill"; tileColor: "#30D158"; title: appRoot.tr("After the game starts")
                        GlassSelect {
                            width: 210; options: ["Stay open", "Minimize", "Minimize until it exits"]
                            selected: appRoot.afterLaunch
                            onChosen: function(value) { appRoot.afterLaunch = value }
                        }
                    }
                    SettingsRow {
                        visible: appRoot.customWindowChrome
                        symbol: "cpu"; tileColor: "#FF9F0A"; title: appRoot.tr("Game process priority")
                        GlassSelect {
                            width: 210; options: ["Below normal", "Normal", "Above normal", "High"]
                            selected: options[appRoot.processPriority]
                            onChosen: function(value) { appRoot.processPriority = options.indexOf(value) }
                        }
                    }
                    SettingsRow {
                        symbol: "square.grid.2x2"; tileColor: "#5E5CE6"; title: appRoot.tr("Game window size")
                        GlassSelect {
                            width: 210; options: ["Default", "Maximized", "Custom"]
                            selected: appRoot.customWindowSize ? "Custom" : appRoot.windowSizeMode
                            onChosen: function(value) { appRoot.setWindowSizeMode(value) }
                        }
                    }
                    SettingsBlock {
                        visible: appRoot.customWindowSize || appRoot.windowSizeMode === "Custom"
                        RowLayout {
                            width: parent.width; spacing: 10
                            GlassText { text: appRoot.tr("Width"); color: appRoot.ink; font.pixelSize: 13; Layout.fillWidth: true }
                            CoreSettingField { key: "MinecraftWinWidth"; fallback: "854"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; validator: IntValidator { bottom: 1; top: 16384 } }
                            GlassText { text: "×"; color: appRoot.muted; font.pixelSize: 13 }
                            CoreSettingField { key: "MinecraftWinHeight"; fallback: "480"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; validator: IntValidator { bottom: 1; top: 16384 } }
                            GlassText { text: appRoot.tr("Height"); color: appRoot.ink; font.pixelSize: 13 }
                        }
                    }
                    SettingsRow {
                        symbol: "doc.on.doc"; tileColor: "#64D2FF"; title: appRoot.tr("Version text")
                        CoreSettingField { key: "CustomVersionType"; width: 210; placeholderText: appRoot.tr("Release") }
                    }
                    SettingsRow {
                        symbol: "bolt.fill"; tileColor: "#FF453A"; title: appRoot.tr("Use discrete graphics")
                        GlassSwitch { checked: !!appRoot.core("UseDiscreteGpu"); onToggled: appRoot.setCore("UseDiscreteGpu", checked) }
                    }
                    SettingsRow {
                        symbol: "doc.on.doc"; tileColor: "#30B0C7"; title: appRoot.tr("Default options.txt")
                        last: !defaultOptionsRow.visible
                        GlassSwitch { checked: !!appRoot.core("DefaultOptionsEnabled"); onToggled: appRoot.setCore("DefaultOptionsEnabled", checked) }
                    }
                    SettingsRow {
                        id: defaultOptionsRow
                        readonly property string path: String(appRoot.core("DefaultOptionsFile") || "")
                        // Re-read while Settings is open: the file can change outside the launcher.
                        readonly property var file: (appRoot.activePage, prismBridge.inspectOptionsFile(path))
                        visible: !!appRoot.core("DefaultOptionsEnabled")
                        symbol: "doc.on.clipboard"; tileColor: "#8E8E93"; title: appRoot.tr("Options file"); last: true
                        value: path.length ? file.name : appRoot.tr("Not selected")
                        GroupButton { text: appRoot.tr("Choose…"); implicitHeight: 26; cornerRadius: 8; plate: true; onClicked: defaultOptionsDialog.open() }
                    }
                }
                SettingsCaption { text: appRoot.tr("Version text replaces “Release” at the bottom of the title screen. Process priority applies once the game window is starting.") }
                SettingsCaption {
                    text: appRoot.tr("After you turn this on or choose another file, each instance’s options.txt is replaced with a copy of it once, on its next launch. Changes made in game after that are kept. Turn off “Use default options.txt” in an instance’s settings to skip it.")
                }
                SettingsCaption {
                    visible: defaultOptionsRow.visible && defaultOptionsRow.path.length > 0
                    text: !defaultOptionsRow.file.exists ? appRoot.tr("This file can’t be found, so nothing will be copied.")
                          : !defaultOptionsRow.file.version ? appRoot.tr("This file has no version line. The game will discard it and use its own defaults.")
                          : appRoot.tr("%1 · data version %2").replace("%1", defaultOptionsRow.path).replace("%2", defaultOptionsRow.file.version)
                }

                // ---- Java: runtime and JVM options ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionJava; text: appRoot.tr("Java") }
                SettingsSection {
                    SettingsRow {
                        id: javaRow
                        symbol: "cpu"; tileColor: "#FF9F0A"; title: appRoot.tr("Java runtime")
                        readonly property var javaOptions: ["Automatic"].concat(appRoot.javaList.map(function(j) { return "Java " + j.version + " · " + j.path }))
                        readonly property string currentPath: String(appRoot.core("JavaPath") || "")
                        Component.onCompleted: if (!appRoot.javaList.length) prismBridge.refreshJavaInstalls()
                        GlassSelect {
                            width: 260; options: javaRow.javaOptions
                            selected: {
                                if (appRoot.core("AutomaticJavaSwitch")) return "Automatic"
                                for (var i = 0; i < appRoot.javaList.length; i++)
                                    if (appRoot.javaList[i].path === javaRow.currentPath) return javaRow.javaOptions[i + 1]
                                return javaRow.currentPath.length ? appRoot.tr("Java · ") + javaRow.currentPath : "Automatic"
                            }
                            onChosen: function(value) {
                                var index = javaRow.javaOptions.indexOf(value)
                                if (index <= 0) { appRoot.setCore("AutomaticJavaSwitch", true); return }
                                appRoot.setCore("JavaPath", appRoot.javaList[index - 1].path)
                                appRoot.setCore("AutomaticJavaSwitch", false)
                            }
                        }
                        // Rescan for installed runtimes.
                        CircleGlyphButton {
                            // Same height as the pop-up button beside it, centred in
                            // the row (a Row only top-aligns its children).
                            implicitWidth: 34; implicitHeight: 34
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "↻"; enabled: !appRoot.javaScanning
                            onClicked: prismBridge.refreshJavaInstalls()
                        }
                    }
                    SettingsRow {
                        symbol: "arrow.down.circle"; tileColor: "#0A84FF"; title: appRoot.tr("Download Java automatically")
                        GlassSwitch { checked: !!appRoot.core("AutomaticJavaDownload"); onToggled: appRoot.setCore("AutomaticJavaDownload", checked) }
                    }
                    SettingsRow {
                        symbol: "memorychip"; tileColor: "#30D158"; title: appRoot.tr("Garbage collector")
                        GlassSelect {
                            width: 210; options: ["Default", "G1GC (tuned)", "ZGC", "Shenandoah"]
                            selected: appRoot.gcPresetOf(appRoot.core("JvmArgs"))
                            onChosen: function(value) { appRoot.applyGcPreset(value) }
                        }
                    }
                    SettingsRow { symbol: "list.bullet"; tileColor: "#8E8E93"; title: appRoot.tr("JVM arguments") }
                    SettingsBlock {
                        SettingsTextArea {
                            width: parent.width; height: Math.max(64, implicitHeight)
                            source: String(appRoot.core("JvmArgs") || "")
                            placeholderText: "-XX:+UseG1GC …"
                            onCommitted: function(value) { appRoot.setCore("JvmArgs", value.trim()) }
                        }
                    }
                    SettingsRow { symbol: "play.fill"; tileColor: "#8E8E93"; title: appRoot.tr("Pre-launch command") }
                    SettingsBlock {
                        CoreSettingField { key: "PreLaunchCommand"; width: parent.width; placeholderText: appRoot.tr("Runs before the game starts") }
                    }
                    SettingsRow { symbol: "link"; tileColor: "#8E8E93"; title: appRoot.tr("Wrapper command") }
                    SettingsBlock {
                        CoreSettingField { key: "WrapperCommand"; width: parent.width; placeholderText: appRoot.tr("Launches the game through this command") }
                    }
                    SettingsRow { symbol: "xmark"; tileColor: "#8E8E93"; title: appRoot.tr("Post-exit command") }
                    SettingsBlock {
                        last: true
                        CoreSettingField { key: "PostExitCommand"; width: parent.width; placeholderText: appRoot.tr("Runs after the game exits") }
                    }
                }

                // ---- Downloads: source, speed test, parallelism and speed limit (PCL2-style) ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionDownloads; text: appRoot.tr("Downloads") }
                SettingsSection {
                    id: downloadSection
                    // Last speed test (bytes/s per source, 0 = unreachable).
                    property var speeds: prismBridge.downloadSourceSpeeds()
                    property bool testing: prismBridge.testingDownloadSources()
                    readonly property bool tested: speeds !== undefined && speeds.gameOfficial !== undefined
                    Connections {
                        target: prismBridge
                        function onDownloadSourcesTesting() { downloadSection.testing = true }
                        function onDownloadSourcesTested(speeds) { downloadSection.speeds = speeds; downloadSection.testing = false }
                    }
                    function speedText(bytesPerSecond) {
                        if (!(bytesPerSecond > 0)) return appRoot.tr("Unreachable")
                        var mb = bytesPerSecond / 1048576
                        return mb >= 1 ? mb.toFixed(1) + " MB/s" : Math.max(1, Math.round(bytesPerSecond / 1024)) + " KB/s"
                    }
                    function pair(official, mirror) {
                        return appRoot.tr("Official %1 · mirror %2").replace("%1", speedText(official)).replace("%2", speedText(mirror))
                    }
                    SettingsRow {
                        id: downloadSourceRow; symbol: "arrow.down.circle"; tileColor: "#30D158"; title: appRoot.tr("Download source")
                        // Shown order → DownloadMirror value (net/DownloadMirror.h).
                        readonly property var values: [3, 0, 1, 2]
                        GlassSelect {
                            width: 260
                            options: ["Automatic (fastest)", "Official servers", "Mirror first", "Official first, mirror as backup"]
                            selected: options[Math.max(0, downloadSourceRow.values.indexOf(Number(appRoot.core("DownloadMirror")) || 0))]
                            onChosen: function(value) {
                                var mode = downloadSourceRow.values[options.indexOf(value)]
                                appRoot.setCore("DownloadMirror", mode)
                                if (mode === 3 && !downloadSection.tested) prismBridge.testDownloadSources()
                            }
                        }
                    }
                    SettingsRow {
                        symbol: "bolt.fill"; tileColor: "#FF9F0A"; title: appRoot.tr("Speed test")
                        value: downloadSection.testing ? appRoot.tr("Testing…") : ""
                        GroupButton {
                            text: appRoot.tr("Start test"); implicitHeight: 26; cornerRadius: 8; plate: true
                            enabled: !downloadSection.testing
                            onClicked: prismBridge.testDownloadSources()
                        }
                    }
                    SettingsRow {
                        visible: downloadSection.tested
                        symbol: "square.grid.2x2"; tileColor: "#8E8E93"; title: appRoot.tr("Game files")
                        value: downloadSection.tested ? downloadSection.pair(downloadSection.speeds.gameOfficial, downloadSection.speeds.gameMirror) : ""
                    }
                    SettingsRow {
                        visible: downloadSection.tested
                        symbol: "square.grid.2x2"; tileColor: "#8E8E93"; title: appRoot.tr("Mod files")
                        value: downloadSection.tested ? downloadSection.pair(downloadSection.speeds.modOfficial, downloadSection.speeds.modMirror) : ""
                    }
                    SettingsRow {
                        symbol: "list.bullet"; tileColor: "#5E5CE6"; title: appRoot.tr("Simultaneous downloads")
                        GlassSelect {
                            width: 120
                            options: ["2", "4", "6", "8", "12", "16", "24", "32"]
                            selected: String(Number(appRoot.core("NumberOfConcurrentDownloads")) || 6)
                            onChosen: function(value) { appRoot.setCore("NumberOfConcurrentDownloads", Number(value)) }
                        }
                    }
                    SettingsRow {
                        id: speedLimitRow; symbol: "arrow.down.to.line"; tileColor: "#0A84FF"; title: appRoot.tr("Download speed limit")
                        last: true
                        // KiB/s; 0 = unlimited (net/DownloadThrottle.h).
                        readonly property var limits: [0, 1024, 2048, 5120, 10240, 20480, 51200]
                        GlassSelect {
                            width: 160
                            options: ["Unlimited", "1 MB/s", "2 MB/s", "5 MB/s", "10 MB/s", "20 MB/s", "50 MB/s"]
                            selected: {
                                var index = speedLimitRow.limits.indexOf(Number(appRoot.core("DownloadSpeedLimit")) || 0)
                                return index >= 0 ? options[index] : Math.round(Number(appRoot.core("DownloadSpeedLimit")) / 1024) + " MB/s"
                            }
                            onChosen: function(value) { appRoot.setCore("DownloadSpeedLimit", speedLimitRow.limits[options.indexOf(value)]) }
                        }
                    }
                }
                SettingsCaption {
                    text: appRoot.tr("Game and mod loader files are mirrored by BMCLAPI, mod files from Modrinth and CurseForge by MCIM. Automatic tests both and uses the faster one; whenever a source fails, the other is tried. Changes to simultaneous downloads and the speed limit apply to downloads that start afterwards.")
                }

                // ---- Translation of project text ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionTranslation; text: appRoot.tr("Translation") }
                SettingsSection {
                    SettingsRow {
                        symbol: "list.bullet"; tileColor: "#0A84FF"; title: appRoot.tr("Translate descriptions automatically"); last: true
                        GlassSwitch { checked: appRoot.autoTranslateDescriptions; onToggled: appRoot.autoTranslateDescriptions = checked }
                    }
                }
                SettingsCaption {
                    text: appRoot.tr("Project summaries and descriptions on the Download page are translated into the launcher language (Core language) with Google Translate. Translations are cached on this computer.")
                }

                // ---- Updates ----
                Item { width: 1; height: 14 }
                SettingsCaption { id: settingsCaptionUpdates; text: appRoot.tr("Updates") }
                SettingsSection {
                    id: updateSection
                    // Re-read the updater after each change.
                    property int revision: 0
                    // The updater starts shortly after the interface; re-read then.
                    readonly property bool available: { revision; return prismBridge.updaterAvailable() }
                    Connections { target: prismBridge; function onUpdateStateChanged() { updateSection.revision++ } }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Vitra Launcher")
                        value: prismBridge.launcherVersion()
                    }
                    // The project's repository: source, releases and issues.
                    SettingsRow {
                        symbol: "link"; tileColor: "#1D1D1F"; title: "GitHub"
                        value: "Davizcbia/Vitra-Launcher"
                        chevron: true
                        last: !updateSection.available
                        onClicked: Qt.openUrlExternally("https://github.com/Davizcbia/Vitra-Launcher")
                    }
                    SettingsRow {
                        visible: updateSection.available
                        symbol: "arrow.down.to.line"; tileColor: "#0A84FF"; title: appRoot.tr("Check for updates automatically")
                        GlassSwitch {
                            checked: { updateSection.revision; return prismBridge.autoUpdateChecks() }
                            onToggled: { prismBridge.setAutoUpdateChecks(checked); updateSection.revision++ }
                        }
                    }
                    SettingsRow {
                        visible: updateSection.available
                        symbol: "list.bullet"; tileColor: "#5E5CE6"; title: appRoot.tr("Check")
                        GlassSelect {
                            readonly property var hours: [0, 1, 6, 24, 168]
                            width: 210; options: ["On launch", "Every hour", "Every 6 hours", "Every day", "Every week"]
                            enabled: { updateSection.revision; return prismBridge.autoUpdateChecks() }
                            selected: { updateSection.revision; var i = hours.indexOf(prismBridge.updateCheckHours()); return options[i < 0 ? 3 : i] }
                            onChosen: function(value) { prismBridge.setUpdateCheckHours(hours[options.indexOf(value)]); updateSection.revision++ }
                        }
                    }
                    // Off: an automatic check that finds an update opens no
                    // dialog; the Settings badge shows it.
                    SettingsRow {
                        visible: updateSection.available
                        symbol: "questionmark.circle"; tileColor: "#FF9F0A"; title: appRoot.tr("Show update alerts")
                        GlassSwitch {
                            checked: { updateSection.revision; return prismBridge.updateAlerts() }
                            onToggled: { prismBridge.setUpdateAlerts(checked); updateSection.revision++ }
                        }
                    }
                    SettingsRow {
                        visible: updateSection.available
                        symbol: "arrow.down.circle"; tileColor: "#30D158"; title: appRoot.tr("Check for Updates Now")
                        chevron: true; last: true
                        onClicked: prismBridge.checkForUpdates()
                    }
                }
                SettingsCaption {
                    visible: !updateSection.available
                    text: appRoot.tr("This build has no updater. Install a release build to receive updates.")
                }

                // Glass Lab interface: parameters copied with the lab's "复制参数"
                // paste here, and "Copy parameters" goes back into "导入参数".
                Item { width: 1; height: 14; visible: Qt.platform.os === "windows" }
                SettingsCaption { id: settingsCaptionGlass; visible: Qt.platform.os === "windows"; text: appRoot.tr("Liquid Glass") }
                SettingsSection {
                    visible: Qt.platform.os === "windows"
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#8E8E93"; title: appRoot.tr("Show Liquid Glass settings"); last: true
                        GlassSwitch { checked: appRoot.glassSettingsVisible; onToggled: appRoot.glassSettingsVisible = checked }
                    }
                }
                // Liquid Glass presets: kept apart from themes.
                SettingsSection {
                    visible: Qt.platform.os === "windows"
                    SettingsRow {
                        id: glassPresetRow
                        symbol: "sparkles"; tileColor: "#FF9F0A"; title: appRoot.tr("Liquid Glass preset")
                        readonly property var choices: [""].concat(["custom"], appRoot.glassPresets.map(function(p) { return p.name }))
                        function label(choice) { return choice === "" ? appRoot.tr("Follow theme") : choice === "custom" ? appRoot.tr("Keep current") : choice }
                        GlassSelect {
                            width: 210
                            options: glassPresetRow.choices.map(glassPresetRow.label)
                            selected: glassPresetRow.label(appRoot.glassPresetChoice)
                            onChosen: function(value) { appRoot.chooseGlassPreset(glassPresetRow.choices[options.indexOf(value)]) }
                        }
                    }
                    SettingsRow {
                        symbol: "doc.on.doc"; tileColor: "#30D158"; title: appRoot.tr("Save current as preset…")
                        chevron: true; last: appRoot.glassPresetIndex(appRoot.glassPresetChoice) < 0
                        onClicked: saveGlassPresetPopup.open()
                    }
                    SettingsRow {
                        visible: appRoot.glassPresetIndex(appRoot.glassPresetChoice) >= 0
                        symbol: "xmark"; tileColor: "#FF453A"; title: appRoot.tr("Delete preset “%1”").replace("%1", appRoot.glassPresetChoice)
                        chevron: true; last: true
                        onClicked: appRoot.deleteGlassPreset(appRoot.glassPresetChoice)
                    }
                }
                SettingsCaption {
                    visible: Qt.platform.os === "windows"
                    font.pixelSize: 12
                    text: appRoot.glassPresetLocked
                        ? appRoot.tr("Themes no longer change Liquid Glass. Changes you make are kept") + (appRoot.glassPresetIndex(appRoot.glassPresetChoice) >= 0 ? appRoot.tr(" and saved to this preset.") : ".")
                        : appRoot.tr("Applying a theme also applies its Liquid Glass. Choose a preset or Keep current to keep your own.")
                }
                SettingsSection {
                    visible: Qt.platform.os !== "windows" || appRoot.showGlassSettings
                    // On Windows this is the Liquid Glass frost (Glass Lab "雾化").
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#5E5CE6"; title: appRoot.tr("Glass appearance")
                        value: Math.round((appRoot.liquidGlass ? glassTuning.frost : appRoot.glassOpacity) * 100) + "%"
                        last: false
                    }
                    SettingsBlock {
                        last: !appRoot.liquidGlass
                        // macOS Accessibility style: end labels inline with the slider.
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Clear"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01
                                value: appRoot.liquidGlass ? glassTuning.frost : appRoot.glassOpacity
                                onMoved: if (appRoot.liquidGlass) glassTuning.frost = value; else appRoot.glassOpacity = value
                            }
                            GlassText { text: appRoot.tr("Frosted"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                    // Liquid Glass brightness (Glass Lab "brightness"), Dark ↔ Light,
                    // with a snap tick at the neutral default.
                    SettingsRow {
                        visible: appRoot.liquidGlass
                        symbol: "circle.lefthalf.filled"; tileColor: "#8E8E93"; title: appRoot.tr("Glass tone")
                        value: glassTuning.brightness < 0.97 ? appRoot.tr("Darker") : glassTuning.brightness > 1.03 ? appRoot.tr("Lighter") : appRoot.tr("Neutral")
                    }
                    SettingsBlock {
                        visible: appRoot.liquidGlass
                        last: true
                        RowLayout {
                            width: parent.width; spacing: 12
                            GlassText { text: appRoot.tr("Dark"); color: appRoot.muted; font.pixelSize: 12 }
                            GlassSlider {
                                Layout.fillWidth: true; from: 0; to: 2; stepSize: 0.01
                                tickValues: [1]
                                value: glassTuning.brightness
                                onMoved: glassTuning.brightness = snapToTick(value)
                            }
                            GlassText { text: appRoot.tr("Light"); color: appRoot.muted; font.pixelSize: 12 }
                        }
                    }
                }
                SettingsSection {
                    visible: appRoot.showGlassSettings
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Liquid Glass")
                        GlassSwitch { checked: glassTuning.glassEnabled; onToggled: glassTuning.glassEnabled = checked }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Material style")
                        GlassSelect {
                            width: 210; options: ["Custom", "Regular", "Clear", "Tinted", "Identity"]
                            selected: options[glassTuning.materialVariant]
                            onChosen: function(value) { glassTuning.materialVariant = options.indexOf(value) }
                        }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Frosted Glass")
                        GlassSwitch { checked: glassTuning.frostedMode; onToggled: glassTuning.frostedMode = checked }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Button fusion")
                        GlassSwitch { checked: glassTuning.fusionEnabled; onToggled: glassTuning.fusionEnabled = checked }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#64D2FF"; title: appRoot.tr("Fusion distance")
                        value: Math.round(glassTuning.fusionDistance) + appRoot.tr(" pt")
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 1; to: 100; stepSize: 1; value: glassTuning.fusionDistance; onMoved: glassTuning.fusionDistance = value }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#FF9F0A"; title: appRoot.tr("Lens text refraction range")
                        value: Math.round(glassTuning.lensLabelRange) + appRoot.tr(" pt")
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 8; to: 32; stepSize: 1; value: glassTuning.lensLabelRange; onMoved: glassTuning.lensLabelRange = value }
                    }
                }
                // Built only when shown: these are many controls.
                Repeater {
                    model: appRoot.showGlassSettings ? appRoot.glassParameterGroups : []
                    delegate: Column {
                        id: glassGroup
                        required property var modelData
                        width: parent ? parent.width : 0
                        spacing: parent ? parent.spacing : 0
                        Item { width: 1; height: 14 }
                        SettingsCaption { text: appRoot.tr(glassGroup.modelData.caption) }
                        SettingsSection {
                            Repeater {
                                model: glassGroup.modelData.parameters
                                delegate: Column {
                                    id: glassParameter
                                    required property var modelData
                                    required property int index
                                    readonly property var range: glassTuning.ranges[modelData.key]
                                    readonly property string unit: modelData.unit ? appRoot.tr(modelData.unit) : ""
                                    // Separator after this setting unless it ends the group.
                                    readonly property bool settingsGroupContinues: index < glassGroup.modelData.parameters.length - 1
                                    width: parent ? parent.width : 0
                                    SettingsRow {
                                        symbol: glassGroup.modelData.symbol; tileColor: glassGroup.modelData.tile
                                        title: appRoot.tr(glassParameter.modelData.title)
                                        value: glassTuning[glassParameter.modelData.key].toFixed(glassParameter.modelData.step >= 1 ? 0 : glassParameter.modelData.step >= 0.01 ? 2 : 3) + glassParameter.unit
                                    }
                                    SettingsBlock {
                                        last: glassParameter.index === glassGroup.modelData.parameters.length - 1
                                        GlassSlider {
                                            width: parent.width; from: glassParameter.range[0]; to: glassParameter.range[1]; stepSize: glassParameter.modelData.step
                                            value: glassTuning[glassParameter.modelData.key]
                                            onMoved: glassTuning[glassParameter.modelData.key] = value
                                        }
                                    }
                                    // Under Reflection strength: keep the reflection still.
                                    SettingsRow {
                                        visible: glassParameter.modelData.key === "glare"
                                        symbol: glassGroup.modelData.symbol; tileColor: glassGroup.modelData.tile
                                        title: appRoot.tr("Reflection does not follow the pointer")
                                        GlassSwitch { checked: glassTuning.staticReflection; onToggled: glassTuning.staticReflection = checked }
                                    }
                                }
                            }
                        }
                    }
                }
                Item { width: 1; height: 14; visible: appRoot.showGlassSettings }
                SettingsCaption { visible: appRoot.showGlassSettings; text: appRoot.tr("Accessibility") }
                SettingsSection {
                    visible: appRoot.showGlassSettings
                    Repeater {
                        model: appRoot.glassAccessibilityFlags
                        delegate: SettingsRow {
                            required property var modelData
                            required property int index
                            symbol: "sparkles"; tileColor: "#5E5CE6"; title: appRoot.tr(modelData.title)
                            last: index === appRoot.glassAccessibilityFlags.length - 1
                            GlassSwitch { checked: glassTuning[modelData.key]; onToggled: glassTuning[modelData.key] = checked }
                        }
                    }
                }
                Item { width: 1; height: 14; visible: appRoot.showGlassSettings }
                SettingsCaption { visible: appRoot.showGlassSettings; text: appRoot.tr("Sidebar") }
                SettingsSection {
                    visible: appRoot.showGlassSettings
                    SettingsRow {
                        symbol: "sidebar.left"; tileColor: "#64D2FF"; title: appRoot.tr("Sidebar blur")
                        value: Math.round(glassTuning.sidebarFrost * 100) + "%"
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 0; to: 1; stepSize: 0.01; value: glassTuning.sidebarFrost; onMoved: glassTuning.sidebarFrost = value }
                    }
                    SettingsRow {
                        symbol: "circle.lefthalf.filled"; tileColor: "#FF375F"; title: appRoot.tr("Sidebar glow")
                        value: Math.round(glassTuning.sidebarGlow * 100) + "%"
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 0; to: 1; stepSize: 0.01; value: glassTuning.sidebarGlow; onMoved: glassTuning.sidebarGlow = value }
                    }
                    SettingsRow {
                        symbol: "sidebar.left"; tileColor: "#64D2FF"; title: appRoot.tr("Glow reach from right edge")
                        value: Math.round(glassTuning.sidebarGlowCoverage * 100) + "%"
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 0.2; to: 0.65; stepSize: 0.01; value: glassTuning.sidebarGlowCoverage; onMoved: glassTuning.sidebarGlowCoverage = value }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#BF5AF2"; title: appRoot.tr("Glow sampling width")
                        value: Math.round(glassTuning.sidebarGlowWidth) + appRoot.tr(" pt")
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 80; to: 600; stepSize: 10; value: glassTuning.sidebarGlowWidth; onMoved: glassTuning.sidebarGlowWidth = value }
                    }
                    SettingsRow {
                        symbol: "sparkles"; tileColor: "#64D2FF"; title: appRoot.tr("Glow softness")
                        value: Math.round(glassTuning.sidebarGlowBlur * 100) + "%"
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 0; to: 1; stepSize: 0.01; value: glassTuning.sidebarGlowBlur; onMoved: glassTuning.sidebarGlowBlur = value }
                    }
                    SettingsRow {
                        symbol: "paintpalette"; tileColor: "#FF9F0A"; title: appRoot.tr("Glow saturation")
                        value: Math.round(glassTuning.sidebarGlowSaturation * 100) + "%"
                    }
                    SettingsBlock {
                        GlassSlider { width: parent.width; from: 0; to: 1; stepSize: 0.01; value: glassTuning.sidebarGlowSaturation; onMoved: glassTuning.sidebarGlowSaturation = value }
                    }
                    SettingsRow {
                        symbol: "doc.on.clipboard"; tileColor: "#0A84FF"; title: appRoot.tr("Paste from Glass Lab"); chevron: true
                        onClicked: appRoot.importGlassTuning()
                    }
                    SettingsRow {
                        symbol: "doc.on.doc"; tileColor: "#8E8E93"; title: appRoot.tr("Copy parameters"); chevron: true
                        onClicked: { macWindowMetrics.copyText(JSON.stringify(glassTuning.parameters(), null, 2)); appRoot.glassTuningStatus = appRoot.tr("Parameters copied") }
                    }
                    SettingsRow {
                        symbol: "arrow.uturn.backward"; tileColor: "#FF453A"; title: appRoot.tr("Default parameters"); last: true
                        // Liquid Glass button (Glass Lab press), like the other page actions.
                        GroupButton {
                            glass: true
                            text: appRoot.tr("Reset")
                            onClicked: { glassTuning.reset(); appRoot.glassTuningStatus = appRoot.tr("Restored the default parameters") }
                        }
                    }
                }
                SettingsCaption {
                    visible: appRoot.showGlassSettings
                    topPadding: 6
                    text: (appRoot.glassTuningStatus.length ? appRoot.glassTuningStatus + ". " : "")
                          + appRoot.tr("Uses the Glass Lab JSON format: copy parameters in the lab (复制参数), then paste them here.")
                    font.pixelSize: 12
                }
            }

        }
        }
        // Section rail, the page's scroll bar: one bar per section, the thumb
        // slides across them with the scroll position. A click jumps to a
        // section; dragging scrolls.
        Item {
            id: settingsRail
            readonly property real rowHeight: 34
            readonly property int currentIndex: Math.round(pageContent.railPosition)
            readonly property bool floating: !pageContent.railLabels && railHover.hovered
            readonly property bool showLabels: pageContent.railLabels || floating
            readonly property real barX: pageContent.railLabels ? 0 : width - 4
            readonly property real columnRight: settingsColumn.x + settingsColumn.width
            // Outside contentScene, like the dock: the floating labels' glass
            // refracts the settings behind it, which the scene capture holds.
            parent: bottomDock.parent
            visible: pageContent.visible
            opacity: pageContent.opacity
            z: 84
            // Bars only: the bars keep their place as the rail grows to the left.
            x: pageContent.x + (pageContent.railLabels ? columnRight + 16 : columnRight + 14 - width)
            y: pageContent.y + Math.max(0, (appRoot.panelHeight(pageContent.y) - height) / 2)
            width: pageContent.railLabels ? 96 : floating ? 150 : 16
            height: rowHeight * pageContent.railSections.length
            HoverHandler { id: railHover }
            GlassPane {
                visible: settingsRail.floating
                y: -6; width: parent.width + 8; height: parent.height + 12; radius: 22
                color: appRoot.materialTint
                edgeGlow: false
                rimColor: appRoot.hairline
                frostBoost: sceneFrostTexture.active ? 0.55 : 0
                MouseArea { anchors.fill: parent }
            }
            Repeater {
                model: pageContent.railSections
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool current: settingsRail.currentIndex === index
                    readonly property string label: appRoot.tr(modelData.title)
                    y: index * settingsRail.rowHeight
                    width: settingsRail.width; height: settingsRail.rowHeight
                    Accessible.role: Accessible.Button; Accessible.name: label
                    Rectangle {
                        x: settingsRail.barX; y: 3; width: 4; height: parent.height - 6; radius: 2
                        color: appRoot.ink; opacity: 0.2
                    }
                    BackdropText {
                        x: pageContent.railLabels ? 16 : 12
                        width: parent.width - (pageContent.railLabels ? x : x + 16)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: settingsRail.showLabels
                        horizontalAlignment: pageContent.railLabels ? Text.AlignLeft : Text.AlignRight
                        text: parent.label; elide: Text.ElideRight
                        color: parent.current || railRowHover.hovered ? appRoot.ink : appRoot.muted
                        font.pixelSize: 13; font.bold: parent.current
                    }
                    HoverHandler { id: railRowHover }
                }
            }
            Rectangle {
                x: settingsRail.barX
                y: pageContent.railPosition * settingsRail.rowHeight + 3
                width: 4; height: settingsRail.rowHeight - 6; radius: 2
                color: appRoot.ink
                Behavior on y {
                    enabled: pageContent.railTarget >= 0 && !glassTuning.reducedMotion
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                }
            }
            // A MouseArea, not a TapHandler: the floating labels cover settings
            // rows, which must not receive the click too.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                property real pressY: 0
                property bool dragging: false
                onPressed: function(mouse) { pressY = mouse.y; dragging = false }
                onPositionChanged: function(mouse) {
                    if (!dragging && Math.abs(mouse.y - pressY) < 4) return
                    dragging = true
                    pageContent.scrollToRail(mouse.y / settingsRail.rowHeight - 0.5)
                }
                onClicked: function(mouse) {
                    if (!dragging) pageContent.jumpToSection(Math.max(0, Math.min(pageContent.railSections.length - 1, Math.floor(mouse.y / settingsRail.rowHeight))))
                }
            }
        }
    }


    // Download uses an independent query so instance search remains untouched.
    Item {
        id: downloadPage
        parent: contentScene
        z: 12
        visible: appRoot.activePage === "Download" && !appRoot.downloadSelection
        x: appRoot.contentLeft + 28
        y: appRoot.pageTop()
        width: Math.max(0, appRoot.width - appRoot.contentLeft - 56)
        height: Math.max(0, appRoot.height - y)
        ColumnLayout {
            id: downloadToolbar
            objectName: "downloadToolbar"
            parent: appRoot.contentItem
            x: downloadPage.x; y: downloadPage.y; width: downloadPage.width
            visible: downloadPage.visible
            z: 72; spacing: 12
            RowLayout {
                opacity: macWindowMetrics.nativeGlassDock ? 0 : 1
                enabled: !macWindowMetrics.nativeGlassDock
                Layout.fillWidth: true
                GlassSelect {
                    Layout.preferredWidth: 148
                    Layout.preferredHeight: appRoot.downloadControlHeight
                    controlHeight: appRoot.downloadControlHeight
                    cornerRadius: appRoot.downloadControlRadius
                    glassMaterial: true
                    options: appRoot.downloadProviders
                    selected: appRoot.downloadProvider
                    onChosen: function(value) { appRoot.downloadProvider = value }
                }
                SearchField {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Math.min(360, downloadPage.width * 0.52)
                    Layout.preferredHeight: appRoot.downloadControlHeight
                    placeholderText: appRoot.tr("Search ") + appRoot.tr(appRoot.downloadCategory).toLowerCase() + "…"
                    text: appRoot.downloadSearch
                    onTextEdited: appRoot.downloadSearch = text
                    onAccepted: { appRoot.submitDownloadSearch(text); focus=false }
                    Keys.onEscapePressed: focus=false
                }
                // Categories live in the sidebar: the filters join this row.
                DownloadFilters { visible: appRoot.sidebarDownloadCategories }
            }
            RowLayout {
                visible: !appRoot.sidebarDownloadTools && !appRoot.sidebarDownloadCategories
                opacity: macWindowMetrics.nativeGlassDock ? 0 : 1
                enabled: !macWindowMetrics.nativeGlassDock
                Layout.fillWidth: true
                Layout.preferredHeight: macWindowMetrics.nativeGlassDock ? 44 : 64
                Flickable {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    // The bar insets its capsules by 8 (room for the press
                    // lens); pull it back so they line up with the row above.
                    Layout.leftMargin: -8
                    Layout.preferredHeight: macWindowMetrics.nativeGlassDock ? 44 : 64
                    contentWidth: categoryRow.width+16; contentHeight: height
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    GlassCategoryBar {
                        id: categoryRow
                        x: 8; y: 4; width: implicitWidth; height: 56
                        options: appRoot.downloadCategories; selected: appRoot.downloadCategory
                        foreground: appRoot.ink; accent: appRoot.accentLabel
                        // Selected like the Download button: accent tint, bold accent label.
                        selectedFill: Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, 0.3)
                        reducedMotion: glassTuning.reducedMotion
                        fusionEnabled: glassTuning.fusionEnabled
                        onChosen: function(value) { appRoot.openDownloadCategory(value) }
                        material: appRoot.liquidGlass && glassTuning.materialVisible ? categoryMaterial : null
                        Component {
                            id: categoryMaterial
                            TunedLiquidGlass {
                                surface: categoryRow; viewport: contentScene
                                sharpTexture: sceneSharpTexture
                                blurredTexture: glassTuning.needsBlur ? sceneFrostTexture : sceneSharpTexture
                                radius: 20; capsuleCount: categoryRow.options.length
                                capsuleOne: categoryRow.shape(0); capsuleTwo: categoryRow.shape(1)
                                capsuleThree: categoryRow.shape(2); capsuleFour: categoryRow.shape(3); capsuleFive: categoryRow.shape(4)
                                pressedCapsule: categoryRow.lastPressedIndex
                                capsuleFusionProgress: categoryRow.fusionProgress
                                fusionDistance: glassTuning.fusionDistance
                            }
                        }
                    }
                }
                DownloadFilters {}
            }
            RowLayout {
                visible: downloadData.catalogueError.length > 0
                Layout.fillWidth: true
                GlassText { text: downloadData.catalogueError; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: appRoot.muted }
                GlassPane {
                    objectName: "editorGlassControl"
                    property string materialRole:"button"
                    color: macWindowMetrics.nativeGlassDock ? "transparent" : prominent ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.24) : (appRoot.darkMode ? "#0CFFFFFF" : "#35FFFFFF")
                    border.width: macWindowMetrics.nativeGlassDock ? 0 : 1
                    edgeGlow: !macWindowMetrics.nativeGlassDock
                    visible: true
                    Layout.preferredWidth: 72; Layout.preferredHeight: 34; radius: 17
                    GlassText { anchors.centerIn: parent; text: appRoot.tr("Retry"); color: appRoot.ink }
                    TapHandler { onTapped: downloadData.retryCatalogue() }
                }
            }
        }
        ColumnLayout {
            anchors.fill: parent; spacing: 12
            Item { Layout.fillWidth: true; Layout.preferredHeight: downloadToolbar.implicitHeight }
            ListView {
                id: downloadList
                header: Item {
                    width:downloadList.width; height:38
                    BackdropText { anchors.left:parent.left; anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter
                        text:appRoot.tr("Target · ") + appRoot.selectedLabel() + " · " + appRoot.selectedVersion();color:appRoot.muted;font.pixelSize:12;elide:Text.ElideRight }
                }
                objectName: "downloadList"
                Layout.fillWidth: true; Layout.fillHeight: true
                // Rows continue behind the floating toolbar to the window edge.
                // The toolbar is outside contentScene, so its glass samples these rows.
                clip: false; spacing: 12
                displayMarginBeginning: appRoot.height
                displayMarginEnd: appRoot.height
                model: downloadRows
                boundsBehavior: Flickable.StopAtBounds
                // Append preserves scroll position. New queries reset below via the query key.
                property string displayedQuery: ""
                function maybeFetchMore() {
                    if (appRoot.activePage !== "Download" || appRoot.downloadSelection || downloadData.catalogueBusy || downloadData.catalogueError || !downloadData.hasMore) return
                    if (contentY + height >= contentHeight - 2 * 142)
                        downloadData.loadCatalogue(appRoot.downloadCategory, appRoot.downloadSearch, appRoot.downloadSort, true, appRoot.downloadLoaderFilter, appRoot.downloadProvider)
                }
                onContentYChanged: autoPage.restart()
                onHeightChanged: autoPage.restart()
                onContentHeightChanged: autoPage.restart()
                Connections {
                    target: downloadData
                    function onCatalogueBusyChanged() { autoPage.restart() }
                    function onCatalogueKeyChanged() {
                        if (downloadList.displayedQuery !== downloadData.catalogueKey) {
                            downloadList.displayedQuery = downloadData.catalogueKey
                            downloadList.positionViewAtBeginning()
                        }
                    }
                }
                Timer { id: autoPage; interval: 80; onTriggered: downloadList.maybeFetchMore() }
                footer: Item {
                    width: downloadList.width
                    height: bottomDock.height + 32
                    GlassText {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 8
                        text: downloadData.catalogueBusy ? appRoot.tr("Loading…") : ""
                        color: appRoot.muted; font.pixelSize: 12
                    }
                }
                ScrollBar.vertical: ScrollBar { }
                delegate: GlassPane {
                    objectName: "editorGlassControl"
                    property string materialRole:"downloadRow"
                    // The cards' frost, soft blur and dimming (Settings › Layout › Card glass).
                    cardStyle: appRoot.panelGlassStyle
                    readonly property var nativeRow: modelData
                    readonly property url nativeIconSource: modelData.category === "Versions" ? Qt.resolvedUrl("assets/version-grass.png") : modelData.icon || ""
                    color: macWindowMetrics.nativeGlassDock ? "transparent" : prominent ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.24) : (appRoot.darkMode ? "#0CFFFFFF" : "#35FFFFFF")
                    border.width: 0
                    edgeGlow: false
                    id: downloadCard
                    required property var entry
                    readonly property var modelData: entry
                    width: downloadList.width
                    readonly property bool narrow: width < 650
                    height: narrow ? 142 : 118
                    radius: Math.max(appRoot.macOSWindowCornerRadius, downloadCard.padding + 12)
                    // Windows: every row is the same material (an accent-tinted
                    // "quick version" row and a hairline in the gaps read as
                    // stray colours); AppKit keeps its selected row.
                    selectedGlass: macWindowMetrics.nativeGlassDock && modelData.category === "Versions" && modelData.version === appRoot.sidebarQuickVersion
                    readonly property real padding: 16
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appRoot.openProject(downloadCard.modelData)
                    }
                    // Fill, picture and outline share one antialiased continuous
                    // clip: a thresholded mask left jagged picture corners with
                    // the dark fill showing through them.
                    Item {
                        id: iconTile
                        visible: !macWindowMetrics.nativeGlassDock
                        objectName: "downloadIconTile"
                        x: downloadCard.padding; y: downloadCard.padding
                        width: downloadCard.height - 2 * downloadCard.padding; height: width
                        readonly property real radius: Math.max(0, downloadCard.radius - downloadCard.padding)
                        layer.enabled: true; layer.smooth: true
                        layer.textureSize: Qt.size(Math.ceil(width * appRoot.glassPixelRatio), Math.ceil(height * appRoot.glassPixelRatio))
                        layer.effect: ContinuousClip { radius: iconTile.radius; rimWidth: 1; rimColor: appRoot.outline }
                        Rectangle { anchors.fill: parent; color: appRoot.darkMode ? "#355B7890" : "#A3DEECF8" }
                        Image {
                            id: projectIcon
                            anchors.fill: parent
                            source: downloadCard.modelData.category === "Versions" ? Qt.resolvedUrl("assets/version-grass.png") : downloadCard.modelData.icon || ""
                            asynchronous: true; fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
                        }
                        GlassText { visible: projectIcon.status !== Image.Ready; anchors.centerIn: parent; text: appRoot.tr(downloadCard.modelData.badge); textFormat: Text.PlainText; color: appRoot.accent; font.pixelSize: 12; font.bold: true }
                    }
                    Column {
                        visible: !macWindowMetrics.nativeGlassDock
                        x: iconTile.x + iconTile.width + 16
                        y: downloadCard.narrow ? downloadCard.padding : (downloadCard.height - height) / 2
                        width: Math.max(0, downloadCard.width - x - downloadCard.padding - (downloadCard.narrow ? 0 : 128))
                        spacing: 8
                        GlassText { width: parent.width; text: downloadCard.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; color: appRoot.ink; font.pixelSize: 18; font.bold: true }
                        GlassText { width: parent.width; text: appRoot.shownSummary(downloadCard.modelData.detail); textFormat: Text.PlainText; color: appRoot.darkMode ? "#DEFFFFFF" : "#D51C1C1E"; font.pixelSize: 13; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        y: downloadCard.narrow ? downloadCard.height - height - downloadCard.padding : (downloadCard.height - height) / 2
                        spacing: 10
                        // Same "Get" capsule as the version list: accent tint,
                        // bright accent label, no outline.
                        GlassPane {
                            objectName: macWindowMetrics.nativeGlassDock ? "" : "editorGlassControl"
                            property string materialRole:"button"
                            liquidGlass: false
                            color: macWindowMetrics.nativeGlassDock ? "transparent" : Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,catalogueGetTap.pressed?0.5:catalogueGetHover.hovered?0.4:0.3)
                            border.width: 0
                            edgeGlow: false
                            width: 104; height: 32; radius: 16
                            GlassText { visible: !macWindowMetrics.nativeGlassDock; anchors.centerIn: parent; text: appRoot.tr("Download"); color: appRoot.accentLabel; font.pixelSize: 13; font.bold: true }
                            HoverHandler { id: catalogueGetHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: catalogueGetTap
                                onTapped: {
                                    if (downloadCard.modelData.category === "Versions") appRoot.sidebarQuickVersion = downloadCard.modelData.version
                                    appRoot.beginDownload(downloadCard.modelData)
                                }
                            }
                        }
                    }
                }
                GlassText {
                    anchors.centerIn: parent
                    visible: downloadList.count === 0 && !downloadData.catalogueError
                    text: downloadData.catalogueBusy ? appRoot.tr("Loading catalogue…") : appRoot.tr("No matches · Try another search")
                    color: appRoot.muted
                }
            }

        }
    }


    Item {
        id: releasePage
        parent: contentScene
        z: 12
        visible: appRoot.activePage === "Download" && appRoot.downloadSelection !== null
        // Compact mode: the header shares the navigation bar's row (centred on
        // it, 14 + 56 / 2 = 42); with the sidebar it is the sidebar's top.
        x: appRoot.contentLeft + 28
        y: macWindowMetrics.nativeGlassDock ? appRoot.pageTop()
           : (appRoot.navigationTopInset + (appRoot.navigationBarHeight - 36) / 2 - appRoot.contentItem.y) * (1 - appRoot.sidebarProgress) + appRoot.sidebarPageTop * appRoot.sidebarProgress
        width: Math.max(0, appRoot.width - appRoot.contentLeft - 56)
        // To the window bottom, like the catalogue; lists keep a dock-sized footer.
        height: Math.max(0, appRoot.height - y)
        readonly property bool game: appRoot.downloadSelection !== null && appRoot.downloadSelection.category === "Versions"
        // Compact mode: back, title and actions sit in the navigation bar's row,
        // clear of the window buttons and the account button, under one bar.
        readonly property bool inlineBar: !appRoot.sidebarMode && !macWindowMetrics.nativeGlassDock
        readonly property bool barMode: navigationBar || inlineBar
        readonly property real leftReserve: !inlineBar ? 0 : appRoot.trafficLights ? 53 : appRoot.captionWidth > 0 ? 46 : 0
        readonly property real rightReserve: !inlineBar ? 0 : appRoot.captionWidth > 0 ? appRoot.captionWidth - 16 : 46
        // Safari / iOS 26: scrolling down hides the navigation bar, scrolling
        // up (or reaching the top) brings it back. Back and the actions stay.
        property real scrollAnchor: 0
        function trackScroll(view) {
            if (!inlineBar || !visible || !view.visible) return
            var y = view.contentY
            if (view.atYBeginning) { appRoot.navigationCollapsed = false; scrollAnchor = y; return }
            if (appRoot.navigationCollapsed) {
                if (y > scrollAnchor) scrollAnchor = y
                else if (scrollAnchor - y > 24) { appRoot.navigationCollapsed = false; scrollAnchor = y }
            } else {
                if (y < scrollAnchor) scrollAnchor = y
                else if (y - scrollAnchor > 24) { appRoot.navigationCollapsed = true; scrollAnchor = y }
            }
        }
        onVisibleChanged: appRoot.navigationCollapsed = false
        Connections { target: appRoot; function onProjectIntroductionChanged() { appRoot.navigationCollapsed = false } }
        Connections { target: introductionFlick; function onContentYChanged() { releasePage.trackScroll(introductionFlick) } }
        Connections { target: releaseList; function onContentYChanged() { releasePage.trackScroll(releaseList) } }
        // With the sidebar, an iPadOS Settings navigation bar: back button and a
        // compact title centred on the page; the large title is for compact mode.
        readonly property bool navigationBar: appRoot.sidebarMode
        readonly property string targetText: game ? "Choose a loader, then choose its version" : "Target: " + appRoot.selectedLabel() + " · " + appRoot.selectedVersion()
        // Like the Minecraft Log header: the release list runs under the bar,
        // which shows it blurred above a hairline; the sharp rows fade out at it.
        readonly property bool barScroll: barMode && !appRoot.projectIntroduction && !game && !macWindowMetrics.nativeGlassDock
        // The project introduction scrolls up to the window top the same way.
        readonly property bool introScroll: barMode && appRoot.projectIntroduction && !macWindowMetrics.nativeGlassDock
        readonly property bool underBar: barScroll || introScroll
        readonly property Flickable barView: introScroll ? introductionFlick : releaseList
        readonly property real barHeight: releaseHeader.height + 12
        // Where the list and introduction would start without the bar.
        readonly property real naturalTop: windowTop + barHeight
        // Rows scroll up to the window top: the list and the blurred bar
        // start there, above this page's own top.
        readonly property real windowTop: y + appRoot.contentItem.y
        readonly property real barReach: inlineBar ? Math.max(naturalTop, appRoot.compactPageTop * (1 - appRoot.sidebarProgress) + naturalTop * appRoot.sidebarProgress) : naturalTop
        Rectangle {
            id: releaseFadeMask
            width: releasePage.barView.width; height: releasePage.barView.height
            visible: false; layer.enabled: releasePage.underBar
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: Math.max(0, (releasePage.barReach - 10) / Math.max(1, releasePage.barView.height)); color: "transparent" }
                GradientStop { position: Math.min(1, (releasePage.barReach + 6) / Math.max(1, releasePage.barView.height)); color: "white" }
                GradientStop { position: 1; color: "white" }
            }
        }
        ColumnLayout {
            anchors.fill: parent; spacing: 12
            Item {
                id: releaseHeader
                z: 2
                // A bar row is the back button's height, so every control in it
                // shares one centre line.
                Layout.preferredHeight: releasePage.barMode ? 36 : Math.max(44,releaseTitleColumn.implicitHeight)+6*appRoot.sidebarProgress
                Layout.fillWidth: true
                // The bar spans the whole content area, sidebar edge to window
                // edge, past the page's 28 pt side insets (sampled as empty).
                Item {
                    visible: releasePage.underBar
                    x: -28; y: -releasePage.windowTop
                    width: appRoot.width - appRoot.contentLeft; height: releasePage.barReach; clip: true
                    ShaderEffectSource {
                        id: releaseBarSource
                        width: parent.width; height: parent.height
                        sourceItem: releasePage.underBar ? releasePage.barView.contentItem : null
                        sourceRect: Qt.rect(-28, releasePage.barView.contentY, parent.width, parent.height)
                        live: true; hideSource: false; visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: releaseBarSource
                        blurEnabled: true; blur: 1.0; blurMax: 40
                        autoPaddingEnabled: false
                        opacity: 0.85
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width; height: 1
                        color: appRoot.darkMode ? "#2EFFFFFF" : "#1F000000"
                    }
                }
                // Centred title: always with the sidebar; in compact mode it takes
                // the navigation bar's place while that is hidden.
                GlassText {
                    visible: releasePage.navigationBar || (releasePage.inlineBar && appRoot.navigationCollapse > 0.01)
                    opacity: releasePage.navigationBar ? 1 : appRoot.navigationCollapse
                    transform: Translate { y: releasePage.navigationBar ? 0 : 8 * (1 - appRoot.navigationCollapse) }
                    width: parent.width; height: 36
                    leftPadding: 150 + Math.max(releasePage.leftReserve, releasePage.rightReserve)
                    rightPadding: leftPadding
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: appRoot.downloadSelection ? appRoot.downloadSelection.name : ""
                    textFormat: Text.PlainText; elide: Text.ElideRight
                    color: appRoot.ink; font.pixelSize: 17; font.bold: true
                }
            // macOS toolbar header: round back button, large title with its
            // subtitle, and an App Store style Install button that turns into a
            // progress ring while installing.
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: releasePage.leftReserve; anchors.rightMargin: releasePage.rightReserve
                spacing: 14
                GlassPane {
                    id: releaseBackButton
                    objectName: "editorGlassControl"
                    property string materialRole:"button"
                    Layout.alignment: Qt.AlignTop
                    color: macWindowMetrics.nativeGlassDock ? "transparent" : (releaseBackTap.pressed ? (appRoot.darkMode ? "#33FFFFFF" : "#30000000") : releaseBackHover.hovered ? (appRoot.darkMode ? "#20FFFFFF" : "#18000000") : (appRoot.darkMode ? "#12FFFFFF" : "#0D000000"))
                    border.width: 0
                    // Navigation bar buttons are blurred, not Liquid Glass.
                    forcePlainBlur: true
                    edgeGlow: false
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 18
                    Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Back")
                    // Press grows the glass, as the dock's Launch button.
                    scale: glassTuning.reducedMotion ? 1 : releaseBackTap.pressed ? 1.1 : releaseBackHover.hovered ? 1.03 : 1
                    Behavior on scale { enabled: !glassTuning.reducedMotion; SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.002 } }
                    SymbolImage { id: releaseBackSymbol; anchors.centerIn: parent; anchors.horizontalCenterOffset: -1; width: 20; height: 20; symbol: "chevron.left" }
                    GlassText { anchors.centerIn: parent; visible: releaseBackSymbol.status !== Image.Ready; text: "‹"; color: appRoot.ink; font.pixelSize: 22 }
                    HoverHandler { id: releaseBackHover }
                    TapHandler { id: releaseBackTap; onTapped: appRoot.downloadBack() }
                }
                Column {
                    id: releaseTitleColumn
                    Layout.fillWidth: true
                    Layout.alignment: releasePage.inlineBar ? Qt.AlignVCenter : Qt.AlignTop
                    spacing: 3
                    // Compact bar: an inline title beside Back, kept clear of the
                    // centred navigation bar; it moves to the centre as that hides.
                    GlassText {
                        visible: !releasePage.navigationBar
                        width: releasePage.inlineBar ? Math.min(parent.width, Math.max(0, topBar.x - releasePage.x - releasePage.leftReserve - 50 - 16)) : parent.width
                        elide: Text.ElideRight
                        opacity: releasePage.inlineBar ? 1 - appRoot.navigationCollapse : 1
                        transform: Translate { x: releasePage.inlineBar ? -10 * appRoot.navigationCollapse : 0 }
                        text: appRoot.downloadSelection ? appRoot.downloadSelection.name : ""
                        textFormat: Text.PlainText
                        color: appRoot.ink; font.pixelSize: releasePage.inlineBar ? 17 : 24; font.bold: true
                    }
                    BackdropText {
                        visible: !appRoot.projectIntroduction && !releasePage.barMode
                        width: parent.width; elide: Text.ElideRight
                        text: releasePage.targetText
                        color: appRoot.muted; font.pixelSize: 13
                    }
                }
                GlassText {
                    // Current step ("Executing task 3 out of 5") beside the ring.
                    visible: prismBridge.installing && !appRoot.projectIntroduction
                    Layout.maximumWidth: 260; Layout.alignment: Qt.AlignVCenter
                    text: prismBridge.status; elide: Text.ElideRight
                    color: appRoot.muted; font.pixelSize: 12
                }
                // Project page primary action, trailing in the header like the
                // App Store's Get button.
                // Translate the description: a language menu, then Show Original.
                GroupButton {
                    id: translateButton
                    visible: appRoot.projectIntroduction && !appRoot.projectBodyBusy && !appRoot.projectBodyError
                    Layout.alignment: Qt.AlignVCenter
                    glass: true; plainBlur: true
                    text: appRoot.projectTranslating ? appRoot.tr("Translating…") : appRoot.projectTranslation ? appRoot.tr("Show Original") : appRoot.tr("Translate")
                    enabled: !appRoot.projectTranslating
                    onClicked: if (appRoot.projectTranslation) appRoot.resetProjectTranslation(); else translateMenu.popup(translateButton, 0, translateButton.height + 4)
                    GlassMenu {
                        id: translateMenu
                        Instantiator {
                            model: appRoot.translationLanguages
                            delegate: GlassMenuItem {
                                required property var modelData
                                text: modelData.name
                                onTriggered: appRoot.translateProject(modelData.code)
                            }
                            onObjectAdded: function(index, object) { translateMenu.insertItem(index, object) }
                            onObjectRemoved: function(index, object) { translateMenu.removeItem(object) }
                        }
                    }
                }
                GroupButton {
                    visible: appRoot.projectIntroduction
                    Layout.alignment: Qt.AlignVCenter
                    glass: true; plainBlur: true
                    text: appRoot.tr("Choose a Version…")
                    onClicked: appRoot.projectIntroduction=false
                }
                InstallButton {
                    visible: !appRoot.projectIntroduction && (prismBridge.installing || (releasePage.game && appRoot.selectedLoader === "Vanilla"))
                    Layout.alignment: Qt.AlignVCenter
                    ready: !prismBridge.installing && !downloadData.releaseBusy && !downloadData.releaseError && ((releasePage.game && appRoot.selectedLoader === "Vanilla" && downloadData.vanillaValid) || (appRoot.selectedReleaseDetails !== null && appRoot.selectedReleaseDetails.eligible && (releasePage.game || appRoot.downloadSelection.category === "Modpacks" || appRoot.selectedId.indexOf("prism:") === 0)))
                    onInstall: appRoot.installSelectedRelease()
                }
            }
            }

            Flickable {
                id: introductionFlick
                visible: appRoot.projectIntroduction
                Layout.fillWidth: true; Layout.fillHeight: true
                // Runs under the navigation bar up to the window top (introScroll).
                Layout.topMargin: releasePage.introScroll ? -releasePage.naturalTop : 0
                // 16 pt between the bar's hairline and the description panel.
                topMargin: releasePage.introScroll ? releasePage.barReach + 16 : 0
                onTopMarginChanged: contentY = -topMargin
                layer.enabled: releasePage.introScroll
                layer.effect: MultiEffect { maskEnabled: true; maskSource: releaseFadeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                clip: true; contentWidth: width; contentHeight: introductionColumn.implicitHeight + bottomDock.height + 32
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                // The description sits in the same Liquid Glass panel as a
                // Settings group, so it stays legible over any project artwork.
                Column {
                    id: introductionColumn; width: parent.width; spacing: 20
                    SettingsSection {
                        width: parent.width
                        // The sidebar's frostier material: long text over busy artwork.
                        frosted: true
                        Item {
                            width: parent.width; height: introductionBody.implicitHeight + 40
                            Column {
                                id: introductionBody
                                x: 22; y: 20; width: parent.width - 44; spacing: 16
                                // Translation status (the Translate button is in the header).
                                GlassText {
                                    width: parent.width; elide: Text.ElideRight; color: appRoot.muted; font.pixelSize: 12
                                    visible: !!text
                                    text: appRoot.projectTranslating ? appRoot.tr("Translating…")
                                        : appRoot.projectTranslateError ? appRoot.projectTranslateError
                                        : appRoot.projectTranslation ? appRoot.tr("Translated by %1").replace("%1", translationService.providerName) : ""
                                }
                                GlassText { width: parent.width; text: appRoot.projectTranslation && appRoot.projectTranslatedDetail ? appRoot.projectTranslatedDetail : appRoot.downloadSelection ? (appRoot.downloadSelection.detail || "") : ""; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: appRoot.ink; font.pixelSize: 17 }
                                // Long inline code (paths, presets) breaks anywhere rather than overflow.
                                GlassText { width: parent.width; visible: !!text; text: appRoot.projectBodyBusy ? appRoot.tr("Loading introduction…") : appRoot.projectBodyError || (appRoot.projectTranslation && !appRoot.projectSegments.length ? "" : appRoot.projectBody); textFormat: appRoot.projectBodyBusy || appRoot.projectBodyError ? Text.PlainText : appRoot.projectBodyHtml ? Text.RichText : Text.MarkdownText; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: appRoot.ink; linkColor: appRoot.accent; onLinkActivated: function(link) { Qt.openUrlExternally(link) } }
                                // Text blocks and the pictures between them.
                                Repeater {
                                    model: appRoot.projectBodyBusy || appRoot.projectBodyError ? [] : appRoot.projectTranslation ? appRoot.projectTranslatedSegments : appRoot.projectSegments
                                    delegate: Item {
                                        id: introSegment
                                        required property var modelData
                                        readonly property bool picture: modelData.kind === "image"
                                        width: introductionBody.width
                                        // Decided from the image itself, never from `visible`:
                                        // a hidden delegate makes its children report hidden.
                                        readonly property bool pictureShown: picture && introImage.status === Image.Ready && introImage.sourceSize.width >= 48
                                        readonly property bool pictureLoading: picture && introImage.status === Image.Loading
                                        height: picture ? (pictureShown ? Math.round(Math.min(width, introImage.sourceSize.width) * introImage.sourceSize.height / introImage.sourceSize.width) : pictureLoading ? 120 : 0) : introText.implicitHeight
                                        visible: height > 0
                                        GlassText {
                                            id: introText
                                            visible: !introSegment.picture
                                            width: parent.width; text: introSegment.picture ? "" : introSegment.modelData.text
                                            textFormat: appRoot.projectBodyHtml && !introSegment.modelData.markdown ? Text.RichText : Text.MarkdownText
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: appRoot.ink; linkColor: appRoot.accent
                                            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                                        }
                                        // Natural size up to the column width, centred; tiny
                                        // pictures (icons, spacers) are left out.
                                        Image {
                                            id: introImage
                                            visible: introSegment.pictureShown
                                            source: introSegment.picture ? introSegment.modelData.url : ""
                                            asynchronous: true; cache: true; smooth: true; mipmap: true
                                            fillMode: Image.PreserveAspectFit
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: introSegment.pictureShown ? Math.min(parent.width, sourceSize.width) : 0
                                            height: introSegment.pictureShown ? parent.height : 0
                                            layer.enabled: introSegment.pictureShown
                                            layer.effect: ContinuousClip { radius: 12 }
                                        }
                                        Rectangle {
                                            visible: introSegment.pictureLoading
                                            anchors.fill: parent; radius: 12
                                            color: appRoot.darkMode ? "#14FFFFFF" : "#0F000000"
                                        }
                                    }
                                }
                                GroupButton { visible: !!appRoot.projectBodyError; text: appRoot.tr("Retry"); onClicked: appRoot.openProject(appRoot.downloadSelection) }
                            }
                        }
                    }
                }
            }
            // System Settings style inset group; the explanation is its footnote.
            SettingsSection {
                visible: !appRoot.projectIntroduction && releasePage.game
                Layout.fillWidth: true; Layout.preferredHeight: 54; Layout.topMargin: 6
                SettingsRow {
                    symbol: "square.grid.2x2"; tileColor: "#0A84FF"; title: appRoot.tr("Mod loader"); last: true
                    GlassSelect {
                        nativeDownloadMaterial: true
                        width: 170
                        options: ["Vanilla", "Fabric", "Forge", "NeoForge", "Quilt"]
                        selected: appRoot.selectedLoader
                        onChosen: function(value) { appRoot.selectedLoader = value; appRoot.selectedRelease = "" }
                    }
                }
            }
            SettingsCaption {
                visible: !appRoot.projectIntroduction && releasePage.game && appRoot.selectedLoader === "Vanilla"
                Layout.fillWidth: true
                text: appRoot.tr("Vanilla uses the selected Minecraft version; no loader version is needed.")
            }
            RowLayout {
                // Under the scrolling bar this is the list header's first row instead.
                visible: !releasePage.barScroll && appRoot.releaseNotice
                Layout.fillWidth: true
                GlassText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: appRoot.muted
                    text: downloadData.releaseBusy ? appRoot.tr("Loading versions…") : downloadData.releaseError || appRoot.tr("No versions listed for this selection. Try another loader or project.")
                }
                GlassPane {
                    objectName: "editorGlassControl"
                    property string materialRole:"button"
                    color: macWindowMetrics.nativeGlassDock ? "transparent" : prominent ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.24) : (appRoot.darkMode ? "#0CFFFFFF" : "#35FFFFFF")
                    border.width: macWindowMetrics.nativeGlassDock ? 0 : 1
                    edgeGlow: !macWindowMetrics.nativeGlassDock
                    visible: !downloadData.releaseBusy
                    Layout.preferredWidth: 72; Layout.preferredHeight: 34; radius: 17
                    GlassText { anchors.centerIn: parent; text: appRoot.tr("Retry"); color: appRoot.ink }
                    TapHandler { onTapped: downloadData.retryReleases() }
                }
            }
            // List header: the install outcome, then required dependencies, each
            // with its own Download, as one inset block like a release group.
            // In the header so they scroll with the releases.
            Component {
                id: releaseListHeader
                Column {
                width: releaseList.width
                spacing: 0
                // Says so before any row does: nothing here fits this instance.
                Item {
                    visible: appRoot.releasesAllIncompatible
                    width: parent.width; height: visible ? incompatibleNotice.height + 16 : 0
                    // The cards' Liquid Glass (frost, soft blur, dimming), tinted amber.
                    GlassPane {
                        id: incompatibleNotice
                        objectName: "editorGlassControl"
                        width: parent.width; height: incompatibleText.implicitHeight + 24; radius: 16
                        edgeGlow: false
                        cardStyle: appRoot.panelGlassStyle
                        glassTint: Qt.rgba(1, 0.62, 0.04, 1)
                        // Without Liquid Glass: the amber fill and outline as before.
                        color: Qt.rgba(1, 0.62, 0.04, 0.16)
                        border.width: liquidActive ? 0 : 1; border.color: Qt.rgba(1, 0.62, 0.04, 0.4)
                        Rectangle { anchors.fill: parent; radius: parent.radius; visible: parent.liquidActive; color: Qt.rgba(1, 0.62, 0.04, 0.10) }
                        SymbolImage { x: 16; y: 14; width: 22; height: 22; symbol: "exclamationmark.triangle.fill"; tint: appRoot.warningColor }
                        Column {
                            id: incompatibleText
                            x: 50; y: 12; width: parent.width - 66; spacing: 2
                            GlassText { width: parent.width; text: appRoot.tr("Not compatible with this instance"); color: appRoot.ink; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap }
                            GlassText {
                                width: parent.width; color: appRoot.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                                text: appRoot.tr("No version of %1 works with %2. Choose another instance or project.").replace("%1", appRoot.downloadSelection ? appRoot.downloadSelection.name : "").replace("%2", appRoot.selectedVersion())
                            }
                        }
                    }
                }
                // The navigation bar has no subtitle; the target leads the list.
                BackdropText {
                    visible: releasePage.barMode && !releasePage.game
                    width: parent.width; leftPadding: 18; rightPadding: 18; bottomPadding: 6
                    text: releasePage.targetText; elide: Text.ElideRight
                    color: appRoot.muted; font.pixelSize: 13
                }
                Row {
                    visible: releasePage.barScroll && appRoot.releaseNotice
                    x: 18; spacing: 12; topPadding: 8; bottomPadding: 8
                    GlassText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, releaseList.width - 130); wrapMode: Text.WordWrap; color: appRoot.muted
                        text: downloadData.releaseBusy ? appRoot.tr("Loading versions…") : downloadData.releaseError || appRoot.tr("No versions listed for this selection. Try another loader or project.")
                    }
                    GroupButton { visible: !downloadData.releaseBusy; text: appRoot.tr("Retry"); onClicked: downloadData.retryReleases() }
                }
                GlassText {
                    visible: appRoot.releaseOutcomeVisible
                    width: parent.width; bottomPadding: 10
                    text: prismBridge.status
                    color: appRoot.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                }
                Row {
                    visible: !releasePage.game && (downloadData.dependencyBusy || downloadData.dependencies.length > 0)
                    x: 18; height: 32; spacing: 6
                    GlassText { anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: appRoot.tr("Required Dependencies"); color: appRoot.muted; font.pixelSize: 13 }
                    GlassText {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8; color: appRoot.muted; font.pixelSize: 12; opacity: 0.7
                        text: downloadData.dependencyBusy ? appRoot.tr("Loading…") : appRoot.downloadSelection && appRoot.downloadSelection.category === "Mods" ? appRoot.tr("Also installed automatically with this mod") : ""
                    }
                }
                Rectangle {
                    visible: downloadData.dependencies.length > 0
                    width: parent.width; height: dependencyRows.implicitHeight; radius: 24
                    color: appRoot.darkMode ? "#D91C1C1F" : "#E6FFFFFF"
                    Column {
                        id: dependencyRows
                        width: parent.width
                        Repeater {
                            model: downloadData.dependencies
                            delegate: Item {
                                id: dependencyRow
                                required property var modelData
                                required property int index
                                width: dependencyRows.width; height: 58
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 4; radius: 20
                                    color: dependencyRowHover.hovered ? (appRoot.darkMode ? "#0FFFFFFF" : "#0A000000") : "transparent"
                                }
                                HoverHandler { id: dependencyRowHover }
                                // Rounded like the catalogue's icon tiles.
                                Item {
                                    id: dependencyIcon
                                    x: 18; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30
                                    layer.enabled: true; layer.smooth: true
                                    layer.textureSize: Qt.size(Math.ceil(width * appRoot.glassPixelRatio), Math.ceil(height * appRoot.glassPixelRatio))
                                    layer.effect: ContinuousClip { radius: 8 }
                                    Rectangle { anchors.fill: parent; color: appRoot.darkMode ? "#355B7890" : "#A3DEECF8" }
                                    Image {
                                        id: dependencyImage
                                        anchors.fill: parent
                                        source: dependencyRow.modelData.icon || ""; asynchronous: true
                                        fillMode: Image.PreserveAspectCrop; sourceSize.width: 68; sourceSize.height: 68; smooth: true
                                    }
                                    GlassText { visible: dependencyImage.status !== Image.Ready; anchors.centerIn: parent; text: appRoot.tr("MOD"); color: appRoot.accent; font.pixelSize: 10; font.bold: true }
                                }
                                Column {
                                    x: 62; anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width - 194); spacing: 3
                                    GlassText { width: parent.width; text: dependencyRow.modelData.name; elide: Text.ElideRight; color: appRoot.ink; font.pixelSize: 15 }
                                    GlassText { width: parent.width; text: appRoot.shownSummary(dependencyRow.modelData.detail || ""); elide: Text.ElideRight; color: appRoot.muted; font.pixelSize: 12 }
                                }
                                // Opens the dependency's own version list; Back returns here.
                                Rectangle {
                                    x: parent.width - width - 16; anchors.verticalCenter: parent.verticalCenter
                                    width: 96; height: 28; radius: 14
                                    color: Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, dependencyGetTap.pressed ? 0.5 : dependencyGetHover.hovered ? 0.4 : 0.3)
                                    GlassText { anchors.centerIn: parent; text: appRoot.tr("Download"); color: appRoot.accentLabel; font.pixelSize: 13; font.bold: true }
                                    HoverHandler { id: dependencyGetHover }
                                    MouseArea { id: dependencyGetTap; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: appRoot.openDependency(dependencyRow.modelData) }
                                }
                                Rectangle {
                                    visible: dependencyRow.index < downloadData.dependencies.length - 1
                                    anchors.left: parent.left; anchors.leftMargin: 62; anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom
                                    height: 1; color: appRoot.darkMode ? "#33FFFFFF" : "#26000000"
                                }
                            }
                        }
                    }
                }
                }
            }
            ListView {
                id: releaseList
                header: releaseListHeader
                // The very top: the header (notice, target) just below the bar.
                // originY alone left it under the bar (topMargin is room for the bar).
                function toTop() { Qt.callLater(function() { releaseList.contentY = releaseList.originY - releaseList.topMargin; releaseList.restingTop = releaseList.contentY }) }
                // Versions load after the list appears; the header (notice, target)
                // then grows upward and ListView keeps the first row in place,
                // which pushed the header under the bar. While the list rests at
                // its top, it stays there as the header changes; once scrolled,
                // it is left alone.
                property real restingTop: NaN
                onOriginYChanged: {
                    var top = originY - topMargin
                    if (!isNaN(restingTop) && Math.abs(contentY - restingTop) < 2 && !moving) contentY = top
                    restingTop = Math.abs(contentY - top) < 2 ? top : NaN
                }                // A new project or loader, the list coming into view, or the notice
                // growing the header: start from the top.
                onVisibleChanged: if (visible) toTop()
                onTopMarginChanged: toTop()
                Connections {
                    target: appRoot
                    function onReleasesAllIncompatibleChanged() { if (appRoot.releasesAllIncompatible) releaseList.toTop() }
                    function onDownloadSelectionChanged() { releaseList.toTop() }
                    function onSelectedLoaderChanged() { releaseList.toTop() }
                }
                Layout.topMargin: releasePage.barScroll ? -releasePage.naturalTop : 0
                // 16 pt between the bar's hairline and the first block, as on the introduction.
                topMargin: releasePage.barScroll ? releasePage.barReach + 16 : 0
                layer.enabled: releasePage.barScroll
                layer.effect: MultiEffect { maskEnabled: true; maskSource: releaseFadeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                // Rows run to the window bottom and scroll clear of the dock.
                footer: Item { width: releaseList.width; height: bottomDock.height + 32 }
                // AppKit rows need off-screen delegates; elsewhere a toggle that
                // rebuilds the model should only create what is on screen.
                displayMarginBeginning: macWindowMetrics.nativeGlassDock ? appRoot.height : 0
                displayMarginEnd: macWindowMetrics.nativeGlassDock ? appRoot.height : 120
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: !appRoot.projectIntroduction && (!releasePage.game || appRoot.selectedLoader !== "Vanilla")
                clip: !macWindowMetrics.nativeGlassDock; spacing: macWindowMetrics.nativeGlassDock ? 8 : 0
                model: appRoot.releaseRows()
                ScrollBar.vertical: ScrollBar { }
                // Non-native: App Store "Version History" look. Each group is one
                // inset rounded block of rows with hairline separators, under a
                // small collapsible section header. macOS AppKit rows keep their
                // own card geometry.
                delegate: GlassPane {
                    id:releaseCard
                    required property var modelData
                    required property int index
                    objectName: !modelData.heading && macWindowMetrics.nativeGlassDock ? "editorGlassControl" : ""
                    liquidGlass: false
                    materialRole:"releaseRow"
                    readonly property bool nativeReleaseRow:true
                    readonly property var nativeRow:({name:modelData.label || "",detail:modelData.detail || "",badge:""})
                    readonly property bool downloadEnabled:appRoot.canInstallRelease(modelData)
                    readonly property bool grouped: !macWindowMetrics.nativeGlassDock
                    readonly property bool firstInGroup: !!modelData.groupFirst
                    readonly property bool lastInGroup: !!modelData.groupLast
                    readonly property bool chosen: !modelData.heading && appRoot.selectedRelease===modelData.id
                    color:"transparent"
                    border.width:0;edgeGlow:false
                    width:releaseList.width
                    height:modelData.heading ? (grouped ? (index === 0 ? 32 : 46) : 36) : (grouped ? 58 : 82)
                    radius:20
                    selectedGlass:!grouped && chosen
                    // Group block slice: only the group's outer corners are round.
                    Item {
                        visible: releaseCard.grouped && !releaseCard.modelData.heading
                        anchors.fill: parent; clip: true
                        // The group block (Settings section radius) in the cards' Liquid
                        // Glass. Each row draws the whole block's shape, extended 24 pt
                        // past its own top and bottom unless it starts or ends the
                        // group, and is clipped to itself: the rounded corners and the
                        // top and bottom rims fall outside the middle rows, so the rows
                        // join into one seamless pane with refracting side edges.
                        GlassPane {
                            id: releaseBlock
                            readonly property real r: 24
                            x: 0; width: parent.width
                            y: releaseCard.firstInGroup ? 0 : -r
                            height: parent.height + (releaseCard.firstInGroup ? 0 : r) + (releaseCard.lastInGroup ? 0 : r)
                            radius: r
                            liquidGlass: true
                            edgeGlow: false
                            border.width: 0
                            cardStyle: appRoot.panelGlassStyle
                            // Without Liquid Glass: the near-solid fill as before.
                            color: appRoot.darkMode ? "#D91C1C1F" : "#E6FFFFFF"
                        }
                        // Inset rounded selection, as in macOS inset lists.
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 4
                            radius: 20 // concentric: section 24 − 4 inset
                            color: releaseCard.chosen ? Qt.rgba(appRoot.accent.r, appRoot.accent.g, appRoot.accent.b, 0.28)
                                   : releaseRowHover.hovered ? (appRoot.darkMode ? "#0FFFFFFF" : "#0A000000") : "transparent"
                        }
                        // Separator starts at the title, as in Settings.
                        Rectangle {
                            visible: !releaseCard.lastInGroup
                            anchors.left: parent.left; anchors.leftMargin: 62; anchors.right: parent.right; anchors.rightMargin: 16; anchors.bottom: parent.bottom
                            height: 1; color: appRoot.darkMode ? "#33FFFFFF" : "#26000000"
                        }
                        // Settings symbol tile: green release, orange beta, red alpha; blue loader builds.
                        Rectangle {
                            readonly property string kind: releaseCard.modelData.versionType || ""
                            readonly property bool blocked: !!releaseCard.modelData.issue
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 8
                            color: blocked ? "#FF9F0A" : kind === "beta" ? "#FF9F0A" : kind === "alpha" ? "#FF453A" : kind === "release" ? "#34C759" : "#0A84FF"
                            SymbolImage {
                                anchors.centerIn: parent; width: 17; height: 17; tint: "white"
                                symbol: parent.blocked ? "exclamationmark.triangle.fill" : parent.kind === "beta" ? "bolt.fill" : parent.kind === "alpha" ? "sparkles" : parent.kind === "release" ? "checkmark" : "square.grid.2x2"
                            }
                        }
                    }
                    HoverHandler { id: releaseRowHover; enabled: releaseCard.grouped && !releaseCard.modelData.heading }
                    MouseArea {
                        anchors.fill:parent
                        onClicked:if(modelData.heading)appRoot.toggleReleaseGroup(modelData.group);else appRoot.selectedRelease=modelData.id
                    }
                    NativeChevron {visible:!!modelData.heading && !releaseCard.grouped;anchors.verticalCenter:parent.verticalCenter;symbol:appRoot.collapsedReleaseGroups[modelData.group]?"chevron.right":"chevron.down"}
                    BackdropText {
                        visible:!!modelData.heading && !releaseCard.grouped;anchors.fill:parent;leftPadding:24;verticalAlignment:Text.AlignVCenter
                        text:modelData.group + appRoot.tr(" · Newest first");color:appRoot.muted;font.pixelSize:12
                    }
                    // Settings section header: muted title, then a disclosure chevron.
                    Row {
                        visible: !!modelData.heading && releaseCard.grouped
                        x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        spacing: 6
                        BackdropText { text: modelData.group || ""; color: modelData.issue ? appRoot.warningColor : appRoot.muted; font.pixelSize: 13; font.bold: !!modelData.issue; anchors.verticalCenter: parent.verticalCenter }
                        SymbolImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11; height: 11; tint: appRoot.muted
                            symbol: appRoot.collapsedReleaseGroups[modelData.group] ? "chevron.right" : "chevron.down"
                        }
                    }
                    Column {
                        visible:!modelData.heading && !macWindowMetrics.nativeGlassDock
                        x:62;anchors.verticalCenter:parent.verticalCenter;width:Math.max(0,parent.width-194);spacing:3
                        GlassText {width:parent.width;text:modelData.label || "";elide:Text.ElideRight;color:modelData.issue?appRoot.muted:appRoot.ink;font.pixelSize:15}
                        GlassText {width:parent.width;text:modelData.issue || modelData.detail || "";elide:Text.ElideRight;color:modelData.issue?appRoot.warningColor:appRoot.muted;font.pixelSize:12}
                    }
                    // App Store "Get" capsule: grey fill, bold accent label.
                    GlassPane {
                        objectName:"releaseDownloadButton"
                        visible:!modelData.heading
                        readonly property real w: releaseCard.grouped && !releaseCard.modelData.issue ? 96 : 112
                        x:parent.width-w-16;y:(parent.height-height)/2;width:w;height:releaseCard.grouped?28:36;radius:height/2
                        // Disabled stays legible: a fainter fill and grey label
                        // instead of fading the whole button.
                        // Theme accent: tinted fill, bright accent label. Disabled
                        // stays legible: grey fill and label, not a faded button.
                        readonly property color label: appRoot.accentLabel
                        liquidGlass:false
                        color:macWindowMetrics.nativeGlassDock?"transparent":releaseCard.grouped
                              ?(!releaseCard.downloadEnabled?(appRoot.darkMode?"#14FFFFFF":"#0A000000")
                                :Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,releaseGetTap.pressed?0.5:releaseGetHover.hovered?0.4:0.3))
                              :appRoot.glassSoft
                        edgeGlow:false;border.width:0
                        opacity:releaseCard.grouped||releaseCard.downloadEnabled?1:0.4
                        GlassText {
                            visible:!macWindowMetrics.nativeGlassDock;anchors.centerIn:parent
                            text:releaseCard.modelData.issue?appRoot.tr("Incompatible"):releaseCard.grouped?appRoot.tr("Download"):appRoot.tr("↓  Download")
                            color:!releaseCard.grouped?appRoot.ink:releaseCard.downloadEnabled?parent.label:appRoot.muted
                            font.pixelSize:13;font.bold:true
                        }
                        HoverHandler { id: releaseGetHover }
                        // A MouseArea, not a TapHandler: the row's MouseArea below
                        // took the exclusive grab and the tap never fired.
                        MouseArea {
                            id: releaseGetTap
                            anchors.fill:parent;preventStealing:true
                            cursorShape:releaseCard.downloadEnabled?Qt.PointingHandCursor:Qt.ArrowCursor
                            onClicked:appRoot.downloadRelease(releaseCard.modelData)
                        }
                    }
                }
            }
            Item { visible: !appRoot.projectIntroduction && releasePage.game && appRoot.selectedLoader === "Vanilla"; Layout.fillHeight: true }
            // Install outcome only ("Installation complete/failed/cancelled");
            // progress lives in the header, and other bridge messages (sign-in,
            // core status) do not belong on this page.
            // With the release list shown, the outcome is its header instead.
            GlassText {
                visible: appRoot.releaseOutcomeVisible && !releaseList.visible
                Layout.fillWidth: true; Layout.bottomMargin: bottomDock.height + 36
                text: prismBridge.status
                color: appRoot.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                Accessible.role: Accessible.StaticText
            }
        }
    }

    // Search and zoom share a single expandable liquid-glass control.
    MouseArea {
        anchors.fill: parent
        z: 74
        visible: appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock
        onClicked: appRoot.searchExpanded = false
    }
    GlassPane {
        id:resizeDoneButton
        objectName:"editorGlassControl";materialRole:"button"
        visible:appRoot.cardSizeEditing && appRoot.activePage==="Launch"
        // In the top corner with the other toolbar items, not over the cards:
        // sidebar, left of the search button; compact, beside the account
        // button (top right, or top left under Windows window buttons). The
        // Groups button, when shown, stays next to its anchor.
        readonly property bool sidebarPlace:appRoot.sidebarProgress>=0.5
        readonly property bool groupsShown:groupManagerButton.visible
        readonly property bool accountOnLeft:appRoot.captionWidth>0
        x:sidebarPlace ? (groupsShown ? groupManagerButton.x : searchDock.x)-width-10
          : accountOnLeft ? compactAccountButton.x+compactAccountButton.width+10
          : (groupsShown ? groupManagerButton.x : compactAccountButton.x)-width-10
        y:sidebarPlace ? searchDock.y+(searchDock.rowHeight-height)/2
          : compactAccountButton.y+(compactAccountButton.height-height)/2
        width:Math.max(120,resizeDoneLabel.implicitWidth+40);height:36;radius:18;z:76
        // Accent Liquid Glass, like the dock's Launch button.
        liquidGlass:true
        prominent:appRoot.liquidGlass
        scale:glassTuning.reducedMotion ? 1 : resizeDoneTap.pressed ? 1.06 : resizeDoneTap.containsMouse ? 1.02 : 1
        Behavior on scale { enabled:!glassTuning.reducedMotion; SpringAnimation { spring:4.5; damping:0.32; epsilon:0.002 } }
        color:macWindowMetrics.nativeGlassDock?"transparent":Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,resizeDoneTap.pressed?0.65:0.45)
        border.width:0;edgeGlow:false
        GlassText {id:resizeDoneLabel;anchors.centerIn:parent;text:appRoot.tr("Done resizing");color:"white";font.pixelSize:13;font.bold:true}
        MouseArea {id:resizeDoneTap;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:appRoot.toggleCardSizeEditing()}
    }
    GlassPane {
        id: searchDock
        objectName: "launcherSearch"
        color: macWindowMetrics.nativeGlassDock ? "transparent" : appRoot.materialTint
        edgeGlow: false; border.width: 0; backdropBlur: false
        visible: appRoot.activePage === "Launch" && (appRoot.searchExpanded || appRoot.sidebarProgress > 0.55)
        z: 75
        readonly property bool sidebarDestination: appRoot.sidebarProgress >= 0.5
        opacity: sidebarDestination
                 ? Math.max(0, Math.min(1, (appRoot.sidebarProgress - 0.60) / 0.25))
                 : Math.max(0, Math.min(1, (0.40 - appRoot.sidebarProgress) / 0.25))
        enabled: opacity > 0.95
        // Grouped layouts have no canvas zoom: the grouping selector and Reset
        // join the search field's row, before Cancel (with and without the sidebar).
        readonly property bool merged: appRoot.searchExpanded && appRoot.groupedLayoutEnabled && !macWindowMetrics.nativeGlassDock
        readonly property real rowHeight: macWindowMetrics.nativeGlassDock ? 40 : 44
        // Selector (≥ 150) + Reset in the row.
        readonly property real inlineWidth: merged ? 206 : 0
        x: sidebarDestination ? appRoot.width-width-22 : (appRoot.width-width)/2
        y: sidebarDestination ? sidebarScroll.y+(42-rowHeight)/2+appRoot.captionInset*0.5 : topBar.y+topBar.height+10
        width: appRoot.searchExpanded ? Math.min(macWindowMetrics.nativeGlassDock ? 568 : 460 + inlineWidth * 0.6,Math.max(macWindowMetrics.nativeGlassDock ? 180 : 240,appRoot.width-appRoot.contentLeft-70-(appRoot.cardSizeEditing?178:0))) : (macWindowMetrics.nativeGlassDock ? 40 : 44)
        height: rowHeight; radius: rowHeight/2
        HoverHandler { id: searchHover }
        PointHandler { id: searchPress; target:null }
        scale: !appRoot.searchExpanded && !glassTuning.reducedMotion ? (searchPress.active ? 1.07 : searchHover.hovered ? 1.025 : 1) : 1
        Behavior on scale { enabled: !glassTuning.reducedMotion; NumberAnimation { duration:180; easing.type:Easing.OutBack; easing.overshoot:0.6 } }
        Behavior on width { enabled: !glassTuning.reducedMotion && !sidebarResizeHandle.pressed && (appRoot.sidebarProgress<=0 || appRoot.sidebarProgress>=1); NumberAnimation { duration:320; easing.type:Easing.OutCubic } }
        // Clicks, double-clicks and wheel on the open pane stay on it: tap
        // handlers do not stop a press, which reached the cards underneath
        // (a double-click there launched an instance).
        MouseArea {
            anchors.fill: parent
            enabled: appRoot.searchExpanded
            acceptedButtons: Qt.AllButtons
            onWheel: function(wheel) { wheel.accepted = true }
        }
        Item {
            id: searchToggle
            x:0; y:0; width:44; height:44
            opacity: macWindowMetrics.nativeGlassDock ? 0 : 1
            SymbolImage { anchors.centerIn:parent; width:21; height:21; symbol:"magnifyingglass" }
            TapHandler { enabled:!appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock; onTapped:appRoot.toggleSearch() }
        }
        TextField {
            id:searchInput
            objectName:"launcherSearchInput"
            visible:appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock
            x:42; y:4; height:36; width:Math.max(0,parent.width-142-searchDock.inlineWidth)
            text:appRoot.searchText; onTextEdited:appRoot.searchText=text
            placeholderText:appRoot.tr("Search instances"); placeholderTextColor:appRoot.muted
            color:appRoot.ink; font.pixelSize:14; background:null; selectByMouse:true
            leftPadding:0; rightPadding:4
            Keys.onEscapePressed:{appRoot.searchExpanded=false;focus=false}
        }
        Item {
            visible:appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock
            x:parent.width-98-searchDock.inlineWidth; width:30; height:44
            SymbolImage { anchors.centerIn:parent; width:13; height:13; symbol:"xmark"; tint:appRoot.muted; visible:appRoot.searchText.length>0 }
            TapHandler { enabled:appRoot.searchText.length>0; onTapped:{appRoot.searchText="";searchInput.forceActiveFocus()} }
        }
        GlassText {
            visible:appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock
            anchors.right:parent.right; anchors.rightMargin:14; y:(searchDock.rowHeight-height)/2
            text:appRoot.tr("Cancel"); color:appRoot.ink; font.pixelSize:13
            TapHandler { onTapped:{appRoot.searchExpanded=false;searchInput.focus=false} }
        }
        GlassPane {
            id:searchAccessories
            objectName:"searchAccessories"
            visible:appRoot.searchExpanded && !macWindowMetrics.nativeGlassDock
            // Its own Liquid Glass pane below the field; merged, it sits in the
            // field's row before Cancel. (Beside the field, not on it: no plain blur.)
            plainBlurOnGlass:false
            liquidGlass:!searchDock.merged
            color:searchDock.merged ? "transparent" : appRoot.glass
            x:searchDock.merged ? parent.width-70-searchDock.inlineWidth : 0
            y:searchDock.merged ? (searchDock.rowHeight-height)/2 : parent.height+8
            width:searchDock.merged ? searchDock.inlineWidth : parent.width; height:searchDock.merged ? 36 : 48; radius:searchDock.merged ? 18 : 24
            border.width:0; edgeGlow:false
            // Outside the dock's own area when separate: block here too.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: function(wheel) { wheel.accepted = true }
            }
            RowLayout {
                anchors.fill:parent; anchors.leftMargin:searchDock.merged ? 0 : 12; anchors.rightMargin:searchDock.merged ? 4 : 14; spacing:8
                GlassSelect {
                    id:sortCombo
                    // Room for the longest method ("Minecraft version").
                    Layout.fillWidth:true; Layout.minimumWidth:150; Layout.preferredHeight:32; controlHeight:32; compact:true
                    options:["Off","Smart","Minecraft version","Mod loader","Installed status","Custom"]
                    selected:appRoot.groupingMethod; onChosen:function(value){appRoot.groupingMethod=value}
                }
                // Canvas zoom only: grouped layouts do not zoom.
                GlassSlider {
                    id:zoomSlider
                    visible:!appRoot.groupedLayoutEnabled
                    Layout.fillWidth:true; Layout.minimumWidth:90; Layout.maximumWidth:170; Layout.preferredWidth:170; Layout.preferredHeight:32
                    thumbScale:0.6; from:0.55; to:1.65; value:appRoot.zoom; onMoved:appRoot.zoom=value
                }
                // Double-click to type a zoom (55–165 %).
                Item {
                    visible:!appRoot.groupedLayoutEnabled
                    Layout.preferredWidth:40; Layout.preferredHeight:32
                    GlassText {
                        anchors.fill:parent; visible:!zoomInput.visible
                        horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter
                        text:Math.round(appRoot.zoom*100)+"%"; color:appRoot.ink; font.pixelSize:11
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onDoubleClicked: { zoomInput.text=String(Math.round(appRoot.zoom*100)); zoomInput.visible=true; zoomInput.forceActiveFocus(); zoomInput.selectAll() }
                        }
                    }
                    TextField {
                        id:zoomInput
                        visible:false
                        anchors.verticalCenter:parent.verticalCenter; width:parent.width; height:24
                        leftPadding:4; rightPadding:4; topPadding:0; bottomPadding:0
                        horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter
                        color:appRoot.ink; font.pixelSize:11; selectByMouse:true
                        validator:IntValidator { bottom:1; top:999 }
                        inputMethodHints:Qt.ImhDigitsOnly
                        background:Rectangle { radius:6; color:appRoot.darkMode ? "#26FFFFFF" : "#26000000"; border.width:1; border.color:appRoot.accent }
                        function apply() {
                            var value=parseInt(text)
                            if(!isNaN(value))appRoot.zoom=Math.max(0.55,Math.min(1.65,value/100))
                            visible=false
                        }
                        onAccepted: apply()
                        onActiveFocusChanged: if(!activeFocus && visible)apply()
                        Keys.onEscapePressed: visible=false
                    }
                }
                GlassText { text:appRoot.tr("Reset"); color:appRoot.ink; font.pixelSize:12; MouseArea { anchors.fill:parent; anchors.margins:-6; cursorShape:Qt.PointingHandCursor; onClicked:{appRoot.resetCanvas();appRoot.searchText=""} } }
            }
        }
    }
    Timer {
        interval: 32
        repeat: true
        running: appRoot.accountMenuOpen && macWindowMetrics.nativeGlassDock
        onTriggered: macWindowMetrics.setAccountGlass(accountMenu, true)
    }
    component GroupButton: Button {
        id: groupButton
        // Windows: liquid glass instead of the flat fill (page-level actions).
        property bool glass: false
        property real cornerRadius: appRoot.customWindowChrome ? height / 2 : 14
        // Windows: the flat plate of the selector it sits beside.
        property bool plate: false
        // Blurred backdrop only, no Liquid Glass (navigation bar actions).
        property bool plainBlur: false
        implicitHeight: 36
        implicitWidth: Math.max(88,groupButtonLabel.implicitWidth+32)
        // Glass page actions grow under the pointer like the dock's Launch button.
        scale: !glass || glassTuning.reducedMotion ? 1 : down ? 1.06 : hovered ? 1.02 : 1
        Behavior on scale { enabled: groupButton.glass && !glassTuning.reducedMotion; SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.002 } }
        contentItem: GlassText {
            id: groupButtonLabel
            text: groupButton.text; color: appRoot.customWindowChrome ? appRoot.buttonText : appRoot.ink
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: GlassSurface {
            objectName: "accountGlassControl"
            property bool glassHovered: groupButton.hovered
            radius: groupButton.cornerRadius
            liquidGlass: !groupButton.plate || onLiquidPane
            forcePlainBlur: groupButton.plainBlur
            opacity: groupButton.enabled ? 1 : 0.45
            color: groupButton.plate ? appRoot.selectFill(groupButton.down, groupButton.hovered) : appRoot.customWindowChrome ? appRoot.buttonFill(groupButton.down, groupButton.hovered) : ((macWindowMetrics.nativeAccountGlass || (macWindowMetrics.nativeGlassDock && appRoot.activePage==="Instance")) ? "transparent" : appRoot.glass)
        }
    }
    // macOS search field (Downloads, Settings): a glass capsule with a leading
    // magnifying glass. TextField hides its placeholder while an input method
    // composes, so pinyin never overlaps it.
    component SearchField: TextField {
        id: searchField
        implicitHeight: appRoot.downloadControlHeight
        leftPadding: 38; rightPadding: 14; font.pixelSize: 13
        color: appRoot.ink
        placeholderTextColor: appRoot.muted
        selectionColor: appRoot.accent; selectedTextColor: "white"
        SymbolImage {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 15; symbol: "magnifyingglass"; tint: appRoot.muted
        }
        background: GlassPane {
            objectName: "editorGlassControl"
            property string materialRole:"button"
            color: macWindowMetrics.nativeGlassDock ? "transparent" : prominent ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.24) : (appRoot.darkMode ? "#0CFFFFFF" : "#35FFFFFF")
            border.width: macWindowMetrics.nativeGlassDock ? 0 : 1
            edgeGlow: !macWindowMetrics.nativeGlassDock; radius: appRoot.downloadControlRadius; subtle: true
        }
    }
    component GroupField: TextField {
        id: groupField
        implicitHeight: 34
        color: appRoot.ink
        background: GlassSurface {
            objectName: "accountGlassControl"
            radius: 10
            liquidGlass: !appRoot.customWindowChrome
            color: appRoot.customWindowChrome ? appRoot.fieldFill : ((macWindowMetrics.nativeAccountGlass || (macWindowMetrics.nativeGlassDock && appRoot.activePage==="Instance")) ? "transparent" : appRoot.glass)
            border.width: appRoot.customWindowChrome ? 1 : 0
            border.color: groupField.activeFocus ? appRoot.accent : (appRoot.darkMode ? "#0AFFFFFF" : "#1A000000")
        }
    }
    Timer {
        interval: 32; repeat: true
        running: macWindowMetrics.nativeGlassDock && groupManagerPopup.visible
        onTriggered: macWindowMetrics.setAccountGlass(groupManagerPopup.contentItem,true)
    }
    GlassPane {
        id: groupManagerButton
        // The open search field takes over this end of the toolbar.
        visible: appRoot.activePage === "Launch" && appRoot.groupedLayoutEnabled && appRoot.groupingMethod === "Custom"
                 && !(appRoot.searchExpanded && appRoot.sidebarProgress > 0.5)
        z: 73
        // Compact: a toolbar item, centred on the toolbar's row beside the account
        // button. Under right-hand window buttons it keeps below them instead:
        // its right edge on the page's, its bottom edge on the toolbar's.
        readonly property real compactTop: topBar.y + appRoot.contentItem.y + (appRoot.captionWidth > 0 ? topBar.height - height : (topBar.height - height) / 2)
        readonly property real compactInset: appRoot.captionWidth > 0 ? 28 : compactAccountButton.width + 26
        // Sidebar: the search button holds the corner; this sits beside it,
        // on its centre line.
        readonly property real sidebarInset: 22 + 44 + 10
        readonly property real sidebarTop: sidebarScroll.y + (42 - height) / 2 + appRoot.captionInset * 0.5
        x: appRoot.width-width-(compactInset*(1-appRoot.sidebarProgress)+sidebarInset*appRoot.sidebarProgress)
        y: (compactTop-appRoot.contentItem.y)*(1-appRoot.sidebarProgress)+sidebarTop*appRoot.sidebarProgress
        width: 108; height: 34; radius: 17
        GlassText { anchors.centerIn: parent; text: appRoot.tr("Groups"); color: appRoot.ink; font.pixelSize: 13 }
        TapHandler { onTapped: { appRoot.accountMenuOpen=false; groupManagerPopup.pendingKey="";groupManagerPopup.pendingKeys=[]; groupManagerPopup.open() } }
    }
    Popup {
        id: groupManagerPopup
        parent: appRoot.contentItem
        popupType: macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        property string pendingKey: ""
        property var pendingKeys: []
        x: appRoot.customWindowChrome ? groupManagerButton.x+groupManagerButton.width-width : appRoot.width-width-14
        y: appRoot.customWindowChrome ? groupManagerButton.y+groupManagerButton.height+8 : 120-appRoot.contentItem.y
        width: 350; height: Math.min(440,appRoot.height-150)
        padding: 16; dim: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: macWindowMetrics.setAccountGlass(contentItem,false)
        background: Item {
            GlassPane {
                anchors.fill: parent
                visible: !appRoot.customWindowChrome
                radius: 24; emphasized: true
                color: macWindowMetrics.nativeAccountGlass ? "transparent" : appRoot.glassStrong
                border.width: macWindowMetrics.nativeAccountGlass ? 0 : 1
                edgeGlow: !macWindowMetrics.nativeAccountGlass
            }
            MenuPanel {
                anchors.fill: parent
                visible: appRoot.customWindowChrome
                open: appRoot.customWindowChrome && groupManagerPopup.visible
                radius: 20
            }
        }
        // Reorder state: rows follow live, the order is saved on release.
        property int dragFrom: -1
        property int dragTo: -1
        property real dragOffset: 0
        readonly property real rowStep: 42
        contentItem: ColumnLayout {
            objectName: "menuPanelContent"
            spacing: 12
            GlassText { text: appRoot.tr("Groups"); color: appRoot.ink; font.pixelSize: 20; font.bold: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                GroupField {
                    id: newGroupName
                    Layout.fillWidth: true; placeholderText: appRoot.tr("New group name"); color: appRoot.ink
                    onAccepted: {
                        appRoot.createInstanceGroup(text,groupManagerPopup.pendingKeys.length ? groupManagerPopup.pendingKeys : groupManagerPopup.pendingKey)
                        text=""; groupManagerPopup.pendingKey="";groupManagerPopup.pendingKeys=[]
                    }
                }
                GroupButton {
                    text: appRoot.tr("Add"); implicitHeight: 34; cornerRadius: 10; plate: appRoot.customWindowChrome
                    onClicked: {
                        appRoot.createInstanceGroup(newGroupName.text,groupManagerPopup.pendingKeys.length ? groupManagerPopup.pendingKeys : groupManagerPopup.pendingKey)
                        newGroupName.text=""; groupManagerPopup.pendingKey="";groupManagerPopup.pendingKeys=[]
                    }
                }
            }
            GlassText { text: appRoot.tr("Right-click a card to move it into a group. Drag a handle to reorder."); color: appRoot.muted; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                Column {
                    id: groupRows
                    width: groupManagerPopup.availableWidth; spacing: 8
                    Repeater {
                        model: appRoot.instanceGroups
                        delegate: RowLayout {
                            id: groupRow
                            required property var modelData
                            required property int index
                            readonly property bool dragged: groupManagerPopup.dragFrom === index
                            readonly property int from: groupManagerPopup.dragFrom
                            readonly property int to: groupManagerPopup.dragTo
                            width: parent.width; height: 34; spacing: 8
                            z: dragged ? 1 : 0
                            transform: Translate {
                                y: groupRow.dragged ? groupManagerPopup.dragOffset
                                   : groupRow.from >= 0 && groupRow.from < groupRow.to && groupRow.index > groupRow.from && groupRow.index <= groupRow.to ? -groupManagerPopup.rowStep
                                   : groupRow.from > groupRow.to && groupRow.index >= groupRow.to && groupRow.index < groupRow.from ? groupManagerPopup.rowStep : 0
                                Behavior on y { enabled: !groupRow.dragged && groupRow.from >= 0 && !glassTuning.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                            // List reorder control: three bars.
                            Item {
                                Layout.preferredWidth: 22; Layout.fillHeight: true
                                Accessible.role: Accessible.Button; Accessible.name: appRoot.tr("Reorder")
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Repeater { model: 3; Rectangle { width: 16; height: 2; radius: 1; color: appRoot.muted } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    preventStealing: true
                                    property real pressY: 0
                                    onPressed: function(mouse) {
                                        pressY = mapToItem(groupRows, 0, mouse.y).y
                                        groupManagerPopup.dragFrom = groupRow.index; groupManagerPopup.dragTo = groupRow.index; groupManagerPopup.dragOffset = 0
                                    }
                                    onPositionChanged: function(mouse) {
                                        var offset = mapToItem(groupRows, 0, mouse.y).y - pressY
                                        var last = appRoot.instanceGroups.length - 1
                                        var maxDown = (last - groupRow.index) * groupManagerPopup.rowStep, maxUp = -groupRow.index * groupManagerPopup.rowStep
                                        groupManagerPopup.dragOffset = Math.max(maxUp, Math.min(maxDown, offset))
                                        groupManagerPopup.dragTo = Math.max(0, Math.min(last, groupRow.index + Math.round(groupManagerPopup.dragOffset / groupManagerPopup.rowStep)))
                                    }
                                    onReleased: {
                                        var from = groupManagerPopup.dragFrom, to = groupManagerPopup.dragTo
                                        groupManagerPopup.dragFrom = -1; groupManagerPopup.dragTo = -1; groupManagerPopup.dragOffset = 0
                                        if (from !== to) appRoot.moveInstanceGroup(from, to)
                                    }
                                    onCanceled: { groupManagerPopup.dragFrom = -1; groupManagerPopup.dragTo = -1; groupManagerPopup.dragOffset = 0 }
                                }
                            }
                            GroupField {
                                Layout.fillWidth: true; text: appRoot.tr(modelData.name); color: appRoot.ink
                                onEditingFinished: appRoot.renameInstanceGroup(modelData.id,text)
                            }
                            GroupButton { text: appRoot.tr("Delete"); implicitHeight: 34; cornerRadius: 10; plate: appRoot.customWindowChrome; onClicked: appRoot.deleteInstanceGroup(modelData.id) }
                        }
                    }
                }
            }
            GlassText { text: appRoot.tr("Deleting a group keeps its instances."); color: appRoot.muted; font.pixelSize: 11 }
        }
    }
    GlassMenu {
        id: canvasAppearanceMenu
        GlassMenuItem {text:appRoot.cardSizeEditing?appRoot.tr("Finish editing card sizes"):appRoot.tr("Edit card sizes…");checkable:true;checked:appRoot.cardSizeEditing;onTriggered:appRoot.toggleCardSizeEditing()}
        GlassMenuItem { text:appRoot.tr("Free mode");checkable:true;checked:appRoot.freeCanvasActive;enabled:!appRoot.hasInstanceGroups;onTriggered:appRoot.enableFreeCanvas() }
        GlassMenu {
            id:freeVisibilityMenu;title:appRoot.tr("Visible cards")
            Instantiator {
                model:appRoot.sortedCards
                delegate:GlassMenuItem { required property var modelData;text:modelData.label;checkable:true;checked:appRoot.freeHidden.indexOf(modelData.key)<0;onTriggered:appRoot.setFreeVisible(modelData.key,appRoot.freeHidden.indexOf(modelData.key)>=0) }
                onObjectAdded:function(i,o){freeVisibilityMenu.insertItem(i,o)}
                onObjectRemoved:function(i,o){freeVisibilityMenu.removeItem(o)}
            }
        }
        GlassMenuItem { text:appRoot.tr("Prevent overlap");enabled:appRoot.freeCanvasActive;checkable:true;checked:appRoot.freeAvoidOverlap;onTriggered:appRoot.freeAvoidOverlap=!appRoot.freeAvoidOverlap }
        GlassMenu {
            id:freeGapMenu;title:appRoot.tr("Minimum gap");enabled:appRoot.freeCanvasActive && appRoot.freeAvoidOverlap
            Instantiator {
                model:[8,16,24,32,48,64]
                delegate:GlassMenuItem {required property int modelData;text:modelData+appRoot.tr(" pt");checkable:true;checked:appRoot.freeMinimumGap===modelData;onTriggered:appRoot.freeMinimumGap=modelData}
                onObjectAdded:function(i,o){freeGapMenu.insertItem(i,o)}
                onObjectRemoved:function(i,o){freeGapMenu.removeItem(o)}
            }
        }
        GlassMenuItem { text:appRoot.tr("Recenter canvas");onTriggered:appRoot.resetCanvas() }
        GlassMenuItem { text:appRoot.tr("Launcher core…");onTriggered:prismConnection.open() }
        GlassMenuSeparator { }
        parent: appRoot.contentItem
        GlassMenuItem { text: appRoot.tr("Use groups"); checkable: true; checked: appRoot.groupedLayoutEnabled; onTriggered: appRoot.groupedLayoutEnabled=!appRoot.groupedLayoutEnabled }
        GlassMenuItem { text:appRoot.tr("Quick Download…");onTriggered:canvasQuickDownload.open() }
        // Same import as dropping a pack on the window.
        GlassMenuItem { text:appRoot.tr("Import modpack from file…");enabled:!prismBridge.importingLocalPack;onTriggered:modpackFileDialog.open() }
        GlassMenuItem { text:appRoot.tr("Sync from a code…");onTriggered:instanceSyncPopup.begin("receive","") }
        GlassMenuItem { text: appRoot.tr("Show Quick Download cards"); checkable: true; checked: appRoot.quickCards; onTriggered: appRoot.quickCards=!appRoot.quickCards }
        GlassMenuSeparator { }
        GlassMenu {
            id: canvasGroupingMenu; title: appRoot.tr("Group by")
            Instantiator {
                model: ["Off", "Smart", "Minecraft version", "Mod loader", "Installed status", "Custom"]
                delegate: GlassMenuItem {
                    required property string modelData
                    text: appRoot.tr(modelData); checkable: true; checked: appRoot.groupingMethod===modelData
                    onTriggered: appRoot.groupingMethod=modelData
                }
                onObjectAdded: function(index,object) { canvasGroupingMenu.insertItem(index,object) }
                onObjectRemoved: function(index,object) { canvasGroupingMenu.removeItem(object) }
            }
        }
        GlassMenu {
            id: canvasBackgroundMenu; title: appRoot.tr("Background")
            Instantiator {
                model: ["White", "Gray", "Black", "Custom", "Custom color"]
                delegate: GlassMenuItem {
                    required property string modelData
                    text: modelData === "Custom" ? appRoot.tr("Current custom wallpaper") : modelData === "Custom color" ? appRoot.tr("Current custom color") : appRoot.tr(modelData)
                    enabled: modelData!=="Custom" || appRoot.backgroundImage.length>0
                    checkable: true; checked: appRoot.backgroundMode===modelData
                    onTriggered: appRoot.backgroundMode=modelData
                }
                onObjectAdded: function(index,object) { canvasBackgroundMenu.insertItem(index,object) }
                onObjectRemoved: function(index,object) { canvasBackgroundMenu.removeItem(object) }
            }
        }
    }
    GlassMenu {
        id: cardContextMenu
        parent: appRoot.contentItem
        property var contextKeys: []
        readonly property bool multiple: contextKeys.length>1
        GlassMenu {
            title:appRoot.tr("Layer");enabled:appRoot.freeCanvasActive
            GlassMenuItem {text:appRoot.tr("Bring to front");onTriggered:appRoot.reorderFreeLayers(cardContextMenu.contextKeys,"front")}
            GlassMenuItem {text:appRoot.tr("Move forward");onTriggered:appRoot.reorderFreeLayers(cardContextMenu.contextKeys,"up")}
            GlassMenuItem {text:appRoot.tr("Move backward");onTriggered:appRoot.reorderFreeLayers(cardContextMenu.contextKeys,"down")}
            GlassMenuItem {text:appRoot.tr("Send to back");onTriggered:appRoot.reorderFreeLayers(cardContextMenu.contextKeys,"back")}
        }
        GlassMenu {
            title:appRoot.tr("Card size")
            GlassMenuItem {text:appRoot.tr("Custom…");onTriggered:{appRoot.cardSizeEditing=true;appRoot.statusMessage=appRoot.tr("Drag card edges · 180×126 to 640×480 · Esc to finish")}}
            GlassMenuItem { text:appRoot.tr("Small");onTriggered:appRoot.setCardPresetSize(cardContextMenu.contextKeys,"Small") }
            GlassMenuItem { text:appRoot.tr("Medium");onTriggered:appRoot.setCardPresetSize(cardContextMenu.contextKeys,"Medium") }
            GlassMenuItem { text:appRoot.tr("Large");onTriggered:appRoot.setCardPresetSize(cardContextMenu.contextKeys,"Large") }
        }
        // Applies to every selected card.
        GlassMenu {
            title:appRoot.tr("Aspect ratio")
            GlassMenuItem { text:appRoot.tr("Default");checkable:true;checked:cardContextMenu.visible && appRoot.cardAspectIs(cardContextMenu.contextKeys,240/168);onTriggered:appRoot.setCardAspect(cardContextMenu.contextKeys,240/168) }
            GlassMenuItem { text:"1:1";checkable:true;checked:cardContextMenu.visible && appRoot.cardAspectIs(cardContextMenu.contextKeys,1);onTriggered:appRoot.setCardAspect(cardContextMenu.contextKeys,1) }
            GlassMenuItem { text:"16:9";checkable:true;checked:cardContextMenu.visible && appRoot.cardAspectIs(cardContextMenu.contextKeys,16/9);onTriggered:appRoot.setCardAspect(cardContextMenu.contextKeys,16/9) }
            GlassMenuItem { text:"4:3";checkable:true;checked:cardContextMenu.visible && appRoot.cardAspectIs(cardContextMenu.contextKeys,4/3);onTriggered:appRoot.setCardAspect(cardContextMenu.contextKeys,4/3) }
        }
        // Card picture for every selected card: the picture itself, how it
        // fills the card and the colour behind it.
        GlassMenu {
            id: cardBackgroundMenu
            title:appRoot.tr("Background")
            readonly property var keys: cardContextMenu.contextKeys
            GlassMenuItem {
                text: cardContextMenu.multiple ? appRoot.tr("Choose picture for selected…") : appRoot.tr("Change background…")
                onTriggered: appRoot.chooseBackgroundFor(cardBackgroundMenu.keys)
            }
            GlassMenuSeparator { }
            GlassMenu {
                title:appRoot.tr("Fill mode")
                GlassMenuItem { text:appRoot.tr("Fill");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"fit","fill");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{fit:"fill"}) }
                GlassMenuItem { text:appRoot.tr("Fit");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"fit","fit");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{fit:"fit"}) }
                GlassMenuItem { text:appRoot.tr("Stretch");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"fit","stretch");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{fit:"stretch"}) }
                GlassMenuItem { text:appRoot.tr("Original size");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"fit","original");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{fit:"original"}) }
            }
            GlassMenu {
                title:appRoot.tr("Colour behind the picture")
                GlassMenuItem { text:appRoot.tr("Automatic");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"color","");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{color:""}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{color:"glass",glassTint:""});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{color:"glass",glassTint:""}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass, theme colour");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{color:"glass",glassTint:"accent"});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{color:"glass",glassTint:"accent"}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass, picture colour");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{color:"glass",glassTint:"artwork"});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{color:"glass",glassTint:"artwork"}) }
                GlassMenuItem {
                    text:appRoot.tr("Custom…")
                    onTriggered: {
                        var keys=cardBackgroundMenu.keys.slice(), first=appRoot.artworkPlacement(keys[0]).color
                        appRoot.pickColor(first && first!=="glass" ? first : "#1F1F1F",
                            function(value){ appRoot.setArtworkPlacementFor(keys,{color:value.toString()}) },
                            appRoot.tr("Colour behind the picture"))
                    }
                }
            }
            // Cards that show the built-in loader icon (no picture).
            GlassMenu {
                title:appRoot.tr("Icon background")
                GlassMenuItem { text:appRoot.tr("Automatic");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"iconFill","");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{iconFill:""}) }
                GlassMenuItem { text:appRoot.tr("Transparent");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementIs(cardBackgroundMenu.keys,"iconFill","transparent");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{iconFill:"transparent"}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:""});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:""}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass, theme colour");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:"accent"});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:"accent"}) }
                GlassMenuItem { text:appRoot.tr("Liquid Glass, icon colour");checkable:true;checked:cardContextMenu.visible && appRoot.artworkPlacementMatches(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:"artwork"});onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{iconFill:"glass",glassTint:"artwork"}) }
                GlassMenuItem {
                    text:appRoot.tr("Custom…")
                    onTriggered: {
                        var keys=cardBackgroundMenu.keys.slice(), first=appRoot.artworkPlacement(keys[0]).iconFill
                        appRoot.pickColor(first && first.charAt(0)==="#" ? first : "#1F1F1F",
                            function(value){ appRoot.setArtworkPlacementFor(keys,{iconFill:value.toString()}) },
                            appRoot.tr("Icon background"))
                    }
                }
            }
            GlassMenuSeparator { }
            GlassMenuItem { text:appRoot.tr("Reset position and size");onTriggered:appRoot.setArtworkPlacementFor(cardBackgroundMenu.keys,{fit:"fill",scale:1,x:0,y:0,color:""}) }
            GlassMenuItem { text:appRoot.tr("Remove background");onTriggered:appRoot.removeBackgrounds(cardBackgroundMenu.keys.slice()) }
        }
        GlassMenuItem { text:appRoot.tr("Show on canvas");checkable:true;checked:cardContextMenu.contextKeys.every(function(k){return appRoot.freeHidden.indexOf(k)<0});onTriggered:{var show=cardContextMenu.contextKeys.some(function(k){return appRoot.freeHidden.indexOf(k)>=0});cardContextMenu.contextKeys.forEach(function(k){appRoot.setFreeVisible(k,show)})} }
        GlassMenuItem {
            text: appRoot.tr("Launch"); visible: !cardContextMenu.multiple
            enabled: cardContextMenu.contextKeys.length===1 && !!appRoot.instanceRecord(cardContextMenu.contextKeys[0]) && appRoot.instanceRecord(cardContextMenu.contextKeys[0]).installed
            onTriggered: appRoot.activateCard(appRoot.instanceRecord(cardContextMenu.contextKeys[0]))
        }
        GlassMenuItem { text:appRoot.tr("Play offline…");visible:!cardContextMenu.multiple;enabled:cardContextMenu.contextKeys.length===1 && !!appRoot.instanceRecord(cardContextMenu.contextKeys[0]) && appRoot.instanceRecord(cardContextMenu.contextKeys[0]).installed;onTriggered:{prismBridge.promptOffline(cardContextMenu.contextKeys[0])} }
        GlassMenuItem { text: appRoot.tr("Kill"); visible: !cardContextMenu.multiple; enabled: false }
        GlassMenuItem { text: appRoot.tr("Edit…"); visible: !cardContextMenu.multiple; onTriggered: appRoot.editInstance(cardContextMenu.contextKeys[0]) }
        GlassMenuSeparator { visible: !cardContextMenu.multiple }
        GlassMenuItem { text: cardContextMenu.multiple ? appRoot.tr("Duplicate selected instances") : appRoot.tr("Duplicate"); onTriggered: appRoot.duplicateCards(cardContextMenu.contextKeys) }
        GlassMenuItem { text: appRoot.tr("Folder"); visible: !cardContextMenu.multiple; onTriggered: appRoot.showInstanceFolder(cardContextMenu.contextKeys[0]) }
        GlassMenu {
            title: appRoot.tr("Export"); rowHidden: cardContextMenu.multiple
            GlassMenuItem { text: appRoot.tr("Instance configuration…"); onTriggered: appRoot.requestExport(cardContextMenu.contextKeys,false) }
            GlassMenuItem { text: appRoot.tr("Mod list…"); onTriggered: appRoot.requestExport(cardContextMenu.contextKeys,true) }
        }
        GlassMenu {
            title: appRoot.tr("Sync to another PC"); rowHidden: cardContextMenu.multiple
            // Quick Download cards are no instances yet: a code creates one.
            GlassMenuItem { text: appRoot.tr("Share this instance…"); enabled: String(cardContextMenu.contextKeys[0]).indexOf("prism:") === 0; onTriggered: instanceSyncPopup.begin("share", cardContextMenu.contextKeys[0]) }
            GlassMenuItem { text: appRoot.tr("Sync from a code…"); onTriggered: instanceSyncPopup.begin("receive", String(cardContextMenu.contextKeys[0]).indexOf("prism:") === 0 ? cardContextMenu.contextKeys[0] : "") }
        }
        GlassMenuItem { text: appRoot.tr("Copy"); onTriggered: macWindowMetrics.copyText(appRoot.exportSelection(cardContextMenu.contextKeys)) }
        GlassMenuItem {
            text: appRoot.tr("Delete…"); visible: !cardContextMenu.multiple
            onTriggered: { appRoot.deletionKeys=cardContextMenu.contextKeys.slice();if(!macWindowMetrics.requestDeleteConfirmation())deleteInstanceDialog.open() }
        }
        GlassMenuItem { text: appRoot.tr("Create Shortcut…"); visible: !cardContextMenu.multiple; onTriggered: shortcutDialog.open() }
        GlassMenuSeparator { }
        GlassMenuItem {
            text: appRoot.tr("New group with selection…")
            onTriggered: { groupManagerPopup.pendingKeys=cardContextMenu.contextKeys.slice();groupManagerPopup.open() }
        }
        GlassMenu {
            id: moveToGroupMenu
            title: appRoot.tr("Change Group"); enabled: appRoot.instanceGroups.length>0
            Instantiator {
                model: appRoot.instanceGroups
                delegate: GlassMenuItem {
                    required property var modelData
                    text: appRoot.tr(modelData.name)
                    onTriggered: appRoot.moveCardsToGroup(cardContextMenu.contextKeys,modelData.id)
                }
                onObjectAdded: function(index,object){moveToGroupMenu.insertItem(index,object)}
                onObjectRemoved: function(index,object){moveToGroupMenu.removeItem(object)}
            }
        }
        GlassMenuItem { text: appRoot.tr("Remove from group"); onTriggered: appRoot.moveCardsToGroup(cardContextMenu.contextKeys,"") }
    }
    Shortcut {
        sequences: ["Ctrl+A","Meta+A"]
        enabled: appRoot.activePage==="Launch" && !appRoot.searchExpanded && !appRoot.accountMenuOpen && !groupManagerPopup.visible
        onActivated: appRoot.selectedCardKeys=appRoot.sortedCards.map(function(c){return c.key})
    }
    Shortcut {
        sequence: "Escape"
        enabled: appRoot.activePage==="Launch" && appRoot.selectedCardKeys.length>1 && !cardContextMenu.visible && !groupManagerPopup.visible
        onActivated: appRoot.selectedCardKeys=[]
    }
    Popup {
        id:accountsPopup;parent:appRoot.contentItem;anchors.centerIn:parent
        width:Math.min(480,appRoot.width-40);height:Math.min(appRoot.height-40,accountManagerColumn.implicitHeight+40)
        modal:true;focus:true;padding:20;popupType:appRoot.liquidGlass?Popup.Item:Popup.Window
        Overlay.modal: SheetDim {}
        onOpened:macWindowMetrics.setAccountGlass(contentItem,true)
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        Timer {interval:32;repeat:true;running:accountsPopup.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(accountsPopup.contentItem,true)}
        background:SheetBackground {}
        contentItem:Column {
            id:accountManagerColumn;spacing:12
            GlassText {text:appRoot.tr("Accounts");color:appRoot.ink;font.pixelSize:20;font.bold:true}
            ListView {width:parent.width;height:Math.min(220,count*48);clip:true;spacing:8;model:prismBridge.savedAccounts || [];delegate:RowLayout {
                required property var modelData;width:accountManagerColumn.width;spacing:10
                ConnectionButton {Layout.fillWidth:true;text:(modelData.selected?"✓  ":"")+modelData.name;onClicked:prismBridge.selectSavedAccount(modelData.id)}
                ConnectionButton {text:appRoot.tr("Remove");onClicked:{removeAccountPopup.accountId=modelData.id;removeAccountPopup.open()}}
            }}
            GlassText {visible:!(prismBridge.savedAccounts || []).length;text:appRoot.tr("No saved Microsoft accounts");color:appRoot.muted;font.pixelSize:13}
            // Trailing buttons, default action last (macOS).
            RowLayout {width:parent.width;spacing:10
                Item {Layout.fillWidth:true}
                ConnectionButton {text:appRoot.tr("Close");onClicked:accountsPopup.close()}
                ConnectionButton {primary:true;text:appRoot.tr("Add Account…");onClicked:{accountsPopup.close();loginPopup.open();prismBridge.signIn()}}
            }
        }
    }
    Popup {
        id:removeAccountPopup;property string accountId:"";parent:appRoot.contentItem;anchors.centerIn:parent
        width:340;height:150;modal:true;focus:true;padding:20;popupType:appRoot.liquidGlass?Popup.Item:Popup.Window
        Overlay.modal: SheetDim {}
        onOpened:macWindowMetrics.setAccountGlass(contentItem,true)
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        Timer {interval:32;repeat:true;running:removeAccountPopup.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(removeAccountPopup.contentItem,true)}
        background:SheetBackground {}
        contentItem:Column {spacing:16
            GlassText {text:appRoot.tr("Remove this saved account?");color:appRoot.ink}
            Row {spacing:12
                ConnectionButton {text:appRoot.tr("Cancel");onClicked:removeAccountPopup.close()}
                ConnectionButton {text:appRoot.tr("Remove");onClicked:{prismBridge.removeSavedAccount(removeAccountPopup.accountId);removeAccountPopup.close()}}
            }
        }
    }
    Popup {
        id:loginPopup
        Connections {
            target: prismBridge
            function onChanged() {
                if(prismBridge.signingIn && !loginPopup.visible)loginPopup.open()
                else if(!prismBridge.signingIn && prismBridge.status===appRoot.tr("Microsoft account added"))loginPopup.close()
            }
        }
        parent:appRoot.contentItem;anchors.centerIn:parent
        width:Math.min(540,appRoot.width-40);height:Math.min(appRoot.height-40,loginColumn.implicitHeight+48)
        modal:true;focus:true;padding:24;popupType:appRoot.liquidGlass?Popup.Item:Popup.Window;closePolicy:Popup.NoAutoClose
        Overlay.modal: SheetDim {}
        onOpened:macWindowMetrics.setAccountGlass(contentItem,true)
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        Timer {interval:32;repeat:true;running:loginPopup.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(loginPopup.contentItem,true)}
        // Windows: liquid glass under a sheet-material tint. Bare glass
        // refracted the canvas cards straight through the text.
        background:SheetBackground {}
        // macOS sign-in sheet. Everything shares one left edge: title, QR,
        // status; the steps and code field form a second column beside the
        // QR. Trailing buttons, default action last. A finished attempt hides
        // the now-stale code.
        property bool codeCopied: false
        Timer {id:codeCopiedTimer;interval:1500;onTriggered:loginPopup.codeCopied=false}
        readonly property bool waitingForCode: prismBridge.signingIn && !!prismBridge.loginCode
        readonly property bool failed: !prismBridge.signingIn && prismBridge.status!=="Microsoft account added"
        contentItem:Column {id:loginColumn;spacing:20
            Column {
                width:parent.width;spacing:4
                GlassText {width:parent.width;text:appRoot.tr("Sign in with Microsoft");color:appRoot.ink;font.pixelSize:22;font.bold:true}
                GlassText {width:parent.width;text:appRoot.tr("Use the Microsoft account that owns Minecraft.");color:appRoot.muted;font.pixelSize:14;wrapMode:Text.Wrap}
            }
            RowLayout {
                visible:loginPopup.waitingForCode
                width:parent.width;spacing:22
                RoundedPanel {
                    Layout.preferredWidth:156;Layout.preferredHeight:156;Layout.alignment:Qt.AlignTop
                    radius:12;color:"white"
                    rimWidth:appRoot.darkMode?0:1;rimColor:"#1A000000"
                    Image {anchors.fill:parent;anchors.margins:10;source:prismBridge.loginQr || "";fillMode:Image.PreserveAspectFit;smooth:false}
                }
                Column {
                    Layout.fillWidth:true;Layout.alignment:Qt.AlignTop;spacing:14
                    LoginStep {number:"1";text:appRoot.tr("Scan the QR code with your phone, or choose Open Microsoft.")}
                    LoginStep {number:"2";text:appRoot.tr("Enter this code, then approve the sign-in.")}
                    RoundedPanel {
                        width:parent.width;height:54
                        radius:12;color:appRoot.darkMode?"#1AFFFFFF":"#0D000000"
                        rimWidth:1;rimColor:appRoot.darkMode?"#14FFFFFF":"#0D000000"
                        GlassText {
                            x:16;anchors.verticalCenter:parent.verticalCenter
                            text:prismBridge.loginCode || "";color:appRoot.ink
                            font.family:"Consolas";font.pixelSize:24;font.bold:true;font.letterSpacing:3
                        }
                        Rectangle {
                            id:copyCodeButton
                            anchors.right:parent.right;anchors.rightMargin:10;anchors.verticalCenter:parent.verticalCenter
                            width:copyCodeLabel.implicitWidth+24;height:30;radius:15
                            color:copyCodeTap.pressed?(appRoot.darkMode?"#33FFFFFF":"#26000000"):copyCodeHover.hovered?(appRoot.darkMode?"#24FFFFFF":"#1A000000"):(appRoot.darkMode?"#14FFFFFF":"#0D000000")
                            Accessible.role:Accessible.Button;Accessible.name:appRoot.tr("Copy code")
                            GlassText {id:copyCodeLabel;anchors.centerIn:parent;text:loginPopup.codeCopied?appRoot.tr("Copied"):appRoot.tr("Copy");color:loginPopup.codeCopied?appRoot.accent:appRoot.ink;font.pixelSize:12;font.bold:true}
                            HoverHandler {id:copyCodeHover;cursorShape:Qt.PointingHandCursor}
                            TapHandler {id:copyCodeTap;onTapped:{prismBridge.copyLoginCode();loginPopup.codeCopied=true;codeCopiedTimer.restart()}}
                        }
                    }
                }
            }
            // One footer line: spinner and status from the shared left edge,
            // buttons trailing. The raw step text is replaced while waiting
            // for approval. Hidden items take no space in the layout.
            RowLayout {
                width:parent.width;spacing:10
                Item {
                    id:loginSpinner
                    visible:prismBridge.signingIn
                    Layout.preferredWidth:14;Layout.preferredHeight:14
                    Canvas {
                        anchors.fill:parent
                        onPaint:{var c=getContext("2d");c.reset();c.lineWidth=2;c.lineCap="round";c.strokeStyle=appRoot.muted;c.beginPath();c.arc(7,7,5.5,0,Math.PI*1.5);c.stroke()}
                        RotationAnimator on rotation {from:0;to:360;duration:900;loops:Animation.Infinite;running:loginSpinner.visible}
                    }
                }
                GlassText {
                    Layout.fillWidth:true
                    text:loginPopup.waitingForCode?appRoot.tr("Waiting for approval in your browser…"):prismBridge.status
                    wrapMode:Text.Wrap;font.pixelSize:13
                    color:loginPopup.failed?"#FF6961":appRoot.muted
                }
                ConnectionButton {text:prismBridge.signingIn?appRoot.tr("Cancel"):appRoot.tr("Close");onClicked:{prismBridge.cancelSignIn();loginPopup.close()}}
                ConnectionButton {
                    primary:true
                    text:prismBridge.signingIn?appRoot.tr("Open Microsoft"):appRoot.tr("Try Again")
                    enabled:prismBridge.signingIn?!!prismBridge.loginUrl:true
                    onClicked:if(prismBridge.signingIn)Qt.openUrlExternally(prismBridge.loginUrl);else prismBridge.signIn()
                }
            }
        }
    }
    Popup {
        id:accountSettingsPopup;parent:appRoot.contentItem;anchors.centerIn:parent
        width:Math.min(540,appRoot.width-40);height:Math.min(appRoot.height-40,contentItem.implicitHeight+40);padding:20;modal:true;focus:true
        Overlay.modal: SheetDim {}
        popupType:appRoot.liquidGlass?Popup.Item:Popup.Window
        onOpened:{macWindowMetrics.setAccountGlass(contentItem,true);Qt.callLater(function(){clientIdField.forceActiveFocus(Qt.PopupFocusReason)})}
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        Timer {interval:16;repeat:true;running:accountSettingsPopup.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(accountSettingsPopup.contentItem,true)}
        background:SheetBackground {}
        contentItem:Column {
            spacing:12
            GlassText {text:appRoot.tr("Microsoft sign-in");color:appRoot.ink;font.pixelSize:20}
            GlassText {width:parent.width;text:appRoot.tr("Vitra Launcher needs its own registered Microsoft application. Enable personal Microsoft accounts and public client flows, then enter the Application (client) ID. Minecraft API access may also require approval. Never enter a password or client secret here.");wrapMode:Text.WordWrap;color:appRoot.muted}
            ConnectionField {id:clientIdField;width:parent.width;text:prismBridge.microsoftClientId();placeholderText:appRoot.tr("Microsoft client ID");activeFocusOnPress:true;readonly property bool validClientId:/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(text.trim())}
            Row {spacing:10
                ConnectionButton {text:appRoot.tr("Register app");onClicked:Qt.openUrlExternally("https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")}
                ConnectionButton {text:appRoot.tr("Setup guide");onClicked:Qt.openUrlExternally("https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-registration")}
            }
            GlassText {width:parent.width;visible:clientIdField.text.length>0 && !clientIdField.validClientId;text:appRoot.tr("Enter the Application (client) ID in UUID format.");color:appRoot.muted;wrapMode:Text.WordWrap}
            Row {width:parent.width;layoutDirection:Qt.RightToLeft
                ConnectionButton {text:appRoot.tr("Close");onClicked:accountSettingsPopup.close()}
            }
            ConnectionButton {text:appRoot.tr("Save and sign in");enabled:clientIdField.validClientId;onClicked:{prismBridge.setMicrosoftClientId(clientIdField.text);if(prismBridge.microsoftClientId().toLowerCase()===clientIdField.text.trim().toLowerCase()){accountSettingsPopup.close();loginPopup.open();prismBridge.signIn()}}}
        }
    }
    Popup {
        id: themeLibraryPopup
        parent: appRoot.contentItem; anchors.centerIn: parent
        width: Math.min(780,appRoot.width-48)
        // Bars, the gallery between them with 16 pt above and below.
        height: Math.min(appRoot.height-48, themeSheetHeader.height + 16 + themeGallery.implicitHeight + themeSheetFooter.height)
        padding: 0; modal: true; focus: true
        Overlay.modal: SheetDim {}
        popupType: Popup.Item
        property string selectedId: ""
        readonly property var selectedTheme: { var revision = themeStore.themes; return themeStore.theme(selectedId) }
        onOpened: {
            selectedId = appRoot.appliedThemeId || (themeStore.themes.length ? themeStore.themes[0].id : "")
            appRoot.themeMessage = ""
            themeLibraryScroll.contentY = -themeLibraryScroll.topMargin
        }
        background: SheetBackground {}
        // Like a Download page: the gallery scrolls under a blurred title bar
        // and a blurred button bar, each with a hairline, to the sheet's edges.
        contentItem: Item {
            id: themeSheet
            layer.enabled: true; layer.smooth: true
            layer.effect: ContinuousClip { radius: 24; rimWidth: appRoot.customWindowChrome ? 1 : 0; rimColor: appRoot.darkMode ? "#1FFFFFFF" : "#14000000" }
            // What the bars blur and the buttons' glass refracts.
            Item {
                id: themeSheetBackdrop
                anchors.fill: parent
                Item {
                    id: themeSheetScene
                    anchors.fill: parent
                    Rectangle { anchors.fill: parent; color: appRoot.popupSurface; visible: appRoot.customWindowChrome }
                    Flickable {
                        id: themeLibraryScroll
                        anchors.fill: parent
                        // The gallery runs to the sheet's bottom edge, under the
                // floating glass buttons; the last row can scroll clear of them.
                topMargin: themeSheetHeader.height + 16; bottomMargin: themeSheetFooter.height
                        contentHeight: themeGallery.implicitHeight; contentWidth: width
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { topPadding: themeSheetHeader.height + 4; bottomPadding: themeSheetFooter.height + 4 }
                        ThemeGallery {
                            id: themeGallery; x: 24; width: themeLibraryScroll.width - 48; height: implicitHeight
                            themes: themeStore.themes; selectedId: themeLibraryPopup.selectedId
                            ink: appRoot.ink; muted: appRoot.muted; accent: appRoot.accent; dark: appRoot.darkMode
                            catImageFor: function(id) { return themeStore.catImage(id) }
                            onSelected: function(themeId) { themeLibraryPopup.selectedId = themeId }
                        }
                    }
                }
                SheetBar { source: themeSheetScene; width: parent.width; height: themeSheetHeader.height; hairlineAtBottom: true }
            }
            ShaderEffectSource {
                id: themeSheetTexture
                sourceItem: themeLibraryPopup.visible ? themeSheetBackdrop : null
                textureSize: Qt.size(Math.ceil(themeSheetBackdrop.width * appRoot.glassPixelRatio), Math.ceil(themeSheetBackdrop.height * appRoot.glassPixelRatio))
                live: themeLibraryPopup.visible; hideSource: false; visible: false; smooth: true
            }
            // Title bar: 24 pt insets, everything on one centre line.
            Item {
                id: themeSheetHeader
                width: parent.width; height: 72
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24
                    spacing: 10
                    GlassText { text: appRoot.tr("Themes"); color: appRoot.ink; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                    SheetButton { text: appRoot.tr("Create theme…"); onClicked: saveThemePopup.open() }
                    SheetButton { text: appRoot.tr("Import…"); onClicked: themeImportDialog.open() }
                }
            }
            // The buttons, 24 pt from the sheet's sides and bottom.
            Item {
                id: themeSheetFooter
                y: parent.height - height
                width: parent.width; height: themeSheetFooterColumn.implicitHeight + 40
                Column {
                    id: themeSheetFooterColumn
                    x: 24; y: 16; width: parent.width - 48
                    RowLayout {
                        width: parent.width; spacing: 10
                        SheetButton {
                            scene: themeSheetBackdrop; texture: themeSheetTexture
                            text: appRoot.tr("Export…"); enabled: !!themeLibraryPopup.selectedTheme.id
                            onClicked: { themeExportDialog.themeId = themeLibraryPopup.selectedId; themeExportDialog.open() }
                        }
                        SheetButton { scene: themeSheetBackdrop; texture: themeSheetTexture; text: appRoot.tr("Remove"); visible: !!themeLibraryPopup.selectedTheme.id && !themeLibraryPopup.selectedTheme.builtIn; onClicked: removeThemePopup.open() }
                        Item { Layout.fillWidth: true }
                        SheetButton { scene: themeSheetBackdrop; texture: themeSheetTexture; text: appRoot.tr("Close"); onClicked: themeLibraryPopup.close() }
                        SheetButton { scene: themeSheetBackdrop; texture: themeSheetTexture; primary: true; text: appRoot.tr("Use theme"); enabled: !!themeLibraryPopup.selectedTheme.id; onClicked: appRoot.applyTheme(themeLibraryPopup.selectedTheme) }
                    }
                }
            }
        }
    }
    Popup {
        id: saveThemePopup
        property string saveError: ""
        parent: appRoot.contentItem; anchors.centerIn: parent
        width: Math.min(440,appRoot.width-48); height: contentItem.implicitHeight+48
        padding: 24; modal: true; focus: true; popupType: Popup.Item
        Overlay.modal: SheetDim {}
        onOpened: { saveError=""; newThemeName.text=""; newThemeAuthor.text=""; newThemeName.forceActiveFocus() }
        background: SheetBackground {}
        contentItem: Column {
            spacing: 14
            GlassText { text: appRoot.tr("Create theme"); color: appRoot.ink; font.pixelSize: 20; font.bold: true }
            GlassText { width: parent.width; text: appRoot.tr("Adjust Appearance and Liquid Glass in Settings, then save the current look. Wallpapers are included in shared files."); color: appRoot.muted; font.pixelSize: 13; wrapMode: Text.Wrap }
            GroupField { id: newThemeName; width: parent.width; maximumLength: 80; placeholderText: appRoot.tr("Theme name") }
            GroupField { id: newThemeAuthor; width: parent.width; maximumLength: 80; placeholderText: appRoot.tr("Author (optional)") }
            GlassText { width: parent.width; text: saveThemePopup.saveError; visible: !!text; color: appRoot.muted; wrapMode: Text.Wrap; font.pixelSize: 12 }
            RowLayout {
                width: parent.width; spacing: 10
                Item { Layout.fillWidth: true }
                ConnectionButton { text: appRoot.tr("Cancel"); onClicked: saveThemePopup.close() }
                ConnectionButton {
                    primary: true; text: appRoot.tr("Save theme"); enabled: newThemeName.text.trim().length > 0
                    onClicked: {
                        var saved = themeStore.saveTheme({format:"vitra-theme",version:1,name:newThemeName.text,author:newThemeAuthor.text,appearance:appRoot.currentThemeAppearance()})
                        if (saved.id) { appRoot.applyTheme(saved); themeLibraryPopup.selectedId=saved.id; saveThemePopup.close() }
                        else saveThemePopup.saveError=themeStore.error
                    }
                }
            }
        }
    }
    Popup {
        id: saveGlassPresetPopup
        parent: appRoot.contentItem; anchors.centerIn: parent
        width: Math.min(440,appRoot.width-48); height: contentItem.implicitHeight+48
        padding: 24; modal: true; focus: true; popupType: Popup.Item
        Overlay.modal: SheetDim {}
        onOpened: { glassPresetName.text = appRoot.glassPresetIndex(appRoot.glassPresetChoice) >= 0 ? appRoot.glassPresetChoice : ""; glassPresetName.forceActiveFocus() }
        background: SheetBackground {}
        contentItem: Column {
            spacing: 14
            GlassText { text: appRoot.tr("Save Liquid Glass preset"); color: appRoot.ink; font.pixelSize: 20; font.bold: true }
            GlassText { width: parent.width; text: appRoot.tr("Saves the current Liquid Glass parameters. While a preset is chosen, themes do not change Liquid Glass."); color: appRoot.muted; font.pixelSize: 13; wrapMode: Text.Wrap }
            GroupField {
                id: glassPresetName; width: parent.width; maximumLength: 60; placeholderText: appRoot.tr("Preset name")
                Keys.onReturnPressed: if (text.trim().length) { appRoot.saveGlassPreset(text); saveGlassPresetPopup.close() }
            }
            GlassText {
                width: parent.width; visible: appRoot.glassPresetIndex(glassPresetName.text.trim()) >= 0
                text: appRoot.tr("A preset with this name exists and will be replaced."); color: appRoot.muted; font.pixelSize: 12; wrapMode: Text.Wrap
            }
            RowLayout {
                width: parent.width; spacing: 10
                Item { Layout.fillWidth: true }
                ConnectionButton { text: appRoot.tr("Cancel"); onClicked: saveGlassPresetPopup.close() }
                ConnectionButton {
                    primary: true; text: appRoot.tr("Save preset"); enabled: glassPresetName.text.trim().length > 0
                    onClicked: { appRoot.saveGlassPreset(glassPresetName.text); saveGlassPresetPopup.close() }
                }
            }
        }
    }
    Popup {
        id: removeThemePopup
        parent: appRoot.contentItem; anchors.centerIn: parent
        width: Math.min(380,appRoot.width-48); height: contentItem.implicitHeight+48
        padding: 24; modal: true; focus: true; popupType: Popup.Item
        Overlay.modal: SheetDim {}
        background: SheetBackground {}
        contentItem: Column {
            spacing: 18
            GlassText { width: parent.width; text: appRoot.tr("Remove this saved theme?"); color: appRoot.ink; wrapMode: Text.Wrap; font.pixelSize: 17; font.bold: true }
            RowLayout {
                width: parent.width; spacing: 10
                Item { Layout.fillWidth: true }
                ConnectionButton { text: appRoot.tr("Cancel"); onClicked: removeThemePopup.close() }
                ConnectionButton {
                    text: appRoot.tr("Remove")
                    onClicked: {
                        var id = themeLibraryPopup.selectedId
                        if (themeStore.removeTheme(id)) {
                            if (appRoot.appliedThemeId===id) appRoot.appliedThemeId=""
                            themeLibraryPopup.selectedId=themeStore.themes[0].id
                            removeThemePopup.close()
                        }
                    }
                }
            }
        }
    }
    Popup {
        id:canvasQuickDownload;parent:appRoot.contentItem;anchors.centerIn:parent
        width:Math.min(360,appRoot.width-40);height:Math.min(appRoot.height-40,contentItem.implicitHeight+padding*2);padding:24;modal:true;focus:true;popupType:appRoot.liquidGlass?Popup.Item:Popup.Window
        Overlay.modal: SheetDim {}
        onOpened:{macWindowMetrics.setAccountGlass(contentItem,true);downloadData.loadQuickVersions(false)}
        onClosed:macWindowMetrics.setAccountGlass(contentItem,false)
        Timer {interval:16;repeat:true;running:canvasQuickDownload.visible && macWindowMetrics.nativeGlassDock;onTriggered:macWindowMetrics.setAccountGlass(canvasQuickDownload.contentItem,true)}
        background:SheetBackground {}
        contentItem:Column {
            spacing:14
            GlassText {text:appRoot.tr("Quick Download");font.pixelSize:20;font.bold:true;color:appRoot.ink}
            GlassSelect {accountMaterial:true;id:canvasQuickVersionSelect;width:parent.width;controlHeight:36;cornerRadius:12;options:appRoot.quickVersionOptions;selected:appRoot.sidebarQuickVersion;onChosen:function(value){appRoot.sidebarQuickVersion=value}}
            GlassSelect {accountMaterial:true;width:parent.width;controlHeight:36;cornerRadius:12;options:["Vanilla","Fabric","Forge","NeoForge","Quilt"];selected:appRoot.sidebarQuickLoader;onChosen:function(value){appRoot.sidebarQuickLoader=value}}
            GlassText {width:parent.width;text:appRoot.tr("Continue to choose a compatible loader release and install.");wrapMode:Text.WordWrap;color:appRoot.muted;font.pixelSize:11}
            GlassText {
                width:parent.width; visible:downloadData.quickVersionsBusy || !!downloadData.quickVersionsError
                text:downloadData.quickVersionsBusy ? appRoot.tr("Loading Minecraft versions…") : downloadData.quickVersionsError
                color:appRoot.muted;font.pixelSize:11;wrapMode:Text.WordWrap
            }
            ConnectionButton {visible:!!downloadData.quickVersionsError;text:appRoot.tr("Retry versions");onClicked:downloadData.loadQuickVersions(true)}
            RowLayout {
                width:parent.width;spacing:10
                Item {Layout.fillWidth:true}
                ConnectionButton {text:appRoot.tr("Cancel");onClicked:canvasQuickDownload.close()}
                ConnectionButton {primary:true;text:appRoot.tr("Continue");onClicked:{canvasQuickDownload.close();appRoot.beginDownload({category:"Versions",name:appRoot.tr("Minecraft ")+appRoot.sidebarQuickVersion,version:appRoot.sidebarQuickVersion,detail:appRoot.tr("Java Edition")})}}
            }
        }
    }
    // Original account card in a window popup: same QML layout, above native views.
    Popup {
        id: accountPopup
        parent: appRoot.contentItem
        popupType: macWindowMetrics.nativeGlassDock ? Popup.Window : Popup.Item
        visible: appRoot.accountMenuOpen
        modal: false
        dim: false
        focus: true
        padding: 0
        margins: 12
        // Windows: a macOS menu that stays inside the sidebar, above the
        // account footer, sized to its rows.
        readonly property bool inSidebar: appRoot.sidebarProgress>0.9
        width: appRoot.customWindowChrome && inSidebar ? sidebar.width-24 : Math.min(appRoot.customWindowChrome?280:340,appRoot.width-24)
        height: appRoot.customWindowChrome ? accountMenuColumn.implicitHeight+16 : 216
        x: Math.max(12,Math.min(appRoot.width-width-12,inSidebar?sidebar.x+(appRoot.customWindowChrome?12:22):compactAccountButton.x+compactAccountButton.width-width))
        y: Math.max(12,Math.min(appRoot.height-height-12,inSidebar?sidebarAccountFooter.y-height-(appRoot.customWindowChrome?6:10):compactAccountButton.y+compactAccountButton.height+10))
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: if (macWindowMetrics.nativeGlassDock) macWindowMetrics.setAccountGlass(accountMenu, true)
        onClosed: {
            appRoot.accountMenuOpen = false
            macWindowMetrics.setAccountGlass(accountMenu, false)
        }
        background: Item {
            Rectangle {
                anchors.fill: parent
                visible: !appRoot.customWindowChrome
                radius: 24
                color: macWindowMetrics.nativeAccountGlass ? "transparent" : "#3D000000"
            }
            MenuPanel {
                anchors.fill: parent
                visible: appRoot.customWindowChrome
                open: appRoot.customWindowChrome && accountPopup.visible
            }
        }
        // Windows: the rows sit straight on the menu panel behind them.
        contentItem: GlassPane {
            id: accountMenu
            objectName: "menuPanelContent"
            color: macWindowMetrics.nativeAccountGlass || appRoot.customWindowChrome ? "transparent" : appRoot.glassStrong
            border.width: macWindowMetrics.nativeAccountGlass || appRoot.customWindowChrome ? 0 : 1
            border.color: appRoot.outline
            edgeGlow: !macWindowMetrics.nativeAccountGlass && !appRoot.customWindowChrome
            backdropBlur: false
            radius: appRoot.customWindowChrome ? 13 : 24
            emphasized: true
            clip: !appRoot.customWindowChrome
            solidInPopup: false
        Column {
            id: accountMenuColumn
            anchors.fill: parent
            anchors.margins: appRoot.customWindowChrome ? 8 : 16
            spacing: appRoot.customWindowChrome ? 4 : 12
            Row {
                width: parent.width
                height: appRoot.customWindowChrome ? 52 : 46
                leftPadding: appRoot.customWindowChrome ? 8 : 0
                spacing: appRoot.customWindowChrome ? 10 : 12
                GlassSurface {
                    TapHandler {onTapped:{appRoot.accountMenuOpen=false;accountsPopup.open()}}
                    objectName: "accountGlassControl"
                    solidInPopup: false
                    anchors.verticalCenter: parent.verticalCenter
                    width: appRoot.customWindowChrome ? 36 : 44; height: width; radius: width / 2
                    color: macWindowMetrics.nativeAccountGlass ? "transparent" : (appRoot.darkMode ? "#527FA0C4" : "#9ED5EBFC")
                    Image { anchors.centerIn: parent; width: parent.width * 0.68; height: width; source: macWindowMetrics.defaultAccountAvatar; fillMode: Image.PreserveAspectFit }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: appRoot.customWindowChrome ? 2 : 4
                    TextField {
                        id: profileName
                        text: prismBridge.offlineMode ? prismBridge.offlineName : (prismBridge.currentAccountName || appRoot.tr("Not signed in"))
                        width: accountMenu.width-(appRoot.customWindowChrome?80:112); height:appRoot.customWindowChrome?22:26; padding:0;leftInset:0;rightInset:0;leftPadding:0;rightPadding:0
                        readOnly: true; selectByMouse: !readOnly
                        font.bold:true;font.pixelSize:appRoot.customWindowChrome?14:15
                        color:readOnly?"transparent":appRoot.ink
                        GlassText {visible:profileName.readOnly;x:0;anchors.verticalCenter:parent.verticalCenter;width:parent.width;text:profileName.text;color:appRoot.ink;font:profileName.font;elide:Text.ElideRight}
                        background:Rectangle {color:profileName.readOnly?"transparent":appRoot.glassSoft;radius:6}
                        MouseArea {anchors.fill:parent;z:10;preventStealing:true;enabled:profileName.readOnly;onDoubleClicked:{if(!prismBridge.offlineMode)return;profileName.readOnly=false;profileName.forceActiveFocus();profileName.selectAll()}}
                        onAccepted:{if(prismBridge.offlineMode){if(!prismBridge.renameOffline(text))return}else appRoot.accountDisplayName=text.trim();readOnly=true;focus=false}
                        onEditingFinished: {if(!readOnly){if(prismBridge.offlineMode)prismBridge.renameOffline(text);else appRoot.accountDisplayName=text.trim();readOnly=true}}
                        Keys.onEscapePressed:{text=prismBridge.offlineMode?prismBridge.offlineName:appRoot.accountDisplayName;readOnly=true;focus=false}
                    }
                    GlassText { text: prismBridge.offlineMode ? appRoot.tr("Offline profile") : (prismBridge.currentAccountName?appRoot.tr("Microsoft account"):appRoot.tr("Not signed in")); font.pixelSize: appRoot.customWindowChrome ? 12 : 11; color: appRoot.muted; width: accountMenu.width - (appRoot.customWindowChrome ? 80 : 112); elide: Text.ElideRight }
                }
            }
            // macOS menu separator: inset hairline.
            Rectangle {
                x: appRoot.customWindowChrome ? 8 : 0
                width: parent.width - 2 * x; height: 1
                color: appRoot.customWindowChrome ? (appRoot.darkMode ? "#26FFFFFF" : "#1A000000") : appRoot.outline
            }
            // Windows menu rows: leading symbol, left-aligned title, accent
            // highlight with white text under the pointer.
            AccountMenuRow {
                visible: appRoot.customWindowChrome
                symbol: "person.crop.circle"; title: appRoot.tr("Add Microsoft account…")
                onActivated: { appRoot.accountMenuOpen = false; loginPopup.open(); prismBridge.useMicrosoft() }
            }
            AccountMenuRow {
                visible: appRoot.customWindowChrome && !prismBridge.microsoftClientId()
                symbol: "gearshape"; title: appRoot.tr("Account settings…")
                onActivated: { appRoot.accountMenuOpen = false; accountSettingsPopup.open() }
            }
            Item {
                visible: appRoot.customWindowChrome
                width: parent.width; height: 40
                SymbolImage { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; symbol: "wifi.slash"; tint: appRoot.ink }
                GlassText { x: 36; anchors.verticalCenter: parent.verticalCenter; text: appRoot.tr("Play offline"); color: appRoot.ink; font.pixelSize: 13 }
                GlassSwitch {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    padding: 0; scale: 0.8; transformOrigin: Item.Right
                    checked: prismBridge.offlineMode; onToggled: prismBridge.setOfflineMode(checked)
                    Accessible.name: appRoot.tr("Play offline")
                }
            }
            GlassSurface {
                visible: !appRoot.customWindowChrome
                objectName: "accountGlassControl"
                property bool glassHovered: microsoftHover.hovered
                width: parent.width; height: 40; radius: 16
                color: macWindowMetrics.nativeAccountGlass ? "transparent" : microsoftHover.hovered ? (appRoot.darkMode ? "#4D719BC3" : "#A5D5ECFC") : "#24FFFFFF"
                border.width: macWindowMetrics.nativeAccountGlass ? 0 : 1; border.color: appRoot.outline
                HoverHandler { id: microsoftHover }
                GlassText {
                    anchors.centerIn: parent
                    text: appRoot.tr("＋  Add Microsoft account")
                    color: appRoot.ink
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        appRoot.accountMenuOpen = false
                        loginPopup.open();prismBridge.useMicrosoft()
                    }
                }
            }
            RowLayout {
                visible:!appRoot.customWindowChrome
                width:parent.width;spacing:8
                Row {
                    spacing:8
                    // AppKit places its NSSwitch over this marker; QML paths use GlassSwitch.
                    Rectangle {
                        visible:macWindowMetrics.nativeAccountGlass
                        objectName:"accountGlassControl"
                        width:56;height:36;radius:18
                        property string nativeKind:"switch"
                        property bool nativeChecked:prismBridge.offlineMode
                        signal nativeActivated()
                        onNativeActivated:prismBridge.setOfflineMode(!prismBridge.offlineMode)
                        color:macWindowMetrics.nativeAccountGlass ? "transparent" : prismBridge.offlineMode ? Qt.rgba(appRoot.accent.r,appRoot.accent.g,appRoot.accent.b,0.38) : appRoot.glassSoft
                        border.width:macWindowMetrics.nativeAccountGlass?0:1;border.color:appRoot.outline
                        Accessible.role:Accessible.CheckBox;Accessible.name:appRoot.tr("Play offline");Accessible.checked:prismBridge.offlineMode
                        activeFocusOnTab:true
                        Keys.onSpacePressed:prismBridge.setOfflineMode(!prismBridge.offlineMode)
                        Rectangle {visible:!macWindowMetrics.nativeAccountGlass;objectName:"accountGlassControl";width:22;height:22;radius:11;y:7;x:prismBridge.offlineMode?31:3;color:macWindowMetrics.nativeAccountGlass?"#60FFFFFF":"white";Behavior on x {NumberAnimation {duration:160}}}
                        TapHandler {onTapped:prismBridge.setOfflineMode(!prismBridge.offlineMode)}
                    }
                    GlassSwitch {
                        visible:!macWindowMetrics.nativeAccountGlass;padding:4
                        anchors.verticalCenter:parent.verticalCenter
                        checked:prismBridge.offlineMode;onToggled:prismBridge.setOfflineMode(checked)
                        Accessible.name:appRoot.tr("Play offline")
                    }
                    GlassText {text:appRoot.tr("Offline");color:appRoot.ink;font.pixelSize:12;anchors.verticalCenter:parent.verticalCenter}
                }
                Item {Layout.fillWidth:true}
                GlassSurface {
                    objectName:"accountGlassControl";visible:!prismBridge.microsoftClientId();width:96;height:36;radius:18
                    property string nativeKind:"button"
                    signal nativeActivated()
                    onNativeActivated:{appRoot.accountMenuOpen=false;accountSettingsPopup.open()}
                    color:macWindowMetrics.nativeAccountGlass?"transparent":appRoot.glassSoft
                    border.width:macWindowMetrics.nativeAccountGlass?0:1;border.color:appRoot.outline
                    GlassText {visible:!macWindowMetrics.nativeAccountGlass;anchors.centerIn:parent;text:appRoot.tr("Settings");color:appRoot.ink;font.pixelSize:12}
                    TapHandler {onTapped:{appRoot.accountMenuOpen=false;accountSettingsPopup.open()}}
                }
            }
        }
    }
    }
    GlassPane {
        id: statusDock
        visible: false
        z: 40
        HoverHandler { id: statusHover }
        // Keep the status above the dock and away from the sidebar.
        anchors.right: parent.right; anchors.rightMargin: 32; anchors.bottom: parent.bottom; anchors.bottomMargin: 110
        width: Math.min(355, appRoot.width - appRoot.contentLeft - 64)
        height: 38; radius: 19; subtle: true
        color: appRoot.darkMode ? appRoot.glassSoft : "#F3F8FD"
        GlassText { anchors.centerIn: parent; text: statusMessage; color: muted; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 24; horizontalAlignment: Text.AlignHCenter }
    }
    // macOS-style close / minimize / zoom buttons for the frameless Windows
    // window: coloured while the window is active, glyphs on hover.
    function windowButton(kind) {
        if (kind === "close") close()
        else if (kind === "minimize") showMinimized()
        else if (visibility === Window.Maximized) showNormal()
        else showMaximized()
    }
    // macOS metrics, measured from the native window: 14 pt buttons, 23 pt
    // apart centre to centre; the same 9 pt inset from the left and top edges.
    Row {
        id: windowButtons
        readonly property real buttonSize: 14
        readonly property real inset: 9
        visible: appRoot.trafficLights
        z: 1001
        x: inset; y: inset - appRoot.contentItem.y
        spacing: 9
        HoverHandler { id: windowButtonsHover }
        Repeater {
            model: [{kind: "close", name: appRoot.tr("Close"), fill: "#FF5F57", edge: "#E0443E", glyph: "#4D0000"},
                    {kind: "minimize", name: appRoot.tr("Minimize"), fill: "#FEBC2E", edge: "#DEA123", glyph: "#995700"},
                    {kind: "zoom", name: appRoot.tr("Maximize"), fill: "#28C840", edge: "#1AAB29", glyph: "#006500"}]
            delegate: Rectangle {
                required property var modelData
                readonly property bool lit: appRoot.active || !appRoot.greyInactiveWindowButtons || windowButtonsHover.hovered
                width: windowButtons.buttonSize; height: width; radius: width / 2
                antialiasing: true
                readonly property color base: lit ? modelData.fill : (appRoot.darkMode ? "#4D4D50" : "#D1D1D4")
                color: "transparent"
                Accessible.role: Accessible.Button; Accessible.name: modelData.name
                // Liquid Glass light on a flat colour: a very thin bright line
                // along the top edge and a fainter one along the bottom, both
                // fading out towards the sides (almost none left and right).
                Canvas {
                    anchors.fill: parent
                    readonly property string signature: String(parent.base) + parent.lit
                    onSignatureChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"), s = width, c = s / 2, line = 0.9, r = c - line / 2 - 0.3
                        ctx.reset()
                        ctx.fillStyle = String(parent.base)
                        ctx.beginPath(); ctx.arc(c, c, c, 0, Math.PI * 2); ctx.fill()
                        function edge(alpha, from, to) {
                            var fade = ctx.createLinearGradient(0, 0, s, 0)
                            fade.addColorStop(0, "rgba(255,255,255,0)")
                            fade.addColorStop(0.5, "rgba(255,255,255," + alpha + ")")
                            fade.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.strokeStyle = fade; ctx.lineWidth = line; ctx.lineCap = "round"
                            ctx.beginPath(); ctx.arc(c, c, r, from, to, false); ctx.stroke()
                        }
                        var lit = parent.lit
                        edge(lit ? 0.75 : 0.4, Math.PI * 1.12, Math.PI * 1.88)  // top
                        edge(lit ? 0.4 : 0.22, Math.PI * 0.12, Math.PI * 0.88)  // bottom
                    }
                }
                // Close: ×, minimize: −, zoom: +. Stroked from the exact circle
                // centre; rotated thin rectangles snapped off-centre at
                // fractional display scales.
                Canvas {
                    anchors.fill: parent
                    visible: windowButtonsHover.hovered
                    onPaint: {
                        var ctx = getContext("2d"), c = width / 2, h = width * 0.243
                        ctx.reset(); ctx.strokeStyle = modelData.glyph; ctx.lineWidth = 1.4; ctx.lineCap = "round"
                        ctx.beginPath()
                        if (modelData.kind === "close") { ctx.moveTo(c - h * 0.72, c - h * 0.72); ctx.lineTo(c + h * 0.72, c + h * 0.72); ctx.moveTo(c + h * 0.72, c - h * 0.72); ctx.lineTo(c - h * 0.72, c + h * 0.72) }
                        else { ctx.moveTo(c - h, c); ctx.lineTo(c + h, c); if (modelData.kind === "zoom") { ctx.moveTo(c, c - h); ctx.lineTo(c, c + h) } }
                        ctx.stroke()
                    }
                }
                // Hit area spans the gaps (no dead space between buttons).
                MouseArea { x: -windowButtons.spacing / 2; y: -7; width: parent.width + windowButtons.spacing; height: parent.height + 14; onClicked: appRoot.windowButton(modelData.kind) }
            }
        }
    }
    // Windows 11 caption buttons (traffic lights switched off): 46 × 32 pt,
    // Segoe Fluent Icons glyphs, flush with the top-right corner; close turns
    // red (#C42B1C) with a white glyph on hover.
    Row {
        id: captionButtons
        visible: appRoot.customWindowChrome && !appRoot.macWindowControls
        z: 1001
        x: appRoot.width - width; y: -appRoot.contentItem.y
        Repeater {
            model: [{kind: "minimize", name: appRoot.tr("Minimize"), glyph: ""},
                    {kind: "zoom", name: appRoot.visibility === Window.Maximized ? appRoot.tr("Restore") : appRoot.tr("Maximize"), glyph: appRoot.visibility === Window.Maximized ? "" : ""},
                    {kind: "close", name: appRoot.tr("Close"), glyph: ""}]
            delegate: Rectangle {
                required property var modelData
                readonly property bool closeButton: modelData.kind === "close"
                width: 46; height: 32
                color: captionArea.pressed ? (closeButton ? "#E5C42B1C" : (appRoot.darkMode ? "#0FFFFFFF" : "#0A000000"))
                       : captionArea.containsMouse ? (closeButton ? "#C42B1C" : (appRoot.darkMode ? "#1AFFFFFF" : "#0F000000")) : "transparent"
                Accessible.role: Accessible.Button; Accessible.name: modelData.name
                GlassText {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: "Segoe Fluent Icons"; font.pixelSize: 10
                    color: parent.closeButton && captionArea.containsMouse ? "white"
                           : appRoot.active ? appRoot.ink : appRoot.muted
                }
                MouseArea { id: captionArea; anchors.fill: parent; hoverEnabled: true; onClicked: appRoot.windowButton(modelData.kind) }
            }
        }
    }
    MouseArea {
        id:windowDragStrip;z:1000;x:0;y:-appRoot.contentItem.y;width:appRoot.width
        height:Math.max(24,topBar.y+appRoot.contentItem.y)
        acceptedButtons:Qt.LeftButton;preventStealing:true
        HoverHandler {id:windowStripHover}
        onPressed:function(mouse){appRoot.startSystemMove();mouse.accepted=true}
        onDoubleClicked:if(appRoot.visibility===Window.Maximized)appRoot.showNormal();else appRoot.showMaximized()
    }
    DropArea {
        id: modpackDropArea
        objectName: "modpackDropArea"
        anchors.fill: parent; z: 2000
        onEntered: function(drag) {
            if (drag.hasUrls && (drag.supportedActions & Qt.CopyAction)) drag.accept(Qt.CopyAction)
            else drag.accepted=false
        }
        onDropped: function(drop) {
            if (!drop.hasUrls || !(drop.supportedActions & Qt.CopyAction)) return
            drop.accept(Qt.CopyAction)
            if (appRoot.editorDropBucket) appRoot.handleEditorDrop(appRoot.editorDropBucket, drop.urls)
            else appRoot.handleModpackDrop(drop.urls)
        }
        Rectangle {
            anchors.fill: parent; visible: modpackDropArea.containsDrag
            color: appRoot.darkMode ? "#B01A1D25" : "#B0F2F4F8"
            Rectangle {
                anchors.centerIn: parent; width: Math.min(440,parent.width-48); height: 140
                radius: 24; color: appRoot.popupSurface; border.width: 2; border.color: appRoot.accent
                Column {
                    anchors.centerIn: parent; width: parent.width-32; spacing: 10
                    GlassText { anchors.horizontalCenter: parent.horizontalCenter; text: "↓"; color: appRoot.accent; font.pixelSize: 32 }
                    GlassText { width: parent.width; text: appRoot.editorDropBucket ? appRoot.tr("Drop files to add them to %1").replace("%1", appRoot.tr(appRoot.editorTab)) : appRoot.tr("Drop a modpack to create an instance"); color: appRoot.ink; font.pixelSize: 17; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
                    GlassText { width: parent.width; text: appRoot.editorDropBucket ? (appRoot.editorDropBucket === "worlds" ? appRoot.tr("World folders (with level.dat)") : appRoot.editorDropBuckets[appRoot.editorDropBucket]) + "  ·  " + appRoot.tr("several at once") : ".mrpack  ·  .zip"; color: appRoot.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                }
            }
        }
    }
    Item {
        id: packImportPanel
        objectName: "packImportPanel"
        z: 2001; visible: appRoot.packImportNotice
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 70
        width: Math.min(440,appRoot.width-48); height: packImportContent.implicitHeight+32
        RoundedPanel { anchors.fill: parent; radius: 20; color: appRoot.popupSurface; rimWidth: 1; rimColor: appRoot.hairline }
        Column {
            id: packImportContent; x: 16; y: 16; width: parent.width-32; spacing: 10
            GlassText { width: parent.width; text: prismBridge.importingLocalPack ? appRoot.tr("Importing modpack") : appRoot.noticeTitle || appRoot.tr("Modpack import"); color: appRoot.ink; font.pixelSize: 15; font.bold: true }
            GlassText { width: parent.width; text: appRoot.packImportOverride ? appRoot.packImportMessage : prismBridge.status; color: appRoot.muted; font.pixelSize: 13; wrapMode: Text.Wrap; textFormat: Text.PlainText }
            RowLayout {
                width: parent.width; spacing: 10
                Rectangle {
                    visible: prismBridge.importingLocalPack
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: appRoot.fieldFill
                    Rectangle { width: parent.width*Math.max(0,Math.min(1,prismBridge.installProgress)); height: parent.height; radius: 2; color: appRoot.accent }
                }
                Item { visible: !prismBridge.importingLocalPack; Layout.fillWidth: true }
                ConnectionButton { glass: false; visible: prismBridge.importingLocalPack; enabled: prismBridge.canCancelInstall; text: appRoot.tr("Cancel"); onClicked: prismBridge.cancelInstall() }
                ConnectionButton { glass: false; visible: !prismBridge.importingLocalPack; text: appRoot.tr("Close"); onClicked: appRoot.packImportNotice=false }
            }
        }
    }

}
