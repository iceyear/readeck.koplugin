-- The article browser: a BookList over the local catalog.
--
-- Online and offline run the same code. The browser never queries the server to build a
-- screen -- every bucket, label list and source list is computed from readeck.browse.
-- Connectivity gates exactly three things: downloading, refreshing the catalog, and the
-- long-press actions that change server state.
--
-- Navigation is the KOReader path stack, which is what makes label drill-down work: each
-- chosen label pushes a screen, so the back arrow deselects it and every count is
-- recomputed on the way back down.

local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local Catalog = require("readeck.browse.catalog")
local ConfirmBox = require("ui/widget/confirmbox")
local Dates = require("readeck.core.dates")
local Facets = require("readeck.browse.facets")
local Filters = require("readeck.core.filters")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Items = require("readeck.ui.browser.items")
local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local Api = require("readeck.net.api")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")

local Browser = {}

local SORT_OPTIONS = {
    { sort = "-created", text = "Newest first" },
    { sort = "created", text = "Oldest first" },
    { sort = "title", text = "Title" },
    { sort = "site", text = "Source" },
    { sort = "-duration", text = "Longest read" },
    { sort = "duration", text = "Shortest read" },
    { sort = "-progress", text = "Most read" },
}

local function copy_list(list)
    local copy = {}
    for _, value in ipairs(list or {}) do
        table.insert(copy, value)
    end
    return copy
end

local function append_copy(list, value)
    local copy = copy_list(list)
    table.insert(copy, value)
    return copy
end

local function copy_filter(filter)
    local copy = {}
    for key, value in pairs(filter or {}) do
        copy[key] = type(value) == "table" and copy_list(value) or value
    end
    return copy
end

