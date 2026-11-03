// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtCore

// Shared Liquid Glass tuning for the Windows renderer. Parameters use the
// Glass Lab JSON format (version 3): "复制参数" output pastes here unchanged,
// and parameters() copies back into the lab's "导入参数" dialog.
QtObject {
    id: tuning
    // Project Glass defaults (Glass Lab export, version 3).
    readonly property var defaults: ({
        frost: 0.33, refraction: 0.5984848484848485, glare: 0.21212121212121213, density: 0.35, strokeWidth: 0,
        refractiveIndex: 1.45, bevelWidth: 16, dispersion: 0.035, magnification: 1, blurSpread: 0.85,
        saturation: 1.1, brightness: 1.27, fresnelAmount: 1, specularAmount: 1, edgeAmount: 1, shadowAmount: 1,
        lightAngle: -120, interactionStrength: 1, interactionRadius: 70, responseTime: 80,
        materialVariant: 0, reduceBrightEffects: false, increaseContrast: false, frostedMode: false,
        reducedMotion: false, reducedTransparency: false, glassEnabled: true, fusionEnabled: true, fusionDistance: 15,
        // Launcher only (the lab ignores these): extra frost for the sidebar
        // rail and the strength of its Apple Music-style colour bleed.
        sidebarFrost: 0.3, sidebarGlow: 0.5, sidebarGlowCoverage: 0.2, sidebarGlowWidth: 100, sidebarGlowBlur: 0.3, sidebarGlowSaturation: 1,
        // Launcher only: how far in from its edge the pressed lens bends labels.
        lensLabelRange: 20
    })
    // Same ranges as the lab. Out-of-range numbers are clamped; any invalid
    // field rejects the whole payload before a live value changes.
    readonly property var ranges: ({
        frost: [0, 1], refraction: [0, 1], glare: [0, 1], density: [0, 1], strokeWidth: [0, 3],
        refractiveIndex: [1, 2.5], bevelWidth: [1, 40], dispersion: [0, 0.3], magnification: [0.5, 2], blurSpread: [0, 1],
        saturation: [0, 2.5], brightness: [0, 2], fresnelAmount: [0, 3], specularAmount: [0, 3], edgeAmount: [0, 3],
        shadowAmount: [0, 3], lightAngle: [-180, 180], interactionStrength: [0, 3], interactionRadius: [10, 200],
        fusionDistance: [1, 100], responseTime: [0, 500], materialVariant: [0, 4], sidebarFrost: [0, 1], sidebarGlow: [0, 1], sidebarGlowCoverage: [0.2, 0.65], sidebarGlowWidth: [80, 600], sidebarGlowBlur: [0, 1], sidebarGlowSaturation: [0, 1], lensLabelRange: [8, 32]
    })
    readonly property var flags: ["reduceBrightEffects", "increaseContrast", "frostedMode", "reducedMotion", "reducedTransparency", "glassEnabled", "fusionEnabled"]

    property real frost: defaults.frost
    property real refraction: defaults.refraction
    property real glare: defaults.glare
    property real density: defaults.density
    property real strokeWidth: defaults.strokeWidth
    property real refractiveIndex: defaults.refractiveIndex
    property real bevelWidth: defaults.bevelWidth
    property real dispersion: defaults.dispersion
    property real magnification: defaults.magnification
    property real blurSpread: defaults.blurSpread
    property real saturation: defaults.saturation
    property real brightness: defaults.brightness
    property real fresnelAmount: defaults.fresnelAmount
    property real specularAmount: defaults.specularAmount
    property real edgeAmount: defaults.edgeAmount
    property real shadowAmount: defaults.shadowAmount
    property real lightAngle: defaults.lightAngle
    property real interactionStrength: defaults.interactionStrength
    property real interactionRadius: defaults.interactionRadius
    property real responseTime: defaults.responseTime
    property int materialVariant: defaults.materialVariant
    property bool reduceBrightEffects: defaults.reduceBrightEffects
    property bool increaseContrast: defaults.increaseContrast
    property bool frostedMode: defaults.frostedMode
    property bool reducedMotion: defaults.reducedMotion
    property bool reducedTransparency: defaults.reducedTransparency
    property bool glassEnabled: defaults.glassEnabled
    property bool fusionEnabled: defaults.fusionEnabled
    property real fusionDistance: defaults.fusionDistance
    property real sidebarFrost: defaults.sidebarFrost
    property real sidebarGlow: defaults.sidebarGlow
    property real sidebarGlowCoverage: defaults.sidebarGlowCoverage
    property real sidebarGlowWidth: defaults.sidebarGlowWidth
    property real sidebarGlowBlur: defaults.sidebarGlowBlur
    property real sidebarGlowSaturation: defaults.sidebarGlowSaturation
    property real lensLabelRange: defaults.lensLabelRange

    // Material variants and accessibility switches, mapped as in Lab.qml.
    readonly property real frostProgress: frostedMode ? 1 : 0
    readonly property bool materialVisible: materialVariant !== 4
    readonly property real effectiveDensity: increaseContrast ? Math.max(0.65, density)
        : materialVariant === 1 ? Math.max(0.38, density)
        : materialVariant === 2 ? density * 0.35
        : materialVariant === 3 ? Math.max(0.68, density) : density
    readonly property real effectiveFrost: materialVariant === 2 ? frost * 0.25
        : materialVariant === 1 ? Math.max(0.65, frost)
        : materialVariant === 3 ? Math.max(0.8, frost)
        : frost + (1 - frost) * frostProgress
    readonly property real effectiveRefraction: refraction * (1 - 0.85 * frostProgress)
    readonly property real effectiveGlare: glare * (1 - 0.65 * frostProgress) * (reduceBrightEffects ? 0.3 : 1)
    readonly property real effectiveSpecular: specularAmount * (reduceBrightEffects ? 0.3 : 1)
    readonly property real effectiveEdge: edgeAmount * (reduceBrightEffects ? 0.4 : 1)
    readonly property real effectiveStrokeWidth: increaseContrast ? Math.max(1, strokeWidth) : strokeWidth
    readonly property real effectiveBlur: blurSpread + (Math.max(0.95, blurSpread) - blurSpread) * frostProgress
    // The blurred backdrop is only sampled when some frost is mixed in.
    readonly property bool needsBlur: effectiveFrost > 0.001 && !reducedTransparency
    // Sidebar surfaces are frostier than the dock and navigation.
    readonly property real effectiveSidebarFrost: Math.min(1, effectiveFrost + sidebarFrost)
    function strokeColor(dark) {
        return increaseContrast ? (dark ? "#B0FFFFFF" : "#A0000000") : (dark ? "#70FFFFFF" : "#60000000")
    }

    function parameters() {
        var result = {version: 3}
        for (var key in ranges) result[key] = tuning[key]
        for (var i = 0; i < flags.length; ++i) result[flags[i]] = tuning[flags[i]]
        return result
    }
    // Errors shown after "Paste from Glass Lab" (see Main.qml's tr).
    function tr(text) { return qsTranslate("ProjectGlass", text) }
    function apply(p) {
        if (!p || typeof p !== "object" || Array.isArray(p)) throw new Error(tr("Expected a parameter JSON object"))
        var next = {}
        for (var key in ranges) {
            var value = p[key] === undefined ? defaults[key] : p[key]
            if (typeof value !== "number" || !isFinite(value)) throw new Error(key + tr(" must be a finite number"))
            next[key] = Math.max(ranges[key][0], Math.min(ranges[key][1], value))
        }
        if (Math.floor(next.materialVariant) !== next.materialVariant) throw new Error(tr("materialVariant must be an integer"))
        for (var i = 0; i < flags.length; ++i) {
            var flag = flags[i]
            if (p[flag] !== undefined && typeof p[flag] !== "boolean") throw new Error(flag + tr(" must be a boolean"))
            next[flag] = p[flag] === undefined ? defaults[flag] : p[flag]
        }
        for (var name in next) tuning[name] = next[name]
    }
    function applyJson(text) {
        apply(JSON.parse(text))
    }
    function reset() {
        apply(defaults)
    }

    // Persist as the same JSON the lab exchanges, independent of launcher settings.
    property bool loaded: false
    property string savedJson: ""
    readonly property string serialized: JSON.stringify(parameters())
    onSerializedChanged: if (loaded) savedJson = serialized
    property Settings store: Settings {
        category: "ProjectGlassLiquidGlass"
        property alias parametersJson: tuning.savedJson
    }
    Component.onCompleted: {
        if (savedJson.length) {
            try { applyJson(savedJson) }
            catch (e) { console.warn("Ignoring saved Liquid Glass parameters:", e.message); reset() }
        }
        loaded = true
        savedJson = serialized
    }
}
