// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// An instance's card picture, placed by its own settings (instance editor ›
// Background): fill mode, scale, offset and the colour behind it. The card,
// its glow, the dock, the lists and the editor preview all draw it with this
// item, so they match at any size.
//
// placement (Main.qml artworkPlacement): {
//   fit:   "fill"     cover the card, cropping (default, as before)
//          "fit"      the whole picture inside the card
//          "stretch"  exactly the card, distorting the picture
//          "original" the picture's own size, relative to a 240 pt card
//   scale: 0.1 … 4, multiplies the size above (default 1)
//   x, y:  -1 … 1, moves the picture's centre by up to half the card's
//          width / height (default 0, centred)
//   color: base colour behind the picture, "" = the picture's own tint,
//          "glass" = no base: the card's liquid glass shows through
// }
Item {
    id: art
    property url source
    property var placement: ({})
    // Optional decode size hint (the blurred glow needs few pixels).
    property size decodeSize: Qt.size(-1, -1)
    clip: true

    readonly property var fits: ["fill", "fit", "stretch", "original"]
    readonly property string fit: placement && fits.indexOf(placement.fit) >= 0 ? placement.fit : "fill"
    readonly property real userScale: placement ? Math.max(0.1, Math.min(4, Number(placement.scale) || 1)) : 1
    readonly property real offsetX: placement ? Math.max(-1, Math.min(1, Number(placement.x) || 0)) : 0
    readonly property real offsetY: placement ? Math.max(-1, Math.min(1, Number(placement.y) || 0)) : 0
    // A covering picture needs no base; the default stays exactly as before.
    readonly property bool glassBase: !!placement && placement.color === "glass"
    readonly property bool needsBase: !glassBase && !(fit === "fill" && userScale >= 1 && offsetX === 0 && offsetY === 0)
    // The automatic colour is the picture's tint on the dark card base, opaque
    // like a default card's fill, so it looks the same over the card's glow,
    // in the dock and in the editor preview.
    readonly property color pictureTint: !needsBase || (placement && placement.color) ? "transparent"
        : typeof macWindowMetrics !== "undefined" ? (macWindowMetrics.artworkTint(source) || "#80466E41") : "#80466E41"
    readonly property color baseColor: !needsBase ? "transparent"
        : placement && placement.color ? placement.color
        : pictureTint.a > 0.99 ? pictureTint : Qt.tint("#1F1F1F", Qt.rgba(pictureTint.r, pictureTint.g, pictureTint.b, 0.45))

    Rectangle { anchors.fill: parent; color: art.baseColor; visible: art.needsBase }
    Image {
        id: picture
        source: art.source
        smooth: true; mipmap: true; asynchronous: true
        fillMode: Image.Stretch
        sourceSize: art.decodeSize
        readonly property real naturalWidth: Math.max(1, implicitWidth)
        readonly property real naturalHeight: Math.max(1, implicitHeight)
        readonly property real coverScale: Math.max(art.width / naturalWidth, art.height / naturalHeight)
        readonly property real fitScale: Math.min(art.width / naturalWidth, art.height / naturalHeight)
        readonly property real originalScale: art.width / 240
        readonly property real baseScale: art.fit === "fit" ? fitScale : art.fit === "original" ? originalScale : coverScale
        width: (art.fit === "stretch" ? art.width : naturalWidth * baseScale) * art.userScale
        height: (art.fit === "stretch" ? art.height : naturalHeight * baseScale) * art.userScale
        x: (art.width - width) / 2 + art.offsetX * art.width / 2
        y: (art.height - height) / 2 + art.offsetY * art.height / 2
    }
}
