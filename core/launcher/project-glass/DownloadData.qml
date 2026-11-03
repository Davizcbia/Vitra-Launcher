import QtQuick
import "DownloadLogic.js" as Logic

QtObject {
    id: api
    property string metadataBase: "https://meta.prismlauncher.org/v1"
    property string modrinthBase: "https://api.modrinth.com/v2"
    property string curseForgeBase: "https://api.curseforge.com/v1"
    // Empty when the build has no CurseForge API key; the provider is then hidden.
    property string curseForgeKey: ""
    property int requestTimeout: 20000
    property var quickVersions: []
    property bool quickVersionsBusy: false
    property string quickVersionsError: ""
    property var catalogue: []
    property int total: 0
    property int nextOffset: 0
    property bool hasMore: false
    property bool catalogueBusy: false
    property string catalogueError: ""
    property var releases: []
    property bool releaseBusy: false
    property string releaseError: ""
    // Required projects of the shown releases, as catalogue entries.
    property var dependencies: []
    property bool dependencyBusy: false
    property var dependencyIds: []
    property bool vanillaValid: false
    property var requests: ({})
    property var cache: ({})
    property string catalogueKey: ""
    property var catalogueArgs: null
    property var releaseArgs: null
    // Messages from the "ProjectGlass" translation (see Main.qml's tr).
    function tr(text) { return qsTranslate("ProjectGlass", text) }
    // Request identities isolate catalogues, project pages, loader changes, and retries.
    function cancel(channel) {
        var prior = requests[channel]
        requests[channel] = null
        if (prior) { prior.xhr.onreadystatechange = null; prior.xhr.abort() }
    }
    function request(channel, url, done) {
        cancel(channel)
        var cached = cache[url]
        if (cached && Date.now() - cached.time < 120000) { done(null, cached.data); return }
        var xhr = new XMLHttpRequest()
        var state = { xhr: xhr, deadline: Date.now() + requestTimeout, fail: done }
        requests[channel] = state
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || requests[channel] !== state) return
            requests[channel] = null
            if (xhr.status < 200 || xhr.status >= 300) {
                var reason = xhr.status === 429 ? tr("Too many requests. Wait a moment and retry.") : xhr.status ? tr("HTTP ") + xhr.status + tr(" · Please retry.") : tr("Network unavailable · Check your connection and retry.")
                done(reason, null); return
            }
            var data
            try { data = JSON.parse(xhr.responseText) }
            catch (e) { done(tr("The server returned invalid JSON."), null); return }
            var now = Date.now()
            Object.keys(cache).forEach(function(key) { if (now - cache[key].time >= 120000) delete cache[key] })
            var keys = Object.keys(cache).sort(function(a, b) { return cache[a].time - cache[b].time })
            while (keys.length >= 12) delete cache[keys.shift()]
            cache[url] = { time: now, data: data }
            done(null, data)
        }
        try {
            xhr.open("GET", url)
            xhr.setRequestHeader("User-Agent", "ProjectGlassPrototype/0.9.30")
            xhr.setRequestHeader("Accept", "application/json")
            if (url.indexOf(curseForgeBase) === 0) xhr.setRequestHeader("x-api-key", curseForgeKey)
            xhr.send()
        } catch (e) { requests[channel] = null; done(tr("Could not start request: ") + e.message, null) }
    }
    property Timer watchdog: Timer {
        interval: 250; repeat: true
        running: api.catalogueBusy || api.releaseBusy || api.quickVersionsBusy || api.dependencyBusy
        onTriggered: {
            for (var channel in api.requests) {
                var state = api.requests[channel]
                if (state && Date.now() >= state.deadline) {
                    api.cancel(channel)
                    state.fail(tr("Request timed out · Please retry."), null)
                }
            }
        }
    }
    function loadQuickVersions(force) {
        if (quickVersionsBusy || (!force && quickVersions.length)) return
        quickVersionsBusy = true; quickVersionsError = ""
        request("quickVersions", metadataBase + "/net.minecraft/index.json", function(error, data) {
            quickVersionsBusy = false
            if (error) { quickVersionsError = error; return }
            try {
                var rows = Logic.minecraftCatalogue(data, "", "Newest")
                if (!rows.length) throw new Error(tr("No Minecraft releases returned"))
                quickVersions = rows.map(function(row) { return row.version })
            } catch (e) { quickVersionsError = tr("Could not load versions: ") + e.message }
        })
    }
    function invalidateCatalogue() {
        cancel("catalogue"); catalogueBusy = false; catalogue = []; catalogueError = ""; hasMore = false; total = 0
    }
    function loadCatalogue(category, query, sort, append, loader, provider) {
        var source = provider === "CurseForge" && curseForgeKey ? "CurseForge" : "Modrinth"
        var curse = source === "CurseForge" && category !== "Versions"
        var key = source + "|" + category + "|" + query + "|" + sort + "|" + (category === "Mods" ? loader || "All loaders" : "")
        var offset = append && catalogueKey === key ? nextOffset : 0
        catalogueArgs = { category: category, query: query, sort: sort, loader: loader || "All loaders", provider: source }
        catalogueKey = key
        if (!append) { catalogue = []; total = 0; hasMore = false; nextOffset = 0 }
        catalogueBusy = true; catalogueError = ""
        var url = category === "Versions" ? metadataBase + "/net.minecraft/index.json"
            : curse ? Logic.curseForgeSearchUrl(curseForgeBase, category, query, sort, offset, loader)
            : Logic.searchUrl(modrinthBase, category, query, sort, offset, loader)
        request("catalogue", url, function(error, data) {
            catalogueBusy = false
            if (error) { catalogueError = error; return }
            try {
                var rows = category === "Versions" ? Logic.minecraftCatalogue(data, query, sort) : curse ? Logic.curseForgeProjects(data, category) : Logic.projects(data, category)
                var page = category === "Versions" ? rows.length : curse ? data.data.length : data.hits.length
                catalogue = append ? catalogue.concat(rows) : rows
                // CurseForge stops paging at index + pageSize = 10000.
                total = category === "Versions" ? rows.length : curse ? Math.min(Number(data.pagination && data.pagination.totalCount || 0), 10000) : Number(data.total_hits || 0)
                nextOffset = offset + page
                hasMore = category !== "Versions" && page > 0 && nextOffset < total
            } catch (e) { catalogueError = tr("Could not read catalogue: ") + e.message }
        })
    }
    function retryCatalogue() {
        if (catalogueArgs) loadCatalogue(catalogueArgs.category, catalogueArgs.query, catalogueArgs.sort, false, catalogueArgs.loader, catalogueArgs.provider)
    }
    function closeReleases() {
        cancel("releases"); releases = []; releaseBusy = false; releaseError = ""; vanillaValid = false
        dependencyIds.forEach(function(id) { cancel("dependency:" + id) }); cancel("dependencies")
        dependencies = []; dependencyBusy = false; dependencyIds = []
    }
    function loadDependencies(entry, rows) {
        var ids = Logic.requiredDependencies(rows, String(entry.projectId))
        dependencyIds = ids
        if (!ids.length) return
        dependencyBusy = true
        if (entry.provider !== "CurseForge") {
            request("dependencies", modrinthBase + "/projects?ids=" + encodeURIComponent(JSON.stringify(ids)), function(error, data) {
                dependencyBusy = false
                if (error) return
                try {
                    var found = Logic.modrinthDependencies(data)
                    dependencies = ids.map(function(id) { return found.filter(function(p) { return p.projectId === id })[0] }).filter(function(p) { return !!p })
                } catch (e) {}
            })
            return
        }
        // CurseForge: one project request per dependency, kept in dependency order.
        var found = {}, pending = ids.length
        ids.forEach(function(id) {
            request("dependency:" + id, curseForgeBase + "/mods/" + encodeURIComponent(id), function(error, data) {
                if (!error) try { found[id] = Logic.curseForgeProjects({ data: [data.data] }, "Mods")[0] } catch (e) {}
                if (--pending) return
                dependencyBusy = false
                dependencies = ids.map(function(i) { return found[i] }).filter(function(p) { return !!p })
            })
        })
    }
    function loadReleases(entry, loader, targetGame, targetLoader) {
        closeReleases()
        releaseArgs = { entry: entry, loader: loader, game: targetGame, targetLoader: targetLoader }
        if (!entry) return
        releaseBusy = true
        var game = entry.category === "Versions"
        var uid = Logic.components[loader]
        var curse = !game && entry.provider === "CurseForge"
        var url = game ? metadataBase + "/" + uid + "/index.json"
            : curse ? curseForgeBase + "/mods/" + encodeURIComponent(entry.projectId) + "/files?pageSize=50&index=0"
            : modrinthBase + "/project/" + encodeURIComponent(entry.projectId) + "/version"
        // First verify that Minecraft / intermediary metadata contains the requested game.
        function getRows() {
            request("releases", url, function(error, data) {
                releaseBusy = false
                if (error) { releaseError = error; return }
                try {
                    if (game && loader === "Vanilla") {
                        vanillaValid = Logic.indexVersions(data).some(function(v) { return v.version === entry.version })
                        if (!vanillaValid) releaseError = tr("This Minecraft version is not listed by the provider.")
                    } else if (game) releases = Logic.loaderRows(data, loader, entry.version)
                    else {
                        releases = Logic.projectRows(curse ? Logic.curseForgeVersions(data) : data, targetGame, targetLoader, entry.category)
                        loadDependencies(entry, releases)
                    }
                } catch (e) { releaseError = tr("Could not read versions: ") + e.message }
            })
        }
        if (game && (loader === "Fabric" || loader === "Quilt")) {
            request("releases", metadataBase + "/net.fabricmc.intermediary/index.json", function(error, data) {
                if (error) { releaseBusy = false; releaseError = error; return }
                try {
                    if (!Logic.indexVersions(data).some(function(v) { return v.version === entry.version })) { releaseBusy = false; releaseError = tr("This loader does not support the selected Minecraft version."); return }
                } catch (e) { releaseBusy = false; releaseError = tr("Could not read intermediary metadata."); return }
                getRows()
            })
        } else getRows()
    }
    function retryReleases() {
        if (releaseArgs) loadReleases(releaseArgs.entry, releaseArgs.loader, releaseArgs.game, releaseArgs.targetLoader)
    }
    Component.onDestruction: { cancel("catalogue"); cancel("releases") }
}
