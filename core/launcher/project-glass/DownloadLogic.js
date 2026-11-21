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
// Items and paragraphs that held only an image are dropped with it.
function curseForgeDescription(html) {
    return String(html || "")
        .replace(/<(img|iframe|video|source)\b[^>]*>(<\/(iframe|video)>)?/gi, "")
        .replace(/<a\b[^>]*>\s*<\/a>/gi, "")
        .replace(/<li\b[^>]*>(\s|&nbsp;|<br\s*\/?>)*<\/li>/gi, "")
        .replace(/<p\b[^>]*>(\s|&nbsp;|<br\s*\/?>)*<\/p>/gi, "")
}

// A project description split into text and picture blocks: Qt's text
// renderer does not load remote images, so pictures become Image items between
// the text. Badges (shields and other small SVGs) are left out; an image
// wrapped in a link is shown without the link.
function descriptionImageUrl(tag) {
    var m = String(tag).match(/\bsrc\s*=\s*["']([^"']+)["']/i)
    return m ? decodeEntities(m[1]) : ""
}
function descriptionBadge(url) {
    return /shields\.io|badge|\.svg(\?|#|$)|bstats\.org|discord(app)?\.com\/api\/guilds/i.test(url)
}
function descriptionSegments(body, html) {
    var images = [], text = String(body || "")
    function token(url) {
        url = String(url || "").trim()
        if (!/^https?:\/\//i.test(url) || descriptionBadge(url)) return ""
        images.push(url)
        return "\n\n\u0001" + (images.length - 1) + "\u0001\n\n"
    }
    if (!html) {
        text = text.replace(/\r\n?/g, "\n")
            .replace(/<!--[\s\S]*?-->/g, "")
            .replace(/\[!\[[^\]]*\]\(\s*<?([^)\s>]+)>?[^)]*\)\]\([^)]*\)/g, function(m, url) { return token(url) })
            .replace(/!\[[^\]]*\]\(\s*<?([^)\s>]+)>?[^)]*\)/g, function(m, url) { return token(url) })
    }
    text = text.replace(/<a\b[^>]*>\s*(<img\b[^>]*>)\s*<\/a>/gi, function(m, tag) { return token(descriptionImageUrl(tag)) })
        .replace(/<img\b[^>]*>/gi, function(tag) { return token(descriptionImageUrl(tag)) })
    var parts = text.split(/\u0001(\d+)\u0001/), result = []
    for (var i = 0; i < parts.length; ++i) {
        if (i % 2) { result.push({ kind: "image", text: "", url: images[Number(parts[i])] }); continue }
        var block = html ? curseForgeDescription(parts[i]) : modrinthDescription(parts[i])
        var visible = html ? decodeEntities(block.replace(/<[^>]+>/g, "")).trim() : block.trim()
        if (visible.length) result.push({ kind: "text", text: block, url: "" })
    }
    return result
}

