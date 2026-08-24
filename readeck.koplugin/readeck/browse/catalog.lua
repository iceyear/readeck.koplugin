-- Metadata-only index of the Readeck library.
--
-- The browser never queries the server to decide what a bucket contains: it filters this
-- catalog, online and offline alike, so both paths run identical code. Entries are kept
-- deliberately narrow (no article content) -- roughly 300 bytes each, so a 5000-article
-- library costs about 1.5 MB.
--
-- This module is pure: it manipulates plain tables and delegates persistence to a store
-- object that implements readSetting/saveSetting/flush (LuaSettings does, and so does the
-- fake used in the specs).
--
-- The one require is readeck.net.api, which is itself dependency-free: a collection stores
-- its label filter in Readeck's search syntax, so reading it back needs the same parser the
-- request encoder uses.

local Api = require("readeck.net.api")

local Catalog = {}

Catalog.VERSION = 1
Catalog.SETTING_KEY = "catalog"

local function string_or_nil(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "number" then
        return tostring(value)
    end
    return nil
end

local function string_list(value)
    local result = {}
    if type(value) ~= "table" then
        return result
    end
    for _, item in ipairs(value) do
        local text = string_or_nil(item)
        if text then
            table.insert(result, text)
        end
    end
    return result
end

local function boolean(value)
    -- Readeck sends real JSON booleans, but the plugin's own callers sometimes use the
    -- 0/1 form the query encoder accepts.
    if value == nil then
        return false
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if value == "true" then
        return true
    end
    if value == "false" then
        return false
    end
    return value and true or false
end

-- A filter flag that can also be "unconstrained".
--
-- Readeck types the nullable collection filters as pointers with no omitempty, so an unset
-- one arrives as JSON `null` -- which KOReader's decoder turns into a sentinel *function*,
-- not nil. `boolean()` cannot be reused here: it maps every truthy value, a function
-- included, to true, which would narrow every collection to archived-only.
--
-- Anything unrecognised becomes nil, and nil means the filter does not apply. That is the
-- safe direction: a value the plugin cannot read widens the collection instead of emptying
-- it, so a server change can cost accuracy but never the whole list.
local function tri_boolean(value)
    if type(value) == "boolean" then
        return value
    end
    if value == "true" or value == 1 then
        return true
    end
    if value == "false" or value == 0 then
        return false
    end
    return nil
end

-- Collections express their label filter as one search string ("mgmt secops", with
-- multi-word names quoted); the plugin's own callers pass a plain array. Accept both.
local function label_list(value)
    if type(value) == "string" then
        return Api.decode_label_terms(value)
    end
    return string_list(value)
end

local function number_or_nil(value)
    local result = tonumber(value)
    if result == nil then
        return nil
    end
    return result
end

function Catalog.empty()
    return {
        version = Catalog.VERSION,
        synced_at = nil,
        cursor = nil,
        etag = nil,
        server_url = nil,
        owner = nil,
        entries = {},
        collections = {},
    }
end

-- Maps one bookmark from GET /api/bookmarks (or /api/bookmarks/sync) onto a catalog
-- entry. The list endpoint returns the same dataset.Bookmark struct as the detail
-- endpoint, so every field the buckets need is already present -- no per-article fetch.
function Catalog.entry_from_bookmark(bookmark)
    if type(bookmark) ~= "table" then
        return nil
    end
    local id = string_or_nil(bookmark.id)
    if not id then
        return nil
    end
    return {
        id = id,
        title = string_or_nil(bookmark.title) or id,
        site = string_or_nil(bookmark.site),
        site_name = string_or_nil(bookmark.site_name),
        labels = string_list(bookmark.labels),
        authors = string_list(bookmark.authors),
        is_archived = boolean(bookmark.is_archived),
        is_marked = boolean(bookmark.is_marked),
        read_progress = number_or_nil(bookmark.read_progress) or 0,
        reading_time = number_or_nil(bookmark.reading_time),
        word_count = number_or_nil(bookmark.word_count),
        type = string_or_nil(bookmark.type) or "article",
        created = string_or_nil(bookmark.created),
        published = string_or_nil(bookmark.published),
        updated = string_or_nil(bookmark.updated),
        description = string_or_nil(bookmark.description),
    }
end

-- Kept so a collection can be re-evaluated locally when offline.
--
-- `source` is the raw collection from the API, where the filter keys sit at the top level,
-- or a `filters` table read back off disk. Coercing both through here is what lets a
-- catalog written by an older build repair itself on load.
local function collection_filters(source)
    source = source or {}
    return {
        labels = label_list(source.labels),
        site = string_or_nil(source.site),
        search = string_or_nil(source.search),
        title = string_or_nil(source.title),
        author = string_or_nil(source.author),
        type = string_list(source.type),
        read_status = string_list(source.read_status),
        is_archived = tri_boolean(source.is_archived),
        is_marked = tri_boolean(source.is_marked),
    }
end

local function collection_shape(id, name, filters)
    return {
        id = id,
        name = string_or_nil(name) or id,
        filters = filters,
    }
end

function Catalog.collection_from_json(collection)
    if type(collection) ~= "table" then
        return nil
    end
    local id = string_or_nil(collection.id)
    if not id then
        return nil
    end
    return collection_shape(id, collection.name, collection_filters(collection))
end

-- Repairs whatever came off disk into a usable catalog. A catalog written by another
-- plugin version, or belonging to a different server or account, is discarded rather
-- than half-trusted: a stale index is worse than an empty one, because the browser
-- would show articles that are not there.
--
-- Validating here rather than clearing at each mutation site is deliberate. It is one
-- check instead of five hooks to forget, and it also catches the case no hook can --
-- the user hand-editing readeck.lua, which the plugin's own settings help documents as
-- a supported workflow.
function Catalog.normalize(data, server_url, owner)
    if type(data) ~= "table" or type(data.entries) ~= "table" then
        return Catalog.empty()
    end
    if tonumber(data.version) ~= Catalog.VERSION then
        return Catalog.empty()
    end
    if server_url and data.server_url and data.server_url ~= server_url then
        return Catalog.empty()
    end
    -- Only a positive mismatch invalidates. The plugin cannot identify the account yet
    -- (there is no profile call, and OAuth re-authorization as a different user on the
    -- same server is currently undetectable), so a missing owner on either side has to
    -- mean "unknown", not "different".
    if owner and data.owner and data.owner ~= owner then
        return Catalog.empty()
    end

    local catalog = Catalog.empty()
    catalog.synced_at = string_or_nil(data.synced_at)
    catalog.cursor = string_or_nil(data.cursor)
    catalog.etag = string_or_nil(data.etag)
    catalog.server_url = string_or_nil(data.server_url) or server_url
    catalog.owner = string_or_nil(data.owner) or owner
    for id, entry in pairs(data.entries) do
        if type(entry) == "table" and type(id) == "string" then
            entry.id = entry.id or id
            entry.labels = type(entry.labels) == "table" and entry.labels or {}
            entry.authors = type(entry.authors) == "table" and entry.authors or {}
            entry.read_progress = tonumber(entry.read_progress) or 0
            entry.is_archived = boolean(entry.is_archived)
            entry.is_marked = boolean(entry.is_marked)
            catalog.entries[id] = entry
        end
    end
    -- Rebuilt rather than trusted, for the same reason the entries above are. A catalog
    -- written before the filter flags were coerced holds the decoder's null sentinel, and
    -- the collection would match nothing until the next refresh replaced it; running it
    -- back through the same builder repairs it on load, offline included.
    if type(data.collections) == "table" then
        for _, collection in ipairs(data.collections) do
            local id = type(collection) == "table" and string_or_nil(collection.id)
            if id then
                table.insert(
                    catalog.collections,
                    collection_shape(id, collection.name, collection_filters(collection.filters))
                )
            end
        end
    end
    return catalog
end

function Catalog.load(store, server_url, owner)
    if type(store) ~= "table" then
        return Catalog.empty()
    end
    local ok, data = pcall(store.readSetting, store, Catalog.SETTING_KEY)
    if not ok then
        return Catalog.empty()
    end
    return Catalog.normalize(data, server_url, owner)
end

-- Clearing must not go through LuaSettings:purge(): purge removes only the main file,
-- while open() silently falls back to "<file>.old" on any read failure -- so a purged
-- catalog comes straight back on the next open, belonging to the previous account.
-- Writing an empty table and deleting the backup ourselves is the only safe form.
function Catalog.clear(store, path, remove_file)
    if type(store) ~= "table" then
        return false
    end
    local ok = pcall(function()
        store:saveSetting(Catalog.SETTING_KEY, nil)
        store:flush()
    end)
    if path and remove_file then
        pcall(remove_file, path .. ".old")
    end
    return ok
end

function Catalog.save(store, catalog, synced_at)
    if type(store) ~= "table" or type(catalog) ~= "table" then
        return false
    end
    if synced_at then
        catalog.synced_at = synced_at
    end
    catalog.version = Catalog.VERSION
    local ok = pcall(function()
        store:saveSetting(Catalog.SETTING_KEY, catalog)
        store:flush()
    end)
    return ok
end

function Catalog.get(catalog, id)
    if type(catalog) ~= "table" or type(catalog.entries) ~= "table" or id == nil then
        return nil
    end
    return catalog.entries[tostring(id)]
end

function Catalog.upsert(catalog, entry)
    if type(catalog) ~= "table" or type(entry) ~= "table" or not entry.id then
        return nil
    end
    catalog.entries[tostring(entry.id)] = entry
    return entry
end

function Catalog.remove(catalog, id)
    if type(catalog) ~= "table" or id == nil then
        return false
    end
    id = tostring(id)
    if catalog.entries[id] == nil then
        return false
    end
    catalog.entries[id] = nil
    return true
end

-- Applies a partial update in place, e.g. after the user archives an article from the
-- browser. Returns the updated entry, or nil when the article is not in the catalog.
function Catalog.patch(catalog, id, changes)
    local entry = Catalog.get(catalog, id)
    if not entry or type(changes) ~= "table" then
        return nil
    end
    for key, value in pairs(changes) do
        entry[key] = value
    end
    return entry
end

function Catalog.set_collections(catalog, collections)
    if type(catalog) ~= "table" then
        return
    end
    catalog.collections = {}
    if type(collections) ~= "table" then
        return
    end
    for _, raw in ipairs(collections) do
        local collection = Catalog.collection_from_json(raw)
        if collection then
            table.insert(catalog.collections, collection)
        end
    end
end

-- All entries as an array. `entries` is a hash keyed by id, and pairs() order is not
-- stable across runs, so sort by id to give callers a deterministic base ordering; the
-- real sort happens in Facets.
function Catalog.all(catalog)
    local result = {}
    if type(catalog) ~= "table" or type(catalog.entries) ~= "table" then
        return result
    end
    for _, entry in pairs(catalog.entries) do
        table.insert(result, entry)
    end
    table.sort(result, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return result
end

function Catalog.count(catalog)
    local total = 0
    if type(catalog) == "table" and type(catalog.entries) == "table" then
        for _ in pairs(catalog.entries) do
            total = total + 1
        end
    end
    return total
end

function Catalog.stats(catalog)
    local stats = {
        total = 0,
        unread = 0,
        archived = 0,
        favorite = 0,
        labels = 0,
        sources = 0,
        collections = 0,
        synced_at = nil,
    }
    if type(catalog) ~= "table" then
        return stats
    end
    stats.synced_at = catalog.synced_at
    stats.collections = #(catalog.collections or {})

    local labels, sources = {}, {}
    for _, entry in pairs(catalog.entries or {}) do
        stats.total = stats.total + 1
        if entry.is_archived then
            stats.archived = stats.archived + 1
        elseif (entry.read_progress or 0) == 0 then
            stats.unread = stats.unread + 1
        end
        if entry.is_marked then
            stats.favorite = stats.favorite + 1
        end
        for _, label in ipairs(entry.labels or {}) do
            labels[label] = true
        end
        local source = entry.site_name or entry.site
        if source then
            sources[source] = true
        end
    end
    for _ in pairs(labels) do
        stats.labels = stats.labels + 1
    end
    for _ in pairs(sources) do
        stats.sources = stats.sources + 1
    end
    return stats
end

return Catalog