function Browser.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log
    local T = deps.T
    local failed = deps.failed

    local ArticleBrowser = BookList:extend({
        name = "readeck_browser",
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_shrink_font_to_fit = true,
    })

    -- Context shared by the facet code (which reads local_progress / local_status) and
    -- the row formatter (which reads the rest). Built once per browser open: the
    -- directory scan behind `downloaded` is the expensive part.
    function ArticleBrowser:refreshContext()
        local state = self.plugin:localReadingState()
        self.ctx = {
            L = L,
            T = T,
            downloaded = self.plugin:scanDownloadedIDs(),
            local_progress = state.local_progress,
            local_status = state.local_status,
            can_download = NetworkMgr:isConnected(),
        }
    end

    -- The one place the catalog becomes a screen. Everything downstream -- bucket counts,
    -- label facets, source facets, collection counts, the article rows themselves -- reads
    -- self.entries, so narrowing it here is what makes the sync settings apply everywhere
    -- at once, with no screen able to forget. Filtering happens at display time rather
    -- than at refresh time so the catalog stays a faithful mirror of the server and a
    -- changed setting takes effect without a rebuild.
    function ArticleBrowser:loadEntries()
        local rules = nil
        if self.plugin.browse_apply_sync_filters ~= false then
            rules = Filters.rules_from(self.plugin)
        end
        self.entries, self.hidden_count = Filters.apply(Catalog.all(self.catalog), rules)
    end

    function ArticleBrowser:init()
        self:loadEntries()
        self:refreshContext()
        self.title = L("Readeck")
        self.subtitle = self:catalogSubtitle()
        self.item_table = self:rootItems()
        self.title_bar_left_icon = "appbar.menu"
        self.onLeftButtonTap = function()
            self:showBrowserMenu()
        end
        BookList.init(self)
    end

    ---------------------------------------------------------------- screens

    function ArticleBrowser:rootItems()
        local counts = {
            all = Facets.count(self.entries, { bucket = "all" }, self.ctx),
            unread = Facets.count(self.entries, { bucket = "unread" }, self.ctx),
            archived = Facets.count(self.entries, { bucket = "archived" }, self.ctx),
            favorite = Facets.count(self.entries, { bucket = "favorite" }, self.ctx),
            collections = #(self.catalog.collections or {}),
            labels = #Facets.labels(self.entries, {}, self.ctx),
            sources = #Facets.sources(self.entries, {}, self.ctx),
        }
        return Items.buckets(counts, self.available, self.ctx)
    end

    function ArticleBrowser:catalogSubtitle()
        local total = #self.entries
        local text
        if self.catalog.partial then
            text = T(L("%1 downloaded articles · offline list"), total)
        else
            local age = Dates.age_in_hours(self.catalog.synced_at)
            local max_age = tonumber(self.plugin.browse_catalog_max_age_hours) or 24
            if age and age >= max_age then
                text = T(L("%1 articles · updated %2"), total, Dates.humanize_age(age, L, T))
            else
                text = T(L("%1 articles"), total)
            end
        end
        -- Never hide silently: this count is the only clue that the sync settings, rather
        -- than an empty server, are why an article the user expected is not on the list.
        if (self.hidden_count or 0) > 0 then
            return T(L("%1 · %2 hidden"), text, self.hidden_count)
        end
        return text
    end

    function ArticleBrowser:currentPath()
        return self.paths[#self.paths]
    end

    function ArticleBrowser:pushPath(path)
        table.insert(self.paths, path)
        self:renderPath(path)
    end

    -- Rebuilds the whole screen for a path. Called on push and on pop alike, which is
    -- what keeps drill-down counts correct in both directions.
    function ArticleBrowser:renderPath(path)
        if path == nil then
            self:switchItemTable(L("Readeck"), self:rootItems(), 1, nil, self:catalogSubtitle())
            return
        end

        local title = Items.breadcrumb(path.crumbs)
        if path.screen == "articles" then
            local entries = Facets.filter(self.entries, path.filter, self.plugin.browse_sort, self.ctx)
            local subtitle = T(L("%1 articles"), #entries)
            if path.approximate then
                subtitle = T(L("%1 articles · text search skipped offline"), #entries)
            end
            if (path.filter or {}).search then
                subtitle = T(L("%1 articles matching “%2”"), #entries, path.filter.search)
            end
            local rows = Items.empty_state(Items.articles(entries, self.ctx), L("No articles here."))
            self:switchItemTable(title, rows, 1, nil, subtitle)
        elseif path.screen == "labels" then
            local candidates, matching = Facets.candidate_labels(self.entries, path.filter, path.selected, self.ctx)
            local rows = Items.labels(candidates, matching, self.ctx)
            self:switchItemTable(title, rows, 1, nil, T(L("%1 labels"), #candidates))
        elseif path.screen == "sources" then
            local facets = Facets.sources(self.entries, path.filter, self.ctx)
            local rows = Items.empty_state(Items.sources(facets), L("No sources here."))
            self:switchItemTable(title, rows, 1, nil, T(L("%1 sources"), #facets))
        elseif path.screen == "collections" then
            local rows = Items.collections(self.catalog.collections, function(filter)
                return Facets.count(self.entries, filter, self.ctx)
            end)
            local count = #rows
            rows = Items.empty_state(rows, L("No collections on the server."))
            self:switchItemTable(title, rows, 1, nil, T(L("%1 collections"), count))
        end
    end

    -- Re-renders the current screen in place, after something changed underneath it.
    function ArticleBrowser:reload()
        self:loadEntries()
        local path = self:currentPath()
        if path == nil then
            self:switchItemTable(L("Readeck"), self:rootItems(), 1, nil, self:catalogSubtitle())
        else
            self:renderPath(path)
        end
    end

    ---------------------------------------------------------------- navigation

    local function bucket_path(item)
        if item.bucket == "labels" then
            return { screen = "labels", filter = { bucket = "labels" }, selected = {}, crumbs = { item.text } }
        elseif item.bucket == "sources" then
            return { screen = "sources", filter = { bucket = "sources" }, crumbs = { item.text } }
        elseif item.bucket == "collections" then
            return { screen = "collections", crumbs = { item.text } }
        end
        return { screen = "articles", filter = { bucket = item.bucket }, crumbs = { item.text } }
    end

    function ArticleBrowser:onMenuSelect(item)
        if item.kind == "bucket" then
            if item.unavailable then
                UIManager:show(InfoMessage:new({
                    text = L("This list needs the article list from the server. Refresh it while online to use it."),
                }))
                return true
            end
            self:pushPath(bucket_path(item))
        elseif item.kind == "label" then
            local path = self:currentPath()
            self:pushPath({
                screen = "labels",
                filter = path.filter,
                selected = append_copy(path.selected, item.label),
                crumbs = append_copy(path.crumbs, item.label),
            })
        elseif item.kind == "show_matching" then
            local path = self:currentPath()
            local filter = copy_filter(path.filter)
            filter.labels = copy_list(path.selected)
            self:pushPath({ screen = "articles", filter = filter, crumbs = path.crumbs })
        elseif item.kind == "source" then
            local path = self:currentPath()
            local filter = copy_filter(path.filter)
            filter.site = item.site
            self:pushPath({ screen = "articles", filter = filter, crumbs = append_copy(path.crumbs, item.site) })
        elseif item.kind == "collection" then
            local path = self:currentPath()
            self:pushPath({
                screen = "articles",
                filter = item.filter,
                approximate = item.approximate,
                crumbs = append_copy(path.crumbs, item.collection.name),
            })
        elseif item.kind == "article" then
            self:openOrDownload(item)
        end
        return true
    end

    function ArticleBrowser:onReturn()
        table.remove(self.paths)
        self:renderPath(self:currentPath())
        return true
    end

    function ArticleBrowser:onHoldReturn()
        self.paths = {}
        self:renderPath(nil)
        return true
    end

    ---------------------------------------------------------------- article actions

    function ArticleBrowser:refreshRow(item)
        local row = item.idx and self.item_table[item.idx]
        if row and row.entry then
            row.mandatory = Items.mandatory_for(row.entry, self.ctx)
            row.dim = (self.ctx.can_download == false and not Items.is_downloaded(row.entry, self.ctx)) or nil
        end
        self:updateItems(1, true)
    end

    function ArticleBrowser:openLocal(file)
        filemanagerutil.openFile(self.plugin.ui, file, self.close_callback)
    end

    -- Returns the local path on success and nil on failure -- a path rather than a
    -- boolean, because the caller has to be able to open the file it just fetched.
    -- `stay_on_list` suppresses the row redraw: on the tap path the browser is about to
    -- close anyway, and a full-page repaint on the way out is pure e-ink flicker.
    function ArticleBrowser:downloadEntry(entry, item, stay_on_list)
        Trapper:info(T(L("Downloading %1…"), entry.title))
        local result = self.plugin:download(entry)
        Trapper:clear()
        if result == failed then
            UIManager:show(InfoMessage:new({ text = T(L("Could not download %1."), entry.title) }))
            return nil
        end
        local file = self.plugin:findLocalArticlePathByID(entry.id)
        if file then
            self.ctx.downloaded[entry.id] = file
            -- The cache is class-level and keyed by path, so a re-downloaded article
            -- would otherwise keep showing the progress of the file it replaced.
            BookList.resetBookInfoCache(file)
        end
        if stay_on_list then
            self:refreshRow(item)
        end
        return file
    end

    -- A tap means "read this". When the article is not on the device yet the download is
    -- a step on the way there, not the destination -- stopping at the list and making the
    -- user tap the same row a second time is the whole bug this guards against, and it is
    -- what OPDS avoids with its "Read now" prompt (opds.koplugin/main.lua showFileDownloadedDialog).
    --
    -- `stay_on_list` is the long-press "Download" action, which deliberately does not
    -- open: picking several articles out of the list without leaving it is the other half
    -- of what browsing is for.
    function ArticleBrowser:openOrDownload(item, stay_on_list)
        local entry = item.entry
        local file = self.ctx.downloaded[entry.id]
        if file then
            self:openLocal(file)
            return
        end
        if self.plugin:isempty(self.plugin.directory) then
            UIManager:show(InfoMessage:new({ text = L("Please configure a download folder first.") }))
            return
        end
        NetworkMgr:runWhenConnected(function()
            Trapper:wrap(function()
                local downloaded_file = self:downloadEntry(entry, item, stay_on_list)
                -- No path means the fetch failed, or succeeded and then could not be found
                -- on disk. Either way there is nothing to open, and downloadEntry has
                -- already said so; falling back to the list beats opening nil.
                if stay_on_list or not downloaded_file then
                    return
                end
                -- Deferred a tick: the Trapper info message is still being torn down, and
                -- openLocal closes this widget on its way to the reader. Handing the
                -- document over from inside that same repaint is what congests the EPDC.
                UIManager:nextTick(function()
                    self:openLocal(downloaded_file)
                end)
            end)
        end)
    end

    function ArticleBrowser:deleteLocalCopy(entry, item)
        local file = self.ctx.downloaded[entry.id]
        if not file then
            return
        end
        UIManager:show(ConfirmBox:new({
            text = T(L("Delete the local copy of %1?\n\nThe article stays on the server."), entry.title),
            ok_text = L("Delete"),
            ok_callback = function()
                self.plugin:deleteLocalArticle(file)
                self.ctx.downloaded[entry.id] = nil
                BookList.resetBookInfoCache(file)
                self:refreshRow(item)
            end,
        }))
    end

    -- One PATCH plus the matching catalog write-through, so the browser reflects the
    -- change without a round trip. `changes` is what the catalog entry becomes; it is
    -- spelled out separately because the API is asymmetric -- you read `is_marked` but
    -- write `is_favorite`.
    function ArticleBrowser:patchEntry(entry, body, changes, item)
        NetworkMgr:runWhenConnected(function()
            Trapper:wrap(function()
                Trapper:info(L("Updating article…"))
                local ok = self.plugin:patchBookmark(entry.id, body)
                Trapper:clear()
                if not ok then
                    UIManager:show(InfoMessage:new({ text = L("Could not update the article on the server.") }))
                    return
                end
                Catalog.patch(self.catalog, entry.id, changes)
                for key, value in pairs(changes) do
                    entry[key] = value
                end
                -- Archiving or unarchiving moves the article between buckets, so the
                -- whole screen has to be rebuilt; a favourite toggle only redraws a row.
                if changes.is_archived ~= nil then
                    self:reload()
                else
                    self:refreshRow(item)
                end
            end)
        end)
    end

    function ArticleBrowser:onMenuHold(item)
        if item.kind ~= "article" then
            return true
        end
        local entry = item.entry
        local file = self.ctx.downloaded[entry.id]
        local dialog

        local function close_then(action)
            return function()
                UIManager:close(dialog)
                action()
            end
        end

        dialog = ButtonDialog:new({
            title = entry.title,
            title_align = "center",
            buttons = {
                {
                    {
                        text = L("Open"),
                        enabled = file ~= nil,
                        callback = close_then(function()
                            self:openLocal(file)
                        end),
                    },
                    {
                        text = L("Download"),
                        enabled = file == nil,
                        callback = close_then(function()
                            self:openOrDownload(item, true)
                        end),
                    },
                },
                {
                    {
                        text = entry.is_marked and L("Remove from favorites") or L("Add to favorites"),
                        callback = close_then(function()
                            self:patchEntry(
                                entry,
                                { is_favorite = not entry.is_marked },
                                { is_marked = not entry.is_marked },
                                item
                            )
                        end),
                    },
                    {
                        text = entry.is_archived and L("Move to unread") or L("Archive"),
                        callback = close_then(function()
                            self:patchEntry(
                                entry,
                                { is_archived = not entry.is_archived },
                                { is_archived = not entry.is_archived },
                                item
                            )
                        end),
                    },
                },
                {},
                {
                    {
                        text = L("Delete local file"),
                        enabled = file ~= nil,
                        callback = close_then(function()
                            self:deleteLocalCopy(entry, item)
                        end),
                    },
                    {
                        text = L("Article details"),
                        callback = close_then(function()
                            self:showDetails(entry)
                        end),
                    },
                },
            },
        })
        UIManager:show(dialog)
        return true
    end

    function ArticleBrowser:showDetails(entry)
        local lines = { entry.title }
        local source = Facets.source_of(entry)
        if source then
            table.insert(lines, T(L("Source: %1"), source))
        end
        if entry.authors and #entry.authors > 0 then
            table.insert(lines, T(L("Authors: %1"), table.concat(entry.authors, ", ")))
        end
        if entry.labels and #entry.labels > 0 then
            table.insert(lines, T(L("Labels: %1"), table.concat(entry.labels, ", ")))
        end
        local reading_time = Items.format_reading_time(entry.reading_time, self.ctx)
        if reading_time then
            table.insert(lines, T(L("Reading time: %1"), reading_time))
        end
        table.insert(lines, T(L("Progress: %1%"), Items.progress_of(entry, self.ctx)))
        if entry.created then
            table.insert(lines, T(L("Added: %1"), entry.created:sub(1, 10)))
        end
        if entry.description and entry.description ~= "" then
            table.insert(lines, "")
            table.insert(lines, entry.description)
        end
        UIManager:show(InfoMessage:new({ text = table.concat(lines, "\n") }))
    end

    ---------------------------------------------------------------- browser menu

    function ArticleBrowser:refineByLabel()
        local path = self:currentPath()
        if not path or path.screen ~= "articles" then
            return
        end
        local filter = copy_filter(path.filter)
        local selected = copy_list(filter.labels)
        filter.labels = nil
        self:pushPath({ screen = "labels", filter = filter, selected = selected, crumbs = path.crumbs })
    end

    function ArticleBrowser:refineBySource()
        local path = self:currentPath()
        if not path or path.screen ~= "articles" then
            return
        end
        self:pushPath({ screen = "sources", filter = path.filter, crumbs = path.crumbs })
    end

    function ArticleBrowser:showSearch()
        local path = self:currentPath()
        local dialog
        dialog = InputDialog:new({
            title = L("Search articles"),
            description = L("Searches titles, authors, sources and labels on this device."),
            input = ((path or {}).filter or {}).search or "",
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(dialog)
                        end,
                    },
                    {
                        text = L("Search"),
                        is_enter_default = true,
                        callback = function()
                            local query = dialog:getInputText()
                            UIManager:close(dialog)
                            local base = (path and path.screen == "articles") and path.filter or { bucket = "all" }
                            local filter = copy_filter(base)
                            filter.search = query ~= "" and query or nil
                            self:pushPath({
                                screen = "articles",
                                filter = filter,
                                crumbs = append_copy((path or {}).crumbs, L("Search")),
                            })
                        end,
                    },
                },
            },
        })
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function ArticleBrowser:showSortMenu()
        local dialog
        local rows = {}
        for _, option in ipairs(SORT_OPTIONS) do
            table.insert(rows, {
                {
                    text = option.sort == self.plugin.browse_sort and ("\u{2713} " .. L(option.text)) or L(option.text),
                    callback = function()
                        UIManager:close(dialog)
                        self.plugin.browse_sort = option.sort
                        self.plugin:saveSettings()
                        self:reload()
                    end,
                },
            })
        end
        dialog = ButtonDialog:new({ title = L("Sort by"), title_align = "center", buttons = rows })
        UIManager:show(dialog)
    end

    function ArticleBrowser:runRefresh(full)
        NetworkMgr:runWhenConnected(function()
            Trapper:wrap(function()
                local ok = full and self.plugin:refreshCatalogFull() or self.plugin:refreshCatalogDelta()
                Trapper:clear()
                if not ok then
                    return
                end
                self.catalog = self.plugin:getCatalog()
                self.available = nil
                self:refreshContext()
                self.paths = {}
                self:reload()
            end)
        end)
    end

    -- The escape hatch for the sync settings. Browsing exists precisely to pick one
    -- article out of the pile the sync does not download, so "excluded from sync" cannot
    -- be allowed to mean "unreachable"; the tick says which way it is currently set.
    function ArticleBrowser:syncFilterButtonText()
        local text = L("Hide what sync skips")
        if self.plugin.browse_apply_sync_filters ~= false then
            return "\u{2713} " .. text
        end
        return text
    end

    function ArticleBrowser:showBrowserMenu()
        local path = self:currentPath()
        local on_articles = path ~= nil and path.screen == "articles"
        local dialog

        local function close_then(action)
            return function()
                UIManager:close(dialog)
                action()
            end
        end

        dialog = ButtonDialog:new({
            title = L("Browse"),
            title_align = "center",
            buttons = {
                {
                    {
                        text = L("Search…"),
                        callback = close_then(function()
                            self:showSearch()
                        end),
                    },
                    {
                        text = L("Sort by…"),
                        callback = close_then(function()
                            self:showSortMenu()
                        end),
                    },
                },
                {
                    {
                        text = L("Refine by label"),
                        enabled = on_articles,
                        callback = close_then(function()
                            self:refineByLabel()
                        end),
                    },
                    {
                        text = L("Refine by source"),
                        enabled = on_articles,
                        callback = close_then(function()
                            self:refineBySource()
                        end),
                    },
                },
                {
                    {
                        text = self:syncFilterButtonText(),
                        callback = close_then(function()
                            self.plugin.browse_apply_sync_filters = self.plugin.browse_apply_sync_filters == false
                            self.plugin:saveSettings()
                            self:reload()
                        end),
                    },
                },
                {},
                {
                    {
                        text = L("Refresh article list"),
                        callback = close_then(function()
                            self:runRefresh(false)
                        end),
                    },
                    {
                        text = L("Rebuild article list"),
                        callback = close_then(function()
                            self:runRefresh(true)
                        end),
                    },
                },
            },
        })
        UIManager:show(dialog)
    end

    -- The widget class is otherwise a local, unreachable from the specs. Publishing it on
    -- the module table (not on Readeck, which is a flat namespace of methods) lets a test
    -- build one instance against stubs and drive a single method.
    Browser.ArticleBrowserClass = ArticleBrowser

    ---------------------------------------------------------------- plugin entry point

    -- A single PATCH against one bookmark. Lives on the plugin rather than the widget so
    -- the catalog write-through has one call site to hook.
    function Readeck:patchBookmark(id, body)
        local payload = JSON.encode(body)
        local headers = {
            ["Content-type"] = "application/json",
            ["Accept"] = "application/json, */*",
            ["Content-Length"] = tostring(#payload),
            ["Authorization"] = "Bearer " .. (self.access_token or ""),
        }
        local ok = self:callAPI("PATCH", Api.paths.bookmark(id), headers, payload, "")
        if ok then
            self.catalog_dirty = true
        end
        return ok and true or false
    end

    function Readeck:prepareBrowseCatalog()
        Trapper:info(L("Loading article list…"))
        local catalog = self:getCatalog()
        if Catalog.count(catalog) > 0 then
            Trapper:clear()
            return catalog, nil
        end

        if NetworkMgr:isConnected() then
            local fetch = Trapper:confirm(
                L("There is no article list on this device yet. Fetch it from the server now?"),
                L("Not now"),
                L("Fetch")
            )
            if fetch and self:refreshCatalogFull() then
                Trapper:clear()
                return self:getCatalog(), nil
            end
        end

        -- Nothing from the server: recover whatever the downloaded files know. That is
        -- labels and lossy titles only, so the buckets it cannot answer are marked
        -- unavailable rather than shown empty.
        Trapper:info(L("Scanning downloaded articles…"))
        local fallback, available = self:buildFallbackCatalog()
        Trapper:clear()
        if Catalog.count(fallback) == 0 then
            UIManager:show(InfoMessage:new({
                text = L("Nothing to browse yet. Connect to the server to fetch the article list."),
            }))
            return nil
        end
        return fallback, available
    end

    function Readeck:showBrowser()
        if self:isempty(self.server_url) then
            UIManager:show(InfoMessage:new({ text = L("Please configure a Readeck server first.") }))
            return
        end
        Trapper:wrap(function()
            local catalog, available = self:prepareBrowseCatalog()
            if not catalog then
                return
            end
            Log:info("Opening browser with", Catalog.count(catalog), "articles")
            self.article_browser = ArticleBrowser:new({
                plugin = self,
                catalog = catalog,
                available = available,
                close_callback = function()
                    UIManager:close(self.article_browser)
                    self.article_browser = nil
                    -- The directory scan is only valid while the browser is open.
                    self.browse_downloaded_ids = nil
                    if self.catalog_dirty then
                        self:saveCatalog()
                        self.catalog_dirty = nil
                    end
                    self:refreshCurrentDirIfNeeded()
                end,
            })
            UIManager:show(self.article_browser)
        end)
    end
end

return Browser