// Description translation (Translate button on a project page). A text
// block becomes Markdown with its link targets swapped for short tokens, so
// the translator cannot break the URLs; HTML (CurseForge) is reduced to
// Markdown first. The translation is shown as Markdown.
function htmlToMarkdown(html) {
    var text = String(html || "")
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, function(m, level, title) { return "\n\n" + "######".slice(0, Number(level)) + " " + title.replace(/<[^>]+>/g, "").trim() + "\n\n" })
        .replace(/<br\s*\/?>/gi, "  \n")
        .replace(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, function(m, href, label) {
            label = label.replace(/<[^>]+>/g, "").trim()
            return label.length ? "[" + label + "](" + href + ")" : ""
        })
        .replace(/<(b|strong)\b[^>]*>([\s\S]*?)<\/\1>/gi, "**$2**")
        .replace(/<(i|em)\b[^>]*>([\s\S]*?)<\/\1>/gi, "*$2*")
        .replace(/<li\b[^>]*>/gi, "\n- ")
        .replace(/<\/?(p|div|center|ul|ol|table|tr|blockquote|section|article|hr)\b[^>]*>/gi, "\n\n")
        .replace(/<\/?[a-zA-Z][^>]*>/g, "")
    return decodeEntities(text).replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
}
function translationSource(text, html) {
    var links = []
    var markdown = (html ? htmlToMarkdown(text) : String(text || ""))
        .replace(/\]\(([^)\s]+)\)/g, function(m, url) { links.push(url); return "](#" + (links.length - 1) + ")" })
    return { text: markdown, links: links }
}
function restoreTranslation(text, links) {
    return String(text || "")
        // Chinese and Japanese output turns Markdown marks full-width.
        .replace(/^([ \t]*)([＃#]{1,6})/gm, function(m, space, marks) { return space + marks.replace(/＃/g, "#") })
        .replace(/^([ \t]*)[－—•・]\s*/gm, "$1- ")
        .replace(/＊/g, "*").replace(/［/g, "[").replace(/］/g, "]")
        // Translators add spaces inside the Markdown punctuation.
        .replace(/\]\s*[\(（]\s*#\s*(\d+)\s*[\)）]/g, function(m, i) { return "](" + (links[Number(i)] || "#") + ")" })
        .replace(/\[\s+/g, "[").replace(/\*\*\s+([^*]+?)\s+\*\*/g, "**$1**")
        .replace(/^(#{1,6})([^#\s])/gm, "$1 $2")
}
// Splits at paragraph breaks into pieces of at most `limit` characters.
function translationChunks(text, limit) {
    var paragraphs = String(text || "").split(/(\n\n+)/), chunks = [], current = ""
    for (var i = 0; i < paragraphs.length; ++i) {
        var piece = paragraphs[i]
        while (piece.length > limit) {
            if (current.length) { chunks.push(current); current = "" }
            chunks.push(piece.slice(0, limit)); piece = piece.slice(limit)
        }
        if (current.length + piece.length > limit) { chunks.push(current); current = "" }
        current += piece
    }
    if (current.length) chunks.push(current)
    return chunks
}
// Google Translate's web endpoint: [[["translated","original",...],...],...].
function parseTranslation(data) {
    if (!Array.isArray(data) || !Array.isArray(data[0])) return null
    return data[0].map(function(part) { return Array.isArray(part) && typeof part[0] === "string" ? part[0] : "" }).join("")
}

function decodeEntities(text) {
    return text.replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
               .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&")
}
// Modrinth descriptions are Markdown with embedded HTML (details/summary,
// badges, centred images). Qt's Markdown renderer splits lists and inline
// code inside HTML blocks, leaving empty bullets and run-together text, and
// it never loads remote images. Reduce the body to plain Markdown: details
// open with their summary as a bold heading, simple tags become Markdown,
// images and image-only links and list items go, other tags are removed.
function modrinthDescription(markdown) {
    var text = String(markdown || "").replace(/\r\n?/g, "\n")
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
        .replace(/<(img|iframe|video|source|picture)\b[^>]*>(<\/(iframe|video|picture)>)?/gi, "")
        .replace(/<summary\b[^>]*>([\s\S]*?)<\/summary>/gi, function(m, title) { return "\n\n**" + title.trim() + "**\n\n" })
        .replace(/<\/?details\b[^>]*>/gi, "\n\n")
        .replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, function(m, level, title) { return "\n\n" + "######".slice(0, Number(level)) + " " + title.trim() + "\n\n" })
        .replace(/<br\s*\/?>/gi, "  \n")
        .replace(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, function(m, href, label) {
            label = label.replace(/<[^>]+>/g, "").trim()
            return label.length ? "[" + label + "](" + href + ")" : ""
        })
        .replace(/<(b|strong)\b[^>]*>([\s\S]*?)<\/\1>/gi, "**$2**")
        .replace(/<(i|em)\b[^>]*>([\s\S]*?)<\/\1>/gi, "*$2*")
        .replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, "`$1`")
        .replace(/<li\b[^>]*>/gi, "\n- ")
        .replace(/<\/?(p|div|center|ul|ol|table|tr|blockquote|section|article|hr)\b[^>]*>/gi, "\n\n")
        .replace(/<\/?[a-zA-Z][^>]*>/g, "")
        .replace(/\[\s*\]\([^)]*\)/g, "")
    text = decodeEntities(text)
    // Bullets left without content (they held only an image or a badge).
    text = text.split("\n").filter(function(line) { return !/^\s*([-*+]|\d+[.)])\s*$/.test(line) }).join("\n")
    return text.replace(/\n{3,}/g, "\n\n").trim()
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
