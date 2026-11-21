// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// Text, optically centred as the Apple HIG asks: Latin on its cap height,
// Chinese on its em box. Segoe UI's ascent leaves room for accents above the
// capitals, so text centred on its line box sits about 0.06 em low (Microsoft
// YaHei's ideographs about 0.03 em), i.e. 1 px at interface sizes. The glyphs
// move up by that amount in whole pixels (native text stays crisp); geometry,
// implicit size and layouts are unchanged.
Text {
    // Icon fonts centre their own glyphs; set 0 for those.
    property real opticalOffset: font.family === "Segoe Fluent Icons" ? 0
                                 : fontInfo.pixelSize >= 9 ? Math.max(1, Math.round(fontInfo.pixelSize * 0.06)) : 0
    transform: Translate { y: -opticalOffset }
}
