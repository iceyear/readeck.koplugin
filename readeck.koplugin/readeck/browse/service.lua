local Api = require("readeck.net.api")
local Catalog = require("readeck.browse.catalog")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local Facets = require("readeck.browse.facets")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local LocalScan = require("readeck.browse.local_scan")
local LuaSettings = require("frontend/luasettings")
local Refresh = require("readeck.browse.refresh")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local Service = {}

-- The catalog lives in its own settings file, not in readeck.lua. Readeck:saveSettings()
-- rewrites its whole table on every settings change, and a few thousand catalog entries
-- in there would turn each checkbox toggle into a full catalog write.
local CATALOG_FILE = "/readeck_catalog.lua"

function Service.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log
    local T = deps.T

    -- Ties in facet lists sort the way the reader's locale expects.
    Facets.set_collator(FFIUtil.strcoll)

    local function catalog_path()
        return DataStorage:getSettingsDir() .. CATALOG_FILE
    end

    function Readeck:getCatalogStore()
        if not self.catalog_store then
            self.catalog_store = LuaSettings:open(catalog_path())
        end
        return self.catalog_store
    end

    -- Loaded lazily and held in memory: the file is a multi-megabyte dofile, so it must
    -- not be read on plugin init, only when the browser is actually opened.
    function Readeck:getCatalog()
        if not self.catalog then
            self.catalog = Catalog.load(self:getCatalogStore(), self.server_url, self.catalog_owner)
            Log:debug("Catalog loaded:", Catalog.count(self.catalog), "entries")
        end
        return self.catalog
    end

    function Readeck:saveCatalog(synced_at)
        if not self.catalog then
            return false
        end
        self.catalog.server_url = self.server_url
        self.catalog.owner = self.catalog_owner
        return Catalog.save(self:getCatalogStore(), self.catalog, synced_at)
    end

    function Readeck:clearCatalog()
        self.catalog = nil
        self.browse_downloaded_ids = nil
        if self.catalog_store then
            Catalog.clear(self.catalog_store, catalog_path(), os.remove)
        end
        Log:info("Catalog cleared")
    end

    function Readeck:isCatalogEmpty()
        return Catalog.count(self:getCatalog()) == 0
    end

    -- One lfs pass, cached for the lifetime of an open browser. The existing
    -- findLocalArticlePathByID rescans the whole directory per article, which is
    -- unaffordable to call once per visible row.
    function Readeck:scanDownloadedIDs(force)
        if self.browse_downloaded_ids and not force then
            return self.browse_downloaded_ids
        end
        self.browse_downloaded_ids = LocalScan.scan_directory(lfs, self:getDownloadDirectory(), function(path)
            return self:getArticleID(path)
        end)
        return self.browse_downloaded_ids
    end

    -- Accessors that let readeck.browse.facets merge device reading state without
    -- knowing anything about KOReader. Both return nil for an article that is not
    -- downloaded, which the facet code reads as "no local opinion".
    function Readeck:localReadingState()
        local BookList = require("ui/widget/booklist")
        local downloaded = self:scanDownloadedIDs()
        return {
            local_progress = function(id)
                local path = downloaded[id]
                if not path then
                    return nil
                end
                local ok, info = pcall(BookList.getBookInfo, path)
                if not ok or type(info) ~= "table" or not info.percent_finished then
                    return nil
                end
                return info.percent_finished * 100
            end,
            local_status = function(id)
                local path = downloaded[id]
                if not path then
                    return nil
                end
                local ok, info = pcall(BookList.getBookInfo, path)
                if not ok or type(info) ~= "table" then
                    return nil
                end
                return info.status
            end,
        }
    end

    -- Write-through for a mutation the plugin has just made on the server.
    --
    -- Deliberately a no-op while the catalog is not already in memory: loading a
    -- multi-megabyte index during a background sync, on behalf of a user who may never
    -- open the browser, costs more than it saves. Those devices pick the same change up
    -- from the next delta refresh, because a mutation the plugin made is a mutation the
    -- server records in its sync log.
    local function loaded_catalog(plugin)
        return plugin.catalog
    end

    function Readeck:catalogPatch(id, changes)
        local catalog = loaded_catalog(self)
        if not catalog or id == nil or Catalog.patch(catalog, id, changes) == nil then
            return false
        end
        self.catalog_dirty = true
        return true
    end

    function Readeck:catalogRemove(id)
        local catalog = loaded_catalog(self)
        if not catalog or not Catalog.remove(catalog, id) then
            return false
        end
        self.catalog_dirty = true
        return true
    end

    function Readeck:catalogUpsertBookmark(bookmark)
        local catalog = loaded_catalog(self)
        if not catalog then
            return false
        end
        local entry = Catalog.entry_from_bookmark(bookmark)
        if not entry then
            return false
        end
        Catalog.upsert(catalog, entry)
        self.catalog_dirty = true
        return true
    end

    -- Labels are add-only on the server (`add_labels`), so the catalog has to union
    -- rather than replace, or the browser would drop every label it did not send.
    function Readeck:catalogAddLabels(id, labels)
        local catalog = loaded_catalog(self)
        local entry = catalog and Catalog.get(catalog, id)
        if not entry or type(labels) ~= "table" then
            return false
        end
        local merged, seen = {}, {}
        for _, list in ipairs({ entry.labels or {}, labels }) do
            for _, name in ipairs(list) do
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    table.insert(merged, name)
                end
            end
        end
        entry.labels = merged
        self.catalog_dirty = true
        return true
    end

    -- Translates an accepted PATCH body into the catalog fields it changed. Kept here so
    -- readeck.sync.local_actions never has to know the catalog's shape; note the body may
    -- carry read_progress, is_marked and add_labels as well as is_archived, and applying
    -- a flat {is_archived = true} would silently under-apply the rest.
    function Readeck:catalogApplyArchive(id, body)
        local changes = { is_archived = body.is_archived == true }
        if body.read_progress ~= nil then
            changes.read_progress = body.read_progress
        end
        if body.is_marked ~= nil then
            changes.is_marked = body.is_marked
        end
        local patched = self:catalogPatch(id, changes)
        if patched and body.add_labels then
            self:catalogAddLabels(id, body.add_labels)
        end
        return patched
    end

    -- Every call below runs inside Trapper:wrap. callAPI is synchronous and can block
    -- for the full 120 s timeout, so calling one outside a Trapper coroutine freezes the
    -- UI outright. This is the single rule the browse layer must not break.
    local function assert_trapped(name)
        if not Trapper:isWrapped() then
            Log:error("Refusing to run", name, "outside Trapper:wrap -- this would block the UI")
            return false
        end
        return true
    end

    function Readeck:fetchSyncLog(cursor, etag)
        -- Headers are built explicitly, and deliberately carry no Content-Type: the
        -- server picks its form binder from that header alone, so a GET announcing
        -- application/json is routed to the JSON body decoder, fails on the empty body,
        -- and turns every sync call into a 422.
        local headers = {
            ["Authorization"] = "Bearer " .. (self.access_token or ""),
        }
        if etag then
            headers["If-None-Match"] = etag
        end
        local url = Api.sync_query(cursor)
        local result, err, code, resp_headers = self:callAPI("GET", url, headers, "", "", true, false, {
            return_headers = true,
        })
        return result, err, code, resp_headers
    end

    -- Hydrates metadata for a specific set of ids, in batches of 100.
    function Readeck:hydrateCatalogIDs(catalog, ids, report)
        local batches = Refresh.batches(ids)
        local hydrated = 0
        for index, batch in ipairs(batches) do
            if report and not report(hydrated, #ids, index, #batches) then
                return hydrated, true
            end
            local url = Api.bookmarks_query({ id = batch, limit = Refresh.ID_BATCH_SIZE })
            local page = self:callAPI("GET", url, nil, "", "", true)
            if type(page) == "table" then
                hydrated = hydrated + Refresh.hydrate(catalog, page)
            else
                Log:warn("Catalog hydration batch failed:", index)
            end
        end
        return hydrated, false
    end

    -- Pages the whole library for metadata. Offset paging here is lossy by design of the
    -- server (no id tiebreak on the sort key, and on SQLite the key is truncated to whole
    -- seconds), so the caller must reconcile against the sync census afterwards rather
    -- than trusting this to be complete.
    function Readeck:pageAllBookmarks(catalog, total_hint, report)
        local offset, hydrated, total = 0, 0, total_hint
        while true do
            if report and not report(hydrated, total) then
                return hydrated, true
            end
            local url = Api.bookmarks_query({
                limit = Refresh.PAGE_SIZE,
                offset = offset,
                -- Deliberately no is_archived filter: the archived bucket exists to show
                -- exactly the articles the download sync excludes.
                sort = "created",
            })
            local page, _, _, resp_headers = self:callAPI("GET", url, nil, "", "", true, false, {
                return_headers = true,
            })
            if type(page) ~= "table" then
                -- Distinguished from "the last page was empty" by the third return: a
                -- failed first page would otherwise look like an account with no
                -- articles, and get saved as an empty catalog.
                return hydrated, false, true
            end
            local pagination = Api.pagination(resp_headers)
            total = total or pagination.total_count
            hydrated = hydrated + Refresh.hydrate(catalog, page)
            offset = offset + Refresh.PAGE_SIZE
            if #page == 0 or not Api.has_next_page(pagination, offset) then
                return hydrated, false
            end
        end
    end

    function Readeck:refreshCollections(catalog)
        local result = self:callAPI("GET", Api.paths.collections, nil, "", "", true)
        if type(result) == "table" then
            Catalog.set_collections(catalog, result)
            return #catalog.collections
        end
        return nil
    end

    local function info(text)
        -- Trapper:info returns false when the user tapped to abort.
        return Trapper:info(text)
    end

    -- Full rebuild. Baselines at the Unix epoch (which returns the complete id census
    -- AND every tombstone ever recorded, unlike the bare call), pages metadata, then
    -- backfills whatever paging skipped.
    function Readeck:refreshCatalogFull()
        if not assert_trapped("refreshCatalogFull") then
            return false
        end
        local catalog = self:getCatalog()

        if not info(L("Fetching article list…")) then
            return false
        end
        -- The census is an optimisation, never a prerequisite: it supplies the progress
        -- total and the only evidence that permits pruning. Paging alone still produces a
        -- correct catalog, so a server that cannot answer it -- too old, or refusing the
        -- cursor -- degrades to a slightly less accurate refresh instead of no refresh.
        local census, census_err, census_code = self:fetchSyncLog(Refresh.BASELINE_CURSOR)
        local status = Refresh.classify_sync_response(census, census_err, census_code)
        local items, max_time = {}, nil
        if status == "ok" then
            items, max_time = Refresh.parse_sync_items(census)
        else
            Log:warn("Baseline sync census unavailable:", status, census_code or "", census_err or "")
        end

        local total = #items > 0 and #items or nil
        local hydrated, cancelled, failed = self:pageAllBookmarks(catalog, total, function(done, page_total)
            return info(T(L("Fetching articles… %1/%2"), done, page_total or "?"))
        end)
        if cancelled then
            self:saveCatalog()
            return false
        end
        if failed and hydrated == 0 then
            UIManager:show(InfoMessage:new({ text = L("Could not fetch the article list.") }))
            return false
        end

        -- Only a complete census may prune: a bounded delta's silences are not deletions.
        if status == "ok" then
            local missing = Refresh.missing_ids(catalog, items)
            if #missing > 0 then
                Log:info("Offset paging skipped", #missing, "articles; backfilling by id")
                self:hydrateCatalogIDs(catalog, missing, function(done, count)
                    return info(T(L("Filling gaps… %1/%2"), done, count))
                end)
            end
            local pruned = Refresh.reconcile(catalog, items, true)
            if #pruned > 0 then
                Log:info("Removed", #pruned, "articles no longer on the server")
            end
            catalog.cursor = Refresh.cursor_from(max_time)
        end

        info(L("Fetching collections…"))
        self:refreshCollections(catalog)

        -- A run that lost pages part way through is not a complete picture of the
        -- server, so it must not be stamped as one: leaving synced_at alone keeps the
        -- browser subtitle honest and the next refresh eager.
        self:saveCatalog(not failed and os.date("!%Y-%m-%dT%H:%M:%SZ") or nil)
        Log:info("Catalog refreshed:", Catalog.count(catalog), "entries,", hydrated, "hydrated")
        return not failed
    end

    -- Incremental refresh. One request when nothing changed, plus one hydration batch per
    -- 100 changed articles.
    function Readeck:refreshCatalogDelta()
        if not assert_trapped("refreshCatalogDelta") then
            return false
        end
        local catalog = self:getCatalog()
        if not catalog.cursor then
            return self:refreshCatalogFull()
        end

        local result, err, code, resp_headers = self:fetchSyncLog(catalog.cursor, catalog.etag)
        local status = Refresh.classify_sync_response(result, err, code)

        if status == "unchanged" then
            -- A 304 has no body; parsing it would look like "everything was deleted".
            Log:debug("Catalog unchanged since", catalog.cursor)
            return true
        end
        if status == "bad_cursor" then
            Log:warn("Server rejected the catalog cursor; rebaselining")
            catalog.cursor = nil
            catalog.etag = nil
            return self:refreshCatalogFull()
        end
        if status == "unsupported" then
            Log:info("Server has no sync endpoint; falling back to a full refresh")
            return self:refreshCatalogFull()
        end
        if status ~= "ok" then
            return false
        end

        local items, max_time = Refresh.parse_sync_items(result)
        local plan = Refresh.apply_sync(catalog, items)
        if #plan.stale > 0 then
            local _, cancelled = self:hydrateCatalogIDs(catalog, plan.stale, function(done, count)
                return info(T(L("Updating articles… %1/%2"), done, count))
            end)
            if cancelled then
                self:saveCatalog()
                return false
            end
        end

        if max_time then
            catalog.cursor = Refresh.cursor_from(max_time)
        end
        if type(resp_headers) == "table" then
            catalog.etag = resp_headers["etag"] or resp_headers["ETag"]
        end
        self:refreshCollections(catalog)
        self:saveCatalog(os.date("!%Y-%m-%dT%H:%M:%SZ"))
        Log:info("Catalog delta:", #plan.stale, "updated,", #plan.removed, "removed")
        return true
    end

    -- Called at the end of a sync, when the network is already up and the article list
    -- has just been fetched anyway. Deliberately silent and best-effort: the user asked
    -- for a sync, not for a catalog refresh, so a failure here must not produce a dialog.
    function Readeck:refreshCatalogAfterSync()
        -- The existence check is an lfs stat, not a parse. Users who never open the
        -- browser have no catalog file, and must not pay a multi-megabyte dofile on
        -- every sync just so this hook can discover there was nothing to update.
        if not self.catalog and lfs.attributes(catalog_path(), "mode") ~= "file" then
            return
        end
        UIManager:nextTick(function()
            Trapper:wrap(function()
                local ok = self:refreshCatalogDelta()
                Trapper:clear()
                if not ok then
                    Log:info("Post-sync catalog refresh did not complete")
                end
            end)
        end)
    end

    -- Degraded path: no catalog and no network. Recovers labels and lossy titles from
    -- what is on disk so the browser has something to show.
    function Readeck:buildFallbackCatalog()
        local entries, available = LocalScan.build_fallback_catalog({
            lfs = lfs,
            doc_settings = DocSettings,
            directory = self:getDownloadDirectory(),
            get_article_id = function(path)
                return self:getArticleID(path)
            end,
            article_id_suffix = deps.article_id_suffix,
            reading_time_label = L("Reading time"),
        })
        local catalog = Catalog.empty()
        for _, entry in ipairs(entries) do
            Catalog.upsert(catalog, entry)
        end
        catalog.partial = true
        return catalog, available
    end
end

return Service
