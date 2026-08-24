-- Filtering and facet counting over a catalog.
--
-- Every bucket, label drill-down and source list in the browser is computed here, from
-- catalog entries only. Nothing in this module touches the network or the filesystem, so
-- the online and offline browsers run byte-identical logic -- the only difference is
-- whether the catalog was refreshed beforehand.

local Facets = {}

-- Overridden at install time with ffi/util.strcoll so ties sort the way the user's locale
-- expects. Plain byte order is the fallback, which is what the specs use.
local collate = function(a, b)
    return a < b
end

function Facets.set_collator(fn)
    if type(fn) == "function" then
        collate = fn
    end
end

Facets.BUCKETS = { "all", "unread", "archived", "favorite", "collections", "labels", "sources" }

local function lower(value)
    return tostring(value or ""):lower()
end

function Facets.source_of(entry)
    local name = entry.site_name
    if name == nil or name == "" then
        name = entry.site
    end
    if name == nil or name == "" then
        return nil
    end
    return name
end

-- The catalog is server truth; the KOReader sidecar is device truth. They diverge by
-- design: `sync_reading_progress` defaults to false, and even when it is on, the push
-- refuses local progress >= 100 and the pull refuses remote progress of 0 or >= 100
-- (readeck.sync.progress). So an article read cover to cover on the device still has
-- read_progress = 0 in the catalog, and one finished on the web still has no local
-- percentage. Merging both here is what keeps the Unread bucket honest.
--
-- opts.local_progress(id) -> 0..100 or nil, opts.local_status(id) -> "complete" / ... .
-- Both are injected so this module stays free of KOReader.
function Facets.effective_progress(entry, opts)
    local server = tonumber(entry.read_progress) or 0
    local device = 0
    if opts and opts.local_progress then
        -- Bound to one value before tonumber: a lookup that returns nothing at all is a
        -- perfectly ordinary "no local progress", but tonumber() with no argument raises.
        local reported = opts.local_progress(entry.id)
        device = tonumber(reported) or 0
    end
    if device > server then
        return device
    end
    return server
end

-- "Complete" at 87% is a normal, common local state that no percentage captures, so the
-- status has to be consulted separately from the progress.
function Facets.locally_finished(entry, opts)
    if not (opts and opts.local_status) then
        return false
    end
    local status = opts.local_status(entry.id)
    return status == "complete" or status == "abandoned"
end

function Facets.read_status_of(entry, opts)
    if Facets.locally_finished(entry, opts) then
        return "read"
    end
    local progress = Facets.effective_progress(entry, opts)
    if progress <= 0 then
        return "unread"
    end
    if progress >= 100 then
        return "read"
    end
    return "reading"
end

function Facets.has_label(entry, label)
    for _, name in ipairs(entry.labels or {}) do
        if name == label then
            return true
        end
    end
    return false
end

local function matches_bucket(entry, bucket, opts)
    if bucket == nil or bucket == "labels" or bucket == "sources" or bucket == "collections" then
        -- Facet buckets do not constrain the set by themselves; the label/site/collection
        -- fields on the filter do that once the user has drilled in.
        return true
    end
    if bucket == "all" then
        return not entry.is_archived
    end
    if bucket == "unread" then
        if entry.is_archived or Facets.locally_finished(entry, opts) then
            return false
        end
        return Facets.effective_progress(entry, opts) == 0
    end
    if bucket == "archived" then
        return entry.is_archived == true
    end
    if bucket == "favorite" then
        return entry.is_marked == true
    end
    return true
end

