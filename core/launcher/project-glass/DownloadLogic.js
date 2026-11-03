.pragma library

// Interface text from the "ProjectGlass" translation (see Main.qml's tr).
function tr(text) { return qsTranslate("ProjectGlass", text) }

var components = { Vanilla: "net.minecraft", Fabric: "net.fabricmc.fabric-loader", Forge: "net.minecraftforge", NeoForge: "net.neoforged", Quilt: "org.quiltmc.quilt-loader" }
var projectTypes = { Mods: "mod", Shaders: "shader", "Resource packs": "resourcepack", Modpacks: "modpack" }
function array(value) { if (!Array.isArray(value)) throw new Error(tr("Unexpected response format")); return value }
function indexVersions(data) { return array(data && data.versions) }
function stamp(value) { var n = Date.parse(value || ""); return isNaN(n) ? 0 : n }
function date(value) { return value ? value.slice(0, 10) : tr("Date unavailable") }
function newest(a, b) { return stamp(b.date) - stamp(a.date) || b.label.localeCompare(a.label) }
function compareGame(a, b) {
    var x = a.match(/\d+|[^\d]+/g) || [], y = b.match(/\d+|[^\d]+/g) || []
    for (var i = 0; i < Math.min(x.length, y.length); i++) {
        var n = /^\d+$/.test(x[i]) && /^\d+$/.test(y[i]) ? Number(x[i]) - Number(y[i]) : x[i].localeCompare(y[i])
        if (n) return n
    }
    return x.length - y.length
}
function minecraftCatalogue(data, query, sort) {
    var q = query.trim().toLowerCase()
    var rows = indexVersions(data).filter(function(v) { return v.type === "release" && v.version && v.version.toLowerCase().indexOf(q) !== -1 }).map(function(v) {
        return { category: "Versions", name: "Minecraft " + v.version, version: v.version, badge: v.version, detail: tr("Java Edition · ") + date(v.releaseTime), date: v.releaseTime, icon: "" }
    })
    rows.sort(function(a, b) { return sort === "Name A–Z" ? a.name.localeCompare(b.name) : stamp(b.date) - stamp(a.date) })
    return rows
}
function searchUrl(base, category, query, sort, offset, loader) {
    if (!projectTypes[category]) throw new Error(tr("Unknown project category"))
    var facets = [["project_type:" + projectTypes[category]]]
    if (category === "Mods" && loader && loader !== "All loaders") facets.push(["categories:" + loader.toLowerCase()])
    var index = sort === "Newest" ? "newest" : sort === "Updated" ? "updated" : "relevance"
    return base + "/search?query=" + encodeURIComponent(query) + "&facets=" + encodeURIComponent(JSON.stringify(facets)) + "&index=" + index + "&limit=20&offset=" + offset
}
function projects(data, category) {
    return array(data && data.hits).filter(function(p) { return p.project_id && p.title }).map(function(p) {
        return { category: category, provider: "Modrinth", projectId: p.project_id, slug: p.slug || "", name: p.title, detail: p.description || "", badge: category === "Mods" ? "MOD" : "PACK", icon: p.icon_url || "" }
    })
}
// CurseForge: Minecraft game id 432; class ids per category; mod loader type ids.
var curseForgeClasses = { Mods: 6, Shaders: 6552, "Resource packs": 12, Modpacks: 4471 }
var curseForgeLoaders = { Forge: 1, Fabric: 4, Quilt: 5, NeoForge: 6 }
function curseForgeSearchUrl(base, category, query, sort, offset, loader) {
    if (!curseForgeClasses[category]) throw new Error(tr("Unknown project category"))
    // sortField: 2 popularity, 3 last updated, 11 release date.
    var field = sort === "Newest" ? 11 : sort === "Updated" ? 3 : 2
    var url = base + "/mods/search?gameId=432&classId=" + curseForgeClasses[category] + "&searchFilter=" + encodeURIComponent(query) + "&sortField=" + field + "&sortOrder=desc&pageSize=20&index=" + offset
    if (category === "Mods" && curseForgeLoaders[loader]) url += "&modLoaderType=" + curseForgeLoaders[loader]
    return url
}
function curseForgeProjects(data, category) {
    return array(data && data.data).filter(function(p) { return p.id && p.name }).map(function(p) {
        return { category: category, provider: "CurseForge", projectId: String(p.id), slug: p.slug || "", name: p.name, detail: p.summary || "", badge: category === "Mods" ? "MOD" : "PACK", icon: p.logo ? p.logo.thumbnailUrl || p.logo.url || "" : "" }
    })
}
// CurseForge files in the Modrinth version shape projectRows reads; raw keeps the original file for installation.
function curseForgeVersions(data) {
    var loaders = ["forge", "fabric", "quilt", "neoforge"]
    return array(data && data.data).filter(function(f) { return f.id && f.isAvailable !== false }).map(function(f) {
        var tags = f.gameVersions || []
        return { id: String(f.id), name: f.displayName || f.fileName, version_number: f.fileName || "", date_published: f.fileDate || "",
                 version_type: f.releaseType === 2 ? "beta" : f.releaseType === 3 ? "alpha" : "release",
                 game_versions: tags.filter(function(t) { return /^\d+\.\d+/.test(t) }),
                 loaders: tags.map(function(t) { return t.toLowerCase() }).filter(function(t) { return loaders.indexOf(t) >= 0 }),
                 // relationType 3: required dependency.
                 dependencies: (f.dependencies || []).filter(function(d) { return d.relationType === 3 && d.modId }).map(function(d) { return { project_id: String(d.modId), dependency_type: "required" } }),
                 raw: f }
    })
}
// Required projects of the best-matching releases (the first rank present), in first-seen order.
function requiredDependencies(rows, selfId) {
    var best = rows.length ? rows[0].rank : 0, ids = []
    rows.forEach(function(r) {
        if (r.rank !== best) return
        var deps = r.dependencies || []
        deps.forEach(function(d) {
            var id = d.project_id ? String(d.project_id) : ""
            if (d.dependency_type === "required" && id && id !== selfId && ids.indexOf(id) < 0) ids.push(id)
        })
    })
    return ids
}
function modrinthDependencies(data) {
    return array(data).filter(function(p) { return p.id && p.title }).map(function(p) {
        return { category: "Mods", provider: "Modrinth", projectId: p.id, slug: p.slug || "", name: p.title, detail: p.description || "", badge: "MOD", icon: p.icon_url || "" }
    })
}
// CurseForge descriptions are HTML; images and embeds would stretch the page.
function curseForgeDescription(html) {
    return String(html || "").replace(/<(img|iframe)\b[^>]*>(<\/iframe>)?/gi, "")
}
function requirementsMatch(row, game) {
    var reqs = row.requires || []
    for (var i = 0; i < reqs.length; i++) {
        if (reqs[i].uid === "net.minecraft" && reqs[i].equals && reqs[i].equals !== game) return false
    }
    return true
}
function loaderRows(data, loader, game) {
    return indexVersions(data).filter(function(v) {
        if (!v.version || !requirementsMatch(v, game)) return false
        // Forge and NeoForge must explicitly identify the exact Minecraft version.
        return loader === "Fabric" || loader === "Quilt" || (v.requires || []).some(function(r) { return r.uid === "net.minecraft" && r.equals === game })
    }).map(function(v) {
        return { id: loader + ":" + v.version, loaderVersion: v.version, label: v.version, date: v.releaseTime || "", detail: date(v.releaseTime) + (v.recommended ? tr(" · Recommended") : ""), group: loader + tr(" · Minecraft ") + game, gameVersion: game, eligible: true }
    }).sort(newest)
}
function projectRows(data, target, loader, category) {
    var wanted = loader.toLowerCase()
    return array(data).filter(function(v) { return v.id && Array.isArray(v.game_versions) && v.game_versions.length }).map(function(v) {
        var games = v.game_versions.slice().sort(function(a, b) { return -compareGame(a, b) })
        var sameGame = !!target && games.indexOf(target) >= 0
        var sameLoader = category !== "Mods" || (v.loaders || []).indexOf(wanted) >= 0
        var game = sameGame ? target : games[0]
        var rank = sameGame ? (sameLoader ? 0 : 1) : 2
        var group = category === "Modpacks" ? tr("New instance · Minecraft ") + game : rank === 0 ? tr("Current instance · Minecraft ") + target : rank === 1 ? "Minecraft " + target + tr(" · Different loader") : "Minecraft " + game
        // Why this version cannot go into the target instance.
        var issue = ""
        if (category !== "Modpacks" && target) {
            if (!sameGame) issue = tr("Made for Minecraft %1 · this instance uses %2").replace("%1", game).replace("%2", target)
            else if (!sameLoader) issue = tr("Needs %1 · this instance uses %2").replace("%1", (v.loaders || []).map(function(name) { return name.charAt(0).toUpperCase() + name.slice(1) }).join(", ")).replace("%2", loader)
        }
        return { id: v.id, label: v.name || v.version_number || v.id, date: v.date_published || "", gameVersion: game, group: group, rank: rank, issue: issue, eligible: category === "Modpacks" || (sameGame && sameLoader), raw: v.raw || v, versionType: v.version_type || "release",
                 detail: date(v.date_published) + " · " + (v.loaders || []).join(", ") + " · " + (v.version_type || "release"),
                 versionNumber: v.version_number || "", files: v.files || [], dependencies: v.dependencies || [], gameVersions: v.game_versions, loaders: v.loaders || [] }
    }).sort(function(a, b) { return a.rank - b.rank || (a.rank === 2 ? -compareGame(a.gameVersion, b.gameVersion) : 0) || newest(a, b) })
}
