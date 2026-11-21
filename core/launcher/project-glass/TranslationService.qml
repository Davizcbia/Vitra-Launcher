// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.LocalStorage

// Machine translation for downloaded text (project summaries and
// descriptions) through Google Translate's web endpoint, which needs no key.
// Requests are batched, and every result is cached on disk, so a summary is
// translated once.
QtObject {
    id: service
    readonly property string provider: "google"
    // Bumped whenever results arrive: bindings that call cached() refresh.
    property int revision: 0
    readonly property string providerName: "Google"
    readonly property bool ready: true
    property var memory: ({})
    property var pending: ({})
    property var db: null

    function tr(text) { return qsTranslate("ProjectGlass", text) }

    // Launcher language key (Prism's, e.g. "zh_CN", "en_US", "pt_BR") to a
    // translation target ("zh-CN", "zh-TW", "en", "pt", ...).
    function targetFor(languageKey) {
        var key = String(languageKey || "en").replace("-", "_")
        var base = key.split("_")[0].toLowerCase()
        if (base === "zh") return /TW|HK|MO|Hant/i.test(key) ? "zh-TW" : "zh-CN"
        return base || "en"
    }
    function base(code) { return String(code || "").split(/[-_]/)[0].toLowerCase() }

    function database() {
        if (db) return db
        try {
            db = LocalStorage.openDatabaseSync("VitraTranslations", "1.0", "Translated project text", 8 * 1024 * 1024)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, text TEXT, used INTEGER)")
            })
        } catch (e) { console.warn("Translation cache unavailable:", e); db = null }
        return db
    }
    function cacheKey(text, target) { return provider + "|" + target + "|" + text }
    // The translation of `text`, or "" when there is none yet.
    function cached(text, target) {
        revision // dependency
        var hit = memory[cacheKey(text, target)]
        return hit === undefined ? "" : hit
    }
    // Fills memory from disk; returns the texts still missing.
    function loadCached(texts, target) {
        var missing = [], store = database(), found = false
        texts.forEach(function(text) {
            var key = cacheKey(text, target)
            if (memory[key] !== undefined) return
            var row = null
            if (store) store.readTransaction(function(tx) {
                var r = tx.executeSql("SELECT text FROM cache WHERE key = ?", [key])
                if (r.rows.length) row = r.rows.item(0).text
            })
            if (row !== null) { memory[key] = row; found = true }
            else missing.push(text)
        })
        if (found) revision++
        return missing
    }
    function remember(pairs, target) {
        var store = database(), now = Date.now()
        pairs.forEach(function(p) { memory[cacheKey(p.source, target)] = p.text })
        if (store) {
            try {
                store.transaction(function(tx) {
                    pairs.forEach(function(p) { tx.executeSql("INSERT OR REPLACE INTO cache VALUES(?, ?, ?)", [cacheKey(p.source, target), p.text, now]) })
                    // Keeps the newest 6000 entries.
                    tx.executeSql("DELETE FROM cache WHERE key IN (SELECT key FROM cache ORDER BY used DESC LIMIT -1 OFFSET 6000)")
                })
            } catch (e) { console.warn("Translation cache write failed:", e) }
        }
        revision++
    }

    // Text already in the target language comes back unchanged. English UI:
    // only text with non-Latin letters is sent (summaries are mostly English).
    function worthSending(text, target) {
        if (!String(text || "").trim().length) return false
        return base(target) !== "en" || /[^\u0000-ɏ -⁯]/.test(text)
    }
    // Translates in the background; cached() gives the results.
    function prefetch(texts, target) {
        if (!ready) return
        var unique = [], seen = {}
        texts.forEach(function(t) {
            t = String(t || "")
            if (!seen[t] && worthSending(t, target) && !pending[cacheKey(t, target)]) { seen[t] = true; unique.push(t) }
        })
        var missing = loadCached(unique, target)
        if (missing.length) translate(missing, target, function() {})
    }

    // done(error, translations) with translations in the order of `texts`.
    function translate(texts, target, done) {
        var results = new Array(texts.length), batches = [], current = [], size = 0
        var maxItems = 50, maxChars = 4500
        texts.forEach(function(text, i) {
            if (current.length && (current.length >= maxItems || size + text.length > maxChars)) { batches.push(current); current = []; size = 0 }
            current.push(i); size += text.length
            pending[cacheKey(text, target)] = true
        })
        if (current.length) batches.push(current)
        var left = batches.length, failure = ""
        if (!left) { done("", []); return }
        batches.forEach(function(indices) {
            var batch = indices.map(function(i) { return texts[i] })
            send(batch, target, function(error, translated) {
                if (error) failure = error
                else {
                    var pairs = []
                    indices.forEach(function(index, k) {
                        var item = translated[k] || {text: batch[k], lang: ""}
                        // Already in the target language: keep the original.
                        var text = item.lang && base(item.lang) === base(target) ? batch[k] : item.text
                        results[index] = text
                        pairs.push({source: batch[k], text: text})
                    })
                    remember(pairs, target)
                }
                batch.forEach(function(t) { delete pending[cacheKey(t, target)] })
                if (--left === 0) done(failure, failure ? null : results)
            })
        })
    }

    // One request; done(error, [{text, lang}]).
    function send(batch, target, done) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300) {
                done(xhr.status === 429 ? tr("Translation limit reached. Try again later.")
                     : xhr.status ? tr("Translation failed (HTTP %1). Please retry.").replace("%1", xhr.status)
                     : tr("Translation needs a network connection. Please retry."), null)
                return
            }
            try { done("", parse(JSON.parse(xhr.responseText), batch.length)) }
            catch (e) { done(tr("The translation service returned an unexpected answer."), null) }
        }
        xhr.open("POST", "https://translate.googleapis.com/translate_a/t?client=gtx&sl=auto&tl=" + encodeURIComponent(target))
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
        xhr.send(batch.map(function(t) { return "q=" + encodeURIComponent(t) }).join("&"))
    }
    // [["text","lang"], ...]; older answers give a bare string per item.
    function parse(data, count) {
        var out = []
        if (typeof data === "string") data = [data]
        data.forEach(function(item) {
            if (typeof item === "string") out.push({text: item, lang: ""})
            else out.push({text: String(item[0]), lang: item[1] || ""})
        })
        if (out.length !== count) throw new Error("count")
        return out
    }
}