local function contains_any(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

function Facets.matches_search(entry, query)
    query = lower(query)
    if query == "" then
        return true
    end
    -- Local search is metadata-only: the device has no article text. The UI says so.
    if lower(entry.title):find(query, 1, true) then
        return true
    end
    if lower(entry.description):find(query, 1, true) then
        return true
    end
    if lower(entry.site_name):find(query, 1, true) or lower(entry.site):find(query, 1, true) then
        return true
    end
    for _, author in ipairs(entry.authors or {}) do
        if lower(author):find(query, 1, true) then
            return true
        end
    end
    for _, label in ipairs(entry.labels or {}) do
        if lower(label):find(query, 1, true) then
            return true
        end
    end
    return false
end

function Facets.matches(entry, filter, opts)
    if type(entry) ~= "table" then
        return false
    end
    filter = filter or {}

    if not matches_bucket(entry, filter.bucket, opts) then
        return false
    end
    -- Selected labels are AND-combined, matching how Readeck reads its `labels` param.
    for _, label in ipairs(filter.labels or {}) do
        if not Facets.has_label(entry, label) then
            return false
        end
    end
    if filter.site and Facets.source_of(entry) ~= filter.site then
        return false
    end
    if filter.type and #(filter.type or {}) > 0 and not contains_any(filter.type, entry.type) then
        return false
    end
    if filter.read_status and #(filter.read_status or {}) > 0 then
        if not contains_any(filter.read_status, Facets.read_status_of(entry, opts)) then
            return false
        end
    end
    -- Tested for boolean-ness rather than for non-nil. These two are tri-state -- true,
    -- false, or "do not care" -- and the catalog is not the only producer of filter tables;
    -- `~= nil` let a stored JSON null (a sentinel *function* after decoding) pass the guard
    -- and then compare unequal to every entry, which emptied every collection.
    if type(filter.is_archived) == "boolean" and entry.is_archived ~= filter.is_archived then
        return false
    end
    if type(filter.is_marked) == "boolean" and entry.is_marked ~= filter.is_marked then
        return false
    end
    if filter.author and not Facets.matches_search({ authors = entry.authors }, filter.author) then
        return false
    end
    if filter.title and not lower(entry.title):find(lower(filter.title), 1, true) then
        return false
    end
    if filter.search and not Facets.matches_search(entry, filter.search) then
        return false
    end
    return true
end

local SORT_KEYS = {
    created = function(e)
        return e.created or ""
    end,
    published = function(e)
        return e.published or e.created or ""
    end,
    updated = function(e)
        return e.updated or e.created or ""
    end,
    title = function(e)
        return lower(e.title)
    end,
    site = function(e)
        return lower(Facets.source_of(e))
    end,
    duration = function(e)
        return tonumber(e.reading_time) or 0
    end,
    -- Server progress, not the merged value: sort_entries takes no opts so that it stays
    -- a pure comparator. The browser sorts rows it has already stamped.
    progress = function(e)
        return tonumber(e.read_progress) or 0
    end,
}

-- Accepts Readeck's own sort syntax: an optional leading "-" for descending.
function Facets.sort_entries(entries, sort)
    sort = sort or "-created"
    local descending = sort:sub(1, 1) == "-"
    local key = descending and sort:sub(2) or sort
    local key_of = SORT_KEYS[key] or SORT_KEYS.created

    table.sort(entries, function(a, b)
        local ka, kb = key_of(a), key_of(b)
        if ka ~= kb then
            if type(ka) == "number" then
                if descending then
                    return ka > kb
                end
                return ka < kb
            end
            if descending then
                return collate(kb, ka)
            end
            return collate(ka, kb)
        end
        -- Stable tiebreak so paging and row refreshes never reshuffle the list.
        return tostring(a.id) < tostring(b.id)
    end)
    return entries
end

function Facets.filter(entries, filter, sort, opts)
    local result = {}
    for _, entry in ipairs(entries or {}) do
        if Facets.matches(entry, filter, opts) then
            table.insert(result, entry)
        end
    end
    if sort ~= false then
        Facets.sort_entries(result, sort or (filter or {}).sort)
    end
    return result
end

-- Counts distinct values produced by key_fn (which may return a string or a list of
-- strings), sorted by count descending with a locale-aware name tiebreak.
function Facets.tally(entries, key_fn)
    local counts, names = {}, {}
    for _, entry in ipairs(entries or {}) do
        local keys = key_fn(entry)
        if type(keys) ~= "table" then
            keys = keys ~= nil and { keys } or {}
        end
        for _, key in ipairs(keys) do
            if key ~= nil and key ~= "" then
                if counts[key] == nil then
                    counts[key] = 0
                    table.insert(names, key)
                end
                counts[key] = counts[key] + 1
            end
        end
    end

    local result = {}
    for _, name in ipairs(names) do
        table.insert(result, { name = name, count = counts[name] })
    end
    return Facets.sort_by_count(result)
end

function Facets.sort_by_count(facets)
    table.sort(facets, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return collate(a.name, b.name)
    end)
    return facets
end

-- The label drill-down. `selected` are the labels already chosen; the returned candidates
-- exclude them, and every count is computed over the entries that survive the base filter
-- AND all selected labels -- never over the whole catalog. That recomputation is the
-- whole point: it is what keeps the list narrowing to only what still matches.
function Facets.candidate_labels(entries, base_filter, selected, opts)
    selected = selected or {}
    local selected_set = {}
    for _, name in ipairs(selected) do
        selected_set[name] = true
    end

    local matching = {}
    for _, entry in ipairs(entries or {}) do
        if Facets.matches(entry, base_filter, opts) then
            local keeps = true
            for _, name in ipairs(selected) do
                if not Facets.has_label(entry, name) then
                    keeps = false
                    break
                end
            end
            if keeps then
                table.insert(matching, entry)
            end
        end
    end

    local candidates = Facets.tally(matching, function(entry)
        local remaining = {}
        for _, name in ipairs(entry.labels or {}) do
            if not selected_set[name] then
                table.insert(remaining, name)
            end
        end
        return remaining
    end)

    return candidates, #matching
end

function Facets.sources(entries, filter, opts)
    return Facets.tally(Facets.filter(entries, filter, false, opts), Facets.source_of)
end

function Facets.labels(entries, filter, opts)
    return Facets.tally(Facets.filter(entries, filter, false, opts), function(entry)
        return entry.labels or {}
    end)
end

function Facets.count(entries, filter, opts)
    local total = 0
    for _, entry in ipairs(entries or {}) do
        if Facets.matches(entry, filter, opts) then
            total = total + 1
        end
    end
    return total
end

-- Turns a stored collection into a filter this module understands. `search` is dropped
-- because it is server-side full-text over article content the device does not have; the
-- second return value tells the UI to say so.
function Facets.collection_filter(collection)
    local stored = (collection or {}).filters or {}
    local filter = {
        labels = stored.labels,
        site = stored.site,
        title = stored.title,
        author = stored.author,
        type = stored.type,
        read_status = stored.read_status,
        is_archived = stored.is_archived,
        is_marked = stored.is_marked,
    }
    local approximate = stored.search ~= nil and stored.search ~= ""
    return filter, approximate
end

return Facets
